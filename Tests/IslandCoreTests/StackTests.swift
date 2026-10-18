import Foundation
import Testing

@testable import IslandCore

struct StackTests {
  private func pr(
    _ number: Int, head: String, base: String = "main", repository: String = "example/app",
    state: String = "OPEN"
  ) -> PullRequest {
    PullRequest(
      id: "PR\(number)-\(repository)", number: number, repository: repository,
      title: "PR \(number)",
      url: URL(string: "https://github.com/\(repository)/pull/\(number)")!, state: state,
      mergedAt: state == "MERGED" ? Date() : nil, headRefName: head, baseRefName: base)
  }

  @Test func prsOnEachOthersBranchesFormAStack() {
    let bottom = pr(1, head: "auth")
    let middle = pr(2, head: "auth-ui", base: "auth")
    let top = pr(3, head: "auth-docs", base: "auth-ui")
    let elsewhere = pr(9, head: "auth-ui-copy", base: "auth", repository: "other/app")
    let links = PRStacks.links([top, elsewhere, bottom, middle])
    #expect(links[bottom.id]?.children.map(\.number) == [2])
    #expect(links[middle.id]?.parent?.number == 1 && links[middle.id]?.depth == 1)
    #expect(links[top.id]?.depth == 2)
    // The same branch name in another repository isn't the same branch.
    #expect(links[elsewhere.id] == nil)
    #expect(PRStacks.chain(of: middle, links: links).map(\.number) == [1, 2, 3])
  }

  @Test func aPRWhoseParentMergedNeedsARestack() {
    let parent = pr(1, head: "auth", state: "MERGED")
    let child = pr(2, head: "auth-ui", base: "auth")
    let link = PRStacks.links([parent, child])[child.id]
    #expect(link?.mergedParent?.number == 1 && link?.parent == nil)
  }

  @Test func branchesPointingAtEachOtherDontLoop() {
    let a = pr(1, head: "a", base: "b")
    let b = pr(2, head: "b", base: "a")
    let links = PRStacks.links([a, b])
    #expect(links.count == 2)
    #expect(PRStacks.ordered([a, b]).count == 2)
    #expect(PRStacks.chain(of: a, links: links).count == 2)
  }

  @Test func listsKeepAStackTogetherBottomFirst() {
    let bottom = pr(1, head: "auth")
    let middle = pr(2, head: "auth-ui", base: "auth")
    let top = pr(3, head: "auth-docs", base: "auth-ui")
    let other = pr(4, head: "fix")
    #expect(PRStacks.ordered([top, other, bottom, middle]).map(\.number) == [1, 2, 3, 4])
    // Without its parent shown, a stacked PR keeps its place.
    #expect(PRStacks.ordered([other, middle]).map(\.number) == [4, 2])
  }

  @Test func branchesDecodeFromTheSearch() throws {
    let row: [String: Any] = [
      "id": "PR", "number": 1, "title": "t", "url": "https://github.com/example/app/pull/1",
      "state": "OPEN", "updatedAt": "2026-10-13T10:00:00Z",
      "repository": ["nameWithOwner": "example/app"], "headRefName": "auth-ui",
      "baseRefName": "auth",
    ]
    let decoded = try GitHubService.decode(row)
    #expect(decoded.headRefName == "auth-ui" && decoded.baseRefName == "auth")
  }
}
