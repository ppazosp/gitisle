import Foundation

/// A PR's changed files as GitHub's file tree shows them: folders before files, and a chain
/// of folders that hold only one folder joined into one line, such as "apps/omnia/lib".
public enum FileTree {
  public struct Row: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
      /// `name` may span several folders; `path` is the full path to its last one, which
      /// identifies it when folding.
      case folder(name: String, path: String, folded: Bool)
      case file(PullRequestDetails.FileChange)
    }

    public var depth: Int
    public var kind: Kind
  }

  /// The rows to show, in order. Folders in `folded` show without what's inside them.
  public static func rows(_ files: [PullRequestDetails.FileChange], folded: Set<String> = [])
    -> [Row]
  {
    var root = Node()
    for file in files {
      root.insert(file, parts: file.path.split(separator: "/").dropLast().map(String.init))
    }
    var rows: [Row] = []
    root.append(to: &rows, depth: 0, path: "", folded: folded)
    return rows
  }

  private struct Node {
    /// Folder names in the order they first appear; GitHub lists files by path.
    var order: [String] = []
    var folders: [String: Node] = [:]
    var files: [PullRequestDetails.FileChange] = []

    mutating func insert(_ file: PullRequestDetails.FileChange, parts: [String]) {
      guard let first = parts.first else {
        files.append(file)
        return
      }
      if folders[first] == nil { order.append(first) }
      folders[first, default: Node()].insert(file, parts: Array(parts.dropFirst()))
    }

    func append(to rows: inout [Row], depth: Int, path: String, folded: Set<String>) {
      for name in order {
        guard var node = folders[name] else { continue }
        var label = name
        var full = path.isEmpty ? name : "\(path)/\(name)"
        // A folder holding only one folder joins it on one line.
        while node.files.isEmpty, node.order.count == 1, let only = node.order.first,
          let next = node.folders[only]
        {
          label += "/\(only)"
          full += "/\(only)"
          node = next
        }
        let isFolded = folded.contains(full)
        rows.append(Row(depth: depth, kind: .folder(name: label, path: full, folded: isFolded)))
        if !isFolded { node.append(to: &rows, depth: depth + 1, path: full, folded: folded) }
      }
      rows += files.map { Row(depth: depth, kind: .file($0)) }
    }
  }
}
