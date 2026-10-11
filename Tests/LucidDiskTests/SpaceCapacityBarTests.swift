import XCTest
@testable import LucidDiskCore

final class SpaceCapacityBarTests: XCTestCase {
    func testScanEstimateAboveCapacityDoesNotShrinkPhysicalFreeSpace() {
        let breakdown = fixture(capacity: 1_000, used: 700, scanned: 1_500)
        let metrics = SpaceCapacityBarMetrics(breakdown: breakdown)

        XCTAssertEqual(metrics.usedFraction, 0.7, accuracy: 0.000_001)
        XCTAssertEqual(metrics.freeFraction, 0.3, accuracy: 0.000_001)
        XCTAssertEqual(breakdown.scannedBytes, 1_500, "Keep the raw estimate in the report")
        XCTAssertEqual(breakdown.items.first?.bytes, 1_500)
    }

    func testPartialScanHasTheSameCapacityBarAsAnOverlappingScan() {
        let partial = SpaceCapacityBarMetrics(breakdown: fixture(capacity: 1_000, used: 700, scanned: 20))
        let overlapping = SpaceCapacityBarMetrics(breakdown: fixture(capacity: 1_000, used: 700, scanned: 1_500))

        XCTAssertEqual(partial.usedFraction, overlapping.usedFraction)
        XCTAssertEqual(partial.freeFraction, overlapping.freeFraction)
    }

    func testEmptyAndFullVolumesDoNotCreateArtificialMinimumSegments() {
        let empty = SpaceCapacityBarMetrics(breakdown: fixture(capacity: 1_000, used: 0, scanned: 0))
        XCTAssertEqual(empty.usedFraction, 0)
        XCTAssertEqual(empty.freeFraction, 1)

        let full = SpaceCapacityBarMetrics(breakdown: fixture(capacity: 1_000, used: 1_000, scanned: 1_500))
        XCTAssertEqual(full.usedFraction, 1)
        XCTAssertEqual(full.freeFraction, 0)

        let unavailable = SpaceCapacityBarMetrics(breakdown: fixture(capacity: 0, used: 0, scanned: 0))
        XCTAssertEqual(unavailable.usedFraction, 0)
        XCTAssertEqual(unavailable.freeFraction, 0)
    }

    private func fixture(capacity: Int64, used: Int64, scanned: Int64) -> SpaceBreakdown {
        SpaceBreakdown(
            volumeName: "Fixture", capacityBytes: capacity, usedBytes: used,
            freeBytes: capacity - used, scannedBytes: scanned,
            items: [.init(id: "scanned", kind: .scanned, title: "Scanned", bytes: scanned, detail: "Fixture")],
            purgeableBytes: nil, localSnapshotCount: nil, unreadableFolderCount: 0
        )
    }
}
