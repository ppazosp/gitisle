import AppKit
import CryptoKit
import IslandCore
import Observation

/// Looks for a newer GitIsle release every few hours and installs it when asked. Only release
/// builds update themselves; a build from source updates with `git pull`. GitHub is reached
/// through `gh`, like everything else GitIsle reads.
@MainActor @Observable final class Updater {
  private(set) var available: AppRelease?
  private(set) var installing = false
  private(set) var error: String?
  @ObservationIgnored private var loop: Task<Void, Never>?

  static var version: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
  }

  /// Release packaging sets this; builds from source leave it out.
  static var enabled: Bool {
    Bundle.main.object(forInfoDictionaryKey: "GitIsleUpdates") as? Bool == true
  }

  func start() {
    guard Self.enabled, loop == nil else { return }
    loop = Task { [weak self] in
      while !Task.isCancelled {
        await self?.check()
        do { try await Task.sleep(for: .seconds(6 * 3600)) } catch { return }
      }
    }
  }

  func stop() {
    loop?.cancel()
    loop = nil
  }

  /// Example data only: shows the update button as it looks when a release is waiting.
  func preview() { available = AppRelease(tag: "v9.9.9", version: "9.9.9") }

  /// A failed check stays quiet; the next one tries again.
  func check() async {
    guard !installing, let gh = ProcessRunner.executable("gh"),
      let data = try? await ProcessRunner.run(
        gh, arguments: ["api", "repos/\(AppRelease.repository)/releases/latest"], deadline: 20),
      let latest = try? AppRelease.latest(from: data)
    else { return }
    available = AppRelease.isNewer(latest.version, than: Self.version) ? latest : nil
  }

  func install() {
    guard let release = available, !installing, Self.enabled else { return }
    installing = true
    error = nil
    let app = Bundle.main.bundleURL
    Task {
      do {
        try await Self.replace(app, with: release)
        Self.relaunch(app)
      } catch {
        self.error = "Couldn't update: \(error.localizedDescription)"
        installing = false
      }
    }
  }

  /// Downloads the release, checks its signature and checksum, and swaps it in for the
  /// running app. The old copy keeps running until GitIsle relaunches.
  nonisolated private static func replace(_ app: URL, with release: AppRelease) async throws {
    guard let gh = ProcessRunner.executable("gh") else {
      throw ProcessFailure.unavailable("GitHub CLI (gh)")
    }
    let files = FileManager.default
    // Next to the app, so the final swap stays on one volume.
    let work = try files.url(
      for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: app, create: true)
    defer { try? files.removeItem(at: work) }
    _ = try await ProcessRunner.run(
      gh,
      arguments: [
        "release", "download", release.tag, "--repo", AppRelease.repository,
        "--pattern", AppRelease.archive, "--pattern", AppRelease.signature,
        "--pattern", AppRelease.checksums, "--dir", work.path,
      ], deadline: 300)
    let archive = work.appendingPathComponent(AppRelease.archive)
    let contents = try Data(contentsOf: archive)
    // The signature proves GitIsle's release workflow made this archive; the checksum only
    // that it arrived intact.
    let signature = try? String(
      contentsOf: work.appendingPathComponent(AppRelease.signature), encoding: .utf8)
    guard let signature, AppRelease.isSigned(contents, signature: signature) else {
      throw UpdateFailure("the download isn't signed by GitIsle.")
    }
    let sums = try String(
      contentsOf: work.appendingPathComponent(AppRelease.checksums), encoding: .utf8)
    let digest = SHA256.hash(data: contents).map { String(format: "%02x", $0) }.joined()
    guard AppRelease.checksum(of: AppRelease.archive, in: sums) == digest else {
      throw UpdateFailure("the download doesn't match its checksum.")
    }
    let unpacked = work.appendingPathComponent("unpacked")
    _ = try await ProcessRunner.run(
      URL(fileURLWithPath: "/usr/bin/ditto"),
      arguments: ["-x", "-k", archive.path, unpacked.path], deadline: 120)
    let fresh = unpacked.appendingPathComponent("GitIsle.app")
    let bundle = Bundle(url: fresh)
    guard bundle?.bundleIdentifier == Bundle.main.bundleIdentifier,
      bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        == release.version
    else { throw UpdateFailure("the download isn't GitIsle \(release.version).") }
    _ = try await ProcessRunner.run(
      URL(fileURLWithPath: "/usr/bin/codesign"),
      arguments: ["--verify", "--deep", "--strict", fresh.path], deadline: 60)
    // Releases are signed ad hoc and not notarized; a quarantined copy wouldn't open.
    _ = try? await ProcessRunner.run(
      URL(fileURLWithPath: "/usr/bin/xattr"),
      arguments: ["-dr", "com.apple.quarantine", fresh.path])
    _ = try files.replaceItemAt(app, withItemAt: fresh)
  }

  /// Opens the new copy once this one has quit.
  private static func relaunch(_ app: URL) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = [
      "-c", "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$0\"",
      app.path, String(ProcessInfo.processInfo.processIdentifier),
    ]
    try? process.run()
    NSApp.terminate(nil)
  }
}

private struct UpdateFailure: LocalizedError {
  let errorDescription: String?
  init(_ message: String) { errorDescription = message }
}
