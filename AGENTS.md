# Lucid Disk — agent guide

This is the **open-source Community edition** (Apache 2.0) of an open-core product. A private Pro edition depends on this repository; see [EDITIONS.md](EDITIONS.md).

## Architecture

- `Sources/LucidDiskCore` — the whole app as a library: scanner, safety rules, AI providers, UI, saved scans, space breakdown, and the extension points (`Extensions/LucidDiskExtensions.swift`).
- `Sources/LucidDisk` — the thin Community `@main` app: `LucidDiskMainScene()` with nothing installed.
- `mcp/` — the read-only Python MCP server. Its risk rules mirror `DeletionSafety.swift`; both test suites read `Tests/Fixtures/deletion-safety.json`.

## Never

- Add paid-edition code, licensing, or "is Pro" switches here. Pro features live only in the private repository.
- Move an existing Community feature behind a paywall or weaken it.
- Delete permanently, or move anything to the Trash outside the review queue → confirmation → `DeletionSafety.validateBeforeTrash` flow. Saved scans must never trash.
- Let AI output or an extension change a safety verdict. Models only fill "probable purpose".
- Add write, move, or delete tools to the MCP server.

## When you change things

- A new hook another edition needs: add a small public extension point in `LucidDiskCore` with a test and document it in `EDITIONS.md`.
- Every new user-facing string needs an English and Turkish entry in `Sources/LucidDiskCore/Resources/Localizable.xcstrings`.
- Safety rules: change Swift and Python together and extend the shared fixture.
- Data handling (what is stored or sent): update `PRIVACY.md`.

## Checks

```bash
swift test
uv run --project mcp --with pytest pytest mcp/tests
Tools/review_ui.sh -AppleLanguages '(en)'   # UI changes, on an idle desktop
./build_app.sh                              # packaging
```

## Releases

Bump `APP_VERSION`/`APP_BUILD` in `build_app.sh`, merge to `main`, then tag `vX.Y.Z`. The Pro edition pins the core to these tags.
