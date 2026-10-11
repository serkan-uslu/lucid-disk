import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel: ScanViewModel
    @ObservedObject private var insightSettings = InsightSettings.shared
    @ObservedObject private var extensions = LucidDiskExtensions.shared
    @State private var wedges: [Wedge] = []
    @State private var quickLookItem: QuickLookItem?
    @State private var showingSpaceBreakdown = false
    @State private var showingHome = false
    @State private var showingDetails = false
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all
    private let volumeRefresh = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    @MainActor
    init(viewModel: ScanViewModel? = nil, showingDetails: Bool = false) {
        _viewModel = StateObject(wrappedValue: viewModel ?? ScanViewModel(scanStore: .shared))
        _showingDetails = State(initialValue: showingDetails)
    }

    var body: some View {
      VStack(spacing: 0) {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
        statusBar
      }
        .navigationTitle(extensions.edition.displayName)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    sidebarVisibility = sidebarVisibility == .detailOnly ? .all : .detailOnly
                } label: {
                    Label(sidebarVisibility == .detailOnly ? String(localized: "Show Sidebar") : String(localized: "Hide Sidebar"),
                          systemImage: "sidebar.left")
                }
                .labelStyle(.titleAndIcon)
                .help("Show or hide volumes, locations and the review queue")
                .accessibilityIdentifier("toggle-sidebar")
            }
            ToolbarItemGroup {
              if !viewModel.isScanning {
                Button { goHome() } label: { Label("Home", systemImage: "house") }
                    .labelStyle(.titleAndIcon)
                    .help("Return to the start page")
                    .accessibilityIdentifier("show-home")
                    .disabled(viewModel.isScanning || viewModel.isMovingToTrash)
                Button {
                    chooseFolder()
                } label: {
                    Label("Choose Folder", systemImage: "folder.badge.plus")
                }
                .labelStyle(.titleAndIcon)
                .accessibilityIdentifier("choose-folder")
                .help("Choose a folder to scan")
                .keyboardShortcut("o", modifiers: .command)
                .disabled(viewModel.isScanning || viewModel.isMovingToTrash)
                Button {
                    showingHome = false
                    viewModel.rescanFocusedFolder()
                } label: {
                    Label(viewModel.focusedNode?.isAggregate == true
                          ? String(localized: "Scan Containing Folder") : String(localized: "Scan Again"),
                          systemImage: "arrow.clockwise")
                }
                .labelStyle(.titleAndIcon)
                .accessibilityIdentifier("rescan-focused-folder")
                .keyboardShortcut("r", modifiers: .command)
                .help(viewModel.focusedNode?.isAggregate == true
                      ? String(localized: "Scan the folder containing this Other group again")
                      : String(localized: "Scan the current folder again"))
                .disabled(viewModel.focusedRescanTarget == nil || viewModel.isScanning || viewModel.isMovingToTrash)
              }
                Menu {
                    Button {
                        showingHome = false
                        viewModel.startScan(path: "/")
                    } label: {
                        Label("Scan Startup Disk", systemImage: "internaldrive")
                    }
                    .accessibilityIdentifier("scan-startup-disk")
                    .help("Scan the startup disk to find what uses space")
                    .disabled(viewModel.isScanning || viewModel.isMovingToTrash)
                    Divider()
                    Button { AppSupport.shared.show(.guide) } label: {
                        Label("How to Use", systemImage: "questionmark.circle")
                    }
                    .accessibilityIdentifier("show-help")
                    SettingsLink {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .accessibilityIdentifier("show-settings")
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .labelStyle(.titleAndIcon)
                .help("Startup disk scan, help and settings")
                .accessibilityIdentifier("more-actions")
                if viewModel.isScanning {
                    Button(role: .destructive) {
                        viewModel.stopScan()
                    } label: {
                        Label("Stop Scan", systemImage: "stop.circle")
                    }
                    .labelStyle(.titleAndIcon)
                    .accessibilityIdentifier("stop-scan")
                    .help("Stop scanning and show the items already scanned")
                }
            }
        }
        .task(id: "\(viewModel.focusedNode?.id.uuidString ?? "")-\(viewModel.treeRevision.uuidString)") {
            wedges = []
            guard let focused = viewModel.focusedNode else { return }
            let revision = viewModel.treeRevision
            let worker = Task.detached(priority: .userInitiated) {
                let result = computeWedges(focusedNode: focused)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard viewModel.focusedNode?.id == focused.id, viewModel.treeRevision == revision else { return }
                    wedges = result
                }
            }
            await withTaskCancellationHandler {
                await worker.value
            } onCancel: { worker.cancel() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { viewModel.refreshAfterActivation() }
        }
        .onReceive(volumeRefresh) { _ in
            if scenePhase == .active { viewModel.refreshMountedVolumes() }
        }
        .onChange(of: viewModel.focusedNode?.id) { _, _ in
            showingHome = false
            showingDetails = false
        }
        .onChange(of: viewModel.isScanning) { _, scanning in
            if scanning { showingHome = false; showingDetails = false }
        }
        .onChange(of: viewModel.selectedNode?.id) { _, selection in
            if selection == nil { showingDetails = false }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in
            viewModel.refreshMountedVolumes()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in
            viewModel.refreshMountedVolumes()
        }
        .onKeyPress(.space) {
            guard !showingHome, !viewModel.isScanning,
                  let node = viewModel.selectedNode, !node.isAggregate else { return .ignored }
            quickLookItem = QuickLookItem(url: URL(fileURLWithPath: node.path))
            return .handled
        }
        .sheet(isPresented: $showingSpaceBreakdown) {
            if let breakdown = viewModel.spaceBreakdown {
                SpaceBreakdownView(breakdown: breakdown, measuredAt: viewModel.spaceObservation?.measuredAt) {
                    showingSpaceBreakdown = false
                }
            }
        }
        .sheet(item: $quickLookItem) { item in
            VStack(spacing: 0) {
                QuickLookPreview(url: item.url)
                Divider()
                HStack {
                    Text(item.url.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Done") { quickLookItem = nil }
                        .keyboardShortcut(.defaultAction)
                    Button("Close preview") { quickLookItem = nil }
                        .keyboardShortcut(.cancelAction).hidden().frame(width: 0, height: 0)
                }
                .padding(10)
            }
            .frame(minWidth: 720, minHeight: 520)
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .confirmationDialog(
            deletionDialogTitle,
            isPresented: Binding(
                get: { viewModel.pendingDeletion != nil },
                set: { if !$0 { viewModel.pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(deletionButtonTitle, role: .destructive) {
                viewModel.confirmDeletion()
            }
            Button("Cancel", role: .cancel) {
                viewModel.pendingDeletion = nil
            }
        } message: {
            if let pending = viewModel.pendingDeletion {
                Text(deletionMessage(for: pending))
            }
        }
        .confirmationDialog(
            batchDialogTitle,
            isPresented: Binding(
                get: { viewModel.pendingBatchDeletion != nil },
                set: { if !$0 { viewModel.pendingBatchDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(batchButtonTitle, role: .destructive) {
                viewModel.confirmBatchDeletion()
            }
            Button("Cancel", role: .cancel) {
                viewModel.pendingBatchDeletion = nil
            }
        } message: {
            if let pending = viewModel.pendingBatchDeletion {
                Text(batchMessage(for: pending))
            }
        }
    }

    private var sidebar: some View {
        List {
            Button { goHome() } label: { Label("Home", systemImage: "house") }
                .buttonStyle(.plain)
                .help("Return to the start page")
                .disabled(viewModel.isScanning || viewModel.isMovingToTrash)
            if showingHome, viewModel.rootNode != nil {
                Button { showingHome = false } label: { Label("Back to Scan Results", systemImage: "chart.pie") }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("back-to-results")
            }
            Section("Volumes") {
                ForEach(viewModel.mountedVolumes) { volume in
                    Button {
                        showingHome = false
                        viewModel.startScan(path: volume.url.path)
                    } label: {
                        VolumeRow(volume: volume, isCurrent: viewModel.rootNode?.path == volume.url.path)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isScanning || viewModel.isMovingToTrash)
                }
            }

            if let root = viewModel.rootNode {
                Section("Location") {
                    let chain = ancestorChain(from: viewModel.focusedNode ?? root)
                    ForEach(Array(chain.enumerated()), id: \.element.id) { depth, node in
                        Button {
                            showingHome = false
                            viewModel.focus(on: node)
                        } label: {
                            let isCurrent = node === viewModel.focusedNode
                            HStack(spacing: 6) {
                                Image(systemName: isCurrent ? "folder.fill" : "folder")
                                    .foregroundStyle(isCurrent ? Theme.accent : .secondary)
                                Text(node.name).lineLimit(1).truncationMode(.middle)
                                    .fontWeight(isCurrent ? .semibold : .regular)
                                Spacer(minLength: 4)
                                Text(ByteCountFormatter.string(fromByteCount: node.size, countStyle: .file))
                                    .foregroundStyle(.secondary).font(.caption).monospacedDigit()
                            }
                            .padding(.leading, CGFloat(min(depth, 6)) * 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !viewModel.reviewQueue.isEmpty {
                Section {
                    ForEach(viewModel.reviewQueue, id: \.id) { node in
                        HStack(spacing: 8) {
                            Button {
                                showingHome = false
                                showingDetails = true
                                viewModel.select([node], primary: node)
                            } label: {
                                HStack(spacing: 8) {
                                    FileIconView(node: node, size: 20)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(node.name).lineLimit(1).truncationMode(.middle)
                                        Text(ByteCountFormatter.string(fromByteCount: node.size, countStyle: .file))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Spacer(minLength: 0)
                            Button {
                                viewModel.removeFromReview(node: node)
                            } label: {
                                Label("Remove", systemImage: "xmark.circle").font(.caption)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove from review queue")
                            .help("Remove from review queue")
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Button("Clear Queue") { viewModel.clearReviewQueue() }
                            .buttonStyle(.borderless)
                        Button {
                            viewModel.requestBatchDeletion()
                        } label: {
                            Label("Move All to Trash…", systemImage: "trash")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                        .disabled(viewModel.isScanning || viewModel.isMovingToTrash)
                        .accessibilityIdentifier("move-all-to-trash")
                    }
                    .font(.caption)
                } header: {
                    HStack {
                        Text("Review Queue")
                        Spacer()
                        Text(ByteCountFormatter.string(
                            fromByteCount: viewModel.reviewQueue.reduce(0) { $0 + $1.size },
                            countStyle: .file
                        ))
                        .foregroundStyle(Theme.accent)
                    }
                }
            }
            ForEach(extensions.sidebarSections) { contribution in
                Section(contribution.title) {
                    contribution.content(viewModel.extensionContext)
                }
            }
            if !viewModel.scanWarnings.isEmpty {
                Section("Scan Warnings") {
                    ForEach(Array(viewModel.scanWarnings.prefix(5).enumerated()), id: \.offset) { _, warning in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(warning.message).foregroundStyle(.primary)
                                Text(warning.path)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        }
                        .font(.caption)
                    }
                    if viewModel.scanWarnings.count > 5 {
                        Text("\(viewModel.scanWarnings.count - 5) more warnings")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .clipped()
    }

    private func ancestorChain(from node: FileNode) -> [FileNode] {
        var chain: [FileNode] = []
        var current: FileNode? = node
        while let n = current {
            chain.insert(n, at: 0)
            current = n.parent
        }
        return chain
    }

    @ViewBuilder
    private var detail: some View {
        if viewModel.isScanning {
            ScanProgressView(count: viewModel.scannedCount, bytes: viewModel.scannedBytes,
                             path: viewModel.currentPath, onCancel: viewModel.stopScan)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        } else if let focused = viewModel.focusedNode, !showingHome {
            GeometryReader { area in
              let inspectorWidth = min(460, max(340, area.size.width * 0.43))
              let hasDetails = showingDetails && !viewModel.selectedNodes.isEmpty
              // At compact heights the inspector needs the map's space. Closing
              // details restores the map, without squeezing its center to zero.
              let showsDiskMap = !hasDetails || area.size.height >= 850
              HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(focused.name).font(.title2.weight(.semibold)).lineLimit(1)
                        PathBar(chain: ancestorChain(from: focused)) { viewModel.focus(on: $0) }
                        ScanMeasurementSummary(measurement: ScanMeasurementPresentation(
                            focused: focused, root: viewModel.rootNode ?? focused,
                            wasStopped: viewModel.lastScanResult?.wasStopped ?? false,
                            savedAt: viewModel.snapshotDate))
                        ScanNavigationActions(
                            canGoToParent: focused.parent != nil,
                            diskSpace: viewModel.spaceBreakdown.map {
                                DiskSpacePresentation(breakdown: $0, scanRootPath: viewModel.rootNode?.path ?? focused.path)
                            },
                            onParent: { viewModel.zoomOut() },
                            onBreakdown: { showingSpaceBreakdown = true })
                    }
                    .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 6)
                    if showsDiskMap {
                        SunburstView(
                            focusedNode: focused,
                            wedges: wedges,
                            selectedNode: viewModel.selectedNode,
                            selectedIDs: Set(viewModel.selectedNodes.map(\.id)),
                            onZoomOut: { viewModel.zoomOut() },
                            onSelect: { node in viewModel.select(node.map { [$0] } ?? [], primary: node) },
                            onFocus: { node in viewModel.focus(on: node) },
                            onToggleSelection: { node in viewModel.toggleSelection(node) }
                        )
                        .padding(.horizontal, 20).padding(.vertical, 12)
                        Text("Select an item, then choose View Details. Double-click a folder to open it. ⌘-click to select several.")
                            .font(.caption).foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity).padding(.bottom, 14)
                    }
                    if hasDetails {
                        Divider()
                        HStack {
                            Text("Details").font(.headline)
                            Spacer()
                            Button { showingDetails = false } label: { Label("Close details", systemImage: "xmark") }
                                .buttonStyle(.plain).help("Close details").accessibilityLabel("Close details")
                                .accessibilityIdentifier("close-details")
                        }
                        .padding(.horizontal, 18).padding(.vertical, 8)
                        Group {
                            if viewModel.selectedNodes.count > 1 {
                                BatchSelectionPanel(nodes: viewModel.selectedNodes, viewModel: viewModel)
                            } else if let selected = viewModel.selectedNode {
                                DetailPanel(node: selected, viewModel: viewModel,
                                            onQuickLook: { quickLookItem = QuickLookItem(url: $0) })
                                    .id("\(selected.id)-\(viewModel.treeRevision)")
                            }
                        }
                        .frame(height: showsDiskMap ? min(300, area.size.height * 0.44) : nil)
                        .frame(maxHeight: showsDiskMap ? nil : .infinity)
                    }
                }
                .frame(width: max(0, area.size.width - inspectorWidth - 1), height: area.size.height)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipped()
                Divider()
                VStack(spacing: 0) {
                    PieContentsPanel(
                        focusedNode: focused,
                        searchRoot: viewModel.rootNode ?? focused,
                        selectedIDs: Set(viewModel.selectedNodes.map(\.id)),
                        primaryID: viewModel.selectedNode?.id,
                        onSelect: { nodes, primary in viewModel.select(nodes, primary: primary) },
                        onFocus: { node in viewModel.focus(on: node) },
                        onPreview: { node in quickLookItem = QuickLookItem(url: URL(fileURLWithPath: node.path)) },
                        treeRevision: viewModel.treeRevision,
                        snapshotDate: viewModel.snapshotDate,
                        wasStopped: viewModel.lastScanResult?.wasStopped ?? false
                    )
                    .frame(minHeight: 200, maxHeight: .infinity)
                    if let selected = viewModel.selectedNode {
                        Divider()
                        selectionActions(selected)
                    }
                }
                .frame(width: inspectorWidth, height: area.size.height)
                .clipped()
              }
            }
        } else {
            WelcomeView(volumes: viewModel.mountedVolumes,
                        savedScans: Array(viewModel.savedScans.prefix(3)),
                        isOpeningSavedScan: viewModel.isOpeningSavedScan,
                        onScan: { viewModel.startScan(path: $0) },
                        onOpenSaved: { viewModel.openSavedScan($0) },
                        onChooseFolder: chooseFolder)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            showingHome = false
            viewModel.startScan(path: url.path)
        }
    }

    private func goHome() {
        showingHome = true
        showingDetails = false
        viewModel.refreshMountedVolumes()
        viewModel.refreshSavedScans()
    }

    private func selectionActions(_ node: FileNode) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(viewModel.selectedNodes.count > 1
                     ? String(localized: "\(viewModel.selectedNodes.count) items selected") : node.name)
                    .font(.subheadline.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button { viewModel.select([], primary: nil) } label: { Label("Clear Selection", systemImage: "xmark.circle") }
                    .font(.caption).fixedSize()
                    .buttonStyle(.plain).help("Clear Selection").accessibilityLabel("Clear Selection")
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 138), alignment: .leading)], alignment: .leading, spacing: 8) {
                Button { showingDetails.toggle() } label: {
                    Label(showingDetails ? String(localized: "Hide Details") : String(localized: "View Details"), systemImage: "info.circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityIdentifier("view-details")
                if viewModel.selectedNodes.count == 1, !node.isAggregate {
                    Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: node.path)]) } label: {
                        Label("Show in Finder", systemImage: "folder")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .help("Show in Finder").accessibilityLabel("Show in Finder")
                    if node.isDirectory {
                        Button { viewModel.rescanFolder(node) } label: {
                            Label("Rescan Folder", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                            .help("Rescan this folder").accessibilityLabel("Rescan this folder")
                            .accessibilityIdentifier("rescan-folder")
                    }
                }
            }
            .buttonStyle(.bordered).controlSize(.small)
            if viewModel.selectedNodes.count == 1, !node.isAggregate {
                Button(role: .destructive) {
                    if !viewModel.isQueued(node) { viewModel.toggleReview(node: node) }
                    viewModel.requestDeletion(node: node)
                } label: {
                    Label("Move to Trash…", systemImage: "trash").frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered).controlSize(.small)
                .help("Add this item to the review queue and review before moving it to Trash")
                .accessibilityIdentifier("selection-trash")
            } else {
                Button { _ = viewModel.addToReview(viewModel.selectedNodes) } label: {
                    Label("Add to Review Queue", systemImage: "plus.circle").frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
            if viewModel.isShowingSavedScan {
                Text("Saved scan: scan again to update results and enable Trash.")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(14)
        .disabled(viewModel.isMovingToTrash || viewModel.isScanning)
    }

    private var statusBar: some View {
        VStack(spacing: 0) {
            Divider()
            if viewModel.saveState == .failed, !viewModel.isScanning {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Scan could not be saved.").fontWeight(.medium)
                        Text("Results are still available. Check free disk space and folder permissions, then retry.")
                            .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Button("Retry Save") { viewModel.retrySave() }
                        .disabled(viewModel.isScanning || viewModel.isMovingToTrash || viewModel.isOpeningSavedScan)
                        .accessibilityIdentifier("retry-save-scan")
                }
                .font(.caption).padding(.horizontal, 16).padding(.vertical, 9)
                .accessibilityIdentifier("scan-save-failure")
                Divider()
            }
            HStack(spacing: 10) {
                if viewModel.isMovingToTrash {
                    ProgressView().controlSize(.mini)
                    Text("Moving to Trash…")
                } else if let message = viewModel.completionMessage {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(message).lineLimit(2)
                    Spacer(minLength: 0)
                    if let url = viewModel.lastTrashedURL {
                        Button("Show in Trash") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                            .buttonStyle(.link)
                    }
                    Button { viewModel.completionMessage = nil } label: { Label("Dismiss", systemImage: "xmark") }
                        .buttonStyle(.plain).accessibilityLabel("Dismiss notification")
                } else if let savedAt = viewModel.snapshotDate, !viewModel.isScanning {
                    Image(systemName: "clock.arrow.circlepath").foregroundStyle(.orange)
                    Text("Saved scan from \(savedAt.formatted(.relative(presentation: .named)))")
                    Text("· Browse and queue now; scan again before moving anything to the Trash.")
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let path = viewModel.rootNode?.path {
                        Button("Scan Again") { viewModel.startScan(path: path) }
                            .buttonStyle(.link)
                            .accessibilityIdentifier("rescan-saved")
                    }
                } else if let result = viewModel.lastScanResult, !viewModel.isScanning {
                    Image(systemName: viewModel.scanWarnings.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(viewModel.scanWarnings.isEmpty ? Theme.accent : .orange)
                    Text("\(result.statistics.scannedFileCount) files · \(String(format: "%.2f", result.duration)) s")
                        .monospacedDigit()
                    if viewModel.saveState == .saving {
                        Label("Saving scan…", systemImage: "arrow.triangle.2.circlepath")
                            .accessibilityIdentifier("scan-save-status")
                    } else if viewModel.saveState == .saved {
                        Label("Scan saved", systemImage: "checkmark.circle")
                            .accessibilityIdentifier("scan-save-status")
                    }
                    if result.wasStopped {
                        Text("Scan stopped. Only items measured so far are shown.").foregroundStyle(.orange).lineLimit(1)
                    } else if !viewModel.scanWarnings.isEmpty {
                        Text("Partial scan — see warnings").foregroundStyle(.orange)
                    }
                    Spacer(minLength: 0)
                    Label(insightSettings.activeProviderLabel, systemImage: "sparkles")
                        .lineLimit(1).help("Ask AI provider")
                    Text("·")
                    Text("Allocated size · estimates may include shared blocks").lineLimit(1)
                } else {
                    Label("On your Mac. Under your control.", systemImage: "lock.shield")
                    Spacer(minLength: 0)
                }
            }
            .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.vertical, 9)
        }
        .background(.bar)
    }

    private func deletionMessage(for pending: PendingDeletion) -> String {
        let size = ByteCountFormatter.string(fromByteCount: pending.node.size, countStyle: .file)
        return "\(pending.assessment.risk.title)\n\n\(pending.node.name) • \(size)\n\(pending.node.path)\n\n\(pending.assessment.summary)\n\(pending.assessment.recommendation)"
    }


    private var batchDialogTitle: String {
        guard let pending = viewModel.pendingBatchDeletion else { return "" }
        return pending.requiresStrongConfirmation
            ? String(localized: "Move \(pending.items.count) items, including sensitive data?")
            : String(localized: "Move \(pending.items.count) items to Trash?")
    }

    private var batchButtonTitle: String {
        viewModel.pendingBatchDeletion?.requiresStrongConfirmation == true
            ? String(localized: "I Understand — Move All to Trash")
            : String(localized: "Move All to Trash")
    }

    private func batchMessage(for pending: PendingBatchDeletion) -> String {
        var lines = [ByteCountFormatter.string(fromByteCount: pending.totalBytes, countStyle: .file)]
        lines += pending.items.prefix(6).map { "• \($0.node.name) — \($0.assessment.risk.title)" }
        if pending.items.count > 6 {
            lines.append(String(localized: "and \(pending.items.count - 6) more"))
        }
        if pending.sensitiveCount > 0 {
            lines.append(String(localized: "\(pending.sensitiveCount) items may contain personal or app data."))
        }
        if pending.excludedProtected > 0 {
            lines.append(String(localized: "\(pending.excludedProtected) protected items stay where they are."))
        }
        if pending.excludedNested > 0 {
            lines.append(String(localized: "\(pending.excludedNested) items are inside a queued folder and move with it."))
        }
        lines.append(String(localized: "Each item is checked again just before it moves. Nothing is permanently deleted."))
        return lines.joined(separator: "\n")
    }

    private var deletionDialogTitle: String {
        viewModel.pendingDeletion?.assessment.actionPolicy == .strongConfirmation
            ? String(localized: "Sensitive item — confirm move")
            : String(localized: "Move to Trash?")
    }

    private var deletionButtonTitle: String {
        viewModel.pendingDeletion?.assessment.actionPolicy == .strongConfirmation
            ? String(localized: "I Understand — Move to Trash")
            : String(localized: "Move to Trash")
    }

}

private struct VolumeRow: View {
    let volume: ScanVolume
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: volume.isInternal ? "internaldrive.fill" : "externaldrive.fill")
                .font(.system(size: 13))
                .foregroundStyle(isCurrent ? Color.white : Theme.accent)
                .frame(width: 26, height: 26)
                .background(isCurrent ? Theme.accent : Theme.accent.opacity(0.13),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(volume.name).lineLimit(1).fontWeight(isCurrent ? .semibold : .regular)
                    Spacer(minLength: 4)
                }
                if let usedFraction = volume.usedFraction {
                    CapacityBar(fraction: usedFraction, height: 4)
                        .accessibilityLabel("Current used storage")
                }
                if let free = volume.freeBytes {
                    Text("\(ByteCountFormatter.string(fromByteCount: free, countStyle: .file)) free now")
                        .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                        .help(Text("Physical free space updated \(volume.measuredAt.formatted(date: .abbreviated, time: .shortened)). Reclaimable space is still included in used storage."))
                }
                if let reclaimable = volume.estimatedReclaimableBytes, reclaimable > 0 {
                    Text("Up to \(ByteCountFormatter.string(fromByteCount: reclaimable, countStyle: .file)) more reclaimable")
                        .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                        .help("Reclaimable space is an estimate of what macOS may free automatically. It is still included in used storage.")
                }
                if let total = volume.totalBytes {
                    Text("\(ByteCountFormatter.string(fromByteCount: total, countStyle: .file)) total")
                        .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
                }
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}

/// Clickable ancestors of the focused folder, like Finder's path bar.
private struct PathBar: View {
    let chain: [FileNode]
    let onSelect: (FileNode) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            bar(chain)
            bar(Array(chain.suffix(3)), truncated: chain.count > 3)
            Text(chain.last?.path ?? "").font(.caption).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
        }
    }

    private func bar(_ nodes: [FileNode], truncated: Bool = false) -> some View {
        HStack(spacing: 3) {
            if truncated {
                Text("…").font(.caption).foregroundStyle(.secondary)
                Image(systemName: "chevron.compact.right").font(.caption2).foregroundStyle(.tertiary)
            }
            ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                if index > 0 {
                    Image(systemName: "chevron.compact.right").font(.caption2).foregroundStyle(.tertiary)
                }
                Button(node.name) { onSelect(node) }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(index == nodes.count - 1 ? .primary : .secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .help(chain.last?.path ?? "")
    }
}
