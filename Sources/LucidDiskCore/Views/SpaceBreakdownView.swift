import AppKit
import SwiftUI

/// Only the physical capacity determines this bar. Per-file allocation estimates
/// can overlap on APFS and must not change the visible proportion of free space.
struct SpaceCapacityBarMetrics {
    let usedFraction: Double
    let freeFraction: Double

    init(breakdown: SpaceBreakdown) {
        guard breakdown.capacityBytes > 0 else {
            usedFraction = 0
            freeFraction = 0
            return
        }
        usedFraction = min(1, max(0, Double(breakdown.usedBytes) / Double(breakdown.capacityBytes)))
        freeFraction = 1 - usedFraction
    }
}

/// Explains a volume's used space, including what a scan cannot see.
struct SpaceBreakdownView: View {
    let breakdown: SpaceBreakdown
    var measuredAt: Date? = nil
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Disk Space Breakdown").font(.title2.weight(.semibold))
                Text("\(breakdown.volumeName) · \(format(breakdown.usedBytes)) used of \(format(breakdown.capacityBytes)) · \(format(breakdown.freeBytes)) free")
                    .foregroundStyle(.secondary)
                if let measuredAt {
                    Text("Disk usage captured \(measuredAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("These disk totals were measured after the scan. The sidebar and Home refresh current free space separately.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding([.horizontal, .top], 24)

            VStack(spacing: 8) {
                GeometryReader { geo in
                    let metrics = SpaceCapacityBarMetrics(breakdown: breakdown)
                    HStack(spacing: 0) {
                        Rectangle().fill(Theme.accent)
                            .frame(width: geo.size.width * metrics.usedFraction)
                        Rectangle().fill(Color.primary.opacity(0.08))
                            .frame(width: geo.size.width * metrics.freeFraction)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .frame(height: 22)
                .accessibilityHidden(true)
                HStack {
                    Label("Used space", systemImage: "circle.fill")
                        .foregroundStyle(Theme.accent)
                    Spacer()
                    Label("Free space", systemImage: "circle")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
            .padding(24)

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
                        Label("Up to \(format(purgeable)) more may be reclaimed by macOS. This estimate is already included in used space.",
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
                    .accessibilityIdentifier("close-space-breakdown")
            }
            .padding(16)
        }
        .frame(width: 640, height: 600)
        .accessibilityIdentifier("space-breakdown-sheet")
        .onExitCommand(perform: onDone)
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
