#!/bin/bash
# Update Flutter launcher icons across all platforms.
# Requires ImageMagick (`convert`) for resizing images.
# Optionally requires `icotool` from icoutils for Windows icons.
# Usage: ./tool/update_icons.sh [source_icon]
# If [source_icon] is not provided, defaults to web/icons/Icon-512.png

set -e

SRC=${1:-web/icons/Icon-512.png}
IOS_DIR="ios/Runner/Assets.xcassets/AppIcon.appiconset"
MAC_DIR="macos/Runner/Assets.xcassets/AppIcon.appiconset"
WIN_DIR="windows/runner/resources"

declare -A IOS_SIZES=(
  ["Icon-App-20x20@1x.png"]=20
  ["Icon-App-20x20@2x.png"]=40
  ["Icon-App-20x20@3x.png"]=60
  ["Icon-App-29x29@1x.png"]=29
  ["Icon-App-29x29@2x.png"]=58
  ["Icon-App-29x29@3x.png"]=87
  ["Icon-App-40x40@1x.png"]=40
  ["Icon-App-40x40@2x.png"]=80
  ["Icon-App-40x40@3x.png"]=120
  ["Icon-App-60x60@2x.png"]=120
  ["Icon-App-60x60@3x.png"]=180
  ["Icon-App-76x76@1x.png"]=76
  ["Icon-App-76x76@2x.png"]=152
  ["Icon-App-83.5x83.5@2x.png"]=167
  ["Icon-App-1024x1024@1x.png"]=1024
)

for name in "${!IOS_SIZES[@]}"; do
  size=${IOS_SIZES[$name]}
  convert "$SRC" -resize ${size}x${size} "$IOS_DIR/$name"
done

declare -A MAC_SIZES=(
  ["app_icon_16.png"]=16
  ["app_icon_32.png"]=32
  ["app_icon_64.png"]=64
  ["app_icon_128.png"]=128
  ["app_icon_256.png"]=256
  ["app_icon_512.png"]=512
  ["app_icon_1024.png"]=1024
)

for name in "${!MAC_SIZES[@]}"; do
  size=${MAC_SIZES[$name]}
  convert "$SRC" -resize ${size}x${size} "$MAC_DIR/$name"
done

# Windows icon (.ico) with multiple sizes
mkdir -p "$WIN_DIR"
convert "$SRC" -resize 16x16   "$WIN_DIR/tmp16.png"
convert "$SRC" -resize 32x32   "$WIN_DIR/tmp32.png"
convert "$SRC" -resize 48x48   "$WIN_DIR/tmp48.png"
convert "$SRC" -resize 256x256 "$WIN_DIR/tmp256.png"
convert "$WIN_DIR/tmp16.png" "$WIN_DIR/tmp32.png" \
        "$WIN_DIR/tmp48.png" "$WIN_DIR/tmp256.png" \
        "$WIN_DIR/app_icon.ico"
rm "$WIN_DIR"/tmp*.png

echo "Icons updated using $SRC"
