import XCTest
@testable import LucidDiskCore

final class ScanProgressLifecycleTests: XCTestCase {
    @MainActor
    func testStopKeepsTheSameScanContextUntilMeasuredResultsArePublished() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = ScanViewModel(mountedVolumesProvider: { [] })
        model.stopScan()
        assertIdleProgress(model)

        let before = Date()
        model.startScan(path: directory.path + "/./")
        let scanID = try XCTUnwrap(model.activeScanID)
        let startedAt = try XCTUnwrap(model.scanStartedAt)
        XCTAssertGreaterThanOrEqual(startedAt, before)
        XCTAssertLessThanOrEqual(startedAt, Date())
        XCTAssertEqual(model.scanTargetPath, directory.path)

        model.stopScan()
        model.stopScan()
        XCTAssertTrue(model.isScanning, "Stop must keep the loading screen until partial results are ready")
        XCTAssertTrue(model.isStoppingScan)
        XCTAssertEqual(model.activeScanID, scanID)
        XCTAssertEqual(model.scanStartedAt, startedAt, "The elapsed timer must not restart when Stop is pressed")
        XCTAssertEqual(model.scanTargetPath, directory.path)

        let measured = result(id: scanID, path: directory.path, stopped: true)
        model.finish(measured, for: scanID)

        assertIdleProgress(model)
        XCTAssertTrue(model.rootNode === measured.root)
        XCTAssertTrue(model.focusedNode === measured.root)
        XCTAssertEqual(model.scannedCount, 1)
        XCTAssertEqual(model.scannedBytes, 4_096)
        XCTAssertEqual(model.rootNode?.children.first?.name, "measured.txt")
        XCTAssertTrue(try XCTUnwrap(model.lastScanResult).wasStopped)
    }

    @MainActor
    func testSupersededResultCannotClearTheCurrentScansTimerTargetOrStoppingState() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = ScanViewModel(mountedVolumesProvider: { [] })
        model.startScan(path: directory.appendingPathComponent("old-missing-folder").path)
        let oldID = try XCTUnwrap(model.activeScanID)
        model.stopScan()

        model.startScan(path: directory.path)
        let currentID = try XCTUnwrap(model.activeScanID)
        let currentStart = try XCTUnwrap(model.scanStartedAt)
        XCTAssertNotEqual(oldID, currentID)
        XCTAssertFalse(model.isStoppingScan, "A new scan must not inherit an earlier stop request")
        model.stopScan()

        model.finish(result(id: oldID, path: "/old", stopped: true), for: oldID)

        XCTAssertTrue(model.isScanning)
        XCTAssertTrue(model.isStoppingScan)
        XCTAssertEqual(model.activeScanID, currentID)
        XCTAssertEqual(model.scanStartedAt, currentStart)
        XCTAssertEqual(model.scanTargetPath, directory.path)
        XCTAssertNil(model.rootNode)
        model.cancelScan()
    }

    @MainActor
    func testCancelClearsProgressContextAndLateCompletionCannotRestoreIt() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = ScanViewModel(mountedVolumesProvider: { [] })
        let retained = FileNode(name: "Retained", path: "/retained", isDirectory: true)
        model.rootNode = retained
        model.focusedNode = retained
        model.startScan(path: directory.path)
        let scanID = try XCTUnwrap(model.activeScanID)
        model.stopScan()
        model.cancelScan()
        assertIdleProgress(model)

        model.finish(result(id: scanID, path: directory.path, stopped: true), for: scanID)
        try await Task.sleep(for: .milliseconds(30))

        assertIdleProgress(model)
        XCTAssertTrue(model.rootNode === retained)
        XCTAssertTrue(model.focusedNode === retained)
    }

    @MainActor
    func testSuccessfulScanClearsProgressContextAndKeepsItsResults() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("fixture".utf8).write(to: directory.appendingPathComponent("file.txt"))
        let model = ScanViewModel(mountedVolumesProvider: { [] })
        model.startScan(path: directory.path)
        try await waitForScan(model)

        assertIdleProgress(model)
        XCTAssertEqual(model.rootNode?.path, directory.path)
        XCTAssertEqual(model.scannedCount, 1)
        XCTAssertFalse(try XCTUnwrap(model.lastScanResult).wasStopped)
    }

    @MainActor
    func testFailedScanClearsStoppingAndTimingWithoutDiscardingPreviousResults() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = ScanViewModel(mountedVolumesProvider: { [] })
        let retained = FileNode(name: "Retained", path: "/retained", isDirectory: true)
        model.rootNode = retained
        model.startScan(path: directory.appendingPathComponent("missing").path)
        model.stopScan()
        try await waitForScan(model)

        assertIdleProgress(model)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertTrue(model.rootNode === retained)
    }

    @MainActor
    private func assertIdleProgress(_ model: ScanViewModel, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(model.isScanning, file: file, line: line)
        XCTAssertFalse(model.isStoppingScan, file: file, line: line)
        XCTAssertNil(model.activeScanID, file: file, line: line)
        XCTAssertNil(model.scanStartedAt, file: file, line: line)
        XCTAssertEqual(model.scanTargetPath, "", file: file, line: line)
    }

    @MainActor
    private func waitForScan(_ model: ScanViewModel) async throws {
        for _ in 0..<200 where model.isScanning {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertFalse(model.isScanning)
    }

    private func result(id: UUID, path: String, stopped: Bool) -> ScanResult {
        let root = FileNode(name: "Measured", path: path, isDirectory: true, size: 4_096,
                            measurementAccuracy: stopped ? .incomplete : .estimated)
        let child = FileNode(name: "measured.txt", path: path + "/measured.txt", isDirectory: false, size: 4_096)
        child.parent = root
        root.children = [child]
        return ScanResult(id: id, root: root, duration: 3,
                          statistics: ScanStatistics(scannedFileCount: 1, scannedDirectoryCount: 1,
                                                     logicalSizeBytes: 4_096, allocatedSizeBytes: 4_096,
                                                     unreadableDirectoryCount: 0, duplicateHardLinkCount: 0),
                          warnings: [], wasStopped: stopped)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LucidProgress-" + UUID().uuidString, isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
