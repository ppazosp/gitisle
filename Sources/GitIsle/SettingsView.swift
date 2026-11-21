import AppKit
import IslandCore
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
  @FocusState private var repositoriesFocused: Bool
  @State private var pendingApply: Task<Void, Never>?
  @State private var cardsHeight: CGFloat = 0
  @State private var footerHeight: CGFloat = 0

  init(store: IslandStore, contentHeight: Binding<CGFloat>) {
    self.store = store
    _contentHeight = contentHeight
    _draft = State(initialValue: store.settings)
    _repositoriesText = State(initialValue: store.settings.repositories)
  }

  /// Read the notification preference from the store so saving a draft never reverts it.
  private var merged: AppSettings {
    var result = draft
    result.notificationsEnabled = store.settings.notificationsEnabled
    return result
  }

  private var changed: Bool { merged != store.settings }

  private func commitText() {
    draft.repositories = repositoriesText
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
        VStack(spacing: 10) {
          HStack(alignment: .top, spacing: 10) {
            github
            island
          }
          .fixedSize(horizontal: false, vertical: true)
          notifications
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 6)
      } onHeight: {
        cardsHeight = $0
        contentHeight = $0 + footerHeight
      }
      HStack(spacing: 12) {
        if let error = store.persistenceError ?? store.loginItemError {
          Text(error).font(.system(size: 11)).foregroundStyle(Palette.failed).lineLimit(2)
        } else {
          Text("Changes save automatically.")
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
    .onChange(of: repositoriesFocused) { commitText() }
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
          .focused($repositoriesFocused)
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
        "While a PR is active, GitIsle uses about \(budgetShare)% of your shared hourly GitHub API budget."
      )
      .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.4))
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  /// Rough share of GitHub's 5,000 points an hour while a PR is active: an active refresh and
  /// a check for new PRs cost 1 point each, and full searches every 10 minutes add about 24.
  private var budgetShare: Int {
    let points = 3600 / draft.activeRefreshSeconds + 3600 / draft.githubRefreshSeconds + 24
    return max(1, Int((points / 5000 * 100).rounded()))
  }

  private var notifications: some View {
    SettingsCard(glyph: .eye, title: "Notifications") {
      HStack(alignment: .top, spacing: 24) {
        notificationToggles
        notificationAnnouncements
      }
      if store.notificationsBlocked { NotificationsBlockedNote() }
    }
  }

  private var notificationToggles: some View {
    VStack(alignment: .leading, spacing: 5) {
      notificationHeading("Delivery")
      VStack(spacing: 2) {
        SettingsRow("Island banner") {
          Toggle("", isOn: $draft.bannersEnabled).islandToggle()
        }
        .frame(height: NotificationEventRow.height)
        SettingsRow("Banner timer") {
          Toggle("", isOn: $draft.bannerTimer).islandToggle()
        }
        .frame(height: NotificationEventRow.height)
        .disabled(!store.settings.bannersEnabled)
        .opacity(store.settings.bannersEnabled ? 1 : 0.45)
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
        .frame(height: NotificationEventRow.height)
        SettingsRow("Sound") {
          Toggle("", isOn: $draft.notificationSound).islandToggle()
        }
        .frame(height: NotificationEventRow.height)
        .disabled(!store.settings.notificationsEnabled)
        .opacity(store.settings.notificationsEnabled ? 1 : 0.45)
      }
    }
    .frame(width: 222)
    .accessibilityElement(children: .contain)
  }

  private var notificationAnnouncements: some View {
    VStack(alignment: .leading, spacing: 5) {
      notificationHeading("PR events")
      HStack(alignment: .top, spacing: 16) {
        announcementColumn(Self.announcements.prefix(4))
        announcementColumn(Self.announcements.dropFirst(4))
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .contain)
  }

  private func notificationHeading(_ title: String) -> some View {
    HStack(spacing: 8) {
      Text(title)
        .font(.system(size: 11.5, weight: .medium))
        .foregroundStyle(.white.opacity(0.62))
        .accessibilityAddTraits(.isHeader)
      Rectangle().fill(Palette.hairline).frame(height: 1)
        .accessibilityHidden(true)
    }
    .frame(height: 16)
  }

  private func announcementColumn(_ announcements: ArraySlice<Announcement>) -> some View {
    VStack(spacing: 2) {
      ForEach(announcements, id: \.label) { item in
        let kinds = Set(item.kinds.map(\.rawValue))
        NotificationEventRow(
          label: item.label, glyph: item.glyph, color: item.kinds[0].color,
          isOn: Binding(
            get: { kinds.isSubset(of: draft.announcedKinds) },
            set: { enabled in
              if enabled {
                draft.announcedKinds.formUnion(kinds)
              } else {
                draft.announcedKinds.subtract(kinds)
              }
            })
        )
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private typealias Announcement = (kinds: [PRStatus], glyph: Glyph, label: String)

  /// Your own PRs as they head to merge, then what can go wrong or wait on you.
  /// One checkbox can cover several kinds: "New PR" is opening a PR, ready or draft, and marking a
  /// draft ready for review; "Failed" is checks failing on the PR or in the merge queue.
  private static let announcements: [Announcement] = [
    ([.opened, .draft, .readyForReview], .pullRequest, "New PR"),
    ([.ready], .checkFill, "Ready"), ([.previewReady], .globe, "Preview"),
    ([.queued], .mergeQueue, "Merging"), ([.merged], .merge, "Merged"),
    ([.failed, .mergeFailed], .failFill, "Failed"), ([.review], .eye, "Review"),
  ]

  private var island: some View {
    SettingsCard(glyph: .pullRequest, title: "Island") {
      SettingsRow("Display") {
        DisplayPicker(displayID: $draft.displayID)
      }
      SettingsRow("Open after") {
        DelaySlider(value: $draft.hoverDelay)
      }
      SettingsRow("Close after") {
        DelaySlider(value: $draft.closeDelay)
      }
      SettingsRow("Show in full screen") {
        Toggle("", isOn: $draft.showInFullscreen).islandToggle()
      }
      SettingsRow("Start at login") {
        Toggle(
          "",
          isOn: Binding(get: { store.startsAtLogin }, set: { store.setStartsAtLogin($0) })
        )
        .islandToggle()
      }
    }
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

private struct NotificationEventRow: View {
  static let height: CGFloat = 23

  let label: String
  let glyph: Glyph
  let color: Color
  @Binding var isOn: Bool
  @State private var hovered = false

  private var checkbox: some View {
    // Like the switches, keep the accent in the island's non-activating panel.
    let shape = RoundedRectangle(cornerRadius: 3)
    return
      shape
      .fill(isOn ? Color(nsColor: .systemBlue) : .white.opacity(0.035))
      .overlay(shape.strokeBorder(.white.opacity(isOn ? 0 : 0.21), lineWidth: 1))
      .overlay {
        if isOn {
          Image(systemName: "checkmark")
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(.white)
        }
      }
      .frame(width: 13, height: 13)
  }

  var body: some View {
    Button {
      isOn.toggle()
    } label: {
      HStack(spacing: 8) {
        GlyphView(glyph: glyph, size: 12)
          .foregroundStyle(color.opacity(isOn ? 1 : 0.65))
          .frame(width: 15, height: 14)
        Text(label)
          .font(.system(size: 12))
          .foregroundStyle(.white.opacity(0.75))
        Spacer(minLength: 8)
        checkbox
      }
      .padding(.horizontal, 8)
      .frame(height: Self.height)
      .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(hovered ? 0.08 : 0)))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hovered = $0 }
    .accessibilityRepresentation { Toggle(label, isOn: $isOn).toggleStyle(.checkbox) }
  }
}

struct SettingsCard<Content: View>: View {
  let glyph: Glyph
  let title: String
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
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
    toggleStyle(IslandSwitchStyle()).labelsHidden()
  }
}

/// A delay in milliseconds, picked on a slider in 50 ms steps. Every delay shares one range,
/// so their sliders line up.
private struct DelaySlider: View {
  @Binding var value: Double
  let range: ClosedRange<Double> = 0.05...1

  var body: some View {
    HStack(spacing: 8) {
      Slider(value: $value, in: range, step: 0.05).controlSize(.small)
        .frame(minWidth: 60, maxWidth: 130)
      Text("\(Int((value * 1000).rounded())) ms").monospacedDigit()
        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
        .frame(width: 50, alignment: .trailing)
    }
  }
}

/// The island's own switch: blue when on. A system switch turns grey in a panel that isn't
/// the active window, which the island never is.
struct IslandSwitchStyle: ToggleStyle {
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    Button {
      withAnimation(Motion.snappy) { configuration.isOn.toggle() }
    } label: {
      Capsule()
        .fill(configuration.isOn ? Color(nsColor: .systemBlue) : .white.opacity(0.16))
        .frame(width: 30, height: 18)
        .overlay(alignment: configuration.isOn ? .trailing : .leading) {
          Circle().fill(.white).padding(2)
            .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
        }
        .opacity(isEnabled ? 1 : 0.45)
        .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
  }
}

/// What to do when macOS won't let GitIsle send notifications.
struct NotificationsBlockedNote: View {
  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Text("macOS didn't allow notifications. Turn them on for GitIsle in System Settings.")
        .font(.system(size: 11)).foregroundStyle(Palette.attention)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 8)
      Button("Open") {
        let id = Bundle.main.bundleIdentifier ?? "dev.ppazosp.gitisle"
        if let url = URL(
          string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)")
        {
          NSWorkspace.shared.open(url)
        }
      }
      .buttonStyle(.plain)
      .font(.system(size: 11, weight: .semibold))
      .foregroundStyle(.white.opacity(0.85))
    }
  }
}

extension Notification.Name {
  static let islandSettingsChanged = Notification.Name("dev.ppazosp.gitisle.settingsChanged")
  static let islandOpenSettings = Notification.Name("dev.ppazosp.gitisle.openSettings")
}

/// Picks the display the island lives on, or leaves it to GitIsle.
private struct DisplayPicker: View {
  @Binding var displayID: UInt32?

  var body: some View {
    let screens = Self.screens
    DropdownButton(id: "display", trailing: true) {
      [
        Dropdown.Section(
          id: "displays", title: nil,
          items: [
            Dropdown.Item(id: "automatic", title: "Automatic", selected: displayID == nil) {
              displayID = nil
            }
          ]
            + screens.map { screen in
              Dropdown.Item(
                id: "\(screen.id)", title: screen.name, selected: displayID == screen.id
              ) { displayID = screen.id }
            })
      ]
    } label: {
      HStack(spacing: 6) {
        Text(screens.first { $0.id == displayID }?.name ?? "Automatic").lineLimit(1)
        Image(systemName: "chevron.up.chevron.down").font(.system(size: 8.5, weight: .bold))
          .foregroundStyle(.white.opacity(0.5))
      }
      .font(.system(size: 12, weight: .medium))
      .padding(.horizontal, 10)
      .frame(maxWidth: 170, minHeight: 24)
      .background(Capsule().fill(.white.opacity(0.08)))
      .contentShape(Capsule())
    }
    .fixedSize()
  }

  static var screens: [(id: UInt32, name: String)] {
    NSScreen.screens.compactMap { screen in
      guard
        let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
          .uint32Value
      else { return nil }
      return (id, screen.localizedName)
    }
  }
}
