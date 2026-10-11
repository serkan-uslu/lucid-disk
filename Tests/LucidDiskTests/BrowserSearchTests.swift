import XCTest
@testable import LucidDiskCore

final class BrowserSearchTests: XCTestCase {
    func testFiltersSearchNestedItemsWithoutANameAndRespectScope() throws {
        let root = FileNode(name: "root", path: "/root", isDirectory: true)
        let folder = FileNode(name: "project", path: "/root/project", isDirectory: true)
        let file = FileNode(name: "archive.ZIP", path: "/root/project/archive.ZIP", isDirectory: false, size: 200_000_000)
        let other = FileNode(name: "other.zip", path: "/root/other.zip", isDirectory: false, size: 300_000_000)
        root.children = [folder, other]
        folder.children = [file]
        var filters = BrowserSearchFilters(kind: .files, minimumBytes: 100_000_000, extensions: ".zip, dmg")
        let all = try BrowserContents.load(focused: folder, root: root, query: "", order: .size, filters: filters)
        XCTAssertEqual(all.nodes.map(\.id), [other.id, file.id])
        filters.scope = .folder
        let local = try BrowserContents.load(focused: folder, root: root, query: "", order: .size, filters: filters)
        XCTAssertEqual(local.nodes.map(\.id), [file.id])
        filters.minimumBytes = 1_000_000_000
        XCTAssertTrue(try BrowserContents.load(focused: folder, root: root, query: "", order: .size, filters: filters).nodes.isEmpty)
    }

    func testWordsMatchAcrossPathCaseAndAccents() throws {
        let root = FileNode(name: "root", path: "/root", isDirectory: true)
        let file = FileNode(name: "résumé.pdf", path: "/root/Client Projects/résumé.pdf", isDirectory: false)
        root.children = [file]
        XCTAssertEqual(try BrowserContents.load(focused: root, root: root, query: "RESUME client", order: .name).nodes.map(\.id), [file.id])
        XCTAssertTrue(try BrowserContents.load(focused: root, root: root, query: "resume missing", order: .name).nodes.isEmpty)
    }

    func testModifiedFilterExcludesUnknownDatesAndCombinesWithKind() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let recent = FileNode(name: "recent", path: "/recent", isDirectory: false, modifiedAt: now.addingTimeInterval(-86_400))
        let old = FileNode(name: "old", path: "/old", isDirectory: true, modifiedAt: now.addingTimeInterval(-400 * 86_400))
        let unknown = FileNode(name: "unknown", path: "/unknown", isDirectory: false)
        var filters = BrowserSearchFilters(modified: .week)
        XCTAssertTrue(filters.matches(recent, query: "", now: now))
        XCTAssertFalse(filters.matches(old, query: "", now: now))
        XCTAssertFalse(filters.matches(unknown, query: "", now: now))
        filters.modified = .olderYear
        filters.kind = .folders
        XCTAssertTrue(filters.matches(old, query: "", now: now))
        XCTAssertFalse(filters.matches(recent, query: "", now: now))
    }
}
