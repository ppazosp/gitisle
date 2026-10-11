import Darwin
import Foundation

public enum ProcessFailure: LocalizedError {
  case unavailable(String)
  case timedOut, cancelled
  case failed(String)
  public var errorDescription: String? {
    switch self {
    case .unavailable(let name): "Install \(name) and sign in before connecting."
    case .timedOut: "The connection timed out. Cached data is still available."
    case .cancelled: "Connection cancelled."
    case .failed(let message): message
    }
  }
}

private final class CancellationFlag: @unchecked Sendable {
  private let lock = NSLock()
  private var value = false
  private var process: Process?
  func bind(_ process: Process) { lock.withLock { self.process = process } }
  func finish() { lock.withLock { process = nil } }
  func cancel() {
    lock.withLock {
      value = true
      if process?.isRunning == true { process?.terminate() }
    }
  }
  var cancelled: Bool { lock.withLock { value } }
}

public enum ProcessRunner {
  public static func executable(_ name: String) -> URL? {
    let folders =
      ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
      + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
    return folders.map { URL(fileURLWithPath: $0).appendingPathComponent(name) }
      .first { FileManager.default.isExecutableFile(atPath: $0.path) }
  }

  public static func run(
    _ executable: URL, arguments: [String], input: Data? = nil,
    deadline: TimeInterval = 30, limit: Int = 8_000_000
  ) async throws -> Data {
    guard (input?.count ?? 0) <= 16_384, deadline.isFinite, deadline > 0, limit > 0 else {
      throw ProcessFailure.failed("The command input or limits are invalid.")
    }
    let cancellation = CancellationFlag()
    return try await withTaskCancellationHandler {
      try await Task.detached(priority: .utility) {
        let process = Process()
        cancellation.bind(process)
        defer { cancellation.finish() }
        guard !cancellation.cancelled else { throw ProcessFailure.cancelled }
        let output = Pipe()
        let errors = Pipe()
        let stdin = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = errors
        process.standardInput = stdin
        try process.run()
        defer {
          try? output.fileHandleForReading.close()
          try? errors.fileHandleForReading.close()
        }
        if let input { try stdin.fileHandleForWriting.write(contentsOf: input) }
        try stdin.fileHandleForWriting.close()
        let stdoutFD = output.fileHandleForReading.fileDescriptor
        let stderrFD = errors.fileHandleForReading.fileDescriptor
        _ = fcntl(stdoutFD, F_SETFL, fcntl(stdoutFD, F_GETFL) | O_NONBLOCK)
        _ = fcntl(stderrFD, F_SETFL, fcntl(stderrFD, F_GETFL) | O_NONBLOCK)
        var stdout = Data()
        var stderr = Data()
        var oversized = false
        let started = ProcessInfo.processInfo.systemUptime
        var cancelledAt: TimeInterval?
        var timedOut = false
        func drain(_ fd: Int32, into data: inout Data) {
          var buffer = [UInt8](repeating: 0, count: 16_384)
          while true {
            let count = read(fd, &buffer, buffer.count)
            guard count > 0 else { return }
            if data.count + count <= limit {
              data.append(contentsOf: buffer.prefix(count))
            } else {
              oversized = true
              return
            }
          }
        }
        while process.isRunning {
          drain(stdoutFD, into: &stdout)
          drain(stderrFD, into: &stderr)
          let elapsed = ProcessInfo.processInfo.systemUptime - started
          if cancelledAt == nil && (cancellation.cancelled || elapsed > deadline || oversized) {
            timedOut = elapsed > deadline
            cancelledAt = elapsed
            process.terminate()
          }
          if let cancelledAt, elapsed - cancelledAt > 1 {
            _ = kill(process.processIdentifier, SIGKILL)
          }
          try? await Task.sleep(for: .milliseconds(20))
        }
        // isRunning is already false. waitUntilExit pumps a thread-local run loop;
        // an async task may resume on a different thread from the one that launched the process.
        drain(stdoutFD, into: &stdout)
        drain(stderrFD, into: &stderr)
        if cancellation.cancelled { throw ProcessFailure.cancelled }
        if timedOut { throw ProcessFailure.timedOut }
        if oversized { throw ProcessFailure.failed("The response exceeded the safe size limit.") }
        guard process.terminationStatus == 0 else {
          let message = String(decoding: stderr.prefix(1800), as: UTF8.self).trimmingCharacters(
            in: .whitespacesAndNewlines)
          throw ProcessFailure.failed(message.isEmpty ? "The connection failed." : message)
        }
        return stdout
      }.value
    } onCancel: {
      cancellation.cancel()
    }
  }
}
