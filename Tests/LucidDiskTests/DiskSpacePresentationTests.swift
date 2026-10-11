import XCTest
@testable import LucidDiskCore

final class DiskSpacePresentationTests: XCTestCase {
    func testOutsideMatchingAndOverlappingAllocationHaveDifferentMeanings() {
        XCTAssertEqual(presentation(scanned: 925_790_000_000).difference, .outsideScan(46_760_000_000))
        XCTAssertEqual(presentation(scanned: 972_550_000_000).difference, .matchesUsedSpace)
        XCTAssertEqual(presentation(scanned: 1_500_000_000_000).difference, .allocationExcess(527_450_000_000))
    }

    @MainActor
    func testFolderAndOtherNavigationKeepWholeDiskObservationAndRootScope() {
        let model = ScanViewModel(mountedVolumesProvider: { [] })
        let root = FileNode(name: "Disk", path: "/fixture/disk", isDirectory: true, size: 900)
        let folder = FileNode(name: "Folder", path: "/fixture/disk/Folder", isDirectory: true, size: 100)
        folder.parent = root; root.children = [folder]
        let other = FileNode(name: "Other", path: folder.path, isDirectory: false, size: 50)
        other.isAggregate = true; other.parent = folder
        model.rootNode = root; model.focusedNode = root
        model.showSampleSpaceBreakdown(breakdown(scanned: 925_790_000_000))
        let observation = model.spaceObservation
        for node in [folder, other, root] {
            model.focus(on: node)
            XCTAssertEqual(model.spaceBreakdown, observation?.breakdown)
            XCTAssertEqual(model.spaceObservation?.measuredAt, observation?.measuredAt)
            let shown = DiskSpacePresentation(breakdown: model.spaceBreakdown!, scanRootPath: model.rootNode!.path)
            XCTAssertEqual(shown.scanRootPath, root.path)
            XCTAssertEqual(shown.volumeName, "Macintosh HD")
            XCTAssertEqual(shown.difference, .outsideScan(46_760_000_000))
        }
    }

    private func presentation(scanned: Int64) -> DiskSpacePresentation {
        DiskSpacePresentation(breakdown: breakdown(scanned: scanned), scanRootPath: "/")
    }
    private func breakdown(scanned: Int64) -> SpaceBreakdown {
        SpaceBreakdown(volumeName: "Macintosh HD", capacityBytes: 994_660_000_000,
                       usedBytes: 972_550_000_000, freeBytes: 22_110_000_000, scannedBytes: scanned,
                       items: [], purgeableBytes: nil, localSnapshotCount: nil, unreadableFolderCount: 0)
    }
}
