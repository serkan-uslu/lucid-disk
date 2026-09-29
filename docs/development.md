# Development

## Requirements

- macOS 14 or later, Xcode Command Line Tools with Swift 5.9+
- [`uv`](https://docs.astral.sh/uv/) for the MCP server
- Node 22 for `website/` and `video/`

## Build and run

```bash
swift build                 # debug build
swift run LucidDisk         # run the Community app from the terminal
./build_app.sh              # universal, ad-hoc signed build/Lucid Disk.app
./build_dmg.sh              # build/LucidDisk.dmg + SHA256SUMS.txt
```

Scanning protected folders may need Full Disk Access for the built app (System Settings → Privacy & Security → Full Disk Access).

## Tests

| Command | Covers |
|---|---|
| `swift test` | scanner, safety rules, saved scans, space breakdown, batch review, AI providers (stubbed network), extension points, localization contracts |
| `uv run --project mcp --with pytest pytest mcp/tests` | MCP tools and the shared safety fixture |
| `Tools/review_ui.sh -AppleLanguages '(en)'` | real AppKit event loop: clicks, keyboard, search, Quick Look, help, settings, batch review, a real Trash round trip on a disposable file |

The UI harness needs a logged-in desktop, Screen Recording permission, and an otherwise idle desktop (keyboard checks fail if another app takes focus). Screenshots go to `build/ui-review/`. Repeat with `'(tr)'` for Turkish.

Tests that touch the filesystem create their own `~/.lucid-*` folders and remove them. Tests never write to your saved scans: `ScanViewModel()` without a store saves nothing.

## Store and website screenshots

```bash
LUCID_MARKETING=1 LUCID_UI_SNAPSHOTS=$PWD/build/site-shots \
  Tools/review_ui.sh -AppleLanguages '(en)' -AppleLocale en_US
```

This renders shadowless windows with sample volumes and a sample space breakdown, so your own disks never appear in published images. Convert with `cwebp -q 86` into `website/public/shots/`.

## Localization

All user-facing strings live in `Sources/LucidDiskCore/Resources/Localizable.xcstrings` with English and Turkish entries. When you add a string:

- use `Text("…")`/`Label("…")` or `String(localized: "…")`,
- add the key with both `en` and `tr` values (interpolated `Int` becomes `%lld`, `String` becomes `%@`),
- run `swift test` (`UIContractTests` checks critical keys) and the UI harness in Turkish.

`build_app.sh` compiles the catalog into the app bundle.

## Conventions

- Match the surrounding code: small types, comments that explain *why*, no speculative abstractions.
- Long work runs off the main actor; UI state stays on `ScanViewModel` (main actor).
- System tools run by absolute path with an argument array, never through a shell.
- New public API in `LucidDiskCore` is an extension point: keep it small, test it, and document it in `EDITIONS.md`.
- Safety rules change in Swift and Python together, with a new row in `Tests/Fixtures/deletion-safety.json`.
- Anything that changes what is stored or sent updates `PRIVACY.md`.

## Common tasks

**Add a safety rule.** Edit `classify` in `DeletionSafety.swift` and `classify_path` in `mcp/src/luciddisk_mcp/safety.py`, use the same `matched_rule` name, add fixture rows (including a differently cased path), run both test suites.

**Add an AI provider.** Add a case to `InsightProviderKind`, a client with an injectable `HTTPTransport`, a branch in `LocalFileInsightService.insight`, a Settings section, and tests with a stubbed transport. The provider may only fill `probablePurpose`.

**Add an extension point.** Add a contribution type and a `add…` method to `LucidDiskExtensions`, render it in the relevant view, add a test in `ExtensionTests`, document it in `EDITIONS.md`.

## Continuous integration

`.github/workflows/ci.yml` runs on every push and pull request: identity check, `swift test`, release build, MCP tests, packaging checks (`build_dmg.sh`, architectures, resources, checksum) and MCP distribution build. Signed releases are separate; see [releasing.md](releasing.md).
