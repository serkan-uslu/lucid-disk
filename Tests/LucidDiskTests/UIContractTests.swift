import XCTest
@testable import LucidDiskCore

final class UIContractTests: XCTestCase {
    func testQuickLookItemKeepsSelectedURL() {
        let url = URL(fileURLWithPath: "/tmp/example.txt")
        let item = QuickLookItem(url: url)

        XCTAssertEqual(item.url, url)
        XCTAssertEqual(item.id, url.path)
    }

    func testTurkishCatalogCoversCriticalCleanupFlow() throws {
        let catalogURL = repositoryRoot()
            .appendingPathComponent("Sources/LucidDiskCore/Resources/Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(json["strings"] as? [String: Any])

        for key in [
            "Scan Startup Disk", "Lucid Insight", "Add to Review Queue",
            "Move to Trash", "Scan Warnings", "Quick Look", "About Lucid Disk",
            "How to Use", "Keyboard Shortcuts", "Privacy & Safety", "Scan Again", "Show in Trash",
            "Home", "View Details", "Close details", "Rescan this folder", "Search filters",
            "Move to Trash…", "OpenAI API", "Open Claude Desktop", "Open Codex",
            "Scan stopped. Only items measured so far are shown.",
            "Export & Review", "Export Results…", "Export Folder Tree…", "Review Cleanup",
            "Copy & Open Codex", "Copy & Open Claude", "Save report…", "Hide Sidebar",
            "Parent Folder", "Rescan Folder",
            "Scan could not be saved.", "Results are still available. Check free disk space and folder permissions, then retry.",
            "Retry Save", "Saving scan…", "Scan saved",
            "This directory was already visited through another path and was not counted again.",
            "Estimated file allocation", "Allocation estimate exceeds used space", "Used space", "Free space",
            "%@ free now", "%@ free now of %@", "Up to %@ more reclaimable", "Current used storage",
            "Physical free space updated %@. Reclaimable space is still included in used storage.",
            "Reclaimable space is an estimate of what macOS may free automatically. It is still included in used storage.",
            "Disk usage captured %@",
            "These disk totals were measured after the scan. The sidebar and Home refresh current free space separately.",
            "Up to %@ more may be reclaimed by macOS. This estimate is already included in used space.",
            "File allocations are estimates. Shared APFS blocks can make their sum exceed disk capacity; this is not reclaimable space.",
            "The measured file allocations exceed the space macOS reports as used. Shared APFS blocks and changes during scanning can contribute. This difference is not reclaimable space."
        ] {
            let entry = try XCTUnwrap(strings[key] as? [String: Any], key)
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any], key)
            XCTAssertNotNil(localizations["en"], key)
            XCTAssertNotNil(localizations["tr"], key)
        }
    }

    func testKeyboardAndVoiceOverContractsRemainDeclared() throws {
        let root = repositoryRoot().appendingPathComponent("Sources/LucidDiskCore")
        let content = try String(contentsOf: root.appendingPathComponent("Views/ContentView.swift"), encoding: .utf8)
        let chart = try String(contentsOf: root.appendingPathComponent("Sunburst/SunburstView.swift"), encoding: .utf8)

        XCTAssertTrue(content.contains(".onKeyPress(.space)"))
        XCTAssertTrue(chart.contains(".accessibilityChildren"))
        XCTAssertTrue(chart.contains(".accessibilityAction"))
        XCTAssertTrue(chart.contains("disk-usage-chart"))
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
