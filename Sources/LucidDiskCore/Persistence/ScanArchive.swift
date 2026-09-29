import Foundation

/// Compact binary encoding of a scanned tree.
///
/// Whole-disk scans hold millions of nodes, so this is a preorder stream of
/// fixed-width fields rather than JSON. Paths are not stored; they are rebuilt
/// from the root path and each node's name. The stream is LZFSE-compressed.
enum ScanArchive {
    static let magic: [UInt8] = Array("LDSC".utf8)
    static let version: UInt16 = 1

    enum Failure: Error, Equatable {
        case notAnArchive
        case unsupportedVersion(UInt16)
        case truncated
    }

    private enum Flag {
        static let directory: UInt8 = 1
        static let symlink: UInt8 = 2
        static let identity: UInt8 = 4
        static let created: UInt8 = 8
        static let modified: UInt8 = 16
        static let warning: UInt8 = 32
    }

    // MARK: Encoding

    static func encode(root: FileNode) throws -> Data {
        var writer = Writer()
        writer.bytes(magic)
        writer.integer(version)
        var stack = [root]
        while let node = stack.popLast() {
            writer.string(node.name)
            var flags: UInt8 = 0
            if node.isDirectory { flags |= Flag.directory }
            if node.isSymlink { flags |= Flag.symlink }
            if node.fileIdentity != nil { flags |= Flag.identity }
            if node.createdAt != nil { flags |= Flag.created }
            if node.modifiedAt != nil { flags |= Flag.modified }
            if node.scanWarning != nil { flags |= Flag.warning }
            writer.integer(flags)
            writer.integer(accuracyCode(node.measurementAccuracy))
            writer.integer(node.logicalSizeBytes)
            writer.integer(node.allocatedSizeBytes)
            if let identity = node.fileIdentity {
                writer.integer(identity.device)
                writer.integer(identity.inode)
            }
            if let createdAt = node.createdAt { writer.double(createdAt.timeIntervalSince1970) }
            if let modifiedAt = node.modifiedAt { writer.double(modifiedAt.timeIntervalSince1970) }
            if let warning = node.scanWarning { writer.string(warning) }
            writer.integer(UInt32(node.children.count))
            // Reverse so children pop in their original order.
            stack.append(contentsOf: node.children.reversed())
        }
        return try (writer.data as NSData).compressed(using: .lzfse) as Data
    }

    // MARK: Decoding

    static func decode(_ compressed: Data, rootPath: String) throws -> FileNode {
        let data: Data
        do {
            data = try (compressed as NSData).decompressed(using: .lzfse) as Data
        } catch {
            throw Failure.notAnArchive
        }
        var reader = Reader(data: data)
        guard try reader.bytes(magic.count) == magic else { throw Failure.notAnArchive }
        let fileVersion: UInt16 = try reader.integer()
        guard fileVersion == version else { throw Failure.unsupportedVersion(fileVersion) }

        // Each frame is a directory still expecting `remaining` children.
        var frames: [(node: FileNode, remaining: UInt32)] = []
        var root: FileNode?
        repeat {
            let parent = frames.last?.node
            let path: String
            let name = try reader.string()
            if let parent {
                path = parent.path == "/" ? "/" + name : parent.path + "/" + name
            } else {
                path = rootPath
            }
            let node = try readNode(named: name, path: path, from: &reader)
            let childCount: UInt32 = try reader.integer()
            if let parent {
                node.parent = parent
                parent.children.append(node)
                frames[frames.count - 1].remaining -= 1
            } else {
                root = node
            }
            if childCount > 0 {
                node.children.reserveCapacity(Int(childCount))
                frames.append((node, childCount))
            }
            while let last = frames.last, last.remaining == 0 { frames.removeLast() }
        } while !frames.isEmpty

        guard let root, reader.isAtEnd else { throw Failure.truncated }
        return root
    }

    private static func readNode(named name: String, path: String, from reader: inout Reader) throws -> FileNode {
        let flags: UInt8 = try reader.integer()
        let accuracy = accuracy(try reader.integer())
        let logical: Int64 = try reader.integer()
        let allocated: Int64 = try reader.integer()
        var identity: FileIdentity?
        if flags & Flag.identity != 0 {
            identity = FileIdentity(device: try reader.integer(), inode: try reader.integer())
        }
        let created = flags & Flag.created != 0 ? Date(timeIntervalSince1970: try reader.double()) : nil
        let modified = flags & Flag.modified != 0 ? Date(timeIntervalSince1970: try reader.double()) : nil
        let warning = flags & Flag.warning != 0 ? try reader.string() : nil
        return FileNode(
            name: name,
            path: path,
            isDirectory: flags & Flag.directory != 0,
            isSymlink: flags & Flag.symlink != 0,
            logicalSizeBytes: logical,
            allocatedSizeBytes: allocated,
            measurementAccuracy: accuracy,
            fileIdentity: identity,
            createdAt: created,
            modifiedAt: modified,
            scanWarning: warning
        )
    }

    private static func accuracyCode(_ accuracy: MeasurementAccuracy) -> UInt8 {
        switch accuracy {
        case .exact: 0
        case .estimated: 1
        case .incomplete: 2
        }
    }

    private static func accuracy(_ code: UInt8) -> MeasurementAccuracy {
        switch code {
        case 0: .exact
        case 2: .incomplete
        default: .estimated
        }
    }

    // MARK: Byte helpers

    private struct Writer {
        var data = Data()

        mutating func bytes(_ bytes: [UInt8]) { data.append(contentsOf: bytes) }

        mutating func integer<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }

        mutating func double(_ value: Double) { integer(value.bitPattern) }

        mutating func string(_ value: String) {
            let utf8 = Array(value.utf8)
            integer(UInt32(utf8.count))
            data.append(contentsOf: utf8)
        }
    }

    private struct Reader {
        let data: Data
        var offset = 0

        var isAtEnd: Bool { offset == data.count }

        mutating func bytes(_ count: Int) throws -> [UInt8] {
            guard count >= 0, offset + count <= data.count else { throw Failure.truncated }
            defer { offset += count }
            let start = data.startIndex + offset
            return Array(data[start..<(start + count)])
        }

        mutating func integer<T: FixedWidthInteger>() throws -> T {
            let size = MemoryLayout<T>.size
            guard offset + size <= data.count else { throw Failure.truncated }
            defer { offset += size }
            let value = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: T.self) }
            return T(littleEndian: value)
        }

        mutating func double() throws -> Double { Double(bitPattern: try integer()) }

        mutating func string() throws -> String {
            let length: UInt32 = try integer()
            guard let value = String(bytes: try bytes(Int(length)), encoding: .utf8) else { throw Failure.truncated }
            return value
        }
    }
}
