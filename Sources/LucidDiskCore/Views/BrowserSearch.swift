import Foundation

enum BrowserSearchScope: String, CaseIterable, Identifiable {
    case all, folder
    var id: Self { self }
    var title: String {
        switch self {
        case .all: String(localized: "All scanned items")
        case .folder: String(localized: "This folder and subfolders")
        }
    }
}

enum BrowserItemKind: String, CaseIterable, Identifiable {
    case any, files, folders
    var id: Self { self }
    var title: String {
        switch self {
        case .any: String(localized: "Files and folders")
        case .files: String(localized: "Files only")
        case .folders: String(localized: "Folders only")
        }
    }
}

enum BrowserModifiedFilter: String, CaseIterable, Identifiable {
    case any, week, month, olderYear
    var id: Self { self }
    var title: String {
        switch self {
        case .any: String(localized: "Any date")
        case .week: String(localized: "Last 7 days")
        case .month: String(localized: "Last 30 days")
        case .olderYear: String(localized: "Older than a year")
        }
    }
}

struct BrowserSearchFilters: Equatable {
    var scope: BrowserSearchScope = .all
    var kind: BrowserItemKind = .any
    var minimumBytes: Int64 = 0
    var extensions = ""
    var modified: BrowserModifiedFilter = .any

    var isFiltering: Bool {
        kind != .any || minimumBytes > 0 || !extensions.trimmingCharacters(in: .whitespaces).isEmpty || modified != .any
    }

    func matches(_ node: FileNode, query: String, now: Date) -> Bool {
        if kind == .files && node.isDirectory { return false }
        if kind == .folders && !node.isDirectory { return false }
        guard node.size >= minimumBytes else { return false }
        let suffixes = extensions.lowercased().split { $0 == "," || $0.isWhitespace }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }.filter { !$0.isEmpty }
        if !suffixes.isEmpty {
            guard !node.isDirectory, suffixes.contains((node.name as NSString).pathExtension.lowercased()) else { return false }
        }
        if modified != .any {
            guard let date = node.modifiedAt else { return false }
            let age = now.timeIntervalSince(date)
            switch modified {
            case .week: if age > 7 * 86_400 { return false }
            case .month: if age > 30 * 86_400 { return false }
            case .olderYear: if age < 365 * 86_400 { return false }
            case .any: break
            }
        }
        // Every word must match; paths make multi-word queries useful across nested folders.
        return query.split(whereSeparator: \.isWhitespace).allSatisfy {
            node.path.range(of: String($0), options: [.caseInsensitive, .diacriticInsensitive]) != nil
                || node.name.range(of: String($0), options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}
