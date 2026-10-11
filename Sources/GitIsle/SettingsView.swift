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

  init(store: IslandStore, contentHeight: Binding<CGFloat>) {
    self.store = store
    _contentHeight = contentHeight
    _draft = State(initialValue: store.settings)
  }

  private var changed: Bool {
    var current = store.settings
    current.notificationsEnabled = draft.notificationsEnabled
    return current != draft
  }

  var body: some View {
    MeasuredColumn {
      VStack(spacing: 12) {
        HStack(alignment: .top, spacing: 12) {
          VStack(spacing: 12) {
            github
            notifications
          }
          VStack(spacing: 12) {
            island
            usage
          }
        }
        .fixedSize(horizontal: false, vertical: true)
        HStack(spacing: 12) {
          if let error = store.persistenceError ?? loginItemError {
            Text(error).font(.system(size: 11)).foregroundStyle(Palette.failed).lineLimit(2)
          } else {
            Text("GitIsle reads GitHub through your gh login and never writes to GitHub.")
              .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.35))
          }
          Spacer()
          Button("Save") {
            draft.notificationsEnabled = store.settings.notificationsEnabled
            store.applySettings(draft)
            if store.persistenceError == nil {
              withAnimation(Motion.snappy) { store.showingSettings = false }
            }
          }
          .buttonStyle(.borderedProminent).controlSize(.small)
          .keyboardShortcut(.defaultAction)
          .disabled(!changed)
        }
        .padding(.horizontal, 4)
      }
      .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 18)
    } onHeight: {
      contentHeight = $0
    }
  }

  private var github: some View {
    SettingsCard(glyph: .github, title: "GitHub") {
      SettingsRow("Also watch") {
        TextField("owner/repo, owner/another-repo", text: $draft.repositories)
          .islandField()
      }
      SettingsRow("Refresh") {
        PillPicker(
          options: [(60.0, "1 min"), (120.0, "2 min"), (300.0, "5 min")],
          selection: $draft.githubRefreshSeconds, fontSize: 11)
      }
      HStack {
        Text("Your PRs and review requests are always included.")
        Spacer()
        Link(
          "GitHub CLI setup",
          destination: URL(string: "https://cli.github.com/manual/gh_auth_login")!)
      }
      .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.4))
    }
  }

  private var notifications: some View {
    SettingsCard(glyph: .eye, title: "Notifications") {
      SettingsRow("Merges, failed checks, review requests") {
        Toggle(
          "",
          isOn: Binding(
            get: { store.settings.notificationsEnabled },
            set: { enabled in
              if enabled {
                Task { await store.requestNotifications() }
              } else {
                store.settings.notificationsEnabled = false
                store.saveSettings()
              }
            })
        )
        .islandToggle()
      }
    }
  }

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
        .labelsHidden().pickerStyle(.menu).fixedSize()
      }
      SettingsRow("Hover delay") {
        HStack(spacing: 8) {
          Slider(value: $draft.hoverDelay, in: 0.05...0.9, step: 0.05).controlSize(.small)
            .frame(width: 130)
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
    }
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
      Text(label).font(.system(size: 12)).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
      Spacer(minLength: 8)
      control
    }
  }
}

extension View {
  fileprivate func islandField() -> some View {
    textFieldStyle(.plain)
      .font(.system(size: 12))
      .padding(.horizontal, 9).padding(.vertical, 6)
      .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.white.opacity(0.07)))
      .frame(maxWidth: 240)
  }

  fileprivate func islandToggle() -> some View {
    toggleStyle(.switch).controlSize(.mini).labelsHidden()
  }
}

extension Notification.Name {
  static let islandSettingsChanged = Notification.Name("dev.ppazosp.gitisle.settingsChanged")
  static let islandOpenSettings = Notification.Name("dev.ppazosp.gitisle.openSettings")
}
