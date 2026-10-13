// Signs a release file with the Ed25519 key in GITISLE_SIGNING_KEY (base64) and writes the
// base64 signature next to it as <file>.sig. The key's public half must match the one the
// app trusts, so a wrong secret fails the release instead of shipping unusable updates:
//   swift scripts/sign-release.swift dist/GitIsle.zip <public key>
import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data("Error: \(message)\n".utf8))
  exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else { fail("Usage: sign-release.swift FILE PUBLIC_KEY") }
guard
  let encoded = ProcessInfo.processInfo.environment["GITISLE_SIGNING_KEY"]?
    .trimmingCharacters(in: .whitespacesAndNewlines), !encoded.isEmpty
else { fail("GITISLE_SIGNING_KEY is not set.") }
guard let raw = Data(base64Encoded: encoded),
  let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw)
else { fail("GITISLE_SIGNING_KEY is not a base64 Ed25519 private key.") }
guard key.publicKey.rawRepresentation.base64EncodedString() == arguments[2] else {
  fail("GITISLE_SIGNING_KEY doesn't match the public key in AppRelease.swift.")
}
let file = URL(fileURLWithPath: arguments[1])
guard let data = try? Data(contentsOf: file) else { fail("Can't read \(file.path).") }
guard let signature = try? key.signature(for: data),
  key.publicKey.isValidSignature(signature, for: data)
else { fail("Signing failed.") }
do {
  try Data(signature.base64EncodedString().utf8).write(to: file.appendingPathExtension("sig"))
} catch { fail("Can't write the signature: \(error.localizedDescription)") }
print("Signed \(file.lastPathComponent)")
