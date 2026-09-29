import SwiftUI

struct ScanProgressView: View {
    let count: Int
    let bytes: Int64
    let path: String
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 18) {
                ScanningRings().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Mapping your storage").font(.title2.weight(.semibold))
                    Text("Finding where your space goes.").foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 40) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(count.formatted()).font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text("Files scanned").font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                        .font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text("Space mapped").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 20)
            Text(path).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                .truncationMode(.middle).frame(height: 36, alignment: .topLeading)
            Button("Stop Scan", action: onCancel).buttonStyle(.bordered).controlSize(.large)
        }
        .padding(32).frame(maxWidth: 580)
    }
}

struct WelcomeView: View {
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
                                    if let total = volume.totalBytes, let available = volume.availableBytes, total > 0 {
                                        CapacityBar(fraction: Double(max(0, total - available)) / Double(total), height: 6)
                                        Text("\(ByteCountFormatter.string(fromByteCount: available, countStyle: .file)) available of \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))")
                                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
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
}

/// Three counter-rotating arcs echoing the sunburst while a scan runs.
struct ScanningRings: View {
    @State private var spinning = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ForEach(0..<3) { index in
                Circle()
                    .trim(from: 0, to: 0.62 - Double(index) * 0.12)
                    .stroke(Theme.accent.opacity(1 - Double(index) * 0.25),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .padding(CGFloat(index) * 9)
                    .rotationEffect(.degrees(spinning ? (index.isMultiple(of: 2) ? 360 : -360) : 0))
                    .animation(reduceMotion ? nil : .linear(duration: 1.6 + Double(index) * 0.5)
                        .repeatForever(autoreverses: false), value: spinning)
            }
        }
        .onAppear { spinning = true }
        .accessibilityHidden(true)
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
