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

extension Diff {
  /// A piece of a changed line, marked when it differs from the line it replaced.
  public struct Segment: Equatable, Sendable {
    public var text: String
    public var changed: Bool

    public init(_ text: String, changed: Bool) {
      self.text = text
      self.changed = changed
    }
  }

  /// One row of the side-by-side view: the old line on the left, the new on the right. A
  /// hunk header spans both; an added or removed line leaves the other side empty.
  public struct SplitRow: Equatable, Sendable {
    public var left: Int?
    public var right: Int?
    public var hunk: Int?
  }

  /// Rows for the side-by-side view, as indexes into `lines`. Removed lines pair with the
  /// added lines that follow them, in order, so a changed line sits opposite its new version.
  public static func split(_ lines: [Line]) -> [SplitRow] {
    var rows: [SplitRow] = []
    var index = 0
    while index < lines.count {
      switch lines[index].kind {
      case .hunk:
        rows.append(SplitRow(hunk: index))
        index += 1
      case .context:
        rows.append(SplitRow(left: index, right: index))
        index += 1
      case .removed, .added:
        let (removed, added, end) = change(at: index, in: lines)
        for row in 0..<max(removed.count, added.count) {
          rows.append(
            SplitRow(
              left: row < removed.count ? removed[row] : nil,
              right: row < added.count ? added[row] : nil))
        }
        index = end
      }
    }
    return rows
  }

  /// The words that changed in each paired line, by line index. Lines with no partner, and
  /// very long ones, are left out and show as wholly changed.
  public static func highlights(_ lines: [Line]) -> [Int: [Segment]] {
    var result: [Int: [Segment]] = [:]
    var index = 0
    while index < lines.count {
      guard lines[index].kind == .removed || lines[index].kind == .added else {
        index += 1
        continue
      }
      let (removed, added, end) = change(at: index, in: lines)
      for (old, new) in zip(removed, added) {
        guard let (left, right) = words(lines[old].text, lines[new].text) else { continue }
        result[old] = left
        result[new] = right
      }
      index = end
    }
    return result
  }

  /// A block of removed lines and the added lines after it, and where the block ends.
  private static func change(at start: Int, in lines: [Line]) -> ([Int], [Int], Int) {
    var index = start
    var removed: [Int] = []
    var added: [Int] = []
    while index < lines.count, lines[index].kind == .removed {
      removed.append(index)
      index += 1
    }
    while index < lines.count, lines[index].kind == .added {
      added.append(index)
      index += 1
    }
    return (removed, added, index)
  }

  /// Each line split into words and the rest, with the words not in common marked. Nil when
  /// the lines share almost nothing, where marking every word would only add noise.
  static func words(_ old: String, _ new: String) -> ([Segment], [Segment])? {
    let a = tokens(old)
    let b = tokens(new)
    guard a.count * b.count <= 40_000 else { return nil }
    // Longest common subsequence of tokens.
    var table = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
    for i in stride(from: a.count - 1, through: 0, by: -1) {
      for j in stride(from: b.count - 1, through: 0, by: -1) {
        table[i][j] = a[i] == b[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
      }
    }
    var keepA = Array(repeating: false, count: a.count)
    var keepB = Array(repeating: false, count: b.count)
    var i = 0
    var j = 0
    while i < a.count, j < b.count {
      if a[i] == b[j] {
        keepA[i] = true
        keepB[j] = true
        i += 1
        j += 1
      } else if table[i + 1][j] >= table[i][j + 1] {
        i += 1
      } else {
        j += 1
      }
    }
    // Similar lines share most of their words; spaces and punctuation don't count, since
    // almost any two lines of code share those.
    func isWord(_ token: String) -> Bool { token.first.map { $0.isLetter || $0.isNumber } ?? false }
    let shared = a.indices.filter { keepA[$0] && isWord(a[$0]) }.reduce(0) { $0 + a[$1].count }
    let wordsA = a.filter(isWord).reduce(0) { $0 + $1.count }
    let wordsB = b.filter(isWord).reduce(0) { $0 + $1.count }
    guard shared * 2 >= min(wordsA, wordsB), shared > 0 else { return nil }
    return (segments(a, keepA), segments(b, keepB))
  }

  /// Runs of letters, digits and underscores as words; every other character on its own.
  static func tokens(_ text: String) -> [String] {
    var result: [String] = []
    var word = ""
    for character in text {
      if character.isLetter || character.isNumber || character == "_" {
        word.append(character)
      } else {
        if !word.isEmpty { result.append(word) }
        word = ""
        result.append(String(character))
      }
    }
    if !word.isEmpty { result.append(word) }
    return result
  }

  private static func segments(_ tokens: [String], _ kept: [Bool]) -> [Segment] {
    var result: [Segment] = []
    for (token, keep) in zip(tokens, kept) {
      if let last = result.last, last.changed == !keep {
        result[result.count - 1].text += token
      } else {
        result.append(Segment(token, changed: !keep))
      }
    }
    return result
  }
}
