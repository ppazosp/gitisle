import Foundation
import Testing

@testable import IslandCore

struct GitHubConnectionTests {
  private let gh = URL(fileURLWithPath: "/opt/homebrew/bin/gh")

  @Test func reportsAMissingCLI() async {
    let result = await GitHubConnection.check(locate: { nil }, login: { _ in Data() })
    #expect(result == .notInstalled)
  }

  @Test func readsTheSignedInAccount() async {
    let result = await GitHubConnection.check(
      locate: { gh }, login: { _ in Data("octocat\n".utf8) })
    #expect(result == .connected(login: "octocat"))
  }

  @Test func treatsTheSignInPromptAsSignedOut() async {
    let result = await GitHubConnection.check(
      locate: { gh },
      login: { _ in
        throw ProcessFailure.failed("To get started with GitHub CLI, please run:  gh auth login")
      })
    #expect(result == .signedOut)
  }

  @Test func treatsAnEmptyAnswerAsSignedOut() async {
    let result = await GitHubConnection.check(locate: { gh }, login: { _ in Data(" \n".utf8) })
    #expect(result == .signedOut)
  }

  @Test func keepsOtherFailures() async {
    let result = await GitHubConnection.check(
      locate: { gh },
      login: { _ in throw ProcessFailure.failed("error connecting to api.github.com") })
    #expect(result == .failed("error connecting to api.github.com"))
  }
}
