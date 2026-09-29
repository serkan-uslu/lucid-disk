# Safety model

Lucid Disk looks at people's files. These invariants hold in every edition and every change. Each one has tests; a change that breaks one is a bug.

## Invariants

1. **Nothing is deleted.** The only destructive operation is `FileManager.trashItem`. Lucid Disk never empties the Trash and never calls `removeItem` on user files.
2. **Nothing moves without the user.** Items reach the Trash only through: add to review queue → request → confirmation dialog → re-validation. A stale confirmation (item no longer queued) does nothing.
3. **Re-check right before moving.** `DeletionSafety.validateBeforeTrash` re-runs the risk rules and compares the file's current device and inode with the scanned identity. A file replaced since the scan is skipped and reported.
4. **Protected locations are blocked.** `/System`, `/usr` (except `/usr/local`), `/bin`, `/sbin`, `/var`, `/Applications`, `/Library`, filesystem, users and home roots, machine-wide roots, and your user Library (`~/Library`) can never be moved. Paths are compared case-insensitively, and both the typed path and its symlink target are assessed; the stricter result wins.
5. **Sensitive data needs a stronger confirmation.** Documents, Desktop, Pictures, Mail, Messages, application support, containers, keychains, preferences, other users' folders and machine-wide areas require "I Understand".
6. **A folder is at least as strict as what it contains.** A folder that contains a sensitive location (for example `~/Library/Developer`, which holds Xcode Archives) needs the strong confirmation too. A folder whose contents could not all be read needs it as well, because the scan cannot see everything that would move. When a queued item sits inside another queued folder, the folder's confirmation takes the stricter of the two. (The unreadable-contents rule looks at scan results, not paths, so it lives only in the app; the MCP server classifies paths and mirrors every path rule.)
7. **Saved scans cannot move anything.** A snapshot from disk may be browsed and queued; Trash requires a fresh scan.
8. **AI never decides.** Models fill only the "probable purpose" line. Risk, summary and recommendation come from the rules; model output that says "safe to delete" changes nothing. A model's line is labelled "Estimate from metadata"; it never borrows the confidence of the matched safety rule.
9. **AI sees metadata only, and only when asked.** Selecting a file never calls a model. Names and paths are escaped as untrusted data in the prompt. Cloud providers need an explicit opt-in; failures fall back to local rules, never to another provider.
10. **The MCP server is read-only.** It has no write, move or delete tools, and its rules match the app's through the shared fixture.
11. **No telemetry.** Scans stay on the Mac. The only network requests are the ones the user configures (Ollama, Claude API, or an edition's license check).

## Where each invariant is tested

| Invariant | Tests |
|---|---|
| Queue and confirmation | `DeletionSafetyTests.testReviewQueueCannotBeBypassed`, `ScanViewModelTests.testStaleConfirmationCannotTrashAnItemRemovedFromQueue` |
| Identity re-check | `ScanViewModelTests.testAsyncTrashRevalidatesIdentityAndLeavesReplacementUntouched`, `BatchReviewTests.testBatchTrashRevalidatesEachItemAndReportsSkips` |
| Protected paths and case folding | `SharedSafetyFixtureTests`, `mcp/tests/test_safety.py` |
| Folders as strict as their contents | `DeletionSafetyTests.testUserLibraryIsBlockedAndItsContainersNeedStrongConfirmation`, `DeletionSafetyTests.testFolderWithUnreadableContentsNeedsStrongConfirmation`, `BatchReviewTests.testQueuedFolderTakesTheStricterPolicyOfQueuedItemsInside` |
| Saved scans | `ScanStoreTests.testSavedScanOpensAsBrowsableSnapshotAndBlocksTrash`, `BatchReviewTests.testSavedScanBlocksBatchTrash` |
| AI boundaries | `LocalFileInsightServiceTests`, `InsightProviderTests` |
| Saved scans never replace a newer scan or survive "Delete all" | `ScanStoreTests.testNewScanWinsOverASavedScanStillLoading`, `ScanStoreTests.testSaveStartedBeforeDeleteAllDoesNotRecreateAFile` |
| MCP read-only | `mcp/tests/test_server.py` |

## Reporting a problem

See [SECURITY.md](../SECURITY.md). Please do not include personal paths or file names in public issues.
