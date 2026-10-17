import XCTest
@testable import LucidDiskCore

final class ScanMeasurementTests: XCTestCase {
    func testFolderKeepsItsOwnAmountAndWholeScanPartialStatus() {
        let root = FileNode(name: "Disk", path: "/fixture", isDirectory: true, size: 900, measurementAccuracy: .incomplete)
        let folder = FileNode(name: "Projects", path: "/fixture/Projects", isDirectory: true, size: 200)
        let item = FileNode(name: "File", path: "/fixture/Projects/file", isDirectory: false, size: 200)
        root.children = [folder]; folder.parent = root; folder.children = [item]
        let measurement = ScanMeasurementPresentation(focused: folder, root: root, wasStopped: false, savedAt: nil)
        XCTAssertEqual(measurement.scopeName, "Projects")
        XCTAssertEqual(measurement.allocatedBytes, 200)
        XCTAssertEqual(measurement.itemCount, 1)
        XCTAssertFalse(measurement.scopeIsIncomplete)
        XCTAssertEqual(measurement.status, .partial)
    }

    func testOtherGroupRetainsIncompleteUnderlyingScope() throws {
        let root = FileNode(name: "Projects", path: "/fixture", isDirectory: true, size: 1_000)
        let unreadable = FileNode(name: "Unreadable", path: "/fixture/Unreadable", isDirectory: true, size: 1, measurementAccuracy: .incomplete)
        unreadable.parent = root; root.children = [unreadable]
        let other = try XCTUnwrap(computeWedges(focusedNode: root, minFraction: 0.1).first?.node)
        XCTAssertTrue(other.isAggregate)
        let measurement = ScanMeasurementPresentation(focused: other, root: root, wasStopped: false, savedAt: nil)
        XCTAssertEqual(measurement.allocatedBytes, 1)
        XCTAssertEqual(measurement.itemCount, 1)
        XCTAssertTrue(measurement.scopeIsIncomplete)
        XCTAssertEqual(measurement.status, .partial)
        XCTAssertTrue(measurement.scopeName.contains("Projects"))
    }

    func testStoppedAndSavedStatesDoNotImplyCompleteness() {
        let root = FileNode(name: "Disk", path: "/fixture", isDirectory: true, size: 100, measurementAccuracy: .incomplete)
        XCTAssertEqual(ScanMeasurementPresentation(focused: root, root: root, wasStopped: true, savedAt: nil).status, .stopped)
        let date = Date(timeIntervalSince1970: 1)
        let saved = ScanMeasurementPresentation(focused: root, root: root, wasStopped: true, savedAt: date)
        XCTAssertEqual(saved.status, .partial, "Saved scans do not persist the stopped flag")
        XCTAssertEqual(saved.savedAt, date)
    }

    func testMeasuredAllocationIsNeverClampedToDiskCapacityOrCalledFreeSpace() {
        let root = FileNode(name: "Disk", path: "/fixture", isDirectory: true, size: 1_500_000_000_000)
        let measurement = ScanMeasurementPresentation(focused: root, root: root, wasStopped: false, savedAt: nil)
        XCTAssertEqual(measurement.allocatedBytes, 1_500_000_000_000)
        XCTAssertNil(measurement.status)
        root.size = 1
        XCTAssertEqual(measurement.allocatedBytes, 1_500_000_000_000, "A presentation is an immutable value snapshot")
    }
}
