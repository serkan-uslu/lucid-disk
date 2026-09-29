#!/usr/bin/env bash
# Builds build/LucidDisk.dmg. With a Developer ID identity it also signs the DMG;
# with notarization credentials it notarizes, staples, assesses with Gatekeeper,
# and writes the final checksum. See docs/releasing.md.
#
#   CODE_SIGN_IDENTITY   "Developer ID Application: Name (TEAMID)"   (default: ad-hoc)
#   NOTARYTOOL_PROFILE   keychain profile from `xcrun notarytool store-credentials`
#   or APPLE_ID + APPLE_TEAM_ID + APPLE_APP_SPECIFIC_PASSWORD (CI)
set -euo pipefail

APP_NAME="Lucid Disk"
SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

DMG="build/LucidDisk.dmg"

# hdiutil occasionally fails with "Resource temporarily unavailable" on busy
# machines (notably CI runners); retry a few times before giving up.
retry() {
    local attempt
    for attempt in 1 2 3 4; do
        "$@" && return 0
        echo "Attempt $attempt failed: $*" >&2
        sleep $((attempt * 5))
    done
    "$@"
}
STAGING="build/dmg-staging"
# Start clean so an old DMG, log or checksum can never be mistaken for this build.
rm -f "$DMG" build/SHA256SUMS.txt build/notarization.json build/notarization-log.json

./build_app.sh

rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "build/${APP_NAME}.app" "$STAGING/"
cp "LICENSE" "$STAGING/LICENSE.txt"
ln -s /Applications "$STAGING/Applications"
retry hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"
retry hdiutil verify "$DMG"

if [[ "$SIGN_IDENTITY" != "-" ]]; then
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
    codesign --verify --verbose=2 "$DMG"
fi

notary_args=()
if [[ -n "${NOTARYTOOL_PROFILE:-}" ]]; then
    notary_args=(--keychain-profile "$NOTARYTOOL_PROFILE")
elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
    notary_args=(--apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD")
fi

if [[ ${#notary_args[@]} -gt 0 ]]; then
    if [[ "$SIGN_IDENTITY" == "-" ]]; then
        echo "Notarization requires a Developer ID CODE_SIGN_IDENTITY." >&2
        exit 1
    fi
    set +e
    xcrun notarytool submit "$DMG" "${notary_args[@]}" --wait --output-format json > build/notarization.json
    submit_status=$?
    set -e
    submission_id="$(plutil -extract id raw -o - build/notarization.json 2>/dev/null || true)"
    if [[ -n "$submission_id" ]]; then
        # Keep the log even when Apple accepts: it can contain warnings.
        xcrun notarytool log "$submission_id" "${notary_args[@]}" build/notarization-log.json || true
    fi
    test "$submit_status" -eq 0
    test "$(plutil -extract status raw -o - build/notarization.json)" = "Accepted"

    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
    codesign --verify --verbose=2 "$DMG"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
fi

# Stapling changes the bytes; the checksum is taken last.
(cd build && shasum -a 256 LucidDisk.dmg > SHA256SUMS.txt)
echo "Created: $DMG"
cat build/SHA256SUMS.txt
