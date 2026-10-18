import AppKit
import IslandCore
import ServiceManagement
import SwiftUI

/// Settings shown inside the expanded island. They save as they change, like System Settings:
/// toggles, pickers and the slider right away, text fields when you press Return or leave them.
/// Leaving the island commits anything pending, so collapsing never loses an edit.
struct SettingsView: View {
  @Bindable var store: IslandStore
  @Binding var contentHeight: CGFloat
  @State private var draft: AppSettings
  /// Text fields edit these and commit to `draft` on Return or when they lose focus, so a
  /// half-typed value (an `owner/` with no repository yet) is never applied.
  @State private var repositoriesText: String
  @State private var codexHomeText: String
  @State private var claudeHomeText: String
  @FocusState private var focusedField: TextSetting?
  @State private var pendingApply: Task<Void, Never>?
  @State private var loginItemError: String?
  @State private var startAtLogin = SMAppService.mainApp.status == .enabled
  @State private var cardsHeight: CGFloat = 0
  @State private var footerHeight: CGFloat = 0

  private enum TextSetting { case repositories, codexHome, claudeHome }

  init(store: IslandStore, contentHeight: Binding<CGFloat>) {
    self.store = store
    _contentHeight = contentHeight
    _draft = State(initialValue: store.settings)
    _repositoriesText = State(initialValue: store.settings.repositories)
    _codexHomeText = State(initialValue: store.settings.codexHome)
    _claudeHomeText = State(initialValue: store.settings.claudeHome)
  }

  /// The draft with the preferences that apply outside this page (system permission and
  /// chart choices) taken from the live settings, so saving never reverts them.
  private var merged: AppSettings {
    var result = draft
    result.notificationsEnabled = store.settings.notificationsEnabled
    result.githubChart = store.settings.githubChart
    result.usageChart = store.settings.usageChart
    result.usageMetric = store.settings.usageMetric
    return result
  }

  private var changed: Bool { merged != store.settings }

  private func commitText() {
    draft.repositories = repositoriesText
    draft.codexHome = codexHomeText
    draft.claudeHome = claudeHomeText
  }

  /// Saves shortly after the last change, so dragging the slider doesn't write on every step.
  private func scheduleApply() {
    pendingApply?.cancel()
    pendingApply = Task {
      try? await Task.sleep(for: .milliseconds(250))
      guard !Task.isCancelled else { return }
      applyNow()
    }
  }

  private func applyNow() {
    pendingApply?.cancel()
    if changed { store.applySettings(merged) }
  }

  var body: some View {
    // The cards scroll; the status row stays pinned below them.
    VStack(spacing: 0) {
      MeasuredColumn {
        VStack(spacing: 12) {
          // Rows of equal-height cards, so no column leaves an empty block.
          HStack(alignment: .top, spacing: 12) {
            github
            notifications
          }
          .fixedSize(horizontal: false, vertical: true)
          HStack(alignment: .top, spacing: 12) {
            island
            usage
          }
          .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 6)
      } onHeight: {
        cardsHeight = $0
        contentHeight = $0 + footerHeight
      }
      HStack(spacing: 12) {
        if let error = store.persistenceError ?? loginItemError {
          Text(error).font(.system(size: 11)).foregroundStyle(Palette.failed).lineLimit(2)
        } else {
          Text("Changes save automatically. GitIsle reads GitHub through your gh login.")
            .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.35))
        }
        Spacer()
        Button("Run setup again") {
          commitText()
          applyNow()
          withAnimation(Motion.snappy) { store.startOnboarding() }
        }
        .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
      }
      .padding(.horizontal, 20).padding(.vertical, 10)
      .onGeometryChange(for: CGFloat.self) {
        $0.size.height
      } action: {
        footerHeight = $0
        contentHeight = cardsHeight + $0
      }
    }
    .onChange(of: draft) { scheduleApply() }
    .onChange(of: focusedField) { commitText() }
    .onDisappear {
      commitText()
      applyNow()
    }
  }

  private var github: some View {
    SettingsCard(glyph: .github, title: "GitHub") {
      SettingsRow("Account") {
        if let login = store.github?.login, store.githubError == nil {
          AccountChip(login: login)
        } else {
          Link(
            "Sign in with gh",
            destination: URL(string: "https://cli.github.com/manual/gh_auth_login")!
          )
          .font(.system(size: 12))
        }
      }
      SettingsRow("Also watch") {
        TextField("owner/repo, owner/another-repo", text: $repositoriesText)
          .islandField()
          .focused($focusedField, equals: .repositories)
          .onSubmit(commitText)
      }
      SettingsRow("Active PRs") {
        PillPicker(
          options: [(5.0, "5s"), (10.0, "10s"), (20.0, "20s"), (30.0, "30s")],
          selection: $draft.activeRefreshSeconds, fontSize: 11)
      }
      SettingsRow("New PRs") {
        PillPicker(
          options: [(30.0, "30s"), (60.0, "1m"), (120.0, "2m"), (300.0, "5m")],
          selection: $draft.githubRefreshSeconds, fontSize: 11)
      }
      Text(
        "Active PRs (checks running, merging, or just updated) refresh most often. About \(budgetShare)% of your hourly GitHub API budget, which other gh tools share."
      )
      .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.4))
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  /// Rough share of GitHub's 5,000 points an hour while a PR is active: an active refresh and
  /// a check for new PRs cost 1 point each, and the full searches every 10 minutes and the
  /// stats add about 30.
  private var budgetShare: Int {
    let points = 3600 / draft.activeRefreshSeconds + 3600 / draft.githubRefreshSeconds + 30
    return max(1, Int((points / 5000 * 100).rounded()))
  }

  private var notifications: some View {
    SettingsCard(glyph: .eye, title: "Notifications") {
      SettingsRow("Island banner") {
        Toggle("", isOn: $draft.bannersEnabled).islandToggle()
      }
      SettingsRow("System notifications") {
        Toggle(
          "",
          isOn: Binding(
            get: { store.settings.notificationsEnabled },
            set: { enabled in
              if enabled {
                Task { await store.requestNotifications() }
              } else {
                store.update { $0.notificationsEnabled = false }
              }
            })
        )
        .islandToggle()
      }
      SettingsRow("Sound") {
        Toggle("", isOn: $draft.notificationSound).islandToggle()
      }
      .disabled(!store.settings.notificationsEnabled)
      .opacity(store.settings.notificationsEnabled ? 1 : 0.45)
      VStack(alignment: .leading, spacing: 7) {
        Text("Announce").font(.system(size: 12)).foregroundStyle(.white.opacity(0.75))
        LazyVGrid(
          columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)],
          spacing: 6
        ) {
          ForEach(Self.announcements, id: \.label) { item in
            let kinds = Set(item.kinds.map(\.rawValue))
            AnnouncementChip(
              glyph: item.glyph, label: item.label, color: item.kinds[0].color,
              selected: kinds.isSubset(of: draft.announcedKinds)
            ) {
              if kinds.isSubset(of: draft.announcedKinds) {
                draft.announcedKinds.subtract(kinds)
              } else {
                draft.announcedKinds.formUnion(kinds)
              }
            }
          }
        }
      }
    }
  }

  /// Your own PRs as they head to merge, then what can go wrong or wait on you.
  /// One chip can cover several kinds: "New PR" is opening a PR, ready or draft, and marking a
  /// draft ready for review; "Failed" is checks failing on the PR or in the merge queue.
  private static let announcements: [(kinds: [PRStatus], glyph: Glyph, label: String)] = [
    ([.opened, .draft, .readyForReview], .pullRequest, "New PR"),
    ([.ready], .checkFill, "Ready"), ([.previewReady], .linkExternal, "Preview"),
    ([.queued], .mergeQueue, "Merging"),
    ([.merged], .merge, "Merged"), ([.failed, .mergeFailed], .failFill, "Failed"),
    ([.review], .eye, "Review"),
  ]

  private var island: some View {
    SettingsCard(glyph: .pullRequest, title: "Island") {
      SettingsRow("Display") {
        Picker("", selection: $draft.displayID) {
          Text("Automatic").tag(nil as UInt32?)
          ForEach(NSScreen.screens, id: \.self) { screen in
            if let id =
              (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
              .uint32Value
            {
              Text(screen.localizedName).tag(id as UInt32?)
            }
          }
        }
        .labelsHidden().pickerStyle(.menu).frame(maxWidth: 150)
      }
      SettingsRow("Hover delay") {
        HStack(spacing: 8) {
          Slider(value: $draft.hoverDelay, in: 0.05...0.9, step: 0.05).controlSize(.small)
            .frame(minWidth: 60, maxWidth: 130)
          Text("\(Int(draft.hoverDelay * 1000)) ms").monospacedDigit()
            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
            .frame(width: 50, alignment: .trailing)
        }
      }
      SettingsRow("Show in full screen") {
        Toggle("", isOn: $draft.showInFullscreen).islandToggle()
      }
      SettingsRow("Start at login") {
        Toggle("", isOn: $startAtLogin).islandToggle()
          .onChange(of: startAtLogin) { _, enabled in
            do {
              if enabled {
                try SMAppService.mainApp.register()
              } else {
                try SMAppService.mainApp.unregister()
              }
              loginItemError = nil
            } catch { loginItemError = error.localizedDescription }
          }
      }
    }
  }

  private var usage: some View {
    SettingsCard(glyph: .claude, title: "Usage statistics") {
      SettingsRow("Codex home") {
        TextField("~/.codex", text: $codexHomeText).islandField()
          .focused($focusedField, equals: .codexHome)
          .onSubmit(commitText)
      }
      SettingsRow("Claude Code home") {
        TextField("~/.claude", text: $claudeHomeText).islandField()
          .focused($focusedField, equals: .claudeHome)
          .onSubmit(commitText)
      }
      SettingsRow("Currency") {
        PillPicker(
          options: [(CostCurrency.usd, "$ USD"), (.eur, "€ EUR")], selection: $draft.currency,
          fontSize: 11)
      }
      if draft.currency == .eur {
        SettingsRow("Rate") {
          HStack(spacing: 6) {
            Text("1 USD =").foregroundStyle(.white.opacity(0.5))
            TextField(
              "0.86", value: $draft.usdToEur, format: .number.precision(.fractionLength(0...4))
            )
            .islandField().frame(width: 70)
            Text("EUR").foregroundStyle(.white.opacity(0.5))
          }
          .font(.system(size: 12))
        }
        .transition(.opacity)
      }
    }
    .animation(Motion.snappy, value: draft.currency)
  }
}

/// The signed-in GitHub account: avatar, handle, and a connected check. Opens the profile.
struct AccountChip: View {
  let login: String
  @State private var hovered = false

  private var avatar: URL? {
    var parts = URLComponents(string: "https://avatars.githubusercontent.com")
    parts?.path = "/\(login)"
    parts?.queryItems = [URLQueryItem(name: "s", value: "64")]
    return parts?.url
  }

  var body: some View {
    Link(
      destination: URL(string: "https://github.com/\(login)") ?? URL(string: "https://github.com")!
    ) {
      HStack(spacing: 7) {
        RepoAvatar(url: avatar, size: 20, circular: true, placeholder: .github)
        Text(verbatim: "@\(login)").font(.system(size: 12, weight: .semibold))
          .foregroundStyle(.white)
        Image(systemName: "checkmark.seal.fill")
          .font(.system(size: 11)).foregroundStyle(Palette.open)
      }
      .padding(.leading, 3).padding(.trailing, 10).padding(.vertical, 3)
      .background(Capsule().fill(.white.opacity(hovered ? 0.1 : 0.06)))
      .overlay(Capsule().inset(by: 0.5).stroke(.white.opacity(0.08), lineWidth: 1))
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .onHover { inside in withAnimation(.easeOut(duration: 0.12)) { hovered = inside } }
    .help("Signed in with the GitHub CLI. Opens your profile.")
    .accessibilityLabel("Signed in to GitHub as \(login)")
  }
}

/// A toggle chip for one kind of announcement.
private struct AnnouncementChip: View {
  let glyph: Glyph
  let label: String
  let color: Color
  let selected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 5) {
        GlyphView(glyph: glyph, size: 10)
        Text(label).lineLimit(1).fixedSize()
      }
      .font(.system(size: 11, weight: .semibold))
      .foregroundStyle(selected ? color : .white.opacity(0.4))
      .padding(.vertical, 5)
      // Stretch after padding so the capsule fills the grid cell without overflowing it.
      .frame(maxWidth: .infinity)
      .background(Capsule().fill(selected ? color.opacity(0.16) : .white.opacity(0.05)))
      .overlay(Capsule().inset(by: 0.5).stroke(color.opacity(selected ? 0.6 : 0), lineWidth: 1))
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(label)
    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
  }
}

struct SettingsCard<Content: View>: View {
  let glyph: Glyph
  let title: String
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 8) {
        GlyphView(glyph: glyph, size: 13).foregroundStyle(.white.opacity(0.6))
        Text(title).font(.system(size: 12.5, weight: .semibold))
      }
      content
    }
    .padding(14)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.surface))
  }
}

struct SettingsRow<Control: View>: View {
  let label: String
  @ViewBuilder let control: Control

  init(_ label: String, @ViewBuilder control: () -> Control) {
    self.label = label
    self.control = control()
  }

  var body: some View {
    HStack(spacing: 12) {
      // Labels keep their full width; controls give way when the card is narrow.
      Text(label).font(.system(size: 12)).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
        .fixedSize()
      Spacer(minLength: 8)
      control.layoutPriority(-1)
    }
  }
}

extension View {
  func islandField() -> some View {
    textFieldStyle(.plain)
      .font(.system(size: 12))
      .padding(.horizontal, 9).padding(.vertical, 6)
      .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.white.opacity(0.07)))
      .frame(minWidth: 80, maxWidth: 240)
  }

  func islandToggle() -> some View {
    toggleStyle(.switch).controlSize(.mini).labelsHidden()
  }
}

extension Notification.Name {
  static let islandSettingsChanged = Notification.Name("dev.ppazosp.gitisle.settingsChanged")
  static let islandOpenSettings = Notification.Name("dev.ppazosp.gitisle.openSettings")
}
