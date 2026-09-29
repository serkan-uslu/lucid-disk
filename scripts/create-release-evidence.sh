#!/usr/bin/env bash
# Writes build/release-evidence.json, binding the final DMG to its exact source
# commit, checksum, signature and notarization. Refuses a dirty working tree.
#   scripts/create-release-evidence.sh 1.0.0
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: $0 VERSION}"
DMG="build/LucidDisk.dmg"
test -f "$DMG" || { echo "Missing $DMG; run ./build_dmg.sh first." >&2; exit 1; }
test -z "$(git status --porcelain=v1 --untracked-files=no)" || { echo "Working tree has uncommitted changes." >&2; exit 1; }
grep -q "APP_VERSION=\"\${APP_VERSION:-$VERSION}\"" build_app.sh || { echo "build_app.sh APP_VERSION is not $VERSION." >&2; exit 1; }

APP_PATH="build/Lucid Disk.app"
authority="$(codesign --display --verbose=2 "$APP_PATH" 2>&1 | sed -n 's/^Authority=//p' | head -1)"
flags="$(codesign --display --verbose=2 "$APP_PATH" 2>&1 | sed -n 's/^CodeDirectory.*flags=\([^ ]*\).*/\1/p')"

python3 - "$VERSION" "$DMG" "$authority" "$flags" <<'PY'
import hashlib, json, os, platform, subprocess, sys

version, dmg, authority, flags = sys.argv[1:5]

def run(*args):
    try:
        return subprocess.run(args, capture_output=True, text=True, check=True).stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None

def ok(*args):
    return subprocess.run(args, capture_output=True).returncode == 0

def load(path):
    if os.path.exists(path):
        with open(path) as f:
            return json.load(f)
    return {}

notary = load("build/notarization.json")
app_notary = load("build/app-notarization.json")
app = "build/Lucid Disk.app"

evidence = {
    "version": version,
    "tag": f"v{version}",
    "sourceCommit": run("git", "rev-parse", "HEAD"),
    "artifact": {
        "name": os.path.basename(dmg),
        "bytes": os.path.getsize(dmg),
        "sha256": hashlib.sha256(open(dmg, "rb").read()).hexdigest(),
        "architectures": run("lipo", "-archs", f"{app}/Contents/MacOS/LucidDisk"),
    },
    "distribution": {
        "signingAuthority": authority or None,
        "hardenedRuntime": "runtime" in flags,
        "notarizationStatus": notary.get("status"),
        "notarizationSubmissionId": notary.get("id"),
        "staplerValidated": ok("xcrun", "stapler", "validate", dmg),
        "appNotarizationStatus": app_notary.get("status"),
        "appNotarizationSubmissionId": app_notary.get("id"),
        "appStaplerValidated": ok("xcrun", "stapler", "validate", app),
        "gatekeeperAccepted": ok("spctl", "--assess", "--type", "open", "--context", "context:primary-signature", dmg),
    },
    "build": {
        "githubRunId": os.environ.get("GITHUB_RUN_ID"),
        "macOS": platform.mac_ver()[0],
        "xcode": run("xcodebuild", "-version"),
        "swift": run("swift", "--version"),
    },
}
with open("build/release-evidence.json", "w") as f:
    json.dump(evidence, f, indent=2)
    f.write("\n")
print(json.dumps(evidence["distribution"], indent=2))
PY
echo "Wrote build/release-evidence.json"
