import XCTest
@testable import LucidDiskCore

final class DiskScannerTests: XCTestCase {
    func testMissingRootIsAnErrorInsteadOfAnEmptySuccessfulScan() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertThrowsError(try DiskScanner { _ in }.scan(rootPath: directory.appendingPathComponent("missing").path))
    }

    func testAFileCannotBeUsedAsDirectoryScanRoot() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("file.txt")
        try Data("fixture".utf8).write(to: file)
        XCTAssertThrowsError(try DiskScanner { _ in }.scan(rootPath: file.path))
    }

    func testExplicitSymlinkRootResolvesToItsDirectory() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let folder = directory.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try Data("fixture".utf8).write(to: folder.appendingPathComponent("file.txt"))
        let alias = directory.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: folder)
        let result = try DiskScanner { _ in }.scan(rootPath: alias.path)
        XCTAssertEqual(result.root.path, folder.resolvingSymlinksInPath().path)
        XCTAssertEqual(result.root.children.map(\.name), ["file.txt"])
    }

    func testStatDatesAndOnDemandTypeRemainAvailable() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("notes.txt")
        try Data("notes".utf8).write(to: file)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: file.path)
        let result = try DiskScanner { _ in }.scan(rootPath: directory.path)
        let node = try XCTUnwrap(result.root.children.first)
        XCTAssertEqual(node.modifiedAt?.timeIntervalSince1970, date.timeIntervalSince1970)
        XCTAssertNotNil(node.createdAt)
        XCTAssertEqual(node.contentTypeIdentifier, "public.plain-text")
    }

    func testHardLinksShareOneAllocatedSizeAndKeepLogicalSizes() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("original.bin")
        let link = directory.appendingPathComponent("link.bin")
        try Data(repeating: 0xA5, count: 16_384).write(to: original)
        try FileManager.default.linkItem(at: original, to: link)

        let result = try DiskScanner { _ in }.scan(rootPath: directory.path)
        let files = result.root.children.sorted { $0.name < $1.name }

        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(files[0].fileIdentity, files[1].fileIdentity)
        XCTAssertEqual(files.map(\.logicalSizeBytes), [16_384, 16_384])
        XCTAssertEqual(files.filter { $0.allocatedSizeBytes == 0 }.count, 1)
        XCTAssertEqual(result.statistics.duplicateHardLinkCount, 1)
        XCTAssertEqual(result.root.logicalSizeBytes, 32_768)
        XCTAssertEqual(result.root.allocatedSizeBytes, files.reduce(0) { $0 + $1.allocatedSizeBytes })
        XCTAssertEqual(result.root.measurementAccuracy, .estimated)
    }

    func testScanIDAndLimitWarningAreReturned() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("one".utf8).write(to: directory.appendingPathComponent("one"))
        try Data("two".utf8).write(to: directory.appendingPathComponent("two"))
        let id = UUID()

        let result = try DiskScanner(maximumItemCount: 1) { _ in }
            .scan(rootPath: directory.path, scanID: id)

        XCTAssertEqual(result.id, id)
        XCTAssertEqual(result.root.measurementAccuracy, .incomplete)
        XCTAssertFalse(result.warnings.isEmpty)
    }

    func testSymlinkChainIsRecordedWithoutBeingTraversed() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("target", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        try Data("payload".utf8).write(to: target.appendingPathComponent("payload.bin"))
        let first = directory.appendingPathComponent("first-link")
        let second = directory.appendingPathComponent("second-link")
        try FileManager.default.createSymbolicLink(at: first, withDestinationURL: target)
        try FileManager.default.createSymbolicLink(at: second, withDestinationURL: first)

        let result = try DiskScanner { _ in }.scan(rootPath: directory.path)
        let links = result.root.children.filter(\.isSymlink)

        XCTAssertEqual(links.count, 2)
        XCTAssertTrue(links.allSatisfy { !$0.isDirectory && $0.children.isEmpty })
        XCTAssertEqual(result.root.children.first(where: { $0.name == "target" })?.children.count, 1)
    }

    func testUnreadableDirectoryMarksTreeIncomplete() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let unreadable = directory.appendingPathComponent("unreadable", isDirectory: true)
        try FileManager.default.createDirectory(at: unreadable, withIntermediateDirectories: false)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: unreadable.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: unreadable.path) }

        let result = try DiskScanner { _ in }.scan(rootPath: directory.path)
        let node = try XCTUnwrap(result.root.children.first(where: { $0.name == "unreadable" }))

        XCTAssertEqual(node.measurementAccuracy, .incomplete)
        XCTAssertEqual(result.root.measurementAccuracy, .incomplete)
        XCTAssertEqual(result.statistics.unreadableDirectoryCount, 1)
        XCTAssertFalse(result.warnings.isEmpty)
    }

    /// A scan of `/` stops at other devices. It still reaches user data because macOS
    /// reports the sealed System volume and its Data volume (joined by firmlinks) as
    /// one device. `SpaceAnalyzer` relies on the same fact to count both as scanned.
    func testStartupVolumeGroupIsOneDeviceSoAScanOfRootReachesHome() throws {
        let root = try XCTUnwrap(FileIdentity.read(atPath: "/"))
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for path in [home, "/Users", "/Applications", "/private/var"] {
            let identity = try XCTUnwrap(FileIdentity.read(atPath: path), path)
            XCTAssertTrue(DiskScanner.isOnRootVolume(rootDevice: root.device, childDevice: identity.device), path)
        }
    }

    func testMountBoundaryDecisionUsesDeviceIdentity() {
        XCTAssertTrue(DiskScanner.isOnRootVolume(rootDevice: 7, childDevice: 7))
        XCTAssertFalse(DiskScanner.isOnRootVolume(rootDevice: 7, childDevice: 8))
        XCTAssertTrue(DiskScanner.isOnRootVolume(rootDevice: nil, childDevice: 8))
        XCTAssertTrue(DiskScanner.isOnRootVolume(rootDevice: 7, childDevice: nil))
    }

    func testEntryDisappearingDuringMetadataReadIsIncomplete() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let volatile = directory.appendingPathComponent("volatile.bin")
        try Data("temporary".utf8).write(to: volatile)
        let scanner = DiskScanner(entryWillBeRead: { url in
            if url.lastPathComponent == volatile.lastPathComponent {
                try? FileManager.default.removeItem(at: url)
            }
        }) { _ in }

        let result = try scanner.scan(rootPath: directory.path)
        let node = try XCTUnwrap(result.root.children.first(where: { $0.name == "volatile.bin" }))

        XCTAssertEqual(node.measurementAccuracy, .incomplete)
        XCTAssertEqual(result.root.measurementAccuracy, .incomplete)
        XCTAssertTrue(result.warnings.contains {
            URL(fileURLWithPath: $0.path).lastPathComponent == volatile.lastPathComponent
        })
    }

    func testRescanAfterRemovingCountedHardLinkReattributesAllocation() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("original.bin")
        let link = directory.appendingPathComponent("link.bin")
        try Data(repeating: 0xA5, count: 16_384).write(to: original)
        try FileManager.default.linkItem(at: original, to: link)

        let first = try DiskScanner { _ in }.scan(rootPath: directory.path)
        let counted = try XCTUnwrap(first.root.children.first(where: { $0.allocatedSizeBytes > 0 }))
        try FileManager.default.removeItem(atPath: counted.path)
        let rescanned = try DiskScanner { _ in }.scan(rootPath: directory.path)

        XCTAssertEqual(rescanned.root.children.count, 1)
        XCTAssertGreaterThan(rescanned.root.children[0].allocatedSizeBytes, 0)
        XCTAssertEqual(rescanned.statistics.duplicateHardLinkCount, 0)
    }

    func testCancelledTaskDoesNotReturnPartialResult() async {
        let scanner = DiskScanner { _ in }
        let task = Task.detached { () throws -> ScanResult in
            withUnsafeCurrentTask { $0?.cancel() }
            return try scanner.scan(rootPath: "/")
        }

        do {
            _ = try await task.value
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    func testSyntheticCorpusBenchmark() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let payload = Data(repeating: 0x4c, count: 4_096)

        for directoryIndex in 0..<32 {
            let directory = root.appendingPathComponent("folder-\(directoryIndex)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            for fileIndex in 0..<128 {
                try payload.write(to: directory.appendingPathComponent("file-\(fileIndex).bin"))
            }
            try FileManager.default.linkItem(
                at: directory.appendingPathComponent("file-0.bin"),
                to: directory.appendingPathComponent("file-0-hardlink.bin")
            )
            try FileManager.default.createSymbolicLink(
                at: directory.appendingPathComponent("file-0-symlink.bin"),
                withDestinationURL: directory.appendingPathComponent("file-0.bin")
            )
        }

        let result = try DiskScanner { _ in }.scan(rootPath: root.path)
        print(
            "LUCID_DISK_BENCHMARK "
                + "duration_seconds=\(String(format: "%.6f", result.duration)) "
                + "files=\(result.statistics.scannedFileCount) "
                + "directories=\(result.statistics.scannedDirectoryCount) "
                + "hardlinks_deduplicated=\(result.statistics.duplicateHardLinkCount)"
        )

        XCTAssertEqual(result.statistics.scannedDirectoryCount, 33)
        XCTAssertEqual(result.statistics.duplicateHardLinkCount, 32)
        XCTAssertEqual(result.warnings.count, 0)
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
