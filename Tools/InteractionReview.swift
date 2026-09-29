// Standalone AppKit review harness. Compile with the LucidDiskCore sources (not the app target).
// It exercises the real macOS event loop; XCTest's non-running NSApplication cannot do that.
import AppKit
import SwiftUI

@main
enum InteractionReview {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        if let icon = NSImage(contentsOfFile: "Resources/AppIcon.icns") { app.applicationIconImage = icon }
        let delegate = ReviewDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class ReviewDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let model = ScanViewModel()
    let output = ProcessInfo.processInfo.environment["LUCID_UI_SNAPSHOTS"] ?? "/tmp/lucid-ui-review"
    var failures: [String] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let root = fixture()
        model.rootNode = root
        model.focusedNode = root
        window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1440, height: 900),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Lucid Disk"
        window.contentView = NSHostingView(rootView: ContentView(viewModel: model)
            .preferredColorScheme(.dark).tint(Color(red: 0.15, green: 0.68, blue: 0.78)))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Task {
            do {
                try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
                try await pause()
                try await review(root)
            } catch { failures.append(error.localizedDescription) }
            print(failures.isEmpty ? "LUCID_UI_REVIEW PASSED" : "LUCID_UI_REVIEW FAILED: \(failures)")
            fflush(stdout)
            exit(failures.isEmpty ? 0 : 1)
        }
    }

    func review(_ root: FileNode) async throws {
        if let language = (UserDefaults.standard.array(forKey: "AppleLanguages") as? [String])?.first {
            let expected = language.hasPrefix("tr") ? "Nasıl Kullanılır" : "How to Use"
            check(String(localized: "How to Use") == expected, "Requested app language is rendered: \(language)")
        }
        for _ in 0..<20 where contentsTable(rows: 6) == nil { try await pause() }
        guard let table = contentsTable(rows: 6) else {
            let tables = descendants(window.contentView!).compactMap { $0 as? NSTableView }
            print("TABLES \(tables.map { "rows=\($0.numberOfRows) width=\($0.bounds.width)" })")
            capture("contents-missing")
            failures.append("Contents table missing"); return
        }
        let row = table.rect(ofRow: 1)
        let point = table.convert(NSPoint(x: row.minX + 90, y: row.midY), to: nil)
        postClick(at: point, count: 1)
        try await pause()
        check(model.selectedNode?.id == root.children[1].id, "Single-click selects a row")
        postClick(at: point, count: 2)
        try await pause()
        check(model.focusedNode?.id == root.children[1].id, "Double-click opens a folder")
        guard let files = contentsTable(rows: 8) else { failures.append("Nested files missing"); return }
        let fileRow = files.rect(ofRow: 0)
        postClick(at: files.convert(NSPoint(x: fileRow.minX + 90, y: fileRow.midY), to: nil), count: 1)
        try await pause()
        check(model.selectedNode?.id == root.children[1].children[0].id, "Found file can be selected")
        for (name, size) in [("wide", NSSize(width: 1440, height: 900)), ("compact", NSSize(width: 1050, height: 700))] {
            window.setContentSize(size)
            try await pause()
            check((window.contentView?.bounds.width ?? 9999) <= size.width + 1, "Layout fits \(name)")
            capture(name)
        }
        // Expand and shrink the actual navigation split view.
        let splits = descendants(window.contentView!).compactMap { $0 as? NSSplitView }
        if let split = splits.first(where: { $0.isVertical }) {
            for width: CGFloat in [280, 180, 260] {
                split.setPosition(width, ofDividerAt: 0)
                try await pause()
                check((window.contentView?.bounds.width ?? 9999) <= 1051, "Sidebar resize stays inside window")
            }
            capture("sidebar-expanded")
        } else { failures.append("Navigation split view missing") }

        model.zoomOut()
        try await pause()
        check(model.focusedNode?.id == root.id, "Back returns to parent")
        if let chart = descendants(window.contentView!).first(where: { $0.identifier?.rawValue == "chart-input" }) {
            let wedges = computeWedges(focusedNode: root)
            let geometry = SunburstGeometry(size: chart.bounds.size, ringCount: wedges.map(\.level).max() ?? 1)
            let first = wedges[0]
            let angle = (first.startDegrees + first.endDegrees) / 2 * .pi / 180
            let radius = geometry.centerRadius + geometry.ringWidth / 2
            let local = CGPoint(x: geometry.center.x + radius * cos(angle),
                                y: geometry.center.y + radius * sin(angle))
            postClick(at: chart.convert(local, to: nil), count: 1)
            try await pause()
            check(model.focusedNode?.id == root.children[0].id, "Clicking chart drills into a folder")
            if let center = descendants(window.contentView!).first(where: { $0.identifier?.rawValue == "chart-input" }) {
                postClick(at: center.convert(CGPoint(x: center.bounds.midX, y: center.bounds.midY), to: nil), count: 1)
            }
            try await pause()
            check(model.focusedNode?.id == root.id, "Clicking chart center returns to parent")
        } else { failures.append("Chart input surface missing") }
        window.setContentSize(NSSize(width: 1440, height: 900))
        try await pause()
        capture("overview")
        try await reviewSearch(root)
        let selectedBeforeHelp = model.focusedNode?.id
        for section in SupportSection.allCases {
            AppSupport.shared.show(section)
            try await pause()
            if let help = AppSupport.shared.window {
                check(help.isVisible, "Help topic opens: \(section.rawValue)")
                capture("help-\(section.rawValue)", in: help)
                help.setContentSize(NSSize(width: 620, height: 540))
                try await pause()
                check((help.contentView?.bounds.width ?? 9999) <= 621, "Help fits its minimum width")
            }
        }
        AppSupport.shared.window?.close()
        try await reviewSettings()
        window.makeKeyAndOrderFront(nil)
        try await reviewExtensionSlots(root)
        try await reviewCommunityFeatures(root)
        check(model.focusedNode?.id == selectedBeforeHelp, "Help leaves disk navigation intact")
        model.rootNode = nil
        model.focusedNode = nil
        model.selectedNode = nil
        try await pause()
        capture("welcome")

        let large = FileNode(name: "Large directory", path: "/tmp/lucid-review", isDirectory: true)
        for index in 0..<10_000 {
            let file = FileNode(name: "asset-\(index).bin", path: large.path + "/asset-\(index).bin",
                                isDirectory: false, size: Int64(10_000 - index))
            file.parent = large
            large.children.append(file)
            large.size += file.size
        }
        model.rootNode = large
        model.focusedNode = large
        try await pause()
        if let largeTable = contentsTable(rows: 10_000) {
            let rows = descendants(largeTable).filter { $0 is NSTableRowView }.count
            check(rows < 128, "10,000 entries use only visible native row views")
            largeTable.scrollRowToVisible(9_000)
            try await pause()
            let row = largeTable.rect(ofRow: 9_000)
            postClick(at: largeTable.convert(NSPoint(x: row.minX + 90, y: row.midY), to: nil), count: 1)
            try await pause()
            check(model.selectedNode?.id == large.children[9_000].id, "A deeply scrolled file remains selectable")
            if model.selectedNode?.id != large.children[9_000].id {
                print("DEEP_SELECTION selected=\(model.selectedNode?.name ?? "nil") row=\(largeTable.selectedRow) visible=\(largeTable.visibleRect)")
                capture("deep-selection-failure")
            }
        } else { failures.append("10,000-entry directory did not load") }
        try await reviewRealFileWorkflow()
    }

    /// Batch selection, saved-scan state and the space breakdown sheet.
    func reviewCommunityFeatures(_ root: FileNode) async throws {
        model.focus(on: root.children[1])
        try await pause()
        let files = root.children[1].children
        model.select(Array(files.prefix(3)), primary: files[2])
        try await pause(); try await pause()
        check(model.selectedNodes.count == 3, "Several files can be selected")
        capture("batch-selection")
        let outcome = model.addToReview(Array(files.prefix(3)))
        check(outcome.added == 3, "Batch adds items to the review queue")
        try await pause()
        capture("batch-queued")
        model.requestBatchDeletion()
        try await pause()
        check(model.pendingBatchDeletion?.items.count == 3, "Move All asks for confirmation with every item")
        capture("batch-confirmation")
        model.pendingBatchDeletion = nil
        model.clearReviewQueue()
        model.select([], primary: nil)

        let info = SavedScanInfo(id: UUID(), rootPath: root.path, rootName: root.name,
                                 scannedAt: Date().addingTimeInterval(-7_200), duration: 3.2, fileCount: 48,
                                 directoryCount: 7, logicalSizeBytes: root.size, allocatedSizeBytes: root.size,
                                 unreadableDirectoryCount: 0, duplicateHardLinkCount: 0, warnings: [],
                                 formatVersion: 1)
        model.show(savedScan: SavedScan(info: info, root: root))
        try await pause()
        check(model.isShowingSavedScan, "A saved scan opens as a snapshot")
        capture("saved-scan")
        model.requestDeletion(node: files[0])
        check(model.pendingDeletion == nil, "A saved scan never asks to move items to the Trash")
        model.errorMessage = nil
        model.snapshotDate = nil
        model.focus(on: root)

        if let breakdown = SpaceAnalyzer.breakdown(rootPath: "/", scannedBytes: 720_000_000_000, unreadableFolderCount: 12) {
            let sheet = NSWindow(contentRect: NSRect(x: 200, y: 160, width: 640, height: 600),
                                 styleMask: [.titled, .closable], backing: .buffered, defer: false)
            sheet.isReleasedWhenClosed = false
            sheet.contentView = NSHostingView(rootView: SpaceBreakdownView(breakdown: breakdown) {}
                .preferredColorScheme(.dark).tint(Theme.accent))
            sheet.makeKeyAndOrderFront(nil)
            try await pause(); try await pause()
            capture("space-breakdown", in: sheet)
            check(breakdown.items.reduce(0) { $0 + $1.bytes } == breakdown.usedBytes, "Space breakdown adds up to used space")
            sheet.close()
        }
        window.makeKeyAndOrderFront(nil)
    }

    /// Installs a throwaway edition to prove the open-core slots render, then removes it.
    func reviewExtensionSlots(_ root: FileNode) async throws {
        let extensions = LucidDiskExtensions.shared
        extensions.setEdition(EditionInfo(badge: "Preview"))
        extensions.addSidebarSection(SidebarContribution(id: "review.sidebar", title: "Extension slot") { context in
            AnyView(Label("\(context.rootNode?.name ?? "—") · \(context.reviewQueue.count) queued", systemImage: "puzzlepiece"))
        })
        extensions.addInspectorSection(InspectorContribution(id: "review.inspector") { node, _ in
            AnyView(Label("Extension card for \(node.name)", systemImage: "puzzlepiece").card())
        })
        model.selectedNode = root.children[0].children[0]
        try await pause(); try await pause()
        capture("extension-slots")
        check(extensions.sidebarSections.count == 1 && extensions.inspectorSections.count == 1, "Extension slots accept contributions")
        extensions.reset()
        model.selectedNode = nil
        try await pause()
        check(extensions.edition == .community, "Extension registry resets to Community")
    }

    func reviewSettings() async throws {
        // The harness has its own defaults domain, so this never changes the app's settings.
        let settings = InsightSettings.shared
        let previous = settings.provider
        defer { settings.provider = previous }
        let panes: [(String, InsightProviderKind?, AnyView)] = [
            ("settings-ai-claude", .claude, AnyView(InsightSettingsPane())),
            ("settings-ai-ollama", .ollama, AnyView(InsightSettingsPane())),
            ("settings-mcp", nil, AnyView(MCPSettingsPane()))
        ]
        for (name, provider, pane) in panes {
            if let provider { settings.provider = provider }
            let settingsWindow = NSWindow(contentRect: NSRect(x: 180, y: 140, width: 660, height: 640),
                                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
            settingsWindow.isReleasedWhenClosed = false
            settingsWindow.title = "Settings"
            settingsWindow.contentView = NSHostingView(rootView: pane.frame(width: 660, height: 640)
                .preferredColorScheme(.dark).tint(Theme.accent))
            settingsWindow.makeKeyAndOrderFront(nil)
            try await pause(); try await pause()
            check(settingsWindow.isVisible, "Settings pane renders: \(name)")
            capture(name, in: settingsWindow)
            settingsWindow.close()
        }
    }

    func reviewSearch(_ root: FileNode) async throws {
        guard let field = descendants(window.contentView!).compactMap({ $0 as? NSTextField })
            .first(where: { $0.isEditable && $0.placeholderString == String(localized: "Search all scanned files") }) else {
            failures.append("Search input missing"); return
        }
        window.makeFirstResponder(field)
        guard let editor = field.currentEditor() as? NSTextView else {
            failures.append("Search editor missing"); return
        }
        editor.selectAll(nil)
        editor.insertText("Lucid-launch-final", replacementRange: editor.selectedRange())
        try await pause()
        check(contentsTable(rows: 6) != nil, "Typed search finds nested files across the scan")
        editor.selectAll(nil)
        editor.insertText("Design library", replacementRange: editor.selectedRange())
        try await pause()
        if let results = contentsTable(rows: 9) {
            let row = results.rect(ofRow: 0)
            postClick(at: results.convert(NSPoint(x: row.minX + 90, y: row.midY), to: nil), count: 1)
            try await pause()
            postKey(36, characters: "\r")
            try await pause()
            check(model.focusedNode?.id == root.children[1].id, "Return opens a search-result folder")
            check(contentsTable(rows: 8) != nil, "Opening search result resets search to folder contents")
        } else { failures.append("Search results failed to update") }
        model.focus(on: root)
        try await pause()
    }

    func reviewRealFileWorkflow() async throws {
        // Only disposable files generated by this harness are moved to Trash.
        // Restore the exact returned Trash URL before removing our isolated fixture.
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".lucid-ui-fixture-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("lucid-preview-" + UUID().uuidString + ".txt")
        try Data("Lucid Disk disposable UI test. Preview and restore this fixture only.".utf8).write(to: file)
        model.startScan(path: directory.path)
        for _ in 0..<100 where model.isScanning { try await Task.sleep(for: .milliseconds(50)) }
        try await pause()
        guard let node = model.rootNode?.children.first, let table = contentsTable(rows: 1) else {
            failures.append("Real fixture scan failed"); return
        }
        check(node.name == file.lastPathComponent && node.fileIdentity != nil, "Real scan produces an inspectable file identity")
        let row = table.rect(ofRow: 0)
        postClick(at: table.convert(NSPoint(x: row.minX + 90, y: row.midY), to: nil), count: 1)
        try await pause()
        postKey(49, characters: " ")
        try await pause()
        check(window.attachedSheet != nil, "Space opens Quick Look for the selected real file")
        if let sheet = window.attachedSheet {
            capture("quick-look", in: sheet)
            postKey(53, characters: "\u{1b}", in: sheet)
            try await pause()
            check(window.attachedSheet == nil, "Escape closes Quick Look")
        }
        model.toggleReview(node: node)
        check(model.isQueued(node), "Review queue accepts the selected scanned file")
        model.requestDeletion(node: node)
        try await pause()
        check(model.pendingDeletion != nil && FileManager.default.fileExists(atPath: file.path), "Requesting Trash waits for confirmation")
        model.pendingDeletion = nil
        try await pause()
        check(FileManager.default.fileExists(atPath: file.path), "Cancelling confirmation keeps the file")
        model.requestDeletion(node: node)
        try await pause()
        model.confirmDeletion()
        for _ in 0..<100 where model.isMovingToTrash || model.isScanning { try await Task.sleep(for: .milliseconds(50)) }
        try await pause()
        check(model.errorMessage == nil && !FileManager.default.fileExists(atPath: file.path), "Confirmed fixture moves to macOS Trash")
        if let trashed = model.lastTrashedURL {
            check(FileManager.default.fileExists(atPath: trashed.path), "Trash destination exists and is recoverable")
            try FileManager.default.moveItem(at: trashed, to: file)
            check(FileManager.default.fileExists(atPath: file.path), "Fixture can be restored from Trash")
        } else { failures.append("Trash did not return a recoverable destination") }
        check(model.rootNode?.children.isEmpty == true && model.reviewQueue.isEmpty,
              "Successful removal refreshes scan and clears obsolete queue")
        check(model.completionMessage != nil, "Successful removal displays recovery guidance")
        capture("trash-complete")
    }

    func contentsTable(rows: Int) -> NSTableView? {
        descendants(window.contentView!).compactMap { $0 as? NSTableView }
            .first { $0.numberOfRows == rows && $0.bounds.width > 300 }
    }

    func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    func postClick(at point: NSPoint, count: Int) {
        for type: NSEvent.EventType in [.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                          timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: window.windowNumber, context: nil,
                                          eventNumber: 0, clickCount: count, pressure: 1)!
            NSApp.postEvent(event, atStart: false)
        }
    }

    func postKey(_ code: UInt16, characters: String, in target: NSWindow? = nil) {
        let target = target ?? window!
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                    timestamp: ProcessInfo.processInfo.systemUptime,
                                    windowNumber: target.windowNumber, context: nil,
                                    characters: characters, charactersIgnoringModifiers: characters,
                                    isARepeat: false, keyCode: code)!
        NSApp.postEvent(event, atStart: false)
    }

    func check(_ passed: Bool, _ name: String) {
        print("\(passed ? "PASS" : "FAIL") \(name)")
        fflush(stdout)
        if !passed { failures.append(name) }
    }

    func pause() async throws { try await Task.sleep(for: .milliseconds(350)) }

    func capture(_ name: String, in target: NSWindow? = nil) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-l", String((target ?? window!).windowNumber), output + "/\(name).png"]
        do {
            try process.run(); process.waitUntilExit()
            if process.terminationStatus != 0 { failures.append("Screenshot failed: \(name)") }
        }
        catch { failures.append("Capture \(name): \(error)") }
    }

    func fixture() -> FileNode {
        let root = FileNode(name: "Creative Studio", path: "/Users/demo/Creative Studio", isDirectory: true)
        for (index, name) in ["Video projects", "Design library", "Downloads", "Development", "Photography", "Documents"].enumerated() {
            let folder = FileNode(name: name, path: root.path + "/" + name, isDirectory: true, size: Int64(6 - index) * 1_500_000_000)
            folder.parent = root
            for childIndex in 0..<8 {
                let name = childIndex == 0 ? "Lucid-launch-final-2026.mov" : "Project asset \(childIndex).mov"
                let file = FileNode(name: name, path: folder.path + "/" + name, isDirectory: false,
                                    size: folder.size / 8, logicalSizeBytes: folder.size / 8)
                file.parent = folder
                folder.children.append(file)
            }
            root.children.append(folder)
            root.size += folder.size
        }
        return root
    }
}
