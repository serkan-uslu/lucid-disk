import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var extensions = LucidDiskExtensions.shared
    @ObservedObject private var navigation = SettingsNavigation.shared

    var body: some View {
        TabView(selection: $navigation.selectedTab) {
            GeneralSettingsPane()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag("general")
            InsightSettingsPane()
                .tabItem { Label("AI", systemImage: "sparkles") }
                .tag("ai")
            MCPSettingsPane()
                .tabItem { Label("MCP", systemImage: "point.3.connected.trianglepath.dotted") }
                .tag("mcp")
            ForEach(extensions.settingsTabs) { tab in
                tab.content()
                    .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                    .tag("extension:" + tab.id)
            }
        }
        .frame(width: 660, height: 640)
        .tint(Theme.accent)
    }
}

// MARK: - General

struct GeneralSettingsPane: View {
    @AppStorage(ScanSaving.key) private var saveScans = true
    @State private var savedCount = 0
    @State private var savedBytes: Int64 = 0
    @State private var confirmDelete = false
    private let store = ScanStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Saved scans").font(.title2.weight(.semibold))
                    Text("Lucid Disk can keep the last scan of each location so it opens instantly next time. Saved scans stay on this Mac and are never uploaded.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Save the last scan of each location", isOn: $saveScans)
                        .accessibilityIdentifier("save-scans-toggle")
                    Text("A saved scan shows names, paths, sizes and dates as they were. You can browse it and build a review queue, but moving items to the Trash always needs a fresh scan.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Divider()
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(savedCount) saved scans")
                            Text(ByteCountFormatter.string(fromByteCount: savedBytes, countStyle: .file))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([store.directory])
                        }
                        .disabled(savedCount == 0)
                        Button("Delete Saved Scans…", role: .destructive) { confirmDelete = true }
                            .disabled(savedCount == 0)
                    }
                }
                .card()
            }
            .padding(24)
        }
        .task { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: ScanStore.didChangeNotification).receive(on: RunLoop.main)) { _ in
            refresh()
        }
        .confirmationDialog("Delete all saved scans?", isPresented: $confirmDelete) {
            Button("Delete Saved Scans", role: .destructive) { store.deleteAll() }
        } message: {
            Text("Only Lucid Disk’s saved scan files are removed. Your own files are not touched.")
        }
    }

    private func refresh() {
        savedCount = store.list().count
        savedBytes = store.diskUsage()
    }
}

// MARK: - AI

struct InsightSettingsPane: View {
    @ObservedObject private var settings = InsightSettings.shared
    @State private var keyDraft = ""
    @State private var openAIKeyDraft = ""
    @State private var ollamaModels: [String] = []
    @State private var hiddenCloudModels = 0
    @State private var ollamaStatus: ConnectionStatus = .idle
    @State private var claudeStatus: ConnectionStatus = .idle
    @State private var openAIStatus: ConnectionStatus = .idle
    @State private var keyError: String?
    @State private var openAIKeyError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Lucid Insight").font(.title2.weight(.semibold))
                    Text("Choose who answers when you press Ask AI. Nothing is sent until you press it, and AI never changes a safety decision.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                VStack(spacing: 8) {
                    ForEach(InsightProviderKind.allCases) { kind in
                        ProviderRow(kind: kind, isSelected: settings.provider == kind) { settings.provider = kind }
                    }
                }
                .accessibilityIdentifier("insight-provider")

                Group {
                    switch settings.provider {
                    case .appleOnDevice: appleSection
                    case .ollama: ollamaSection
                    case .claude: claudeSection
                    case .openAI: openAISection
                    case .rulesOnly: rulesSection
                    }
                }
                .card()
            }
            .padding(24)
        }
        .task(id: settings.provider) {
            if settings.provider == .ollama, ollamaModels.isEmpty { await refreshOllama() }
        }
    }

    private var appleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Apple Foundation Models", systemImage: "apple.logo").font(.headline)
            Text(LocalFileInsightService.appleModelStatus)
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("When the model is unavailable, Ask AI shows the rule-based explanation instead.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("No model", systemImage: "list.bullet.rectangle").font(.headline)
            Text("Ask AI shows Lucid Disk’s deterministic explanation: matched safety rule, size, type, dates and associated app.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var ollamaSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Ollama server", systemImage: "desktopcomputer").font(.headline)
                Spacer()
                StatusText(status: ollamaStatus)
            }
            HStack {
                TextField("Server URL", text: $settings.ollamaURLString)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await refreshOllama() } }
                Button("Connect") { Task { await refreshOllama() } }
            }
            if settings.ollamaBaseURL == nil {
                Text("Enter an http:// or https:// address, for example http://127.0.0.1:11434.")
                    .font(.caption).foregroundStyle(.red)
            }
            if ollamaModels.isEmpty {
                TextField("Model name (for example llama3.2)", text: $settings.ollamaModel)
                    .textFieldStyle(.roundedBorder)
            } else {
                Picker("Model", selection: $settings.ollamaModel) {
                    if !ollamaModels.contains(settings.ollamaModel) {
                        Text(settings.ollamaModel.isEmpty ? String(localized: "Choose a model") : settings.ollamaModel)
                            .tag(settings.ollamaModel)
                    }
                    ForEach(ollamaModels, id: \.self) { Text($0).tag($0) }
                }
            }
            if hiddenCloudModels > 0 {
                Label("\(hiddenCloudModels) Ollama cloud models are hidden because they would send data to ollama.com.",
                      systemImage: "cloud.slash")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Text("Requests go only to this server. Keep it on this Mac or a network you trust; a remote address receives the item’s metadata.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Link("Get Ollama", destination: URL(string: "https://ollama.com/download")!).font(.caption)
        }
    }

    private var claudeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Anthropic API", systemImage: "key").font(.headline)
                Spacer()
                StatusText(status: claudeStatus)
            }
            if let hint = settings.claudeKeyHint {
                HStack {
                    Image(systemName: "lock.fill").foregroundStyle(.green)
                    Text("Key saved in Keychain ••••\(hint)")
                    Spacer()
                    Button("Test") { Task { await testClaude() } }
                    Button("Remove", role: .destructive) {
                        do { try settings.removeClaudeKey(); claudeStatus = .idle } catch { keyError = error.localizedDescription }
                    }
                }
            } else {
                HStack {
                    SecureField("API key (sk-ant-…)", text: $keyDraft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(saveKey)
                    Button("Save", action: saveKey).disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Link("Create a key in the Claude Console", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                    .font(.caption)
            }
            if let keyError { Text(keyError).font(.caption).foregroundStyle(.red) }
            HStack {
                TextField("Model", text: $settings.claudeModel).textFieldStyle(.roundedBorder)
                Menu("Models") {
                    ForEach(ClaudeClient.suggestedModels, id: \.self) { model in
                        Button(model) { settings.claudeModel = model }
                    }
                }
                .fixedSize()
            }
            Divider()
            Toggle(isOn: $settings.cloudConsent) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Allow sending metadata to Anthropic")
                    Text("Only when you press Ask AI: the item’s name, full path, size, type, dates, associated app and safety rule. File contents are never read or sent. Anthropic’s data policies apply.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.checkbox)
            .accessibilityIdentifier("claude-consent")
        }
    }

    private var openAISection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("OpenAI API", systemImage: "key").font(.headline)
                Spacer()
                StatusText(status: openAIStatus)
            }
            if let hint = settings.openAIKeyHint {
                HStack {
                    Image(systemName: "lock.fill").foregroundStyle(.green)
                    Text("Key saved in Keychain ••••\(hint)")
                    Spacer()
                    Button("Test") { Task { await testOpenAI() } }
                        .disabled(openAIStatus == .checking)
                    Button("Remove", role: .destructive) {
                        do {
                            try settings.removeOpenAIKey()
                            openAIStatus = .idle
                            openAIKeyError = nil
                        } catch { openAIKeyError = error.localizedDescription }
                    }
                }
            } else {
                HStack {
                    SecureField("OpenAI API key (sk-…)", text: $openAIKeyDraft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(saveOpenAIKey)
                    Button("Save", action: saveOpenAIKey)
                        .disabled(openAIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Link("Create an OpenAI API key", destination: URL(string: "https://platform.openai.com/api-keys")!)
                    .font(.caption)
            }
            if let openAIKeyError { Text(openAIKeyError).font(.caption).foregroundStyle(.red) }
            HStack {
                TextField("Model", text: $settings.openAIModel).textFieldStyle(.roundedBorder)
                Menu("Models") {
                    ForEach(OpenAIClient.suggestedModels, id: \.self) { model in
                        Button(model) { settings.openAIModel = model }
                    }
                }
                .fixedSize()
            }
            Text("Uses your OpenAI API account. A ChatGPT subscription does not include API usage.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            Toggle(isOn: $settings.openAIConsent) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Allow sending metadata to OpenAI")
                    Text("Only when you press Ask AI: the item’s name, full path, size, type, dates, associated app and safety rule. File contents are never read or sent. OpenAI’s data policies apply.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.checkbox)
            .accessibilityIdentifier("openai-consent")
        }
    }

    private func saveOpenAIKey() {
        do {
            try settings.saveOpenAIKey(openAIKeyDraft)
            openAIKeyDraft = ""
            openAIKeyError = nil
            openAIStatus = .idle
        } catch {
            openAIKeyError = error.localizedDescription
        }
    }

    private func testOpenAI() async {
        guard let client = settings.openAIClient() else { openAIStatus = .failed(String(localized: "No key")); return }
        openAIStatus = .checking
        do {
            try await client.verify()
            openAIStatus = .ok(String(localized: "Key works"))
        } catch {
            openAIStatus = .failed(error.localizedDescription)
        }
    }

    private func saveKey() {
        do {
            try settings.saveClaudeKey(keyDraft)
            keyDraft = ""
            keyError = nil
            Task { await testClaude() }
        } catch {
            keyError = error.localizedDescription
        }
    }

    private func testClaude() async {
        guard let client = settings.claudeClient() else { claudeStatus = .failed(String(localized: "No key")); return }
        claudeStatus = .checking
        do {
            try await client.verify()
            claudeStatus = .ok(String(localized: "Key works"))
        } catch {
            claudeStatus = .failed(error.localizedDescription)
        }
    }

    private func refreshOllama() async {
        guard let url = settings.ollamaBaseURL else { ollamaStatus = .failed(String(localized: "Invalid URL")); return }
        ollamaStatus = .checking
        do {
            let inventory = try await OllamaClient(baseURL: url).inventory()
            let models = inventory.localModels
            ollamaModels = models
            hiddenCloudModels = inventory.hiddenCloudModels
            if !models.contains(settings.ollamaModel), let first = models.first { settings.ollamaModel = first }
            ollamaStatus = models.isEmpty
                ? .failed(String(localized: "No models installed. Run: ollama pull llama3.2"))
                : .ok(String(localized: "Connected · \(models.count) models"))
        } catch {
            ollamaModels = []
            hiddenCloudModels = 0
            ollamaStatus = .failed(String(localized: "Not reachable. Is Ollama running?"))
        }
    }
}

private struct ProviderRow: View {
    let kind: InsightProviderKind
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: kind.systemImage)
                    .font(.title3).frame(width: 34, height: 34)
                    .foregroundStyle(isSelected ? Color.white : Theme.accent)
                    .background(isSelected ? Theme.accent : Theme.accent.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(kind.title).font(.body.weight(.medium))
                        if kind.sendsDataOffDevice {
                            Pill(title: String(localized: "Cloud"), systemImage: "arrow.up.right", color: .orange)
                        } else {
                            Pill(title: String(localized: "Private"), systemImage: "lock", color: .green)
                        }
                    }
                    Text(kind.subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(isSelected ? Theme.accent : .secondary)
            }
            .padding(12)
            .contentShape(Rectangle())
            .background(isSelected ? Theme.accent.opacity(0.08) : Theme.cardFill,
                        in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(isSelected ? Theme.accent.opacity(0.7) : Theme.cardStroke, lineWidth: isSelected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

enum ConnectionStatus: Equatable {
    case idle, checking
    case ok(String)
    case failed(String)
}

private struct StatusText: View {
    let status: ConnectionStatus
    var body: some View {
        switch status {
        case .idle: EmptyView()
        case .checking: ProgressView().controlSize(.small)
        case .ok(let text): Label(text, systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
        case .failed(let text):
            Label(text, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.caption)
                .lineLimit(2).multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - MCP

struct MCPTool: Identifiable {
    let name: String
    let summary: String
    let parameters: String
    let systemImage: String
    var id: String { name }

    static let all: [MCPTool] = [
        MCPTool(name: "summarize_known_locations",
                summary: String(localized: "Measures common space-heavy places such as Xcode DerivedData, caches, logs, Downloads and Trash, with each location’s risk."),
                parameters: "max_entries", systemImage: "map"),
        MCPTool(name: "inventory_directory",
                summary: String(localized: "Measures and ranks the direct children of a folder by allocated size."),
                parameters: "path, min_size_bytes, limit, max_children, max_entries_total", systemImage: "list.number"),
        MCPTool(name: "find_large_files",
                summary: String(localized: "Finds the largest files below a folder on the same volume, counting hard links once."),
                parameters: "path, min_size_bytes, limit, max_entries", systemImage: "doc.text.magnifyingglass"),
        MCPTool(name: "assess_paths",
                summary: String(localized: "Reports size, accuracy, warnings and cleanup risk for up to 50 paths, checking symlink targets too."),
                parameters: "paths, calculate_size, max_entries", systemImage: "checkmark.shield"),
        MCPTool(name: "create_cleanup_plan",
                summary: String(localized: "Groups chosen paths by risk and lists blockers and questions to answer before removing anything."),
                parameters: "paths, calculate_size, max_entries", systemImage: "checklist")
    ]
}

struct MCPSettingsPane: View {
    @AppStorage("mcp.projectPath") private var projectPath = MCPSetup.detectedProjectPath() ?? ""
    @State private var copied: String?
    @State private var assistant: MCPAssistant = .claudeDesktop
    @State private var launchError: String?

    private var setup: MCPSetup { MCPSetup(projectPath: projectPath) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("MCP server").font(.title2.weight(.semibold))
                        Pill(title: String(localized: "Read-only"), systemImage: "lock", color: .green)
                    }
                    Text("An optional companion that lets assistants such as Claude Code, Claude Desktop or Codex look at your disk through five tools. It never deletes, moves or changes files, and it runs separately from this app.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }

                connectionSection

                DisclosureGroup("Available MCP tools") {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(MCPTool.all.enumerated()), id: \.element.id) { index, tool in
                            if index > 0 { Divider().padding(.leading, 44) }
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: tool.systemImage).foregroundStyle(Theme.accent)
                                    .frame(width: 30, height: 30)
                                    .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(tool.name).font(.system(.callout, design: .monospaced).weight(.semibold))
                                        .textSelection(.enabled)
                                    Text(tool.summary).font(.callout).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(tool.parameters).font(.system(.caption, design: .monospaced)).foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.vertical, 10)
                        }
                    }
                }
                .card(padding: 12)

                Label("Tool results include paths, names, sizes and dates. Your assistant sends them to the model it uses, so approve each call and connect only services you trust.",
                      systemImage: "hand.raised")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
        }
    }

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connect an assistant").font(.headline)
            Text("Set up the companion once, then open your assistant here whenever you need it.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button { openAssistant(.claudeDesktop) } label: {
                    Label("Open Claude Desktop", systemImage: "arrow.up.forward.app")
                }
                .help("Launch Claude Desktop. MCP setup below is required before its first use.")
                .accessibilityIdentifier("open-claude-desktop")
                Button { openAssistant(.codex) } label: {
                    Label("Open Codex", systemImage: "arrow.up.forward.app")
                }
                .help("Launch Codex. MCP setup below is required before its first use.")
                .accessibilityIdentifier("open-codex")
            }
            .buttonStyle(.bordered)
            if let launchError {
                Label(launchError, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            Text("Opening an assistant only launches the app. It does not install or connect the MCP server.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack {
                Image(systemName: "folder")
                Text(projectPath.isEmpty ? String(localized: "Choose the repository’s mcp folder") : projectPath)
                    .lineLimit(1).truncationMode(.middle)
                    .foregroundStyle(projectPath.isEmpty ? .secondary : .primary)
                Spacer()
                Button("Choose…", action: chooseFolder)
                    .help("Choose the mcp folder inside the Lucid Disk repository.")
            }
            if !projectPath.isEmpty && !setup.isValidProject {
                Label("This folder has no pyproject.toml for luciddisk-mcp.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            if setup.uvPath == nil {
                Label("uv was not found. Install it from docs.astral.sh/uv, then restart your assistant.", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Picker("Assistant", selection: $assistant) {
                Text("Claude Desktop").tag(MCPAssistant.claudeDesktop)
                Text("Codex").tag(MCPAssistant.codex)
            }
            .pickerStyle(.segmented)
            if assistant == .claudeDesktop {
                Text("Copy this configuration and merge the luciddisk entry into Claude Desktop’s Settings → Developer → Edit Config. Keep any existing servers, then restart Claude Desktop.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                snippet(String(localized: "Claude Desktop — claude_desktop_config.json"), setup.claudeDesktopJSON)
            } else {
                Text("Copy and run this command in Terminal after installing the Codex CLI. Restart Codex, then check that luciddisk appears in its MCP settings.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                snippet(String(localized: "Codex"), setup.codexCommand)
            }
            DisclosureGroup("Claude Code setup") {
                snippet(String(localized: "Claude Code"), setup.claudeCodeCommand)
                    .padding(.top, 6)
            }
        }
        .card()
    }

    private func snippet(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button(copied == title ? String(localized: "Copied") : String(localized: "Copy")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = title
                }
                .buttonStyle(.borderless).font(.caption)
                .disabled(!setup.isValidProject)
                .help("Copy this assistant’s MCP configuration")
            }
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func openAssistant(_ assistant: MCPAssistant) {
        launchError = nil
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: assistant.bundleIdentifier) else {
            launchError = assistant.notInstalledMessage
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if error != nil {
                Task { @MainActor in launchError = String(localized: "The assistant could not be opened. Try opening it from Applications.") }
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = String(localized: "Choose the mcp folder inside the Lucid Disk repository.")
        if panel.runModal() == .OK, let url = panel.url {
            projectPath = url.path
            copied = nil
        }
    }
}

enum MCPAssistant: String {
    case claudeDesktop, codex

    var bundleIdentifier: String {
        switch self {
        case .claudeDesktop: "com.anthropic.claudefordesktop"
        case .codex: "com.openai.codex"
        }
    }

    var notInstalledMessage: String {
        switch self {
        case .claudeDesktop: String(localized: "Claude Desktop is not installed. Install it, then use the setup below to connect the MCP server.")
        case .codex: String(localized: "Codex is not installed. Install it, then use the setup below to connect the MCP server.")
        }
    }
}

/// Builds copy-paste configuration for the separately installed MCP server.
struct MCPSetup {
    let projectPath: String
    var uvPath: String? = MCPSetup.findUV()

    var isValidProject: Bool {
        let pyproject = URL(fileURLWithPath: projectPath).appendingPathComponent("pyproject.toml")
        guard let text = try? String(contentsOf: pyproject, encoding: .utf8) else { return false }
        return text.contains("luciddisk-mcp")
    }

    private var path: String { projectPath.isEmpty ? "/path/to/lucid-disk/mcp" : projectPath }
    private var uv: String { uvPath ?? "uv" }

    var claudeCodeCommand: String {
        "claude mcp add luciddisk -- \(Self.shellQuoted(uv)) run --project \(Self.shellQuoted(path)) luciddisk-mcp"
    }

    var codexCommand: String {
        "codex mcp add luciddisk -- \(Self.shellQuoted(uv)) run --project \(Self.shellQuoted(path)) luciddisk-mcp"
    }

    var claudeDesktopJSON: String {
        let config: [String: Any] = ["mcpServers": ["luciddisk": [
            "command": uv, "args": ["run", "--project", path, "luciddisk-mcp"]
        ]]]
        guard let data = try? JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }

    static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func findUV() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["/opt/homebrew/bin/uv", "/usr/local/bin/uv", home + "/.local/bin/uv", home + "/.cargo/bin/uv"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// A build under `<repo>/build/` can find the server next to it.
    static func detectedProjectPath(bundlePath: String = Bundle.main.bundlePath) -> String? {
        var url = URL(fileURLWithPath: bundlePath)
        for _ in 0..<4 {
            url.deleteLastPathComponent()
            let candidate = url.appendingPathComponent("mcp")
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("pyproject.toml").path) {
                return candidate.path
            }
        }
        return nil
    }
}
