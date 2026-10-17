import SwiftUI

struct DiskSpacePresentation {
    enum Difference: Equatable {
        case outsideScan(Int64), matchesUsedSpace, allocationExcess(Int64)
    }
    let volumeName: String
    let scanRootPath: String
    let difference: Difference

    init(breakdown: SpaceBreakdown, scanRootPath: String) {
        volumeName = breakdown.volumeName
        self.scanRootPath = scanRootPath
        if breakdown.scannedBytes > breakdown.usedBytes {
            difference = .allocationExcess(breakdown.scannedBytes - breakdown.usedBytes)
        } else if breakdown.scannedBytes < breakdown.usedBytes {
            difference = .outsideScan(breakdown.usedBytes - breakdown.scannedBytes)
        } else {
            difference = .matchesUsedSpace
        }
    }

    var explanation: String {
        switch difference {
        case .outsideScan(let bytes):
            String(localized: "\(format(bytes)) used outside this scan")
        case .matchesUsedSpace:
            String(localized: "Measured allocation matches reported used space")
        case .allocationExcess(let bytes):
            String(localized: "Allocation estimate exceeds used space by \(format(bytes))")
        }
    }

    var help: String {
        String(localized: "Disk totals for \(volumeName), compared with the root scan at \(scanRootPath). These figures keep the whole-disk scope when you open a folder.")
    }

    private func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

struct ScanNavigationActions: View {
    let canGoToParent: Bool
    let diskSpace: DiskSpacePresentation?
    let onParent: () -> Void
    let onBreakdown: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { buttons }
                VStack(alignment: .leading, spacing: 6) { buttons }
            }
            if let diskSpace {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Whole disk: \(diskSpace.volumeName)").fontWeight(.medium)
                    Text(diskSpace.explanation)
                }
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .help(diskSpace.help)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("space-breakdown-scope")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var buttons: some View {
        Button(action: onParent) { Label("Parent Folder", systemImage: "chevron.left") }
            .buttonStyle(.bordered).controlSize(.small).fixedSize()
            .disabled(!canGoToParent)
            .help("Back to parent folder")
            .keyboardShortcut(.leftArrow, modifiers: .command)
        if let diskSpace {
            Button(action: onBreakdown) {
                Label("Disk Space Breakdown", systemImage: "chart.bar.doc.horizontal")
            }
            .buttonStyle(.bordered).controlSize(.small).fixedSize()
            .help(diskSpace.help)
            .accessibilityIdentifier("space-breakdown")
        }
    }
}
