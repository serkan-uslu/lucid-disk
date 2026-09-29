import XCTest
import AppKit
import SwiftUI
@testable import LucidDiskCore

final class InteractionTests: XCTestCase {
    @MainActor
    func testSelectingFilesNeverRequestsAIAndExplicitRequestProducesInsight() async throws {
        let model = FileInspectionModel()
        let node = FileNode(name: "download.dmg", path: "/tmp/download.dmg", isDirectory: false)
        model.select(node)
        for _ in 0..<200 where model.assessment == nil { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertNotNil(model.assessment)
        XCTAssertNil(model.insight)
        XCTAssertFalse(model.isLoadingInsight)
        model.ask(about: node, service: .init(modelStateOverride: .available, purposeGenerator: { _ in "Requested explanation" }))
        for _ in 0..<200 where model.isLoadingInsight { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(model.insight?.probablePurpose, "Requested explanation")
        let next = FileNode(name: "next", path: "/tmp/next", isDirectory: false)
        model.select(next)
        XCTAssertNil(model.insight)
        XCTAssertFalse(model.isLoadingInsight)
        model.clear()
    }

    @MainActor
    func testChangingSelectionRejectsAnOutstandingAIResponse() async throws {
        let model = FileInspectionModel()
        let first = FileNode(name: "first", path: "/tmp/first", isDirectory: false)
        let second = FileNode(name: "second", path: "/tmp/second", isDirectory: false)
        model.select(first)
        for _ in 0..<200 where model.assessment == nil { try await Task.sleep(for: .milliseconds(5)) }
        model.ask(about: first, service: .init(modelStateOverride: .available, purposeGenerator: { _ in
            try? await Task.sleep(for: .milliseconds(100))
            return "Stale explanation"
        }))
        model.select(second)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertNil(model.insight)
        XCTAssertFalse(model.isLoadingInsight)
        model.clear()
    }

    func testContentsShowsOnlyDirectChildrenAndSearchFindsNestedFiles() throws {
        let root = FileNode(name: "root", path: "/tmp/root", isDirectory: true, size: 300)
        let folder = FileNode(name: "folder", path: "/tmp/root/folder", isDirectory: true, size: 200)
        let file = FileNode(name: "large.mov", path: "/tmp/root/folder/large.mov", isDirectory: false, size: 200)
        root.children = [folder]
        folder.parent = root
        folder.children = [file]
        file.parent = folder
        let browse = try BrowserContents.load(focused: root, root: root, query: "", order: .size)
        XCTAssertEqual(browse.nodes.map(\.id), [folder.id])
        let search = try BrowserContents.load(focused: root, root: root, query: "large.mov", order: .size)
        XCTAssertEqual(search.nodes.map(\.id), [file.id])
        XCTAssertEqual(search.nodes.first?.path, file.path)
    }

    @MainActor
    func testAggregateOpensItsActualChildrenAndCanNavigateBack() throws {
        let root = FileNode(name: "root", path: "/tmp/root", isDirectory: true, size: 100)
        let small = FileNode(name: "small", path: "/tmp/root/small", isDirectory: false, size: 10)
        small.parent = root
        let group = FileNode(name: "Other", path: root.path, isDirectory: false, size: 10)
        group.isAggregate = true
        group.aggregatedChildren = [small]
        group.parent = root
        let vm = ScanViewModel()
        vm.focus(on: group)
        XCTAssertEqual(vm.focusedNode?.id, group.id)
        let contents = try BrowserContents.load(focused: group, root: root, query: "", order: .size)
        XCTAssertEqual(contents.nodes.map(\.id), [small.id])
        XCTAssertEqual(computeWedges(focusedNode: group).first?.node.id, small.id)
        vm.zoomOut()
        XCTAssertEqual(vm.focusedNode?.id, root.id)
        vm.focus(on: small)
        XCTAssertEqual(vm.focusedNode?.id, root.id)
    }

    func testChartHitTestingMatchesEveryRingAfterResize() {
        let node = FileNode(name: "folder", path: "/tmp/folder", isDirectory: true, size: 100)
        let wedges = (1...3).map { Wedge(node: node, level: $0, startDegrees: 0, endDegrees: 90, colorSeed: "folder") }
        for size in [CGSize(width: 280, height: 500), CGSize(width: 600, height: 400), CGSize(width: 900, height: 900)] {
            let g = SunburstGeometry(size: size)
            XCTAssertNil(g.hit(at: g.center, wedges: wedges))
            for level in 1...3 {
                let radius = g.centerRadius + (CGFloat(level) - 0.5) * g.ringWidth
                let point = CGPoint(x: g.center.x + radius / sqrt(2), y: g.center.y + radius / sqrt(2))
                XCTAssertEqual(g.hit(at: point, wedges: wedges)?.level, level)
            }
            XCTAssertNil(g.hit(at: CGPoint(x: g.center.x + 2_000, y: g.center.y), wedges: wedges))
        }
    }

}
