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
