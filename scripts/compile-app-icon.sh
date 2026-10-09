#!/bin/sh
# Compiles an Icon Composer .icon file with Xcode's asset compiler (actool).
# Run by CMake when building the app for macOS and iOS, the files it generates
# are added to the app as resources.
#
# Usage: compile-app-icon.sh <icon> <platform> <min version> <output dir>
#                            <device>...
#
#   icon           path to the .icon file, the app icon is named after it
#   platform       macosx, iphoneos or iphonesimulator
#   min version    the deployment target, an older system gets the .icns or
#                  PNG icons that are generated alongside Assets.car
#   output dir     where Assets.car and the fallback icons are written
#   device         mac, iphone or ipad
#
# The Info.plist keys that point to the icon are in the Info.plist templates
# (macos/ and ios/), they have to match the names of the generated files.

set -e

ICON=$1
PLATFORM=$2
MIN_VERSION=$3
OUTPUT_DIR=$4
shift 4

NAME=$(basename "$ICON" .icon)

# nix shells have their own xcrun and point DEVELOPER_DIR at an SDK that
# doesn't have Xcode's tools, use Apple's xcrun and the Xcode that's selected
# with xcode-select instead
XCRUN=/usr/bin/xcrun
if ! $XCRUN --find actool > /dev/null 2>&1; then
    unset DEVELOPER_DIR SDKROOT
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

for device in "$@"; do
    set -- "$@" --target-device "$device"
    shift
done

mkdir -p "$OUTPUT_DIR"
if ! $XCRUN actool "$ICON" --compile "$OUTPUT_DIR" --platform "$PLATFORM" \
        --minimum-deployment-target "$MIN_VERSION" --app-icon "$NAME" "$@" \
        --output-partial-info-plist "$TMP/partial.plist" > "$TMP/actool.log" 2>&1; then
    cat "$TMP/actool.log" >&2
    exit 1
fi
