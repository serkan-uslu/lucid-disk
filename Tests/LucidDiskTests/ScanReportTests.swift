import XCTest
@testable import LucidDiskCore

final class ScanReportTests: XCTestCase {
    private let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

    private func context(query: String = "", filters: [String] = [], saved: Bool = false, stopped: Bool = false) -> ScanReportContext {
        ScanReportContext(title: "Search results", query: query, filters: filters,
                          snapshotDate: saved ? timestamp.addingTimeInterval(-86_400) : nil,
                          wasStopped: stopped, generatedAt: timestamp)
    }

    private func fixture() -> (root: FileNode, folder: FileNode, nested: FileNode, match: FileNode, unrelated: FileNode) {
        let root = FileNode(name: "scan", path: "/scan", isDirectory: true, size: 12_000)
        let folder = FileNode(name: "Projects", path: "/scan/Projects", isDirectory: true, size: 8_000)
        let nested = FileNode(name: "Client", path: "/scan/Projects/Client", isDirectory: true, size: 6_000)
        let match = FileNode(name: "résumé.csv", path: "/scan/Projects/Client/résumé.csv", isDirectory: false,
                             logicalSizeBytes: 120, allocatedSizeBytes: 4_096, modifiedAt: timestamp)
        let sibling = FileNode(name: "private.txt", path: "/scan/Projects/Client/private.txt", isDirectory: false, size: 2_000)
        let unrelated = FileNode(name: "unrelated.bin", path: "/scan/unrelated.bin", isDirectory: false, size: 4_000)
        // Deliberately omit parent pointers: the report derives relationships
        // from the captured tree and does not depend on mutable navigation state.
        root.children = [unrelated, folder]
        folder.children = [nested]
        nested.children = [match, sibling]
        return (root, folder, nested, match, unrelated)
    }

    func testDeepMatchKeepsOnlyAncestorScaffoldingAndExactMatch() throws {
        let tree = fixture()
        let report = try ScanReport.build(root: tree.root, matches: [tree.match, tree.match], context: context(query: "résumé", filters: ["Files only"]))
        XCTAssertEqual(report.rows.map(\.path), [tree.root.path, tree.folder.path, tree.nested.path, tree.match.path])
        XCTAssertEqual(report.rows.map(\.depth), [0, 1, 2, 3])
        XCTAssertEqual(report.rows.map(\.parentPath), [nil, tree.root.path, tree.folder.path, tree.nested.path])
        XCTAssertEqual(report.rows.map(\.isMatch), [false, false, false, true])
        XCTAssertEqual(report.matchedCount, 1)
        XCTAssertEqual(report.ancestorCount, 3)
        XCTAssertFalse(report.rows.contains { $0.path == tree.unrelated.path || $0.name == "private.txt" })
        XCTAssertEqual(report.rows.last?.allocatedBytes, 4_096)
        XCTAssertEqual(report.rows.last?.logicalBytes, 120)
    }

    func testMatchedFolderDoesNotImplyItsDescendantsAreExported() throws {
        let tree = fixture()
        let report = try ScanReport.build(root: tree.root, matches: [tree.folder], context: context())
        XCTAssertEqual(report.rows.map(\.path), [tree.root.path, tree.folder.path])
        XCTAssertEqual(report.matchedCount, 1)
        XCTAssertEqual(report.ancestorCount, 1)
        let text = try XCTUnwrap(String(data: report.data(format: .text), encoding: .utf8))
        XCTAssertTrue(text.contains("A matched folder does not include unlisted descendants."))
        XCTAssertFalse(text.contains(tree.match.name))
    }

    func testFullSubtreeIncludesEveryRealRowInDeterministicHierarchy() throws {
        let tree = fixture()
        let report = try ScanReport.build(root: tree.root, matches: nil, context: context())
        XCTAssertEqual(report.rows.count, 6)
        XCTAssertEqual(report.matchedCount, 6)
        XCTAssertEqual(report.ancestorCount, 0)
        XCTAssertTrue(report.rows.allSatisfy(\.isMatch))
        XCTAssertFalse(report.isFiltered)
        XCTAssertEqual(report.rows.map(\.name), ["scan", "Projects", "Client", "résumé.csv", "private.txt", "unrelated.bin"])
        XCTAssertEqual(tree.root.children.map(\.name), ["unrelated.bin", "Projects"], "Export must not reorder the source tree")
    }

    func testAggregatesExpandToRealItemsAndDeduplicate() throws {
        let tree = fixture()
        let group = FileNode(name: "Other", path: tree.root.path, isDirectory: false)
        group.isAggregate = true
        group.aggregatedChildren = [tree.folder, tree.unrelated, tree.unrelated]
        let report = try ScanReport.build(root: tree.root, matches: [group, tree.folder], context: context())
        XCTAssertEqual(report.rows.map(\.path), [tree.root.path, tree.folder.path, tree.unrelated.path])
        XCTAssertEqual(report.matchedCount, 2)
        XCTAssertFalse(report.rows.contains { $0.name == "Other" })
        let groupTree = try ScanReport.build(root: group, matches: nil, context: context())
        XCTAssertEqual(groupTree.rows.count, 5)
        XCTAssertFalse(groupTree.rows.contains { $0.name == "Other" })
    }

    func testEmptyMatchesAndForeignItemsDoNotLeakRootOrSiblings() throws {
        let tree = fixture()
        let foreign = FileNode(name: "foreign", path: "/elsewhere/foreign", isDirectory: false)
        for matches in [[], [foreign]] {
            let report = try ScanReport.build(root: tree.root, matches: matches, context: context(query: "no match"))
            XCTAssertTrue(report.rows.isEmpty)
            XCTAssertEqual(report.rootPath, tree.root.path)
            XCTAssertEqual(report.matchedCount, 0)
            XCTAssertEqual(report.ancestorCount, 0)
            let csv = parseCSV(try XCTUnwrap(String(data: report.data(format: .csv), encoding: .utf8)))
            XCTAssertEqual(csv.count, 2, "An empty export still has its report metadata record")
        }
    }

    func testFullExportIsNotLimitedByPreview() throws {
        let root = FileNode(name: "many", path: "/many", isDirectory: true)
        for index in 0..<1_001 {
            root.children.append(FileNode(name: String(format: "item-%04d", index), path: String(format: "/many/item-%04d", index), isDirectory: false))
        }
        let report = try ScanReport.build(root: root, matches: nil, context: context())
        let preview = try report.preview(maximumRows: 3)
        XCTAssertTrue(preview.contains("Rows omitted from this preview: 999"))
        XCTAssertFalse(preview.contains("item-1000"))
        let text = try XCTUnwrap(String(data: report.data(format: .text), encoding: .utf8))
        XCTAssertTrue(text.contains("item-1000"))
        XCTAssertFalse(text.contains("Rows omitted from this preview"))
        let csv = parseCSV(try XCTUnwrap(String(data: report.data(format: .csv), encoding: .utf8)))
        XCTAssertEqual(csv.count, 1_004)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: report.data(format: .json)) as? [String: Any])
        XCTAssertEqual((json["rows"] as? [[String: Any]])?.count, 1_002)
    }

    func testJSONPreservesUnicodeQuotesNewlinesAndExplicitParentRelation() throws {
        let root = FileNode(name: "日本語", path: "/日本語", isDirectory: true)
        let name = "résumé, \"üç\"\nline.txt"
        let file = FileNode(name: name, path: root.path + "/" + name, isDirectory: false, isSymlink: true,
                            logicalSizeBytes: 5, allocatedSizeBytes: 0, measurementAccuracy: .exact, modifiedAt: timestamp)
        root.children = [file]
        let report = try ScanReport.build(root: root, matches: [file], context: context(query: "\"quoted\"\nsearch", filters: ["Türkçe", "日本語"]))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: report.data(format: .json)) as? [String: Any])
        XCTAssertEqual(json["schema"] as? String, "lucid-disk.scan-report")
        XCTAssertEqual(json["schemaVersion"] as? Int, 1)
        let rows = try XCTUnwrap(json["rows"] as? [[String: Any]])
        XCTAssertTrue(rows[0]["parentPath"] is NSNull)
        XCTAssertEqual(rows[1]["name"] as? String, name)
        XCTAssertEqual(rows[1]["parentPath"] as? String, root.path)
        XCTAssertEqual(rows[1]["kind"] as? String, "symlink")
        let source = try XCTUnwrap(json["context"] as? [String: Any])
        XCTAssertEqual(source["query"] as? String, "\"quoted\"\nsearch")
        let text = try XCTUnwrap(String(data: report.data(format: .text), encoding: .utf8))
        XCTAssertTrue(text.contains("\\nline.txt"))
        XCTAssertFalse(text.contains("\nline.txt"), "An embedded filename newline must not forge a new report line")
    }

    func testCSVQuotesAllFieldsAndNeutralizesFormulaPrefixesIncludingWhitespace() throws {
        let root = FileNode(name: "root", path: "/root", isDirectory: true)
        let names = ["=SUM(1,2)", "+cmd", "-42", "@formula", " \t=HYPERLINK(\"x\")", "\r\n=1", "üç, \"quoted\"\nfile"]
        root.children = names.map { FileNode(name: $0, path: "/root/" + $0, isDirectory: false, scanWarning: "=warning") }
        let report = try ScanReport.build(root: root, matches: nil, context: context(query: "+query", filters: ["@filter"]))
        let records = parseCSV(try XCTUnwrap(String(data: report.data(format: .csv), encoding: .utf8)))
        let headers = records[0]
        XCTAssertTrue(records.allSatisfy { $0.count == headers.count })
        let nameColumn = try XCTUnwrap(headers.firstIndex(of: "name"))
        let queryColumn = try XCTUnwrap(headers.firstIndex(of: "query"))
        let filterColumn = try XCTUnwrap(headers.firstIndex(of: "filters"))
        let warningColumn = try XCTUnwrap(headers.firstIndex(of: "warning"))
        XCTAssertEqual(records[1][queryColumn], "'+query")
        XCTAssertEqual(records[1][filterColumn], "'@filter")
        let itemRecords = Array(records.dropFirst(3))
        let exportedNames = Set(itemRecords.map { $0[nameColumn] })
        for name in names.dropLast() { XCTAssertTrue(exportedNames.contains("'" + name)) }
        XCTAssertTrue(exportedNames.contains(try XCTUnwrap(names.last)))
        XCTAssertTrue(itemRecords.allSatisfy { $0[warningColumn] == "'=warning" })
    }

    func testSavedStoppedAndIncompleteSourcesRemainExplicit() throws {
        let tree = fixture()
        tree.root.measurementAccuracy = .incomplete
        tree.match.scanWarning = "unreadable \"metadata\""
        let report = try ScanReport.build(root: tree.root, matches: [tree.match], context: context(saved: true, stopped: true))
        XCTAssertTrue(report.isPartial)
        let text = try report.preview()
        XCTAssertTrue(text.contains("historical snapshot"))
        XCTAssertTrue(text.contains("Stopped scan"))
        XCTAssertTrue(text.contains("unreadable \\\"metadata\\\""))
        let emptyPartial = try ScanReport.build(root: tree.root, matches: [], context: context())
        XCTAssertTrue(emptyPartial.isPartial, "An empty filtered export must retain the source scan's incomplete state")
    }

    func testBuildAndEncodingRespectTaskCancellation() async throws {
        let tree = fixture()
        let sourceContext = context()
        let report = try ScanReport.build(root: tree.root, matches: nil, context: sourceContext)
        let task = Task.detached { () throws -> Void in
            withUnsafeCurrentTask { $0?.cancel() }
            XCTAssertThrowsError(try ScanReport.build(root: tree.root, matches: nil, context: sourceContext)) { XCTAssertTrue($0 is CancellationError) }
            for format in ScanReportFormat.allCases {
                XCTAssertThrowsError(try report.data(format: format)) { XCTAssertTrue($0 is CancellationError) }
            }
            XCTAssertThrowsError(try report.preview()) { XCTAssertTrue($0 is CancellationError) }
        }
        try await task.value
    }

    /// Minimal RFC 4180 reader for assertions, including quoted line breaks.
    private func parseCSV(_ text: String) -> [[String]] {
        let characters = Array(text)
        var records: [[String]] = []
        var record: [String] = []
        var cell = ""
        var quoted = false
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                if quoted, index + 1 < characters.count, characters[index + 1] == "\"" { cell.append("\""); index += 1 }
                else { quoted.toggle() }
            } else if character == ",", !quoted {
                record.append(cell); cell = ""
            } else if !quoted, character == "\r\n" || character == "\n" || character == "\r" {
                record.append(cell); records.append(record); cell = ""; record = []
            } else {
                cell.append(character)
            }
            index += 1
        }
        if !cell.isEmpty || !record.isEmpty { record.append(cell); records.append(record) }
        return records
    }
}
