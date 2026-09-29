import SwiftUI

/// Inspector for several selected items: totals, risk mix and batch queue actions.
struct BatchSelectionPanel: View {
    let nodes: [FileNode]
    @ObservedObject var viewModel: ScanViewModel
    @State private var riskCounts: [DeletionRisk: Int] = [:]
    @State private var outcome: BatchQueueOutcome?

    private var totalBytes: Int64 { ScanViewModel.topLevelItems(nodes).reduce(0) { $0 + $1.size } }
    private var queuedCount: Int { nodes.filter { viewModel.isQueued($0) }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: "square.stack.3d.up.fill").foregroundStyle(Theme.accent)
                    Text("\(nodes.count) items selected").font(.headline)
                    Spacer()
                    Button("Clear Selection") { viewModel.select([], primary: nil) }
                        .buttonStyle(.borderless).font(.caption)
                }
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))
                            .font(.system(.title2, design: .rounded).weight(.semibold)).monospacedDigit()
                        Text("Allocated on disk").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if queuedCount > 0 {
                        StatView(title: String(localized: "In queue"), value: queuedCount.formatted())
                    }
                }
                .card(padding: 12)

                if !riskCounts.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(DeletionRisk.allCasesByRisk, id: \.self) { risk in
                            if let count = riskCounts[risk], count > 0 {
                                Pill(title: "\(count) \(risk.title)", systemImage: risk.systemImage, color: risk.color)
                            }
                        }
                    }
                }

                Button {
                    outcome = viewModel.addToReview(nodes)
                } label: {
                    Label("Add \(nodes.count) to Review Queue", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered).controlSize(.large)
                .accessibilityIdentifier("batch-add-to-queue")
                if queuedCount > 0 {
                    Button {
                        viewModel.removeFromReview(nodes)
                        outcome = nil
                    } label: {
                        Label("Remove \(queuedCount) from Review Queue", systemImage: "minus.circle")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered).controlSize(.large)
                }
                if let outcome { outcomeText(outcome) }

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(nodes.prefix(8), id: \.id) { node in
                        HStack(spacing: 8) {
                            FileIconView(node: node, size: 18)
                            Text(node.name).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: node.size, countStyle: .file))
                                .foregroundStyle(.secondary).monospacedDigit()
                        }
                        .font(.caption)
                    }
                    if nodes.count > 8 {
                        Text("and \(nodes.count - 8) more").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("Queued items move to the Trash only after you confirm, and each is checked again first.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.background)
        .accessibilityIdentifier("batch-inspector")
        .task(id: nodes.map(\.id)) {
            outcome = nil
            let snapshot = nodes
            let counts = await Task.detached(priority: .userInitiated) {
                snapshot.reduce(into: [DeletionRisk: Int]()) { counts, node in
                    counts[DeletionSafety.assess(node: node).risk, default: 0] += 1
                }
            }.value
            guard !Task.isCancelled else { return }
            riskCounts = counts
        }
    }

    @ViewBuilder
    private func outcomeText(_ outcome: BatchQueueOutcome) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Added \(outcome.added) to the queue.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            if outcome.alreadyQueued > 0 { Text("\(outcome.alreadyQueued) were already queued.") }
            if outcome.skippedProtected > 0 { Text("\(outcome.skippedProtected) protected items were skipped.") }
            if outcome.skippedGroups > 0 { Text("\(outcome.skippedGroups) “Other” groups were skipped; open them to pick items.") }
        }
        .font(.caption).foregroundStyle(.secondary)
    }
}

extension DeletionRisk {
    static let allCasesByRisk: [DeletionRisk] = [.rebuildable, .review, .sensitive, .protected]
}
