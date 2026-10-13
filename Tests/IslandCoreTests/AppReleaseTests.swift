import Foundation
import Testing

@testable import IslandCore

struct AppReleaseTests {
  private func response(
    tag: String = "v0.1.4", assets: [String] = ["GitIsle.zip", "GitIsle.dmg", "checksums.txt"],
    draft: Bool = false, prerelease: Bool = false
  ) -> Data {
    let list = assets.map {
      #"{"name":"\#($0)","browser_download_url":"https://example.com/\#($0)"}"#
    }
    return Data(
      """
      {"tag_name":"\(tag)","draft":\(draft),"prerelease":\(prerelease),"html_url":"https://example.com",
       "assets":[\(list.joined(separator: ","))]}
      """.utf8)
  }

  @Test func readsTheLatestRelease() throws {
    #expect(try AppRelease.latest(from: response()) == AppRelease(tag: "v0.1.4", version: "0.1.4"))
  }

  @Test func waitsUntilTheAppAndItsChecksumsAreAttached() throws {
    #expect(try AppRelease.latest(from: response(assets: [])) == nil)
    #expect(try AppRelease.latest(from: response(assets: ["GitIsle.zip"])) == nil)
    #expect(try AppRelease.latest(from: response(assets: ["checksums.txt"])) == nil)
  }

  @Test func ignoresDraftsPrereleasesAndOddTags() throws {
    #expect(try AppRelease.latest(from: response(draft: true)) == nil)
    #expect(try AppRelease.latest(from: response(prerelease: true)) == nil)
    #expect(try AppRelease.latest(from: response(tag: "nightly")) == nil)
    #expect(try AppRelease.latest(from: response(tag: "v1.0.0-beta")) == nil)
    #expect(throws: (any Error).self) { try AppRelease.latest(from: Data("{}".utf8)) }
  }

  @Test func comparesVersionsByNumber() {
    #expect(AppRelease.isNewer("0.1.4", than: "0.1.3"))
    #expect(AppRelease.isNewer("0.1.10", than: "0.1.9"))
    #expect(AppRelease.isNewer("0.2", than: "0.1.9"))
    #expect(AppRelease.isNewer("1.0.0", than: "0.9.9"))
    #expect(!AppRelease.isNewer("0.1.3", than: "0.1.3"))
    #expect(!AppRelease.isNewer("0.1.3", than: "0.1.3.0"))
    #expect(!AppRelease.isNewer("0.1.2", than: "0.1.3"))
    #expect(!AppRelease.isNewer("0.1.4", than: ""))
    #expect(!AppRelease.isNewer("", than: "0.1.3"))
    #expect(!AppRelease.isNewer("0.1.x", than: "0.1.3"))
  }

  @Test func findsTheChecksumForAFile() {
    let zip = String(repeating: "a", count: 64)
    let dmg = String(repeating: "B", count: 64)
    let sums = "\(zip)  GitIsle.zip\n\(dmg) *GitIsle.dmg\n"
    #expect(AppRelease.checksum(of: "GitIsle.zip", in: sums) == zip)
    #expect(AppRelease.checksum(of: "GitIsle.dmg", in: sums) == dmg.lowercased())
    #expect(AppRelease.checksum(of: "other.zip", in: sums) == nil)
    #expect(AppRelease.checksum(of: "GitIsle.zip", in: "abc  GitIsle.zip") == nil)
  }
}
