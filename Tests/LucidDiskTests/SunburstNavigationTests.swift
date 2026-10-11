import AppKit
import XCTest
@testable import LucidDiskCore

@MainActor
final class SunburstNavigationTests: XCTestCase {
    func testParentCenterHighlightsAndNavigatesAfterResize() {
        let fixture = Fixture()
        defer { fixture.close() }
        fixture.view.canZoomOut = true

        for size in [NSSize(width: 280, height: 500), NSSize(width: 640, height: 360)] {
            fixture.resize(size)
            let center = SunburstGeometry(size: size).center
            fixture.move(to: center)
            XCTAssertEqual(fixture.centerHover, true)
            XCTAssertNil(fixture.hoveredNode)
            XCTAssertEqual(fixture.view.toolTip, String(localized: "Back to parent folder"))
            let count = fixture.parentActions
            fixture.click(at: center)
            XCTAssertEqual(fixture.parentActions, count + 1)
            XCTAssertTrue(fixture.activated.isEmpty)
            XCTAssertTrue(fixture.toggled.isEmpty)
        }
    }

    func testRootCenterHasNoNavigationActionOrHoverAffordance() {
        let fixture = Fixture()
        defer { fixture.close() }
        fixture.view.canZoomOut = true
        let center = SunburstGeometry(size: fixture.view.bounds.size).center
        fixture.move(to: center)
        XCTAssertEqual(fixture.centerHover, true)

        fixture.view.canZoomOut = false
        XCTAssertNil(fixture.view.toolTip, "Returning to the root must clear the parent tooltip before another mouse move")
        fixture.move(to: center)
        fixture.click(at: center)
        XCTAssertEqual(fixture.centerHover, false)
        XCTAssertNil(fixture.view.toolTip)
        XCTAssertEqual(fixture.parentActions, 0)
        XCTAssertTrue(fixture.activated.isEmpty)
    }

    func testLeavingCenterClearsHoverAndKeepsWedgeActions() {
        let fixture = Fixture()
        defer { fixture.close() }
        fixture.view.canZoomOut = true
        let geometry = SunburstGeometry(size: fixture.view.bounds.size, ringCount: 1)
        fixture.move(to: geometry.center)
        XCTAssertEqual(fixture.centerHover, true)

        let radius = geometry.centerRadius + geometry.ringWidth / 2
        let wedgePoint = CGPoint(x: geometry.center.x + radius / sqrt(2), y: geometry.center.y + radius / sqrt(2))
        fixture.move(to: wedgePoint)
        XCTAssertEqual(fixture.centerHover, false)
        XCTAssertEqual(fixture.hoveredNode, fixture.node.id)
        XCTAssertNil(fixture.view.toolTip)
        fixture.click(at: wedgePoint)
        fixture.click(at: wedgePoint, modifiers: .command)
        XCTAssertEqual(fixture.activated, [fixture.node.id])
        XCTAssertEqual(fixture.toggled, [fixture.node.id])
        XCTAssertEqual(fixture.parentActions, 0)

        fixture.move(to: geometry.center)
        fixture.view.mouseExited(with: fixture.event(.mouseMoved, at: .zero))
        XCTAssertEqual(fixture.centerHover, false)
        XCTAssertNil(fixture.hoveredNode)
        XCTAssertNil(fixture.view.toolTip)
    }

    /// Direct native events in an unordered window never interrupt an active scan.
    @MainActor
    private final class Fixture {
        let window: NSWindow
        let view = ChartMouseView()
        let node = FileNode(name: "Folder", path: "/tmp/folder", isDirectory: true, size: 100)
        var centerHover: Bool?
        var hoveredNode: UUID?
        var parentActions = 0
        var activated: [UUID] = []
        var toggled: [UUID] = []

        init() {
            _ = NSApplication.shared
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
                              styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = view
            view.wedges = [Wedge(node: node, level: 1, startDegrees: 0, endDegrees: 90, colorSeed: "folder")]
            view.onCenterHover = { [weak self] in self?.centerHover = $0 }
            view.onHover = { [weak self] in self?.hoveredNode = $0 }
            view.onZoomOut = { [weak self] in self?.parentActions += 1 }
            view.onActivate = { [weak self] in self?.activated.append($0.id) }
            view.onToggle = { [weak self] in self?.toggled.append($0.id) }
        }

        func resize(_ size: NSSize) {
            window.setContentSize(size)
            view.setFrameSize(size)
        }

        func event(_ type: NSEvent.EventType, at point: CGPoint, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil), modifierFlags: modifiers,
                              timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                              context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }

        func move(to point: CGPoint) { view.mouseMoved(with: event(.mouseMoved, at: point)) }

        func click(at point: CGPoint, modifiers: NSEvent.ModifierFlags = []) {
            view.mouseDown(with: event(.leftMouseDown, at: point, modifiers: modifiers))
        }

        func close() {
            XCTAssertFalse(window.isVisible)
            window.close()
            NSCursor.arrow.set()
        }
    }
}
