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

  @Test func readsByIDCarryPreviewsAndSearchesDont() throws {
    var row: [String: Any] = [
      "id": "PR", "number": 1, "title": "t", "url": "https://github.com/example/app/pull/1",
      "state": "OPEN", "updatedAt": "2026-10-13T10:00:00Z",
      "repository": ["nameWithOwner": "example/app"],
    ]
    #expect(try GitHubService.decode(row).previews == nil)
    row["commits"] = [
      "nodes": [
        [
          "commit": [
            "deployments": [
              "nodes": [
                [
                  "environment": "Preview – app",
                  "latestStatus": [
                    "state": "SUCCESS", "environmentUrl": "https://app-1.vercel.app",
                  ],
                ]
              ]
            ]
          ]
        ]
      ]
    ]
    #expect(try GitHubService.decode(row).readyPreviews.map(\.name) == ["app"])
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
