import XCTest
@testable import LucidDiskCore

final class WedgeTests: XCTestCase {
    func testVisibleWedgesContainNodeSizeNameAndPathSource() {
        let root = FileNode(name: "Root", path: "/tmp/root", isDirectory: true, size: 100)
        let large = FileNode(name: "Large", path: "/tmp/root/large", isDirectory: false, size: 80)
        let small = FileNode(name: "Small", path: "/tmp/root/small", isDirectory: false, size: 20)
        large.parent = root
        small.parent = root
        root.children = [large, small]

        let wedges = computeWedges(focusedNode: root, minFraction: 0)

        XCTAssertEqual(wedges.count, 2)
        XCTAssertEqual(wedges.map(\.node.name), ["Large", "Small"])
        XCTAssertEqual(wedges.map(\.node.path), ["/tmp/root/large", "/tmp/root/small"])
        XCTAssertEqual(wedges.map(\.node.size), [80, 20])
    }

    func testOtherGroupRetainsEveryUnderlyingItem() throws {
        let root = FileNode(name: "Root", path: "/tmp/root", isDirectory: true, size: 10_000)
        root.children = (0..<75).map { index in
            let child = FileNode(
                name: "Small \(index)",
                path: "/tmp/root/small-\(index)",
                isDirectory: false,
                size: 1
            )
            child.parent = root
            return child
        }

        let aggregate = try XCTUnwrap(
            computeWedges(focusedNode: root, minFraction: 0.01).first(where: { $0.node.isAggregate })?.node
        )

        XCTAssertEqual(aggregate.aggregatedChildren.count, 75)
        XCTAssertEqual(Set(aggregate.aggregatedChildren.map(\.id)).count, 75)
    }
}
