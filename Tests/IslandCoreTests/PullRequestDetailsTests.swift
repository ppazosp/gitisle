import Foundation
import Testing

@testable import IslandCore

struct PullRequestDetailsTests {
  private func checkRun(
    _ name: String, workflow: String = "CI", conclusion: String? = "FAILURE",
    status: String = "COMPLETED", annotations: [[String: Any]] = []
  ) -> [String: Any] {
    [
      "__typename": "CheckRun", "name": name, "status": status, "conclusion": conclusion as Any,
      "detailsUrl": "https://github.com/example/app/actions/runs/1/job/2",
      "startedAt": "2026-10-13T10:00:00Z", "completedAt": "2026-10-13T10:05:01Z",
      "annotations": ["nodes": annotations],
      "checkSuite": ["workflowRun": ["workflow": ["name": workflow]]],
    ]
  }

  private func annotation(_ path: String, _ line: Int, _ message: String, level: String = "FAILURE")
    -> [String: Any]
  {
    [
      "annotationLevel": level, "path": path, "message": message,
      "location": ["start": ["line": line]],
    ]
  }

  /// The shape a failed run on a real PR came back in.
  private var node: [String: Any] {
    [
      "id": "PR1",
      "author": [
        "login": "person", "avatarUrl": "https://avatars.githubusercontent.com/u/1?v=4",
      ],
      "baseRefName": "main", "headRefName": "feature", "createdAt": "2026-10-13T09:00:00Z",
      "additions": 120, "deletions": 8, "changedFiles": 2,
      "files": [
        "nodes": [
          [
            "path": "Sources/Cache.swift", "additions": 100, "deletions": 8,
            "changeType": "MODIFIED",
          ],
          ["path": "Sources/New.swift", "additions": 20, "deletions": 0, "changeType": "ADDED"],
        ]
      ],
      "reviewRequests": [
        "nodes": [
          [
            "requestedReviewer": [
              "login": "maya", "avatarUrl": "https://evil.example/u/2.png",
            ]
          ],
          ["requestedReviewer": ["name": "core"]],
        ]
      ],
      "latestReviews": [
        "nodes": [
          ["author": ["login": "sam"], "state": "APPROVED", "submittedAt": "2026-10-13T11:00:00Z"]
        ]
      ],
      "comments": ["totalCount": 7],
      "commits": [
        "totalCount": 3,
        "nodes": [
          [
            "commit": [
              "statusCheckRollup": [
                "contexts": [
                  "nodes": [
                    checkRun(
                      "CI Success",
                      annotations: [
                        annotation(".github", 30, "Process completed with exit code 1.")
                      ]),
                    checkRun("lint", conclusion: "SUCCESS"),
                    checkRun(
                      "unit",
                      annotations: [
                        annotation(".github", 25684, "Process completed with exit code 1."),
                        annotation(
                          "apps/web/lib/logger.ts", 24,
                          "Error: [vitest] No \"isVercelIntegration\" export is defined"),
                        annotation(
                          "apps/web/lib/logger.ts", 24,
                          "Error: [vitest] No \"isVercelIntegration\" export is defined"),
                        annotation(
                          ".github", 1, "The ubuntu-latest label will migrate", level: "NOTICE"),
                      ]),
                    checkRun("e2e", conclusion: nil, status: "IN_PROGRESS"),
                    [
                      "__typename": "StatusContext", "context": "Vercel", "state": "FAILURE",
                      "targetUrl": "https://vercel.com/example/app/1",
                      "description": "Deployment has failed",
                    ],
                  ]
                ]
              ]
            ]
          ]
        ],
      ],
    ]
  }

  @Test func detailsDecodeEverythingThePageShows() throws {
    let details = try GitHubService.decodeDetails(node)
    #expect(details.author == "person")
    #expect(details.authorAvatar?.host() == "avatars.githubusercontent.com")
    #expect(details.additions == 120 && details.deletions == 8 && details.changedFiles == 2)
    #expect(details.files.map(\.path) == ["Sources/Cache.swift", "Sources/New.swift"])
    #expect(details.files.map(\.kind) == [.modified, .added])
    #expect(details.files.map(\.folder) == ["Sources/", "Sources/"])
    // Avatars come only from GitHub's avatar host.
    #expect(details.requestedReviewers == [.init(name: "maya"), .init(name: "core")])
    #expect(details.reviews.map(\.state) == ["APPROVED"])
    #expect(details.commentCount == 7)
    #expect(details.commitCount == 3)
    #expect(details.checks.count == 5)
  }

  @Test func errorsDropRunnerNoiseAndRepeats() throws {
    let unit = try #require(
      try GitHubService.decodeDetails(node).checks.first { $0.name == "unit" })
    #expect(unit.errors.map(\.location) == ["logger.ts:24"])
    #expect(
      Check.Annotation(path: ".github", line: 2190, message: "Type error\n at x").location == nil)
    #expect(
      Check.Annotation(path: "a.ts", line: 1, message: "TypeError: x\n ❯ trace").headline
        == "TypeError: x")
    #expect(
      Check(name: "typecheck / typecheck", workflow: "CI", outcome: .failed).title
        == "CI / typecheck")
    #expect(unit.errors.first?.message.hasPrefix("Error: [vitest]") == true)
    #expect(unit.title == "CI / unit" && unit.duration == 301)
  }

  @Test func realFailuresComeFirstAndSummaryChecksLast() throws {
    let details = try GitHubService.decodeDetails(node)
    #expect(details.sortedChecks.map(\.name) == ["unit", "Vercel", "CI Success", "e2e", "lint"])
    #expect(details.failingChecks.map(\.name) == ["unit", "Vercel"])
    let vercel = try #require(details.checks.first { $0.name == "Vercel" })
    #expect(vercel.summary == "Deployment has failed" && vercel.workflow == nil)
  }

  @Test func aCheckThatOnlyCountsOthersIsASummary() {
    let gate = Check(
      name: "All required checks pass", outcome: .failed,
      errors: [.init(path: ".github", line: 119, message: "1 job(s) failed: contributor-check")])
    let real = Check(name: "check-attribution", outcome: .failed)
    #expect(gate.isSummary && !real.isSummary)
    let details = PullRequestDetails(id: "PR", checks: [gate, real])
    // The real failure leads even though it reports no errors of its own.
    #expect(details.failingChecks.map(\.name) == ["check-attribution"])
  }

  @Test func outcomesCoverEveryStateGitHubReports() {
    #expect(Check.outcome(status: "COMPLETED", conclusion: "TIMED_OUT") == .failed)
    #expect(Check.outcome(status: "COMPLETED", conclusion: "SUCCESS") == .passed)
    #expect(Check.outcome(status: "COMPLETED", conclusion: "SKIPPED") == .skipped)
    #expect(Check.outcome(status: "QUEUED", conclusion: nil) == .running)
    #expect(Check.outcome(state: "ERROR") == .failed && Check.outcome(state: "PENDING") == .running)
  }
}
