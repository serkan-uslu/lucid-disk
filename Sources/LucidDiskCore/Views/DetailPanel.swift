import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct DetailPanel: View {
    let node: FileNode
    @ObservedObject var viewModel: ScanViewModel
    let onQuickLook: (URL) -> Void
    @StateObject private var inspection = FileInspectionModel()
    @ObservedObject private var insightSettings = InsightSettings.shared
    @ObservedObject private var extensions = LucidDiskExtensions.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                facts
                if let warning = node.scanWarning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let assessment = inspection.assessment {
                    Text(assessment.summary).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if node.isAggregate {
                    Button { viewModel.focus(on: node) } label: {
                        Label("Open Group", systemImage: "folder")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered).controlSize(.large)
                } else {
                    actions
                    insightSection
                }
                ForEach(extensions.inspectorSections) { contribution in
                    contribution.content(node, viewModel.extensionContext)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.background)
        .task(id: node.id) { inspection.select(node) }
        .onDisappear { inspection.clear() }
        .accessibilityIdentifier("file-inspector")
        .disabled(viewModel.isMovingToTrash)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            FileIconView(node: node, size: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(node.name).font(.headline).textSelection(.enabled)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                Text(node.path).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2).truncationMode(.middle).help(node.path)
                if let assessment = inspection.assessment {
                    RiskBadge(risk: assessment.risk).padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var facts: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ByteCountFormatter.string(fromByteCount: node.size, countStyle: .file))
                    .font(.system(.title2, design: .rounded).weight(.semibold)).monospacedDigit()
                Text(node.measurementAccuracy == .incomplete ? node.measurementAccuracy.title : String(localized: "Allocated on disk"))
                    .font(.caption2).foregroundStyle(node.measurementAccuracy == .incomplete ? .orange : .secondary)
            }
            Spacer(minLength: 12)
            if node.logicalSizeBytes != node.allocatedSizeBytes {
                StatView(title: String(localized: "Logical"),
                         value: ByteCountFormatter.string(fromByteCount: node.logicalSizeBytes, countStyle: .file))
                Spacer(minLength: 12)
            }
            if let modifiedAt = node.modifiedAt {
                StatView(title: String(localized: "Modified"),
                         value: modifiedAt.formatted(date: .abbreviated, time: .omitted))
                Spacer(minLength: 12)
            }
            StatView(title: String(localized: "Kind"), value: kindDescription)
        }
        .card(padding: 12)
    }

    private var kindDescription: String {
        if node.isAggregate { return String(localized: "Group") }
        if node.isSymlink { return String(localized: "Alias") }
        if node.isDirectory { return String(localized: "Folder") }
        return node.contentTypeIdentifier.flatMap { UTType($0)?.localizedDescription } ?? String(localized: "File")
    }

    private var actions: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button { onQuickLook(URL(fileURLWithPath: node.path)) } label: {
                    Label("Quick Look", systemImage: "eye").frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("quick-look")
                Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: node.path)]) } label: {
                    Image(systemName: "folder").frame(width: 22)
                }
                .help("Show in Finder").accessibilityLabel("Show in Finder")
                if node.isDirectory {
                    Button { viewModel.focus(on: node) } label: {
                        Image(systemName: "arrow.down.right.and.arrow.up.left").frame(width: 22)
                    }
                    .help("Open Folder").accessibilityLabel("Open Folder")
                }
            }
            .buttonStyle(.bordered)
            let queued = viewModel.isQueued(node)
            Button { viewModel.toggleReview(node: node) } label: {
                Label(queued ? String(localized: "Remove from Review Queue") : String(localized: "Add to Review Queue"),
                      systemImage: queued ? "checkmark.circle.fill" : "plus.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .tint(queued ? Theme.accent : nil)
            .accessibilityIdentifier("review-queue-toggle")
            if queued {
                Button(role: .destructive) { viewModel.requestDeletion(node: node) } label: {
                    Label("Move to Trash", systemImage: "trash").frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("move-to-trash")
                .disabled(inspection.assessment?.allowsTrash != true)
            }
        }
        .controlSize(.large)
    }

    private var insightSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("Lucid Insight", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
                Spacer()
                if inspection.isLoadingInsight {
                    ProgressView().controlSize(.small)
                    Button("Cancel") { inspection.cancelInsight() }
                } else {
                    Button("Ask AI") {
                        inspection.ask(about: node,
                                       service: LocalFileInsightService(configuration: insightSettings.configuration()))
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(inspection.assessment == nil)
                    .accessibilityIdentifier("ask-insight")
                }
            }
            if let insight = inspection.insight {
                Text(insight.probablePurpose).font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                HStack(spacing: 6) {
                    Pill(title: insight.source.title,
                         systemImage: insight.source == .claude ? "cloud" : "lock",
                         color: insight.source == .localRules ? .secondary : Theme.accent)
                    if let model = insight.modelName {
                        Text(model).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text(insight.confidence.title).font(.caption2).foregroundStyle(.secondary)
                }
                if let note = insight.providerNote {
                    Label(note, systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                DisclosureGroup("Evidence and verification") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(insight.evidence + insight.verificationSteps, id: \.self) { item in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("•").foregroundStyle(.tertiary)
                                Text(item).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }.font(.caption).padding(.top, 6)
                }
                .font(.caption)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: insightSettings.provider.sendsDataOffDevice ? "cloud" : "lock")
                    Text(askFootnote)
                }
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card(padding: 14)
    }

    private var askFootnote: String {
        switch insightSettings.provider {
        case .claude:
            String(localized: "Ask AI sends this item’s metadata to \(insightSettings.activeProviderLabel). File contents stay unread.")
        case .rulesOnly:
            String(localized: "Explanations come from local rules. Change this in Settings.")
        default:
            String(localized: "AI runs only when you ask, with \(insightSettings.activeProviderLabel). File contents stay unread.")
        }
    }
}
