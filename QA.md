# Desktop regression review — 0.2.1

> **0.3.0 note:** 0.3.0 adds selectable AI providers (Apple on-device, Ollama, Claude API, rules only), a Settings window with AI and MCP tabs, a visual refresh, case-insensitive safety rules shared with the MCP server through one fixture, and two new read-only MCP tools. Automated coverage: `swift test` and `pytest mcp/tests`. The desktop review below predates 0.3.0; re-run `Tools/review_ui.sh` on an otherwise idle desktop (keyboard checks fail if another app takes focus) and exercise real Ollama and Claude API requests manually before a release.

Reviewed on 2026-09-29 on Apple Silicon, macOS 26.4. This is a local development build, not a notarized release sign-off.

## Automated evidence

- `swift test`: 48 passing tests, including explicit-only AI requests, stale AI responses, hard links, incomplete scans, symlink boundaries, identity revalidation, queue requirements, stale scan rejection, cancelled/failed rescans, invalid roots, and localization contracts.
- `uv run --project mcp python -m unittest discover -s mcp/tests -v`: 14 passing tests; the separate MCP server remains read-only.
- `Tools/review_ui.sh -AppleLanguages '(en)'` and the same harness with `'(tr)'`: 37 assertions per language. Assertions include the requested language actually rendering, native row selection, folder double-click, chart drill-down/back, typed global search, Return to open a search-result folder, Space/Escape Quick Look, narrow/wide layout, sidebar resizing, four help topics, and selection at row 9,000 in a 10,000-item native table.
- The desktop harness drives queue/confirmation actions through the real view model, not simulated mouse clicks on confirmation buttons. It scans its own disposable file, verifies confirmation cancellation leaves it intact, moves it to real macOS Trash, restores the exact returned destination, and removes its isolated fixture. No existing user file is removed, and no live AI request is made.
- Universal app/DMG build, `lipo` arm64+x86_64 check, strict ad-hoc signature verification, bundled license and both language resources, and DMG checksum validation.

Screenshots and desktop transcripts are generated under `build/ui-review/` (English) and `build/ui-review-tr/` (Turkish). They are ignored build artifacts. The harness needs a logged-in desktop and screenshot permission; it is not run on headless CI. CI runs unit/MCP tests and packaging/resource checks.

## Issues fixed during this pass

- Rescan cancellation/failure no longer discards a completed snapshot, selection, or review queue.
- Missing/non-directory scan roots now fail instead of appearing as empty successful scans. Explicit directory symlink roots resolve before traversal.
- Search-result folder navigation clears the global filter, making the new folder's children visible.
- Footer layout no longer overlays the last visible native table row. Empty-folder headers stay at the top.
- Trash work does not run on the UI actor. Stale confirmation of an item removed from the queue cannot proceed. Success provides recovery guidance and Show in Trash; the obsolete snapshot is cleared before rescanning.
- English resources are explicitly emitted as well as Turkish; tests no longer silently render Turkish when English was requested.
- About, How to Use, Keyboard Shortcuts, Privacy & Safety, rescan/choose/search shortcuts, and a non-floral glass-disk icon are included.

## Remaining release/manual gates

- Developer ID signing, notarization/stapling and Gatekeeper acceptance require release credentials. Ad-hoc signature validation does not satisfy these gates.
- Execute on physical Intel and macOS 14 systems; a universal build alone proves neither runtime environment.
- Manually exercise VoiceOver reading order, Full Disk Access transitions, removable/network drive disconnects, and actual Apple Foundation Models availability/generation on supported hardware. Model-state tests use deterministic injected providers.
- Manually verify the packaged app's menu entry activation, Finder reveal and System Settings link. Help content/window rendering and packaged resources are covered, but these external-application interactions are not automated.
- The benchmark is synthetic and warm-cache; no whole-disk speed or reclaimable-space guarantee is made.
