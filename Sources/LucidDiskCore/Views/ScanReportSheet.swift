import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Retains one immutable tree revision while a report is prepared off the UI thread.
struct ScanReportPresentation: Identifiable {
    let id = UUID()
    let root: FileNode
    let matches: [FileNode]?
    let context: ScanReportContext
    var reviewWithAssistant = false
}

struct ScanReportSheet: View {
    let presentation: ScanReportPresentation
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings
    @State private var report: ScanReport?
    @State private var preview = ""
    @State private var brief = ""
    @State private var format: ScanReportFormat = .text
    @State private var reviewWithAssistant: Bool
    @State private var preparing = true
    @State private var saving = false
    @State private var errorMessage: String?
    @State private var notice: String?
    @State private var savedURL: URL?

    init(presentation: ScanReportPresentation) {
        self.presentation = presentation
        _reviewWithAssistant = State(initialValue: presentation.reviewWithAssistant)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Export & Review").font(.title2.weight(.semibold))
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                    .disabled(saving)
            }
            Text(presentation.context.title).font(.headline)
            Text(presentation.root.path).font(.caption).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            Picker("Report action", selection: $reviewWithAssistant) {
                Text("Export report").tag(false)
                Text("Review with Codex or Claude").tag(true)
            }.pickerStyle(.segmented)

            if preparing {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Preparing report…")
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let report {
                if reviewWithAssistant {
                    assistantActions
                } else {
                    Text("Includes names, full paths, item types, sizes, dates and scan warnings. Parent folders are marked separately from matching results.")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("File format", selection: $format) {
                        Text("Text · folder tree").tag(ScanReportFormat.text)
                        Text("CSV · table").tag(ScanReportFormat.csv)
                        Text("JSON · structured data").tag(ScanReportFormat.json)
                    }.pickerStyle(.segmented)
                }
                Text("\(report.matchedCount) results · \(report.ancestorCount) parent folders")
                    .font(.caption.weight(.medium))
                ScrollView([.vertical, .horizontal]) {
                    Text(reviewWithAssistant ? brief : preview)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityIdentifier("report-preview")
                HStack {
                    Button { save(report) } label: {
                        Label(reviewWithAssistant ? String(localized: "Save full report…") : String(localized: "Save report…"),
                              systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(saving)
                    .accessibilityIdentifier("save-scan-report")
                    if saving { ProgressView().controlSize(.small) }
                    Spacer()
                    if let savedURL {
                        Button("Show exported file") { NSWorkspace.shared.activateFileViewerSelecting([savedURL]) }
                    }
                }
            }
            if let notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
            if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
        }
        .padding(20)
        .frame(width: 740, height: 590)
        .task(id: presentation.id) { await prepare() }
        .interactiveDismissDisabled(saving)
        .accessibilityIdentifier("scan-report-sheet")
    }

    private var assistantActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Copy the cleanup brief, then paste it into a new assistant chat. Attach the full report for more detail. MCP can check current sizes and risks before you review cleanup in Lucid Disk.")
                .font(.caption)
            Text("The brief includes file names and full paths. Nothing is sent automatically; you choose what to share in the assistant.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button { copyAndOpen(.codex) } label: { Label("Copy & Open Codex", systemImage: "arrow.up.forward.app") }
                    .accessibilityIdentifier("review-with-codex")
                Button { copyAndOpen(.claudeDesktop) } label: { Label("Copy & Open Claude", systemImage: "arrow.up.forward.app") }
                    .accessibilityIdentifier("review-with-claude")
                Button("Copy brief") { copyBrief() }.accessibilityIdentifier("copy-review-brief")
                Button("MCP Setup") {
                    SettingsNavigation.shared.selectedTab = "mcp"
                    openSettings()
                }
            }
            .controlSize(.small)
            .disabled(brief.isEmpty)
        }
    }

    private func prepare() async {
        let captured = presentation
        let worker = Task.detached(priority: .userInitiated) { () throws -> (ScanReport, String, String) in
            let report = try ScanReport.build(root: captured.root, matches: captured.matches, context: captured.context)
            let preview = try report.preview()
            // An unusually large context may not fit a chat, but it must remain exportable.
            let brief = try? AssistantReviewBrief.make(report: report)
            try Task.checkCancellation()
            return (report, preview, brief ?? "")
        }
        do {
            let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
            guard !Task.isCancelled else { return }
            report = result.0
            preview = result.1
            brief = result.2
            if brief.isEmpty { errorMessage = String(localized: "This report is too large for a clipboard brief. Save the full report and attach it in your assistant.") }
        } catch is CancellationError { return }
        catch { errorMessage = error.localizedDescription }
        preparing = false
    }

    private func copyBrief() {
        guard !brief.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(brief, forType: .string)
        notice = String(localized: "Brief copied. Paste it into a new chat to request a cleanup plan.")
    }

    private func copyAndOpen(_ assistant: MCPAssistant) {
        copyBrief()
        errorMessage = nil
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: assistant.bundleIdentifier) else {
            errorMessage = assistant.notInstalledMessage
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if error != nil {
                Task { @MainActor in errorMessage = String(localized: "The assistant could not be opened. Try opening it from Applications.") }
            }
        }
    }

    private func save(_ report: ScanReport) {
        let selectedFormat = format
        let panel = NSSavePanel()
        switch selectedFormat {
        case .text: panel.allowedContentTypes = [.plainText]
        case .csv: panel.allowedContentTypes = [.commaSeparatedText]
        case .json: panel.allowedContentTypes = [.json]
        }
        panel.nameFieldStringValue = "Lucid-Disk-Report." + selectedFormat.fileExtension
        panel.canCreateDirectories = true
        panel.message = String(localized: "Save the complete report, including all results and their folder hierarchy.")
        saving = true
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { saving = false; return }
            errorMessage = nil
            Task {
                do {
                    try await Task.detached(priority: .userInitiated) {
                        let data = try report.data(format: selectedFormat)
                        try data.write(to: url, options: .atomic)
                    }.value
                    savedURL = url
                    notice = String(localized: "Report saved. The exported file includes every result; only the on-screen preview is shortened.")
                } catch { errorMessage = error.localizedDescription }
                saving = false
            }
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }
}
