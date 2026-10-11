import AppKit
import IslandCore
import ServiceManagement
import SwiftUI

struct SettingsView: View {
  @Bindable var store: IslandStore
  @State private var draft: AppSettings
  @State private var loginItemError: String?
  @State private var startAtLogin = SMAppService.mainApp.status == .enabled

  init(store: IslandStore) {
    self.store = store
    _draft = State(initialValue: store.settings)
  }

  var body: some View {
    Form {
      Section("GitHub") {
        Text("Your own open PRs and requested reviews are included automatically.")
          .font(.callout).foregroundStyle(.secondary)
        TextField(
          "Also watch repositories", text: $draft.repositories,
          prompt: Text("owner/repo, owner/another-repo"))
        Text(
          "GitIsle uses your existing GitHub CLI login. It reads PRs and opens GitHub for actions."
        )
        .font(.caption).foregroundStyle(.secondary)
        Picker("Refresh", selection: $draft.githubRefreshSeconds) {
          Text("Every minute").tag(60.0)
          Text("Every 2 minutes").tag(120.0)
          Text("Every 5 minutes").tag(300.0)
        }
        Link(
          "GitHub CLI setup",
          destination: URL(string: "https://cli.github.com/manual/gh_auth_login")!)
      }
      Section("Island") {
        Picker("Display", selection: $draft.displayID) {
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
        HStack {
          Text("Hover delay")
          Slider(value: $draft.hoverDelay, in: 0.15...0.9, step: 0.05)
          Text("\(Int(draft.hoverDelay * 1000)) ms").monospacedDigit().frame(
            width: 60, alignment: .trailing)
        }
        Toggle("Show in full screen", isOn: $draft.showInFullscreen)
        Toggle("Start at login", isOn: $startAtLogin).onChange(of: startAtLogin) { _, enabled in
          do {
            if enabled {
              try SMAppService.mainApp.register()
            } else {
              try SMAppService.mainApp.unregister()
            }
            loginItemError = nil
          } catch { loginItemError = error.localizedDescription }
        }
        if let loginItemError { Text(loginItemError).font(.caption).foregroundStyle(.orange) }
      }
      Section("Notifications") {
        Toggle(
          "Notify when PRs merge, checks fail, or a review is requested",
          isOn: Binding(
            get: { store.settings.notificationsEnabled },
            set: { enabled in
              if enabled {
                Task { await store.requestNotifications() }
              } else {
                store.settings.notificationsEnabled = false
                store.saveSettings()
              }
            }
          ))
      }
      Section("Local agents") {
        TextField("Codex home", text: $draft.codexHome)
        TextField("Claude Code home", text: $draft.claudeHome)
        Text(
          "Desktop and CLI sessions share their provider's history. Models and tokens come from local records; missing values stay unavailable. Session summaries and caches stay on this Mac."
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      if let error = store.persistenceError { Text(error).foregroundStyle(.red).font(.caption) }
      HStack {
        Spacer()
        Button("Save settings") {
          draft.notificationsEnabled = store.settings.notificationsEnabled
          store.applySettings(draft)
        }.buttonStyle(.borderedProminent)
      }
      Section {
        Link("GitIsle on GitHub", destination: URL(string: "https://github.com/ppazosp/gitisle")!)
        Text("Usage parsing by CodexBar · Island window pattern from Agents Island")
          .font(.caption).foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .frame(width: 540, height: 690)
  }
}

extension Notification.Name {
  static let islandSettingsChanged = Notification.Name("dev.ppazosp.gitisle.settingsChanged")
}
