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
    /// Invalidates cached layouts/searches when a new tree revision is published.
    @Published private(set) var treeRevision = UUID()
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
    /// The saved scan being loaded. A new scan clears it so a late load cannot replace fresh results.
    private var savedScanRequest: UUID?
    /// Where a scanned volume's used space goes, for volume-root scans only.
    @Published private(set) var spaceBreakdown: SpaceBreakdown?
    var spaceProbe: SpaceProbe = SystemSpaceProbe()

    /// `nil` in tests and review tools so they never write to the user's saved scans.
    let scanStore: ScanStore?

    private var scanTask: Task<Void, Never>?
    private var activeScanner: DiskScanner?
    private var subtreeBeingRescanned: FileNode?
    private var reconciliationTask: Task<Void, Never>?
    /// The read-only view handed to edition extensions.
    lazy var extensionContext = LucidDiskContext(viewModel: self)

    init(scanStore: ScanStore? = nil) {
        self.scanStore = scanStore
        refreshMountedVolumes()
        refreshSavedScans()
    }

    func startScan(path: String) {
        beginScan(path: path, replacing: nil)
    }

    /// Refreshes only this folder. Historical snapshots become a separate fresh
    /// folder scan, so no unscanned portion of a saved tree gains Trash access.
    func rescanFolder(_ node: FileNode) {
        guard node.isDirectory, !node.isAggregate, !isScanning, !isMovingToTrash else { return }
        guard let rootNode, ScanTreeRevision.contains(node.path, in: rootNode.path) else { return }
        beginScan(path: node.path, replacing: isShowingSavedScan ? nil : node)
    }

    private func beginScan(path: String, replacing subtree: FileNode?) {
        guard !isMovingToTrash else { return }
        cancelScan()
        reconciliationTask?.cancel()
        reconciliationTask = nil
        subtreeBeingRescanned = subtree
        let scanID = UUID()
        activeScanID = scanID
        savedScanRequest = nil
        isOpeningSavedScan = false
        isScanning = true
        // Keep the completed snapshot intact until its replacement succeeds.
        // Cancelling or failing a rescan must not discard navigation or review work.
        pendingDeletion = nil
        pendingBatchDeletion = nil
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

        activeScanner = scanner
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

    /// User-facing Stop retains a partial tree; it does not invalidate this scan's ID.
    func stopScan() {
        activeScanner?.requestStop()
    }

    /// Abandons work when another scan supersedes it, without publishing its tree.
    func cancelScan() {
        activeScanID = nil
        scanTask?.cancel()
        scanTask = nil
        activeScanner = nil
        subtreeBeingRescanned = nil
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

        mountedVolumes = urls.compactMap { mountedURL in
            var url = URL(fileURLWithPath: mountedURL.path, isDirectory: true)
            url.removeAllCachedResourceValues()
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
        trash(node: pendingDeletion.node, confirmedPolicy: pendingDeletion.assessment.actionPolicy)
    }

    func finish(_ result: ScanResult, for scanID: UUID) {
        guard activeScanID == scanID, result.id == scanID else { return }
        guard let subtree = subtreeBeingRescanned, let previousRoot = rootNode else {
            publishFinished(result, preservingContext: false)
            return
        }
        // The filesystem may have replaced a folder with a symlink while it was
        // being rescanned. Never merge a result from a different location.
        guard result.root.path == subtree.path else {
            finish(error: CocoaError(.fileReadInvalidFileName), for: scanID)
            return
        }
        let previousDuration = lastScanResult?.duration ?? 0
        Task { [weak self] in
            let revised = await Task.detached(priority: .userInitiated) {
                ScanTreeRevision.replacing(subtree, in: previousRoot, with: result, previousDuration: previousDuration)
            }.value
            guard let self, self.activeScanID == scanID else { return }
            guard let revised else { self.finishCancellation(for: scanID); return }
            self.publishFinished(revised, preservingContext: true)
        }
    }

    private func publishFinished(_ result: ScanResult, preservingContext: Bool) {
        let focusPath = focusedNode?.path
        let selection = selectedNodes
        let primary = selectedNode
        let queued = reviewQueue
        rootNode = result.root
        if preservingContext {
            focusedNode = ScanTreeRevision.nearestFolder(to: focusPath, in: result.root)
            restoreSelection(selection, primary: primary, queue: queued, in: result.root)
        } else {
            focusedNode = result.root
            selectedNode = nil
            reviewQueue = []
        }
        pendingDeletion = nil
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
        activeScanner = nil
        subtreeBeingRescanned = nil
        isScanning = false
        treeRevision = UUID()
        refreshMountedVolumes()
        save(result)
        explainSpace(for: result)
    }

    private func finishCancellation(for scanID: UUID) {
        guard activeScanID == scanID else { return }
        activeScanID = nil
        scanTask = nil
        activeScanner = nil
        subtreeBeingRescanned = nil
        isScanning = false
    }

    private func finish(error: Error, for scanID: UUID) {
        guard activeScanID == scanID else { return }
        errorMessage = error.localizedDescription
        activeScanID = nil
        scanTask = nil
        activeScanner = nil
        subtreeBeingRescanned = nil
        isScanning = false
    }



    private func trash(node: FileNode, confirmedPolicy: ActionPolicy) {
        guard !node.isAggregate, node.parent != nil else { return }
        isMovingToTrash = true
        let rootPath = rootNode?.path
        // Filesystem validation and Trash may be slow on external/network volumes.
        // Keep the UI responsive, but don't allow a second operation concurrently.
        Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> (error: String?, url: URL?) in
                do {
                    try DeletionSafety.validateBeforeTrash(node: node, confirmedPolicy: confirmedPolicy)
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
        treeRevision = UUID()
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
        let generation = scanStore.generation
        let scannedAt = Date()
        Task {
            _ = await Task.detached(priority: .utility) { try? scanStore.save(result, scannedAt: scannedAt, generation: generation) }.value
            refreshSavedScans()
        }
    }

    /// Shows a saved scan. Browsing and queueing work; Trash waits for a fresh scan.
    func openSavedScan(_ info: SavedScanInfo) {
        guard let scanStore, !isScanning, !isMovingToTrash, !isOpeningSavedScan else { return }
        let request = UUID()
        savedScanRequest = request
        isOpeningSavedScan = true
        errorMessage = nil
        Task {
            let loaded = await Task.detached(priority: .userInitiated) { try? scanStore.load(info) }.value
            guard savedScanRequest == request, !isScanning else { return }
            savedScanRequest = nil
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
        treeRevision = UUID()
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
        let revision = treeRevision
        Task {
            let breakdown = await Task.detached(priority: .utility) {
                SpaceAnalyzer.breakdown(rootPath: rootPath, scannedBytes: scanned,
                                        unreadableFolderCount: unreadable, probe: probe)
            }.value
            guard rootNode?.id == rootID, treeRevision == revision, !isShowingSavedScan else { return }
            spaceBreakdown = breakdown
        }
    }

    func deleteAllSavedScans() {
        scanStore?.deleteAll()
        refreshSavedScans()
    }
}

// MARK: - Live filesystem refresh

extension ScanViewModel {
    /// Refreshes capacity and checks the visible/selected/queued live items when
    /// returning from Finder. Missing or replaced scan roots preserve the tree;
    /// an ejected volume must never look like a successfully emptied folder.
    func refreshAfterActivation() {
        refreshMountedVolumes()
        guard !isScanning, !isMovingToTrash, !isShowingSavedScan,
              let root = rootNode, reconciliationTask == nil else { return }
        let revision = treeRevision
        let previousResult = lastScanResult
        let visible = focusedNode.map { [$0] + ($0.isAggregate ? $0.aggregatedChildren : $0.children) } ?? [root]
        let paths = Set((visible + selectedNodes + reviewQueue).map(\.path))
        reconciliationTask = Task { [weak self] in
            let revised = await Task.detached(priority: .utility) { () -> ScanResult? in
                guard let stat = fileSystemStat(atPath: root.path),
                      stat.isDirectory, root.fileIdentity == nil || stat.identity == root.fileIdentity else { return nil }
                let missing = paths.filter { path in
                    guard fileSystemStat(atPath: path) == nil else { return false }
                    return errno == ENOENT || errno == ENOTDIR
                }
                guard !missing.isEmpty, !missing.contains(root.path),
                      fileSystemStat(atPath: root.path)?.identity == stat.identity else { return nil }
                return ScanTreeRevision.removing(missing, from: root, previousResult: previousResult)
            }.value
            guard !Task.isCancelled, let self else { return }
            self.reconciliationTask = nil
            guard self.treeRevision == revision, self.rootNode?.id == root.id,
                  !self.isScanning, !self.isMovingToTrash, !self.isShowingSavedScan,
                  let revised else { return }
            let focusPath = self.focusedNode?.path
            let selection = self.selectedNodes
            let primary = self.selectedNode
            let queued = self.reviewQueue
            self.pendingDeletion = nil
            self.pendingBatchDeletion = nil
            self.rootNode = revised.root
            self.focusedNode = ScanTreeRevision.nearestFolder(to: focusPath, in: revised.root)
            self.restoreSelection(selection, primary: primary, queue: queued, in: revised.root)
            self.lastScanResult = revised
            self.scanWarnings = revised.warnings
            self.scannedCount = revised.statistics.scannedFileCount
            self.scannedBytes = revised.statistics.allocatedSizeBytes
            self.unreadableDirectoryCount = revised.statistics.unreadableDirectoryCount
            self.treeRevision = UUID()
            self.save(revised)
            self.explainSpace(for: revised)
        }
    }

    /// Queued items survive a refresh only if they still refer to the same file.
    /// A replacement at the same path needs its own review and confirmation.
    private func restoreSelection(_ selected: [FileNode], primary: FileNode?, queue: [FileNode], in root: FileNode) {
        let index = Dictionary(uniqueKeysWithValues: ScanTreeRevision.nodes(in: root).map { ($0.path, $0) })
        func current(_ old: FileNode) -> FileNode? {
            guard let node = index[old.path], node.fileIdentity == old.fileIdentity else { return nil }
            return node
        }
        let updatedSelection = selected.compactMap(current)
        select(updatedSelection, primary: primary.flatMap(current))
        reviewQueue = queue.compactMap(current)
    }
}
