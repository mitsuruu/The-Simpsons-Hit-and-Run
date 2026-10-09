#!/bin/sh
# Builds the static libraries the iOS port links against: SDL3, OpenAL Soft,
# libpng and a minimal FFmpeg (Bink and XMV movies only).
#
# Usage: ios/build-deps.sh [iphoneos|iphonesimulator]
#
# Requires Xcode, cmake and ninja. Everything is built into build/ios-deps.

set -e

SDK=${1:-iphoneos}
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

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DEPS=$ROOT/build/ios-deps
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
sed -i '' -E 's/-framework ([A-Za-z]+)/-Wl,-framework,\1/g' "$PREFIX"/lib/pkgconfig/libav*.pc "$PREFIX"/lib/pkgconfig/libsw*.pc

echo "Dependencies installed to $PREFIX"
