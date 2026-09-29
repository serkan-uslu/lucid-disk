"""Deterministic cleanup-risk rules.

These rules mirror `Sources/LucidDisk/Safety/DeletionSafety.swift`. Both
implementations are checked against `Tests/Fixtures/deletion-safety.json`, so a
rule change must be made on both sides.
"""

from __future__ import annotations

import os
from enum import Enum
from pathlib import Path

from pydantic import BaseModel


class RiskLevel(str, Enum):
    REBUILDABLE = "rebuildable"
    REVIEW = "review"
    SENSITIVE = "sensitive"
    PROTECTED = "protected"


class SafetyClassification(BaseModel):
    risk: RiskLevel
    risk_title: str
    reasons: list[str]
    recommendation: str
    matched_rule: str


RISK_TITLES = {
    RiskLevel.REBUILDABLE: "Rebuildable",
    RiskLevel.REVIEW: "Review first",
    RiskLevel.SENSITIVE: "Sensitive data",
    RiskLevel.PROTECTED: "Protected",
}

RISK_PRIORITY = {
    RiskLevel.REBUILDABLE: 0,
    RiskLevel.REVIEW: 1,
    RiskLevel.SENSITIVE: 2,
    RiskLevel.PROTECTED: 3,
}

PROTECTED_RECOMMENDATION = "Do not remove it with Lucid Disk; use macOS or the owning management tool."


def normalize_path(path: str) -> str:
    expanded = os.path.expanduser(path.strip())
    if not expanded:
        raise ValueError("path must not be empty")
    return os.path.normpath(os.path.abspath(expanded))


def _fold(path: str) -> str:
    # APFS and HFS+ are case-insensitive by default: "/applications" is "/Applications".
    return path.lower()


def is_same(path: str, other: str) -> bool:
    return _fold(path) == _fold(other)


def is_within(path: str, root: str) -> bool:
    path, root = _fold(path), _fold(root)
    return path == root or path.startswith(root if root.endswith("/") else root + "/")


def _classification(
    risk: RiskLevel,
    matched_rule: str,
    reason: str,
    recommendation: str,
) -> SafetyClassification:
    return SafetyClassification(
        risk=risk,
        risk_title=RISK_TITLES[risk],
        reasons=[reason],
        recommendation=recommendation,
        matched_rule=matched_rule,
    )


def classify_path(path: str, home_path: str | None = None) -> SafetyClassification:
    normalized = normalize_path(path)
    home = normalize_path(home_path or str(Path.home()))

    if any(is_same(normalized, root) for root in ("/", home, "/Users")):
        return _classification(
            RiskLevel.PROTECTED,
            "protected.root",
            "This is a filesystem, users, or home root.",
            PROTECTED_RECOMMENDATION,
        )

    if any(is_same(normalized, root) for root in ("/private", "/etc", "/opt", "/usr/local")):
        return _classification(
            RiskLevel.PROTECTED,
            "protected.machine-wide-root",
            "This is a machine-wide application or configuration root.",
            PROTECTED_RECOMMENDATION,
        )

    protected_roots = ("/System", "/bin", "/sbin", "/var", "/private/var", "/Applications", "/Library")
    if any(is_within(normalized, root) for root in protected_roots) or (
        is_within(normalized, "/usr") and not is_within(normalized, "/usr/local")
    ):
        return _classification(
            RiskLevel.PROTECTED,
            "protected.system",
            "This location is part of a protected or machine-wide macOS area.",
            PROTECTED_RECOMMENDATION,
        )

    if is_within(normalized, f"{home}/Library/Developer/Xcode/DerivedData"):
        return _classification(
            RiskLevel.REBUILDABLE,
            "rebuildable.xcode-derived-data",
            "Xcode can rebuild this build and index cache.",
            "Close Xcode and confirm that no active build needs it before moving it to the Trash.",
        )

    if is_within(normalized, f"{home}/Library/Developer/Xcode/Archives"):
        return _classification(
            RiskLevel.SENSITIVE,
            "sensitive.xcode-archives",
            "Archives can contain shipped builds and symbol files.",
            "Verify the release and dSYM requirements in Xcode Organizer first.",
        )

    if is_within(normalized, f"{home}/Library/Developer/Xcode/UserData"):
        return _classification(
            RiskLevel.SENSITIVE,
            "sensitive.xcode-user-data",
            "This can contain snippets, breakpoints, and personal Xcode settings.",
            "Verify its contents and backup before moving it to the Trash.",
        )

    if is_within(normalized, f"{home}/Library/Developer/CoreSimulator/Devices"):
        return _classification(
            RiskLevel.SENSITIVE,
            "sensitive.simulator-data",
            "This can contain simulator app data and device state.",
            "Manage unused simulators with Xcode or simctl instead of deleting the raw folder.",
        )

    if is_within(normalized, f"{home}/Library/Developer/Xcode/iOS DeviceSupport"):
        return _classification(
            RiskLevel.REVIEW,
            "review.ios-device-support",
            "This contains support and symbol data for connected iOS versions.",
            "Confirm that the device versions are old; Xcode can recreate needed support data.",
        )

    review_roots = (
        f"{home}/Library/Caches",
        f"{home}/Library/Logs",
        f"{home}/Downloads",
        f"{home}/.Trash",
    )
    if any(is_within(normalized, root) for root in review_roots):
        return _classification(
            RiskLevel.REVIEW,
            "review.user-cleanup",
            "This location often contains removable items, but it can also contain user data.",
            "Verify the file name, owning app, and whether you still need it.",
        )

    sensitive_user_roots = (
        f"{home}/Desktop",
        f"{home}/Documents",
        f"{home}/Pictures",
        f"{home}/Movies",
        f"{home}/Music",
        f"{home}/Library/Application Support",
        f"{home}/Library/CloudStorage",
        f"{home}/Library/Mail",
        f"{home}/Library/Messages",
        f"{home}/Library/Mobile Documents",
        f"{home}/.ssh",
        f"{home}/.gnupg",
    )
    if any(is_within(normalized, root) for root in sensitive_user_roots):
        return _classification(
            RiskLevel.SENSITIVE,
            "sensitive.user-data",
            "This location can contain personal, synced, or persistent app data.",
            "Prefer the owning app, or verify a backup before moving it to the Trash.",
        )

    if any(is_within(normalized, root) for root in ("/private", "/etc", "/opt", "/usr/local")):
        return _classification(
            RiskLevel.SENSITIVE,
            "sensitive.machine-wide",
            "This is a machine-wide application or configuration area.",
            "Identify the owning app and prefer its uninstall or management flow.",
        )

    if is_within(normalized, "/Users") and not is_within(normalized, home):
        return _classification(
            RiskLevel.SENSITIVE,
            "sensitive.other-user",
            "This location can contain another user's data.",
            "Do not move it to the Trash without the account owner's approval and a verified backup.",
        )

    if is_within(normalized, home):
        return _classification(
            RiskLevel.REVIEW,
            "review.home",
            "Lucid Disk cannot automatically determine whether this user item is safe to remove.",
            "Open it and verify what created it and whether it is backed up.",
        )

    return _classification(
        RiskLevel.REVIEW,
        "review.unknown",
        "This location does not match a known cleanup rule.",
        "Verify its source, contents, and backup before moving it to the Trash.",
    )
