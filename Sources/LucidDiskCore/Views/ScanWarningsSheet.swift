import AppKit
import SwiftUI

@MainActor
enum ScanWarningClipboard {
    @discardableResult
    static func copy(_ path: String, to pasteboard: NSPasteboard) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(path, forType: .string)
    }
}

struct ScanWarningsButton: View {
    let count: Int
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            Label {
                Text("Show All Warnings (\(count))")
                    .lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            } icon: {
                Image(systemName: "list.bullet")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain).font(.caption).foregroundStyle(Theme.accent)
        .accessibilityIdentifier("show-all-scan-warnings")
    }
}

struct ScanWarningsSheet: View {
    let presentation: ScanWarningsPresentation
    @Environment(\.dismiss) private var dismiss
    @State private var query: String
    @State private var copyNotice: String?
    @FocusState private var searchFocused: Bool

    init(presentation: ScanWarningsPresentation, query: String = "") {
        self.presentation = presentation
        _query = State(initialValue: query)
    }

    var body: some View {
        let matches = presentation.matching(query)
        VStack(alignment: .leading, spacing: 12) {
            Text("Scan Warnings").font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text(presentation.rootPath).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            if let savedAt = presentation.savedAt {
                Text("Saved scan from \(savedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let status = presentation.status {
                Text(status == .stopped
                     ? String(localized: "Stopped scan: only items measured before stopping are represented.")
                     : String(localized: "Partial scan: some items or folder contents could not be measured."))
                    .font(.caption).foregroundStyle(.orange)
            }
            Text("Warnings include unreadable locations and intentionally skipped items. Full Disk Access may help with permission errors, but does not remove deliberate exclusions.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                TextField("Search warning paths or messages", text: $query)
                    .textFieldStyle(.roundedBorder).focused($searchFocused)
                    .accessibilityLabel("Search warning paths or messages")
                    .accessibilityIdentifier("scan-warning-search")
                Button("Clear search") { query = ""; searchFocused = true }
                    .disabled(query.isEmpty)
                    .accessibilityIdentifier("clear-warning-search")
            }
            Text("\(matches.count) of \(presentation.entries.count) warnings")
                .font(.caption.weight(.medium))
                .accessibilityIdentifier("scan-warning-count")

            if presentation.entries.isEmpty {
                ContentUnavailableView("No scan warnings", systemImage: "checkmark.circle",
                                       description: Text("This scan has no recorded warnings."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if matches.isEmpty {
                ContentUnavailableView("No matching warnings", systemImage: "magnifyingglass",
                                       description: Text("Try another path or message, or clear the search."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Native List keeps thousands of full warning rows virtualized.
                List(matches) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.message).font(.callout.weight(.medium))
                            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        Text(entry.path).font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        Button {
                            copyNotice = ScanWarningClipboard.copy(entry.path, to: .general)
                                ? String(localized: "Path copied.") : String(localized: "The path could not be copied.")
                        } label: {
                            Label("Copy Path", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.borderless).controlSize(.small)
                        .accessibilityLabel(Text("Copy path for \(entry.path)"))
                        .accessibilityIdentifier("copy-warning-path-\(entry.id)")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("scan-warning-\(entry.id)")
                }
                .listStyle(.plain)
                .accessibilityIdentifier("scan-warning-list")
            }
            Divider()
            HStack {
                if let copyNotice { Text(copyNotice).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("close-scan-warnings")
            }
        }
        .padding(20)
        .frame(width: 740, height: 590)
        .onAppear { searchFocused = true }
        .accessibilityIdentifier("scan-warnings-sheet")
    }
}
