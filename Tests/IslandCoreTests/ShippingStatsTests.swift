import Foundation
import Testing

@testable import IslandCore

struct ShippingStatsTests {
  private let now = Date(timeIntervalSince1970: 1_791_720_000)
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
    return calendar
  }

  /// A PR merged `mergedAgo` seconds ago, opened `took` seconds before that.
  private func merged(
    _ id: String, repository: String = "a/web", mergedAgo: TimeInterval, took: TimeInterval,
    lines: (Int, Int) = (10, 5), author: String = "me"
  ) -> PullRequest {
    let mergedAt = now.addingTimeInterval(-mergedAgo)
    return PullRequest(
      id: id, number: 1, repository: repository, title: id,
      url: URL(string: "https://github.com/a/web/pull/1")!, state: "MERGED", updatedAt: mergedAt,
      mergedAt: mergedAt, author: author, createdAt: mergedAt.addingTimeInterval(-took),
      additions: lines.0, deletions: lines.1)
  }

  @Test func speedSizeAndRepositoriesCoverTheWindow() {
    let hour = 3600.0
    let prs = [
      merged("fast", mergedAgo: 1 * hour, took: 0.5 * hour, lines: (40, 10)),
      merged("slow", repository: "a/api", mergedAgo: 2 * hour, took: 30 * hour, lines: (300, 100)),
      merged("middle", mergedAgo: 3 * hour, took: 2 * hour, lines: (100, 20)),
      // Ten days ago: in 30 days, not in 7.
      merged("old", repository: "b/docs", mergedAgo: 240 * hour, took: 4 * hour),
      // Someone else's merge, and a PR still open: neither counts.
      merged("theirs", mergedAgo: 1 * hour, took: 1 * hour, author: "them"),
      PullRequest(
        id: "open", number: 2, repository: "a/web", title: "open",
        url: URL(string: "https://github.com/a/web/pull/2")!, author: "me"),
    ]
    let week = ShippingStats(
      pullRequests: prs, login: "me", days: 7, now: now, calendar: calendar)
    #expect(week.merged == 3)
    #expect(week.medianTimeToMerge == 2 * hour)
    #expect(week.fastest == 0.5 * hour)
    #expect(week.slowest == 30 * hour)
    #expect(week.additions == 440 && week.deletions == 130)
    #expect(week.medianSize == 120)
    #expect(week.repositories.map(\.name) == ["a/web", "a/api"])
    #expect(week.repositories.map(\.merged) == [2, 1])

    let month = ShippingStats(
      pullRequests: prs, login: "me", days: 30, now: now, calendar: calendar)
    #expect(month.merged == 4)
    // Ties keep a stable order, by name.
    #expect(month.repositories.map(\.name) == ["a/web", "a/api", "b/docs"])
    #expect(month.dailyLines.count == 30 && month.dailyTimeToMerge.count == 30)
    #expect(month.dailyLines.last?.value == 570)
    #expect(month.dailyLines.reduce(0) { $0 + $1.value } == 585)
  }

  @Test func anEmptyWindowHasNoSpeed() {
    let stats = ShippingStats(pullRequests: [], login: "me", days: 1, now: now, calendar: calendar)
    #expect(stats.merged == 0)
    #expect(stats.medianTimeToMerge == nil && stats.medianSize == nil)
    #expect(stats.repositories.isEmpty)
    #expect(stats.dailyLines.allSatisfy { $0.value == 0 })
  }
}
