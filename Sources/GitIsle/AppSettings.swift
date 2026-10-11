import Foundation

struct AppSettings: Codable, Equatable {
  var repositories = ""
  var hoverDelay = 0.2
  var githubRefreshSeconds = 60.0
  var displayID: UInt32?
  var showInFullscreen = false
  var notificationsEnabled = false
  var codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"] ?? NSHomeDirectory() + "/.codex"
  var claudeHome =
    ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] ?? NSHomeDirectory() + "/.claude"

  static func load(from url: URL) -> AppSettings {
    guard let data = try? Data(contentsOf: url),
      let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
    else {
      return AppSettings()
    }
    return settings
  }

  func save(to url: URL) throws {
    try JSONEncoder().encode(self).write(to: url, options: .atomic)
  }
}

enum AppFiles {
  static var directory: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("GitIsle", isDirectory: true)
  }
  static func prepare() throws {
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
  }
  static var settings: URL { directory.appendingPathComponent("settings.json") }
  static var snapshot: URL { directory.appendingPathComponent("github.json") }
  static var events: URL { directory.appendingPathComponent("events.json") }
}
