# Releasing

Lucid Disk is distributed outside the Mac App Store as a signed, notarized DMG on GitHub Releases. The website's download button always points to `releases/latest/download/LucidDisk.dmg`.

## The chain

```mermaid
flowchart LR
    A[Commit on main] --> B[swift test]
    B --> C[Build universal app]
    C --> D[Sign app<br/>Developer ID · Hardened Runtime · timestamp]
    D --> E[Create DMG · sign DMG]
    E --> F[notarytool submit --wait]
    F --> G[stapler staple]
    G --> H[Gatekeeper + verify-release.sh]
    H --> I[SHA-256 + evidence + attestation]
    I --> J[Draft release]
    J --> K[Manual acceptance on a clean Mac]
    K --> L[Publish as Latest]
```

The app has a single executable and a code-free resource bundle, so it is signed once from the outside, never with `--deep`. The build fails if the signature contains `get-task-allow`. The checksum is taken after stapling, because stapling changes the bytes.

## Version

`APP_VERSION` and `APP_BUILD` in `build_app.sh` are the single source. Bump them, merge to `main`, then release that exact commit. Tags are `vX.Y.Z` and never move; a bad release gets a patch release, not a replaced asset.

## Option A — release from GitHub Actions (recommended)

One-time setup:

1. Repository → Settings → Environments → create **release**; add yourself as required reviewer and restrict it to `main`.
2. Add these secrets to the **release** environment (never to the repository or a chat):

   | Secret | Value |
   |---|---|
   | `APPLE_SIGNING_IDENTITY` | `Developer ID Application: Name (TEAMID)` |
   | `MACOS_CERTIFICATE_P12_BASE64` | `base64 < DeveloperID.p12 \| tr -d '\n'` |
   | `MACOS_CERTIFICATE_PASSWORD` | the `.p12` export password |
   | `APPLE_ID` | Apple ID email |
   | `APPLE_TEAM_ID` | 10-character team ID |
   | `APPLE_APP_SPECIFIC_PASSWORD` | an app-specific password from appleid.apple.com |

   With the GitHub CLI each command prompts for the value: `gh secret set APPLE_ID --env release`, and for the certificate `base64 < DeveloperID.p12 | tr -d '\n' | gh secret set MACOS_CERTIFICATE_P12_BASE64 --env release`.

Each release:

1. Actions → **Signed release candidate** → version `1.0.0` and the full commit SHA from `main`. It tests, builds, signs, notarizes, staples, verifies, writes `release-evidence.json`, attests the DMG and uploads a private artifact. It never tags or publishes.
2. Download the artifact (`gh run download RUN_ID`), check it on a clean Mac (below).
3. Actions → **Publish release draft** → version and the candidate's run ID. It checks the checksum and evidence, tags the candidate's source commit and creates a **draft** release with the same bytes.
4. Review the draft, then publish: `gh release edit v1.0.0 --draft=false --prerelease=false --latest`.

## Option B — release from a Mac with the certificate

One-time: store notarization credentials in your login keychain (it prompts for the app-specific password):

```bash
xcrun notarytool store-credentials lucid-notary --apple-id you@example.com --team-id TEAMID
```

Each release, from a clean checkout of the release commit:

```bash
CODE_SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" \
NOTARYTOOL_PROFILE=lucid-notary ./build_dmg.sh
scripts/verify-release.sh "$PWD/build/LucidDisk.dmg" "Lucid Disk.app"
scripts/create-release-evidence.sh 1.0.0

git tag -a v1.0.0 -m "Lucid Disk 1.0.0" && git push origin v1.0.0
gh release create v1.0.0 build/LucidDisk.dmg build/SHA256SUMS.txt \
  build/notarization.json build/notarization-log.json build/release-evidence.json \
  --verify-tag --draft --title "Lucid Disk 1.0.0" --generate-notes
# after acceptance:
gh release edit v1.0.0 --draft=false --prerelease=false --latest
```

## Acceptance on a clean Mac

1. Download the DMG with Safari (so it is quarantined) on a Mac or user account that has never run Lucid Disk.
2. Open it, drag the app to Applications, launch it from Finder: no Gatekeeper warning.
3. Scan a folder, open Help, Settings and Quick Look, queue and move a disposable file to the Trash and restore it.
4. Compare the checksum: `shasum -a 256 -c SHA256SUMS.txt`, and if attested, `gh attestation verify LucidDisk.dmg --repo serkan-uslu/lucid-disk`.
5. Check the website's download button returns the new DMG.

## If something goes wrong

- **Notarization rejected:** read `notarization-log.json`; the path in each issue shows what to fix.
- **Gatekeeper rejects an accepted DMG:** run `scripts/verify-release.sh`; check the stapled ticket and that nothing changed after signing.
- **Published a bad build:** mark it in the release notes, move Latest back if needed, and ship a patch version. Do not replace assets.
- **Certificate leaked:** revoke it in the Apple Developer account, rotate every secret, release a new patch signed with a new certificate.
