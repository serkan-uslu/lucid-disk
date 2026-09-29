import Foundation
import SwiftUI

enum DeletionRisk: Int, Comparable {
    case rebuildable
    case review
    case sensitive
    case protected

    static func < (lhs: DeletionRisk, rhs: DeletionRisk) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var title: String {
        switch self {
        case .rebuildable: String(localized: "Rebuildable")
        case .review: String(localized: "Review first")
        case .sensitive: String(localized: "Sensitive data")
        case .protected: String(localized: "Protected")
        }
    }

    var systemImage: String {
        switch self {
        case .rebuildable: "arrow.clockwise"
        case .review: "exclamationmark.triangle"
        case .sensitive: "hand.raised"
        case .protected: "lock.shield"
        }
    }

    var color: Color {
        switch self {
        case .rebuildable: .green
        case .review: .orange
        case .sensitive, .protected: .red
        }
    }
}

enum ActionPolicy: Int, Comparable {
    case standardConfirmation
    case strongConfirmation
    case blocked

    static func < (lhs: ActionPolicy, rhs: ActionPolicy) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct DeletionAssessment {
    let risk: DeletionRisk
    let actionPolicy: ActionPolicy
    let summary: String
    let recommendation: String
    let matchedRule: String

    var allowsTrash: Bool { actionPolicy != .blocked }

    init(
        risk: DeletionRisk,
        actionPolicy: ActionPolicy? = nil,
        summary: String,
        recommendation: String,
        matchedRule: String = "default"
    ) {
        self.risk = risk
        self.actionPolicy = actionPolicy ?? {
            switch risk {
            case .protected: .blocked
            case .sensitive: .strongConfirmation
            case .review, .rebuildable: .standardConfirmation
            }
        }()
        self.summary = summary
        self.recommendation = recommendation
        self.matchedRule = matchedRule
    }
}

enum DeletionValidationError: LocalizedError {
    case missingScannedIdentity
    case itemMissing
    case identityChanged
    case newlyBlocked(String)

    var errorDescription: String? {
        switch self {
        case .missingScannedIdentity:
            String(localized: "The item has no scan identity. Scan it again before moving it to the Trash.")
        case .itemMissing:
            String(localized: "The item no longer exists at the scanned path.")
        case .identityChanged:
            String(localized: "The item changed after it was scanned. Scan it again before moving it to the Trash.")
        case .newlyBlocked(let reason):
            reason
        }
    }
}

enum DeletionSafety {
    static func assess(
        node: FileNode,
        homePath: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) -> DeletionAssessment {
        if node.isAggregate {
            return DeletionAssessment(
                risk: .protected,
                summary: String(localized: "‘Other’ represents multiple small items."),
                recommendation: String(localized: "Open the group and select a real file or folder first."),
                matchedRule: "synthetic.aggregate"
            )
        }

        if node.parent == nil {
            return DeletionAssessment(
                risk: .protected,
                summary: String(localized: "A scanned root cannot be moved in one operation."),
                recommendation: String(localized: "Review its children individually."),
                matchedRule: "scan.root"
            )
        }

        return assess(path: node.path, homePath: homePath)
    }

    /// Classifies both the user-visible path and its symlink-resolved path,
    /// returning whichever rule is safer.
    static func assess(
        path: String,
        homePath: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) -> DeletionAssessment {
        let lexicalPath = standardized(path)
        let home = standardized(homePath)
        let lexical = classify(path: lexicalPath, home: home)
        let resolvedPath = URL(fileURLWithPath: lexicalPath).resolvingSymlinksInPath().path
        guard resolvedPath != lexicalPath else { return lexical }
        let resolved = classify(path: resolvedPath, home: home)
        return safer(lexical, resolved)
    }

    /// Must be called immediately before `FileManager.trashItem`. It closes
    /// the scan-to-delete identity race and re-runs canonical path policy.
    @discardableResult
    static func validateBeforeTrash(
        node: FileNode,
        homePath: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) throws -> DeletionAssessment {
        let assessment = assess(node: node, homePath: homePath)
        guard assessment.actionPolicy != .blocked else {
            throw DeletionValidationError.newlyBlocked(assessment.recommendation)
        }
        guard let expected = node.fileIdentity else {
            throw DeletionValidationError.missingScannedIdentity
        }
        guard let current = FileIdentity.read(atPath: node.path) else {
            throw DeletionValidationError.itemMissing
        }
        guard current == expected else {
            throw DeletionValidationError.identityChanged
        }
        return assessment
    }

    private static func classify(path: String, home: String) -> DeletionAssessment {
        if path == "/" || path == home || path == "/Users" {
            return protected(
                summary: String(localized: "This is a filesystem, users, or home root."),
                rule: "protected.root"
            )
        }

        if ["/private", "/etc", "/opt", "/usr/local"].contains(path) {
            return protected(
                summary: String(localized: "This is a machine-wide application or configuration root."),
                rule: "protected.machine-wide-root"
            )
        }

        let protectedRoots = ["/System", "/bin", "/sbin", "/var", "/private/var", "/Applications", "/Library"]
        let protectedSystemPath = protectedRoots.contains { isWithin(path, root: $0) }
            || (isWithin(path, root: "/usr") && !isWithin(path, root: "/usr/local"))
        if protectedSystemPath {
            return protected(
                summary: String(localized: "This location is part of a protected or machine-wide macOS area."),
                rule: "protected.system"
            )
        }

        let derivedData = home + "/Library/Developer/Xcode/DerivedData"
        if isWithin(path, root: derivedData) {
            return DeletionAssessment(
                risk: .rebuildable,
                summary: String(localized: "Xcode can rebuild this build and index cache."),
                recommendation: String(localized: "Close Xcode and confirm that no active build needs it before moving it to the Trash."),
                matchedRule: "rebuildable.xcode-derived-data"
            )
        }

        let xcodeArchives = home + "/Library/Developer/Xcode/Archives"
        if isWithin(path, root: xcodeArchives) {
            return sensitive(
                summary: String(localized: "Archives can contain shipped builds and symbol files."),
                recommendation: String(localized: "Verify the release and dSYM requirements in Xcode Organizer first."),
                rule: "sensitive.xcode-archives"
            )
        }

        let xcodeUserData = home + "/Library/Developer/Xcode/UserData"
        if isWithin(path, root: xcodeUserData) {
            return sensitive(
                summary: String(localized: "This can contain snippets, breakpoints, and personal Xcode settings."),
                recommendation: String(localized: "Verify its contents and backup before moving it to the Trash."),
                rule: "sensitive.xcode-user-data"
            )
        }

        let simulatorDevices = home + "/Library/Developer/CoreSimulator/Devices"
        if isWithin(path, root: simulatorDevices) {
            return sensitive(
                summary: String(localized: "This can contain simulator app data and device state."),
                recommendation: String(localized: "Manage unused simulators with Xcode or simctl instead of deleting the raw folder."),
                rule: "sensitive.simulator-data"
            )
        }

        let deviceSupport = home + "/Library/Developer/Xcode/iOS DeviceSupport"
        if isWithin(path, root: deviceSupport) {
            return DeletionAssessment(
                risk: .review,
                summary: String(localized: "This contains support and symbol data for connected iOS versions."),
                recommendation: String(localized: "Confirm that the device versions are old; Xcode can recreate needed support data."),
                matchedRule: "review.ios-device-support"
            )
        }

        let reviewRoots = [
            home + "/Library/Caches",
            home + "/Library/Logs",
            home + "/Downloads",
            home + "/.Trash"
        ]
        if reviewRoots.contains(where: { isWithin(path, root: $0) }) {
            return DeletionAssessment(
                risk: .review,
                summary: String(localized: "This location often contains removable items, but it can also contain user data."),
                recommendation: String(localized: "Verify the file name, owning app, and whether you still need it."),
                matchedRule: "review.user-cleanup"
            )
        }

        let sensitiveUserRoots = [
            home + "/Desktop",
            home + "/Documents",
            home + "/Pictures",
            home + "/Movies",
            home + "/Music",
            home + "/Library/Application Support",
            home + "/Library/CloudStorage",
            home + "/Library/Mail",
            home + "/Library/Messages",
            home + "/Library/Mobile Documents",
            home + "/.ssh",
            home + "/.gnupg"
        ]
        if sensitiveUserRoots.contains(where: { isWithin(path, root: $0) }) {
            return sensitive(
                summary: String(localized: "This location can contain personal, synced, or persistent app data."),
                recommendation: String(localized: "Prefer the owning app, or verify a backup before moving it to the Trash."),
                rule: "sensitive.user-data"
            )
        }

        let machineWideRoots = ["/private", "/etc", "/opt", "/usr/local"]
        if machineWideRoots.contains(where: { isWithin(path, root: $0) }) {
            return sensitive(
                summary: String(localized: "This is a machine-wide application or configuration area."),
                recommendation: String(localized: "Identify the owning app and prefer its uninstall or management flow."),
                rule: "sensitive.machine-wide"
            )
        }

        if isWithin(path, root: "/Users") && !isWithin(path, root: home) {
            return sensitive(
                summary: String(localized: "This location can contain another user's data."),
                recommendation: String(localized: "Do not move it to the Trash without the account owner's approval and a verified backup."),
                rule: "sensitive.other-user"
            )
        }

        if isWithin(path, root: home) {
            return DeletionAssessment(
                risk: .review,
                summary: String(localized: "Lucid Disk cannot automatically determine whether this user item is safe to remove."),
                recommendation: String(localized: "Open it and verify what created it and whether it is backed up."),
                matchedRule: "review.home"
            )
        }

        return DeletionAssessment(
            risk: .review,
            summary: String(localized: "This location does not match a known cleanup rule."),
            recommendation: String(localized: "Verify its source, contents, and backup before moving it to the Trash."),
            matchedRule: "review.unknown"
        )
    }

    private static func protected(summary: String, rule: String) -> DeletionAssessment {
        DeletionAssessment(
            risk: .protected,
            actionPolicy: .blocked,
            summary: summary,
            recommendation: String(localized: "Do not remove it with Lucid Disk; use macOS or the owning management tool."),
            matchedRule: rule
        )
    }

    private static func sensitive(summary: String, recommendation: String, rule: String) -> DeletionAssessment {
        DeletionAssessment(
            risk: .sensitive,
            actionPolicy: .strongConfirmation,
            summary: summary,
            recommendation: recommendation,
            matchedRule: rule
        )
    }

    private static func safer(_ lhs: DeletionAssessment, _ rhs: DeletionAssessment) -> DeletionAssessment {
        if lhs.actionPolicy != rhs.actionPolicy {
            return lhs.actionPolicy > rhs.actionPolicy ? lhs : rhs
        }
        return lhs.risk >= rhs.risk ? lhs : rhs
    }

    private static func standardized(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private static func isWithin(_ path: String, root: String) -> Bool {
        path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }
}
