import Foundation
import SwiftUI

public enum DeletionRisk: Int, Comparable, Sendable {
    case rebuildable
    case review
    case sensitive
    case protected

    public static func < (lhs: DeletionRisk, rhs: DeletionRisk) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var title: String {
        switch self {
        case .rebuildable: String(localized: "Rebuildable")
        case .review: String(localized: "Review first")
        case .sensitive: String(localized: "Sensitive data")
        case .protected: String(localized: "Protected")
        }
    }

    public var systemImage: String {
        switch self {
        case .rebuildable: "arrow.clockwise"
        case .review: "exclamationmark.triangle"
        case .sensitive: "hand.raised"
        case .protected: "lock.shield"
        }
    }

    public var color: Color {
        switch self {
        case .rebuildable: .green
        case .review: .orange
        case .sensitive, .protected: .red
        }
    }
}

public enum ActionPolicy: Int, Comparable, Sendable {
    case standardConfirmation
    case strongConfirmation
    case blocked

    public static func < (lhs: ActionPolicy, rhs: ActionPolicy) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// The deterministic verdict for one path. Extensions may read it but never override it.
public struct DeletionAssessment: Sendable {
    public let risk: DeletionRisk
    public let actionPolicy: ActionPolicy
    public let summary: String
    public let recommendation: String
    public let matchedRule: String

    public var allowsTrash: Bool { actionPolicy != .blocked }

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

public enum DeletionSafety {
    public static func assess(
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

        let assessment = assess(path: node.path, homePath: homePath)
        // A folder whose contents could not all be read may hold more than the
        // scan saw, so it never moves with a standard confirmation.
        if node.isDirectory, node.measurementAccuracy == .incomplete,
           assessment.actionPolicy == .standardConfirmation {
            // Unknown is not the same as sensitive: keep the path's risk, raise only the confirmation.
            return DeletionAssessment(
                risk: assessment.risk,
                actionPolicy: .strongConfirmation,
                summary: String(localized: "Some folders inside could not be read, so Lucid Disk cannot verify everything this would move."),
                recommendation: String(localized: "Open it in Finder and check its contents, or grant Full Disk Access and scan again."),
                matchedRule: "review.unverified-contents"
            )
        }
        return assessment
    }

    /// The stricter of two verdicts. Used when one move covers several assessed items.
    static func stricter(_ lhs: DeletionAssessment, _ rhs: DeletionAssessment) -> DeletionAssessment {
        safer(lhs, rhs)
    }

    /// Classifies both the user-visible path and its symlink-resolved path,
    /// returning whichever rule is safer.
    public static func assess(
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

    /// APFS and HFS+ volumes are case-insensitive by default, so `/applications`
    /// names the same folder as `/Applications`. Rules compare case-folded paths so
    /// a differently cased path can never slip past a protected rule.
    private static func classify(path: String, home: String) -> DeletionAssessment {
        if ["/", home, "/Users"].contains(where: { isSame(path, $0) }) {
            return protected(
                summary: String(localized: "This is a filesystem, users, or home root."),
                rule: "protected.root"
            )
        }

        if ["/private", "/etc", "/opt", "/usr/local"].contains(where: { isSame(path, $0) }) {
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

        if isSame(path, home + "/Library") {
            return protected(
                summary: String(localized: "This is your user Library: app data, settings, mail, messages and keychains."),
                rule: "protected.user-library"
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
            home + "/Library/Containers",
            home + "/Library/Group Containers",
            home + "/Library/Keychains",
            home + "/Library/Preferences",
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

        // A folder that contains a sensitive location is at least as sensitive:
        // moving ~/Library/Developer also moves Xcode Archives inside it.
        let sensitiveRoots = sensitiveUserRoots + [xcodeArchives, xcodeUserData, simulatorDevices]
        if sensitiveRoots.contains(where: { isStrictAncestor(path, of: $0) }) {
            return sensitive(
                summary: String(localized: "This folder contains a location with personal or persistent app data."),
                recommendation: String(localized: "Open it and move only the items you have verified, or confirm a backup first."),
                rule: "sensitive.contains-sensitive"
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

    private static func isSame(_ path: String, _ other: String) -> Bool {
        path.lowercased() == other.lowercased()
    }

    private static func isStrictAncestor(_ path: String, of other: String) -> Bool {
        let path = path.lowercased()
        let other = other.lowercased()
        return other.hasPrefix(path.hasSuffix("/") ? path : path + "/")
    }

    private static func isWithin(_ path: String, root: String) -> Bool {
        let path = path.lowercased()
        let root = root.lowercased()
        return path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }
}
