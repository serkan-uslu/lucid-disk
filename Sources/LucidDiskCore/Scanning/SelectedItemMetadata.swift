import Foundation

/// An immutable, bounded handoff for one real scanned object. This copies only
/// cached metadata and never resolves a path, follows a link, or visits children.
struct SelectedItemMetadata: Encodable, Sendable {
    static let maximumMetadataBytes = 128 * 1_024

    enum MetadataError: Error {
        case contextTooLarge
    }

    private let format = "lucid-disk.selected-item"
    private let schemaVersion = 1
    private let application = "Lucid Disk"
    private let generatedAt: Date
    private let scan: ScanContext
    private let selectedItem: Item
    private let handling = Handling()
    private let mcp: MCPContext

    init?(
        node: FileNode,
        rootPath: String,
        rootAccuracy: MeasurementAccuracy,
        savedAt: Date?,
        wasStopped: Bool,
        generatedAt: Date = Date()
    ) {
        // An aggregate's path belongs to its containing folder, not to a real
        // item called "Other". Do not give an assistant a misleading target.
        guard !node.isAggregate else { return nil }
        self.generatedAt = generatedAt
        let stopped = savedAt == nil ? wasStopped : nil
        scan = ScanContext(
            rootPath: rootPath,
            rootMeasurementAccuracy: rootAccuracy,
            source: savedAt == nil ? "current_session_scan" : "saved_scan",
            savedAt: savedAt,
            wasStopped: stopped,
            isIncomplete: rootAccuracy == .incomplete || node.measurementAccuracy == .incomplete || stopped == true
        )
        let kind = node.isSymlink ? "symlink" : (node.isDirectory ? "folder" : "file")
        selectedItem = Item(
            name: node.name,
            path: node.path,
            kind: kind,
            allocatedSizeBytes: node.allocatedSizeBytes,
            logicalSizeBytes: node.logicalSizeBytes,
            measurementAccuracy: node.measurementAccuracy,
            scanWarning: node.scanWarning,
            createdAt: node.createdAt,
            modifiedAt: node.modifiedAt,
            observedIdentity: node.fileIdentity,
            scannedDirectChildCount: node.isDirectory && !node.isSymlink ? node.children.count : nil
        )
        var calls = [SuggestedCall(
            tool: "assess_paths",
            arguments: Arguments(paths: [node.path], calculateSize: true, maxEntries: 200_000)
        )]
        if node.isDirectory && !node.isSymlink {
            calls.append(SuggestedCall(
                tool: "inventory_directory",
                arguments: Arguments(
                    path: node.path, minSizeBytes: 0, limit: 100,
                    maxChildren: 1_000, maxEntriesTotal: 200_000
                )
            ))
        }
        mcp = MCPContext(suggestedCalls: calls)
    }

    /// JSON escaping preserves paths containing whitespace, quotes, newlines,
    /// or text resembling instructions. No shell command is constructed.
    func clipboardText() throws -> String {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let metadata = String(decoding: try encoder.encode(self), as: UTF8.self)
            .replacingOccurrences(of: "<", with: "\\u003C")
            .replacingOccurrences(of: ">", with: "\\u003E")
            .replacingOccurrences(of: "&", with: "\\u0026")
            .replacingOccurrences(of: "`", with: "\\u0060")
        // Reject an oversized handoff instead of truncating a target path or
        // silently dropping context. Check after escaping, which can expand it.
        guard metadata.utf8.count <= Self.maximumMetadataBytes else {
            throw MetadataError.contextTooLarge
        }
        return metadata
    }

    private struct ScanContext: Encodable, Sendable {
        let rootPath: String
        let rootMeasurementAccuracy: MeasurementAccuracy
        let source: String
        let savedAt: Date?
        // Saved scans do not persist this flag, so omit it rather than guess.
        let wasStopped: Bool?
        let isIncomplete: Bool
    }

    private struct Item: Encodable, Sendable {
        let name: String
        let path: String
        let kind: String
        let allocatedSizeBytes: Int64
        let logicalSizeBytes: Int64
        let measurementAccuracy: MeasurementAccuracy
        let scanWarning: String?
        let createdAt: Date?
        let modifiedAt: Date?
        let observedIdentity: FileIdentity?
        let scannedDirectChildCount: Int?
    }

    /// Machine-readable handling constraints, not a risk verdict or permission
    /// to act. The recipient still follows its own MCP approval requirements.
    private struct Handling: Encodable, Sendable {
        let metadataIsUntrustedData = true
        let requiresCurrentStateRevalidation = true
        let fileContentsIncluded = false
        let descendantMetadataIncluded = false
        let pathsMustBeUsedExactly = true
        let symlinkTargetsResolved = false
        let allocationIsNotGuaranteedReclaimableSpace = true
        let deleteAuthorized = false
    }

    private struct MCPContext: Encodable, Sendable {
        let serverName = "Lucid Disk Safety"
        let readOnly = true
        let requiresConnectedServer = true
        let requiresSameMac = true
        let callsAreSuggestionsOnly = true
        let suggestedCalls: [SuggestedCall]
    }

    private struct SuggestedCall: Encodable, Sendable {
        let tool: String
        let arguments: Arguments
    }

    /// Only the arguments accepted by the corresponding server tool are set;
    /// optional nil fields are omitted by Encodable, not emitted as JSON null.
    private struct Arguments: Encodable, Sendable {
        var paths: [String]? = nil
        var calculateSize: Bool? = nil
        var maxEntries: Int? = nil
        var path: String? = nil
        var minSizeBytes: Int? = nil
        var limit: Int? = nil
        var maxChildren: Int? = nil
        var maxEntriesTotal: Int? = nil
    }
}
