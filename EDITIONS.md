# Editions

Lucid Disk is open core. This repository is the **Community edition**: a complete, useful app under the [Apache License 2.0](LICENSE). A separately distributed **Pro edition** is planned; it is built on this core and adds features through the extension points below.

## Promises

- The Community edition is a full product, not a demo. Scanning, the map, search, the review queue, every safety rule, Lucid Insight with every AI provider, and the read-only MCP server stay free.
- Safety is never a paid feature. Protected paths, risk rules, and the checks before Trash are identical in every edition.
- A feature released in the Community edition is never moved into a paid edition.
- Paid editions add capabilities; they do not remove or weaken Community behavior.
- Code in this repository stays open. Paid features live in a separate codebase and are not part of Community builds.

## Architecture

```
Sources/
  LucidDiskCore/   the app: scanner, safety, AI providers, UI, extension points (library)
  LucidDisk/       the Community @main app — LucidDiskMainScene() with nothing installed
```

Another edition is its own Swift package that depends on the `LucidDiskCore` library at a released tag, installs a `LucidDiskExtension` at launch, and shows `LucidDiskMainScene()`:

```swift
import LucidDiskCore
import SwiftUI

@main
struct ExampleEditionApp: App {
    init() { LucidDiskExtensions.shared.install(ExampleEdition()) }
    var body: some Scene { LucidDiskMainScene() }
}
```

### Extension points

| Slot | Type | Where it appears |
|---|---|---|
| Edition name | `EditionInfo` via `setEdition(_:)` | Window title and About |
| Sidebar section | `SidebarContribution` | Below Location and Review Queue |
| Inspector card | `InspectorContribution` | Below Lucid Insight for the selected item |
| Settings tab | `SettingsTabContribution` | After the AI and MCP tabs |

Contributions are replaced when added again with the same `id` and removed with `remove(id:)`, so an edition can install or withdraw features at runtime.

Extensions receive a `LucidDiskContext`. It exposes the scan tree (read-only `FileNode`s), the selection, and the review queue, and allows starting a scan, changing focus or selection, and **adding** items to the review queue. It cannot move anything to Trash: that still requires the user's confirmation and the core's identity and safety checks. Risk comes from `DeletionSafety.assess`, whose verdicts extensions can read but not construct.

### Building another edition

- Pin the dependency to a release tag of this repository, not a branch.
- Localized strings in the core use the app's main bundle. Compile `Sources/LucidDiskCore/Resources/Localizable.xcstrings` into the edition's app bundle exactly as `build_app.sh` does, alongside the edition's own catalog.
- Keep new public API in the core small; propose it here as an extension point with a test, so Community users benefit from the same seams.
