#!/bin/sh
# Downloads the port's UI art (art/) from the official release.
#
# Usage: scripts/fetch-art.sh [NTSC|PAL] [destination]
#
# The redesigned menus aren't in the git repository, they are only shipped in
# the release packages, and the game crashes when it opens the pause menu
# without them. The .vpk release package is a zip file, the art/ folder is
# extracted from it. The download is checked against a known checksum.
#
# Does nothing if art/ already exists. The destination defaults to the root of
# the repository.

set -e

REGION=${1:-NTSC}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DEST=${2:-$ROOT}

VERSION=v0.6.1
case "$REGION" in
    NTSC) SHA256=1dc7ddb06ab3372c4a8896c3a7cb3712a5e8cb7f5bcedd466f56aa9fc1e1278b ;;
    PAL)  SHA256=fef5c17394869cb825ba241267b230d5b5a6b0eeb47db9a6e00b9eedf9e14e66 ;;
    *) echo "Unknown region $REGION, use NTSC or PAL" >&2; exit 1 ;;
esac
URL=https://github.com/ZenoArrows/The-Simpsons-Hit-and-Run/releases/download/$VERSION/Simpsons$REGION.vpk

if [ -f "$DEST/art/frontend/scrooby/ingame.p3d" ]; then
    echo "The UI art is already in $DEST/art"
    exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "Downloading the UI art from the $VERSION $REGION release"
curl -fsSL "$URL" -o "$TMP/release.vpk"

ACTUAL=$(shasum -a 256 "$TMP/release.vpk" | cut -d ' ' -f 1)
if [ "$ACTUAL" != "$SHA256" ]; then
    echo "$URL doesn't have the expected checksum:" >&2
    echo "  expected $SHA256" >&2
    echo "  got      $ACTUAL" >&2
    exit 1
fi

mkdir -p "$DEST"
unzip -q "$TMP/release.vpk" 'art/*' -d "$DEST"
echo "Extracted the UI art to $DEST/art"
