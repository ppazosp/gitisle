import CryptoKit
import Foundation
import Testing

@testable import IslandCore

struct AppReleaseTests {
  private func response(
    tag: String = "v0.1.4",
    assets: [String] = ["GitIsle.zip", "GitIsle.zip.sig", "GitIsle.dmg", "checksums.txt"],
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

  @Test func waitsUntilTheAppItsSignatureAndChecksumsAreAttached() throws {
    #expect(try AppRelease.latest(from: response(assets: [])) == nil)
    #expect(try AppRelease.latest(from: response(assets: ["GitIsle.zip", "checksums.txt"])) == nil)
    #expect(
      try AppRelease.latest(from: response(assets: ["GitIsle.zip", "GitIsle.zip.sig"])) == nil)
  }

  @Test func acceptsOnlyArchivesSignedByTheReleaseKey() throws {
    let key = Curve25519.Signing.PrivateKey()
    let trusted = key.publicKey.rawRepresentation.base64EncodedString()
    let archive = Data("GitIsle.app".utf8)
    let signature = try key.signature(for: archive).base64EncodedString()
    #expect(AppRelease.isSigned(archive, signature: signature, key: trusted))
    #expect(AppRelease.isSigned(archive, signature: signature + "\n", key: trusted))
    #expect(!AppRelease.isSigned(Data("tampered".utf8), signature: signature, key: trusted))
    let stranger = try Curve25519.Signing.PrivateKey().signature(for: archive)
    #expect(!AppRelease.isSigned(archive, signature: stranger.base64EncodedString(), key: trusted))
    #expect(!AppRelease.isSigned(archive, signature: "not base64", key: trusted))
    #expect(!AppRelease.isSigned(archive, signature: signature, key: "short"))
    // The release key is a real Ed25519 public key.
    let raw = try #require(Data(base64Encoded: AppRelease.signingKey))
    #expect((try? Curve25519.Signing.PublicKey(rawRepresentation: raw)) != nil)
    #expect(!AppRelease.isSigned(archive, signature: signature))
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
