import CryptoKit
import Foundation

/// A published GitIsle release that an installed copy can update to.
public struct AppRelease: Equatable, Sendable {
  public static let repository = "ppazosp/gitisle"
  /// The release files an update needs: the app, its signature, and its checksums.
  public static let archive = "GitIsle.zip"
  public static let signature = "GitIsle.zip.sig"
  public static let checksums = "checksums.txt"
  /// Ed25519 public key for release signatures. The private key is the repository's
  /// `GITISLE_SIGNING_KEY` secret; only the release workflow signs with it.
  public static let signingKey = "xj86zYHI4tbnZRukAzO00X7WmdvH0ssWB03hR6H9QOY="

  public var tag: String
  public var version: String

  public init(tag: String, version: String) {
    self.tag = tag
    self.version = version
  }

  /// Reads GitHub's latest-release response. A release counts only once it has all its
  /// files, since the build uploads them several minutes after the release appears.
  public static func latest(from data: Data) throws -> AppRelease? {
    struct Response: Decodable {
      struct Asset: Decodable { let name: String }
      let tagName: String
      let draft: Bool?
      let prerelease: Bool?
      let assets: [Asset]
    }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let response = try decoder.decode(Response.self, from: data)
    let names = Set(response.assets.map(\.name))
    guard response.draft != true, response.prerelease != true,
      names.isSuperset(of: [archive, signature, checksums]),
      let version = version(response.tagName)
    else { return nil }
    return AppRelease(tag: response.tagName, version: version)
  }

  /// Whether `signature` (base64, as in `GitIsle.zip.sig`) is a valid Ed25519 signature of
  /// `data` by the key that signs GitIsle releases.
  public static func isSigned(
    _ data: Data, signature: String, key: String = signingKey
  ) -> Bool {
    guard
      let signature = Data(
        base64Encoded: signature.trimmingCharacters(in: .whitespacesAndNewlines)),
      let raw = Data(base64Encoded: key),
      let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw)
    else { return false }
    return key.isValidSignature(signature, for: data)
  }

  /// Whether `candidate` is a later version than `current`, comparing numbers part by part.
  /// Anything that isn't a plain version never counts as newer.
  public static func isNewer(_ candidate: String, than current: String) -> Bool {
    guard let new = parts(candidate), let old = parts(current) else { return false }
    for index in 0..<max(new.count, old.count) {
      let (left, right) = (part(new, index), part(old, index))
      if left != right { return left > right }
    }
    return false
  }

  /// The SHA-256 that `checksums.txt` lists for a file, in `shasum -a 256` format.
  public static func checksum(of file: String, in text: String) -> String? {
    for line in text.split(whereSeparator: \.isNewline) {
      let fields = line.split(separator: " ", omittingEmptySubsequences: true)
      guard fields.count == 2, fields[1] == file || fields[1] == "*\(file)" else { continue }
      let hash = fields[0].lowercased()
      guard hash.count == 64, hash.allSatisfy(\.isHexDigit) else { return nil }
      return hash
    }
    return nil
  }

  private static func version(_ tag: String) -> String? {
    let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    return parts(version) == nil ? nil : version
  }

  private static func parts(_ version: String) -> [Int]? {
    let fields = version.split(separator: ".", omittingEmptySubsequences: false)
    let numbers = fields.compactMap { Int($0) }
    guard !fields.isEmpty, fields.count <= 4, numbers.count == fields.count,
      numbers.allSatisfy({ $0 >= 0 })
    else { return nil }
    return numbers
  }

  private static func part(_ parts: [Int], _ index: Int) -> Int {
    index < parts.count ? parts[index] : 0
  }
}
