import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel: ScanViewModel
    @ObservedObject private var insightSettings = InsightSettings.shared
    @ObservedObject private var extensions = LucidDiskExtensions.shared
    @State private var wedges: [Wedge] = []
    @State private var quickLookItem: QuickLookItem?

    @MainActor
    init(viewModel: ScanViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? ScanViewModel())
    }

    var body: some View {
      VStack(spacing: 0) {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        statusBar
      }
        .navigationTitle(extensions.edition.displayName)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    viewModel.startScan(path: "/")
                } label: {
                    Label("Scan Startup Disk", systemImage: "internaldrive")
                }
                .accessibilityIdentifier("scan-startup-disk")
                .disabled(viewModel.isScanning || viewModel.isMovingToTrash)

                Button {
                    chooseFolder()
                } label: {
                    Label("Choose Folder", systemImage: "folder.badge.plus")
                }
                .accessibilityIdentifier("choose-folder")
                .keyboardShortcut("o", modifiers: .command)
                .disabled(viewModel.isScanning || viewModel.isMovingToTrash)

                Button {
                    if let path = viewModel.rootNode?.path { viewModel.startScan(path: path) }
                } label: {
                    Label("Scan Again", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
                .help("Scan Again")
                .disabled(viewModel.rootNode == nil || viewModel.isScanning || viewModel.isMovingToTrash)

                Button { AppSupport.shared.show(.guide) } label: {
                    Label("How to Use", systemImage: "questionmark.circle")
                }
                .help("How to Use")
                .accessibilityIdentifier("show-help")

                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Settings")
                .accessibilityIdentifier("show-settings")

                if viewModel.isScanning {
                    Button(role: .destructive) {
                        viewModel.cancelScan()
                    } label: {
                        Label("Stop", systemImage: "stop.circle")
                    }
                    .accessibilityIdentifier("stop-scan")
                }
            }
        }
        .task(id: viewModel.focusedNode?.id) {
            wedges = []
            guard let focused = viewModel.focusedNode else { return }
            let worker = Task.detached(priority: .userInitiated) {
                let result = computeWedges(focusedNode: focused)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard viewModel.focusedNode?.id == focused.id else { return }
                    wedges = result
                }
            }
            await withTaskCancellationHandler {
                await worker.value
            } onCancel: { worker.cancel() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { viewModel.refreshMountedVolumes() }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in
            viewModel.refreshMountedVolumes()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in
            viewModel.refreshMountedVolumes()
        }
        .onKeyPress(.space) {
            guard let node = viewModel.selectedNode, !node.isAggregate else { return .ignored }
            quickLookItem = QuickLookItem(url: URL(fileURLWithPath: node.path))
            return .handled
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
    }

    private var sidebar: some View {
        List {
            Section("Volumes") {
                ForEach(viewModel.mountedVolumes) { volume in
                    Button {
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
                                viewModel.selectedNode = node
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
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove from review queue")
                        }
                    }
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
                             path: viewModel.currentPath, onCancel: viewModel.cancelScan)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        } else if let focused = viewModel.focusedNode {
            GeometryReader { area in
              let inspectorWidth = min(460, max(340, area.size.width * 0.43))
              HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center, spacing: 12) {
                        Button { viewModel.zoomOut() } label: {
                            Image(systemName: "chevron.left").font(.body.weight(.semibold))
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.borderless)
                        .background(Theme.cardFill, in: Circle())
                        .disabled(focused.parent == nil)
                        .help("Back to parent folder")
                        .keyboardShortcut(.leftArrow, modifiers: .command)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(focused.name).font(.title2.weight(.semibold)).lineLimit(1)
                            PathBar(chain: ancestorChain(from: focused)) { viewModel.focus(on: $0) }
                        }
                        Spacer(minLength: 8)
                        if area.size.width > 1_000 {
                            HStack(spacing: 18) {
                                StatView(title: String(localized: "Allocated"),
                                         value: ByteCountFormatter.string(fromByteCount: focused.allocatedSizeBytes, countStyle: .file))
                                StatView(title: String(localized: "Items"),
                                         value: (focused.isAggregate ? focused.aggregatedChildren.count : focused.children.count).formatted())
                                if focused.measurementAccuracy == .incomplete {
                                    Pill(title: String(localized: "Partial"), systemImage: "exclamationmark.triangle", color: .orange)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 6)
                    SunburstView(
                        focusedNode: focused,
                        wedges: wedges,
                        selectedNode: viewModel.selectedNode,
                        onZoomOut: { viewModel.zoomOut() },
                        onSelect: { node in viewModel.selectedNode = node },
                        onFocus: { node in viewModel.focus(on: node) }
                    )
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    Text("Click a folder to open it. Click a file to inspect it.")
                        .font(.caption).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity).padding(.bottom, 14)
                }
                .frame(width: max(0, area.size.width - inspectorWidth - 1), height: area.size.height)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipped()
                Divider()
                VStack(spacing: 0) {
                    PieContentsPanel(
                        focusedNode: focused,
                        searchRoot: viewModel.rootNode ?? focused,
                        selectedNode: viewModel.selectedNode,
                        onSelect: { node in viewModel.selectedNode = node },
                        onFocus: { node in viewModel.focus(on: node) },
                        onPreview: { node in quickLookItem = QuickLookItem(url: URL(fileURLWithPath: node.path)) }
                    )
                    .frame(minHeight: 200, maxHeight: .infinity)
                    if let selected = viewModel.selectedNode {
                        Divider()
                        DetailPanel(node: selected, viewModel: viewModel,
                                    onQuickLook: { quickLookItem = QuickLookItem(url: $0) })
                            .id(selected.id)
                            .frame(height: min(460, max(300, area.size.height * 0.54)))
                    }
                }
                .frame(width: inspectorWidth, height: area.size.height)
                .clipped()
              }
            }
        } else {
            WelcomeView(volumes: viewModel.mountedVolumes,
                        onScan: { viewModel.startScan(path: $0) },
                        onChooseFolder: chooseFolder)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.startScan(path: url.path)
        }
    }

    private var statusBar: some View {
        VStack(spacing: 0) {
            Divider()
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
                    Button { viewModel.completionMessage = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).accessibilityLabel("Dismiss notification")
                } else if let result = viewModel.lastScanResult, !viewModel.isScanning {
                    Image(systemName: viewModel.scanWarnings.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(viewModel.scanWarnings.isEmpty ? Theme.accent : .orange)
                    Text("\(result.statistics.scannedFileCount) files · \(String(format: "%.2f", result.duration)) s")
                        .monospacedDigit()
                    if !viewModel.scanWarnings.isEmpty {
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

private extension ScanVolume {
    var usedFraction: Double? {
        guard let totalBytes, let availableBytes, totalBytes > 0 else { return nil }
        return min(1, max(0, Double(totalBytes - availableBytes) / Double(totalBytes)))
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
                    if let total = volume.totalBytes {
                        Text(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                if let usedFraction = volume.usedFraction {
                    CapacityBar(fraction: usedFraction, height: 4)
                        .accessibilityLabel("Used storage")
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
