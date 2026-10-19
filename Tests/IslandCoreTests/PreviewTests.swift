import Foundation
import Testing

@testable import IslandCore

struct PreviewTests {
  private func pr(_ id: String = "mine", head: String = "abc", previews: [PreviewDeploy]? = nil)
    -> PullRequest
  {
    PullRequest(
      id: id, number: 12, repository: "example/app", title: "A change",
      url: URL(string: "https://github.com/example/app/pull/12")!, headOID: head, author: "person",
      previews: previews)
  }

  private let ready = PreviewDeploy(
    name: "app", state: .ready, url: URL(string: "https://app-git-12.vercel.app"))

  @Test func deploymentsBecomeOnePreviewPerProject() {
    let previews = PreviewDeploy.from([
      ("Preview – app", "PENDING", nil),
      ("Preview – app", "SUCCESS", "https://app-1.vercel.app"),
      ("Preview – docs", "INACTIVE", "https://docs-old.vercel.app"),
      ("Production", "SUCCESS", "https://app.example.com"),
      ("deploy-preview", "FAILURE", "https://ignored.netlify.app"),
      ("Preview - web", "SUCCESS", "http://insecure.example.com"),
    ])
    #expect(previews.map(\.name) == ["app", "deploy-preview", "web"])
    #expect(previews[0].state == .ready && previews[0].url?.host() == "app-1.vercel.app")
    // Only a ready preview carries a link, and only over https.
    #expect(previews[1].state == .failed && previews[1].url == nil)
    #expect(previews[2].url == nil)
  }

  @Test func aPushThatSkipsAProjectKeepsItsEarlierPreview() {
    // As on a monorepo PR: the last push only touched one app, so Vercel retired the others'
    // deploys on the new commit and built nothing for the main app.
    let previews = PreviewDeploy.from(commits: [
      (
        "old",
        [
          ("Preview – web", "SUCCESS", "https://web-1.vercel.app"),
          ("Preview – docs", "SUCCESS", "https://docs-1.vercel.app"),
          ("Preview – api", "SUCCESS", "https://api-1.vercel.app"),
        ]
      ),
      (
        "new",
        [
          ("Preview – docs", "INACTIVE", "https://docs-2.vercel.app"),
          ("Preview – api", "PENDING", nil),
        ]
      ),
    ])
    #expect(previews.map(\.name) == ["web", "docs", "api"])
    #expect(previews[0].commit == "old" && previews[0].url?.host() == "web-1.vercel.app")
    #expect(previews[1].commit == "old" && previews[1].state == .ready)
    // A project the push did touch shows its new build.
    #expect(previews[2].commit == "new" && previews[2].state == .building)
  }

  @Test func readsByIDCarryPreviewsAndSearchesDont() throws {
    var row: [String: Any] = [
      "id": "PR", "number": 1, "title": "t", "url": "https://github.com/example/app/pull/1",
      "state": "OPEN", "updatedAt": "2026-10-13T10:00:00Z",
      "repository": ["nameWithOwner": "example/app"],
    ]
    #expect(try GitHubService.decode(row).previews == nil)
    row["recentCommits"] = [
      "nodes": [
        [
          "commit": [
            "oid": "abc",
            "deployments": [
              "nodes": [
                [
                  "environment": "Preview – app",
                  "latestStatus": [
                    "state": "SUCCESS", "environmentUrl": "https://app-1.vercel.app",
                  ],
                ]
              ]
            ],
          ]
        ]
      ]
    ]
    #expect(try GitHubService.decode(row).readyPreviews.map(\.name) == ["app"])
    #expect(try GitHubService.decode(row).previews?.first?.commit == "abc")
  }

  private func events(_ before: PullRequest, _ after: PullRequest) -> [IslandEvent] {
    GitHubChanges.events(
      previous: GitHubSnapshot(login: "person", pullRequests: [before]),
      current: GitHubSnapshot(login: "person", pullRequests: [after]))
  }

  @Test func aPreviewOfYourPRAnnouncesWhenItBecomesReady() {
    let building = pr(previews: [PreviewDeploy(name: "app", state: .building)])
    let found = events(building, pr(previews: [ready]))
    #expect(found.map(\.kind) == [.previewReady])
    // The banner opens the preview itself.
    #expect(found.first?.url == ready.url && found.first?.note == "app")
    #expect(events(pr(previews: [ready]), pr(previews: [ready])).isEmpty)
    // A new commit's preview announces again.
    #expect(
      events(pr(previews: [ready]), pr(head: "def", previews: [ready])).map(\.kind) == [
        .previewReady
      ])
  }

  @Test func anEarlierCommitsPreviewDoesNotAnnounceAfterAPush() {
    var built = ready
    built.commit = "abc"
    // After the push, the new commit has no preview of its own yet.
    #expect(events(pr(previews: [built]), pr(head: "def", previews: [built])).isEmpty)
    // Its own preview announces once it's ready.
    var rebuilt = ready
    rebuilt.commit = "def"
    #expect(
      events(pr(head: "def", previews: [built]), pr(head: "def", previews: [rebuilt])).map(\.kind)
        == [.previewReady])
  }

  @Test func previewsStayQuietWhenFirstReadOrNotYours() {
    // Never read before, as after updating GitIsle: the preview may be hours old.
    #expect(events(pr(), pr(previews: [ready])).isEmpty)
    var theirs = pr(previews: [])
    theirs.author = "someone-else"
    var theirsReady = theirs
    theirsReady.previews = [ready]
    #expect(events(theirs, theirsReady).isEmpty)
  }
}
