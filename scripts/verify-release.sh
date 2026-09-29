#!/usr/bin/env bash
set -euo pipefail
# Verifies a final DMG and the app inside it: integrity, signatures, notarization
# ticket, Gatekeeper, entitlements and checksum.
#   scripts/verify-release.sh build/LucidDisk.dmg "Lucid Disk.app"

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 /absolute/path/My-App.dmg 'My App.app'" >&2
  exit 2
fi

DMG="$1"
APP_NAME="$2"

test -f "$DMG" || {
  echo "DMG not found: $DMG" >&2
  exit 1
}

MOUNT_POINT="$(mktemp -d)"
mounted=0
cleanup() {
  if [ "$mounted" -eq 1 ]; then
    hdiutil detach "$MOUNT_POINT" -quiet || true
  fi
  rmdir "$MOUNT_POINT" 2>/dev/null || true
}
trap cleanup EXIT

echo "== DMG integrity =="
hdiutil verify "$DMG"

echo "== DMG code signature =="
codesign --verify --verbose=2 "$DMG"
codesign --display --verbose=4 "$DMG" 2>&1

echo "== DMG notarization ticket =="
xcrun stapler validate "$DMG"

echo "== DMG Gatekeeper assessment =="
spctl --assess \
  --type open \
  --context context:primary-signature \
  --verbose=2 \
  "$DMG"

echo "== Mounting final DMG =="
hdiutil attach "$DMG" \
  -mountpoint "$MOUNT_POINT" \
  -readonly \
  -nobrowse \
  -quiet
mounted=1

APP_PATH="$MOUNT_POINT/$APP_NAME"
test -d "$APP_PATH" || {
  echo "Expected app not found in DMG: $APP_PATH" >&2
  find "$MOUNT_POINT" -maxdepth 2 -print >&2
  exit 1
}

echo "== App code signature =="
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign --display --verbose=4 "$APP_PATH" 2>&1

echo "== App entitlements =="
ENTITLEMENTS="$(codesign --display --entitlements - --xml "$APP_PATH" 2>/dev/null)"
if [ -z "$ENTITLEMENTS" ]; then
  echo "(none)"
else
  printf '%s' "$ENTITLEMENTS" | plutil -convert xml1 -o - -
  if printf '%s' "$ENTITLEMENTS" | grep -q "get-task-allow"; then
    echo "Release app must not contain get-task-allow." >&2
    exit 1
  fi
fi

echo "== App Gatekeeper assessment =="
if command -v syspolicy_check >/dev/null 2>&1; then
  syspolicy_check distribution "$APP_PATH"
else
  spctl --assess --type execute --verbose=2 "$APP_PATH"
fi

echo "== Optional app-level stapling =="
if xcrun stapler validate "$APP_PATH"; then
  echo "The app itself has a valid stapled ticket."
else
  echo "The app has no individually stapled ticket."
  echo "This can be acceptable when only the stapled DMG is distributed."
fi

echo "== Final SHA-256 =="
shasum -a 256 "$DMG"

echo "Static release verification passed."
echo "Still download it through a browser on a clean Mac and launch it from /Applications."
