// Hidden-window rendering of deterministic fixtures. No windows are displayed or personal scans loaded.
import AppKit
import SwiftUI

@main @MainActor
struct PresentationReview {
    static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        let locale = Locale(identifier: UserDefaults.standard.stringArray(forKey: "AppleLanguages")?.first ?? "en")
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let breakdown = SpaceBreakdown(volumeName: "Macintosh HD", capacityBytes: 994_660_000_000,
            usedBytes: 972_550_000_000, freeBytes: 22_110_000_000, scannedBytes: 925_790_000_000,
            items: [.init(id: "scan", kind: .scanned, title: String(localized: "Estimated file allocation"), bytes: 925_790_000_000,
                          detail: String(localized: "File allocations are estimates. Shared APFS blocks can make their sum exceed disk capacity; this is not reclaimable space.")),
                    .init(id: "outside", kind: .notVisible, title: String(localized: "Used, but not visible to the scan"), bytes: 46_760_000_000,
                          detail: String(localized: "Everything the scan could open and measure."))],
            purgeableBytes: 4_910_000_000, localSnapshotCount: 1, unreadableFolderCount: 1073)
        try render(SpaceBreakdownView(breakdown: breakdown, measuredAt: Date(timeIntervalSince1970: 1_790_000_000), onDone: {}).environment(\.locale, locale),
                   size: NSSize(width: 640, height: 600), to: output.appendingPathComponent("space-breakdown.png"))
        let volume = ScanVolume(url: URL(fileURLWithPath: "/"), name: "Macintosh HD", totalBytes: 994_660_000_000,
                                freeBytes: 22_110_000_000, availableForImportantUsageBytes: 27_020_000_000,
                                isInternal: true, isRemovable: false)
        try render(WelcomeView(volumes: [volume], onScan: { _ in }, onChooseFolder: {}).environment(\.locale, locale),
                   size: NSSize(width: 920, height: 1350), to: output.appendingPathComponent("welcome-capacity.png"))
        let root = FileNode(name: "Macintosh HD", path: "/", isDirectory: true, size: 925_790_000_000, measurementAccuracy: .incomplete)
        var warnings = (0..<1073).map { index in
            ScanWarning(path: "/Users/demo/Library/Application Support/Creative Studio/Project Archives/Folder-\(index)",
                        message: index.isMultiple(of: 2) ? String(localized: "This directory could not be read.")
                            : String(localized: "This directory was already visited through another path and was not counted again."))
        }
        warnings[1] = ScanWarning(path: warnings[0].path, message: warnings[1].message)
        warnings[1072] = ScanWarning(path: "/Users/demo/Library/Application Support/Creative Studio/Project Archives/Long project name/Previous versions/Final-warning-location",
                                    message: String(localized: "This directory could not be read."))
        let warningSnapshot = ScanWarningsPresentation(root: root, warnings: warnings, wasStopped: false,
                                                       savedAt: Date(timeIntervalSince1970: 1_790_000_000))
        try render(ScanWarningsButton(count: warnings.count, onOpen: {}).padding(12).environment(\.locale, locale),
                   size: NSSize(width: 180, height: 80), to: output.appendingPathComponent("warnings-sidebar-180.png"))
        for (name, query) in [("warnings-all", ""), ("warnings-last", "Final-warning-location"), ("warnings-no-match", "no-such-warning")] {
            try render(ScanWarningsSheet(presentation: warningSnapshot, query: query).environment(\.locale, locale),
                       size: NSSize(width: 740, height: 590), to: output.appendingPathComponent(name + ".png"))
        }
        let stoppedWarnings = ScanWarningsPresentation(root: root, warnings: warnings, wasStopped: true, savedAt: nil)
        try render(ScanWarningsSheet(presentation: stoppedWarnings).environment(\.locale, locale),
                   size: NSSize(width: 740, height: 590), to: output.appendingPathComponent("warnings-stopped.png"))
        let folder = FileNode(name: "Projects", path: "/Users/demo/Projects", isDirectory: true, size: 160_000_000_000)
        folder.parent = root
        root.children = [folder]
        folder.children = (0..<8).map { index in
            let child = FileNode(name: "Folder \(index)", path: folder.path + "/Folder-\(index)", isDirectory: true, size: Int64(8 - index) * 3_000_000_000)
            child.parent = folder
            return child
        }
        let remaining = FileNode(name: "Media", path: folder.path + "/Media", isDirectory: true, size: 52_000_000_000)
        remaining.parent = folder; folder.children.append(remaining)
        let system = FileNode(name: "System", path: "/System", isDirectory: true, size: root.size - folder.size)
        system.parent = root; root.children.append(system)
        for (name, node, stopped, saved, size) in [
            ("root-compact", root, false, Optional<Date>.none, NSSize(width: 390, height: 440)),
            ("folder-compact", folder, true, Optional<Date>.none, NSSize(width: 390, height: 440)),
            ("saved-compact", folder, false, Optional(Date(timeIntervalSince1970: 1_790_000_000)), NSSize(width: 390, height: 440)),
            ("root-wide", root, false, Optional<Date>.none, NSSize(width: 760, height: 700))
        ] {
            try render(VStack(alignment: .leading, spacing: 10) {
                Text(node.name).font(.title2.weight(.semibold))
                ScanMeasurementSummary(measurement: ScanMeasurementPresentation(focused: node, root: root, wasStopped: stopped, savedAt: saved))
                SunburstView(focusedNode: node, wedges: computeWedges(focusedNode: node), selectedNode: nil, selectedIDs: [],
                             onZoomOut: {}, onSelect: { _ in }, onFocus: { _ in })
            }.padding(16).environment(\.locale, locale), size: size, to: output.appendingPathComponent(name + ".png"))
        }
        let model = ScanViewModel(mountedVolumesProvider: { [] })
        model.rootNode = root; model.focusedNode = root
        model.select([folder], primary: folder)
        model.snapshotDate = Date(timeIntervalSince1970: 1_790_000_000)
        model.showSampleVolumes([volume])
        try render(ContentView(viewModel: model, showingDetails: true).environment(\.locale, locale),
                   size: NSSize(width: 1050, height: 640), to: output.appendingPathComponent("details-minimum.png"))
        for (name, scanned) in [("outside", Int64(925_790_000_000)), ("matching", 972_550_000_000), ("excess", 1_500_000_000_000)] {
            let sample = SpaceBreakdown(volumeName: breakdown.volumeName, capacityBytes: breakdown.capacityBytes,
                usedBytes: breakdown.usedBytes, freeBytes: breakdown.freeBytes, scannedBytes: scanned,
                items: [], purgeableBytes: nil, localSnapshotCount: nil, unreadableFolderCount: 0)
            try render(ScanNavigationActions(canGoToParent: true,
                       diskSpace: DiskSpacePresentation(breakdown: sample, scanRootPath: "/"), onParent: {}, onBreakdown: {})
                       .padding(16).environment(\.locale, locale), size: NSSize(width: 320, height: 170),
                       to: output.appendingPathComponent("navigation-" + name + ".png"))
        }
        model.snapshotDate = nil; model.showSampleSpaceBreakdown(breakdown)
        model.focus(on: folder)
        try render(ContentView(viewModel: model).environment(\.locale, locale),
                   size: NSSize(width: 1050, height: 640), to: output.appendingPathComponent("folder-disk-scope-minimum.png"))
        print("Rendered \(output.path) without displaying a window")
    }
    static func render<V: View>(_ view: V, size: NSSize, to url: URL) throws {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: view.preferredColorScheme(.dark)
            .frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor)))
        hosting.sizingOptions = []
        window.contentView = hosting
        window.setContentSize(size)
        for _ in 0..<8 { RunLoop.main.run(until: Date().addingTimeInterval(0.03)); hosting.layoutSubtreeIfNeeded() }
        guard !window.isVisible, hosting.bounds.size == size,
              let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { throw NSError(domain: "Review", code: 2) }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw NSError(domain: "Review", code: 3) }
        try data.write(to: url)
        window.close()
    }
}
