import Darwin
import Foundation

/// Where a volume's used space goes, including what a scan cannot see
/// (the "System Data" gap). Every size comes from macOS; nothing is guessed.
public struct SpaceBreakdown: Equatable, Sendable {
    public struct Item: Identifiable, Equatable, Sendable {
        public enum Kind: String, Sendable {
            /// Measured by the scan.
            case scanned
            /// Another APFS volume in the same container, such as Preboot or VM.
            case otherVolume
            /// Used space on the scanned volumes the scan could not see.
            case notVisible
            /// File allocations exceed reported usage; shared blocks may contribute.
            case sharedBlocks
        }

        public let id: String
        public let kind: Kind
        public let title: String
        public let bytes: Int64
        public let detail: String
    }

    public let volumeName: String
    public let capacityBytes: Int64
    public let usedBytes: Int64
    public let freeBytes: Int64
    public let scannedBytes: Int64
    public let items: [Item]
    /// Space macOS can reclaim automatically (caches, iCloud copies, and so on).
    public let purgeableBytes: Int64?
    /// Local Time Machine snapshots; macOS does not report their size.
    public let localSnapshotCount: Int?
    /// Folders the scan could not open, usually for lack of Full Disk Access.
    public let unreadableFolderCount: Int

    /// Used space that the scan itself did not measure.
    public var outsideScanBytes: Int64 { max(0, usedBytes - scannedBytes) }
}

// MARK: - macOS data sources

struct APFSVolumeInfo: Equatable, Sendable {
    let name: String
    let roles: [String]
    let capacityInUse: Int64
    let deviceIdentifier: String
}

struct APFSContainerInfo: Equatable, Sendable {
    let reference: String
    let capacityCeiling: Int64
    let capacityFree: Int64
    let volumes: [APFSVolumeInfo]
}

struct VolumeCapacity: Equatable, Sendable {
    let name: String
    let total: Int64
    let available: Int64
    let availableForImportantUsage: Int64?
}

enum StorageCapacity {
    /// Capacity samples can disagree or be unavailable. Do not turn inconsistent
    /// readings into a confident reclaimable-space estimate.
    static func estimatedReclaimableBytes(total: Int64, free: Int64, available: Int64?) -> Int64? {
        guard total >= 0, (0...total).contains(free), let available,
              (free...total).contains(available) else { return nil }
        return available - free
    }
}

struct DiskInfo: Equatable, Sendable {
    let containerReference: String?
    let deviceIdentifier: String?
    var volumeGroupID: UUID? = nil
}

/// Read-only system queries, injectable so tests use fixtures.
protocol SpaceProbe: Sendable {
    func isMountPoint(_ path: String) -> Bool
    func volumeCapacity(at path: String) -> VolumeCapacity?
    func diskInfo(forMountPoint path: String) -> DiskInfo?
    func apfsContainers() -> [APFSContainerInfo]
    func localSnapshotCount(forMountPoint path: String) -> Int?
    func swapUsage() -> (total: Int64, used: Int64)?
}

struct SystemSpaceProbe: SpaceProbe {
    func isMountPoint(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard let volume = try? url.resourceValues(forKeys: [.volumeURLKey]).volume else { return false }
        return volume.standardizedFileURL.path == url.path
    }

    func volumeCapacity(at path: String) -> VolumeCapacity? {
        let keys: Set<URLResourceKey> = [
            .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]
        guard let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity, let available = values.volumeAvailableCapacity else { return nil }
        return VolumeCapacity(
            name: values.volumeName ?? (path as NSString).lastPathComponent,
            total: Int64(total),
            available: Int64(available),
            availableForImportantUsage: values.volumeAvailableCapacityForImportantUsage
        )
    }

    func diskInfo(forMountPoint path: String) -> DiskInfo? {
        Command.run("/usr/sbin/diskutil", ["info", "-plist", path]).flatMap(SpaceParsing.diskInfo)
    }

    func apfsContainers() -> [APFSContainerInfo] {
        Command.run("/usr/sbin/diskutil", ["apfs", "list", "-plist"]).map(SpaceParsing.apfsContainers) ?? []
    }

    func localSnapshotCount(forMountPoint path: String) -> Int? {
        Command.run("/usr/bin/tmutil", ["listlocalsnapshots", path])
            .flatMap { String(data: $0, encoding: .utf8) }
            .map(SpaceParsing.snapshotCount)
    }

    func swapUsage() -> (total: Int64, used: Int64)? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return nil }
        return (Int64(usage.xsu_total), Int64(usage.xsu_used))
    }
}

/// Runs a system tool by absolute path with a timeout. Output is data, never interpreted as commands.
enum Command {
    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 10) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let deadline = Date().addingTimeInterval(timeout)
        var data = Data()
        let reader = DispatchQueue(label: "lucid.command.read")
        let done = DispatchSemaphore(value: 0)
        reader.async {
            data = output.fileHandleForReading.readDataToEndOfFile()
            done.signal()
        }
        if done.wait(timeout: .now() + timeout) == .timedOut || Date() > deadline {
            process.terminate()
            return nil
        }
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }
}

enum SpaceParsing {
    static func plist(_ data: Data) -> [String: Any]? {
        try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    }

    static func diskInfo(_ data: Data) -> DiskInfo? {
        guard let dictionary = plist(data) else { return nil }
        return DiskInfo(
            containerReference: dictionary["APFSContainerReference"] as? String,
            deviceIdentifier: dictionary["DeviceIdentifier"] as? String,
            volumeGroupID: (dictionary["APFSVolumeGroupID"] as? String).flatMap(UUID.init(uuidString:))
        )
    }

    static func apfsContainers(_ data: Data) -> [APFSContainerInfo] {
        guard let containers = plist(data)?["Containers"] as? [[String: Any]] else { return [] }
        return containers.compactMap { container in
            guard let reference = container["ContainerReference"] as? String,
                  let ceiling = (container["CapacityCeiling"] as? NSNumber)?.int64Value,
                  let free = (container["CapacityFree"] as? NSNumber)?.int64Value else { return nil }
            let volumes = (container["Volumes"] as? [[String: Any]] ?? []).compactMap { volume -> APFSVolumeInfo? in
                guard let identifier = volume["DeviceIdentifier"] as? String else { return nil }
                return APFSVolumeInfo(
                    name: volume["Name"] as? String ?? identifier,
                    roles: volume["Roles"] as? [String] ?? [],
                    capacityInUse: (volume["CapacityInUse"] as? NSNumber)?.int64Value ?? 0,
                    deviceIdentifier: identifier
                )
            }
            return APFSContainerInfo(reference: reference, capacityCeiling: ceiling, capacityFree: free, volumes: volumes)
        }
    }

    static func snapshotCount(_ text: String) -> Int {
        text.split(separator: "\n").filter { $0.hasPrefix("com.apple.") }.count
    }
}

// MARK: - Analysis

enum SpaceAnalyzer {
    /// Explains a completed scan of a volume's root. Returns `nil` for folder scans.
    static func breakdown(
        rootPath: String,
        scannedBytes: Int64,
        unreadableFolderCount: Int,
        probe: SpaceProbe = SystemSpaceProbe()
    ) -> SpaceBreakdown? {
        guard probe.isMountPoint(rootPath), let capacity = probe.volumeCapacity(at: rootPath) else { return nil }

        let snapshots = probe.localSnapshotCount(forMountPoint: rootPath)
        var items: [SpaceBreakdown.Item] = []
        var hasUnclassifiedVolumes = false

        let info = probe.diskInfo(forMountPoint: rootPath)
        let container = info?.containerReference.flatMap { reference in
            probe.apfsContainers().first { $0.reference == reference }
        }

        let total: Int64
        let free: Int64
        var otherVolumesBytes: Int64 = 0
        if let container {
            total = container.capacityCeiling
            free = container.capacityFree
            let device = info?.deviceIdentifier ?? ""
            let isStartup = rootPath == "/"
            let sourceVolume = container.volumes.first {
                device == $0.deviceIdentifier || device.hasPrefix($0.deviceIdentifier + "s")
            }
            let dataDevice = isStartup
                ? startupDataDevice(in: container, rootGroupID: info?.volumeGroupID, probe: probe) : nil
            for volume in container.volumes {
                // Only the booted System/snapshot and its mounted Data volume are
                // covered. Other installations can have the same roles in this container.
                let covered = volume.deviceIdentifier == sourceVolume?.deviceIdentifier
                    || volume.deviceIdentifier == dataDevice
                guard !covered, volume.capacityInUse > 0 else { continue }
                let uncertain = isStartup
                    ? (dataDevice == nil && volume.roles.contains("Data"))
                        || (sourceVolume == nil && volume.roles.contains("System"))
                    : sourceVolume == nil
                if uncertain {
                    // Do not add an amount that may already be in the scan. Leave
                    // attribution unresolved, preserving the physical used/free totals.
                    hasUnclassifiedVolumes = true
                    continue
                }
                otherVolumesBytes += volume.capacityInUse
                items.append(otherVolumeItem(volume, swap: probe.swapUsage()))
            }
        } else {
            total = capacity.total
            free = capacity.available
        }
        guard total >= 0, (0...total).contains(free) else { return nil }
        let used = total - free

        var scannedDetail = String(localized: "Everything the scan could open and measure.")
        if hasUnclassifiedVolumes {
            scannedDetail += " " + String(localized: "Some volumes could not be matched to this scan. Their separate amounts are omitted because they may overlap the scan.")
        }
        items.insert(SpaceBreakdown.Item(
            id: "scanned", kind: .scanned,
            title: String(localized: "Scanned by Lucid Disk"),
            bytes: scannedBytes, detail: scannedDetail
        ), at: 0)

        let remainder = used - scannedBytes - otherVolumesBytes
        if remainder > 0 {
            items.append(SpaceBreakdown.Item(
                id: "not-visible", kind: .notVisible,
                title: String(localized: "Used, but not visible to the scan"),
                bytes: remainder,
                detail: notVisibleDetail(isStartup: rootPath == "/", snapshots: snapshots, unreadable: unreadableFolderCount)
            ))
        } else if remainder < 0 {
            items.append(SpaceBreakdown.Item(
                id: "shared-blocks", kind: .sharedBlocks,
                title: String(localized: "Allocation estimate exceeds used space"),
                bytes: -remainder,
                detail: String(localized: "The measured file allocations exceed the space macOS reports as used. Shared APFS blocks and changes during scanning can contribute. This difference is not reclaimable space."),
            ))
        }

        return SpaceBreakdown(
            volumeName: capacity.name,
            capacityBytes: total,
            usedBytes: used,
            freeBytes: free,
            scannedBytes: scannedBytes,
            items: items,
            purgeableBytes: StorageCapacity.estimatedReclaimableBytes(
                total: total, free: free, available: capacity.availableForImportantUsage),
            localSnapshotCount: snapshots,
            unreadableFolderCount: unreadableFolderCount
        )
    }

    private static func startupDataDevice(in container: APFSContainerInfo, rootGroupID: UUID?,
                                          probe: SpaceProbe) -> String? {
        let path = "/System/Volumes/Data"
        guard probe.isMountPoint(path), let dataInfo = probe.diskInfo(forMountPoint: path),
              dataInfo.containerReference == container.reference,
              let device = dataInfo.deviceIdentifier,
              container.volumes.contains(where: { $0.deviceIdentifier == device && $0.roles.contains("Data") }) else {
            return nil
        }
        if let rootGroupID, let dataGroupID = dataInfo.volumeGroupID, rootGroupID != dataGroupID { return nil }
        // Older or incomplete diskutil output may omit group IDs. The canonical
        // mounted Data device in the same container still identifies the booted Data volume.
        return device
    }

    private static func otherVolumeItem(_ volume: APFSVolumeInfo, swap: (total: Int64, used: Int64)?) -> SpaceBreakdown.Item {
        let title: String
        let detail: String
        switch volume.roles.first {
        case "VM":
            title = String(localized: "Virtual memory")
            var text = String(localized: "Swap files and the sleep image. macOS manages this volume and shrinks it as memory pressure falls.")
            if let swap, swap.total > 0 {
                text += " " + String(localized: "Swap in use: \(ByteCountFormatter.string(fromByteCount: swap.used, countStyle: .memory)).")
            }
            detail = text
        case "Preboot":
            title = String(localized: "Startup support (Preboot)")
            detail = String(localized: "Files macOS needs to start up, including cryptexes for system updates. Managed by macOS.")
        case "Recovery":
            title = String(localized: "macOS Recovery")
            detail = String(localized: "The recovery system used to repair or reinstall macOS. Managed by macOS.")
        case "Update":
            title = String(localized: "Software update staging")
            detail = String(localized: "Space used while macOS prepares updates. Managed by macOS.")
        default:
            title = String(localized: "Other volume: \(volume.name)")
            detail = String(localized: "Another volume sharing this disk's space. Scan it separately to see inside.")
        }
        return SpaceBreakdown.Item(id: "volume-\(volume.deviceIdentifier)", kind: .otherVolume,
                                   title: title, bytes: volume.capacityInUse, detail: detail)
    }

    private static func notVisibleDetail(isStartup: Bool, snapshots: Int?, unreadable: Int) -> String {
        var parts: [String] = []
        if isStartup {
            parts.append(String(localized: "System files kept outside the folders a scan can reach: the Spotlight index, document versions, file-system event logs and APFS metadata."))
        } else {
            parts.append(String(localized: "File-system metadata and hidden system folders on this volume."))
        }
        if let snapshots, snapshots > 0 {
            parts.append(String(localized: "\(snapshots) local Time Machine snapshots. macOS does not report their size and removes them automatically when space runs low."))
        }
        if unreadable > 0 {
            parts.append(String(localized: "\(unreadable) folders could not be read. Grant Full Disk Access and scan again to measure them."))
        }
        return parts.joined(separator: " ")
    }
}
