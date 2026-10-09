#!/bin/sh
# Regenerates the app icons from icon-source-1024.png:
#
#   Assets.xcassets/AppIcon.appiconset  the iOS icon
#   Simpsons.icns                       the macOS icon
#
# The source is a 1024x1024 PNG exported from Icon Composer, with the rounded
# shape drawn into it and transparent corners. The generated files are
# committed so building doesn't need this script.
#
# Requires ImageMagick (magick), sips and iconutil.

set -e
cd "$(dirname "$0")"

SRC=icon-source-1024.png
APPICONSET=Assets.xcassets/AppIcon.appiconset
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# iOS applies its own corner mask and doesn't allow transparency, otherwise
# the corners turn black. Fill the transparent corners with the colours of the
# neighbouring pixels: blur the image and its alpha channel and divide the
# first by the second, then put the original on top.
magick "$SRC" -background black -alpha remove -alpha off -blur 0x48 "$WORK/colour.png"
magick "$SRC" -alpha extract -blur 0x48 "$WORK/alpha.png"
magick "$WORK/colour.png" "$WORK/alpha.png" -compose Divide_Src -composite "$WORK/fill.png"

mkdir -p "$APPICONSET"
magick "$WORK/fill.png" "$SRC" -compose Over -composite -alpha off "$APPICONSET/icon-1024.png"
cat > "$APPICONSET/Contents.json" <<'EOF'
{
  "images" : [
    {
      "filename" : "icon-1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF
cat > Assets.xcassets/Contents.json <<'EOF'
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF

# macOS doesn't mask icons. Scale the artwork to the 824x824 area of Apple's
# icon template and add the soft shadow below it.
magick \( "$SRC" -resize 824x824 \) \( +clone -background black -shadow 40x14+0+10 \) +swap \
    -background none -gravity center -layers merge +repage -extent 1024x1024 "$WORK/mac-1024.png"

ICONSET="$WORK/Simpsons.iconset"
mkdir "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z $size $size "$WORK/mac-1024.png" --out "$ICONSET/icon_${size}x${size}.png" > /dev/null
    sips -z $((size * 2)) $((size * 2)) "$WORK/mac-1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" > /dev/null
done
iconutil -c icns "$ICONSET" -o Simpsons.icns

echo "Generated $APPICONSET and Simpsons.icns"
