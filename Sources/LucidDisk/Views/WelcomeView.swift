import SwiftUI

struct ScanProgressView: View {
    let count: Int
    let bytes: Int64
    let path: String
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 16) {
                ProgressView().controlSize(.large)
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
            .frame(maxWidth: .infinity, alignment: .leading).padding(20)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 14))
            Text(path).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                .truncationMode(.middle).frame(height: 36, alignment: .topLeading)
            Button("Stop Scan", action: onCancel).buttonStyle(.bordered).controlSize(.large)
        }
        .padding(32).frame(maxWidth: 580)
    }
}

struct WelcomeView: View {
    let volumes: [ScanVolume]
    let onScan: (String) -> Void
    let onChooseFolder: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(alignment: .center, spacing: 28) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("YOUR SPACE, CLEARLY.")
                                .font(.caption.weight(.semibold)).tracking(2).foregroundStyle(.cyan)
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
                                        .stroke(AngularGradient(colors: [.cyan, .blue, .indigo, .cyan], center: .center),
                                                style: StrokeStyle(lineWidth: 16, lineCap: .round))
                                        .frame(width: CGFloat(200 - index * 48), height: CGFloat(200 - index * 48))
                                        .rotationEffect(.degrees(Double(index) * 65 - 70))
                                        .opacity(1 - Double(index) * 0.16)
                                }
                                Image(systemName: "sparkle").font(.title).foregroundStyle(.cyan)
                            }
                            .frame(width: 220, height: 220).accessibilityHidden(true)
                        }
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(LinearGradient(colors: [.cyan.opacity(0.07), .indigo.opacity(0.04)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 20))

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Connected storage").font(.title3.weight(.semibold))
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
                            ForEach(volumes) { volume in
                                VStack(alignment: .leading, spacing: 16) {
                                    HStack(spacing: 10) {
                                        Image(systemName: volume.isInternal ? "internaldrive" : "externaldrive")
                                            .font(.title2).foregroundStyle(.cyan)
                                        Text(volume.name).font(.headline).lineLimit(1)
                                        Spacer(minLength: 0)
                                    }
                                    if let total = volume.totalBytes, let available = volume.availableBytes, total > 0 {
                                        ProgressView(value: Double(max(0, total - available)), total: Double(total))
                                            .tint(.cyan)
                                        Text("\(ByteCountFormatter.string(fromByteCount: available, countStyle: .file)) available of \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Button { onScan(volume.url.path) } label: {
                                        HStack { Text("Explore Disk"); Spacer(); Image(systemName: "arrow.right") }
                                    }.buttonStyle(.bordered).controlSize(.large)
                                }
                                .padding(18)
                                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 14))
                            }
                        }
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield").foregroundStyle(.cyan)
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
