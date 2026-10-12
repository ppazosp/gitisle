#!/bin/bash
# Installs or updates GitIsle on this Mac.
#
#   curl -fsSL https://gitisle.ppazosp.dev/install.sh | bash
#
# Downloads the latest release into /Applications (or ~/Applications when /Applications is not
# writable). Pass --from-source to build the current checkout instead; that needs Xcode.
# Pass --no-open to install without launching. GITISLE_INSTALL_DIR overrides the destination.
set -euo pipefail

repo="ppazosp/gitisle"
from_source=false
open_after=true
for argument in "$@"; do
    case "$argument" in
        --from-source) from_source=true ;;
        --no-open) open_after=false ;;
        -h | --help)
            sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "Unknown option: $argument" >&2; exit 2 ;;
    esac
done

say() { printf '\033[1m==>\033[0m %s\n' "$*"; }
fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "GitIsle runs on macOS."
major="$(sw_vers -productVersion | cut -d. -f1)"
[ "$major" -ge 14 ] || fail "GitIsle needs macOS 14 or later."

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

if $from_source; then
    root="$(cd "$(dirname "$0")/.." && pwd)"
    say "Building GitIsle from $root"
    bash "$root/scripts/build-app.sh" release
    cp -R "$root/dist/GitIsle.app" "$work/"
else
    say "Downloading the latest GitIsle release"
    curl -fsSL "https://github.com/$repo/releases/latest/download/GitIsle.zip" -o "$work/GitIsle.zip" \
        || fail "Could not download the latest release from github.com/$repo."
    ditto -x -k "$work/GitIsle.zip" "$work"
fi
[ -d "$work/GitIsle.app" ] || fail "The download did not contain GitIsle.app."

destination="${GITISLE_INSTALL_DIR:-/Applications}"
[ -w "$destination" ] || [ -n "${GITISLE_INSTALL_DIR:-}" ] || destination="$HOME/Applications"
mkdir -p "$destination"

if pgrep -x GitIsle > /dev/null; then
    say "Quitting the running GitIsle"
    osascript -e 'quit app id "dev.ppazosp.gitisle"' > /dev/null 2>&1 || pkill -x GitIsle || true
    sleep 1
fi

say "Installing into $destination"
rm -rf "$destination/GitIsle.app"
mv "$work/GitIsle.app" "$destination/GitIsle.app"
# Releases are signed ad hoc and not notarized yet, so remove the download quarantine flag;
# otherwise Gatekeeper refuses to open the app.
xattr -dr com.apple.quarantine "$destination/GitIsle.app" 2> /dev/null || true

if ! command -v gh > /dev/null; then
    printf '\nGitIsle reads GitHub through the GitHub CLI. Install it and sign in:\n'
    printf '  brew install gh && gh auth login\n\n'
elif ! gh auth status > /dev/null 2>&1; then
    printf '\nSign in to the GitHub CLI so GitIsle can read your pull requests:\n  gh auth login\n\n'
fi

if $open_after; then
    say "Opening GitIsle"
    open "$destination/GitIsle.app"
fi
say "Done. Hover the notch to open GitIsle; right-click it for Settings or to quit."
