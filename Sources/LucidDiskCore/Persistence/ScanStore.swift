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
        remove(info)
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
        list().forEach(remove)
        notifyChange()
    }

    /// Total bytes used by saved scans.
    public func diskUsage() -> Int64 {
        let urls = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return urls.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    @discardableResult
    func save(_ result: ScanResult, scannedAt: Date = Date()) throws -> SavedScanInfo {
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
        // Write the tree first so an index entry never points at a missing blob.
        try ScanArchive.encode(root: result.root).write(to: blobURL(info.id), options: .atomic)
        try JSONEncoder().encode(info).write(to: infoURL(info.id), options: .atomic)
        prune(rootPath: info.rootPath)
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
