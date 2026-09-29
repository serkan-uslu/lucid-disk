import SwiftUI
import AppKit

/// Calculated off the main actor and reused when selection changes.
struct BrowserContents {
    let revision = UUID()
    let nodes: [FileNode]
    /// Chart palette rank per folder child; empty for search results.
    var colorRanks: [UUID: Int] = [:]

    static func load(focused: FileNode, root: FileNode, query: String, order: FileSortOrder) throws -> BrowserContents {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var nodes: [FileNode]
        if query.isEmpty {
            nodes = focused.isAggregate ? focused.aggregatedChildren : focused.children
        } else {
            nodes = []
            var stack = root.children
            while let node = stack.popLast() {
                try Task.checkCancellation()
                if node.name.localizedCaseInsensitiveContains(query)
                    || node.path.localizedCaseInsensitiveContains(query) {
                    nodes.append(node)
                }
                stack.append(contentsOf: node.children)
            }
        }
        try Task.checkCancellation()
        let ranks = query.isEmpty ? paletteRanks(of: nodes) : [:]
        nodes.sort(by: order.precedes)
        try Task.checkCancellation()
        return BrowserContents(nodes: nodes, colorRanks: ranks)
    }
}

struct PieContentsPanel: View {
    let focusedNode: FileNode
    let searchRoot: FileNode
    let selectedNode: FileNode?
    let onSelect: (FileNode?) -> Void
    let onFocus: (FileNode) -> Void
    let onPreview: (FileNode) -> Void

    @State private var searchText = ""
    @State private var sortOrder: FileSortOrder = .size
    @State private var contents = BrowserContents(nodes: [])
    @State private var loading = false
    @FocusState private var searchFocused: Bool

    private var request: BrowserRequest {
        BrowserRequest(focus: focusedNode.id, root: searchRoot.id, query: searchText, order: sortOrder)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text(searchText.isEmpty ? String(localized: "Contents") : String(localized: "Search Results"))
                        .font(.headline)
                    Pill(title: String(localized: "\(contents.nodes.count) items"))
                    Spacer(minLength: 8)
                    if loading { ProgressView().controlSize(.small) }
                    Menu {
                        Picker("Sort", selection: $sortOrder) {
                            ForEach(FileSortOrder.allCases) { order in Text(order.title).tag(order) }
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down").labelStyle(.iconOnly)
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                    .help("Sort").accessibilityIdentifier("file-sort")
                }
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search all scanned files", text: $searchText).textFieldStyle(.plain)
                        .focused($searchFocused)
                        .accessibilityIdentifier("file-search")
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(searchFocused ? Theme.accent.opacity(0.7) : Theme.cardStroke))
            }
            .padding(16)
            Divider()
            if contents.nodes.isEmpty, !loading {
                ContentUnavailableView(
                    searchText.isEmpty ? String(localized: "Nothing to display") : String(localized: "No matching files"),
                    systemImage: searchText.isEmpty ? "folder" : "magnifyingglass",
                    description: Text(searchText.isEmpty
                                      ? String(localized: "This folder may be empty or unreadable.")
                                      : String(localized: "Try another file name or path."))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                FileBrowserTable(contents: contents, selectedID: selectedNode?.id,
                                 total: focusedNode.size, showPath: !searchText.isEmpty,
                                 onSelect: onSelect, onOpen: { node in
                                     searchText = ""
                                     onFocus(node)
                                 }, onPreview: onPreview)
                    .accessibilityIdentifier("file-list")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.background)
        .background {
            Button("Search all scanned files") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command).hidden()
        }
        .onChange(of: focusedNode.id) { _, _ in searchText = "" }
        .task(id: request) {
            let current = request
            let focused = focusedNode
            let root = searchRoot
            loading = true
            contents = BrowserContents(nodes: [])
            let worker = Task.detached(priority: .userInitiated) {
                do {
                    if !current.query.isEmpty { try await Task.sleep(for: .milliseconds(180)) }
                    let result = try BrowserContents.load(focused: focused, root: root,
                                                         query: current.query, order: current.order)
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        guard request == current else { return }
                        contents = result
                        loading = false
                    }
                } catch {
                    // Replaced searches are cancelled and must never publish stale rows.
                }
            }
            await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
        }
        .accessibilityLabel("Disk contents")
    }
}

/// Native row reuse and selection avoid rebuilding a large SwiftUI List on every click.
private struct FileBrowserTable: NSViewRepresentable {
    let contents: BrowserContents
    let selectedID: UUID?
    let total: Int64
    let showPath: Bool
    let onSelect: (FileNode?) -> Void
    let onOpen: (FileNode) -> Void
    let onPreview: (FileNode) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let table = BrowserTableView()
        table.identifier = NSUserInterfaceItemIdentifier("file-list")
        table.setAccessibilityIdentifier("file-list")
        table.setAccessibilityLabel(String(localized: "Disk contents"))
        table.headerView = nil
        table.style = .inset
        table.rowHeight = 52
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .regular
        table.allowsMultipleSelection = false
        table.allowsEmptySelection = true
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("file"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.delegate = context.coordinator
        table.dataSource = context.coordinator
        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.openSelected(_:))
        table.openSelection = { [weak coordinator = context.coordinator, weak table] in
            if let table { coordinator?.openSelected(table) }
        }
        table.previewSelection = { [weak coordinator = context.coordinator, weak table] in
            if let table { coordinator?.previewSelected(table) }
        }
        scroll.documentView = table
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let table = scroll.documentView as? NSTableView else { return }
        let coordinator = context.coordinator
        let changed = coordinator.revision != contents.revision
        coordinator.parent = self
        coordinator.updating = true
        if changed {
            coordinator.revision = contents.revision
            coordinator.rowByID = Dictionary(uniqueKeysWithValues: contents.nodes.enumerated().map { ($0.element.id, $0.offset) })
            table.reloadData()
        }
        let row = selectedID.flatMap { coordinator.rowByID[$0] } ?? -1
        if table.selectedRow != row {
            table.selectRowIndexes(row < 0 ? [] : IndexSet(integer: row), byExtendingSelection: false)
            if row >= 0 { table.scrollRowToVisible(row) }
        }
        coordinator.updating = false
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: FileBrowserTable
        var revision: UUID?
        var rowByID: [UUID: Int] = [:]
        var updating = false
        init(parent: FileBrowserTable) { self.parent = parent }

        func numberOfRows(in tableView: NSTableView) -> Int { parent.contents.nodes.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let node = parent.contents.nodes[row]
            let view = FileBrowserRow(node: node, colorSeed: parent.contents.colorRanks[node.id].map(paletteSeed) ?? node.path,
                                      total: parent.total, showPath: parent.showPath,
                                      onOpen: { [weak self] in self?.parent.onOpen(node) })
                .padding(.horizontal, 8)
            let id = NSUserInterfaceItemIdentifier("file-cell")
            if let host = tableView.makeView(withIdentifier: id, owner: self) as? NSHostingView<AnyView> {
                host.rootView = AnyView(view)
                return host
            }
            let host = NSHostingView(rootView: AnyView(view))
            host.identifier = id
            return host
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !updating, let table = notification.object as? NSTableView else { return }
            parent.onSelect(node(at: table.selectedRow))
        }

        @objc func openSelected(_ table: NSTableView) {
            guard let node = node(at: table.selectedRow), node.isDirectory || node.isAggregate else { return }
            parent.onOpen(node)
        }

        func previewSelected(_ table: NSTableView) {
            guard let node = node(at: table.selectedRow), !node.isAggregate else { return }
            parent.onPreview(node)
        }

        private func node(at row: Int) -> FileNode? {
            parent.contents.nodes.indices.contains(row) ? parent.contents.nodes[row] : nil
        }
    }
}

private final class BrowserTableView: NSTableView {
    var openSelection: (() -> Void)?
    var previewSelection: (() -> Void)?
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if selectedRow >= 0, !NSLocationInRange(selectedRow, rows(in: visibleRect)) {
            scrollRowToVisible(selectedRow)
        }
    }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 124: openSelection?()
        case 49: previewSelection?()
        default: super.keyDown(with: event)
        }
    }
}

private struct BrowserRequest: Equatable {
    let focus: UUID
    let root: UUID
    let query: String
    let order: FileSortOrder
}

enum FileSortOrder: String, CaseIterable, Identifiable {
    case size, name, modified
    var id: Self { self }
    var title: String {
        switch self {
        case .size: String(localized: "Size")
        case .name: String(localized: "Name")
        case .modified: String(localized: "Date Modified")
        }
    }
    func precedes(_ lhs: FileNode, _ rhs: FileNode) -> Bool {
        switch self {
        case .size:
            lhs.size == rhs.size ? lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending : lhs.size > rhs.size
        case .name:
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        case .modified:
            (lhs.modifiedAt ?? .distantPast) == (rhs.modifiedAt ?? .distantPast)
                ? lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                : (lhs.modifiedAt ?? .distantPast) > (rhs.modifiedAt ?? .distantPast)
        }
    }
}

private struct FileBrowserRow: View {
    let node: FileNode
    let colorSeed: String
    let total: Int64
    let showPath: Bool
    let onOpen: () -> Void

    private var fraction: Double { min(1, Double(node.size) / Double(max(1, total))) }

    var body: some View {
        HStack(spacing: 10) {
            FileIconView(node: node, size: 28)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(node.name).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    if !showPath {
                        Text(fraction.formatted(.percent.precision(.fractionLength(fraction < 0.01 ? 1 : 0))))
                            .font(.caption.monospacedDigit()).foregroundStyle(.tertiary).fixedSize()
                    }
                    Text(ByteCountFormatter.string(fromByteCount: node.size, countStyle: .file))
                        .font(.callout.weight(.medium).monospacedDigit()).foregroundStyle(.secondary).fixedSize()
                }
                if showPath {
                    Text(node.path).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                } else {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.07))
                            Capsule().fill(chartColor(seed: colorSeed, level: 1, aggregate: node.isAggregate))
                                .frame(width: max(3, geo.size.width * fraction))
                        }
                    }.frame(height: 4)
                }
            }
            if node.isDirectory || node.isAggregate {
                Button(action: onOpen) {
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                        .frame(width: 22, height: 30).contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Open Folder").accessibilityLabel("Open Folder")
            } else {
                Color.clear.frame(width: 22, height: 30)
            }
        }
        .padding(.vertical, 7)
        .help(node.path)
        .accessibilityElement(children: .contain)
    }
}
