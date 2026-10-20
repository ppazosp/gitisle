import ServiceManagement

/// Opening GitIsle at login, through macOS's background task service. Its calls can block for
/// seconds, the first registration most of all, so they never run on the main thread.
enum LoginItem {
  static func isEnabled() async -> Bool {
    await Task.detached(priority: .userInitiated) {
      SMAppService.mainApp.status == .enabled
    }.value
  }

  static func set(_ enabled: Bool) async throws {
    try await Task.detached(priority: .userInitiated) {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    }.value
  }
}
