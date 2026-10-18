import Foundation

/// A file's changes as GitHub's unified diff shows them, one line at a time.
public enum Diff {
  public struct Line: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
      /// The start of a block of changes: "@@ -52,9 +52,21 @@ func name(".
      case hunk
      case context, added, removed
    }

    public var kind: Kind
    /// The line in the file before the change; nil for added lines and hunk headers.
    public var oldNumber: Int?
    /// The line in the file after the change; nil for removed lines and hunk headers.
    public var newNumber: Int?
    /// The line without its leading "+", "-", or space.
    public var text: String

    public init(kind: Kind, oldNumber: Int? = nil, newNumber: Int? = nil, text: String) {
      self.kind = kind
      self.oldNumber = oldNumber
      self.newNumber = newNumber
      self.text = text
    }
  }

  /// The lines of one file's patch, numbered from its hunk headers.
  public static func lines(_ patch: String) -> [Line] {
    var result: [Line] = []
    var old = 0
    var new = 0
    for raw in patch.split(separator: "\n", omittingEmptySubsequences: false) {
      let line = raw.hasSuffix("\r") ? raw.dropLast() : raw
      if line.hasPrefix("@@") {
        if let (oldStart, newStart) = starts(String(line)) {
          old = oldStart
          new = newStart
        }
        result.append(Line(kind: .hunk, text: String(line)))
      } else if line.hasPrefix("+") {
        result.append(Line(kind: .added, newNumber: new, text: String(line.dropFirst())))
        new += 1
      } else if line.hasPrefix("-") {
        result.append(Line(kind: .removed, oldNumber: old, text: String(line.dropFirst())))
        old += 1
      } else if line.hasPrefix("\\") {
        // "\ No newline at end of file" describes the line before; it isn't code.
        continue
      } else if !line.isEmpty || !result.isEmpty {
        result.append(
          Line(kind: .context, oldNumber: old, newNumber: new, text: String(line.dropFirst())))
        old += 1
        new += 1
      }
    }
    // The patch ends with a newline, which isn't a line of its own.
    if result.last?.kind == .context, result.last?.text.isEmpty == true,
      patch.hasSuffix("\n")
    {
      result.removeLast()
    }
    return result
  }

  /// The first old and new line numbers from "@@ -52,9 +52,21 @@".
  static func starts(_ header: String) -> (Int, Int)? {
    let pattern = #"^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@"#
    guard let match = header.firstMatch(of: try! Regex(pattern)),
      let old = match.output[1].substring.flatMap({ Int($0) }),
      let new = match.output[2].substring.flatMap({ Int($0) })
    else { return nil }
    return (old, new)
  }
}
