import AppKit
import IslandCore
import SwiftUI

/// The steps of first-run setup, in order.
enum OnboardingStep: Int, CaseIterable {
  case welcome, github, notifications, display, tuning, login

  /// Preview names for `--onboarding <step>`.
  init?(name: String) {
    guard let step = Self.allCases.first(where: { "\($0)" == name }) else { return nil }
    self = step
  }

  var title: String {
    switch self {
    case .welcome: "Welcome to GitIsle"
    case .github: "Connect GitHub"
    case .notifications: "Notifications"
    case .display: "Your screen"
    case .tuning: "Make it yours"
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
        case .notifications: NotificationsStep(store: store)
        case .display: DisplayStep(store: store)
        case .tuning: TuningStep()
        case .login: LoginStep(store: store)
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
      if store.notificationsBlocked { NotificationsBlockedNote() }
      Text("Choose which changes to announce any time in Settings.")
        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
    }
  }
}

private struct LoginStep: View {
  let store: IslandStore

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      StepToggle(
        title: "Open GitIsle when you log in",
        detail: "It lives in the notch, so it's ready whenever you are.",
        isOn: Binding(get: { store.startsAtLogin }, set: { store.setStartsAtLogin($0) })
      )
      if let error = store.loginItemError {
        Text(error).font(.system(size: 11)).foregroundStyle(Palette.failed).lineLimit(2)
      }
      StepText(
        "That's it. Hover the notch to open GitIsle; right-click it for Settings or to quit.")
    }
  }
}

/// Picks the screen the island lives on, drawn as the screens themselves.
private struct DisplayStep: View {
  let store: IslandStore

  var body: some View {
    let screens = Screen.connected
    VStack(alignment: .leading, spacing: 12) {
      StepText(
        "GitIsle sits at the top of one screen. On a display without a notch, it draws one. Automatic keeps it on your main display, the one with the menu bar."
      )
      HStack(alignment: .bottom, spacing: 14) {
        ForEach(screens) { screen in
          ScreenCard(screen: screen, selected: isSelected(screen)) {
            var next = store.settings
            next.displayID = screen.isMain ? nil : screen.id
            store.applySettings(next)
          }
        }
        // With one screen there's nothing to pick, but the island can live on another.
        if screens.count == 1 {
          ScreenCard(screen: .other, selected: false, action: nil)
        }
      }
      .frame(maxWidth: .infinity)
      Text("Change it any time in Settings.")
        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
    }
  }

  private func isSelected(_ screen: Screen) -> Bool {
    guard let id = store.settings.displayID, Screen.connected.contains(where: { $0.id == id })
    else { return screen.isMain }
    return screen.id == id
  }
}

/// A connected screen, as setup draws it.
private struct Screen: Identifiable {
  let id: UInt32
  let name: String
  let aspect: CGFloat
  let builtIn: Bool
  let isMain: Bool

  /// A display that isn't connected, to show the island can live there too.
  static let other = Screen(
    id: 0, name: "Another display", aspect: 16 / 9, builtIn: false, isMain: false)

  /// The main display first.
  static var connected: [Screen] {
    NSScreen.screens.enumerated().compactMap { index, screen in
      guard
        let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
          .uint32Value
      else { return nil }
      return Screen(
        id: id, name: screen.localizedName, aspect: screen.frame.width / screen.frame.height,
        builtIn: CGDisplayIsBuiltin(id) != 0, isMain: index == 0)
    }
  }
}

/// A small drawing of a screen: a laptop for the built-in display, a monitor for the others,
/// with the island's notch at the top.
private struct ScreenCard: View {
  let screen: Screen
  let selected: Bool
  let action: (() -> Void)?
  @State private var hovered = false

  private var placeholder: Bool { action == nil }

  var body: some View {
    let width: CGFloat = screen.builtIn ? 150 : 176
    let height = width / max(screen.aspect, 1)
    Button {
      action?()
    } label: {
      VStack(spacing: 8) {
        VStack(spacing: 0) {
          RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(
              LinearGradient(
                colors: [Color(white: 0.16), Color(white: 0.08)], startPoint: .top,
                endPoint: .bottom)
            )
            .overlay(alignment: .top) {
              UnevenRoundedRectangle(bottomLeadingRadius: 4, bottomTrailingRadius: 4)
                .fill(.black).frame(width: width * 0.22, height: 7)
            }
            .overlay(
              RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                  selected ? .white : .white.opacity(hovered && !placeholder ? 0.35 : 0.15),
                  lineWidth: selected ? 2 : 1)
            )
            .frame(width: width, height: height)
          if screen.builtIn {
            // The laptop's base.
            UnevenRoundedRectangle(bottomLeadingRadius: 4, bottomTrailingRadius: 4)
              .fill(Color(white: 0.22)).frame(width: width + 18, height: 6)
          } else {
            Rectangle().fill(Color(white: 0.2)).frame(width: 10, height: 10)
            Capsule().fill(Color(white: 0.22)).frame(width: 46, height: 4)
          }
        }
        VStack(spacing: 2) {
          Text(screen.name).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
          Text(placeholder ? "Pick it later in Settings" : screen.isMain ? "Main display" : " ")
            .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.45))
        }
        .frame(width: width + 18)
      }
      .opacity(placeholder ? 0.4 : 1)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(placeholder)
    .onHover { hovered = $0 }
    .accessibilityLabel(screen.name)
    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
  }
}

/// What Settings can change, so the island can feel the way you like.
private struct TuningStep: View {
  private let rows: [(symbol: String, title: String, detail: String)] = [
    (
      "cursorarrow.motionlines", "Timing",
      "How quickly it opens and closes."
    ),
    (
      "bell.badge", "Announcements", "Which changes slide out as banners, and system notifications."
    ),
    ("arrow.triangle.2.circlepath", "Refresh speed", "How often active and new PRs are checked."),
    ("display", "Display", "The screen the island lives on."),
    ("text.magnifyingglass", "Repositories", "Watch repositories beyond your own PRs."),
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      StepText("GitIsle works out of the box, and you can tune how it feels any time in Settings:")
      VStack(spacing: 0) {
        ForEach(rows, id: \.title) { row in
          HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: row.symbol).font(.system(size: 12, weight: .semibold))
              .foregroundStyle(.white.opacity(0.6)).frame(width: 18)
            Text(row.title).font(.system(size: 12.5, weight: .semibold))
              .frame(width: 110, alignment: .leading)
            Text(row.detail).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.55))
              .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
          }
          .padding(.vertical, 7)
        }
      }
      .padding(.horizontal, 12).padding(.vertical, 5)
      .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.surface))
      Text("Open Settings from the gear in the island's footer, or right-click the island.")
        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
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
