import XCTest
@testable import LucidDiskCore

final class ScanStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lucid-store-" + UUID().uuidString)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func sampleResult(rootPath: String = "/Users/example/Projects") -> ScanResult {
        let root = FileNode(name: "Projects", path: rootPath, isDirectory: true, measurementAccuracy: .incomplete,
                            fileIdentity: FileIdentity(device: 16777233, inode: 2), modifiedAt: Date(timeIntervalSince1970: 1_700_000_000.25))
        let folder = FileNode(name: "Çalışma — ünïcode 📁", path: rootPath + "/Çalışma — ünïcode 📁", isDirectory: true,
                              logicalSizeBytes: 300, allocatedSizeBytes: 8192, measurementAccuracy: .estimated,
                              fileIdentity: FileIdentity(device: 16777233, inode: 3),
                              createdAt: Date(timeIntervalSince1970: 1_600_000_000.5), scanWarning: "This directory could not be read.")
        let file = FileNode(name: "report.pdf", path: folder.path + "/report.pdf", isDirectory: false,
                            logicalSizeBytes: 300, allocatedSizeBytes: 8192, measurementAccuracy: .estimated,
                            fileIdentity: FileIdentity(device: 16777233, inode: UInt64.max - 1),
                            modifiedAt: Date(timeIntervalSince1970: 1_650_000_000.125))
        let link = FileNode(name: "latest", path: rootPath + "/latest", isDirectory: false, isSymlink: true,
                            logicalSizeBytes: 12, allocatedSizeBytes: 0, measurementAccuracy: .exact)
        let empty = FileNode(name: "empty", path: rootPath + "/empty", isDirectory: true)
        folder.children = [file]
        file.parent = folder
        root.children = [folder, link, empty]
        [folder, link, empty].forEach { $0.parent = root }
        root.logicalSizeBytes = 312
        root.allocatedSizeBytes = 8192
        return ScanResult(
            id: UUID(), root: root, duration: 1.5,
            statistics: ScanStatistics(scannedFileCount: 2, scannedDirectoryCount: 3, logicalSizeBytes: 312,
                                       allocatedSizeBytes: 8192, unreadableDirectoryCount: 1, duplicateHardLinkCount: 0),
            warnings: [ScanWarning(path: folder.path, message: "This directory could not be read.")]
        )
    }

    private func flatten(_ node: FileNode) -> [FileNode] {
        [node] + node.children.flatMap(flatten)
    }

    func testRoundTripPreservesEveryField() throws {
        let store = ScanStore(directory: directory)
        let result = sampleResult()
        let info = try store.save(result)
        let loaded = try store.load(info)

        let original = flatten(result.root)
        let restored = flatten(loaded.root)
        XCTAssertEqual(original.count, restored.count)
        for (a, b) in zip(original, restored) {
            XCTAssertEqual(a.name, b.name)
            XCTAssertEqual(a.path, b.path)
            XCTAssertEqual(a.isDirectory, b.isDirectory)
            XCTAssertEqual(a.isSymlink, b.isSymlink)
            XCTAssertEqual(a.logicalSizeBytes, b.logicalSizeBytes)
            XCTAssertEqual(a.allocatedSizeBytes, b.allocatedSizeBytes)
            XCTAssertEqual(a.measurementAccuracy, b.measurementAccuracy)
            XCTAssertEqual(a.fileIdentity, b.fileIdentity)
            XCTAssertEqual(a.createdAt, b.createdAt)
            XCTAssertEqual(a.modifiedAt, b.modifiedAt)
            XCTAssertEqual(a.scanWarning, b.scanWarning)
            XCTAssertEqual(a.parent?.path, b.parent?.path)
        }
        XCTAssertEqual(loaded.scanResult.statistics.unreadableDirectoryCount, 1)
        XCTAssertEqual(loaded.scanResult.warnings, result.warnings)
    }

    func testStartupDiskPathsRebuildWithoutDoubleSlash() throws {
        let store = ScanStore(directory: directory)
        let root = FileNode(name: "Macintosh HD", path: "/", isDirectory: true)
        let users = FileNode(name: "Users", path: "/Users", isDirectory: true)
        users.parent = root
        root.children = [users]
        let result = ScanResult(id: UUID(), root: root, duration: 0,
                                statistics: ScanStatistics(scannedFileCount: 0, scannedDirectoryCount: 2, logicalSizeBytes: 0,
                                                           allocatedSizeBytes: 0, unreadableDirectoryCount: 0, duplicateHardLinkCount: 0),
                                warnings: [])
        let loaded = try store.load(try store.save(result))
        XCTAssertEqual(loaded.root.children.first?.path, "/Users")
    }

    func testRetentionKeepsNewestPerLocationOnly() throws {
        let store = ScanStore(directory: directory)
        try store.save(sampleResult(), scannedAt: Date(timeIntervalSince1970: 1))
        let newest = try store.save(sampleResult(), scannedAt: Date(timeIntervalSince1970: 2))
        let other = try store.save(sampleResult(rootPath: "/Volumes/Backup"), scannedAt: Date(timeIntervalSince1970: 3))

        XCTAssertEqual(store.list().map(\.id), [other.id, newest.id])
        XCTAssertEqual(store.latest(forRootPath: "/Users/example/Projects")?.id, newest.id)

        store.retentionPerRoot = 3
        try store.save(sampleResult(), scannedAt: Date(timeIntervalSince1970: 4))
        XCTAssertEqual(store.list().filter { $0.rootPath == "/Users/example/Projects" }.count, 2)
    }

    func testCorruptAndFutureArchivesAreRejected() throws {
        let store = ScanStore(directory: directory)
        let info = try store.save(sampleResult())
        try Data("not a scan".utf8).write(to: directory.appendingPathComponent("\(info.id.uuidString).ldscan"))
        XCTAssertThrowsError(try store.load(info))

        var future = Data()
        future.append(contentsOf: Array("LDSC".utf8))
        withUnsafeBytes(of: UInt16(99).littleEndian) { future.append(contentsOf: $0) }
        let compressed = try (future as NSData).compressed(using: .lzfse) as Data
        XCTAssertThrowsError(try ScanArchive.decode(compressed, rootPath: "/")) { error in
            XCTAssertEqual(error as? ScanArchive.Failure, .unsupportedVersion(99))
        }
    }

    func testDeleteAllRemovesOnlyStoreFiles() throws {
        let store = ScanStore(directory: directory)
        try store.save(sampleResult())
        let unrelated = directory.appendingPathComponent("notes.txt")
        try Data("keep".utf8).write(to: unrelated)
        store.deleteAll()
        XCTAssertTrue(store.list().isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }

    @MainActor
    func testSavedScanOpensAsBrowsableSnapshotAndBlocksTrash() async throws {
        let store = ScanStore(directory: directory)
        let info = try store.save(sampleResult())
        let vm = ScanViewModel(scanStore: store)
        XCTAssertEqual(vm.savedScans.map(\.id), [info.id])

        vm.openSavedScan(info)
        for _ in 0..<200 where vm.isOpeningSavedScan { try await Task.sleep(for: .milliseconds(5)) }
        let root = try XCTUnwrap(vm.rootNode)
        XCTAssertEqual(root.path, "/Users/example/Projects")
        XCTAssertTrue(vm.isShowingSavedScan)

        let file = try XCTUnwrap(root.children.first?.children.first)
        vm.toggleReview(node: file)
        XCTAssertTrue(vm.isQueued(file), "Queueing works on a saved scan")
        vm.requestDeletion(node: file)
        XCTAssertNil(vm.pendingDeletion)
        XCTAssertEqual(vm.errorMessage, ScanViewModel.savedScanTrashMessage)
    }

    @MainActor
    func testFreshScanIsSavedAndClearsSnapshotState() async throws {
        let store = ScanStore(directory: directory)
        let folder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".lucid-save-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("x".utf8).write(to: folder.appendingPathComponent("a.txt"))

        let vm = ScanViewModel(scanStore: store)
        vm.snapshotDate = Date(timeIntervalSince1970: 0)
        vm.startScan(path: folder.path)
        for _ in 0..<200 where vm.isScanning { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertFalse(vm.isShowingSavedScan)
        for _ in 0..<200 where store.list().isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(store.list().first?.rootPath, folder.path)
    }

    func testSaveStartedBeforeDeleteAllDoesNotRecreateAFile() throws {
        let store = ScanStore(directory: directory)
        let generation = store.generation
        store.deleteAll()
        XCTAssertThrowsError(try store.save(sampleResult(), generation: generation))
        XCTAssertTrue(store.list().isEmpty)
        XCTAssertNoThrow(try store.save(sampleResult(), generation: store.generation))
        XCTAssertEqual(store.list().count, 1)
    }

    @MainActor
    func testNewScanWinsOverASavedScanStillLoading() async throws {
        let store = ScanStore(directory: directory)
        let info = try store.save(sampleResult())
        let folder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".lucid-race-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let vm = ScanViewModel(scanStore: store)
        vm.openSavedScan(info)
        XCTAssertTrue(vm.isOpeningSavedScan)
        vm.startScan(path: folder.path)
        XCTAssertFalse(vm.isOpeningSavedScan, "Starting a scan abandons the pending saved-scan load")
        for _ in 0..<200 where vm.isScanning { try await Task.sleep(for: .milliseconds(5)) }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(vm.rootNode?.path, folder.path)
        XCTAssertFalse(vm.isShowingSavedScan, "A late saved-scan load must not replace the fresh scan")
        XCTAssertFalse(vm.isOpeningSavedScan)
    }

    func testLargeTreeEncodesCompactly() throws {
        let root = FileNode(name: "big", path: "/tmp/big", isDirectory: true)
        for index in 0..<50_000 {
            let file = FileNode(name: "asset-\(index).bin", path: "/tmp/big/asset-\(index).bin", isDirectory: false,
                                size: Int64(index), fileIdentity: FileIdentity(device: 1, inode: UInt64(index)))
            file.parent = root
            root.children.append(file)
        }
        let data = try ScanArchive.encode(root: root)
        XCTAssertLessThan(data.count, 50_000 * 40, "About 40 bytes per node or less after compression")
        XCTAssertEqual(try ScanArchive.decode(data, rootPath: "/tmp/big").children.count, 50_000)
    }
}
