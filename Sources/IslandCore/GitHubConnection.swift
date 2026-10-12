import Foundation

/// Whether GitIsle can reach GitHub through the GitHub CLI, for first-run setup.
public enum GitHubConnection: Equatable, Sendable {
  /// `gh` isn't installed where GitIsle looks for it.
  case notInstalled
  /// `gh` is installed but not signed in.
  case signedOut
  /// Signed in as this account.
  case connected(login: String)
  /// Anything else, such as no network; the message is gh's own.
  case failed(String)

  /// Asks `gh` which account it is signed in as. `locate` and `login` are replaceable in tests.
  public static func check(
    locate: () -> URL? = { ProcessRunner.executable("gh") },
    login: (URL) async throws -> Data = {
      try await ProcessRunner.run($0, arguments: ["api", "user", "--jq", ".login"], deadline: 15)
    }
  ) async -> GitHubConnection {
    guard let gh = locate() else { return .notInstalled }
    do {
      let name = String(decoding: try await login(gh), as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      return name.isEmpty ? .signedOut : .connected(login: name)
    } catch {
      let message = error.localizedDescription
      // gh tells signed-out users to run `gh auth login`; other failures keep their message.
      return message.contains("gh auth login") ? .signedOut : .failed(message)
    }
  }
}
