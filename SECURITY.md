# Security

GitIsle reads GitHub through your existing GitHub CLI login and stores its
caches and settings under `~/Library/Application Support/GitIsle/`. It never
writes to GitHub or to agent configuration.

Installed releases look for a newer release every hour, and when the Mac
wakes, with `gh`. When you choose to update, GitIsle downloads `GitIsle.zip`,
its signature `GitIsle.zip.sig`, and `checksums.txt` from that release. It
installs the archive only if the signature is valid for the Ed25519 public key
built into the app, and the SHA-256, bundle identifier, version, and code
signature all check out; then it replaces itself and relaunches. Only the
release workflow can sign, with the private key stored as the repository
secret `GITISLE_SIGNING_KEY`, so files uploaded to a release by anyone else
are refused. Builds from source never update themselves.

## Reporting a vulnerability

Please report security issues privately with GitHub's
[private vulnerability reporting](https://github.com/ppazosp/gitisle/security/advisories/new)
rather than in a public issue. Include the steps to reproduce and the GitIsle
and macOS versions. You will get a reply as soon as possible, and fixes are
released with credit unless you prefer otherwise.

## Supported versions

Security fixes go into the latest release.
