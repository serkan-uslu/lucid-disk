import SwiftUI
import AppKit

/// Calculated off the main actor and reused when selection changes.
struct BrowserContents {
    let revision = UUID()
    let nodes: [FileNode]
    /// Chart palette rank per folder child; empty for search results.
    var colorRanks: [UUID: Int] = [:]

    static func load(focused: FileNode, root: FileNode, query: String, order: FileSortOrder,
                     filters: BrowserSearchFilters = .init(), now: Date = Date()) throws -> BrowserContents {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let searching = !query.isEmpty || filters.isFiltering
        var nodes: [FileNode]
        if !searching {
            nodes = focused.isAggregate ? focused.aggregatedChildren : focused.children
        } else {
            nodes = []
            let scopeRoot = filters.scope == .all ? root : focused
            var stack = scopeRoot.isAggregate ? scopeRoot.aggregatedChildren : scopeRoot.children
            while let node = stack.popLast() {
                try Task.checkCancellation()
                if filters.matches(node, query: query, now: now) {
                    nodes.append(node)
                }
                stack.append(contentsOf: node.children)
            }
        }
        try Task.checkCancellation()
        let ranks = searching ? [:] : paletteRanks(of: nodes)
        nodes.sort(by: order.precedes)
        try Task.checkCancellation()
        return BrowserContents(nodes: nodes, colorRanks: ranks)
    }
}

struct PieContentsPanel: View {
    let focusedNode: FileNode
    let searchRoot: FileNode
    let selectedIDs: Set<UUID>
    let onSelect: ([FileNode], FileNode?) -> Void
    let onFocus: (FileNode) -> Void
    let onPreview: (FileNode) -> Void
    var treeRevision: UUID = UUID()
    var snapshotDate: Date?
    var wasStopped = false

    @State private var searchText = ""
    @State private var sortOrder: FileSortOrder = .size
    @State private var contents = BrowserContents(nodes: [])
    @State private var loading = false
    @State private var filters = BrowserSearchFilters()
    @State private var showingFilters = false
    @State private var contentsRequest: BrowserRequest?
    @State private var reportPresentation: ScanReportPresentation?
    @FocusState private var searchFocused: Bool

    private var request: BrowserRequest {
        BrowserRequest(focus: focusedNode.id, root: searchRoot.id, revision: treeRevision,
                       query: searchText, order: sortOrder, filters: filters)
    }

    private var isSearching: Bool { !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || filters.isFiltering }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text(isSearching ? String(localized: "Search Results") : String(localized: "Contents"))
                        .font(.headline)
                    Pill(title: String(localized: "\(contents.nodes.count) items"))
                    Spacer(minLength: 8)
                    if loading { ProgressView().controlSize(.small) }
                }
                HStack(spacing: 12) {
                    Button { showingFilters.toggle() } label: {
                        Label(showingFilters ? String(localized: "Hide filters") : String(localized: "Filters"),
                              systemImage: filters.isFiltering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                    .buttonStyle(.plain).help("Search filters").accessibilityLabel("Search filters")
                    .accessibilityIdentifier("search-filters")
                    Menu {
                        Picker("Sort", selection: $sortOrder) {
                            ForEach(FileSortOrder.allCases) { order in Text(order.title).tag(order) }
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down").labelStyle(.titleAndIcon)
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                    .help("Sort").accessibilityIdentifier("file-sort")
                    Spacer(minLength: 0)
                }
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search all scanned files", text: $searchText).textFieldStyle(.plain)
                        .focused($searchFocused)
                        .accessibilityLabel("Search all scanned files")
                        .accessibilityIdentifier("file-search")
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: { Label("Clear search", systemImage: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Clear search")
                            .font(.caption).fixedSize()
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(searchFocused ? Theme.accent.opacity(0.7) : Theme.cardStroke))
                if showingFilters { searchFilters }
                if isSearching {
                    Text(filters.scope.title).font(.caption2).foregroundStyle(.secondary)
                }
                HStack {
                    Menu {
                        Button("Export Results…") { presentReport() }
                        Button("Export Folder Tree…") { presentReport(entireFolder: true) }
                            .disabled(focusedNode.isAggregate)
                    } label: { Label("Export", systemImage: "square.and.arrow.up") }
                        .menuStyle(.borderlessButton).fixedSize()
                        .help("Export results with names, paths, types and sizes")
                        .accessibilityIdentifier("export-results")
                    Button { presentReport(review: true) } label: {
                        Label("Review Cleanup", systemImage: "sparkles")
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    .help("Prepare these results for Codex or Claude")
                    .accessibilityIdentifier("review-cleanup")
                    .disabled(contents.nodes.isEmpty)
                    Spacer(minLength: 0)
                }
                .font(.caption)
                .disabled(loading || contentsRequest != request)
            }
            .padding(16)
            Divider()
            if contents.nodes.isEmpty, !loading {
                ContentUnavailableView(
                    isSearching ? String(localized: "No matching files") : String(localized: "Nothing to display"),
                    systemImage: isSearching ? "magnifyingglass" : "folder",
                    description: Text(!isSearching
                                      ? String(localized: "This folder may be empty or unreadable.")
                                      : String(localized: "Try other words or clear the search filters."))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                FileBrowserTable(contents: contents, selectedIDs: selectedIDs,
                                 total: focusedNode.size, showPath: isSearching,
                                 onSelect: onSelect, onOpen: { node in
                                     searchText = ""
                                     filters = BrowserSearchFilters()
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
        .sheet(item: $reportPresentation) { ScanReportSheet(presentation: $0) }
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
                                                         query: current.query, order: current.order, filters: current.filters)
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        guard !Task.isCancelled, request == current else { return }
                        contents = result
                        contentsRequest = current
                        loading = false
                    }
                } catch {
                    // Replaced searches are cancelled and must never publish stale rows.
                }
            }
            await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
        }
    }

    private func presentReport(entireFolder: Bool = false, review: Bool = false) {
        guard !loading, contentsRequest == request else { return }
        var descriptions: [String]
        if entireFolder {
            descriptions = [String(localized: "All scanned descendants of this folder; search filters are not applied.")]
        } else if isSearching {
            descriptions = [filters.scope.title, filters.kind.title, filters.modified.title]
            if filters.minimumBytes > 0 {
                descriptions.append(String(localized: "Minimum size: \(ByteCountFormatter.string(fromByteCount: filters.minimumBytes, countStyle: .file))"))
            }
            if !filters.extensions.isEmpty { descriptions.append(String(localized: "Extensions: \(filters.extensions)")) }
        } else {
            descriptions = [String(localized: "Immediate contents of the current folder; nested contents are not included.")]
        }
        let context = ScanReportContext(
            title: entireFolder ? String(localized: "Folder Tree") : (isSearching ? String(localized: "Search Results") : String(localized: "Contents")),
            query: entireFolder ? "" : searchText,
            filters: descriptions,
            snapshotDate: snapshotDate,
            wasStopped: wasStopped
        )
        reportPresentation = ScanReportPresentation(root: entireFolder ? focusedNode : searchRoot,
                                                  matches: entireFolder ? nil : contents.nodes,
                                                  context: context, reviewWithAssistant: review)
    }

    private var searchFilters: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Search in", selection: $filters.scope) {
                ForEach(BrowserSearchScope.allCases) { Text($0.title).tag($0) }
            }
            Picker("Kind", selection: $filters.kind) {
                ForEach(BrowserItemKind.allCases) { Text($0.title).tag($0) }
            }
            Picker("Minimum size", selection: $filters.minimumBytes) {
                Text("Any size").tag(Int64(0))
                ForEach([Int64(100_000_000), 1_000_000_000, 10_000_000_000], id: \.self) { bytes in
                    Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)).tag(bytes)
                }
            }
            Picker("Date Modified", selection: $filters.modified) {
                ForEach(BrowserModifiedFilter.allCases) { Text($0.title).tag($0) }
            }
            TextField("Extensions, e.g. zip, dmg, mov", text: $filters.extensions)
                .textFieldStyle(.roundedBorder)
                .help("Separate file extensions with commas")
            Button("Reset filters") { filters = BrowserSearchFilters() }
                .buttonStyle(.link)
        }
        .font(.caption)
    }
}

/// Native row reuse and selection avoid rebuilding a large SwiftUI List on every click.
private struct FileBrowserTable: NSViewRepresentable {
    let contents: BrowserContents
    let selectedIDs: Set<UUID>
    let total: Int64
    let showPath: Bool
    let onSelect: ([FileNode], FileNode?) -> Void
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
        table.rowHeight = 62
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .regular
        // ⌘-click and ⇧-click select several items for batch review.
        table.allowsMultipleSelection = true
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
        let rows = IndexSet(selectedIDs.compactMap { coordinator.rowByID[$0] })
        if table.selectedRowIndexes != rows {
            table.selectRowIndexes(rows, byExtendingSelection: false)
            if rows.count == 1, let row = rows.first { table.scrollRowToVisible(row) }
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
            let nodes = table.selectedRowIndexes.compactMap { node(at: $0) }
            // The clicked row is the natural primary item; keyboard moves use the last selected row.
            let primaryRow = table.selectedRowIndexes.contains(table.clickedRow) ? table.clickedRow : table.selectedRow
            parent.onSelect(nodes, node(at: primaryRow))
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
    let revision: UUID
    let query: String
    let order: FileSortOrder
    let filters: BrowserSearchFilters
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
                    Text(ByteCountFormatter.string(fromByteCount: node.size, countStyle: .file))
                        .font(.callout.weight(.medium).monospacedDigit()).foregroundStyle(.secondary).fixedSize()
                }
                HStack(spacing: 8) {
                    if showPath {
                        Text(node.path).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(fraction.formatted(.percent.precision(.fractionLength(fraction < 0.01 ? 1 : 0))))
                            .font(.caption.monospacedDigit()).foregroundStyle(.tertiary).fixedSize()
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.primary.opacity(0.07))
                                Capsule().fill(chartColor(seed: colorSeed, level: 1, aggregate: node.isAggregate))
                                    .frame(width: max(3, geo.size.width * fraction))
                            }
                        }.frame(height: 4)
                    }
                    if node.isDirectory || node.isAggregate {
                        Button(action: onOpen) {
                            Label("Open Folder", systemImage: "chevron.right").font(.caption.weight(.semibold))
                                .fixedSize().contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .help("Open Folder").accessibilityLabel("Open Folder")
                    }
                }
            }
        }
        .padding(.vertical, 7)
        .help(node.path)
        .accessibilityElement(children: .contain)
    }
}
