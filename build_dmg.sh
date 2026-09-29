#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Lucid Disk"
SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

./build_app.sh

DMG_STAGING="build/dmg-staging"
DMG_PATH="build/${APP_NAME}.dmg"

rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"

cp -R "build/${APP_NAME}.app" "$DMG_STAGING/"
cp "LICENSE" "$DMG_STAGING/LICENSE.txt"
ln -s /Applications "$DMG_STAGING/Applications"

rm -f "$DMG_PATH"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGING" -ov -format UDZO "$DMG_PATH"

rm -rf "$DMG_STAGING"

if [[ "$SIGN_IDENTITY" != "-" ]]; then
    codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG_PATH"
    codesign --verify --strict "$DMG_PATH"
fi

if [[ -n "${NOTARYTOOL_PROFILE:-}" ]]; then
    if [[ "$SIGN_IDENTITY" == "-" ]]; then
        echo "NOTARYTOOL_PROFILE requires a Developer ID CODE_SIGN_IDENTITY." >&2
        exit 1
    fi
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARYTOOL_PROFILE" --wait
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH"
fi

echo "Created: $DMG_PATH"
