import Foundation

public actor AgentLogReader {
  private struct Cached {
    var modified: Date
    var size: Int
    var session: AgentSession
  }
  private var cache: [String: Cached] = [:]

  public init() {}

  public func sessions(codexHome: URL, claudeHome: URL, now: Date = Date()) -> [AgentSession] {
    var found: [AgentSession] = []
    var seen = Set<String>()
    for (provider, root) in [
      (AgentProvider.codex, codexHome.appendingPathComponent("sessions")),
      (.claude, claudeHome.appendingPathComponent("projects")),
    ] {
      guard
        let enumerator = FileManager.default.enumerator(
          at: root,
          includingPropertiesForKeys: [
            .contentModificationDateKey, .fileSizeKey, .isRegularFileKey,
          ],
          options: [.skipsHiddenFiles])
      else { continue }
      var files: [(URL, Date, Int)] = []
      for case let file as URL in enumerator where file.pathExtension == "jsonl" {
        if provider == .claude, file.path.contains("/subagents/") { continue }
        guard
          let attributes = try? file.resourceValues(forKeys: [
            .contentModificationDateKey, .fileSizeKey, .isRegularFileKey,
          ]),
          attributes.isRegularFile == true, let date = attributes.contentModificationDate,
          now.timeIntervalSince(date) < 24 * 3600
        else { continue }
        files.append((file, date, attributes.fileSize ?? 0))
      }
      for (file, modified, size) in files.sorted(by: { $0.1 > $1.1 }).prefix(60) {
        seen.insert(file.path)
        let session: AgentSession
        if let cached = cache[file.path], cached.modified == modified, cached.size == size {
          session = cached.session
        } else {
          guard let parsed = Self.read(file: file, provider: provider, modified: modified) else {
            continue
          }
          session = parsed
          cache[file.path] = Cached(modified: modified, size: size, session: parsed)
        }
        var displayed = session
        // A stale "started" event can survive a crashed process. Its age is not proof of activity.
        if displayed.isActive && now.timeIntervalSince(displayed.updatedAt) > 5 * 60 {
          displayed.phase = .unknown
          displayed.activity = "No recent activity"
        }
        if now.timeIntervalSince(displayed.updatedAt) < 2 * 3600 { found.append(displayed) }
      }
    }
    cache = cache.filter { seen.contains($0.key) }
    let grouped = Dictionary(grouping: found, by: \.id)
    return grouped.values.compactMap { $0.max(by: { $0.updatedAt < $1.updatedAt }) }
      .sorted { lhs, rhs in
        lhs.isActive != rhs.isActive ? lhs.isActive : lhs.updatedAt > rhs.updatedAt
      }
  }

  private static func read(file: URL, provider: AgentProvider, modified: Date) -> AgentSession? {
    guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
    defer { try? handle.close() }
    let size = (try? handle.seekToEnd()) ?? 0
    try? handle.seek(toOffset: 0)
    let head = (try? handle.read(upToCount: 1_048_576)) ?? Data()
    let offset = size > 1_048_576 ? size - 1_048_576 : 0
    try? handle.seek(toOffset: offset)
    var tail = (try? handle.read(upToCount: 1_048_576)) ?? Data()
    if offset > 0, let newline = tail.firstIndex(of: 10) {
      tail = tail.suffix(from: tail.index(after: newline))
    }
    return parse(
      head: head, tail: tail, provider: provider, fallbackID: file.lastPathComponent,
      modified: modified)
  }

  public static func parse(
    head: Data, tail: Data, provider: AgentProvider, fallbackID: String,
    modified: Date
  ) -> AgentSession? {
    var id = fallbackID
    var directory = ""
    var source = provider.label
    var branch: String?
    var model: String?
    var phase: ActivityPhase = .unknown
    var activity = "Recent session"
    var timestamp = modified
    func rows(_ data: Data, maximum: Int = .max) -> [[String: Any]] {
      data.split(separator: 10).prefix(maximum).compactMap { line in
        (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any]
      }
    }
    // Never retain prompts, code, command arguments, or transcript content in the app model.
    for row in rows(head, maximum: 8) {
      if provider == .codex, row["type"] as? String == "session_meta",
        let payload = row["payload"] as? [String: Any]
      {
        id = payload["id"] as? String ?? id
        directory = payload["cwd"] as? String ?? ""
        let originator = payload["originator"] as? String ?? ""
        source = originator.lowercased().contains("desktop") ? "Codex desktop" : "Codex CLI"
        if let sessionSource = payload["source"] as? [String: Any], sessionSource["subagent"] != nil
        {
          source = "Codex subagent"
        }
        branch = (payload["git"] as? [String: Any])?["branch"] as? String
      } else if provider == .claude {
        id = row["sessionId"] as? String ?? id
        directory = row["cwd"] as? String ?? directory
        branch = row["gitBranch"] as? String ?? branch
      }
    }
    for row in rows(tail) {
      let type = row["type"] as? String ?? ""
      let payload = row["payload"] as? [String: Any] ?? [:]
      if provider == .codex {
        if type == "turn_context" { model = payload["model"] as? String ?? model }
        if type == "event_msg" {
          switch payload["type"] as? String {
          case "task_started", "task_start", "turn_started":
            phase = .working
            activity = "Working"
          case "task_complete", "task_completed", "turn_completed":
            phase = .finished
            activity = "Task completed"
          case "turn_aborted":
            phase = .interrupted
            activity = "Interrupted"
          case "exec_approval_request", "apply_patch_approval_request":
            phase = .waiting
            activity = "Approval requested"
          case "exec_command_begin", "item_started":
            phase = .working
            activity = "Running a tool"
          default: break
          }
        }
        if type == "response_item", payload["type"] as? String == "function_call" {
          phase = .working
          activity = "Using \(payload["name"] as? String ?? "a tool")"
        }
      } else {
        directory = row["cwd"] as? String ?? directory
        branch = row["gitBranch"] as? String ?? branch
        id = row["sessionId"] as? String ?? id
        if type == "user", let message = row["message"] as? [String: Any],
          message["content"] is String
        {
          phase = .working
          activity = "Working"
        }
        if type == "assistant", let message = row["message"] as? [String: Any] {
          model = message["model"] as? String ?? model
          if let stop = message["stop_reason"] as? String,
            ["end_turn", "stop_sequence"].contains(stop)
          {
            phase = .finished
            activity = "Turn completed"
          } else if let blocks = message["content"] as? [[String: Any]],
            let tool = blocks.last(where: { $0["type"] as? String == "tool_use" })
          {
            phase = .working
            activity = "Using \(tool["name"] as? String ?? "a tool")"
          }
        }
        if type == "system", row["subtype"] as? String == "turn_duration" {
          phase = .finished
          activity = "Turn completed"
        }
      }
      if let date = (row["timestamp"] as? String).flatMap(Dates.parse) { timestamp = date }
    }
    guard !directory.isEmpty else { return nil }
    return AgentSession(
      id: "\(provider.rawValue):\(id)", provider: provider, source: source, directory: directory,
      branch: branch, model: model, phase: phase, activity: activity, updatedAt: timestamp)
  }
}
