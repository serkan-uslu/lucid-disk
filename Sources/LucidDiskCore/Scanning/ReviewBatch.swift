import Foundation

/// What happened when several items were offered to the review queue.
struct BatchQueueOutcome: Equatable {
    var added = 0
    var alreadyQueued = 0
    var skippedProtected = 0
    var skippedGroups = 0
}

/// A reviewed set of queue items waiting for the user's confirmation.
struct PendingBatchDeletion: Identifiable {
    struct Item {
        let node: FileNode
        let assessment: DeletionAssessment
    }

    let id = UUID()
    let items: [Item]
    /// Blocked items that stay in the queue but are never moved.
    let excludedProtected: Int
    /// Items inside another queued folder; moving the folder covers them.
    let excludedNested: Int

    var totalBytes: Int64 { items.reduce(0) { $0 + $1.node.size } }
    var requiresStrongConfirmation: Bool { items.contains { $0.assessment.actionPolicy == .strongConfirmation } }
    var sensitiveCount: Int { items.filter { $0.assessment.actionPolicy == .strongConfirmation }.count }
}

extension ScanViewModel {
    // MARK: Selection

    /// Replaces the selection. `primary` is what a single-item inspector would show.
    func select(_ nodes: [FileNode], primary: FileNode?) {
        setSelectedNodes(nodes)
        selectedNode = primary ?? nodes.last
    }

    /// ⌘-click behaviour: adds or removes one item from the selection.
    func toggleSelection(_ node: FileNode) {
        guard !node.isAggregate else { return }
        var nodes = selectedNodes
        if let index = nodes.firstIndex(where: { $0.id == node.id }) {
            nodes.remove(at: index)
            select(nodes, primary: nodes.last)
        } else {
            nodes.append(node)
            select(nodes, primary: node)
        }
    }

    // MARK: Queue

    /// Queues every item that may be reviewed. Protected items and synthetic groups are skipped.
    @discardableResult
    func addToReview(_ nodes: [FileNode]) -> BatchQueueOutcome {
        var outcome = BatchQueueOutcome()
        for node in nodes {
            if node.isAggregate {
                outcome.skippedGroups += 1
            } else if isQueued(node) {
                outcome.alreadyQueued += 1
            } else if !DeletionSafety.assess(node: node).allowsTrash {
                outcome.skippedProtected += 1
            } else {
                reviewQueue.append(node)
                outcome.added += 1
            }
        }
        return outcome
    }

    func removeFromReview(_ nodes: [FileNode]) {
        let ids = Set(nodes.map(\.id))
        reviewQueue.removeAll { ids.contains($0.id) }
    }

    func clearReviewQueue() {
        reviewQueue = []
        pendingBatchDeletion = nil
    }

    // MARK: Batch Trash

    /// Items whose ancestor is also listed are dropped: moving the ancestor moves them.
    static func topLevelItems(_ nodes: [FileNode]) -> [FileNode] {
        let ids = Set(nodes.map(\.id))
        return nodes.filter { node in
            var ancestor = node.parent
            while let current = ancestor {
                if ids.contains(current.id) { return false }
                ancestor = current.parent
            }
            return true
        }
    }

    func requestBatchDeletion() {
        guard !isScanning, !isMovingToTrash, !reviewQueue.isEmpty else { return }
        guard !isShowingSavedScan else {
            errorMessage = Self.savedScanTrashMessage
            return
        }
        let topLevel = Self.topLevelItems(reviewQueue)
        var items: [PendingBatchDeletion.Item] = []
        var protected = 0
        for node in topLevel {
            let assessment = DeletionSafety.assess(node: node)
            if assessment.allowsTrash {
                items.append(.init(node: node, assessment: assessment))
            } else {
                protected += 1
            }
        }
        guard !items.isEmpty else {
            errorMessage = String(localized: "None of the queued items can be moved to the Trash.")
            return
        }
        pendingBatchDeletion = PendingBatchDeletion(
            items: items,
            excludedProtected: protected,
            excludedNested: reviewQueue.count - topLevel.count
        )
    }

    func confirmBatchDeletion() {
        guard !isScanning, !isMovingToTrash, !isShowingSavedScan, let pending = pendingBatchDeletion else {
            pendingBatchDeletion = nil
            return
        }
        pendingBatchDeletion = nil
        // A stale confirmation must not move items the user has since removed from the queue.
        let queued = Set(reviewQueue.map(\.id))
        let nodes = pending.items.map(\.node).filter { queued.contains($0.id) && !$0.isAggregate && $0.parent != nil }
        guard !nodes.isEmpty else { return }
        setMovingToTrash(true)
        let rootPath = rootNode?.path
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                Self.moveToTrash(nodes)
            }.value
            setMovingToTrash(false)
            if outcome.moved > 0 {
                invalidateAfterTrash(rescanning: rootPath)
                setLastTrashedURL(outcome.lastURL)
            }
            completionMessage = outcome.summary
            if outcome.moved == 0 { errorMessage = outcome.summary }
        }
    }

    struct BatchTrashOutcome: Sendable {
        var moved = 0
        var failures: [String] = []
        /// Where each moved item landed in the Trash, for "Show in Trash" and recovery.
        var destinations: [URL] = []
        var lastURL: URL? { destinations.last }

        var summary: String {
            var text = moved == 1
                ? String(localized: "Moved 1 item to Trash. You can restore it from Finder.")
                : String(localized: "Moved \(moved) items to Trash. You can restore them from Finder.")
            if !failures.isEmpty {
                text += " " + String(localized: "Skipped \(failures.count): \(failures.prefix(3).joined(separator: "; "))")
            }
            return text
        }
    }

    /// Each item is re-validated immediately before its own move.
    nonisolated static func moveToTrash(_ nodes: [FileNode]) -> BatchTrashOutcome {
        var outcome = BatchTrashOutcome()
        for node in nodes {
            do {
                try DeletionSafety.validateBeforeTrash(node: node)
                var destination: NSURL?
                try FileManager.default.trashItem(at: URL(fileURLWithPath: node.path), resultingItemURL: &destination)
                outcome.moved += 1
                if let destination = destination as URL? { outcome.destinations.append(destination) }
            } catch {
                outcome.failures.append("\(node.name) — \(error.localizedDescription)")
            }
        }
        return outcome
    }
}
