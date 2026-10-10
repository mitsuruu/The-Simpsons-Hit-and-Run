#!/bin/sh
# Builds the macOS app.
#
# Usage: macos/build-app.sh
#        SRR2_REGION=PAL macos/build-app.sh
#
# The result is build/macos/Simpsons Hit & Run.app. It links the libraries from the
# environment (SDL3, OpenAL Soft, libpng and FFmpeg), so it only runs on this
# machine unless they are installed in a standard location.
#
# Requires Xcode, cmake, ninja, pkg-config and the libraries above. With nix,
# run it in the shell from the root of the repository:
#   nix develop -c macos/build-app.sh
#
# Downloads the port's UI art (art/) from the official release if it's
# missing, it isn't in the git repository (scripts/fetch-art.sh).

set -e

REGION=${SRR2_REGION:-NTSC}

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD=$ROOT/build/macos

cd "$ROOT"

for tool in cmake ninja pkg-config; do
    if ! command -v "$tool" > /dev/null; then
        echo "$tool not found, see the usage at the top of this script" >&2
        exit 1
    fi
done

scripts/fetch-art.sh "$REGION"

echo "Configuring"
cmake -S . -B "$BUILD" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DSRR2_BUILD_TESTS=OFF \
    -DSRR2_REGION="$REGION" \
    > /dev/null

echo "Building"
cmake --build "$BUILD" > "$BUILD/build.log" 2>&1 || {
    echo "Build failed, the end of $BUILD/build.log:" >&2
    tail -n 25 "$BUILD/build.log" >&2
    exit 1
}

# The Dock names the app after its file, but CMake can't build a target with an
# "&" in its name, so the app is copied to its final name
APP="$BUILD/Simpsons Hit & Run.app"
rm -rf "$APP"
ditto "$BUILD/code/Simpsons Hit and Run.app" "$APP"

echo "Created $APP"
