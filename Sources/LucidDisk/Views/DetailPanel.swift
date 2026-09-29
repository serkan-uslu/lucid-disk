import SwiftUI
import AppKit

struct DetailPanel: View {
    let node: FileNode
    @ObservedObject var viewModel: ScanViewModel
    let onQuickLook: (URL) -> Void
    @StateObject private var inspection = FileInspectionModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: node.isDirectory ? "folder.fill" : "doc.fill")
                        .font(.title2).foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(node.name).font(.headline).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(node.path).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(2).truncationMode(.middle).help(node.path)
                    }
                    Spacer(minLength: 0)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(ByteCountFormatter.string(fromByteCount: node.size, countStyle: .file))
                        .font(.title2.weight(.semibold)).monospacedDigit()
                    Text(node.measurementAccuracy.title).font(.caption).foregroundStyle(.secondary)
                }
                if node.logicalSizeBytes != node.allocatedSizeBytes {
                    Text("Logical: \(ByteCountFormatter.string(fromByteCount: node.logicalSizeBytes, countStyle: .file))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let warning = node.scanWarning {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
                if let assessment = inspection.assessment {
                    Label(assessment.risk.title, systemImage: assessment.risk.systemImage)
                        .font(.caption.weight(.semibold)).foregroundStyle(assessment.risk.color)
                    Text(assessment.summary).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if node.isAggregate {
                    Button { viewModel.focus(on: node) } label: {
                        Label("Open Group", systemImage: "folder")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    actions
                    Divider()
                    insightSection
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
            Button { viewModel.toggleReview(node: node) } label: {
                Label(viewModel.isQueued(node) ? String(localized: "Remove from Review Queue") : String(localized: "Add to Review Queue"),
                      systemImage: viewModel.isQueued(node) ? "checkmark.circle.fill" : "plus.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("review-queue-toggle")
            if viewModel.isQueued(node) {
                Button(role: .destructive) { viewModel.requestDeletion(node: node) } label: {
                    Label("Move to Trash", systemImage: "trash").frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityIdentifier("move-to-trash")
                .disabled(inspection.assessment?.allowsTrash != true)
            }
        }
        .buttonStyle(.bordered).controlSize(.large)
    }

    private var insightSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Lucid Insight", systemImage: "sparkles").font(.subheadline.weight(.semibold))
                Spacer()
                if inspection.isLoadingInsight {
                    ProgressView().controlSize(.small)
                    Button("Cancel") { inspection.cancelInsight() }
                } else {
                    Button("Ask AI") { inspection.ask(about: node) }
                        .disabled(inspection.assessment == nil)
                        .accessibilityIdentifier("ask-insight")
                }
            }
            if let insight = inspection.insight {
                Text(insight.probablePurpose).font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(insight.source.title).font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("Evidence and verification") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(insight.evidence + insight.verificationSteps, id: \.self) { Text($0) }
                    }.font(.caption).padding(.top, 6)
                }
            } else {
                Text("AI runs only when you ask. File contents stay unread.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
