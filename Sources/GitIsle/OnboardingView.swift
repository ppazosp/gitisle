import AppKit
import IslandCore
import ServiceManagement
import SwiftUI

/// The steps of first-run setup, in order.
enum OnboardingStep: Int, CaseIterable {
  case welcome, github, agents, notifications, login

  /// Preview names for `--onboarding <step>`.
  init?(name: String) {
    guard let step = Self.allCases.first(where: { "\($0)" == name }) else { return nil }
    self = step
  }

  var title: String {
    switch self {
    case .welcome: "Welcome to GitIsle"
    case .github: "Connect GitHub"
    case .agents: "Coding agents"
    case .notifications: "Notifications"
    case .login: "Start at login"
    }
  }
}

/// First-run setup inside the expanded island: one step at a time, GitHub first.
struct OnboardingView: View {
  @Bindable var store: IslandStore
  @Binding var contentHeight: CGFloat

  var body: some View {
    MeasuredColumn {
      VStack(alignment: .leading, spacing: 14) {
        Text(store.onboardingStep.title).font(.system(size: 20, weight: .semibold))
        switch store.onboardingStep {
        case .welcome: WelcomeStep()
        case .github: GitHubStep(store: store)
        case .agents: AgentsStep(store: store)
        case .notifications: NotificationsStep(store: store)
        case .login: LoginStep()
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 28).padding(.top, 18).padding(.bottom, 16)
      .id(store.onboardingStep)
      .transition(.opacity)
    } onHeight: {
      contentHeight = $0
    }
    .animation(Motion.snappy, value: store.onboardingStep)
  }
}

/// Step dots for the header.
struct OnboardingProgress: View {
  let step: OnboardingStep

  var body: some View {
    HStack(spacing: 6) {
      ForEach(OnboardingStep.allCases, id: \.self) { item in
        Capsule()
          .fill(.white.opacity(item == step ? 0.9 : item.rawValue < step.rawValue ? 0.45 : 0.15))
          .frame(width: item == step ? 16 : 6, height: 6)
      }
    }
    .animation(Motion.snappy, value: step)
    .accessibilityElement()
    .accessibilityLabel("Step \(step.rawValue + 1) of \(OnboardingStep.allCases.count)")
  }
}

/// Skip on the left, Back and Continue on the right.
struct OnboardingFooter: View {
  @Bindable var store: IslandStore

  private var step: OnboardingStep { store.onboardingStep }
  private var isLast: Bool { step == OnboardingStep.allCases.last }
  /// GitIsle needs a signed-in gh, so setup waits for it.
  private var canContinue: Bool {
    guard step == .github else { return true }
    if case .connected = store.githubConnection { return true }
    return false
  }

  var body: some View {
    HStack(spacing: 8) {
      Button("Skip setup") { store.finishOnboarding() }
        .buttonStyle(.plain).font(.system(size: 11.5))
        .foregroundStyle(.white.opacity(0.45))
        .opacity(isLast ? 0 : 1).disabled(isLast)
      Spacer()
      if step != .welcome {
        Button("Back") { move(-1) }
          .buttonStyle(StepButtonStyle(prominent: false))
      }
      Button(isLast ? "Start using GitIsle" : "Continue") {
        if isLast { store.finishOnboarding() } else { move(1) }
      }
      .buttonStyle(StepButtonStyle(prominent: true))
      .keyboardShortcut(.defaultAction)
      .disabled(!canContinue)
    }
    // Like the app's footer: closer to the bottom of the island than to its sides.
    .padding(.horizontal, 24).padding(.bottom, 6.5)
  }

  private func move(_ offset: Int) {
    guard let next = OnboardingStep(rawValue: step.rawValue + offset) else { return }
    withAnimation(Motion.snappy) { store.onboardingStep = next }
  }
}

// MARK: - Steps

private struct WelcomeStep: View {
  var body: some View {
    HStack(alignment: .top, spacing: 16) {
      Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
      VStack(alignment: .leading, spacing: 8) {
        StepText(
          "GitIsle turns your notch into a live view of your pull requests: what's merging, what's failing and what needs you."
        )
        StepText(
          "It reads GitHub through the GitHub CLI and never writes to it. Setup takes a minute.")
      }
    }
  }
}

private struct GitHubStep: View {
  let store: IslandStore

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      switch store.githubConnection {
      case nil:
        HStack(spacing: 8) {
          ProgressView().controlSize(.small)
          StepText("Checking the GitHub CLI…")
        }
      case .notInstalled:
        StepText("GitIsle uses the GitHub CLI (gh) to read your pull requests. Install it:")
        CommandBox(command: "brew install gh")
        Link("Other ways to install gh", destination: URL(string: "https://cli.github.com")!)
          .font(.system(size: 12))
      case .signedOut:
        StepText("The GitHub CLI is installed. Sign in with it in Terminal, then come back:")
        CommandBox(command: "gh auth login")
      case .connected(let login):
        HStack(spacing: 10) {
          AccountChip(login: login)
          StepText("Connected. GitIsle will show your PRs and review requests.")
        }
      case .failed(let message):
        StepText("GitHub didn't answer. Check your connection; GitIsle keeps trying.")
        Text(message).font(.system(size: 11)).foregroundStyle(Palette.attention)
          .lineLimit(3).textSelection(.enabled)
      }
      if !isConnected, store.githubConnection != nil {
        HStack(spacing: 6) {
          ProgressView().controlSize(.mini)
          Text("Checking again every few seconds")
            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
        }
      }
    }
    // Re-checks while this step is open, until gh is installed and signed in.
    .task {
      while !Task.isCancelled {
        await store.checkGitHubConnection()
        if isConnected { return }
        try? await Task.sleep(for: .seconds(3))
      }
    }
  }

  private var isConnected: Bool {
    if case .connected = store.githubConnection { return true }
    return false
  }
}

private struct AgentsStep: View {
  let store: IslandStore

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      StepText(
        "The Stats tab can chart Claude Code and Codex usage from their local history. These are the usual folders; change them only if yours live elsewhere."
      )
      FolderRow(
        label: "Claude Code", glyph: .claude, path: store.settings.claudeHome
      ) { path in
        var next = store.settings
        next.claudeHome = path
        store.applySettings(next)
      }
      FolderRow(label: "Codex", glyph: .openai, path: store.settings.codexHome) { path in
        var next = store.settings
        next.codexHome = path
        store.applySettings(next)
      }
      Text("Don't use one of them? Leave it; GitIsle skips what it can't find.")
        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
    }
  }
}

/// A folder setting with a found or not-found mark; edits apply on Return or leaving the field.
private struct FolderRow: View {
  let label: String
  let glyph: Glyph
  let path: String
  let commit: (String) -> Void
  @State private var text = ""
  @FocusState private var focused: Bool

  private var exists: Bool {
    var directory: ObjCBool = false
    let expanded = (text as NSString).expandingTildeInPath
    return FileManager.default.fileExists(atPath: expanded, isDirectory: &directory)
      && directory.boolValue
  }

  var body: some View {
    HStack(spacing: 10) {
      GlyphView(glyph: glyph, size: 13).foregroundStyle(.white.opacity(0.6)).frame(width: 16)
      Text(label).font(.system(size: 12.5)).frame(width: 90, alignment: .leading)
      TextField("Folder", text: $text).islandField().frame(maxWidth: .infinity)
        .focused($focused)
        .onSubmit { commitIfValid() }
        .onChange(of: focused) { _, isFocused in if !isFocused { commitIfValid() } }
      HStack(spacing: 4) {
        Image(systemName: exists ? "checkmark.circle.fill" : "questionmark.circle")
        Text(exists ? "Found" : "Not found")
      }
      .font(.system(size: 11))
      .foregroundStyle(exists ? Palette.open : .white.opacity(0.4))
      .frame(width: 84, alignment: .leading)
    }
    .onAppear { text = path }
    .onDisappear { commitIfValid() }
  }

  private func commitIfValid() {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    if !trimmed.isEmpty, trimmed != path { commit(trimmed) }
  }
}

private struct NotificationsStep: View {
  let store: IslandStore

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      StepText("GitIsle can announce what matters: a merge, failed checks, a review request.")
      StepToggle(
        title: "Island banners",
        detail: "A short banner slides out of the notch, then gets out of the way.",
        isOn: Binding(
          get: { store.settings.bannersEnabled },
          set: { value in store.update { $0.bannersEnabled = value } }))
      StepToggle(
        title: "System notifications",
        detail: "Also send them to Notification Center. macOS asks for permission.",
        isOn: Binding(
          get: { store.settings.notificationsEnabled },
          set: { enabled in
            if enabled {
              Task { await store.requestNotifications() }
            } else {
              store.update { $0.notificationsEnabled = false }
            }
          }))
      Text("Choose which changes to announce any time in Settings.")
        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
    }
  }
}

private struct LoginStep: View {
  @State private var startAtLogin = SMAppService.mainApp.status == .enabled
  @State private var error: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      StepToggle(
        title: "Open GitIsle when you log in",
        detail: "It lives in the notch, so it's ready whenever you are.",
        isOn: $startAtLogin
      )
      .onChange(of: startAtLogin) { _, enabled in
        do {
          if enabled {
            try SMAppService.mainApp.register()
          } else {
            try SMAppService.mainApp.unregister()
          }
          error = nil
        } catch { self.error = error.localizedDescription }
      }
      if let error {
        Text(error).font(.system(size: 11)).foregroundStyle(Palette.failed).lineLimit(2)
      }
      StepText(
        "That's it. Hover the notch to open GitIsle; right-click it for Settings or to quit.")
    }
  }
}

// MARK: - Pieces

private struct StepText: View {
  let text: String
  init(_ text: String) { self.text = text }

  var body: some View {
    Text(text).font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.7))
      .fixedSize(horizontal: false, vertical: true)
  }
}

private struct StepToggle: View {
  let title: String
  let detail: String
  @Binding var isOn: Bool

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 3) {
        Text(title).font(.system(size: 12.5, weight: .semibold))
        Text(detail).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.5))
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 12)
      Toggle("", isOn: $isOn).islandToggle()
    }
    .padding(12)
    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.surface))
  }
}

/// The island's own buttons: system prominent buttons turn grey in a panel that isn't the
/// active window, which the island never is.
private struct StepButtonStyle: ButtonStyle {
  let prominent: Bool
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 12, weight: .semibold))
      .foregroundStyle(prominent ? .black : .white.opacity(0.85))
      .padding(.horizontal, 14).padding(.vertical, 6)
      .background(Capsule().fill(prominent ? .white : .white.opacity(0.1)))
      .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.35)
      .contentShape(Capsule())
  }
}

/// A Terminal command to run, with a copy button.
private struct CommandBox: View {
  let command: String
  @State private var copied = false

  var body: some View {
    HStack(spacing: 10) {
      Text(verbatim: "$ \(command)").font(.system(size: 12.5, design: .monospaced))
        .textSelection(.enabled)
      Spacer()
      Button {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        withAnimation(Motion.snappy) { copied = true }
        Task {
          try? await Task.sleep(for: .seconds(1.6))
          withAnimation(Motion.snappy) { copied = false }
        }
      } label: {
        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
          .font(.system(size: 11.5, weight: .medium))
          .foregroundStyle(copied ? Palette.open : .white.opacity(0.8))
      }
      .buttonStyle(.plain)
      .accessibilityLabel(copied ? "Copied" : "Copy \(command)")
    }
    .padding(.horizontal, 12).padding(.vertical, 10)
    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.07)))
  }
}
