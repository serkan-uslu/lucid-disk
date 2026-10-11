import Foundation

/// Captures values from one displayed scan so a later scan cannot replace an
/// open warning viewer's content or its saved/stopped context.
struct ScanWarningsPresentation: Identifiable {
    struct Entry: Identifiable, Equatable {
        /// Original position, retained through filtering. Paths and messages may repeat.
        let id: Int
        let path: String
        let message: String
    }

    let id = UUID()
    let rootPath: String
    let entries: [Entry]
    let savedAt: Date?
    let status: ScanMeasurementPresentation.Status?

    init(root: FileNode, warnings: [ScanWarning], wasStopped: Bool, savedAt: Date?) {
        rootPath = root.path
        entries = warnings.enumerated().map { Entry(id: $0.offset, path: $0.element.path, message: $0.element.message) }
        self.savedAt = savedAt
        // Saved scans retain completeness but do not persist the stopped flag.
        status = ScanMeasurementPresentation(focused: root, root: root, wasStopped: wasStopped, savedAt: savedAt).status
    }

    func matching(_ query: String) -> [Entry] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return entries }
        return entries.filter { $0.path.localizedStandardContains(query) || $0.message.localizedStandardContains(query) }
    }
}
