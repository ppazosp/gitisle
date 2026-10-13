# Security

GitIsle reads GitHub through your existing GitHub CLI login and stores its
caches and settings under `~/Library/Application Support/GitIsle/`. It never
writes to GitHub or to agent configuration.

Installed releases look for a newer release every 6 hours with `gh`. When you
choose to update, GitIsle downloads `GitIsle.zip` and `checksums.txt` from that
release, checks the archive's SHA-256, the bundle identifier, the version, and
the code signature, then replaces itself and relaunches. Releases are signed
ad hoc, so this guards against a damaged download, not against a release
published by someone with write access to the repository. Builds from source
never update themselves.

## Reporting a vulnerability

Please report security issues privately with GitHub's
[private vulnerability reporting](https://github.com/ppazosp/gitisle/security/advisories/new)
rather than in a public issue. Include the steps to reproduce and the GitIsle
and macOS versions. You will get a reply as soon as possible, and fixes are
released with credit unless you prefer otherwise.

## Supported versions

Security fixes go into the latest release.
