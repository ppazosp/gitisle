import AppKit
import IslandCore
import ServiceManagement
import SwiftUI

/// Settings shown inside the expanded island. Text and pickers apply on Save;
/// notification and login toggles apply immediately because they ask the system.
struct SettingsView: View {
  @Bindable var store: IslandStore
  @Binding var contentHeight: CGFloat
  @State private var draft: AppSettings
  @State private var loginItemError: String?
  @State private var startAtLogin = SMAppService.mainApp.status == .enabled
  @State private var cardsHeight: CGFloat = 0
  @State private var saveRowHeight: CGFloat = 0

  init(store: IslandStore, contentHeight: Binding<CGFloat>) {
    self.store = store
    _contentHeight = contentHeight
    _draft = State(initialValue: store.settings)
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

  var body: some View {
    // The cards scroll; the save row stays pinned below them so Save is always visible.
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
        contentHeight = $0 + saveRowHeight
      }
      HStack(spacing: 12) {
        if let error = store.persistenceError ?? loginItemError {
          Text(error).font(.system(size: 11)).foregroundStyle(Palette.failed).lineLimit(2)
        } else {
          Text("GitIsle reads GitHub through your gh login and never writes to GitHub.")
            .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.35))
        }
        Spacer()
        Button("Save") {
          store.applySettings(merged)
          if store.persistenceError == nil {
            withAnimation(Motion.snappy) { store.showingSettings = false }
          }
        }
        .buttonStyle(.borderedProminent).controlSize(.small)
        .keyboardShortcut(.defaultAction)
        .disabled(!changed)
      }
      .padding(.horizontal, 20).padding(.vertical, 8)
      .onGeometryChange(for: CGFloat.self) {
        $0.size.height
      } action: {
        saveRowHeight = $0
        contentHeight = cardsHeight + $0
      }
    }
  }

  private var github: some View {
    SettingsCard(glyph: .github, title: "GitHub") {
      SettingsRow("Account") {
        if let login = store.github?.login, store.githubError == nil {
          HStack(spacing: 6) {
            Circle().fill(Palette.open).frame(width: 6, height: 6)
            Text(verbatim: "@\(login)").font(.system(size: 12, weight: .medium))
          }
        } else {
          Link(
            "Sign in with gh",
            destination: URL(string: "https://cli.github.com/manual/gh_auth_login")!
          )
          .font(.system(size: 12))
        }
      }
      SettingsRow("Also watch") {
        TextField("owner/repo, owner/another-repo", text: $draft.repositories)
          .islandField()
      }
      SettingsRow("Refresh") {
        PillPicker(
          options: [(60.0, "1 min"), (120.0, "2 min"), (300.0, "5 min")],
          selection: $draft.githubRefreshSeconds, fontSize: 11)
      }
      Text("Your PRs and review requests are always included.")
        .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.4))
    }
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
          ForEach(Self.announcements, id: \.kind) { item in
            AnnouncementChip(
              glyph: item.glyph, label: item.label, color: item.kind.color,
              selected: draft.announcedKinds.contains(item.kind.rawValue)
            ) {
              if draft.announcedKinds.remove(item.kind.rawValue) == nil {
                draft.announcedKinds.insert(item.kind.rawValue)
              }
            }
          }
        }
      }
    }
  }

  private static let announcements: [(kind: PRStatus, glyph: Glyph, label: String)] = [
    (.merged, .merge, "Merged"), (.failed, .failFill, "Failed"), (.review, .eye, "Review"),
    (.queued, .mergeQueue, "Merging"),
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
        TextField("~/.codex", text: $draft.codexHome).islandField()
      }
      SettingsRow("Claude Code home") {
        TextField("~/.claude", text: $draft.claudeHome).islandField()
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

private struct SettingsCard<Content: View>: View {
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

private struct SettingsRow<Control: View>: View {
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
  fileprivate func islandField() -> some View {
    textFieldStyle(.plain)
      .font(.system(size: 12))
      .padding(.horizontal, 9).padding(.vertical, 6)
      .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.white.opacity(0.07)))
      .frame(minWidth: 80, maxWidth: 240)
  }

  fileprivate func islandToggle() -> some View {
    toggleStyle(.switch).controlSize(.mini).labelsHidden()
  }
}

extension Notification.Name {
  static let islandSettingsChanged = Notification.Name("dev.ppazosp.gitisle.settingsChanged")
  static let islandOpenSettings = Notification.Name("dev.ppazosp.gitisle.openSettings")
}
