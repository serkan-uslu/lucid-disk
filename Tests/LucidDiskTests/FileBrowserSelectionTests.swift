import AppKit
import XCTest
@testable import LucidDiskCore

@MainActor
final class FileBrowserSelectionTests: XCTestCase {
    func testProgrammaticPrimaryDrivesActionsAndChangesWithoutChangingSelectedSet() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.click(0)
        fixture.click(2, modifiers: .command)
        let selectionChanges = fixture.selectionChanges
        fixture.model.select([fixture.nodes[0], fixture.nodes[2]], primary: fixture.nodes[0])
        // Native lead is not always the smallest selected index. A model-driven
        // primary change can leave it on a different item until synchronization.
        XCTAssertEqual(fixture.table.selectedRow, 2)
        XCTAssertEqual(fixture.model.selectedNode?.id, fixture.nodes[0].id)
        fixture.sync()

        XCTAssertEqual(fixture.table.selectedRowIndexes, IndexSet([0, 2]))
        XCTAssertEqual(fixture.table.selectedRow, 0)
        fixture.key(36)
        fixture.key(124)
        fixture.key(49)
        XCTAssertEqual(fixture.opened, [fixture.nodes[0].id, fixture.nodes[0].id])
        XCTAssertEqual(fixture.previewed, [fixture.nodes[0].id])

        fixture.model.select([fixture.nodes[0], fixture.nodes[2]], primary: fixture.nodes[2])
        fixture.sync()
        XCTAssertEqual(fixture.table.selectedRowIndexes, IndexSet([0, 2]))
        fixture.key(49)
        XCTAssertEqual(fixture.previewed.last, fixture.nodes[2].id)
        XCTAssertEqual(fixture.selectionChanges, selectionChanges, "Model synchronization must not publish a second selection")
    }

    func testCommandClickActionsUseTheNewPrimaryBeforeSwiftUIUpdates() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.click(1) // A file must not prevent the later selected folder from opening.
        fixture.click(3, modifiers: .command)
        XCTAssertEqual(fixture.table.selectedRowIndexes, IndexSet([1, 3]))
        XCTAssertEqual(fixture.model.selectedNode?.id, fixture.nodes[3].id)
        // No sync(): the representable still holds its earlier selection inputs.
        fixture.key(36)
        fixture.key(124)
        fixture.key(49)
        XCTAssertEqual(fixture.opened, [fixture.nodes[3].id, fixture.nodes[3].id])
        XCTAssertEqual(fixture.previewed, [fixture.nodes[3].id])
    }

    func testNativeKeyboardAndShiftSelectionsKeepTheirLead() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.model.select([fixture.nodes[0], fixture.nodes[2]], primary: fixture.nodes[0])
        fixture.sync()
        fixture.key(125) // Down starts from the model primary, not the other selected row.
        XCTAssertEqual(fixture.table.selectedRowIndexes, IndexSet(integer: 1))
        XCTAssertEqual(fixture.model.selectedNode?.id, fixture.nodes[1].id)
        fixture.key(125, modifiers: .shift)
        XCTAssertEqual(fixture.table.selectedRowIndexes, IndexSet([1, 2]))
        XCTAssertEqual(fixture.model.selectedNode?.id, fixture.nodes[2].id)
        fixture.key(49)
        XCTAssertEqual(fixture.previewed.last, fixture.nodes[2].id)
        fixture.key(126, modifiers: .shift)
        XCTAssertEqual(fixture.table.selectedRowIndexes, IndexSet(integer: 1))
        XCTAssertEqual(fixture.model.selectedNode?.id, fixture.nodes[1].id)
        fixture.key(49)
        XCTAssertEqual(fixture.previewed.last, fixture.nodes[1].id)

        fixture.click(3, modifiers: .shift)
        XCTAssertEqual(fixture.table.selectedRowIndexes, IndexSet([1, 2, 3]))
        XCTAssertEqual(fixture.model.selectedNode?.id, fixture.nodes[3].id)
        fixture.key(36)
        XCTAssertEqual(fixture.opened.last, fixture.nodes[3].id)
    }

    func testSortingAndFilteringResolvePrimaryIdentityInsteadOfAnOldRow() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.model.select([fixture.nodes[0], fixture.nodes[3]], primary: fixture.nodes[0])
        fixture.sync()
        fixture.contents = BrowserContents(nodes: [fixture.nodes[3], fixture.nodes[2], fixture.nodes[0], fixture.nodes[1]])
        fixture.sync()
        XCTAssertEqual(fixture.table.selectedRowIndexes, IndexSet([0, 2]))
        XCTAssertEqual(fixture.table.selectedRow, 2)
        fixture.key(36)
        fixture.key(49)
        XCTAssertEqual(fixture.opened, [fixture.nodes[0].id])
        XCTAssertEqual(fixture.previewed, [fixture.nodes[0].id])

        fixture.contents = BrowserContents(nodes: [fixture.nodes[3], fixture.nodes[2]])
        fixture.sync()
        XCTAssertEqual(fixture.table.selectedRowIndexes, IndexSet(integer: 0))
        fixture.key(36)
        fixture.key(49)
        XCTAssertEqual(fixture.opened.count, 1, "A hidden primary must not become another visible item")
        XCTAssertEqual(fixture.previewed.count, 1)

        fixture.model.select([], primary: nil)
        fixture.sync()
        fixture.key(36)
        fixture.key(49)
        XCTAssertEqual(fixture.opened.count, 1)
        XCTAssertEqual(fixture.previewed.count, 1)
    }

    func testDoubleClickOpensClickedRowEvenWhenAnotherSelectedRowIsPrimary() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.click(0)
        fixture.click(3, modifiers: .command)
        XCTAssertEqual(fixture.model.selectedNode?.id, fixture.nodes[3].id)
        fixture.click(0, count: 2)
        XCTAssertEqual(fixture.opened, [fixture.nodes[0].id])
    }

    func testSingleFilesPreviewAndAggregateGroupsOnlyOpen() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.click(1)
        fixture.key(36)
        fixture.key(49)
        XCTAssertTrue(fixture.opened.isEmpty)
        XCTAssertEqual(fixture.previewed, [fixture.nodes[1].id])

        fixture.click(4)
        fixture.key(36)
        fixture.key(49)
        XCTAssertEqual(fixture.opened, [fixture.nodes[4].id])
        XCTAssertEqual(fixture.previewed, [fixture.nodes[1].id])
        XCTAssertFalse(fixture.window.isVisible)
    }

    func testCopyMetadataButtonClickKeepsTheNativeSelectionAndDoesNotOpenTheFolder() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.click(0)
        fixture.click(3, modifiers: .command)
        let selectionChanges = fixture.selectionChanges
        try fixture.clickCopyMetadataButton(row: 0)
        XCTAssertEqual(fixture.copied.map(\.id), [fixture.nodes[0].id])
        XCTAssertEqual(fixture.table.selectedRowIndexes, IndexSet([0, 3]))
        XCTAssertEqual(fixture.model.selectedNode?.id, fixture.nodes[3].id)
        XCTAssertEqual(fixture.selectionChanges, selectionChanges)
        XCTAssertTrue(fixture.opened.isEmpty)
        XCTAssertTrue(fixture.previewed.isEmpty)
    }

    func testCopyMetadataUsesClickedSelectedItemWithoutChangingThePrimaryOrNavigating() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.click(1) // A real file.
        fixture.click(3, modifiers: .command) // The other selected item becomes primary.
        let selectedRows = fixture.table.selectedRowIndexes
        let selectedIDs = Set(fixture.model.selectedNodes.map(\.id))
        let selectionChanges = fixture.selectionChanges
        XCTAssertEqual(fixture.model.selectedNode?.id, fixture.nodes[3].id)

        // No SwiftUI synchronization: native selection must already authorize the action.
        fixture.copyMetadata(fixture.nodes[1].id)
        fixture.copyMetadata(fixture.nodes[3].id)

        XCTAssertEqual(fixture.copied.map(\.id), [fixture.nodes[1].id, fixture.nodes[3].id])
        XCTAssertEqual(fixture.table.selectedRowIndexes, selectedRows)
        XCTAssertEqual(Set(fixture.model.selectedNodes.map(\.id)), selectedIDs)
        XCTAssertEqual(fixture.model.selectedNode?.id, fixture.nodes[3].id)
        XCTAssertEqual(fixture.selectionChanges, selectionChanges)
        XCTAssertTrue(fixture.opened.isEmpty)
        XCTAssertTrue(fixture.previewed.isEmpty)
    }

    func testCopyMetadataResolvesTheCurrentNodeAfterSortingAndScanRevision() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.model.select([fixture.nodes[0]], primary: fixture.nodes[0])
        fixture.sync()
        let updated = fixture.nodes[0].copyForRevision()
        updated.allocatedSizeBytes = 42_000
        updated.logicalSizeBytes = 39_000
        fixture.contents = BrowserContents(nodes: [fixture.nodes[3], updated, fixture.nodes[1]])
        fixture.sync()

        // A queued action carries identity, not an old row number or captured scan node.
        fixture.copyMetadata(fixture.nodes[0].id)

        let copied = try XCTUnwrap(fixture.copied.last)
        XCTAssertTrue(copied === updated)
        XCTAssertFalse(copied === fixture.nodes[0])
        XCTAssertEqual(copied.allocatedSizeBytes, 42_000)
        XCTAssertEqual(copied.logicalSizeBytes, 39_000)
        XCTAssertEqual(fixture.table.selectedRowIndexes, IndexSet(integer: 1))
    }

    func testCopyMetadataRejectsHiddenDeselectedAndUnknownRows() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.click(0)
        fixture.copyMetadata(fixture.nodes[1].id)
        fixture.copyMetadata(UUID())
        XCTAssertTrue(fixture.copied.isEmpty)

        fixture.contents = BrowserContents(nodes: [fixture.nodes[1], fixture.nodes[3]])
        fixture.sync()
        fixture.copyMetadata(fixture.nodes[0].id)
        XCTAssertTrue(fixture.copied.isEmpty, "An action from a filtered-out row must not copy a replacement row")

        fixture.click(1)
        fixture.copyMetadata(fixture.nodes[3].id)
        XCTAssertEqual(fixture.copied.map(\.id), [fixture.nodes[3].id])
        fixture.model.select([], primary: nil)
        fixture.sync()
        fixture.copyMetadata(fixture.nodes[3].id)
        XCTAssertEqual(fixture.copied.count, 1, "Deselecting an item invalidates its old copy action")
    }

    func testCopyMetadataRejectsSyntheticAggregateRows() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.click(4)
        XCTAssertTrue(fixture.nodes[4].isAggregate)
        fixture.copyMetadata(fixture.nodes[4].id)
        XCTAssertTrue(fixture.copied.isEmpty)
        XCTAssertEqual(fixture.model.selectedNode?.id, fixture.nodes[4].id)
        XCTAssertTrue(fixture.opened.isEmpty)
    }

    /// Uses the production table and AppKit's selection handling in an unordered window.
    /// Mouse-up is queued for NSTableView's tracking loop; no app activation is needed.
    @MainActor
    private final class Fixture {
        let nodes: [FileNode]
        let model = ScanViewModel()
        var contents: BrowserContents
        var opened: [UUID] = []
        var previewed: [UUID] = []
        var copied: [FileNode] = []
        var selectionChanges = 0
        let window: NSWindow
        var coordinator: FileBrowserTable.Coordinator!
        var scroll: NSScrollView!
        var table: NSTableView!

        init() throws {
            _ = NSApplication.shared
            nodes = (0..<5).map {
                FileNode(name: "Item \($0)", path: "/tmp/lucid-table-item-\($0)", isDirectory: $0 != 1 && $0 != 4)
            }
            nodes[4].isAggregate = true
            contents = BrowserContents(nodes: nodes)
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 400),
                              styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let view = representation
            coordinator = view.makeCoordinator()
            scroll = view.makeScrollView(coordinator: coordinator)
            window.contentView = scroll
            table = try XCTUnwrap(scroll.documentView as? NSTableView)
            table.setFrameSize(NSSize(width: 480, height: 400))
            sync()
            window.makeFirstResponder(table)
        }

        private var representation: FileBrowserTable {
            FileBrowserTable(contents: contents, selectedIDs: Set(model.selectedNodes.map(\.id)),
                             primaryID: model.selectedNode?.id, total: 1, showPath: false,
                             onSelect: { [weak self] nodes, primary in
                                 self?.selectionChanges += 1
                                 self?.model.select(nodes, primary: primary)
                             }, onOpen: { [weak self] in self?.opened.append($0.id) },
                             onPreview: { [weak self] in self?.previewed.append($0.id) },
                             onCopyMetadata: { [weak self] in self?.copied.append($0) })
        }

        func sync() { representation.updateTable(in: scroll, coordinator: coordinator) }

        func copyMetadata(_ id: UUID) { coordinator.copyMetadata(for: id, in: table) }

        func click(_ row: Int, modifiers: NSEvent.ModifierFlags = [], count: Int = 1) {
            let point = table.convert(NSPoint(x: 80, y: table.rect(ofRow: row).midY), to: nil)
            func event(_ type: NSEvent.EventType) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: point, modifierFlags: modifiers,
                                   timestamp: ProcessInfo.processInfo.systemUptime,
                                   windowNumber: window.windowNumber, context: nil,
                                   eventNumber: 0, clickCount: count, pressure: 1)!
            }
            NSApp.postEvent(event(.leftMouseUp), atStart: true)
            table.mouseDown(with: event(.leftMouseDown))
        }

        func clickCopyMetadataButton(row: Int) throws {
            // Dispatch through the actual hit view in the production row. This also
            // exercises native selection-triggered host refresh before SwiftUI sync.
            for _ in 0..<5 {
                window.contentView?.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            }
            let host = try XCTUnwrap(table.view(atColumn: 0, row: row, makeIfNecessary: true))
            // In a selected folder's trailing column, Copy Metadata is above Open Folder.
            let point = host.convert(NSPoint(x: host.bounds.maxX - 60, y: host.bounds.midY - 10), to: nil)
            let target = try XCTUnwrap(window.contentView?.hitTest(point))
            func event(_ type: NSEvent.EventType) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                   timestamp: ProcessInfo.processInfo.systemUptime,
                                   windowNumber: window.windowNumber, context: nil,
                                   eventNumber: 0, clickCount: 1, pressure: 1)!
            }
            NSApp.postEvent(event(.leftMouseUp), atStart: true)
            target.mouseDown(with: event(.leftMouseDown))
            for _ in 0..<5 { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        }

        func key(_ code: UInt16, modifiers: NSEvent.ModifierFlags = []) {
            let characters: String
            switch code {
            case 36: characters = "\r"
            case 49: characters = " "
            case 124: characters = "\u{f703}"
            case 125: characters = "\u{f701}"
            case 126: characters = "\u{f700}"
            default: preconditionFailure("Unsupported test key")
            }
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                                        timestamp: ProcessInfo.processInfo.systemUptime,
                                        windowNumber: window.windowNumber, context: nil,
                                        characters: characters, charactersIgnoringModifiers: characters,
                                        isARepeat: false, keyCode: code)!
            table.keyDown(with: event)
        }

        func close() {
            XCTAssertFalse(window.isVisible, "The fixture must never take over the desktop")
            window.close()
        }
    }
}
