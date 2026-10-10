#!/bin/sh
# Builds an unsigned iOS .ipa of the game, including the app icon.
#
# Usage: ios/build-ipa.sh
#        SRR2_REGION=PAL ios/build-ipa.sh
#
# The result is build/Simpsons<region>-unsigned.ipa. It has to be signed before
# it can be installed, sideloading tools like AltStore and Sideloadly do that
# with your Apple ID.
#
# Requires Xcode, cmake, ninja and pkg-config. With nix, run it as
#   nix develop -c ios/build-ipa.sh
#
# Steps that were already done are skipped, so running it again is quick:
#   1. Downloads the port's UI art (art/) from the official release if it's
#      missing, it isn't in the git repository (scripts/fetch-art.sh)
#   2. Builds the libraries the game links against (ios/build-deps.sh)
#   3. Builds the game
#   4. Packages it as an .ipa

set -e

REGION=${SRR2_REGION:-NTSC}

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DEPS=$ROOT/build/ios-deps/iphoneos
BUILD=$ROOT/build/ios
IPA=$ROOT/build/Simpsons$REGION-unsigned.ipa

cd "$ROOT"

for tool in xcodebuild cmake ninja pkg-config; do
    if ! command -v "$tool" > /dev/null; then
        echo "$tool not found, see the usage at the top of this script" >&2
        exit 1
    fi
done

scripts/fetch-art.sh "$REGION"

if [ ! -f "$DEPS/lib/libSDL3.a" ]; then
    ios/build-deps.sh iphoneos
fi

echo "Configuring"
PKG_CONFIG_LIBDIR=$DEPS/lib/pkgconfig cmake -S . -B "$BUILD" -G Xcode \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT=iphoneos \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
    -DCMAKE_FIND_ROOT_PATH="$DEPS" \
    -DCMAKE_PREFIX_PATH="$DEPS" \
    -DSRR2_REGION="$REGION" \
    > /dev/null

echo "Building"
xcodebuild -project "$BUILD/SRR2.xcodeproj" -target SRR2 -configuration Release -sdk iphoneos \
    -jobs "$(sysctl -n hw.ncpu)" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
    > "$BUILD/xcodebuild.log" 2>&1 || {
    echo "Build failed, the end of $BUILD/xcodebuild.log:" >&2
    tail -n 25 "$BUILD/xcodebuild.log" >&2
    exit 1
}

APP=$BUILD/code/Release-iphoneos/Simpsons.app
if [ ! -d "$APP" ]; then
    echo "$APP wasn't created" >&2
    exit 1
fi

echo "Packaging"
rm -rf "$BUILD/ipa" "$IPA"
mkdir -p "$BUILD/ipa/Payload"
cp -R "$APP" "$BUILD/ipa/Payload/"
(cd "$BUILD/ipa" && zip -qry "$IPA" Payload)
rm -rf "$BUILD/ipa"

echo "Created $IPA"
