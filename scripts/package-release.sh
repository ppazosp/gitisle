#!/bin/bash
# Builds a release of GitIsle and packages it for distribution:
#   bash scripts/package-release.sh 0.2.0
# Produces dist/GitIsle.zip, dist/GitIsle.dmg, and SHA-256 checksums for both.
set -euo pipefail
cd "$(dirname "$0")/.."
version="${1:?Usage: package-release.sh VERSION}"
version="${version#v}"

GITISLE_VERSION="$version" bash scripts/build-app.sh release

rm -f dist/GitIsle.zip dist/GitIsle.dmg dist/checksums.txt
ditto -c -k --keepParent dist/GitIsle.app dist/GitIsle.zip

staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
cp -R dist/GitIsle.app "$staging/"
ln -s /Applications "$staging/Applications"
hdiutil create -quiet -volname "GitIsle $version" -srcfolder "$staging" -ov -format UDZO dist/GitIsle.dmg

(cd dist && shasum -a 256 GitIsle.zip GitIsle.dmg > checksums.txt)
cat dist/checksums.txt
printf 'Packaged GitIsle %s in %s/dist\n' "$version" "$PWD"
