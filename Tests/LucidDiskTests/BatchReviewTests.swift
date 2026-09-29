import XCTest
@testable import LucidDiskCore

@MainActor
final class BatchReviewTests: XCTestCase {
    private func tree() -> (root: FileNode, folder: FileNode, child: FileNode, file: FileNode) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let root = FileNode(name: "Downloads", path: home + "/Downloads", isDirectory: true)
        let folder = FileNode(name: "Old", path: root.path + "/Old", isDirectory: true, size: 30)
        let child = FileNode(name: "a.zip", path: folder.path + "/a.zip", isDirectory: false, size: 30)
        let file = FileNode(name: "b.dmg", path: root.path + "/b.dmg", isDirectory: false, size: 20)
        folder.parent = root
        child.parent = folder
        file.parent = root
        root.children = [folder, file]
        folder.children = [child]
        return (root, folder, child, file)
    }

    func testPlainSelectionReplacesMultiSelection() {
        let vm = ScanViewModel()
        let t = tree()
        vm.select([t.folder, t.file], primary: t.file)
        XCTAssertEqual(vm.selectedNodes.map(\.id), [t.folder.id, t.file.id])
        XCTAssertEqual(vm.selectedNode?.id, t.file.id)

        vm.selectedNode = t.child
        XCTAssertEqual(vm.selectedNodes.map(\.id), [t.child.id])

        vm.selectedNode = nil
        XCTAssertTrue(vm.selectedNodes.isEmpty)
    }

    func testToggleSelectionAddsAndRemoves() {
        let vm = ScanViewModel()
        let t = tree()
        vm.toggleSelection(t.folder)
        vm.toggleSelection(t.file)
        XCTAssertEqual(vm.selectedNodes.count, 2)
        vm.toggleSelection(t.folder)
        XCTAssertEqual(vm.selectedNodes.map(\.id), [t.file.id])
        XCTAssertEqual(vm.selectedNode?.id, t.file.id)
    }

    func testBatchQueueSkipsProtectedGroupsAndDuplicates() {
        let vm = ScanViewModel()
        let t = tree()
        // `parent` is weak: keep the parent alive, or the node would count as a
        // scan root and be blocked by the wrong rule.
        let systemRoot = FileNode(name: "System", path: "/System", isDirectory: true)
        let system = FileNode(name: "Library", path: "/System/Library", isDirectory: true)
        system.parent = systemRoot
        XCTAssertEqual(DeletionSafety.assess(node: system).matchedRule, "protected.system")
        let group = FileNode(name: "Other", path: t.root.path, isDirectory: false, size: 1)
        group.isAggregate = true

        let first = vm.addToReview([t.file, system, group])
        XCTAssertEqual(first, BatchQueueOutcome(added: 1, alreadyQueued: 0, skippedProtected: 1, skippedGroups: 1))
        let second = vm.addToReview([t.file, t.folder])
        XCTAssertEqual(second.added, 1)
        XCTAssertEqual(second.alreadyQueued, 1)
        XCTAssertEqual(vm.reviewQueue.count, 2)
        withExtendedLifetime(systemRoot) {}

        vm.removeFromReview([t.file])
        XCTAssertEqual(vm.reviewQueue.map(\.id), [t.folder.id])
        vm.clearReviewQueue()
        XCTAssertTrue(vm.reviewQueue.isEmpty)
    }

    func testQueuedFolderTakesTheStricterPolicyOfQueuedItemsInside() {
        let t = tree()
        // A subfolder that could not be read completely needs a strong confirmation.
        let locked = FileNode(name: "locked", path: t.folder.path + "/locked", isDirectory: true)
        locked.parent = t.folder
        locked.measurementAccuracy = .incomplete
        XCTAssertEqual(DeletionSafety.assess(node: t.folder).actionPolicy, .standardConfirmation)
        XCTAssertEqual(DeletionSafety.assess(node: locked).actionPolicy, .strongConfirmation)

        let vm = ScanViewModel()
        vm.reviewQueue = [t.folder, locked]
        vm.requestBatchDeletion()
        let pending = try? XCTUnwrap(vm.pendingBatchDeletion)
        XCTAssertEqual(pending?.items.map(\.node.id), [t.folder.id])
        XCTAssertEqual(pending?.excludedNested, 1)
        XCTAssertEqual(pending?.requiresStrongConfirmation, true,
                       "Moving the folder moves the child, so its stronger confirmation carries over")
        withExtendedLifetime(t.root) {}
    }

    func testNestedQueueItemsMoveWithTheirFolder() {
        let t = tree()
        let top = ScanViewModel.topLevelItems([t.child, t.folder, t.file])
        XCTAssertEqual(Set(top.map(\.id)), [t.folder.id, t.file.id])
    }

    func testSavedScanBlocksBatchTrash() {
        let vm = ScanViewModel()
        let t = tree()
        vm.addToReview([t.file])
        vm.snapshotDate = Date()
        vm.requestBatchDeletion()
        XCTAssertNil(vm.pendingBatchDeletion)
        XCTAssertEqual(vm.errorMessage, ScanViewModel.savedScanTrashMessage)

        vm.errorMessage = nil
        vm.requestDeletion(node: t.file)
        XCTAssertNil(vm.pendingDeletion)
        XCTAssertEqual(vm.errorMessage, ScanViewModel.savedScanTrashMessage)
    }

    func testBatchTrashRevalidatesEachItemAndReportsSkips() async throws {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".lucid-batch-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("folder"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for name in ["keep-me.txt", "one.txt", "folder/nested.txt"] {
            try Data(name.utf8).write(to: directory.appendingPathComponent(name))
        }
        let vm = ScanViewModel()
        vm.startScan(path: directory.path)
        for _ in 0..<200 where vm.isScanning { try await Task.sleep(for: .milliseconds(5)) }
        let root = try XCTUnwrap(vm.rootNode)
        let folder = try XCTUnwrap(root.children.first { $0.name == "folder" })
        let nested = try XCTUnwrap(folder.children.first)
        let one = try XCTUnwrap(root.children.first { $0.name == "one.txt" })
        let keep = try XCTUnwrap(root.children.first { $0.name == "keep-me.txt" })

        vm.addToReview([folder, nested, one, keep])
        vm.requestBatchDeletion()
        let pending = try XCTUnwrap(vm.pendingBatchDeletion)
        XCTAssertEqual(pending.items.count, 3)
        XCTAssertEqual(pending.excludedNested, 1)

        // Replace one file after the scan: its identity no longer matches.
        let keepURL = directory.appendingPathComponent("keep-me.txt")
        try FileManager.default.removeItem(at: keepURL)
        try Data("replacement".utf8).write(to: keepURL)

        let outcome = ScanViewModel.moveToTrash(pending.items.map(\.node))
        defer {
            for destination in outcome.destinations {
                try? FileManager.default.removeItem(at: destination)
            }
        }
        XCTAssertEqual(outcome.moved, 2)
        XCTAssertEqual(outcome.failures.count, 1)
        XCTAssertTrue(outcome.failures[0].hasPrefix("keep-me.txt"))
        XCTAssertEqual(try String(contentsOf: keepURL, encoding: .utf8), "replacement")
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("folder").path))
        XCTAssertTrue(outcome.destinations.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        vm.pendingBatchDeletion = nil
    }
}
