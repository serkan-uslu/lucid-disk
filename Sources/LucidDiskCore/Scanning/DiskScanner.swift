import Foundation

struct ScanProgress {
    let scanID: UUID
    let scannedCount: Int
    let scannedBytes: Int64
    let currentPath: String
}

struct ScanStatistics {
    let scannedFileCount: Int
    let scannedDirectoryCount: Int
    let logicalSizeBytes: Int64
    let allocatedSizeBytes: Int64
    let unreadableDirectoryCount: Int
    let duplicateHardLinkCount: Int
}

struct ScanWarning: Equatable {
    let path: String
    let message: String
}

struct ScanResult {
    let id: UUID
    let root: FileNode
    let duration: TimeInterval
    let statistics: ScanStatistics
    let warnings: [ScanWarning]
    /// The user stopped scanning; measured items are still available to browse.
    var wasStopped = false
}

/// Recursively builds a physical-allocation tree. Task cancellation abandons a
/// superseded scan; a cooperative stop retains the measured portion of the tree.
final class DiskScanner {
    // These root-level macOS path-resolution aliases expose the same filesystem
    // again. They are not ordinary symlinks: lstat("/.nofollow") even reports a
    // different inode from lstat("/.nofollow/"). Never descend through them.
    private static let resolutionAliases: Set<String> = ["/.nofollow", "/.resolve"]
    static let excludedPaths: Set<String> = Set([
        "/System/Volumes", "/Volumes", "/dev", "/Network", "/.vol",
        "/home", "/cores", "/afs", "/net"
    ]).union(resolutionAliases)

    private let readStat: (String) -> FileSystemStat?
    private let readDirectory: (URL) throws -> [URL]
    private let progressHandler: (ScanProgress) -> Void
    private let maximumItemCount: Int?
    private let entryWillBeRead: ((URL) -> Void)?
    private let stopLock = NSLock()
    private var stopRequested = false

    func requestStop() {
        stopLock.lock()
        stopRequested = true
        stopLock.unlock()
    }

    private var shouldStop: Bool {
        stopLock.lock()
        defer { stopLock.unlock() }
        return stopRequested
    }

    init(
        maximumItemCount: Int? = nil,
        entryWillBeRead: ((URL) -> Void)? = nil,
        readStat: @escaping (String) -> FileSystemStat? = fileSystemStat(atPath:),
        readDirectory: @escaping (URL) throws -> [URL] = {
            try FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: [], options: [])
        },
        progressHandler: @escaping (ScanProgress) -> Void
    ) {
        self.maximumItemCount = maximumItemCount
        self.entryWillBeRead = entryWillBeRead
        self.readStat = readStat
        self.readDirectory = readDirectory
        self.progressHandler = progressHandler
    }

    static func isOnRootVolume(rootDevice: UInt64?, childDevice: UInt64?) -> Bool {
        guard let rootDevice, let childDevice else { return true }
        return rootDevice == childDevice
    }

    func scan(rootPath: String, scanID: UUID = UUID()) throws -> ScanResult {
        try Task.checkCancellation()
        let startedAt = Date()
        let normalizedRoot = URL(fileURLWithPath: rootPath).standardizedFileURL.resolvingSymlinksInPath().path
        let displayName: String
        if normalizedRoot == "/" {
            // Use the startup volume's real name; it may have been renamed.
            displayName = (try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeNameKey]).volumeName)
                ?? "Macintosh HD"
        } else {
            let last = (normalizedRoot as NSString).lastPathComponent
            displayName = last.isEmpty ? normalizedRoot : last
        }

        guard let rootStat = readStat(normalizedRoot) else {
            // Preserve access-denied vs. missing-path errors for actionable feedback.
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno),
                          userInfo: [NSFilePathErrorKey: normalizedRoot])
        }
        guard rootStat.isDirectory else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENOTDIR),
                          userInfo: [NSFilePathErrorKey: normalizedRoot])
        }
        let root = FileNode(
            name: displayName,
            path: normalizedRoot,
            isDirectory: true,
            measurementAccuracy: .estimated,
            fileIdentity: rootStat.identity,
            createdAt: rootStat.createdAt,
            modifiedAt: rootStat.modifiedAt
        )
        var state = ScanState(scanID: scanID, rootDevice: rootStat.identity.device)
        try scanDirectory(root, state: &state)
        try Task.checkCancellation()
        progressHandler(ScanProgress(
            scanID: scanID,
            scannedCount: state.scannedFileCount,
            scannedBytes: root.allocatedSizeBytes,
            currentPath: normalizedRoot
        ))

        return ScanResult(
            id: scanID,
            root: root,
            duration: Date().timeIntervalSince(startedAt),
            statistics: ScanStatistics(
                scannedFileCount: state.scannedFileCount,
                scannedDirectoryCount: state.scannedDirectoryCount,
                logicalSizeBytes: root.logicalSizeBytes,
                allocatedSizeBytes: root.allocatedSizeBytes,
                unreadableDirectoryCount: state.unreadableDirectoryCount,
                duplicateHardLinkCount: state.duplicateHardLinkCount
            ),
            warnings: state.warnings,
            wasStopped: state.wasStopped
        )
    }

    private func scanDirectory(_ node: FileNode, state: inout ScanState) throws {
        try Task.checkCancellation()
        if stopIfRequested(node, state: &state) { return }
        if Self.excludedPaths.contains(node.path) || Self.resolutionAliases.contains(where: {
            node.path.hasPrefix($0 + "/")
        }) {
            markIncomplete(
                node,
                message: String(localized: "This filesystem location was intentionally excluded."),
                state: &state
            )
            return
        }
        // Device + inode identifies a directory independently of the path used
        // to reach it (firmlinks, aliases, or a directory cycle). Register the
        // root as well, before enumerating, so an alias cannot walk back into it.
        if let identity = node.fileIdentity, !state.seenDirectories.insert(identity).inserted {
            markIncomplete(
                node,
                message: String(localized: "This directory was already visited through another path and was not counted again."),
                state: &state
            )
            return
        }
        state.scannedDirectoryCount += 1

        let dirURL = URL(fileURLWithPath: node.path)
        let entries: [URL]
        do {
            entries = try readDirectory(dirURL)
        } catch {
            state.unreadableDirectoryCount += 1
            markIncomplete(
                node,
                message: String(localized: "This directory could not be read."),
                state: &state
            )
            return
        }

        for url in entries {
            try Task.checkCancellation()
            if stopIfRequested(node, state: &state) { break }
            if let limit = maximumItemCount, state.visitedItemCount >= limit {
                markIncomplete(
                    node,
                    message: String(localized: "The scan item limit was reached."),
                    state: &state
                )
                break
            }
            state.visitedItemCount += 1

            entryWillBeRead?(url)
            if stopIfRequested(node, state: &state) { break }
            guard let stat = readStat(url.path) else {
                let child = FileNode(
                    name: url.lastPathComponent,
                    path: url.path,
                    isDirectory: false,
                    measurementAccuracy: .incomplete
                )
                child.parent = node
                node.children.append(child)
                markIncomplete(
                    child,
                    message: String(localized: "This item changed or became unreadable during the scan."),
                    state: &state
                )
                node.measurementAccuracy = .incomplete
                continue
            }
            let isSymlink = stat.isSymbolicLink
            let isDir = stat.isDirectory && !isSymlink
            let logicalSize = stat.logicalSizeBytes
            var allocatedSize = stat.allocatedSizeBytes

            if !isDir, stat.hardLinkCount > 1 {
                if !state.seenHardLinks.insert(stat.identity).inserted {
                    allocatedSize = 0
                    state.duplicateHardLinkCount += 1
                }
            }

            let child = FileNode(
                name: url.lastPathComponent,
                path: url.path,
                isDirectory: isDir,
                isSymlink: isSymlink,
                logicalSizeBytes: isDir ? 0 : logicalSize,
                allocatedSizeBytes: isDir ? 0 : allocatedSize,
                measurementAccuracy: isSymlink ? .exact : .estimated,
                fileIdentity: stat.identity,
                createdAt: stat.createdAt,
                modifiedAt: stat.modifiedAt
            )
            child.parent = node
            node.children.append(child)

            if isDir {
                if !Self.isOnRootVolume(
                    rootDevice: state.rootDevice,
                    childDevice: stat.identity.device
                ) {
                    markIncomplete(
                        child,
                        message: String(localized: "A different mounted volume was not scanned."),
                        state: &state
                    )
                } else {
                    try scanDirectory(child, state: &state)
                }
            } else {
                state.scannedFileCount += 1
                state.allocatedBytes += allocatedSize
                emitProgressIfNeeded(path: url.path, state: &state)
            }

            node.logicalSizeBytes += child.logicalSizeBytes
            node.allocatedSizeBytes += child.allocatedSizeBytes
            if child.measurementAccuracy == .incomplete {
                node.measurementAccuracy = .incomplete
            }
        }
    }

    private func stopIfRequested(_ node: FileNode, state: inout ScanState) -> Bool {
        guard shouldStop else { return false }
        state.wasStopped = true
        markIncomplete(node, message: String(localized: "Scan stopped. Only items measured so far are shown."), state: &state)
        return true
    }

    private func markIncomplete(_ node: FileNode, message: String, state: inout ScanState) {
        node.measurementAccuracy = .incomplete
        node.scanWarning = message
        let warning = ScanWarning(path: node.path, message: message)
        state.warnings.append(warning)
    }

    private func emitProgressIfNeeded(path: String, state: inout ScanState) {
        let now = Date()
        if now.timeIntervalSince(state.lastProgressAt) > 0.15 {
            state.lastProgressAt = now
            progressHandler(ScanProgress(
                scanID: state.scanID,
                scannedCount: state.scannedFileCount,
                scannedBytes: state.allocatedBytes,
                currentPath: path
            ))
        }
    }

    private struct ScanState {
        let scanID: UUID
        let rootDevice: UInt64?
        var wasStopped = false
        var visitedItemCount = 0
        var scannedFileCount = 0
        var scannedDirectoryCount = 0
        var unreadableDirectoryCount = 0
        var duplicateHardLinkCount = 0
        var allocatedBytes: Int64 = 0
        var seenDirectories: Set<FileIdentity> = []
        var seenHardLinks: Set<FileIdentity> = []
        var warnings: [ScanWarning] = []
        var lastProgressAt = Date.distantPast
    }
}
