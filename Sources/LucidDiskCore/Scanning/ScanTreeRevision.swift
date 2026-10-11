import Foundation

/// Repairs aggregates after a measured subtree is replaced or missing entries
/// are removed. Allocation is attributed once per inode across the whole tree,
/// including hard links whose counted sibling was just removed.
enum ScanTreeRevision {
    static func contains(_ path: String, in parent: String) -> Bool {
        path == parent || path.hasPrefix(parent == "/" ? "/" : parent + "/")
    }

    static func nodes(in root: FileNode) -> [FileNode] {
        var result: [FileNode] = []
        var pending = [root]
        while let node = pending.popLast() {
            result.append(node)
            pending.append(contentsOf: node.children)
        }
        return result
    }

    static func allocations(in root: FileNode) -> [FileIdentity: Int64] {
        var result: [FileIdentity: Int64] = [:]
        for node in nodes(in: root) where !node.isDirectory {
            guard let identity = node.fileIdentity else { continue }
            result[identity] = max(result[identity] ?? 0, node.allocatedSizeBytes)
        }
        return result
    }

    static func result(root: FileNode, id: UUID, duration: TimeInterval,
                       allocations: [FileIdentity: Int64], wasStopped: Bool = false) -> ScanResult {
        var seen: Set<FileIdentity> = []
        var files = 0
        var directories = 0
        var duplicates = 0
        var warnings: [ScanWarning] = []
        func update(_ node: FileNode) {
            if let message = node.scanWarning { warnings.append(.init(path: node.path, message: message)) }
            if node.isDirectory {
                directories += 1
                node.children.forEach(update)
                node.logicalSizeBytes = node.children.reduce(0) { $0 + $1.logicalSizeBytes }
                node.allocatedSizeBytes = node.children.reduce(0) { $0 + $1.allocatedSizeBytes }
                node.measurementAccuracy = node.scanWarning != nil || node.children.contains { $0.measurementAccuracy == .incomplete }
                    ? .incomplete : .estimated
            } else {
                files += 1
                if let identity = node.fileIdentity {
                    if seen.insert(identity).inserted {
                        node.allocatedSizeBytes = allocations[identity] ?? node.allocatedSizeBytes
                    } else {
                        node.allocatedSizeBytes = 0
                        duplicates += 1
                    }
                }
            }
        }
        update(root)
        let unreadableMessage = String(localized: "This directory could not be read.")
        return ScanResult(
            id: id, root: root, duration: duration,
            statistics: ScanStatistics(scannedFileCount: files, scannedDirectoryCount: directories,
                                       logicalSizeBytes: root.logicalSizeBytes, allocatedSizeBytes: root.allocatedSizeBytes,
                                       unreadableDirectoryCount: warnings.filter { $0.message == unreadableMessage }.count,
                                       duplicateHardLinkCount: duplicates),
            warnings: warnings, wasStopped: wasStopped
        )
    }

    static func replacing(_ subtree: FileNode, in root: FileNode, with fresh: ScanResult,
                          previousDuration: TimeInterval) -> ScanResult? {
        let allocations = allocations(in: root).merging(allocations(in: fresh.root), uniquingKeysWith: { _, fresh in fresh })
        let revised: FileNode
        if subtree.id == root.id {
            revised = fresh.root
        } else {
            revised = root.copyForRevision()
            guard let target = nodes(in: revised).first(where: { $0.id == subtree.id }),
                  let parent = target.parent,
                  let index = parent.children.firstIndex(where: { $0.id == target.id }) else { return nil }
            parent.children[index] = fresh.root
            fresh.root.parent = parent
        }
        return result(root: revised, id: fresh.id, duration: previousDuration + fresh.duration,
                      allocations: allocations, wasStopped: fresh.wasStopped)
    }

    static func removing(_ paths: Set<String>, from root: FileNode, previousResult: ScanResult?) -> ScanResult {
        let allocations = allocations(in: root)
        let revised = root.copyForRevision()
        // A missing directory detaches its entire subtree in one operation.
        // Exact set membership keeps this linear even after a large Finder deletion.
        for node in nodes(in: revised) where node.isDirectory {
            node.children.removeAll { paths.contains($0.path) }
        }
        return result(root: revised, id: UUID(), duration: previousResult?.duration ?? 0,
                      allocations: allocations, wasStopped: previousResult?.wasStopped ?? false)
    }

    static func nearestFolder(to path: String?, in root: FileNode) -> FileNode {
        guard let path else { return root }
        return nodes(in: root).filter { $0.isDirectory && contains(path, in: $0.path) }
            .max { $0.path.count < $1.path.count } ?? root
    }
}
