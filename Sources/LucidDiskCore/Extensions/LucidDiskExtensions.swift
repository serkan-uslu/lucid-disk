import Combine
import SwiftUI

// Extension points for editions built on top of this open-source core, such as
// a separately distributed Pro app. The Community build installs nothing, so
// every slot below stays empty.
//
// Rules the API enforces by construction:
// - Extensions read scan results; only the core scanner changes them.
// - Extensions may add items to the review queue, never move anything to Trash.
// - Safety verdicts come from `DeletionSafety` and cannot be replaced.

/// Name and badge of the running edition.
public struct EditionInfo: Equatable, Sendable {
    public var name: String
    /// A short label such as "Pro"; `nil` for the Community edition.
    public var badge: String?

    public init(name: String = "Lucid Disk", badge: String? = nil) {
        self.name = name
        self.badge = badge
    }

    public static let community = EditionInfo()

    public var displayName: String { badge.map { "\(name) \($0)" } ?? name }
}

/// Something an edition plugs into the core UI.
@MainActor
public protocol LucidDiskExtension {
    func install(into extensions: LucidDiskExtensions)
}

/// A section appended to the main window's sidebar.
public struct SidebarContribution: Identifiable {
    public let id: String
    public let title: String
    public let content: @MainActor (LucidDiskContext) -> AnyView

    public init(id: String, title: String, content: @escaping @MainActor (LucidDiskContext) -> AnyView) {
        self.id = id
        self.title = title
        self.content = content
    }
}

/// A card appended to the inspector for the selected item.
public struct InspectorContribution: Identifiable {
    public let id: String
    public let content: @MainActor (FileNode, LucidDiskContext) -> AnyView

    public init(id: String, content: @escaping @MainActor (FileNode, LucidDiskContext) -> AnyView) {
        self.id = id
        self.content = content
    }
}

/// A tab appended to the Settings window.
public struct SettingsTabContribution: Identifiable {
    public let id: String
    public let title: String
    public let systemImage: String
    public let content: @MainActor () -> AnyView

    public init(id: String, title: String, systemImage: String, content: @escaping @MainActor () -> AnyView) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.content = content
    }
}

/// The registry an edition fills at launch. Contributions with an existing id replace it.
@MainActor
public final class LucidDiskExtensions: ObservableObject {
    public static let shared = LucidDiskExtensions()

    @Published public private(set) var edition: EditionInfo = .community
    @Published public private(set) var sidebarSections: [SidebarContribution] = []
    @Published public private(set) var inspectorSections: [InspectorContribution] = []
    @Published public private(set) var settingsTabs: [SettingsTabContribution] = []

    init() {}

    public func install(_ extension: LucidDiskExtension) {
        `extension`.install(into: self)
    }

    public func setEdition(_ edition: EditionInfo) {
        self.edition = edition
    }

    public func addSidebarSection(_ contribution: SidebarContribution) {
        sidebarSections = Self.upserting(contribution, into: sidebarSections)
    }

    public func addInspectorSection(_ contribution: InspectorContribution) {
        inspectorSections = Self.upserting(contribution, into: inspectorSections)
    }

    public func addSettingsTab(_ contribution: SettingsTabContribution) {
        settingsTabs = Self.upserting(contribution, into: settingsTabs)
    }

    /// Removes every contribution with this id, e.g. when a license is deactivated.
    public func remove(id: String) {
        sidebarSections.removeAll { $0.id == id }
        inspectorSections.removeAll { $0.id == id }
        settingsTabs.removeAll { $0.id == id }
    }

    /// Returns the registry to the Community state.
    public func reset() {
        edition = .community
        sidebarSections = []
        inspectorSections = []
        settingsTabs = []
    }

    private static func upserting<T: Identifiable>(_ item: T, into items: [T]) -> [T] where T.ID == String {
        var items = items
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
        return items
    }
}

/// The scan state an extension may observe, plus the few actions it may take.
@MainActor
public final class LucidDiskContext: ObservableObject {
    private unowned let viewModel: ScanViewModel
    private var forwarding: AnyCancellable?

    init(viewModel: ScanViewModel) {
        self.viewModel = viewModel
        forwarding = viewModel.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    public var rootNode: FileNode? { viewModel.rootNode }
    public var focusedNode: FileNode? { viewModel.focusedNode }
    public var selectedNode: FileNode? { viewModel.selectedNode }
    /// Every selected item, including `selectedNode`.
    public var selectedNodes: [FileNode] { viewModel.selectedNodes }
    public var reviewQueue: [FileNode] { viewModel.reviewQueue }
    public var isScanning: Bool { viewModel.isScanning }
    public var mountedVolumePaths: [String] { viewModel.mountedVolumes.map(\.url.path) }

    public func startScan(path: String) { viewModel.startScan(path: path) }
    public func focus(on node: FileNode) { viewModel.focus(on: node) }
    public func select(_ node: FileNode?) { viewModel.selectedNode = node }

    /// Queues an item for the user's review. Moving it to Trash still requires
    /// the user's own confirmation and the core safety checks.
    @discardableResult
    public func addToReview(_ node: FileNode) -> Bool {
        guard !node.isAggregate, !viewModel.isQueued(node) else { return false }
        viewModel.toggleReview(node: node)
        return viewModel.isQueued(node)
    }
}
