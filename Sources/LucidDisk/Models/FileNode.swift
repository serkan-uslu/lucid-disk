import Darwin
import Foundation
import UniformTypeIdentifiers

enum MeasurementAccuracy: String, Codable {
    /// The filesystem exposes all values needed for this measurement.
    case exact
    /// APFS clone sharing cannot be attributed exactly with public APIs.
    case estimated
    /// Some descendants could not be inspected.
    case incomplete

    var title: String {
        switch self {
        case .exact: String(localized: "Exact measurement")
        case .estimated: String(localized: "Estimated measurement")
        case .incomplete: String(localized: "Incomplete measurement")
        }
    }
}

struct FileIdentity: Hashable, Codable {
    let device: UInt64
    let inode: UInt64

    static func read(atPath path: String) -> FileIdentity? {
        fileSystemStat(atPath: path)?.identity
    }
}

struct FileSystemStat {
    let identity: FileIdentity
    let logicalSizeBytes: Int64
    let allocatedSizeBytes: Int64
    let hardLinkCount: UInt64
    let isDirectory: Bool
    let isSymbolicLink: Bool
    let createdAt: Date
    let modifiedAt: Date
}

func fileSystemStat(atPath path: String) -> FileSystemStat? {
    var value = stat()
    guard path.withCString({ lstat($0, &value) }) == 0 else { return nil }

    return FileSystemStat(
        identity: FileIdentity(
            device: UInt64(bitPattern: Int64(value.st_dev)),
            inode: UInt64(value.st_ino)
        ),
        logicalSizeBytes: max(0, Int64(value.st_size)),
        allocatedSizeBytes: max(0, Int64(value.st_blocks) * 512),
        hardLinkCount: UInt64(value.st_nlink),
        isDirectory: (value.st_mode & S_IFMT) == S_IFDIR,
        isSymbolicLink: (value.st_mode & S_IFMT) == S_IFLNK,
        createdAt: Date(timeIntervalSince1970: Double(value.st_birthtimespec.tv_sec) + Double(value.st_birthtimespec.tv_nsec) / 1e9),
        modifiedAt: Date(timeIntervalSince1970: Double(value.st_mtimespec.tv_sec) + Double(value.st_mtimespec.tv_nsec) / 1e9)
    )
}

final class FileNode: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let isDirectory: Bool
    let isSymlink: Bool
    let fileIdentity: FileIdentity?
    let createdAt: Date?
    let modifiedAt: Date?
    private let scannedContentTypeIdentifier: String?
    // Resolve type only when an item is inspected, never for every scan entry.
    var contentTypeIdentifier: String? {
        if let scannedContentTypeIdentifier { return scannedContentTypeIdentifier }
        if isSymlink { return "public.symlink" }
        if isDirectory { return "public.folder" }
        return UTType(filenameExtension: (name as NSString).pathExtension)?.identifier
    }
    var logicalSizeBytes: Int64
    var allocatedSizeBytes: Int64
    var measurementAccuracy: MeasurementAccuracy
    var scanWarning: String?
    var children: [FileNode]
    weak var parent: FileNode?

    /// Compatibility for the sunburst and existing callers: charts display
    /// physical allocation rather than the logical byte count.
    var size: Int64 {
        get { allocatedSizeBytes }
        set { allocatedSizeBytes = newValue }
    }

    var identity: FileIdentity? { fileIdentity }
    var unreadableWarning: String? { scanWarning }

    // Synthetic "Other" node representing small siblings grouped together.
    var isAggregate = false
    var aggregatedChildren: [FileNode] = []

    init(
        name: String,
        path: String,
        isDirectory: Bool,
        isSymlink: Bool = false,
        size: Int64 = 0,
        logicalSizeBytes: Int64? = nil,
        allocatedSizeBytes: Int64? = nil,
        measurementAccuracy: MeasurementAccuracy = .estimated,
        fileIdentity: FileIdentity? = nil,
        createdAt: Date? = nil,
        modifiedAt: Date? = nil,
        contentTypeIdentifier: String? = nil,
        scanWarning: String? = nil
    ) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.isSymlink = isSymlink
        self.logicalSizeBytes = logicalSizeBytes ?? size
        self.allocatedSizeBytes = allocatedSizeBytes ?? size
        self.measurementAccuracy = measurementAccuracy
        self.fileIdentity = fileIdentity
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.scannedContentTypeIdentifier = contentTypeIdentifier
        self.scanWarning = scanWarning
        self.children = []
    }
}
