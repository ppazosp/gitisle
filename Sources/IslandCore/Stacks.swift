import Foundation

/// PRs built on top of each other: a PR whose base branch is another open PR's branch, in the
/// same repository, sits on that PR.
public enum PRStacks {
  public struct Link: Equatable, Sendable {
    /// The open PR this one is built on.
    public var parent: PullRequest?
    /// Open PRs built on this one, by number.
    public var children: [PullRequest]
    /// How many PRs sit below this one.
    public var depth: Int
    /// A merged PR whose branch this one still targets: GitHub didn't move it to the merged
    /// PR's base, so it needs retargeting or a rebase.
    public var mergedParent: PullRequest?

    public var isStacked: Bool { parent != nil || !children.isEmpty }
  }

  /// Each open PR's place in its stack, by ID. Only PRs in a stack, or with a merged parent,
  /// appear.
  public static func links(_ pullRequests: [PullRequest]) -> [String: Link] {
    let open = pullRequests.filter { $0.state == "OPEN" }
    var byHead: [String: PullRequest] = [:]
    for pr in open {
      if let head = pr.headRefName { byHead["\(pr.repository)\n\(head)"] = pr }
    }
    var mergedByHead: [String: PullRequest] = [:]
    for pr in pullRequests where pr.state == "MERGED" {
      guard let head = pr.headRefName else { continue }
      let key = "\(pr.repository)\n\(head)"
      if (mergedByHead[key]?.mergedAt ?? .distantPast) < (pr.mergedAt ?? .distantPast) {
        mergedByHead[key] = pr
      }
    }
    func parent(of pr: PullRequest) -> PullRequest? {
      guard let base = pr.baseRefName, let parent = byHead["\(pr.repository)\n\(base)"],
        parent.id != pr.id
      else { return nil }
      return parent
    }
    var children: [String: [PullRequest]] = [:]
    for pr in open {
      if let parent = parent(of: pr) { children[parent.id, default: []].append(pr) }
    }
    var links: [String: Link] = [:]
    for pr in open {
      var depth = 0
      var seen: Set<String> = [pr.id]
      var below = parent(of: pr)
      while let current = below, seen.insert(current.id).inserted {
        depth += 1
        below = parent(of: current)
      }
      let merged =
        parent(of: pr) == nil
        ? pr.baseRefName.flatMap { mergedByHead["\(pr.repository)\n\($0)"] } : nil
      let link = Link(
        parent: parent(of: pr),
        children: (children[pr.id] ?? []).sorted { $0.number < $1.number }, depth: depth,
        mergedParent: merged)
      if link.isStacked || merged != nil { links[pr.id] = link }
    }
    return links
  }

  /// `pullRequests` with each stack kept together, bottom first, where its first member was.
  public static func ordered(_ pullRequests: [PullRequest]) -> [PullRequest] {
    let links = links(pullRequests)
    let present = Set(pullRequests.map(\.id))
    var emitted = Set<String>()
    var result: [PullRequest] = []
    func emit(_ pr: PullRequest) {
      guard present.contains(pr.id), emitted.insert(pr.id).inserted else { return }
      result.append(pr)
      for child in links[pr.id]?.children ?? [] { emit(child) }
    }
    for pr in pullRequests where !emitted.contains(pr.id) {
      // Start from the bottom of this PR's stack, among the PRs shown.
      var root = pr
      var seen: Set<String> = [pr.id]
      while let parent = links[root.id]?.parent, present.contains(parent.id),
        seen.insert(parent.id).inserted
      {
        root = parent
      }
      emit(root)
      emit(pr)
    }
    return result
  }

  /// The PRs in `pr`'s stack, bottom first: those below it, it, and those above it.
  public static func chain(of pr: PullRequest, links: [String: Link]) -> [PullRequest] {
    var below: [PullRequest] = []
    var seen: Set<String> = [pr.id]
    var current = links[pr.id]?.parent
    while let parent = current, seen.insert(parent.id).inserted {
      below.insert(parent, at: 0)
      current = links[parent.id]?.parent
    }
    var above: [PullRequest] = []
    var next = links[pr.id]?.children ?? []
    while let child = next.first, seen.insert(child.id).inserted {
      above.append(child)
      next = links[child.id]?.children ?? []
    }
    return below + [pr] + above
  }
}
