#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
configuration="${1:-debug}"
swift build --configuration "$configuration" --jobs 2
binary_directory="$(swift build --configuration "$configuration" --show-bin-path)"
stage="dist/build-$(date +%s)-$$"
bundle="$stage/GitIsle.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$binary_directory/GitIsle" "$bundle/Contents/MacOS/GitIsle"
for resource in "$binary_directory"/*.bundle; do
    if [ -d "$resource" ]; then cp -R "$resource" "$bundle/Contents/Resources/"; fi
done
cp Resources/Info.plist "$bundle/Contents/Info.plist"
# Release builds stamp the version from the tag, for example GITISLE_VERSION=0.2.0, and
# update themselves from later releases. Builds from source update with `git pull`.
if [ -n "${GITISLE_VERSION:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $GITISLE_VERSION" "$bundle/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${GITISLE_BUILD:-$GITISLE_VERSION}" "$bundle/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :GitIsleUpdates bool true" "$bundle/Contents/Info.plist"
fi
swift scripts/make-icon.swift assets/icon.png dist/GitIsle.iconset
iconutil -c icns dist/GitIsle.iconset -o "$bundle/Contents/Resources/GitIsle.icns"
cp THIRD_PARTY_NOTICES.md "$bundle/Contents/Resources/ThirdPartyNotices.md"
cp LICENSE "$bundle/Contents/Resources/LICENSE"
mkdir -p "$bundle/Contents/Resources/DependencyLicenses"
while IFS= read -r license; do
    dependency="$(basename "$(dirname "$license")")"
    cp "$license" "$bundle/Contents/Resources/DependencyLicenses/${dependency}-$(basename "$license")"
done < <(find .build/checkouts -maxdepth 2 -type f \( -iname 'LICENSE*' -o -iname 'NOTICE*' -o -iname 'COPYING*' \))
codesign --force --deep --sign - "$bundle"
codesign --verify --deep --strict "$bundle"
if [ -e dist/GitIsle.app ]; then
    mv dist/GitIsle.app "dist/previous-GitIsle-$(date +%s)-$$.app"
fi
mv "$bundle" dist/GitIsle.app
printf 'Built %s\n' "$PWD/dist/GitIsle.app"
