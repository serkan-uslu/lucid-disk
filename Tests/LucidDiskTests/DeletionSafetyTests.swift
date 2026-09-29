import XCTest
@testable import LucidDiskCore

final class DeletionSafetyTests: XCTestCase {
    private let home = "/Users/example"

    func testSystemPathIsProtected() {
        let assessment = DeletionSafety.assess(path: "/System/Library", homePath: home)
        XCTAssertEqual(assessment.risk, .protected)
        XCTAssertEqual(assessment.actionPolicy, .blocked)
        XCTAssertFalse(assessment.allowsTrash)
    }

    func testDerivedDataIsRebuildable() {
        let assessment = DeletionSafety.assess(
            path: "/Users/example/Library/Developer/Xcode/DerivedData/App-abcd",
            homePath: home
        )
        XCTAssertEqual(assessment.risk, .rebuildable)
        XCTAssertEqual(assessment.actionPolicy, .standardConfirmation)
        XCTAssertTrue(assessment.allowsTrash)
    }

    func testUsrLocalIsSensitiveRatherThanProtected() {
        let assessment = DeletionSafety.assess(path: "/usr/local/bin/tool", homePath: home)
        XCTAssertEqual(assessment.risk, .sensitive)
        XCTAssertEqual(assessment.actionPolicy, .strongConfirmation)
        XCTAssertTrue(assessment.allowsTrash)
    }

    func testArchivesAreSensitive() {
        let assessment = DeletionSafety.assess(
            path: "/Users/example/Library/Developer/Xcode/Archives/2026-08-04/App.xcarchive",
            homePath: home
        )
        XCTAssertEqual(assessment.risk, .sensitive)
    }

    func testAggregateNodeCannotBeTrashed() {
        let node = FileNode(name: "Diğer", path: home, isDirectory: false)
        node.isAggregate = true

        let assessment = DeletionSafety.assess(node: node, homePath: home)

        XCTAssertEqual(assessment.risk, .protected)
        XCTAssertFalse(assessment.allowsTrash)
    }

    func testMachineWideAndUserRootsAreBlocked() {
        for path in [
            "/", "/Users", home, "/Applications/App.app", "/Library/Application Support",
            "/private", "/etc", "/opt", "/usr/local"
        ] {
            XCTAssertEqual(
                DeletionSafety.assess(path: path, homePath: home).actionPolicy,
                .blocked,
                path
            )
        }
    }

    @MainActor
    func testReviewQueueCannotBeBypassed() {
        let viewModel = ScanViewModel()
        let parent = FileNode(
            name: "Downloads",
            path: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads").path,
            isDirectory: true
        )
        let node = FileNode(name: "candidate.bin", path: parent.path + "/candidate.bin", isDirectory: false)
        node.parent = parent

        viewModel.requestDeletion(node: node)
        XCTAssertNil(viewModel.pendingDeletion)
        XCTAssertNotNil(viewModel.errorMessage)

        viewModel.toggleReview(node: node)
        viewModel.requestDeletion(node: node)
        XCTAssertEqual(viewModel.pendingDeletion?.node.id, node.id)
    }

    func testResolvedSymlinkUsesHighestRisk() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let link = directory.appendingPathComponent("looks-safe")
        try FileManager.default.createSymbolicLink(
            atPath: link.path,
            withDestinationPath: "/System/Library"
        )

        let assessment = DeletionSafety.assess(path: link.path, homePath: directory.path)

        XCTAssertEqual(assessment.risk, .protected)
        XCTAssertEqual(assessment.actionPolicy, .blocked)
    }

    func testIntermediateSymlinkChainUsesResolvedRisk() throws {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".luciddisk-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let link = directory.appendingPathComponent("system-link")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "/System")

        let assessment = DeletionSafety.assess(
            path: link.appendingPathComponent("Library").path,
            homePath: FileManager.default.homeDirectoryForCurrentUser.path
        )

        XCTAssertEqual(assessment.risk, .protected)
        XCTAssertEqual(assessment.actionPolicy, .blocked)
    }

    func testIdentityMismatchAbortsTrashValidation() throws {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".luciddisk-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("item")
        try Data("data".utf8).write(to: file)
        let actual = try XCTUnwrap(FileIdentity.read(atPath: file.path))
        let parent = FileNode(name: "parent", path: directory.path, isDirectory: true)
        let node = FileNode(
            name: file.lastPathComponent,
            path: file.path,
            isDirectory: false,
            fileIdentity: FileIdentity(device: actual.device, inode: actual.inode &+ 1)
        )
        node.parent = parent

        XCTAssertThrowsError(try DeletionSafety.validateBeforeTrash(node: node)) {
            guard case DeletionValidationError.identityChanged = $0 else {
                return XCTFail("Expected identityChanged, got \($0)")
            }
        }
    }

    func testDisappearingFileAbortsTrashValidation() throws {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".luciddisk-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("item")
        try Data("data".utf8).write(to: file)
        let parent = FileNode(name: "parent", path: directory.path, isDirectory: true)
        let node = FileNode(
            name: file.lastPathComponent,
            path: file.path,
            isDirectory: false,
            fileIdentity: try XCTUnwrap(FileIdentity.read(atPath: file.path))
        )
        node.parent = parent
        try FileManager.default.removeItem(at: file)

        XCTAssertThrowsError(try DeletionSafety.validateBeforeTrash(node: node)) {
            guard case DeletionValidationError.itemMissing = $0 else {
                return XCTFail("Expected itemMissing, got \($0)")
            }
        }
    }

    func testSharedGoldenFixture() throws {
        struct Fixture: Decodable {
            let path: String
            let home: String
            let risk: String
        }
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/deletion-safety.json")
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: fixtureURL))

        for fixture in fixtures {
            XCTAssertEqual(
                String(describing: DeletionSafety.assess(path: fixture.path, homePath: fixture.home).risk),
                fixture.risk,
                fixture.path
            )
        }
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

final class SharedSafetyFixtureTests: XCTestCase {
    /// The MCP server runs the same fixture, keeping both rule sets in sync.
    func testSharedDeletionSafetyFixture() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/deletion-safety.json")
        let cases = try JSONDecoder().decode([FixtureCase].self, from: Data(contentsOf: url))
        XCTAssertFalse(cases.isEmpty)
        for item in cases {
            let assessment = DeletionSafety.assess(path: item.path, homePath: item.home)
            XCTAssertEqual(String(describing: assessment.risk), item.risk, item.path)
            XCTAssertEqual(assessment.matchedRule, item.rule, item.path)
        }
    }

    private struct FixtureCase: Decodable {
        let path: String
        let home: String
        let risk: String
        let rule: String
    }
}
