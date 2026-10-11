import XCTest
@testable import LucidDiskCore

final class ScanSavingTests: XCTestCase {
    private var directory: URL!
    private var folder: URL { directory.appendingPathComponent("source", isDirectory: true) }
    private var storeURL: URL { directory.appendingPathComponent("saved", isDirectory: true) }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lucid-saving-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: folder.appendingPathComponent("file.txt"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    @MainActor
    func testFailedSavePreservesResultAndRetriesAfterStoreIsRepaired() async throws {
        try Data("directory blocker".utf8).write(to: storeURL)
        let store = ScanStore(directory: storeURL)
        let vm = ScanViewModel(scanStore: store, savingEnabled: { true })
        vm.startScan(path: folder.path)
        try await waitUntil { !vm.isScanning && vm.saveState == .failed }
        let result = try XCTUnwrap(vm.lastScanResult)
        let root = try XCTUnwrap(vm.rootNode)
        let revision = vm.treeRevision
        XCTAssertNil(vm.errorMessage, "Saving failures must not be presented as scan failures")
        XCTAssertFalse(vm.isShowingSavedScan)
        XCTAssertEqual(root.children.first?.name, "file.txt")
        XCTAssertTrue(vm.focusedNode === root)
        XCTAssertFalse(try ScanArchive.encode(root: root).isEmpty, "The completed tree remains exportable")
        XCTAssertTrue(vm.savedScans.isEmpty)

        try FileManager.default.removeItem(at: storeURL)
        vm.retrySave()
        XCTAssertEqual(vm.saveState, .saving)
        XCTAssertFalse(vm.isScanning)
        try await waitUntil { vm.saveState == .saved }
        XCTAssertTrue(vm.rootNode === root)
        XCTAssertEqual(vm.lastScanResult?.id, result.id)
        XCTAssertEqual(vm.treeRevision, revision)
        XCTAssertEqual(vm.savedScans.map(\.id), [result.id])
        XCTAssertEqual(try store.load(XCTUnwrap(store.list().first)).root.children.first?.name, "file.txt")
    }

    @MainActor
    func testSavingDisabledDoesNotAttemptOrOfferRetry() async throws {
        let gate = ControlledSave()
        let vm = controlledModel(gate, enabled: { false })
        vm.startScan(path: folder.path)
        try await waitUntil { !vm.isScanning }
        vm.retrySave()
        XCTAssertEqual(vm.saveState, .idle)
        XCTAssertNotNil(vm.rootNode)
        XCTAssertNil(vm.errorMessage)
        let count = await gate.pendingCount
        XCTAssertEqual(count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path))
    }

    @MainActor
    func testRetryRespectsSavingDisabledAfterFailure() async throws {
        let enabled = SavingPreference()
        try Data("directory blocker".utf8).write(to: storeURL)
        let vm = ScanViewModel(scanStore: ScanStore(directory: storeURL), savingEnabled: { enabled.value })
        vm.startScan(path: folder.path)
        try await waitUntil { vm.saveState == .failed }
        enabled.value = false
        try FileManager.default.removeItem(at: storeURL)
        vm.retrySave()
        XCTAssertEqual(vm.saveState, .idle)
        XCTAssertTrue(vm.savedScans.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path))
    }

    @MainActor
    func testFailedOrCancelledReplacementPreservesUnsavedResultAndRetry() async throws {
        for cancelReplacement in [false, true] {
            let gate = ControlledSave()
            let vm = controlledModel(gate)
            vm.startScan(path: folder.path)
            try await waitUntil { await gate.pendingCount == 1 }
            let result = try XCTUnwrap(vm.lastScanResult)
            await gate.finish(result.id, fail: true)
            try await waitUntil { vm.saveState == .failed }
            let revision = vm.treeRevision

            vm.startScan(path: folder.appendingPathComponent("missing").path)
            if cancelReplacement { vm.cancelScan() }
            try await waitUntil { !vm.isScanning }
            XCTAssertEqual(vm.lastScanResult?.id, result.id)
            XCTAssertEqual(vm.treeRevision, revision)
            XCTAssertEqual(vm.saveState, .failed)
            vm.retrySave()
            try await waitUntil { await gate.pendingCount == 1 }
            await gate.finish(result.id)
            try await waitUntil { vm.saveState == .saved }
            XCTAssertEqual(vm.lastScanResult?.id, result.id)
            XCTAssertEqual(vm.treeRevision, revision, "Retry must not start a fresh scan")
            XCTAssertEqual(vm.savedScans.map(\.id), [result.id])
        }
    }

    @MainActor
    func testPendingSaveStillReportsFailureWhenReplacementScanFails() async throws {
        let gate = ControlledSave()
        let vm = controlledModel(gate)
        vm.startScan(path: folder.path)
        try await waitUntil { await gate.pendingCount == 1 }
        let result = try XCTUnwrap(vm.lastScanResult)
        vm.startScan(path: folder.appendingPathComponent("missing").path)
        try await waitUntil { !vm.isScanning }
        await gate.finish(result.id, fail: true)
        try await waitUntil { vm.saveState == .failed }
        XCTAssertEqual(vm.lastScanResult?.id, result.id)
        vm.retrySave()
        try await waitUntil { await gate.pendingCount == 1 }
        await gate.finish(result.id)
        try await waitUntil { vm.saveState == .saved }
    }

    @MainActor
    func testLatePreviousSuccessAndFailureCannotReplaceNewScanState() async throws {
        for olderFails in [false, true] {
            let gate = ControlledSave()
            let vm = controlledModel(gate)
            vm.startScan(path: folder.path)
            try await waitUntil { await gate.pendingCount == 1 }
            let oldID = try XCTUnwrap(vm.lastScanResult?.id)
            XCTAssertEqual(vm.saveState, .saving)

            vm.startScan(path: folder.path)
            XCTAssertEqual(vm.saveState, .saving, "Persistence still belongs to the retained result until replacement succeeds")
            try await waitUntil { await gate.pendingCount == 2 }
            let currentID = try XCTUnwrap(vm.lastScanResult?.id)
            XCTAssertNotEqual(oldID, currentID)
            await gate.finish(currentID, fail: !olderFails)
            let currentState: ScanSaveState = olderFails ? .saved : .failed
            try await waitUntil { vm.saveState == currentState }
            await gate.finish(oldID, fail: olderFails)
            try await waitUntil { await gate.pendingCount == 0 }
            // Yield to the main-actor completion after the controlled operation returns.
            try await Task.sleep(for: .milliseconds(20))
            XCTAssertEqual(vm.saveState, currentState)
            XCTAssertEqual(vm.lastScanResult?.id, currentID)
        }
    }

    @MainActor
    func testOpeningSavedSnapshotIgnoresLateSaveFailure() async throws {
        let gate = ControlledSave()
        let vm = controlledModel(gate)
        vm.startScan(path: folder.path)
        try await waitUntil { await gate.pendingCount == 1 }
        let result = try XCTUnwrap(vm.lastScanResult)
        let store = try XCTUnwrap(vm.scanStore)
        let info = try store.save(result)
        vm.openSavedScan(info)
        try await waitUntil { !vm.isOpeningSavedScan }
        XCTAssertTrue(vm.isShowingSavedScan)
        XCTAssertEqual(vm.saveState, .idle)
        await gate.finish(result.id, fail: true)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(vm.saveState, .idle)
        XCTAssertNil(vm.errorMessage)
    }

    @MainActor
    func testRevisedTreeIgnoresLateSaveFailure() async throws {
        let gate = ControlledSave()
        let vm = controlledModel(gate)
        vm.startScan(path: folder.path)
        try await waitUntil { await gate.pendingCount == 1 }
        let oldID = try XCTUnwrap(vm.lastScanResult?.id)
        try FileManager.default.removeItem(at: folder.appendingPathComponent("file.txt"))
        vm.refreshAfterActivation()
        try await waitUntil { await gate.pendingCount == 2 }
        let revisedID = try XCTUnwrap(vm.lastScanResult?.id)
        XCTAssertNotEqual(oldID, revisedID)
        await gate.finish(revisedID)
        try await waitUntil { vm.saveState == .saved }
        await gate.finish(oldID, fail: true)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(vm.saveState, .saved)
        XCTAssertEqual(vm.lastScanResult?.id, revisedID)
        XCTAssertEqual(vm.rootNode?.children.count, 0)
    }

    @MainActor
    func testDeleteAllDuringSaveSuppressesFailureAndRetry() async throws {
        let gate = ControlledSave()
        let vm = controlledModel(gate)
        vm.startScan(path: folder.path)
        try await waitUntil { await gate.pendingCount == 1 }
        let resultID = try XCTUnwrap(vm.lastScanResult?.id)
        let store = try XCTUnwrap(vm.scanStore)
        store.deleteAll() // Mirrors Settings, which does not call the view model.
        try await waitUntil { vm.saveState == .idle }
        await gate.finish(resultID)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(vm.saveState, .idle)
        XCTAssertNil(vm.errorMessage)
        vm.retrySave()
        XCTAssertTrue(store.list().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path))
    }

    @MainActor
    func testDeleteAllAfterFailurePreventsRetryAndPassiveRefreshFromRecreatingHistory() async throws {
        try Data("directory blocker".utf8).write(to: storeURL)
        let store = ScanStore(directory: storeURL)
        let vm = ScanViewModel(scanStore: store, savingEnabled: { true })
        vm.startScan(path: folder.path)
        try await waitUntil { vm.saveState == .failed }
        let originalID = try XCTUnwrap(vm.lastScanResult?.id)
        store.deleteAll()
        try await waitUntil { vm.saveState == .idle }
        try FileManager.default.removeItem(at: storeURL)
        vm.retrySave()
        try FileManager.default.removeItem(at: folder.appendingPathComponent("file.txt"))
        vm.refreshAfterActivation()
        try await waitUntil { vm.lastScanResult?.id != originalID }
        XCTAssertEqual(vm.saveState, .idle)
        XCTAssertTrue(store.list().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path))

        // An explicitly requested fresh scan may be saved after history is cleared.
        vm.startScan(path: folder.path)
        try await waitUntil { vm.saveState == .saved }
        XCTAssertEqual(store.list().count, 1)
    }

    @MainActor
    private func controlledModel(_ gate: ControlledSave, enabled: @escaping @Sendable () -> Bool = { true }) -> ScanViewModel {
        ScanViewModel(scanStore: ScanStore(directory: storeURL), savingEnabled: enabled) { store, result, date, generation in
            try await gate.save(store: store, result: result, date: date, generation: generation)
        }
    }

    @MainActor
    private func waitUntil(_ condition: () async -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<400 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out waiting for scan/save state", file: file, line: line)
        throw CancellationError()
    }
}

private final class SavingPreference: @unchecked Sendable {
    private let lock = NSLock()
    private var enabled = true
    var value: Bool {
        get { lock.withLock { enabled } }
        set { lock.withLock { enabled = newValue } }
    }
}

private actor ControlledSave {
    private struct Pending {
        let store: ScanStore
        let result: ScanResult
        let date: Date
        let generation: Int
        let continuation: CheckedContinuation<Void, Error>
    }
    private var pending: [UUID: Pending] = [:]
    var pendingCount: Int { pending.count }

    func save(store: ScanStore, result: ScanResult, date: Date, generation: Int) async throws {
        try await withCheckedThrowingContinuation { continuation in
            pending[result.id] = Pending(store: store, result: result, date: date, generation: generation,
                                         continuation: continuation)
        }
    }

    func finish(_ id: UUID, fail: Bool = false) {
        guard let request = pending.removeValue(forKey: id) else { return }
        do {
            if fail { throw CocoaError(.fileWriteNoPermission) }
            try request.store.save(request.result, scannedAt: request.date, generation: request.generation)
            request.continuation.resume()
        } catch {
            request.continuation.resume(throwing: error)
        }
    }
}
