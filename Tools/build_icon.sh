#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Mechanical macOS icon-size export. AppIcon.png is the editable source artwork.
source_icon="Resources/AppIcon.png"
iconset="Resources/AppIcon.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$source_icon" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    retina_size=$((size * 2))
    sips -z "$retina_size" "$retina_size" "$source_icon" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
# Keep the pre-existing source copy in this iconset consistent as well.
cp "$source_icon" "$iconset/AppIcon.png"
iconutil -c icns "$iconset" -o Resources/AppIcon.icns
