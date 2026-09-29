import XCTest
@testable import LucidDiskCore

final class SpaceBreakdownTests: XCTestCase {
    /// Mirrors a real startup disk: System + Data are covered, the rest is outside the scan.
    private struct FixtureProbe: SpaceProbe {
        var mounted = true
        var containers: [APFSContainerInfo] = [APFSContainerInfo(
            reference: "disk3", capacityCeiling: 1_000_000, capacityFree: 100_000,
            volumes: [
                APFSVolumeInfo(name: "Macintosh HD", roles: ["System"], capacityInUse: 12_000, deviceIdentifier: "disk3s1"),
                APFSVolumeInfo(name: "Preboot", roles: ["Preboot"], capacityInUse: 10_000, deviceIdentifier: "disk3s2"),
                APFSVolumeInfo(name: "Recovery", roles: ["Recovery"], capacityInUse: 2_000, deviceIdentifier: "disk3s3"),
                APFSVolumeInfo(name: "Macintosh HD - Data", roles: ["Data"], capacityInUse: 858_000, deviceIdentifier: "disk3s5"),
                APFSVolumeInfo(name: "VM", roles: ["VM"], capacityInUse: 18_000, deviceIdentifier: "disk3s6"),
                APFSVolumeInfo(name: "Empty", roles: ["Update"], capacityInUse: 0, deviceIdentifier: "disk3s4"),
                APFSVolumeInfo(name: "Stray", roles: [], capacityInUse: 1_000, deviceIdentifier: "disk3s10")
            ])]
        var snapshots: Int? = 2

        func isMountPoint(_ path: String) -> Bool { mounted }
        func volumeCapacity(at path: String) -> VolumeCapacity? {
            VolumeCapacity(name: "Macintosh HD", total: 1_000_000, available: 100_000, availableForImportantUsage: 130_000)
        }
        func diskInfo(forMountPoint path: String) -> DiskInfo? {
            DiskInfo(containerReference: "disk3", deviceIdentifier: path == "/" ? "disk3s1s1" : "disk3s10")
        }
        func apfsContainers() -> [APFSContainerInfo] { containers }
        func localSnapshotCount(forMountPoint path: String) -> Int? { snapshots }
        func swapUsage() -> (total: Int64, used: Int64)? { (4_096, 1_024) }
    }

    func testStartupDiskAccountsForEveryUsedByte() throws {
        let breakdown = try XCTUnwrap(SpaceAnalyzer.breakdown(
            rootPath: "/", scannedBytes: 800_000, unreadableFolderCount: 3, probe: FixtureProbe()))

        XCTAssertEqual(breakdown.usedBytes, 900_000)
        XCTAssertEqual(breakdown.items.reduce(0) { $0 + $1.bytes }, breakdown.usedBytes)
        XCTAssertEqual(breakdown.outsideScanBytes, 100_000)
        XCTAssertEqual(breakdown.purgeableBytes, 30_000)
        XCTAssertEqual(breakdown.localSnapshotCount, 2)

        let ids = breakdown.items.map(\.id)
        XCTAssertFalse(ids.contains("volume-disk3s1"), "System is covered by the startup scan")
        XCTAssertFalse(ids.contains("volume-disk3s5"), "Data is covered through firmlinks")
        XCTAssertFalse(ids.contains("volume-disk3s4"), "Empty volumes are omitted")
        XCTAssertTrue(ids.contains("volume-disk3s6"))
        XCTAssertTrue(ids.contains("volume-disk3s10"))

        let hidden = try XCTUnwrap(breakdown.items.first { $0.kind == .notVisible })
        XCTAssertEqual(hidden.bytes, 900_000 - 800_000 - 10_000 - 2_000 - 18_000 - 1_000)
        XCTAssertTrue(hidden.detail.contains("3"), "Unreadable folders are called out")
    }

    func testVolumeMatchingDoesNotConfuseSimilarIdentifiers() throws {
        // disk3s10 must not be treated as covering disk3s1.
        let breakdown = try XCTUnwrap(SpaceAnalyzer.breakdown(
            rootPath: "/Volumes/Stray", scannedBytes: 500, unreadableFolderCount: 0, probe: FixtureProbe()))
        let ids = breakdown.items.map(\.id)
        XCTAssertTrue(ids.contains("volume-disk3s1"))
        XCTAssertFalse(ids.contains("volume-disk3s10"))
    }

    func testOvercountingIsExplainedNotHidden() throws {
        let breakdown = try XCTUnwrap(SpaceAnalyzer.breakdown(
            rootPath: "/", scannedBytes: 950_000, unreadableFolderCount: 0, probe: FixtureProbe()))
        let shared = try XCTUnwrap(breakdown.items.first { $0.kind == .sharedBlocks })
        XCTAssertEqual(shared.bytes, 950_000 + 31_000 - 900_000)
        XCTAssertNil(breakdown.items.first { $0.kind == .notVisible })
    }

    func testFolderScansHaveNoBreakdown() {
        var probe = FixtureProbe()
        probe.mounted = false
        XCTAssertNil(SpaceAnalyzer.breakdown(rootPath: "/Users/example", scannedBytes: 1, unreadableFolderCount: 0, probe: probe))
    }

    func testNonAPFSVolumesFallBackToCapacity() throws {
        var probe = FixtureProbe()
        probe.containers = []
        let breakdown = try XCTUnwrap(SpaceAnalyzer.breakdown(
            rootPath: "/Volumes/USB", scannedBytes: 850_000, unreadableFolderCount: 0, probe: probe))
        XCTAssertEqual(breakdown.usedBytes, 900_000)
        XCTAssertEqual(breakdown.items.first { $0.kind == .notVisible }?.bytes, 50_000)
    }

    func testParsesDiskutilPlists() throws {
        let apfs = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict><key>Containers</key><array><dict>
          <key>ContainerReference</key><string>disk3</string>
          <key>CapacityCeiling</key><integer>994662584320</integer>
          <key>CapacityFree</key><integer>9670569984</integer>
          <key>Volumes</key><array><dict>
            <key>Name</key><string>VM</string>
            <key>Roles</key><array><string>VM</string></array>
            <key>CapacityInUse</key><integer>18297794560</integer>
            <key>DeviceIdentifier</key><string>disk3s6</string>
          </dict></array>
        </dict></array></dict></plist>
        """
        let containers = SpaceParsing.apfsContainers(Data(apfs.utf8))
        XCTAssertEqual(containers.first?.capacityFree, 9_670_569_984)
        XCTAssertEqual(containers.first?.volumes.first?.roles, ["VM"])

        let info = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
          <key>APFSContainerReference</key><string>disk3</string>
          <key>DeviceIdentifier</key><string>disk3s1s1</string>
        </dict></plist>
        """
        XCTAssertEqual(SpaceParsing.diskInfo(Data(info.utf8)), DiskInfo(containerReference: "disk3", deviceIdentifier: "disk3s1s1"))
        XCTAssertEqual(SpaceParsing.snapshotCount("Snapshots for disk /:\ncom.apple.TimeMachine.2026-09-29-101010.local\ncom.apple.TimeMachine.2026-09-29-111010.local\n"), 2)
    }

    /// Runs the real macOS tools. On any Mac, the parts must add up to the used space.
    func testRealStartupDiskAddsUp() throws {
        guard let breakdown = SpaceAnalyzer.breakdown(rootPath: "/", scannedBytes: 1, unreadableFolderCount: 0) else {
            throw XCTSkip("Startup disk information is unavailable")
        }
        XCTAssertGreaterThan(breakdown.usedBytes, 0)
        XCTAssertEqual(breakdown.items.reduce(0) { $0 + $1.bytes }, breakdown.usedBytes)
    }
}
