# Roadmap

The order reflects product priority, not a promise of dates.

## High — first public release

- Complete the Lucid Disk identity, open-source policies, English default UI, and Turkish localization.
- Ship cancellable scans with stale-result protection, hard-link deduplication, measurement accuracy, and incomplete-tree warnings.
- Cover mounted volumes, large-file search and sorting, Quick Look, accessible navigation, and a cleanup review queue.
- Recheck canonical paths, file identity, and deterministic risk immediately before moving an item to Trash.
- Explain selected items locally with Lucid Insight while keeping deterministic safety authoritative.
- Keep the three MCP tools read-only and make their metadata boundary explicit.
- Produce universal signed/notarized DMGs and run Swift, Python, package, and identity checks in CI.
- Complete trademark, store-name, and domain checks before the public launch.

## Medium — 1.x

- Add allowlisted administrator-assisted scanning and read-only System Data analysis.
- Detect APFS and Time Machine snapshots and purgeable storage before offering separately confirmed cleanup.
- Research better APFS clone accounting while labeling estimates honestly.
- Compare scan history and highlight fast-growing folders.
- Find duplicates with size-based filtering before hashing.
- Allow explicitly approved, size-limited local content inspection for one text file at a time.
- Add a read-only MCP scan-snapshot tool after the app persists snapshots.
- Notify users about releases published on GitHub.

## Low — later

- Add direct Google Drive, Dropbox, OneDrive, and Box connectors.
- Discover unmounted network storage.
- Support reusable cleanup recipes and team policies.
- Explore additional visualizations and themes.

Autonomous cleanup, permanent deletion, destructive MCP tools, automatic (unselected) cloud AI fallback, and a custom model runtime are not planned. Cloud AI is available only as an explicitly chosen, opt-in provider.

## Next small steps

- Add an OpenAI-compatible provider (base URL + key) behind the same provider protocol.
