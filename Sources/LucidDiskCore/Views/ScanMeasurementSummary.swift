import SwiftUI

/// A value snapshot of the displayed scope and whole-scan completeness. A folder
/// can be complete even when another part of the scan was unreadable or stopped.
struct ScanMeasurementPresentation {
    enum Status: Equatable {
        case partial, stopped
        var title: String {
            switch self {
            case .partial: String(localized: "Partial scan")
            case .stopped: String(localized: "Scan stopped")
            }
        }
        var explanation: String {
            switch self {
            case .partial: String(localized: "This scan is incomplete. Some locations were unreadable or skipped; see Scan Warnings.")
            case .stopped: String(localized: "Scan stopped. Only items measured so far are shown.")
            }
        }
    }

    let scopeName: String
    let allocatedBytes: Int64
    let itemCount: Int
    let scopeIsIncomplete: Bool
    let status: Status?
    let savedAt: Date?

    init(focused: FileNode, root: FileNode, wasStopped: Bool, savedAt: Date?) {
        scopeName = Self.scopeName(for: focused)
        allocatedBytes = focused.allocatedSizeBytes
        itemCount = focused.isAggregate ? focused.aggregatedChildren.count : focused.children.count
        scopeIsIncomplete = focused.measurementAccuracy == .incomplete ||
            (focused.isAggregate && focused.aggregatedChildren.contains { $0.measurementAccuracy == .incomplete })
        // Saved scans retain completeness, but do not persist the stopped flag.
        status = wasStopped && savedAt == nil ? .stopped :
            (root.measurementAccuracy == .incomplete || scopeIsIncomplete ? .partial : nil)
        self.savedAt = savedAt
    }

    static func scopeName(for node: FileNode) -> String {
        node.isAggregate ? String(localized: "Other items in \(node.parent?.name ?? node.path)") : node.name
    }

    static var allocationHelp: String {
        String(localized: "Estimated allocation measured in this scope. Shared APFS blocks can be counted in more than one file, so this is neither total disk usage nor guaranteed space you can reclaim.")
    }
}

struct ScanMeasurementSummary: View {
    let measurement: ScanMeasurementPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 16) {
                StatView(title: String(localized: "Measured allocation"),
                         value: ByteCountFormatter.string(fromByteCount: measurement.allocatedBytes, countStyle: .file))
                    .help(ScanMeasurementPresentation.allocationHelp)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Measured allocation for \(measurement.scopeName)"))
                    .accessibilityValue(ByteCountFormatter.string(fromByteCount: measurement.allocatedBytes, countStyle: .file))
                Spacer(minLength: 0)
                StatView(title: String(localized: "Items"), value: measurement.itemCount.formatted())
            }
            if measurement.status != nil || measurement.savedAt != nil {
                HStack(spacing: 8) {
                    if let status = measurement.status {
                        Pill(title: status.title, systemImage: "exclamationmark.triangle", color: .orange)
                            .help(status.explanation)
                            .accessibilityIdentifier("scan-completeness")
                    }
                    if let savedAt = measurement.savedAt {
                        Pill(title: String(localized: "Saved scan"), systemImage: "clock.arrow.circlepath", color: .secondary)
                            .help(Text("Saved scan from \(savedAt.formatted(.relative(presentation: .named)))"))
                    }
                }
            }
        }
        .accessibilityIdentifier("scan-measurement-summary")
    }
}
