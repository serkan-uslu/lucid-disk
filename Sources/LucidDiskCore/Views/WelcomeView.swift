import SwiftUI

struct WelcomeView: View {
    @Environment(\.openSettings) private var openSettings
    let volumes: [ScanVolume]
    var savedScans: [SavedScanInfo] = []
    var isOpeningSavedScan = false
    let onScan: (String) -> Void
    var onOpenSaved: (SavedScanInfo) -> Void = { _ in }
    let onChooseFolder: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(alignment: .center, spacing: 28) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("YOUR SPACE, CLEARLY.")
                                .font(.caption.weight(.semibold)).tracking(2).foregroundStyle(Theme.accent)
                            Text("Make room for\nwhat matters.")
                                .font(.system(size: 38, weight: .semibold, design: .rounded))
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Explore your storage. Understand your files. Choose what goes.")
                                .font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Button(action: onChooseFolder) {
                                Label("Choose Folder", systemImage: "folder.badge.plus")
                            }
                            .buttonStyle(.borderedProminent).controlSize(.large)
                            .padding(.top, 6)
                            Button { AppSupport.shared.show(.guide) } label: {
                                Label("How to Use", systemImage: "play.circle")
                            }.buttonStyle(.link).padding(.top, 2)
                        }
                        Spacer(minLength: 0)
                        if geometry.size.width > 800 {
                            ZStack {
                                ForEach(0..<3) { index in
                                    Circle().trim(from: 0.04 * Double(index + 1), to: 0.88)
                                        .stroke(AngularGradient(colors: [Theme.accent, .blue, .indigo, Theme.accent], center: .center),
                                                style: StrokeStyle(lineWidth: 16, lineCap: .round))
                                        .frame(width: CGFloat(200 - index * 48), height: CGFloat(200 - index * 48))
                                        .rotationEffect(.degrees(Double(index) * 65 - 70))
                                        .opacity(1 - Double(index) * 0.16)
                                }
                                Image(systemName: "sparkle").font(.title).foregroundStyle(Theme.accent)
                            }
                            .frame(width: 220, height: 220).accessibilityHidden(true)
                        }
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(LinearGradient(colors: [Theme.accent.opacity(0.12), .indigo.opacity(0.05)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.cardStroke))

                    assistantIntroduction

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 14)], alignment: .leading, spacing: 14) {
                        featureCard("See where space goes", systemImage: "chart.pie", description: "Explore folders in the disk map, find large files and search your scan.")
                        featureCard("Review before removing", systemImage: "checkmark.shield", description: "Add items to the review queue, check their risks and confirm before moving them to Trash.")
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Ask about your files", systemImage: "sparkles")
                                .font(.headline).foregroundStyle(Theme.accent)
                            Text("Get explanations from local rules, an on-device model or a cloud provider you choose.")
                                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            Button("Choose AI Provider") { showSettings("ai") }
                                .buttonStyle(.link).help("Open AI provider settings")
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .card(padding: 18)
                    }

                    if !savedScans.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text("Continue where you left off").font(.title3.weight(.semibold))
                                if isOpeningSavedScan { ProgressView().controlSize(.small) }
                            }
                            ForEach(savedScans) { scan in
                                SavedScanRow(scan: scan, onOpen: { onOpenSaved(scan) }, onRescan: { onScan(scan.rootPath) })
                                    .disabled(isOpeningSavedScan)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Connected storage").font(.title3.weight(.semibold))
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
                            ForEach(volumes) { volume in
                                VStack(alignment: .leading, spacing: 14) {
                                    HStack(spacing: 12) {
                                        Image(systemName: volume.isInternal ? "internaldrive.fill" : "externaldrive.fill")
                                            .font(.title3).foregroundStyle(Theme.accent)
                                            .frame(width: 40, height: 40)
                                            .background(Theme.accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(volume.name).font(.headline).lineLimit(1)
                                            Text(volume.isInternal ? String(localized: "Internal") : String(localized: "External"))
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    if let fraction = volume.usedFraction {
                                        CapacityBar(fraction: fraction, height: 6)
                                            .accessibilityLabel("Current used storage")
                                    }
                                    if let free = volume.freeBytes {
                                        Group {
                                            if let total = volume.totalBytes {
                                                Text("\(ByteCountFormatter.string(fromByteCount: free, countStyle: .file)) free now of \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))")
                                            } else {
                                                Text("\(ByteCountFormatter.string(fromByteCount: free, countStyle: .file)) free now")
                                            }
                                        }
                                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                                        .help(Text("Physical free space updated \(volume.measuredAt.formatted(date: .abbreviated, time: .shortened)). Reclaimable space is still included in used storage."))
                                    }
                                    if let reclaimable = volume.estimatedReclaimableBytes, reclaimable > 0 {
                                        Text("Up to \(ByteCountFormatter.string(fromByteCount: reclaimable, countStyle: .file)) more reclaimable")
                                            .font(.caption).foregroundStyle(.secondary)
                                            .help("Reclaimable space is an estimate of what macOS may free automatically. It is still included in used storage.")
                                    }
                                    Button { onScan(volume.url.path) } label: {
                                        HStack { Text("Explore Disk"); Spacer(); Image(systemName: "arrow.right") }
                                    }.buttonStyle(.bordered).controlSize(.large)
                                }
                                .card(padding: 18)
                            }
                        }
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield").foregroundStyle(Theme.accent)
                        Text("On your Mac. Under your control.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(32)
                .frame(maxWidth: 1120)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var assistantIntroduction: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Label("Your disk, connected to your assistant", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.headline)
                Pill(title: String(localized: "Read-only"), systemImage: "lock", color: .green)
            }
            Text("Connect Claude Desktop or Codex through MCP to find large files, understand storage and prepare a cleanup plan. The companion server only reads metadata; you stay in control of changes.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button { showSettings("mcp") } label: {
                Label("Connect Claude or Codex", systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(.bordered).help("Open MCP setup and assistant shortcuts")
            .accessibilityIdentifier("welcome-mcp-setup")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 20)
    }

    private func featureCard(_ title: LocalizedStringKey, systemImage: String, description: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage).font(.headline).foregroundStyle(Theme.accent)
            Text(description).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card(padding: 18)
    }

    private func showSettings(_ tab: String) {
        SettingsNavigation.shared.selectedTab = tab
        openSettings()
    }
}

private struct SavedScanRow: View {
    let scan: SavedScanInfo
    let onOpen: () -> Void
    let onRescan: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.title3).foregroundStyle(Theme.accent)
                .frame(width: 40, height: 40)
                .background(Theme.accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(scan.rootName).font(.headline).lineLimit(1)
                Text(scan.rootPath).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 3) {
                Text(ByteCountFormatter.string(fromByteCount: scan.allocatedSizeBytes, countStyle: .file))
                    .font(.callout.weight(.semibold)).monospacedDigit()
                Text(scan.scannedAt.formatted(.relative(presentation: .named)))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button("Open", action: onOpen).buttonStyle(.borderedProminent)
                .accessibilityIdentifier("open-saved-scan")
            Button("Scan Again", action: onRescan).buttonStyle(.bordered)
        }
        .card(padding: 14)
    }
}
