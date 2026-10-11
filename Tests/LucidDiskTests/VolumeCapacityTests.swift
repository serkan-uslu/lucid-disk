import XCTest
@testable import LucidDiskCore

@MainActor
final class VolumeCapacityTests: XCTestCase {
    func testCapacityBarUsesPhysicalFreeAndKeepsReclaimableInUsedSpace() {
        let volume = fixture(free: 100, available: 130)
        XCTAssertEqual(volume.freeBytes, 100)
        XCTAssertEqual(volume.usedFraction!, 0.9, accuracy: 0.000_001)
        XCTAssertEqual(volume.estimatedReclaimableBytes, 30)
        let missingAvailability = fixture(free: 100, available: nil)
        XCTAssertEqual(missingAvailability.usedFraction, volume.usedFraction)
        XCTAssertNil(missingAvailability.estimatedReclaimableBytes)
        XCTAssertEqual(fixture(free: 0, available: 20).usedFraction, 1)
        XCTAssertEqual(fixture(free: 1_000, available: 1_000).usedFraction, 0)
    }

    func testUnknownAndInconsistentCapacityDoesNotBecomeZero() {
        for free in [nil, Int64(-1), 1_001] {
            let volume = fixture(free: free, available: 130)
            XCTAssertNil(volume.freeBytes)
            XCTAssertNil(volume.usedFraction)
            XCTAssertNil(volume.estimatedReclaimableBytes)
        }
        for available in [Int64(-1), 99, 1_001] {
            XCTAssertNil(fixture(free: 100, available: available).estimatedReclaimableBytes)
        }
        for total in [nil, Int64(-1)] {
            let volume = fixture(total: total, free: 100, available: 130)
            XCTAssertNil(volume.totalBytes)
            XCTAssertEqual(volume.freeBytes, 100, "Known free bytes do not require a known total")
            XCTAssertNil(volume.usedFraction)
            XCTAssertNil(volume.estimatedReclaimableBytes)
        }
        XCTAssertNil(fixture(total: 0, free: 0, available: 0).usedFraction)
        XCTAssertEqual(fixture(free: 100, available: 100).estimatedReclaimableBytes, 0)
    }

    func testSlowVolumeRefreshCoalescesRepeatedRequestsAndPublishesBeforeFollowup() async throws {
        let gate = VolumeProviderGate()
        let model = ScanViewModel(mountedVolumesProvider: { await gate.read() })
        try await waitUntil { await gate.requestCount == 1 }
        for _ in 0..<10 { model.refreshMountedVolumes() }
        try await Task.sleep(for: .milliseconds(20))
        var requestCount = await gate.requestCount
        var activeCount = await gate.pendingCount
        XCTAssertEqual(requestCount, 1, "A slow read must not start concurrent metadata queries")
        XCTAssertEqual(activeCount, 1)
        let first = fixture(free: 100, available: 130)
        await gate.finish(0, volumes: [first])
        try await waitUntil { await gate.requestCount == 2 }
        XCTAssertEqual(model.mountedVolumes, [first], "Publish the completed reading before draining the pending refresh")
        activeCount = await gate.pendingCount
        XCTAssertEqual(activeCount, 1)
        let newer = fixture(free: 200, available: 230)
        await gate.finish(1, volumes: [newer])
        try await waitUntil { model.mountedVolumes == [newer] }
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(model.mountedVolumes, [newer])
        requestCount = await gate.requestCount
        activeCount = await gate.pendingCount
        XCTAssertEqual(requestCount, 2, "Repeated requests collapse into exactly one follow-up")
        XCTAssertEqual(activeCount, 0)
    }

    func testVolumeRefreshDoesNotRemeasureOrRedateTheScanBreakdown() async throws {
        let gate = VolumeProviderGate()
        let model = ScanViewModel(mountedVolumesProvider: { await gate.read() })
        let probe = CapacityProbe()
        model.spaceProbe = probe
        let breakdown = sampleBreakdown()
        model.showSampleSpaceBreakdown(breakdown)
        let measuredAt = try XCTUnwrap(model.spaceObservation?.measuredAt)
        try await waitUntil { await gate.requestCount == 1 }
        await gate.finish(0, volumes: [fixture(free: 200, available: 250)])
        try await waitUntil { !model.mountedVolumes.isEmpty }
        model.refreshMountedVolumes()
        try await waitUntil { await gate.requestCount == 2 }
        await gate.finish(1, volumes: []) // An unmounted disk must disappear from current capacity.
        try await waitUntil { model.mountedVolumes.isEmpty }
        XCTAssertEqual(model.spaceBreakdown, breakdown)
        XCTAssertEqual(model.spaceObservation?.measuredAt, measuredAt)
        XCTAssertFalse(probe.started, "Periodic volume refresh must not run the disk breakdown probes")
    }

    func testSampleVolumesRejectPendingAndPeriodicLiveRefreshes() async throws {
        let gate = VolumeProviderGate()
        let model = ScanViewModel(mountedVolumesProvider: { await gate.read() })
        try await waitUntil { await gate.requestCount == 1 }
        let sample = fixture(free: 100, available: 130)
        model.refreshMountedVolumes() // Also invalidate a queued follow-up.
        model.showSampleVolumes([sample])
        await gate.finish(0, volumes: [])
        model.refreshMountedVolumes()
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(model.mountedVolumes, [sample])
        let count = await gate.requestCount
        XCTAssertEqual(count, 1)
    }

    func testLateSpaceObservationCannotReplaceANewerScan() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lucid-capacity-" + UUID().uuidString)
        let first = directory.appendingPathComponent("first")
        let second = directory.appendingPathComponent("second")
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = ScanViewModel(mountedVolumesProvider: { [] })
        let oldProbe = CapacityProbe(blocked: true, free: 100)
        defer { oldProbe.release() }
        model.spaceProbe = oldProbe
        model.startScan(path: first.path)
        try await waitUntil { oldProbe.started }
        let newProbe = CapacityProbe(free: 200)
        model.spaceProbe = newProbe
        model.startScan(path: second.path)
        try await waitUntil { model.spaceBreakdown?.freeBytes == 200 }
        let measuredAt = try XCTUnwrap(model.spaceObservation?.measuredAt)
        XCTAssertEqual(model.rootNode?.path, second.path)
        oldProbe.release()
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(model.spaceBreakdown?.freeBytes, 200)
        XCTAssertEqual(model.spaceObservation?.measuredAt, measuredAt)
    }

    private func fixture(total: Int64? = 1_000, free: Int64?, available: Int64?) -> ScanVolume {
        ScanVolume(url: URL(fileURLWithPath: "/"), name: "Fixture", totalBytes: total, freeBytes: free,
                   availableForImportantUsageBytes: available, isInternal: true, isRemovable: false,
                   measuredAt: Date(timeIntervalSince1970: 1))
    }

    private func sampleBreakdown() -> SpaceBreakdown {
        SpaceBreakdown(volumeName: "Fixture", capacityBytes: 1_000, usedBytes: 900, freeBytes: 100,
                       scannedBytes: 800, items: [], purgeableBytes: 30, localSnapshotCount: nil, unreadableFolderCount: 0)
    }

    private func waitUntil(_ condition: () async -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<400 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out waiting for capacity observation", file: file, line: line)
        throw CancellationError()
    }
}

private actor VolumeProviderGate {
    private var pending: [Int: CheckedContinuation<[ScanVolume], Never>] = [:]
    private(set) var requestCount = 0
    var pendingCount: Int { pending.count }
    func read() async -> [ScanVolume] {
        let id = requestCount
        requestCount += 1
        return await withCheckedContinuation { pending[id] = $0 }
    }
    func finish(_ id: Int, volumes: [ScanVolume]) { pending.removeValue(forKey: id)?.resume(returning: volumes) }
}

private final class CapacityProbe: SpaceProbe, @unchecked Sendable {
    private let lock = NSLock()
    private let gate = DispatchSemaphore(value: 0)
    private let blocked: Bool
    private let free: Int64
    private var didStart = false
    var started: Bool { lock.withLock { didStart } }
    init(blocked: Bool = false, free: Int64 = 100) { self.blocked = blocked; self.free = free }
    func release() { gate.signal() }
    func isMountPoint(_ path: String) -> Bool { true }
    func volumeCapacity(at path: String) -> VolumeCapacity? {
        lock.withLock { didStart = true }
        if blocked { _ = gate.wait(timeout: .now() + 5) }
        return VolumeCapacity(name: "Fixture", total: 1_000, available: free, availableForImportantUsage: free + 30)
    }
    func diskInfo(forMountPoint path: String) -> DiskInfo? { nil }
    func apfsContainers() -> [APFSContainerInfo] { [] }
    func localSnapshotCount(forMountPoint path: String) -> Int? { nil }
    func swapUsage() -> (total: Int64, used: Int64)? { nil }
}
