#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Lucid Disk"
EXECUTABLE="LucidDisk"
BUNDLE_ID="com.serkanuslu.luciddisk"
APP_VERSION="${APP_VERSION:-0.2.1}"
APP_BUILD="${APP_BUILD:-3}"
SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

APP_DIR="build/${APP_NAME}.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

binaries=()
resource_dir=""
for arch in arm64 x86_64; do
    args=(-c release --triple "${arch}-apple-macosx14.0" --scratch-path ".build/${arch}")
    swift build "${args[@]}" --product "$EXECUTABLE"
    bin_dir="$(swift build "${args[@]}" --show-bin-path)"
    binaries+=("$bin_dir/$EXECUTABLE")
    if [[ "$arch" == arm64 ]]; then
        resource_dir="$bin_dir"
    fi
done

lipo -create "${binaries[@]}" -output "$APP_DIR/Contents/MacOS/$EXECUTABLE"
lipo "$APP_DIR/Contents/MacOS/$EXECUTABLE" -verify_arch arm64 x86_64
cp "Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
cp "LICENSE" "$APP_DIR/Contents/Resources/LICENSE"
find "$resource_dir" -maxdepth 1 -type d -name '*.bundle' -exec cp -R {} "$APP_DIR/Contents/Resources/" \;
xcrun xcstringstool compile \
    "Sources/LucidDisk/Resources/Localizable.xcstrings" \
    --output-directory "$APP_DIR/Contents/Resources"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${EXECUTABLE}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${APP_BUILD}</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
</dict>
</plist>
PLIST

plutil -lint "$APP_DIR/Contents/Info.plist"

sign_args=(--force --deep --sign "$SIGN_IDENTITY")
if [[ "$SIGN_IDENTITY" != "-" ]]; then
    sign_args+=(--options runtime --timestamp)
fi
codesign "${sign_args[@]}" "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

echo "Created: $APP_DIR"
