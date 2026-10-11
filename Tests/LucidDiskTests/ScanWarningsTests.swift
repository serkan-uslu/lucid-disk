import AppKit
import SwiftUI
import XCTest
@testable import LucidDiskCore

final class ScanWarningsTests: XCTestCase {
    func testAll1073WarningsRemainReachableByFullPathAndMessage() {
        let warnings = fixtureWarnings()
        let presentation = makePresentation(warnings: warnings)
        XCTAssertEqual(presentation.entries.count, 1_073)
        XCTAssertEqual(presentation.matching("  \n "), presentation.entries)
        XCTAssertEqual(presentation.matching(warnings[1_072].path).map(\.id), [1_072])
        XCTAssertEqual(presentation.matching("BOUNDARY MARKER").map(\.id), [1_072])
        XCTAssertEqual(presentation.matching("Folder-1068/").first?.path, warnings[1_068].path)
        XCTAssertEqual(presentation.entries.map(\.path), warnings.map(\.path))
        XCTAssertEqual(presentation.entries.map(\.message), warnings.map(\.message))
    }

    func testRepeatedPathsAndIdenticalWarningsKeepTheirOriginalIdentities() {
        let presentation = makePresentation(warnings: fixtureWarnings())
        XCTAssertEqual(Set(presentation.entries.map(\.id)).count, 1_073)
        XCTAssertEqual(presentation.matching("shared-path").map(\.id), [0, 1, 2])
        XCTAssertEqual(presentation.matching("repeated warning").map(\.id), [0, 2])
        XCTAssertEqual(presentation.entries[0].path, presentation.entries[2].path)
        XCTAssertEqual(presentation.entries[0].message, presentation.entries[2].message)
        XCTAssertNotEqual(presentation.entries[0].id, presentation.entries[2].id)
    }

    func testEmptyAndNoMatchResultsDoNotReplaceTheCapturedWarnings() {
        let empty = makePresentation(warnings: [])
        XCTAssertTrue(empty.matching("").isEmpty)
        XCTAssertTrue(empty.matching("anything").isEmpty)
        let presentation = makePresentation(warnings: fixtureWarnings())
        XCTAssertTrue(presentation.matching("no-such-warning-unique-query").isEmpty)
        XCTAssertEqual(presentation.matching("").count, 1_073)
    }

    func testCapturedContentAndCompletenessAreIndependentOfLaterChanges() {
        let root = FileNode(name: "Scan", path: "/fixture/original", isDirectory: true, measurementAccuracy: .incomplete)
        var warnings = [ScanWarning(path: "/fixture/original/child", message: "Captured warning")]
        let presentation = ScanWarningsPresentation(root: root, warnings: warnings, wasStopped: false, savedAt: nil)
        warnings.removeAll()
        root.measurementAccuracy = .estimated
        root.scanWarning = nil
        XCTAssertEqual(presentation.rootPath, "/fixture/original")
        XCTAssertEqual(presentation.entries.map(\.message), ["Captured warning"])
        XCTAssertEqual(presentation.status, .partial)
        XCTAssertNil(presentation.savedAt)
    }

    func testStoppedAndSavedContextDoNotInventAHistoricalStoppedFlag() {
        let root = FileNode(name: "Scan", path: "/fixture", isDirectory: true, measurementAccuracy: .incomplete)
        let warnings = [ScanWarning(path: root.path, message: "Original saved message")]
        let stopped = ScanWarningsPresentation(root: root, warnings: warnings, wasStopped: true, savedAt: nil)
        XCTAssertEqual(stopped.status, .stopped)
        let date = Date(timeIntervalSince1970: 123)
        let saved = ScanWarningsPresentation(root: root, warnings: warnings, wasStopped: true, savedAt: date)
        XCTAssertEqual(saved.status, .partial)
        XCTAssertEqual(saved.savedAt, date)
        XCTAssertEqual(saved.entries[0].message, "Original saved message")
        root.measurementAccuracy = .estimated
        XCTAssertNil(ScanWarningsPresentation(root: root, warnings: warnings, wasStopped: true, savedAt: date).status)
    }

    @MainActor
    func testCopyUsesTheExactFullPathAndAnInjectedPrivatePasteboard() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let path = "/fixture/İzinler/very long folder/line\nbreak/emoji-🗂/trailing space "
        XCTAssertTrue(ScanWarningClipboard.copy(path, to: pasteboard))
        XCTAssertEqual(pasteboard.string(forType: .string), path)
    }

    @MainActor
    func testNativeListVirtualizes1073RowsAndCanReachTheLastWarningOffscreen() async throws {
        let (window, host) = makeWindow(presentation: makePresentation(warnings: fixtureWarnings()))
        defer { window.close() }
        try await settle(host)
        let table = try XCTUnwrap(descendants(host).compactMap { $0 as? NSTableView }.first)
        XCTAssertEqual(table.numberOfRows, 1_073)
        XCTAssertLessThan(descendants(table).filter { $0 is NSTableRowView }.count, 100)
        table.scrollRowToVisible(1_072)
        try await settle(host)
        // The first scroll measures previously unseen, wrapping rows. Scroll once
        // more using those actual heights instead of the list's initial estimates.
        table.scrollRowToVisible(1_072)
        try await settle(host)
        XCTAssertNotNil(table.rowView(atRow: 1_072, makeIfNecessary: false))
        XCTAssertTrue(table.visibleRect.intersects(table.rect(ofRow: 1_072)),
                      "Visible \(table.visibleRect), final row \(table.rect(ofRow: 1_072))")
        XCTAssertEqual(host.bounds.size, NSSize(width: 740, height: 590))
        XCTAssertFalse(window.isVisible)
    }

    @MainActor
    func testNativeFilteredListRetainsEveryRepeatedPathOffscreen() async throws {
        let (window, host) = makeWindow(presentation: makePresentation(warnings: fixtureWarnings()), query: "shared-path")
        defer { window.close() }
        try await settle(host)
        let table = try XCTUnwrap(descendants(host).compactMap { $0 as? NSTableView }.first)
        XCTAssertEqual(table.numberOfRows, 3)
        XCTAssertFalse(window.isVisible)
    }

    private func makePresentation(warnings: [ScanWarning]) -> ScanWarningsPresentation {
        ScanWarningsPresentation(root: FileNode(name: "Fixture", path: "/fixture", isDirectory: true),
                                 warnings: warnings, wasStopped: false, savedAt: nil)
    }

    private func fixtureWarnings() -> [ScanWarning] {
        var warnings = (0..<1_073).map { ScanWarning(path: "/fixture/Folder-\($0)/item", message: "Warning \($0)") }
        warnings[0] = ScanWarning(path: "/fixture/shared-path", message: "Repeated warning")
        warnings[1] = ScanWarning(path: "/fixture/shared-path", message: "A second kind of warning")
        warnings[2] = warnings[0]
        warnings[1_072] = ScanWarning(path: "/fixture/very-long-location/with-many-parent-folders/\(String(repeating: "nested-folder/", count: 12))last-entry",
                                     message: "Intentional exclusion with a unique boundary marker")
        return warnings
    }

    @MainActor
    private func makeWindow(presentation: ScanWarningsPresentation, query: String = "") -> (NSWindow, NSHostingView<ScanWarningsSheet>) {
        _ = NSApplication.shared
        let size = NSSize(width: 740, height: 590)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: ScanWarningsSheet(presentation: presentation, query: query))
        host.sizingOptions = []
        window.contentView = host
        window.setContentSize(size)
        return (window, host)
    }

    @MainActor
    private func settle(_ host: NSView) async throws {
        for _ in 0..<8 {
            try await Task.sleep(for: .milliseconds(20))
            host.layoutSubtreeIfNeeded()
        }
    }

    @MainActor
    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
}
