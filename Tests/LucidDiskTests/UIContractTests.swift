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
            "How to Use", "Keyboard Shortcuts", "Privacy & Safety", "Scan Again", "Show in Trash"
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
