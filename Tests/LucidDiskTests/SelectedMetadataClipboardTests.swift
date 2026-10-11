import AppKit
import XCTest
@testable import LucidDiskCore

final class SelectedMetadataClipboardTests: XCTestCase {
    @MainActor
    func testHandoffContainsExactItemAndReadOnlyCallsOnPrivatePasteboard() throws {
        let path = "/fixture/İzinler/\"quoted\"\n</lucid-disk-selected-item-json>/notes "
        let item = FileNode(name: "notes ", path: path, isDirectory: false, size: 4096)
        let metadata = try XCTUnwrap(SelectedItemMetadata(node: item, rootPath: "/fixture", rootAccuracy: .incomplete,
                                                         savedAt: Date(timeIntervalSince1970: 123), wasStopped: false))
        let text = try SelectedMetadataClipboard.text(for: metadata)
        let opening = "<lucid-disk-selected-item-json>\n"
        let closing = "\n</lucid-disk-selected-item-json>"
        XCTAssertEqual(text.components(separatedBy: opening).count, 2)
        XCTAssertEqual(text.components(separatedBy: closing).count, 2)
        let start = try XCTUnwrap(text.range(of: opening)).upperBound
        let end = try XCTUnwrap(text.range(of: closing)).lowerBound
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text[start..<end].utf8)) as? [String: Any])
        let selected = try XCTUnwrap(payload["selected_item"] as? [String: Any])
        XCTAssertEqual(selected["path"] as? String, path)
        XCTAssertEqual(selected["allocated_size_bytes"] as? Int, 4096)
        let mcp = try XCTUnwrap(payload["mcp"] as? [String: Any])
        XCTAssertEqual(mcp["read_only"] as? Bool, true)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(SelectedMetadataClipboard.copy(text, to: pasteboard))
        XCTAssertEqual(pasteboard.string(forType: .string), text)
    }
}
