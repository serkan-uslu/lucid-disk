import XCTest
@testable import LucidDiskCore

final class ScanViewModelTests: XCTestCase {
    @MainActor
    func testNewScanInvalidatesPreviousScanID() throws {
        let firstRoot = temporaryDirectory()
        let secondRoot = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: firstRoot)
            try? FileManager.default.removeItem(at: secondRoot)
        }
        let viewModel = ScanViewModel()

        viewModel.startScan(path: firstRoot.path)
        let firstID = try XCTUnwrap(viewModel.activeScanID)
        viewModel.startScan(path: secondRoot.path)
        let secondID = try XCTUnwrap(viewModel.activeScanID)

        XCTAssertNotEqual(firstID, secondID)
        XCTAssertFalse(viewModel.isCurrentScan(firstID))
        XCTAssertTrue(viewModel.isCurrentScan(secondID))

        let staleRoot = FileNode(name: "Stale", path: firstRoot.path, isDirectory: true)
        let staleResult = ScanResult(
            id: firstID,
            root: staleRoot,
            duration: 0,
            statistics: ScanStatistics(
                scannedFileCount: 0,
                scannedDirectoryCount: 1,
                logicalSizeBytes: 0,
                allocatedSizeBytes: 0,
                unreadableDirectoryCount: 0,
                duplicateHardLinkCount: 0
            ),
            warnings: []
        )
        viewModel.finish(staleResult, for: firstID)

        XCTAssertNil(viewModel.rootNode)
        XCTAssertTrue(viewModel.isCurrentScan(secondID))
        viewModel.cancelScan()
    }

    @MainActor
    func testCancelledRescanKeepsCompletedSnapshotSelectionAndQueue() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("fixture".utf8).write(to: directory.appendingPathComponent("file.txt"))
        let vm = ScanViewModel()
        vm.startScan(path: directory.path)
        try await waitForScan(vm)
        let root = try XCTUnwrap(vm.rootNode)
        let node = try XCTUnwrap(root.children.first)
        vm.selectedNode = node
        vm.toggleReview(node: node)
        vm.startScan(path: directory.path)
        vm.cancelScan()
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(vm.rootNode?.id, root.id)
        XCTAssertEqual(vm.selectedNode?.id, node.id)
        XCTAssertTrue(vm.isQueued(node))
        XCTAssertFalse(vm.isScanning)
    }

    @MainActor
    func testFailedRescanKeepsSnapshotAndReportsError() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let vm = ScanViewModel()
        vm.startScan(path: directory.path)
        try await waitForScan(vm)
        let root = try XCTUnwrap(vm.rootNode)
        vm.startScan(path: directory.appendingPathComponent("does-not-exist").path)
        try await waitForScan(vm)
        XCTAssertEqual(vm.rootNode?.id, root.id)
        XCTAssertNotNil(vm.errorMessage)
    }

    @MainActor
    func testStaleConfirmationCannotTrashAnItemRemovedFromQueue() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("file.txt")
        try Data("fixture".utf8).write(to: file)
        let vm = ScanViewModel()
        vm.startScan(path: directory.path)
        try await waitForScan(vm)
        let node = try XCTUnwrap(vm.rootNode?.children.first)
        vm.toggleReview(node: node)
        vm.requestDeletion(node: node)
        XCTAssertNotNil(vm.pendingDeletion)
        vm.removeFromReview(node: node)
        vm.confirmDeletion()
        XCTAssertNil(vm.pendingDeletion)
        XCTAssertFalse(vm.isMovingToTrash)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    @MainActor
    func testAsyncTrashRevalidatesIdentityAndLeavesReplacementUntouched() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("file.txt")
        try Data("original".utf8).write(to: file)
        let vm = ScanViewModel()
        vm.startScan(path: directory.path)
        try await waitForScan(vm)
        let node = try XCTUnwrap(vm.rootNode?.children.first)
        vm.toggleReview(node: node)
        vm.requestDeletion(node: node)
        XCTAssertNotNil(vm.pendingDeletion)
        try FileManager.default.moveItem(at: file, to: directory.appendingPathComponent("original.txt"))
        try Data("replacement".utf8).write(to: file)
        vm.confirmDeletion()
        for _ in 0..<200 where vm.isMovingToTrash { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertFalse(vm.isMovingToTrash)
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertNil(vm.lastTrashedURL)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "replacement")
    }

    @MainActor
    func testStopPublishesPartialScanInsteadOfReturningToWelcome() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for index in 0..<20 { try Data("fixture".utf8).write(to: directory.appendingPathComponent("file-\(index).txt")) }
        let vm = ScanViewModel()
        vm.startScan(path: directory.path)
        vm.stopScan()
        try await waitForScan(vm)
        let root = try XCTUnwrap(vm.rootNode)
        XCTAssertEqual(root.path, directory.path)
        XCTAssertEqual(vm.focusedNode?.id, root.id)
        XCTAssertTrue(try XCTUnwrap(vm.lastScanResult).wasStopped)
        XCTAssertEqual(root.measurementAccuracy, .incomplete)
        XCTAssertFalse(vm.isShowingSavedScan)
    }

    @MainActor
    func testFolderRescanReplacesSubtreePreservesFocusAndQueueAndHardLinks() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let folder = directory.appendingPathComponent("folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let original = folder.appendingPathComponent("original.bin")
        let link = directory.appendingPathComponent("link.bin")
        try Data(repeating: 0xA5, count: 16_384).write(to: original)
        try FileManager.default.linkItem(at: original, to: link)
        let vm = ScanViewModel()
        vm.startScan(path: directory.path)
        try await waitForScan(vm)
        let root = try XCTUnwrap(vm.rootNode)
        let beforeBytes = root.allocatedSizeBytes
        let beforeRevision = vm.treeRevision
        let oldFolder = try XCTUnwrap(root.children.first { $0.name == "folder" })
        let oldOriginal = try XCTUnwrap(oldFolder.children.first)
        vm.focus(on: oldFolder)
        vm.selectedNode = oldOriginal
        vm.toggleReview(node: oldOriginal)
        vm.rescanFolder(oldFolder)
        try await waitForScan(vm)
        XCTAssertEqual(vm.rootNode?.id, root.id)
        XCTAssertEqual(vm.rootNode?.allocatedSizeBytes, beforeBytes)
        XCTAssertFalse(vm.rootNode === root)
        XCTAssertEqual(root.children.first { $0.name == "folder" }?.id, oldFolder.id, "Previously published trees stay immutable")
        XCTAssertEqual(vm.lastScanResult?.statistics.duplicateHardLinkCount, 1)
        XCTAssertEqual(vm.focusedNode?.path, folder.path)
        XCTAssertNotEqual(vm.focusedNode?.id, oldFolder.id)
        XCTAssertEqual(vm.selectedNode?.path, original.path)
        XCTAssertEqual(vm.reviewQueue.map(\.path), [original.path])
        XCTAssertNotEqual(vm.treeRevision, beforeRevision)

        // Removing the counted link in this subtree must reattribute allocation
        // to the surviving link outside the subtree.
        try FileManager.default.removeItem(at: original)
        vm.rescanFolder(try XCTUnwrap(vm.focusedNode))
        try await waitForScan(vm)
        XCTAssertEqual(vm.rootNode?.allocatedSizeBytes, beforeBytes)
        XCTAssertEqual(vm.lastScanResult?.statistics.duplicateHardLinkCount, 0)
        XCTAssertTrue(vm.reviewQueue.isEmpty)
        XCTAssertNil(vm.selectedNode)
    }

    @MainActor
    func testReplacementAtQueuedPathDoesNotInheritReviewAfterFolderRescan() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("file.txt")
        try Data("original".utf8).write(to: file)
        let vm = ScanViewModel()
        vm.startScan(path: directory.path)
        try await waitForScan(vm)
        let old = try XCTUnwrap(vm.rootNode?.children.first)
        vm.toggleReview(node: old)
        try FileManager.default.moveItem(at: file, to: directory.appendingPathComponent("moved.txt"))
        try Data("replacement".utf8).write(to: file)
        vm.rescanFolder(try XCTUnwrap(vm.rootNode))
        try await waitForScan(vm)
        XCTAssertTrue(vm.reviewQueue.isEmpty)
        XCTAssertEqual(vm.rootNode?.children.count, 2)
    }

    @MainActor
    func testActivationRemovesExternallyDeletedVisibleItemAndUpdatesTotals() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("file.txt")
        try Data("fixture".utf8).write(to: file)
        let vm = ScanViewModel()
        vm.startScan(path: directory.path)
        try await waitForScan(vm)
        let node = try XCTUnwrap(vm.rootNode?.children.first)
        vm.selectedNode = node
        vm.toggleReview(node: node)
        let revision = vm.treeRevision
        let originalRoot = try XCTUnwrap(vm.rootNode)
        let originalResultID = vm.lastScanResult?.id
        try FileManager.default.removeItem(at: file)
        vm.refreshAfterActivation()
        for _ in 0..<200 where vm.treeRevision == revision { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertNotEqual(vm.treeRevision, revision)
        XCTAssertTrue(try XCTUnwrap(vm.rootNode).children.isEmpty)
        XCTAssertEqual(originalRoot.children.count, 1, "Background readers retain the old immutable tree")
        XCTAssertNotEqual(vm.lastScanResult?.id, originalResultID)
        XCTAssertEqual(vm.rootNode?.allocatedSizeBytes, 0)
        XCTAssertEqual(vm.lastScanResult?.statistics.scannedFileCount, 0)
        XCTAssertTrue(vm.reviewQueue.isEmpty)
        XCTAssertNil(vm.selectedNode)
    }

    @MainActor
    func testActivationDoesNotRewriteSavedSnapshot() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("file.txt")
        try Data("fixture".utf8).write(to: file)
        let vm = ScanViewModel()
        vm.startScan(path: directory.path)
        try await waitForScan(vm)
        vm.snapshotDate = .now
        let revision = vm.treeRevision
        try FileManager.default.removeItem(at: file)
        vm.refreshAfterActivation()
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(vm.treeRevision, revision)
        XCTAssertEqual(vm.rootNode?.children.count, 1)
        XCTAssertTrue(vm.isShowingSavedScan)
    }

    @MainActor
    func testRescanningSavedFolderProducesOnlyFreshFolderTree() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let folder = directory.appendingPathComponent("folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let vm = ScanViewModel()
        vm.startScan(path: directory.path)
        try await waitForScan(vm)
        vm.snapshotDate = .now
        vm.rescanFolder(try XCTUnwrap(vm.rootNode?.children.first))
        try await waitForScan(vm)
        XCTAssertEqual(vm.rootNode?.path, folder.path)
        XCTAssertFalse(vm.isShowingSavedScan)
    }

    @MainActor
    func testStoppedFolderRescanRetainsStrongConfirmationForPartialFolder() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let folder = directory.appendingPathComponent("folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for index in 0..<30 { try Data("fixture".utf8).write(to: folder.appendingPathComponent("file-\(index)")) }
        let vm = ScanViewModel()
        vm.startScan(path: directory.path)
        try await waitForScan(vm)
        vm.rescanFolder(try XCTUnwrap(vm.rootNode?.children.first))
        vm.stopScan()
        try await waitForScan(vm)
        let partial = try XCTUnwrap(vm.rootNode?.children.first)
        XCTAssertEqual(partial.measurementAccuracy, .incomplete)
        XCTAssertEqual(DeletionSafety.assess(node: partial).actionPolicy, .strongConfirmation)
    }

    @MainActor
    func testActivationPreservesUnavailableRootInsteadOfTreatingItAsEmpty() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("fixture".utf8).write(to: directory.appendingPathComponent("file.txt"))
        let vm = ScanViewModel()
        vm.startScan(path: directory.path)
        try await waitForScan(vm)
        let revision = vm.treeRevision
        let root = try XCTUnwrap(vm.rootNode)
        try FileManager.default.removeItem(at: directory)
        vm.refreshAfterActivation()
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(vm.treeRevision, revision)
        XCTAssertTrue(vm.rootNode === root)
        XCTAssertEqual(vm.rootNode?.children.count, 1)
    }

    @MainActor
    func testActivationRemovesMissingFocusedFolderAndReturnsToExistingParent() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let folder = directory.appendingPathComponent("folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let vm = ScanViewModel()
        vm.startScan(path: directory.path)
        try await waitForScan(vm)
        vm.focus(on: try XCTUnwrap(vm.rootNode?.children.first))
        let revision = vm.treeRevision
        try FileManager.default.removeItem(at: folder)
        vm.refreshAfterActivation()
        for _ in 0..<200 where vm.treeRevision == revision { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(vm.focusedNode?.id, vm.rootNode?.id)
        XCTAssertTrue(try XCTUnwrap(vm.rootNode).children.isEmpty)
    }

    @MainActor
    private func waitForScan(_ vm: ScanViewModel) async throws {
        for _ in 0..<200 where vm.isScanning { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertFalse(vm.isScanning, "Scan did not finish within the test deadline")
    }

    private func temporaryDirectory() -> URL {
        // System temporary directories are deliberately blocked by the Trash policy.
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".lucid-test-" + UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
