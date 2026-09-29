# Safety model

Lucid Disk looks at people's files. These invariants hold in every edition and every change. Each one has tests; a change that breaks one is a bug.

## Invariants

1. **Nothing is deleted.** The only destructive operation is `FileManager.trashItem`. Lucid Disk never empties the Trash and never calls `removeItem` on user files.
2. **Nothing moves without the user.** Items reach the Trash only through: add to review queue → request → confirmation dialog → re-validation. A stale confirmation (item no longer queued) does nothing.
3. **Re-check right before moving.** `DeletionSafety.validateBeforeTrash` re-runs the risk rules and compares the file's current device and inode with the scanned identity. A file replaced since the scan is skipped and reported.
4. **Protected locations are blocked.** `/System`, `/usr` (except `/usr/local`), `/bin`, `/sbin`, `/var`, `/Applications`, `/Library`, filesystem, users and home roots, and machine-wide roots can never be moved. Paths are compared case-insensitively, and both the typed path and its symlink target are assessed; the stricter result wins.
5. **Sensitive data needs a stronger confirmation.** Documents, Desktop, Pictures, Mail, Messages, application support, other users' folders and machine-wide areas require "I Understand".
6. **Saved scans cannot move anything.** A snapshot from disk may be browsed and queued; Trash requires a fresh scan.
7. **AI never decides.** Models fill only the "probable purpose" line. Risk, summary and recommendation come from the rules; model output that says "safe to delete" changes nothing.
8. **AI sees metadata only, and only when asked.** Selecting a file never calls a model. Names and paths are escaped as untrusted data in the prompt. Cloud providers need an explicit opt-in; failures fall back to local rules, never to another provider.
9. **The MCP server is read-only.** It has no write, move or delete tools, and its rules match the app's through the shared fixture.
10. **No telemetry.** Scans stay on the Mac. The only network requests are the ones the user configures (Ollama, Claude API, or an edition's license check).

## Where each invariant is tested

| Invariant | Tests |
|---|---|
| Queue and confirmation | `DeletionSafetyTests.testReviewQueueCannotBeBypassed`, `ScanViewModelTests.testStaleConfirmationCannotTrashAnItemRemovedFromQueue` |
| Identity re-check | `ScanViewModelTests.testAsyncTrashRevalidatesIdentityAndLeavesReplacementUntouched`, `BatchReviewTests.testBatchTrashRevalidatesEachItemAndReportsSkips` |
| Protected paths and case folding | `SharedSafetyFixtureTests`, `mcp/tests/test_safety.py` |
| Saved scans | `ScanStoreTests.testSavedScanOpensAsBrowsableSnapshotAndBlocksTrash`, `BatchReviewTests.testSavedScanBlocksBatchTrash` |
| AI boundaries | `LocalFileInsightServiceTests`, `InsightProviderTests` |
| MCP read-only | `mcp/tests/test_server.py` |

## Reporting a problem

See [SECURITY.md](../SECURITY.md). Please do not include personal paths or file names in public issues.
