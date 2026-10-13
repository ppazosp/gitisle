import Foundation
import Testing

@testable import IslandCore

struct SearchFingerprintTests {
  @Test func changedIDsNameEveryDifference() {
    var before = SearchFingerprint()
    before.add(id: "same", updatedAt: "2026-10-13T10:00:00Z", search: "mine")
    before.add(id: "edited", updatedAt: "2026-10-13T10:00:00Z", search: "mine")
    before.add(id: "gone", updatedAt: "2026-10-13T10:00:00Z", search: "mine")
    before.add(id: "reviewed", updatedAt: "2026-10-13T10:00:00Z", search: "reviews")
    var after = SearchFingerprint()
    after.add(id: "same", updatedAt: "2026-10-13T10:00:00Z", search: "mine")
    after.add(id: "edited", updatedAt: "2026-10-13T10:05:00Z", search: "mine")
    after.add(id: "reviewed", updatedAt: "2026-10-13T10:00:00Z", search: "repos")
    after.add(id: "new", updatedAt: "2026-10-13T10:05:00Z", search: "mine")
    #expect(after.changedIDs(since: before) == ["edited", "gone", "new", "reviewed"])
    #expect(after.changedIDs(since: after).isEmpty)
  }

  @Test func aPRFoundByTwoSearchesKeepsBoth() {
    var first = SearchFingerprint()
    first.add(id: "pr", updatedAt: "2026-10-13T10:00:00Z", search: "reviews")
    first.add(id: "pr", updatedAt: "2026-10-13T10:00:00Z", search: "repos")
    var second = SearchFingerprint()
    second.add(id: "pr", updatedAt: "2026-10-13T10:00:00Z", search: "repos")
    second.add(id: "pr", updatedAt: "2026-10-13T10:00:00Z", search: "reviews")
    #expect(first == second)
    #expect(first.found("pr", by: "reviews") && first.found("pr", by: "repos"))
    #expect(!first.found("pr", by: "mine") && !first.found("other", by: "reviews"))
  }

  @Test func snapshotsKeepTheirFingerprintAndOlderOnesLoadWithout() throws {
    var fingerprint = SearchFingerprint()
    fingerprint.add(id: "pr", updatedAt: "2026-10-13T10:00:00Z", search: "mine")
    let snapshot = GitHubSnapshot(login: "person", pullRequests: [], searchFingerprint: fingerprint)
    let decoded = try JSONDecoder().decode(
      GitHubSnapshot.self, from: try JSONEncoder().encode(snapshot))
    #expect(decoded.searchFingerprint == fingerprint)
    let legacy = Data(
      #"{"login":"person","pullRequests":[],"fetchedAt":0,"selection":"","isLimited":false}"#.utf8)
    #expect(try JSONDecoder().decode(GitHubSnapshot.self, from: legacy).searchFingerprint == nil)
  }
}
