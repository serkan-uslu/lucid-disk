import SwiftUI

/// Live values get fixed layout slots; only the small activity mark animates.
struct ScanProgressView: View {
    let count: Int
    let bytes: Int64
    let path: String
    let targetPath: String
    let startedAt: Date?
    let isStopping: Bool
    let onCancel: () -> Void
    var animatesActivity = true
    @State private var tip: ScanWaitingTip = .explore

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    ScanProgressMetrics(count: count, bytes: bytes)
                    location
                    Text("File allocations are estimates. Shared APFS blocks can make their sum exceed disk capacity; this is not reclaimable space.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    waitingGuide
                }
                .padding(20)
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            stopControls
                .padding(.horizontal, 20).padding(.vertical, 12)
                .frame(maxWidth: 700).frame(maxWidth: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    private var stopControls: some View {
        HStack(spacing: 16) {
            Button(action: onCancel) {
                Label(isStopping ? String(localized: "Preparing results…") : String(localized: "Stop Scan"),
                      systemImage: isStopping ? "hourglass" : "stop.circle")
                    .frame(width: 180)
            }
            .buttonStyle(.bordered).controlSize(.large)
            .disabled(isStopping)
            .help("Stop scanning and show the items already scanned")
            .accessibilityIdentifier("progress-stop-scan")
            Text("Stopping keeps the items measured so far.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            ScanningRings(isAnimating: animatesActivity)
            VStack(alignment: .leading, spacing: 6) {
                Text("Mapping your storage").font(.title2.weight(.semibold))
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(verbatim: targetPath).font(.callout).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle).help(targetPath)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 6) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(ScanElapsedTime.format(startedAt.map { context.date.timeIntervalSince($0) } ?? 0))
                        .font(.system(.title3, design: .rounded).weight(.medium)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .contentTransition(.identity)
                }
                Text("Elapsed").font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 84, alignment: .trailing)
        }
        .frame(height: 64)
    }

    private var location: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(isStopping ? String(localized: "Keeping measured results") : String(localized: "Currently scanning"),
                  systemImage: isStopping ? "checkmark.circle" : "folder")
                .font(.callout.weight(.medium)).foregroundStyle(Theme.accent)
            Text(path.isEmpty ? String(localized: "Preparing the scan…") : path)
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading).frame(height: 18)
                .help(path).textSelection(.enabled)
        }
        .frame(height: 48, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    private var waitingGuide: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("While you wait").font(.headline)
            Picker("While you wait", selection: $tip) {
                ForEach(ScanWaitingTip.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .labelsHidden().pickerStyle(.segmented)
            // Reserve the tallest localized tip so selecting a tab cannot move Stop.
            ZStack(alignment: .topLeading) {
                ForEach(ScanWaitingTip.allCases) { item in
                    Text(item.detail).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .opacity(tip == item ? 1 : 0)
                        .accessibilityHidden(tip != item)
                }
            }
        }
        .card(padding: 16)
    }
}

struct ScanProgressMetrics: View {
    let count: Int
    let bytes: Int64

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            metric(count.formatted(), title: "Files scanned")
            metric(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file), title: "Estimated file allocation")
        }
        .card(padding: 18)
    }

    private func metric(_ value: String, title: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value).font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6).contentTransition(.identity)
                .frame(height: 36, alignment: .leading)
            Text(title).font(.caption).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.8).frame(height: 18, alignment: .topLeading)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

enum ScanWaitingTip: Int, CaseIterable, Identifiable {
    case explore, search, assistant
    var id: Self { self }
    var title: LocalizedStringKey {
        switch self {
        case .explore: return "Disk map"
        case .search: return "Search & export"
        case .assistant: return "Ask an assistant"
        }
    }
    var detail: LocalizedStringKey {
        switch self {
        case .explore: return "After scanning, open a folder in the disk map to see where its space goes. Parent Folder takes you back up."
        case .search: return "Use search and size filters to find large items. Export the results as a folder tree for a quick overview."
        case .assistant: return "Select an item and choose Copy Metadata to discuss it with Codex or Claude. With MCP connected, your assistant can check the current item."
        }
    }
}

enum ScanElapsedTime {
    static func format(_ elapsed: TimeInterval) -> String {
        let seconds = Int(min(max(elapsed.isFinite ? elapsed : 0, 0), 359_999))
        if seconds >= 3600 {
            return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
        }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

/// Draw arcs about the canvas center instead of rotating the asymmetric bounds
/// of a trimmed SwiftUI shape. The stroke stays inside its fixed 64-point square.
struct ScanningRings: View {
    var isAnimating = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || !isAnimating)) { timeline in
            Canvas { context, size in
                let time = reduceMotion || !isAnimating ? 0 : timeline.date.timeIntervalSinceReferenceDate
                for index in 0..<2 {
                    context.stroke(Self.arc(index: index, time: time, size: size),
                                   with: .color(Theme.accent.opacity(index == 0 ? 1 : 0.5)),
                                   style: StrokeStyle(lineWidth: 4, lineCap: .round))
                }
            }
        }
        .frame(width: 64, height: 64)
        .accessibilityHidden(true)
    }

    static func arc(index: Int, time: TimeInterval, size: CGSize) -> Path {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = max(0, min(size.width, size.height) / 2 - 6 - CGFloat(index) * 10)
        let period = index == 0 ? 3.2 : 4.8
        let degrees = time.truncatingRemainder(dividingBy: period) / period * 360 * (index == 0 ? 1 : -1)
        var path = Path()
        path.addArc(center: center, radius: radius, startAngle: .degrees(degrees - 90),
                    endAngle: .degrees(degrees + (index == 0 ? 150 : 70)), clockwise: false)
        return path
    }
}
