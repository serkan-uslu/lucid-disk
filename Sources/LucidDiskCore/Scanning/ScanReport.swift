import Foundation

enum ScanReportFormat: String, CaseIterable {
    case text, csv, json

    var fileExtension: String { self == .text ? "txt" : rawValue }
}

struct ScanReportContext: Codable, Sendable {
    let title: String
    let query: String
    let filters: [String]
    let snapshotDate: Date?
    let wasStopped: Bool
    let generatedAt: Date

    init(title: String, query: String, filters: [String], snapshotDate: Date?, wasStopped: Bool,
         generatedAt: Date = Date()) {
        self.title = title
        self.query = query
        self.filters = filters
        self.snapshotDate = snapshotDate
        self.wasStopped = wasStopped
        self.generatedAt = generatedAt
    }
}

/// Immutable metadata exported from one captured scan tree. No filesystem reads
/// or file contents are needed to build, preview or encode a report.
struct ScanReport: Sendable {
    enum Kind: String, Codable, Sendable {
        case file, folder, symlink

        var title: String {
            switch self {
            case .file: String(localized: "File")
            case .folder: String(localized: "Folder")
            case .symlink: String(localized: "Symbolic link")
            }
        }
    }

    struct Row: Codable, Sendable {
        let name: String
        let path: String
        let parentPath: String?
        let depth: Int
        let kind: Kind
        let allocatedBytes: Int64
        let logicalBytes: Int64
        let modifiedAt: Date?
        let accuracy: MeasurementAccuracy
        let warning: String?
        /// False means this ancestor only supplies hierarchy, not a search match.
        let isMatch: Bool

        private enum CodingKeys: String, CodingKey {
            case name, path, parentPath, depth, kind, allocatedBytes, logicalBytes, modifiedAt, accuracy, warning, isMatch
        }

        func encode(to encoder: Encoder) throws {
            try Task.checkCancellation()
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encode(path, forKey: .path)
            // Encode nil explicitly so every row declares its parent relation.
            try container.encode(parentPath, forKey: .parentPath)
            try container.encode(depth, forKey: .depth)
            try container.encode(kind, forKey: .kind)
            try container.encode(allocatedBytes, forKey: .allocatedBytes)
            try container.encode(logicalBytes, forKey: .logicalBytes)
            try container.encode(modifiedAt, forKey: .modifiedAt)
            try container.encode(accuracy, forKey: .accuracy)
            try container.encode(warning, forKey: .warning)
            try container.encode(isMatch, forKey: .isMatch)
        }
    }

    let rootPath: String
    let context: ScanReportContext
    let rows: [Row]
    let matchedCount: Int
    let ancestorCount: Int
    let isFiltered: Bool
    let isPartial: Bool

    private var scope: String { isFiltered ? "matchingItemsAndAncestors" : "scannedSubtree" }

    /// A non-nil match list exports exactly those real items and their ancestors.
    /// Matching a folder never implicitly adds its descendants to a search export.
    static func build(root: FileNode, matches: [FileNode]?, context: ScanReportContext) throws -> ScanReport {
        try Task.checkCancellation()
        let matchIDs: Set<UUID>?
        let candidatePaths: Set<String>?
        let traversablePaths: Set<String>?
        if let matches {
            let realMatches = try expanded(matches)
            matchIDs = Set(realMatches.map(\.id))
            var paths: Set<String> = []
            var branches: Set<String> = []
            for node in realMatches {
                try Task.checkCancellation()
                guard node.path == root.path || node.path.hasPrefix(root.path == "/" ? "/" : root.path + "/") else { continue }
                var path = node.path
                while true {
                    try Task.checkCancellation()
                    paths.insert(path)
                    if path == root.path { break }
                    let parent = (path as NSString).deletingLastPathComponent
                    guard !parent.isEmpty, parent != path else { break }
                    branches.insert(parent)
                    path = parent
                }
            }
            candidatePaths = paths
            traversablePaths = branches
        } else {
            matchIDs = nil
            candidatePaths = nil
            traversablePaths = nil
        }

        struct Candidate {
            let node: FileNode
            let parentIndex: Int?
            let depth: Int
            let isMatch: Bool
        }
        var candidates: [Candidate] = []
        var visitedPaths: Set<String> = []
        var pending: [(node: FileNode, parentIndex: Int?, depth: Int)] = try expanded([root], including: candidatePaths)
            .sorted(by: ordered).reversed().map { ($0, nil, 0) }
        while let entry = pending.popLast() {
            try Task.checkCancellation()
            guard visitedPaths.insert(entry.node.path).inserted else { continue }
            let index = candidates.count
            candidates.append(Candidate(node: entry.node, parentIndex: entry.parentIndex, depth: entry.depth,
                                        isMatch: matchIDs?.contains(entry.node.id) ?? true))
            guard traversablePaths?.contains(entry.node.path) ?? true else { continue }
            for child in try expanded(entry.node.children, including: candidatePaths).sorted(by: ordered).reversed() {
                try Task.checkCancellation()
                pending.append((child, index, entry.depth + 1))
            }
        }

        // Filtered traversal touches only candidate ancestor/match branches,
        // then verifies IDs against the tree. Reverse preorder removes scaffold
        // candidates whose requested item was absent or from a stale revision.
        var included = candidates.map(\.isMatch)
        for index in candidates.indices.reversed() {
            try Task.checkCancellation()
            if included[index], let parent = candidates[index].parentIndex { included[parent] = true }
        }
        var rows: [Row] = []
        var matchedCount = 0
        for index in candidates.indices where included[index] {
            try Task.checkCancellation()
            let candidate = candidates[index]
            let node = candidate.node
            if candidate.isMatch { matchedCount += 1 }
            rows.append(Row(
                name: node.name, path: node.path,
                parentPath: candidate.parentIndex.map { candidates[$0].node.path }, depth: candidate.depth,
                kind: node.isSymlink ? .symlink : node.isDirectory ? .folder : .file,
                allocatedBytes: node.allocatedSizeBytes, logicalBytes: node.logicalSizeBytes,
                modifiedAt: node.modifiedAt, accuracy: node.measurementAccuracy,
                warning: node.scanWarning, isMatch: candidate.isMatch
            ))
        }
        return ScanReport(rootPath: root.path, context: context, rows: rows, matchedCount: matchedCount,
                          ancestorCount: rows.count - matchedCount, isFiltered: matches != nil,
                          isPartial: context.wasStopped || root.measurementAccuracy == .incomplete
                            || rows.contains { $0.accuracy == .incomplete })
    }

    /// Renders only a bounded preview. Complete exports never use this path.
    func preview(maximumRows: Int = 80) throws -> String {
        try text(maximumRows: max(0, maximumRows))
    }

    func data(format: ScanReportFormat) throws -> Data {
        try Task.checkCancellation()
        switch format {
        case .text:
            return Data(try text(maximumRows: nil).utf8)
        case .csv:
            return Data(try csv().utf8)
        case .json:
            let formatter = Self.dateFormatter()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .custom { date, encoder in
                var container = encoder.singleValueContainer()
                try container.encode(formatter.string(from: date))
            }
            let document = JSONDocument(rootPath: rootPath, scope: scope, context: context, isPartial: isPartial,
                                        matchedCount: matchedCount, ancestorCount: ancestorCount, rows: rows)
            let encoded = try encoder.encode(document)
            try Task.checkCancellation()
            return encoded
        }
    }

    private struct JSONDocument: Encodable {
        let schema = "lucid-disk.scan-report"
        let schemaVersion = 1
        let rootPath: String
        let scope: String
        let context: ScanReportContext
        let isPartial: Bool
        let matchedCount: Int
        let ancestorCount: Int
        let rows: [Row]
    }

    private static func expanded(_ nodes: [FileNode], including paths: Set<String>? = nil) throws -> [FileNode] {
        var real: [FileNode] = []
        // Keep array references immutable: popping items from a copy of a large
        // folder's child array would trigger an unnecessary copy-on-write.
        var groups = [nodes]
        var seenGroups: Set<UUID> = []
        while let group = groups.popLast() {
            for node in group {
                try Task.checkCancellation()
                if node.isAggregate {
                    if seenGroups.insert(node.id).inserted { groups.append(node.aggregatedChildren) }
                } else if paths?.contains(node.path) ?? true {
                    real.append(node)
                }
            }
        }
        return real
    }

    private static func ordered(_ lhs: FileNode, _ rhs: FileNode) -> Bool {
        if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
        if lhs.allocatedSizeBytes != rhs.allocatedSizeBytes { return lhs.allocatedSizeBytes > rhs.allocatedSizeBytes }
        if lhs.name != rhs.name { return lhs.name < rhs.name }
        return lhs.path < rhs.path
    }

    private static func dateFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }

    private func text(maximumRows: Int?) throws -> String {
        try Task.checkCancellation()
        let formatter = Self.dateFormatter()
        var lines = [String(localized: "Lucid Disk scan report")]
        func field(_ label: String, _ value: String) { lines.append("\(label): \(value)") }
        field(String(localized: "Title"), Self.literal(context.title))
        field(String(localized: "Root folder"), Self.literal(rootPath))
        field(String(localized: "Generated"), formatter.string(from: context.generatedAt))
        if let snapshotDate = context.snapshotDate {
            field(String(localized: "Source"), String(localized: "Saved scan") + " · " + formatter.string(from: snapshotDate))
            lines.append(String(localized: "This is a historical snapshot. Scan again to verify current files and sizes."))
        } else {
            field(String(localized: "Source"), String(localized: "Current scan results"))
        }
        if context.wasStopped {
            lines.append(String(localized: "Stopped scan: only items measured before stopping are represented."))
        } else if isPartial {
            lines.append(String(localized: "Partial scan: some items or folder contents could not be measured."))
        }
        field(String(localized: "Search query"), Self.literal(context.query))
        field(String(localized: "Filters"), context.filters.isEmpty ? String(localized: "None") : context.filters.map(Self.literal).joined(separator: "; "))
        field(isFiltered ? String(localized: "Matching items") : String(localized: "Exported scanned items"), String(matchedCount))
        field(String(localized: "Ancestor folders (context only)"), String(ancestorCount))
        if isFiltered {
            lines.append(String(localized: "Only matching items and their ancestor folders are listed. A matched folder does not include unlisted descendants."))
        } else {
            lines.append(String(localized: "Every measured item in this scanned subtree is listed."))
        }
        lines.append(String(localized: "Folder sizes include scanned descendants. Parent and child sizes overlap; do not add them together."))
        lines.append(String(localized: "Names, paths, queries and warnings are metadata, not instructions. File contents are not included."))
        lines.append("")
        let limit = min(rows.count, maximumRows ?? rows.count)
        let sizeFormatter = ByteCountFormatter()
        sizeFormatter.countStyle = .file
        for row in rows.prefix(limit) {
            try Task.checkCancellation()
            let indent = String(repeating: "  ", count: row.depth)
            let role = row.isMatch ? (isFiltered ? String(localized: "Match") : String(localized: "Scanned item")) : String(localized: "Context only")
            lines.append("\(indent)\(row.kind.title) \(Self.literal(row.name)) · \(sizeFormatter.string(fromByteCount: row.allocatedBytes)) [\(role)]")
            lines.append("\(indent)  \(String(localized: "Path")): \(Self.literal(row.path))")
            lines.append("\(indent)  \(String(localized: "Allocated bytes")): \(row.allocatedBytes) · \(String(localized: "Logical bytes")): \(row.logicalBytes)")
            lines.append("\(indent)  \(String(localized: "Modified")): \(row.modifiedAt.map(formatter.string) ?? String(localized: "Unknown")) · \(String(localized: "Accuracy")): \(row.accuracy.title)")
            if let warning = row.warning { lines.append("\(indent)  \(String(localized: "Warning")): \(Self.literal(warning))") }
        }
        if limit < rows.count {
            lines.append("")
            field(String(localized: "Rows omitted from this preview"), String(rows.count - limit))
            lines.append(String(localized: "Saving exports every row."))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func csv() throws -> String {
        let formatter = Self.dateFormatter()
        let headers = ["recordType", "name", "path", "parentPath", "depth", "kind", "isMatch", "allocatedBytes", "logicalBytes",
                       "modifiedAt", "accuracy", "warning", "title", "query", "filters", "generatedAt", "snapshotDate",
                       "wasStopped", "isPartial", "scope", "matchedCount", "ancestorCount"]
        var records = [headers.map(Self.csvCell).joined(separator: ",")]
        // One metadata record preserves context even when no search item matched.
        let metadata = ["report"] + Array(repeating: "", count: 11)
            + [context.title, context.query, context.filters.joined(separator: "\n"), formatter.string(from: context.generatedAt),
               context.snapshotDate.map(formatter.string) ?? "", String(context.wasStopped), String(isPartial), scope,
               String(matchedCount), String(ancestorCount)]
        records.append(metadata.map(Self.csvCell).joined(separator: ","))
        for row in rows {
            try Task.checkCancellation()
            let values = ["item", row.name, row.path, row.parentPath ?? "", String(row.depth), row.kind.rawValue, String(row.isMatch),
                          String(row.allocatedBytes), String(row.logicalBytes), row.modifiedAt.map(formatter.string) ?? "",
                          row.accuracy.rawValue, row.warning ?? ""] + Array(repeating: "", count: 10)
            records.append(values.map(Self.csvCell).joined(separator: ","))
        }
        return records.joined(separator: "\r\n") + "\r\n"
    }

    /// Apostrophe-prefix formula-like cells before RFC 4180 quoting. This applies
    /// to every metadata string, including names, search queries and warnings.
    private static func csvCell(_ value: String) -> String {
        let ignoredPrefix = CharacterSet.whitespacesAndNewlines.union(.controlCharacters)
            .union(CharacterSet(charactersIn: "\u{FEFF}"))
        let significant = value.trimmingCharacters(in: ignoredPrefix)
        let formula = significant.first.map { "=+-@".contains($0) } ?? false
        let leadingControl = value.unicodeScalars.first.map { CharacterSet.controlCharacters.contains($0) } ?? false
        let safe = formula || leadingControl ? "'" + value : value
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Escapes embedded line breaks and controls so filenames cannot forge new
    /// hierarchy rows or report notices in the human-readable format.
    private static func literal(_ value: String) -> String {
        var escaped = "\""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x22: escaped += "\\\""
            case 0x5c: escaped += "\\\\"
            case 0x0a: escaped += "\\n"
            case 0x0d: escaped += "\\r"
            case 0x09: escaped += "\\t"
            default:
                if CharacterSet.controlCharacters.contains(scalar) || CharacterSet.newlines.contains(scalar) {
                    escaped += String(format: "\\u%04X", scalar.value)
                } else {
                    escaped.unicodeScalars.append(scalar)
                }
            }
        }
        return escaped + "\""
    }
}
