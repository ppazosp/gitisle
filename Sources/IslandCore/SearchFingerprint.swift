import Foundation

/// What the open-PR searches find, which GitHub prices at one point for all of them: each PR's
/// last update and the searches that found it. Comparing two names the PRs to read again, so a
/// refresh reads those by ID instead of running every search in full.
///
/// It can't see what moves without touching a PR's update time, such as checks finishing or the
/// base branch moving on; active PRs refresh on their own, and a full search runs periodically.
public struct SearchFingerprint: Codable, Equatable, Sendable {
  public struct Entry: Codable, Equatable, Sendable {
    public var updatedAt: String
    /// The searches that found the PR, sorted.
    public var searches: [String]
  }

  /// The most PRs one search reports for a point; a search that finds more can't be compared.
  public static let pageSize = 100

  public private(set) var entries: [String: Entry] = [:]

  public init() {}

  public mutating func add(id: String, updatedAt: String, search: String) {
    var entry = entries[id] ?? Entry(updatedAt: updatedAt, searches: [])
    entry.updatedAt = max(entry.updatedAt, updatedAt)
    if !entry.searches.contains(search) {
      entry.searches.append(search)
      entry.searches.sort()
    }
    entries[id] = entry
  }

  /// PRs that appeared, disappeared, changed, or moved between searches since `previous`.
  public func changedIDs(since previous: SearchFingerprint) -> [String] {
    Set(entries.keys).union(previous.entries.keys)
      .filter { entries[$0] != previous.entries[$0] }
      .sorted()
  }

  public func found(_ id: String, by search: String) -> Bool {
    entries[id]?.searches.contains(search) == true
  }
}
