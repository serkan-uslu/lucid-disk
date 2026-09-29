import SwiftUI
import XCTest
@testable import LucidDiskCore

@MainActor
final class ExtensionTests: XCTestCase {
    override func tearDown() async throws {
        LucidDiskExtensions.shared.reset()
    }

    func testCommunityEditionInstallsNothing() {
        let extensions = LucidDiskExtensions()
        XCTAssertEqual(extensions.edition, .community)
        XCTAssertEqual(extensions.edition.displayName, "Lucid Disk")
        XCTAssertTrue(extensions.sidebarSections.isEmpty)
        XCTAssertTrue(extensions.inspectorSections.isEmpty)
        XCTAssertTrue(extensions.settingsTabs.isEmpty)
    }

    func testExtensionInstallsContributionsAndReplacesById() {
        let extensions = LucidDiskExtensions()
        extensions.install(SampleEdition())

        XCTAssertEqual(extensions.edition.displayName, "Lucid Disk Sample")
        XCTAssertEqual(extensions.sidebarSections.map(\.id), ["sample.sidebar"])
        XCTAssertEqual(extensions.inspectorSections.map(\.id), ["sample.inspector"])
        XCTAssertEqual(extensions.settingsTabs.map(\.title), ["Sample"])

        extensions.addSettingsTab(SettingsTabContribution(id: "sample.settings", title: "Renamed", systemImage: "star") {
            AnyView(EmptyView())
        })
        XCTAssertEqual(extensions.settingsTabs.map(\.title), ["Renamed"])

        extensions.remove(id: "sample.sidebar")
        XCTAssertTrue(extensions.sidebarSections.isEmpty)
        extensions.reset()
        XCTAssertEqual(extensions.edition, .community)
        XCTAssertTrue(extensions.settingsTabs.isEmpty)
    }

    func testContextCanQueueButNeverQueuesSyntheticGroups() {
        let viewModel = ScanViewModel()
        let context = viewModel.extensionContext
        let parent = FileNode(name: "Downloads", path: "/Users/example/Downloads", isDirectory: true)
        let file = FileNode(name: "a.zip", path: parent.path + "/a.zip", isDirectory: false, size: 10)
        file.parent = parent
        let group = FileNode(name: "Other", path: parent.path, isDirectory: false, size: 5)
        group.isAggregate = true

        XCTAssertTrue(context.addToReview(file))
        XCTAssertFalse(context.addToReview(file), "Queuing twice must not toggle the item back out")
        XCTAssertFalse(context.addToReview(group))
        XCTAssertEqual(context.reviewQueue.map(\.id), [file.id])
        XCTAssertNil(viewModel.pendingDeletion, "Queuing never starts a Trash confirmation")
    }

    func testContextForwardsViewModelChanges() {
        let viewModel = ScanViewModel()
        let context = viewModel.extensionContext
        var changes = 0
        let token = context.objectWillChange.sink { changes += 1 }
        viewModel.selectedNode = FileNode(name: "x", path: "/tmp/x", isDirectory: false)
        XCTAssertGreaterThan(changes, 0)
        token.cancel()
    }
}

private struct SampleEdition: LucidDiskExtension {
    func install(into extensions: LucidDiskExtensions) {
        extensions.setEdition(EditionInfo(badge: "Sample"))
        extensions.addSidebarSection(SidebarContribution(id: "sample.sidebar", title: "Sample") { _ in
            AnyView(Text("Sidebar"))
        })
        extensions.addInspectorSection(InspectorContribution(id: "sample.inspector") { node, _ in
            AnyView(Text(node.name))
        })
        extensions.addSettingsTab(SettingsTabContribution(id: "sample.settings", title: "Sample", systemImage: "star") {
            AnyView(Text("Settings"))
        })
    }
}
