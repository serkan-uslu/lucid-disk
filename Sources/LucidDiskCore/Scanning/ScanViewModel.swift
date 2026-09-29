import Combine
import Foundation

struct ScanVolume: Identifiable, Hashable {
    let url: URL
    let name: String
    let totalBytes: Int64?
    let availableBytes: Int64?
    let isInternal: Bool
    let isRemovable: Bool

    var id: String { url.path }
}

@MainActor
final class ScanViewModel: ObservableObject {
    @Published var rootNode: FileNode?
    @Published var focusedNode: FileNode?
    /// The primary (last clicked) item; the inspector shows it when one item is selected.
    @Published var selectedNode: FileNode? {
        didSet {
            // A plain selection replaces a multi-selection; `select(_:primary:)` keeps it.
            guard selectedNode?.id != oldValue?.id || selectedNode == nil else { return }
            if let selectedNode {
                if !selectedNodes.contains(where: { $0.id == selectedNode.id }) { selectedNodes = [selectedNode] }
            } else if !selectedNodes.isEmpty {
                selectedNodes = []
            }
        }
    }
    /// Every selected item, including `selectedNode`.
    @Published private(set) var selectedNodes: [FileNode] = []
    @Published var isScanning = false
    @Published var scannedCount = 0
    @Published var scannedBytes: Int64 = 0
    @Published var unreadableDirectoryCount = 0
    @Published var currentPath = ""
    @Published var errorMessage: String?
    @Published var pendingDeletion: PendingDeletion?
    @Published var pendingBatchDeletion: PendingBatchDeletion?
    @Published private(set) var isMovingToTrash = false
    @Published var completionMessage: String?
    @Published private(set) var lastTrashedURL: URL?
    @Published var reviewQueue: [FileNode] = []
    @Published private(set) var mountedVolumes: [ScanVolume] = []
    @Published private(set) var scanWarnings: [ScanWarning] = []
    @Published private(set) var lastScanResult: ScanResult?
    @Published private(set) var activeScanID: UUID?
    /// When the shown tree was loaded from disk rather than scanned just now.
    @Published internal(set) var snapshotDate: Date?
    var isShowingSavedScan: Bool { snapshotDate != nil }
    /// Saved scans available to reopen, newest first.
    @Published private(set) var savedScans: [SavedScanInfo] = []
    @Published private(set) var isOpeningSavedScan = false
    /// Where a scanned volume's used space goes, for volume-root scans only.
    @Published private(set) var spaceBreakdown: SpaceBreakdown?
    var spaceProbe: SpaceProbe = SystemSpaceProbe()

    /// `nil` in tests and review tools so they never write to the user's saved scans.
    let scanStore: ScanStore?

    private var scanTask: Task<Void, Never>?
    /// The read-only view handed to edition extensions.
    lazy var extensionContext = LucidDiskContext(viewModel: self)

    init(scanStore: ScanStore? = nil) {
        self.scanStore = scanStore
        refreshMountedVolumes()
        refreshSavedScans()
    }

    func startScan(path: String) {
        guard !isMovingToTrash else { return }
        cancelScan()
        let scanID = UUID()
        activeScanID = scanID
        isScanning = true
        // Keep the completed snapshot intact until its replacement succeeds.
        // Cancelling or failing a rescan must not discard navigation or review work.
        pendingDeletion = nil
        completionMessage = nil
        lastTrashedURL = nil
        scannedCount = 0
        scannedBytes = 0
        unreadableDirectoryCount = 0
        currentPath = ""
        errorMessage = nil

        let scanner = DiskScanner { [weak self] progress in
            Task { @MainActor [weak self] in
                guard let self, self.activeScanID == progress.scanID else { return }
                self.scannedCount = progress.scannedCount
                self.scannedBytes = progress.scannedBytes
                self.currentPath = progress.currentPath
            }
        }

        scanTask = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let result = try scanner.scan(rootPath: path, scanID: scanID)
                await self?.finish(result, for: scanID)
            } catch is CancellationError {
                await self?.finishCancellation(for: scanID)
            } catch {
                await self?.finish(error: error, for: scanID)
            }
        }
    }

    func cancelScan() {
        activeScanID = nil
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }

    func refreshMountedVolumes() {
        let keys: Set<URLResourceKey> = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeIsInternalKey,
            .volumeIsRemovableKey,
            .volumeIsBrowsableKey
        ]
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(keys),
            options: []
        ) ?? []

        mountedVolumes = urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.volumeIsBrowsable != false else { return nil }
            return ScanVolume(
                url: url,
                name: values.volumeName ?? url.lastPathComponent,
                totalBytes: values.volumeTotalCapacity.map(Int64.init),
                availableBytes: values.volumeAvailableCapacityForImportantUsage,
                isInternal: values.volumeIsInternal ?? false,
                isRemovable: values.volumeIsRemovable ?? false
            )
        }.sorted {
            if $0.isInternal != $1.isInternal { return $0.isInternal }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// Review tooling shows sample volumes instead of the reviewer's own disks.
    func showSampleVolumes(_ volumes: [ScanVolume]) {
        mountedVolumes = volumes
    }

    /// Review tooling shows a fixed space breakdown instead of this Mac's real numbers.
    func showSampleSpaceBreakdown(_ breakdown: SpaceBreakdown?) {
        spaceBreakdown = breakdown
    }

    func isCurrentScan(_ id: UUID) -> Bool {
        activeScanID == id
    }

    func zoomOut() {
        guard let parent = focusedNode?.parent else { return }
        focus(on: parent)
    }

    func focus(on node: FileNode) {
        guard node.isDirectory || node.isAggregate else { return }
        focusedNode = node
        selectedNode = nil
    }

    func isQueued(_ node: FileNode) -> Bool {
        reviewQueue.contains { $0.id == node.id }
    }

    func toggleReview(node: FileNode) {
        if isQueued(node) {
            removeFromReview(node: node)
        } else if !node.isAggregate {
            reviewQueue.append(node)
        }
    }

    func removeFromReview(node: FileNode) {
        reviewQueue.removeAll { $0.id == node.id }
    }

    func requestDeletion(node: FileNode) {
        guard !isScanning, !isMovingToTrash else { return }
        guard !isShowingSavedScan else {
            errorMessage = Self.savedScanTrashMessage
            return
        }
        guard isQueued(node) else {
            errorMessage = String(localized: "Add this item to the review queue before moving it to the Trash.")
            return
        }
        let assessment = DeletionSafety.assess(node: node)
        guard assessment.allowsTrash else {
            errorMessage = String(localized: "This item cannot be removed with Lucid Disk.")
                + " " + assessment.recommendation
            return
        }
        pendingDeletion = PendingDeletion(node: node, assessment: assessment)
    }

    func confirmDeletion() {
        guard !isScanning, !isMovingToTrash, !isShowingSavedScan, let pendingDeletion,
              isQueued(pendingDeletion.node) else {
            self.pendingDeletion = nil
            return
        }
        self.pendingDeletion = nil
        trash(node: pendingDeletion.node)
    }

    func finish(_ result: ScanResult, for scanID: UUID) {
        guard activeScanID == scanID, result.id == scanID else { return }
        rootNode = result.root
        focusedNode = result.root
        selectedNode = nil
        reviewQueue = []
        pendingBatchDeletion = nil
        snapshotDate = nil
        lastScanResult = result
        scanWarnings = result.warnings
        scannedCount = result.statistics.scannedFileCount
        scannedBytes = result.statistics.allocatedSizeBytes
        unreadableDirectoryCount = result.statistics.unreadableDirectoryCount
        currentPath = result.root.path
        activeScanID = nil
        scanTask = nil
        isScanning = false
        save(result)
        explainSpace(for: result)
    }

    private func finishCancellation(for scanID: UUID) {
        guard activeScanID == scanID else { return }
        activeScanID = nil
        scanTask = nil
        isScanning = false
    }

    private func finish(error: Error, for scanID: UUID) {
        guard activeScanID == scanID else { return }
        errorMessage = error.localizedDescription
        activeScanID = nil
        scanTask = nil
        isScanning = false
    }



    private func trash(node: FileNode) {
        guard !node.isAggregate, node.parent != nil else { return }
        isMovingToTrash = true
        let rootPath = rootNode?.path
        // Filesystem validation and Trash may be slow on external/network volumes.
        // Keep the UI responsive, but don't allow a second operation concurrently.
        Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> (error: String?, url: URL?) in
                do {
                    try DeletionSafety.validateBeforeTrash(node: node)
                    var destination: NSURL?
                    try FileManager.default.trashItem(at: URL(fileURLWithPath: node.path), resultingItemURL: &destination)
                    return (nil, destination as URL?)
                } catch { return (error.localizedDescription, nil) }
            }.value
            isMovingToTrash = false
            if let error = outcome.error {
                errorMessage = error
            } else {
                invalidateAfterTrash(rescanning: rootPath)
                lastTrashedURL = outcome.url
                completionMessage = String(localized: "Moved \(node.name) to Trash. You can restore it from Finder.")
            }
        }
    }
}

extension ScanViewModel {
    static var savedScanTrashMessage: String {
        String(localized: "This is a saved scan. Scan again before moving items to the Trash.")
    }

    /// The old tree is invalid after a mutation, even if the rescan is stopped.
    func invalidateAfterTrash(rescanning rootPath: String?) {
        rootNode = nil
        focusedNode = nil
        selectedNode = nil
        reviewQueue = []
        pendingBatchDeletion = nil
        lastScanResult = nil
        scanWarnings = []
        snapshotDate = nil
        spaceBreakdown = nil
        if let rootPath { startScan(path: rootPath) }
    }

    func setMovingToTrash(_ value: Bool) { isMovingToTrash = value }
    func setLastTrashedURL(_ url: URL?) { lastTrashedURL = url }
    func setSelectedNodes(_ nodes: [FileNode]) { selectedNodes = nodes }
}

struct PendingDeletion: Identifiable {
    let id = UUID()
    let node: FileNode
    let assessment: DeletionAssessment
}

// MARK: - Saved scans

/// Whether completed scans are saved on this Mac. On by default.
enum ScanSaving {
    static let key = "scans.saveEnabled"
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }
}

extension ScanViewModel {
    func refreshSavedScans() {
        savedScans = scanStore?.list() ?? []
    }

    private func save(_ result: ScanResult) {
        guard let scanStore, ScanSaving.isEnabled else { return }
        Task {
            _ = await Task.detached(priority: .utility) { try? scanStore.save(result) }.value
            refreshSavedScans()
        }
    }

    /// Shows a saved scan. Browsing and queueing work; Trash waits for a fresh scan.
    func openSavedScan(_ info: SavedScanInfo) {
        guard let scanStore, !isScanning, !isMovingToTrash, !isOpeningSavedScan else { return }
        isOpeningSavedScan = true
        errorMessage = nil
        Task {
            let loaded = await Task.detached(priority: .userInitiated) { try? scanStore.load(info) }.value
            isOpeningSavedScan = false
            guard let loaded else {
                errorMessage = String(localized: "The saved scan could not be opened. Scan again to replace it.")
                return
            }
            show(savedScan: loaded)
        }
    }

    func show(savedScan: SavedScan) {
        let result = savedScan.scanResult
        // Current disk numbers would not match an old scan.
        spaceBreakdown = nil
        rootNode = result.root
        focusedNode = result.root
        selectedNode = nil
        reviewQueue = []
        pendingDeletion = nil
        pendingBatchDeletion = nil
        lastScanResult = result
        scanWarnings = result.warnings
        scannedCount = result.statistics.scannedFileCount
        scannedBytes = result.statistics.allocatedSizeBytes
        unreadableDirectoryCount = result.statistics.unreadableDirectoryCount
        currentPath = result.root.path
        completionMessage = nil
        snapshotDate = savedScan.info.scannedAt
    }

    private func explainSpace(for result: ScanResult) {
        spaceBreakdown = nil
        let probe = spaceProbe
        let rootPath = result.root.path
        let scanned = result.root.allocatedSizeBytes
        let unreadable = result.statistics.unreadableDirectoryCount
        let rootID = result.root.id
        Task {
            let breakdown = await Task.detached(priority: .utility) {
                SpaceAnalyzer.breakdown(rootPath: rootPath, scannedBytes: scanned,
                                        unreadableFolderCount: unreadable, probe: probe)
            }.value
            guard rootNode?.id == rootID, !isShowingSavedScan else { return }
            spaceBreakdown = breakdown
        }
    }

    func deleteAllSavedScans() {
        scanStore?.deleteAll()
        refreshSavedScans()
    }
}
