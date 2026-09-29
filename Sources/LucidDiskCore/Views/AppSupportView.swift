import AppKit
import SwiftUI

enum SupportSection: String, CaseIterable, Identifiable {
    case guide, shortcuts, privacy, about
    var id: Self { self }
    var title: String {
        switch self {
        case .guide: String(localized: "How to Use")
        case .shortcuts: String(localized: "Keyboard Shortcuts")
        case .privacy: String(localized: "Privacy & Safety")
        case .about: String(localized: "About")
        }
    }
}

/// One reusable, non-modal window. Reading help never interrupts a scan or selection.
@MainActor
final class AppSupport: ObservableObject {
    static let shared = AppSupport()
    @Published var section: SupportSection = .guide
    private(set) var window: NSWindow?

    func show(_ section: SupportSection) {
        self.section = section
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 660),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "Lucid Disk"
            window.identifier = NSUserInterfaceItemIdentifier("lucid-support")
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 620, height: 540)
            window.contentView = NSHostingView(rootView: AppSupportView(support: self)
                .tint(Color(red: 0.15, green: 0.68, blue: 0.78)))
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
    }
}

struct AppSupportView: View {
    @ObservedObject var support: AppSupport
    @ObservedObject private var extensions = LucidDiskExtensions.shared
    @State private var showingLicense = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 18) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().frame(width: 64, height: 64).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(verbatim: extensions.edition.displayName)
                        .font(.system(size: 27, weight: .semibold, design: .rounded))
                    Text("Understand your space. Keep control.").foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(24)
            .background(LinearGradient(colors: [.cyan.opacity(0.10), .indigo.opacity(0.04)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
            Picker("Help topic", selection: $support.section) {
                ForEach(SupportSection.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().padding(20)
            .accessibilityIdentifier("help-topic")
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch support.section {
                    case .guide: guide
                    case .shortcuts: shortcuts
                    case .privacy: privacy
                    case .about: about
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28).padding(.bottom, 24)
                .textSelection(.enabled)
            }
            .id(support.section)
            Divider()
            HStack {
                Label("On your Mac. Under your control.", systemImage: "lock.shield")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Done") { support.window?.close() }.keyboardShortcut(.cancelAction)
            }.padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showingLicense) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Apache License 2.0").font(.title2.bold())
                ScrollView { Text(licenseText).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
                Button("Done") { showingLicense = false }.keyboardShortcut(.cancelAction)
            }.padding(24).frame(width: 580, height: 460)
        }
    }

    private var guide: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("From a full disk to a clear decision.").font(.title2.weight(.semibold))
            info("1", "Start with a folder", "Choose Folder is a good first scan. Explore Disk scans a mounted volume. Stop Scan cancels safely; your previous completed scan stays available.")
            info("2", "Explore the map", "On the chart, click a folder to enter it and the center to go back. In the file list, single-click to inspect and double-click a folder to open it. Other groups contain real, smaller items.")
            info("3", "Understand before removing", "Select a file for its size and safety notes. Press Space for Quick Look. Ask AI is optional: only that button requests an explanation, based on metadata, not file contents. Choose the AI provider in Settings (⌘,).")
            info("4", "Review, then move to Trash", "Add an item to the Review Queue. Select the queued item, choose Move to Trash, and confirm. Nothing is removed automatically. A new scan refreshes the list and clears the old queue.")
            Divider()
            info(nil, "Need a file back?", "Open Trash in Finder and use Put Back where available. Lucid Disk never empties the Trash. Disk space is not necessarily freed until you empty it yourself.")
            info(nil, "Missing files or access warnings?", "Some folders require Full Disk Access. You can enable Lucid Disk in System Settings → Privacy & Security → Full Disk Access, then scan again. This does not bypass all macOS protections.")
            Button("Open Privacy Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                    NSWorkspace.shared.open(url)
                }
            }.buttonStyle(.bordered)
        }
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("A little less clicking.").font(.title2.weight(.semibold))
            shortcut("Choose Folder", "⌘ O")
            shortcut("Scan Again", "⌘ R")
            shortcut("Search all scanned files", "⌘ F")
            shortcut("Move between files", "↑  ↓")
            shortcut("Open selected folder", "↩  →")
            shortcut("Back to parent folder", "⌘ ←")
            shortcut("Quick Look", "Space")
            shortcut("Close preview or help", "Esc")
            shortcut("How to Use", "⌘ ?")
            shortcut("Settings", "⌘ ,")
            Text("File navigation shortcuts apply while the file list is focused. Search covers the entire completed scan, including nested folders.")
                .font(.callout).foregroundStyle(.secondary).padding(.top, 8)
        }
    }

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Your files. Your decision.").font(.title2.weight(.semibold))
            info(nil, "Local by design", "Disk scans run on your Mac. There is no telemetry or analytics, and nothing is sent to a cloud service unless you choose one. Selecting a file does not invoke AI.")
            info(nil, "AI only when you ask", "Ask AI uses the provider chosen in Settings: Apple’s on-device model (default), a local Ollama model, the Claude API, or rules only. No provider reads file contents. If a provider fails, the rule-based explanation is shown; Lucid Disk never switches to another provider on its own. AI cannot authorize deletion or lower a safety restriction.")
            info(nil, "Cloud is opt-in", "The Claude API is used only after you add your own key and allow sending metadata. Then only the selected item’s name, path, size, type, dates, associated app and safety rule are sent when you press Ask AI. The key is stored in your Keychain.")
            info(nil, "Honest size estimates", "Allocated size is disk allocation; logical size is file length. Hard links are counted once. APFS clones may share blocks, so estimates are not a promise of reclaimable space. Incomplete scans are labeled.")
            info(nil, "Protected removal", "Protected system locations are blocked. Before moving a reviewed item to Trash, Lucid Disk checks its identity and path again. Sensitive items require stronger confirmation.")
            info(nil, "MCP is separate", "The optional MCP server runs outside this app; Settings → MCP lists its five read-only tools and setup commands. Its tools can expose metadata to the model you connect; review that client’s privacy settings before sharing anything.")
        }
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("A clearer view of your Mac.").font(.title2.weight(.semibold))
            Text("An open-source disk explorer for understanding storage and reviewing what you choose to remove.")
                .foregroundStyle(.secondary)
            HStack {
                Label(version, systemImage: "app.badge")
                Spacer()
                Text("macOS 14+").foregroundStyle(.secondary)
            }.padding(16).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
            info(nil, "Made by Serkan Uslu", "Built with Swift, SwiftUI and AppKit. Optional explanations use Apple Foundation Models, a local Ollama model, or the Claude API — your choice in Settings.")
            info(nil, "Open source · Apache 2.0", "You may use, study, modify and distribute Lucid Disk under the Apache License 2.0. The software is provided without warranties; review files and keep backups before removing anything.")
            Button("Read License") { showingLicense = true }.buttonStyle(.bordered)
            Button("How to Use") { support.section = .guide }.buttonStyle(.link)
        }
    }

    private var version: String {
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
            return String(localized: "Development build")
        }
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return String(localized: "Version \(version) (\(build))")
    }

    private var licenseText: String {
        guard let url = Bundle.main.url(forResource: "LICENSE", withExtension: nil),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return String(localized: "The license is included in packaged builds and in the source repository’s LICENSE file.")
        }
        return text
    }

    private func info(_ number: String?, _ title: LocalizedStringKey, _ body: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            if let number {
                Text(number).font(.headline).foregroundStyle(.cyan)
                    .frame(width: 30, height: 30).background(.cyan.opacity(0.1), in: Circle())
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(body).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func shortcut(_ title: LocalizedStringKey, _ keys: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(keys).font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        }
    }
}
