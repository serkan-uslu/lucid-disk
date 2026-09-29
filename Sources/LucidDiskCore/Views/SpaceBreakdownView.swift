import AppKit
import SwiftUI

/// Explains a volume's used space, including what a scan cannot see.
struct SpaceBreakdownView: View {
    let breakdown: SpaceBreakdown
    let onDone: () -> Void

    private struct Segment: Identifiable {
        let id: String
        let bytes: Int64
        let color: Color
    }

    private var segments: [Segment] {
        var segments = breakdown.items.filter { $0.kind != .sharedBlocks }.map {
            Segment(id: $0.id, bytes: $0.bytes, color: color(for: $0))
        }
        segments.append(Segment(id: "free", bytes: breakdown.freeBytes, color: Color.primary.opacity(0.08)))
        return segments
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Where your space goes").font(.title2.weight(.semibold))
                Text("\(breakdown.volumeName) · \(format(breakdown.usedBytes)) used of \(format(breakdown.capacityBytes)) · \(format(breakdown.freeBytes)) free")
                    .foregroundStyle(.secondary)
            }
            .padding([.horizontal, .top], 24)

            GeometryReader { geo in
                let total = max(1, Double(segments.reduce(0) { $0 + $1.bytes }))
                HStack(spacing: 2) {
                    ForEach(segments) { segment in
                        Rectangle().fill(segment.color)
                            .frame(width: max(3, (geo.size.width - CGFloat(segments.count * 2)) * Double(segment.bytes) / total))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .frame(height: 22)
            .padding(24)
            .accessibilityHidden(true)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(breakdown.items) { item in
                        HStack(alignment: .top, spacing: 12) {
                            Circle().fill(color(for: item)).frame(width: 10, height: 10).padding(.top, 5)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(item.title).font(.headline)
                                    Spacer()
                                    Text(format(item.bytes)).font(.headline).monospacedDigit()
                                }
                                Text(item.detail).font(.callout).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .card(padding: 12)
                    }
                    if let purgeable = breakdown.purgeableBytes, purgeable > 0 {
                        Label("Up to \(format(purgeable)) is purgeable: macOS frees it automatically when an app needs the space.",
                              systemImage: "arrow.3.trianglepath")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    if breakdown.unreadableFolderCount > 0 {
                        HStack {
                            Label("\(breakdown.unreadableFolderCount) folders could not be read.", systemImage: "lock")
                                .font(.callout)
                            Spacer()
                            Button("Open Full Disk Access Settings") {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
            }

            Divider()
            HStack {
                Label("Sizes come from macOS. Volumes it manages are listed so you know what they are; Lucid Disk never changes them.",
                      systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Done", action: onDone).keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 640, height: 600)
        .accessibilityIdentifier("space-breakdown-sheet")
    }

    private func color(for item: SpaceBreakdown.Item) -> Color {
        switch item.kind {
        case .scanned: Theme.accent
        case .otherVolume: Color(hue: 0.76, saturation: 0.45, brightness: 0.85)
        case .notVisible: Color.orange.opacity(0.75)
        case .sharedBlocks: Color.secondary
        }
    }

    private func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
