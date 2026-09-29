import Foundation

/// Summary of a scan saved on this Mac. Small enough to list without loading the tree.
public struct SavedScanInfo: Codable, Identifiable, Equatable, Sendable {
    public struct Warning: Codable, Equatable, Sendable {
        public let path: String
        public let message: String
    }

    public let id: UUID
    public let rootPath: String
    public let rootName: String
    public let scannedAt: Date
    public let duration: TimeInterval
    public let fileCount: Int
    public let directoryCount: Int
    public let logicalSizeBytes: Int64
    public let allocatedSizeBytes: Int64
    public let unreadableDirectoryCount: Int
    public let duplicateHardLinkCount: Int
    public let warnings: [Warning]
    public let formatVersion: Int
}

/// A saved scan with its tree rebuilt.
public struct SavedScan {
    public let info: SavedScanInfo
    public let root: FileNode
}

/// Saves scans as local files so the last result opens instantly.
///
/// The Community edition keeps one scan per location. Other editions may raise
/// `retentionPerRoot` to keep a history; this type stays free of history logic.
public final class ScanStore: @unchecked Sendable {
    public static let shared = ScanStore()
    /// Posted after a scan is saved or deleted. The object is the store.
    public static let didChangeNotification = Notification.Name("LucidDiskScanStoreDidChange")

    public let directory: URL
    /// How many scans to keep for each scanned location, newest first.
    public var retentionPerRoot: Int {
        get { lock.withLock { _retention } }
        set { lock.withLock { _retention = max(1, newValue) } }
    }

    private let lock = NSLock()
    private var _retention = 1
    /// Serializes writes and deletions so they reach the disk in the order they were made.
    private let ioLock = NSLock()
    private var _generation = 0

    /// Changes every time all saved scans are deleted. A save that started
    /// before that passes the old value and is dropped instead of recreating a file.
    public var generation: Int { ioLock.withLock { _generation } }
    private let fileManager = FileManager.default

    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.directory = support.appendingPathComponent("Lucid Disk/Scans", isDirectory: true)
        }
    }

    /// Every saved scan, newest first. Unreadable entries are ignored.
    public func list() -> [SavedScanInfo] {
        let urls = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(SavedScanInfo.self, from: Data(contentsOf: $0)) }
            .filter { $0.formatVersion <= Int(ScanArchive.version) }
            .sorted { $0.scannedAt > $1.scannedAt }
    }

    public func latest(forRootPath rootPath: String) -> SavedScanInfo? {
        list().first { $0.rootPath == rootPath }
    }

    public func load(_ info: SavedScanInfo) throws -> SavedScan {
        let data = try Data(contentsOf: blobURL(info.id))
        return SavedScan(info: info, root: try ScanArchive.decode(data, rootPath: info.rootPath))
    }

    public func delete(_ info: SavedScanInfo) {
        ioLock.withLock { remove(info) }
        notifyChange()
    }

    private func remove(_ info: SavedScanInfo) {
        try? fileManager.removeItem(at: blobURL(info.id))
        try? fileManager.removeItem(at: infoURL(info.id))
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    public func deleteAll() {
        ioLock.withLock {
            _generation += 1
            list().forEach(remove)
        }
        notifyChange()
    }

    /// Total bytes used by saved scans.
    public func diskUsage() -> Int64 {
        let urls = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return urls.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    /// Pass `generation` read when the scan finished; the save is skipped if
    /// every saved scan was deleted in the meantime.
    @discardableResult
    func save(_ result: ScanResult, scannedAt: Date = Date(), generation expected: Int? = nil) throws -> SavedScanInfo {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var excluded = URLResourceValues()
        excluded.isExcludedFromBackup = true
        var directoryURL = directory
        try? directoryURL.setResourceValues(excluded)

        let info = SavedScanInfo(
            id: result.id,
            rootPath: result.root.path,
            rootName: result.root.name,
            scannedAt: scannedAt,
            duration: result.duration,
            fileCount: result.statistics.scannedFileCount,
            directoryCount: result.statistics.scannedDirectoryCount,
            logicalSizeBytes: result.statistics.logicalSizeBytes,
            allocatedSizeBytes: result.statistics.allocatedSizeBytes,
            unreadableDirectoryCount: result.statistics.unreadableDirectoryCount,
            duplicateHardLinkCount: result.statistics.duplicateHardLinkCount,
            warnings: result.warnings.map { .init(path: $0.path, message: $0.message) },
            formatVersion: Int(ScanArchive.version)
        )
        let archive = try ScanArchive.encode(root: result.root)
        let index = try JSONEncoder().encode(info)
        let saved = try ioLock.withLock { () throws -> Bool in
            if let expected, expected != _generation { return false }
            // Write the tree first so an index entry never points at a missing blob.
            try archive.write(to: blobURL(info.id), options: .atomic)
            try index.write(to: infoURL(info.id), options: .atomic)
            prune(rootPath: info.rootPath)
            return true
        }
        guard saved else { throw ScanStoreError.clearedDuringSave }
        notifyChange()
        return info
    }

    private func prune(rootPath: String) {
        let keep = retentionPerRoot
        list().filter { $0.rootPath == rootPath }.dropFirst(keep).forEach(remove)
    }

    private func blobURL(_ id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).ldscan") }
    private func infoURL(_ id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).json") }
}

enum ScanStoreError: Error {
    /// Every saved scan was deleted while this one was being written.
    case clearedDuringSave
}

extension SavedScan {
    /// The shape the scanner produces, for showing a saved scan like a fresh one.
    var scanResult: ScanResult {
        ScanResult(
            id: info.id,
            root: root,
            duration: info.duration,
            statistics: ScanStatistics(
                scannedFileCount: info.fileCount,
                scannedDirectoryCount: info.directoryCount,
                logicalSizeBytes: info.logicalSizeBytes,
                allocatedSizeBytes: info.allocatedSizeBytes,
                unreadableDirectoryCount: info.unreadableDirectoryCount,
                duplicateHardLinkCount: info.duplicateHardLinkCount
            ),
            warnings: info.warnings.map { ScanWarning(path: $0.path, message: $0.message) }
        )
    }
}
