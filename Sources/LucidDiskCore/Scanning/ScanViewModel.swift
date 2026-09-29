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
    @Published var selectedNode: FileNode?
    @Published var isScanning = false
    @Published var scannedCount = 0
    @Published var scannedBytes: Int64 = 0
    @Published var unreadableDirectoryCount = 0
    @Published var currentPath = ""
    @Published var errorMessage: String?
    @Published var pendingDeletion: PendingDeletion?
    @Published private(set) var isMovingToTrash = false
    @Published var completionMessage: String?
    @Published private(set) var lastTrashedURL: URL?
    @Published var reviewQueue: [FileNode] = []
    @Published private(set) var mountedVolumes: [ScanVolume] = []
    @Published private(set) var scanWarnings: [ScanWarning] = []
    @Published private(set) var lastScanResult: ScanResult?
    @Published private(set) var activeScanID: UUID?

    private var scanTask: Task<Void, Never>?
    /// The read-only view handed to edition extensions.
    lazy var extensionContext = LucidDiskContext(viewModel: self)

    init() {
        refreshMountedVolumes()
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
        guard !isScanning, !isMovingToTrash, let pendingDeletion,
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
        lastScanResult = result
        scanWarnings = result.warnings
        scannedCount = result.statistics.scannedFileCount
        scannedBytes = result.statistics.allocatedSizeBytes
        unreadableDirectoryCount = result.statistics.unreadableDirectoryCount
        currentPath = result.root.path
        activeScanID = nil
        scanTask = nil
        isScanning = false
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
                // The old snapshot is invalid after a mutation, even if the rescan is stopped.
                rootNode = nil
                focusedNode = nil
                selectedNode = nil
                reviewQueue = []
                lastScanResult = nil
                scanWarnings = []
                if let rootPath { startScan(path: rootPath) }
                lastTrashedURL = outcome.url
                completionMessage = String(localized: "Moved \(node.name) to Trash. You can restore it from Finder.")
            }
        }
    }
}

struct PendingDeletion: Identifiable {
    let id = UUID()
    let node: FileNode
    let assessment: DeletionAssessment
}
