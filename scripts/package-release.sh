#!/bin/bash
# Builds a release of GitIsle and packages it for distribution:
#   bash scripts/package-release.sh 0.2.0
# Produces dist/GitIsle.zip, dist/GitIsle.dmg, and SHA-256 checksums for both. The release
# workflow signs GitIsle.zip separately (scripts/sign-release.swift), away from the build.
set -euo pipefail
cd "$(dirname "$0")/.."
version="${1:?Usage: package-release.sh VERSION}"
version="${version#v}"

echo "Building GitIsle $version"
GITISLE_VERSION="$version" bash scripts/build-app.sh release

rm -f dist/GitIsle.zip dist/GitIsle.zip.sig dist/GitIsle.dmg dist/checksums.txt
echo "Zipping"
ditto -c -k --keepParent dist/GitIsle.app dist/GitIsle.zip

echo "Creating disk image"
# dmgbuild lays out the window (background, icon positions) without scripting Finder, so it
# works on CI runners. It runs from a virtual environment with hash-pinned requirements.
venv=".build/dmgbuild"
if [ ! -x "$venv/bin/dmgbuild" ]; then
    python3 -m venv "$venv"
    "$venv/bin/pip" install --quiet --disable-pip-version-check --require-hashes \
        -r scripts/dmg/requirements.txt
fi
tiffutil -cathidpicheck scripts/dmg/background.png scripts/dmg/background@2x.png \
    -out dist/dmg-background.tiff
# hdiutil, which dmgbuild uses, sometimes fails with "Resource busy" on CI runners.
for attempt in 1 2 3; do
    if "$venv/bin/dmgbuild" -s scripts/dmg/settings.py \
        -D app=dist/GitIsle.app -D background=dist/dmg-background.tiff \
        -D icon=dist/GitIsle.app/Contents/Resources/GitIsle.icns \
        "GitIsle $version" dist/GitIsle.dmg; then
        break
    fi
    [ "$attempt" -lt 3 ] || exit 1
    echo "Creating the disk image failed (attempt $attempt); retrying"
    sleep 5
done

(cd dist && shasum -a 256 GitIsle.zip GitIsle.dmg > checksums.txt)
cat dist/checksums.txt
printf 'Packaged GitIsle %s in %s/dist\n' "$version" "$PWD"
