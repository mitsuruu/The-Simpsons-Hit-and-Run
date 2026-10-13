# Build tasks for the macOS and iOS ports. Requires Xcode. With nix, run them in
# the shell from the root of the repository:
#   nix develop -c just build-macos

set positional-arguments

ios_deps := justfile_directory() / 'build/ios-deps'

[private]
default:
    @just --list --unsorted

# Build the macOS app, build/macos/Simpsons Hit & Run.app
#
# It links the libraries from the environment (SDL3, OpenAL Soft, libpng and
# FFmpeg), so it only runs on this machine unless they are installed in a
# standard location.
[doc('Build the macOS app, build/macos/Simpsons Hit & Run.app')]
[group('build')]
[no-exit-message]
build-macos: (_require 'cmake ninja pkg-config') fetch-art
    #!/bin/sh
    set -e
    BUILD='{{ justfile_directory() }}/build/macos'

    echo "Configuring"
    cmake -S . -B "$BUILD" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DSRR2_BUILD_TESTS=OFF \
        > /dev/null

    echo "Building"
    just _quiet "$BUILD/build.log" cmake --build "$BUILD"

    # The Dock names the app after its file, but CMake can't build a target with an
    # "&" in its name, so the app is copied to its final name
    APP="$BUILD/Simpsons Hit & Run.app"
    rm -rf "$APP"
    ditto "$BUILD/code/Simpsons Hit and Run.app" "$APP"

    echo "Created $APP"

# Build an unsigned iOS .ipa, build/Simpsons-unsigned.ipa
#
# It has to be signed before it can be installed, sideloading tools like
# AltStore and Sideloadly do that with your Apple ID. Steps that were already
# done are skipped, so running it again is quick.
[doc('Build an unsigned iOS .ipa, build/Simpsons-unsigned.ipa')]
[group('build')]
[no-exit-message]
build-ios: (_require 'xcodebuild cmake ninja pkg-config') fetch-art _ensure-ios-deps
    #!/bin/sh
    set -e
    ROOT='{{ justfile_directory() }}'
    DEPS='{{ ios_deps }}/iphoneos'
    BUILD=$ROOT/build/ios
    IPA=$ROOT/build/Simpsons-unsigned.ipa

    echo "Configuring"
    PKG_CONFIG_LIBDIR=$DEPS/lib/pkgconfig cmake -S . -B "$BUILD" -G Xcode \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_SYSROOT=iphoneos \
        -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
        -DCMAKE_FIND_ROOT_PATH="$DEPS" \
        -DCMAKE_PREFIX_PATH="$DEPS" \
        > /dev/null

    echo "Building"
    just _quiet "$BUILD/xcodebuild.log" \
        xcodebuild -project "$BUILD/SRR2.xcodeproj" -target SRR2 -configuration Release -sdk iphoneos \
        -jobs "$(sysctl -n hw.ncpu)" \
        CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""

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

# Build the static libraries the iOS port links against into build/ios-deps
#
# SDL3, OpenAL Soft, libpng and a minimal FFmpeg (Bink and XMV movies only).
# sdk is iphoneos or iphonesimulator.
[doc('Build the static libraries the iOS port links against')]
[group('build')]
[no-exit-message]
ios-deps sdk='iphoneos': (_require 'xcrun cmake ninja')
    #!/bin/sh
    set -e
    SDK='{{ sdk }}'
    case "$SDK" in
        iphoneos)        MIN_VERSION_FLAG="-miphoneos-version-min" ;;
        iphonesimulator) MIN_VERSION_FLAG="-mios-simulator-version-min" ;;
        *) echo "Unknown SDK: $SDK" >&2; exit 1 ;;
    esac

    IOS_DEPLOYMENT_TARGET=15.0
    SDL_VERSION=3.4.16
    OPENAL_VERSION=1.24.3
    LIBPNG_VERSION=1.6.58
    FFMPEG_VERSION=6.1.6

    DEPS='{{ ios_deps }}'
    SRC=$DEPS/src
    PREFIX=$DEPS/$SDK
    SYSROOT=$(xcrun --sdk "$SDK" --show-sdk-path)
    JOBS=$(sysctl -n hw.ncpu)

    mkdir -p "$SRC" "$PREFIX"

    fetch()
    {
        name=$1
        url=$2
        if [ ! -d "$SRC/$name" ]; then
            echo "Downloading $name"
            curl -fsSL "$url" -o "$SRC/$name.archive"
            mkdir -p "$SRC/$name"
            tar -xf "$SRC/$name.archive" -C "$SRC/$name" --strip-components 1
            rm "$SRC/$name.archive"
        fi
    }

    cmake_build()
    {
        name=$1
        shift
        echo "Building $name for $SDK"
        cmake -S "$SRC/$name" -B "$DEPS/build/$SDK/$name" -G Ninja \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_SYSTEM_NAME=iOS \
            -DCMAKE_OSX_SYSROOT="$SDK" \
            -DCMAKE_OSX_ARCHITECTURES=arm64 \
            -DCMAKE_OSX_DEPLOYMENT_TARGET=$IOS_DEPLOYMENT_TARGET \
            -DCMAKE_INSTALL_PREFIX="$PREFIX" \
            -DCMAKE_FIND_ROOT_PATH="$PREFIX" \
            -DBUILD_SHARED_LIBS=OFF \
            "$@"
        cmake --build "$DEPS/build/$SDK/$name"
        cmake --install "$DEPS/build/$SDK/$name"
    }

    fetch SDL3 "https://github.com/libsdl-org/SDL/releases/download/release-$SDL_VERSION/SDL3-$SDL_VERSION.tar.gz"
    fetch openal-soft "https://github.com/kcat/openal-soft/archive/refs/tags/$OPENAL_VERSION.tar.gz"
    fetch libpng "https://github.com/pnggroup/libpng/archive/refs/tags/v$LIBPNG_VERSION.tar.gz"
    fetch ffmpeg "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz"

    cmake_build SDL3 \
        -DSDL_SHARED=OFF \
        -DSDL_STATIC=ON \
        -DSDL_TESTS=OFF \
        -DSDL_EXAMPLES=OFF

    cmake_build openal-soft \
        -DLIBTYPE=STATIC \
        -DALSOFT_UTILS=OFF \
        -DALSOFT_EXAMPLES=OFF \
        -DALSOFT_INSTALL_EXAMPLES=OFF \
        -DALSOFT_INSTALL_UTILS=OFF

    cmake_build libpng \
        -DPNG_SHARED=OFF \
        -DPNG_STATIC=ON \
        -DPNG_FRAMEWORK=OFF \
        -DPNG_TESTS=OFF \
        -DPNG_TOOLS=OFF

    echo "Building ffmpeg for $SDK"
    mkdir -p "$DEPS/build/$SDK/ffmpeg"
    cd "$DEPS/build/$SDK/ffmpeg"
    "$SRC/ffmpeg/configure" \
        --prefix="$PREFIX" \
        --enable-cross-compile \
        --target-os=darwin \
        --arch=aarch64 \
        --cc="$(xcrun --sdk "$SDK" -f clang)" \
        --sysroot="$SYSROOT" \
        --extra-cflags="-arch arm64 $MIN_VERSION_FLAG=$IOS_DEPLOYMENT_TARGET" \
        --extra-ldflags="-arch arm64 $MIN_VERSION_FLAG=$IOS_DEPLOYMENT_TARGET" \
        --enable-static \
        --disable-shared \
        --disable-programs \
        --disable-doc \
        --disable-network \
        --disable-autodetect \
        --disable-everything \
        --disable-avdevice \
        --disable-avfilter \
        --disable-postproc \
        --enable-protocol=file \
        --enable-demuxer=bink,xmv \
        --enable-decoder=bink,binkaudio_dct,binkaudio_rdft,wmv2,adpcm_ima_wav,pcm_s16le
    make -j"$JOBS"
    make install

    # CMake de-duplicates the separate "-framework" words in FFmpeg's pkg-config
    # files, which breaks linking. Use the single-word linker form instead.
    # The suffix after -i works with both BSD and GNU sed, nix shells have GNU sed.
    sed -i.bak -E 's/-framework ([A-Za-z]+)/-Wl,-framework,\1/g' "$PREFIX"/lib/pkgconfig/libav*.pc "$PREFIX"/lib/pkgconfig/libsw*.pc
    rm "$PREFIX"/lib/pkgconfig/*.bak

    echo "Dependencies installed to $PREFIX"

# Remove the CMake build directories and the .ipa
#
# The iOS libraries in build/ios-deps take a long time to build, so they are
# kept. Remove build/ios-deps by hand to rebuild them.
[group('util')]
clean:
    rm -rf '{{ justfile_directory() }}/build/macos' '{{ justfile_directory() }}/build/ios' '{{ justfile_directory() }}/build/Simpsons-unsigned.ipa'

# Remove the whole build directory, including the iOS libraries
[group('util')]
clean-all:
    rm -rf '{{ justfile_directory() }}/build'

# Compile an Icon Composer .icon file with Xcode's asset compiler (actool)
#
# Run by CMake when building the app for macOS and iOS, the files it generates
# are added to the app as resources. The Info.plist keys that point to the icon
# are in the Info.plist templates (macos/ and ios/), they have to match the
# names of the generated files.
#
#   icon         absolute path to the .icon file, the app icon is named after it
#   platform     macosx, iphoneos or iphonesimulator
#   min_version  the deployment target, an older system gets the .icns or PNG
#                icons that are generated alongside Assets.car
#   output_dir   absolute path of where Assets.car and the fallback icons go
#   devices      mac, iphone or ipad
[doc('Compile an Icon Composer .icon file with actool')]
[group('util')]
[no-exit-message]
app-icon icon platform min_version output_dir +devices:
    #!/bin/sh
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

# Download the port's UI art (art/) from the official release
#
# The redesigned menus aren't in the git repository, they are only shipped in
# the release packages, and the game crashes when it opens the pause menu
# without them. The .vpk release package is a zip file, the art/ folder is
# extracted from it. The download is checked against a known checksum. Does
# nothing if art/ already exists.
[doc('Download the UI art (art/) from the official release')]
[group('util')]
[no-exit-message]
fetch-art dest=justfile_directory():
    #!/bin/sh
    set -e
    DEST='{{ dest }}'

    VERSION=v0.6.1
    SHA256=1dc7ddb06ab3372c4a8896c3a7cb3712a5e8cb7f5bcedd466f56aa9fc1e1278b
    URL=https://github.com/ZenoArrows/The-Simpsons-Hit-and-Run/releases/download/$VERSION/SimpsonsNTSC.vpk

    if [ -f "$DEST/art/frontend/scrooby/ingame.p3d" ]; then
        echo "The UI art is already in $DEST/art"
        exit 0
    fi

    TMP=$(mktemp -d)
    trap 'rm -rf "$TMP"' EXIT

    echo "Downloading the UI art from the $VERSION release"
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

# Fail if any of the given tools (space separated) isn't installed
[private]
_require tools:
    #!/bin/sh
    for tool in $1; do
        if ! command -v "$tool" > /dev/null; then
            echo "$tool not found, run this in the shell from 'nix develop' or install it" >&2
            exit 1
        fi
    done

# Build the iOS libraries unless they were built already
[private]
_ensure-ios-deps:
    #!/bin/sh
    set -e
    if [ ! -f '{{ ios_deps }}/iphoneos/lib/libSDL3.a' ]; then
        just ios-deps iphoneos
    fi

# Run a command with its output in a log file, show the end of it if it fails
[private]
_quiet log +command:
    #!/bin/sh
    log=$1
    shift
    "$@" > "$log" 2>&1 || {
        echo "Build failed, the end of $log:" >&2
        tail -n 25 "$log" >&2
        exit 1
    }
