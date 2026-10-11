import XCTest
@testable import LucidDiskCore

final class SpaceBreakdownTests: XCTestCase {
    /// Mirrors a real startup disk: System + Data are covered, the rest is outside the scan.
    private struct FixtureProbe: SpaceProbe {
        var mounted = true
        var dataMounted = true
        var rootInfo: DiskInfo? = DiskInfo(containerReference: "disk3", deviceIdentifier: "disk3s1s1",
                                          volumeGroupID: UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        var dataInfo: DiskInfo? = DiskInfo(containerReference: "disk3", deviceIdentifier: "disk3s5",
                                          volumeGroupID: UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        var externalInfo: DiskInfo? = DiskInfo(containerReference: "disk3", deviceIdentifier: "disk3s10")
        var capacity = VolumeCapacity(name: "Macintosh HD", total: 1_000_000, available: 100_000,
                                      availableForImportantUsage: 130_000)
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

        func isMountPoint(_ path: String) -> Bool { mounted && (path != "/System/Volumes/Data" || dataMounted) }
        func volumeCapacity(at path: String) -> VolumeCapacity? { capacity }
        func diskInfo(forMountPoint path: String) -> DiskInfo? {
            if path == "/" { return rootInfo }
            if path == "/System/Volumes/Data" { return dataInfo }
            return externalInfo
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

    func testSecondInstallationIsSeparateFromTheBootedSystemAndData() throws {
        let breakdown = try analyze(twoInstallations())
        let other = breakdown.items.filter { $0.kind == .otherVolume }
        XCTAssertEqual(Set(other.map(\.id)), ["volume-disk3s7", "volume-disk3s8", "volume-disk3s2"])
        XCTAssertEqual(other.filter { $0.id != "volume-disk3s2" }.reduce(0) { $0 + $1.bytes }, 300)
        XCTAssertEqual(breakdown.items.first { $0.kind == .notVisible }?.bytes, 150)
        XCTAssertEqual(breakdown.items.reduce(0) { $0 + $1.bytes }, 800)
        XCTAssertEqual(breakdown.capacityBytes, 1_000)
        XCTAssertEqual(breakdown.freeBytes, 200)
        XCTAssertEqual(breakdown.usedBytes, 800)
        XCTAssertFalse(try XCTUnwrap(breakdown.items.first).detail.contains(uncertaintyDetail))
    }

    func testCanonicalMountedDataRemainsAuthoritativeWithoutGroupIDs() throws {
        for missingRoot in [false, true] {
            for missingData in [false, true] {
                var probe = twoInstallations()
                if missingRoot { probe.rootInfo?.volumeGroupID = nil }
                if missingData { probe.dataInfo?.volumeGroupID = nil }
                let breakdown = try analyze(probe)
                XCTAssertFalse(breakdown.items.contains { $0.id == "volume-disk3s5" })
                XCTAssertEqual(breakdown.items.first { $0.kind == .notVisible }?.bytes, 150)
                XCTAssertFalse(try XCTUnwrap(breakdown.items.first).detail.contains(uncertaintyDetail))
            }
        }
    }

    func testUnverifiedDataAmountsAreNotAddedToTheScan() throws {
        var cases: [(String, FixtureProbe)] = []
        var probe = twoInstallations()
        probe.dataMounted = false
        cases.append(("not a mountpoint", probe))
        probe = twoInstallations()
        probe.dataInfo = nil
        cases.append(("missing disk info", probe))
        probe = twoInstallations()
        probe.dataInfo = DiskInfo(containerReference: "disk9", deviceIdentifier: "disk3s5")
        cases.append(("different container", probe))
        probe = twoInstallations()
        probe.dataInfo = DiskInfo(containerReference: "disk3", deviceIdentifier: "disk3s50")
        cases.append(("unknown device", probe))
        probe = twoInstallations()
        probe.dataInfo = DiskInfo(containerReference: "disk3", deviceIdentifier: "disk3s1")
        cases.append(("wrong role", probe))
        probe = twoInstallations()
        probe.dataInfo?.volumeGroupID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")
        cases.append(("conflicting volume group", probe))

        for (name, probe) in cases {
            let breakdown = try analyze(probe)
            XCTAssertEqual(Set(breakdown.items.filter { $0.kind == .otherVolume }.map(\.id)),
                           ["volume-disk3s7", "volume-disk3s2"], name)
            XCTAssertEqual(breakdown.items.first { $0.kind == .notVisible }?.bytes, 350, name)
            XCTAssertEqual(breakdown.items.reduce(0) { $0 + $1.bytes }, 800, name)
            XCTAssertTrue(try XCTUnwrap(breakdown.items.first).detail.contains(uncertaintyDetail), name)
        }
    }

    func testUncertaintyRemainsVisibleWithZeroOrNegativeRemainder() throws {
        var probe = twoInstallations()
        probe.dataInfo = nil
        for scanned in [Int64(650), 900] {
            let breakdown = try analyze(probe, scanned: scanned)
            XCTAssertTrue(try XCTUnwrap(breakdown.items.first).detail.contains(uncertaintyDetail))
            XCTAssertNil(breakdown.items.first { $0.kind == .notVisible })
            XCTAssertEqual(breakdown.scannedBytes, scanned)
            XCTAssertEqual(breakdown.usedBytes, 800)
            XCTAssertEqual(breakdown.freeBytes, 200)
            if scanned == 900 {
                XCTAssertEqual(breakdown.items.first { $0.kind == .sharedBlocks }?.bytes, 250)
            } else {
                XCTAssertNil(breakdown.items.first { $0.kind == .sharedBlocks })
            }
        }
    }

    func testUnknownStartupDeviceDoesNotDoubleCountSystemVolumes() throws {
        var probe = twoInstallations()
        probe.rootInfo = DiskInfo(containerReference: "disk3", deviceIdentifier: nil)
        probe.dataInfo = nil
        let breakdown = try analyze(probe)
        XCTAssertEqual(breakdown.items.filter { $0.kind == .otherVolume }.map(\.id), ["volume-disk3s2"])
        XCTAssertEqual(breakdown.items.first { $0.kind == .notVisible }?.bytes, 450)
        XCTAssertTrue(try XCTUnwrap(breakdown.items.first).detail.contains(uncertaintyDetail))
    }

    func testExternalSystemVolumeDoesNotClaimItsDataOrTheBootedInstallation() throws {
        var probe = twoInstallations()
        probe.externalInfo = DiskInfo(containerReference: "disk3", deviceIdentifier: "disk3s7")
        let breakdown = try analyze(probe, rootPath: "/Volumes/Other macOS", scanned: 50)
        XCTAssertEqual(Set(breakdown.items.filter { $0.kind == .otherVolume }.map(\.id)),
                       ["volume-disk3s1", "volume-disk3s5", "volume-disk3s8", "volume-disk3s2"])
        XCTAssertEqual(breakdown.items.first { $0.kind == .notVisible }?.bytes, 50)

        probe.externalInfo = DiskInfo(containerReference: "disk3", deviceIdentifier: nil)
        let unknown = try analyze(probe, rootPath: "/Volumes/Other macOS", scanned: 50)
        XCTAssertFalse(unknown.items.contains { $0.kind == .otherVolume })
        XCTAssertEqual(unknown.items.first { $0.kind == .notVisible }?.bytes, 750)
        XCTAssertTrue(try XCTUnwrap(unknown.items.first).detail.contains(uncertaintyDetail))
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
        XCTAssertEqual(breakdown.purgeableBytes, 30_000)
    }

    func testScreenshotCapacitySeparatesPhysicalFreeAndAdditionalReclaimable() throws {
        var probe = FixtureProbe()
        probe.capacity = VolumeCapacity(name: "Fixture", total: 994_660_000_000, available: 20_000_000_000,
                                        availableForImportantUsage: 27_020_000_000)
        probe.containers = [APFSContainerInfo(reference: "disk3", capacityCeiling: 994_660_000_000,
                                             capacityFree: 22_110_000_000, volumes: [])]
        let breakdown = try analyze(probe, scanned: 925_790_000_000)
        XCTAssertEqual(breakdown.freeBytes, 22_110_000_000)
        XCTAssertEqual(breakdown.outsideScanBytes, 46_760_000_000)
        XCTAssertEqual(breakdown.purgeableBytes, 4_910_000_000,
                       "Reclaimable must use the chosen physical free sample, not the separate Foundation free sample")
        XCTAssertEqual(breakdown.usedBytes + breakdown.freeBytes, breakdown.capacityBytes)
    }

    func testInconsistentOrMissingAvailabilityDoesNotInventReclaimableSpace() throws {
        for available in [nil, Int64(-1), 99_999, 1_000_001] {
            var probe = FixtureProbe()
            probe.capacity = VolumeCapacity(name: "Fixture", total: 1_000_000, available: 100_000,
                                            availableForImportantUsage: available)
            let breakdown = try analyze(probe)
            XCTAssertNil(breakdown.purgeableBytes)
            XCTAssertEqual(breakdown.freeBytes, 100_000)
            XCTAssertEqual(breakdown.usedBytes, 900_000)
        }
    }

    func testInvalidPhysicalCapacityIsUnavailableForAPFSAndFallback() {
        for (total, free) in [(Int64(-1), Int64(0)), (1_000, -1), (1_000, 1_001)] {
            var probe = FixtureProbe()
            probe.capacity = VolumeCapacity(name: "Fixture", total: total, available: free, availableForImportantUsage: nil)
            probe.containers = [APFSContainerInfo(reference: "disk3", capacityCeiling: total, capacityFree: free, volumes: [])]
            XCTAssertNil(SpaceAnalyzer.breakdown(rootPath: "/", scannedBytes: 0, unreadableFolderCount: 0, probe: probe))
            probe.containers = []
            XCTAssertNil(SpaceAnalyzer.breakdown(rootPath: "/Volumes/USB", scannedBytes: 0, unreadableFolderCount: 0, probe: probe))
        }
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
          <key>APFSVolumeGroupID</key><string>00000000-0000-0000-0000-000000000001</string>
        </dict></plist>
        """
        XCTAssertEqual(SpaceParsing.diskInfo(Data(info.utf8)), DiskInfo(containerReference: "disk3", deviceIdentifier: "disk3s1s1",
                                                                      volumeGroupID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")))
        XCTAssertEqual(SpaceParsing.snapshotCount("Snapshots for disk /:\ncom.apple.TimeMachine.2026-09-29-101010.local\ncom.apple.TimeMachine.2026-09-29-111010.local\n"), 2)
    }

    func testOptionalVolumeGroupMetadataUsesTheDiskInfoFieldName() throws {
        for metadata: [String: Any] in [[:], ["APFSVolumeGroupID": ""], ["APFSVolumeGroupID": "invalid"],
                                      ["APFSVolumeGroupUUID": "00000000-0000-0000-0000-000000000001"]] {
            var plist: [String: Any] = ["APFSContainerReference": "disk3", "DeviceIdentifier": "disk3s5"]
            plist.merge(metadata) { _, new in new }
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            XCTAssertEqual(SpaceParsing.diskInfo(data), DiskInfo(containerReference: "disk3", deviceIdentifier: "disk3s5"))
        }
    }

    private var uncertaintyDetail: String {
        String(localized: "Some volumes could not be matched to this scan. Their separate amounts are omitted because they may overlap the scan.")
    }

    private func analyze(_ probe: FixtureProbe, rootPath: String = "/", scanned: Int64 = 300) throws -> SpaceBreakdown {
        try XCTUnwrap(SpaceAnalyzer.breakdown(rootPath: rootPath, scannedBytes: scanned, unreadableFolderCount: 0, probe: probe))
    }

    private func twoInstallations() -> FixtureProbe {
        var probe = FixtureProbe()
        probe.capacity = VolumeCapacity(name: "Macintosh HD", total: 1_000, available: 200, availableForImportantUsage: nil)
        probe.containers = [APFSContainerInfo(reference: "disk3", capacityCeiling: 1_000, capacityFree: 200, volumes: [
            APFSVolumeInfo(name: "Active System", roles: ["System"], capacityInUse: 100, deviceIdentifier: "disk3s1"),
            APFSVolumeInfo(name: "Active Data", roles: ["Data"], capacityInUse: 350, deviceIdentifier: "disk3s5"),
            APFSVolumeInfo(name: "Second System", roles: ["System"], capacityInUse: 100, deviceIdentifier: "disk3s7"),
            APFSVolumeInfo(name: "Second Data", roles: ["Data"], capacityInUse: 200, deviceIdentifier: "disk3s8"),
            APFSVolumeInfo(name: "Preboot", roles: ["Preboot"], capacityInUse: 50, deviceIdentifier: "disk3s2")
        ])]
        return probe
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
