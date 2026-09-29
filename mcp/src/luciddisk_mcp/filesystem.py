from __future__ import annotations

import os
import stat
from datetime import datetime, timezone
from pathlib import Path

from pydantic import BaseModel, Field

from .safety import RISK_PRIORITY, RISK_TITLES, RiskLevel, SafetyClassification, classify_path, normalize_path

# Same exclusions as the app's DiskScanner. /System/Volumes holds the firmlinked
# Data volume, so descending into it would count /Users and friends twice.
EXCLUDED_PATHS = frozenset({
    "/System/Volumes", "/Volumes", "/dev", "/Network", "/.vol",
    "/home", "/cores", "/afs", "/net",
})


class SizeMeasurement(BaseModel):
    logical_size_bytes: int = 0
    allocated_size_bytes: int = 0
    entries_scanned: int = 0
    complete: bool = True
    size_accuracy: str = "estimated"
    errors: list[str] = Field(default_factory=list)
    warnings: list[str] = Field(default_factory=list)


class PathAssessment(BaseModel):
    path: str
    resolved_path: str
    name: str
    exists: bool
    kind: str
    symlink_target: str | None = None
    modified_at: str | None = None
    logical_size_bytes: int | None = None
    allocated_size_bytes: int | None = None
    size_complete: bool = True
    entries_scanned: int = 0
    scan_errors: list[str] = Field(default_factory=list)
    size_accuracy: str
    warnings: list[str] = Field(default_factory=list)
    risk: RiskLevel
    effective_risk: RiskLevel
    risk_title: str
    reasons: list[str]
    recommendation: str
    matched_rule: str


class AssessmentBatch(BaseModel):
    assessments: list[PathAssessment]
    total_allocated_size_bytes: int
    all_sizes_complete: bool
    size_accuracy: str
    warnings: list[str] = Field(default_factory=list)


class DirectoryInventory(BaseModel):
    root: str
    resolved_root: str
    items: list[PathAssessment]
    returned_items: int
    discovered_children: int
    children_complete: bool
    measurement_complete: bool
    remaining_entry_budget: int
    size_accuracy: str
    warnings: list[str] = Field(default_factory=list)


class CleanupPlan(BaseModel):
    paths: list[PathAssessment]
    total_allocated_size_bytes: int
    counts_by_risk: dict[str, int]
    blockers: list[str]
    decision_questions: list[str]
    requires_explicit_user_decision: bool = True
    size_accuracy: str
    warnings: list[str] = Field(default_factory=list)


def _allocated_bytes(info: os.stat_result) -> int:
    blocks = getattr(info, "st_blocks", None)
    return int(blocks * 512) if blocks is not None else int(info.st_size)


def _kind(info: os.stat_result) -> str:
    mode = info.st_mode
    if stat.S_ISLNK(mode):
        return "symlink"
    if stat.S_ISDIR(mode):
        return "directory"
    if stat.S_ISREG(mode):
        return "file"
    return "other"


def _classifications(path: str) -> tuple[str, SafetyClassification, SafetyClassification]:
    resolved = os.path.realpath(path)
    lexical = classify_path(path)
    resolved_classification = classify_path(resolved)
    return resolved, lexical, max(
        (lexical, resolved_classification),
        key=lambda item: RISK_PRIORITY[item.risk],
    )


def measure_path(path: str, max_entries: int = 200_000) -> SizeMeasurement:
    if max_entries < 1:
        raise ValueError("max_entries must be at least 1")

    normalized = normalize_path(path)
    result = SizeMeasurement()
    stack = [normalized]
    seen_files: set[tuple[int, int]] = set()
    duplicate_hard_links = 0
    saw_regular_file = False
    root_device: int | None = None
    skipped_volumes = 0
    skipped_excluded = 0

    while stack:
        if result.entries_scanned >= max_entries:
            result.complete = False
            result.warnings.append("Entry budget reached; reported sizes are incomplete.")
            break

        current = stack.pop()
        try:
            info = os.lstat(current)
        except OSError as error:
            result.complete = False
            if len(result.errors) < 20:
                result.errors.append(f"{current}: {error.strerror or error}")
            continue

        result.entries_scanned += 1
        if root_device is None:
            root_device = int(info.st_dev)

        if stat.S_ISREG(info.st_mode):
            saw_regular_file = True
            result.logical_size_bytes += int(info.st_size)
            identity = (int(info.st_dev), int(info.st_ino))
            if info.st_nlink > 1 and identity in seen_files:
                duplicate_hard_links += 1
            else:
                if info.st_nlink > 1:
                    seen_files.add(identity)
                result.allocated_size_bytes += _allocated_bytes(info)
            continue

        if stat.S_ISLNK(info.st_mode):
            result.allocated_size_bytes += _allocated_bytes(info)
            result.logical_size_bytes += int(info.st_size)
            continue

        if not stat.S_ISDIR(info.st_mode):
            continue

        # Directory entries themselves are not counted, matching the app scanner.
        if current != normalized and int(info.st_dev) != root_device:
            skipped_volumes += 1
            result.complete = False
            continue
        if current in EXCLUDED_PATHS:
            skipped_excluded += 1
            result.complete = False
            continue

        try:
            with os.scandir(current) as entries:
                for entry in entries:
                    stack.append(entry.path)
        except OSError as error:
            result.complete = False
            if len(result.errors) < 20:
                result.errors.append(f"{current}: {error.strerror or error}")

    if skipped_volumes:
        result.warnings.append(
            f"Skipped {skipped_volumes} director{'y' if skipped_volumes == 1 else 'ies'} on other mounted volumes."
        )
    if skipped_excluded:
        result.warnings.append(
            "Skipped system locations such as /System/Volumes and /Volumes to avoid double counting."
        )
    if duplicate_hard_links:
        result.warnings.append(
            f"Deduplicated {duplicate_hard_links} hard-linked entr{'y' if duplicate_hard_links == 1 else 'ies'} by device and inode."
        )
    if saw_regular_file:
        result.warnings.append(
            "Allocated size uses filesystem-reported blocks; shared APFS clone extents may make physical usage approximate."
        )
    if result.errors:
        result.warnings.append("Some entries could not be read; inspect scan_errors before making a cleanup decision.")
    result.size_accuracy = "estimated" if result.complete else "incomplete"
    return result


def assess_path(path: str, calculate_size: bool = True, max_entries: int = 200_000) -> PathAssessment:
    normalized = normalize_path(path)
    resolved, lexical_classification, classification = _classifications(normalized)
    path_warnings: list[str] = []
    if resolved != normalized:
        path_warnings.append("The resolved path differs from the supplied lexical path; both safety classifications were evaluated.")
    if classification.risk != lexical_classification.risk:
        path_warnings.append("The resolved path has a stricter risk classification; effective_risk uses the stricter result.")

    try:
        info = os.lstat(normalized)
    except FileNotFoundError:
        return PathAssessment(
            path=normalized,
            resolved_path=resolved,
            name=Path(normalized).name or normalized,
            exists=False,
            kind="missing",
            size_complete=False,
            size_accuracy="unavailable",
            warnings=[*path_warnings, "The path does not currently exist, so its identity and size could not be verified."],
            risk=lexical_classification.risk,
            effective_risk=classification.risk,
            risk_title=classification.risk_title,
            reasons=[*classification.reasons, "The path does not currently exist on the filesystem."],
            recommendation="Refresh the Lucid Disk scan and verify the path again.",
            matched_rule=classification.matched_rule,
        )
    except OSError as error:
        effective_risk = max(
            (classification.risk, RiskLevel.SENSITIVE),
            key=lambda risk: RISK_PRIORITY[risk],
        )
        return PathAssessment(
            path=normalized,
            resolved_path=resolved,
            name=Path(normalized).name or normalized,
            exists=False,
            kind="unreadable",
            size_complete=False,
            scan_errors=[str(error)],
            size_accuracy="unavailable",
            warnings=[*path_warnings, "The path metadata could not be read."],
            risk=lexical_classification.risk,
            effective_risk=effective_risk,
            risk_title=RISK_TITLES[effective_risk],
            reasons=["The path metadata could not be read, so no safe decision is possible."],
            recommendation="Verify permissions and the path in Finder before taking any action.",
            matched_rule="sensitive.unreadable-path",
        )

    measurement = measure_path(normalized, max_entries=max_entries) if calculate_size else None
    modified_at = datetime.fromtimestamp(info.st_mtime, tz=timezone.utc).isoformat()
    symlink_target = os.readlink(normalized) if stat.S_ISLNK(info.st_mode) else None
    warnings = [*path_warnings, *(measurement.warnings if measurement else ["Recursive size measurement was not requested."])]

    return PathAssessment(
        path=normalized,
        resolved_path=resolved,
        name=Path(normalized).name or normalized,
        exists=True,
        kind=_kind(info),
        symlink_target=symlink_target,
        modified_at=modified_at,
        # Without a measurement a directory has no meaningful size (its own entry is not counted).
        logical_size_bytes=measurement.logical_size_bytes if measurement else (
            None if stat.S_ISDIR(info.st_mode) else int(info.st_size)
        ),
        allocated_size_bytes=measurement.allocated_size_bytes if measurement else (
            None if stat.S_ISDIR(info.st_mode) else _allocated_bytes(info)
        ),
        size_complete=measurement.complete if measurement else True,
        entries_scanned=measurement.entries_scanned if measurement else 1,
        scan_errors=measurement.errors if measurement else [],
        size_accuracy=measurement.size_accuracy if measurement else "metadata-only",
        warnings=warnings,
        risk=lexical_classification.risk,
        effective_risk=classification.risk,
        risk_title=classification.risk_title,
        reasons=classification.reasons,
        recommendation=classification.recommendation,
        matched_rule=classification.matched_rule,
    )


def assess_many(paths: list[str], calculate_size: bool, max_entries: int) -> AssessmentBatch:
    if not paths:
        raise ValueError("paths must contain at least one path")
    if len(paths) > 50:
        raise ValueError("at most 50 paths can be assessed at once")
    if max_entries < 1 or max_entries > 2_000_000:
        raise ValueError("max_entries must be between 1 and 2000000")

    remaining = max_entries
    assessments: list[PathAssessment] = []
    for path in paths:
        if calculate_size and remaining <= 0:
            assessment = assess_path(path, calculate_size=False, max_entries=1)
            assessment.size_complete = False
            assessment.size_accuracy = "incomplete"
            assessment.warnings.append("Shared entry budget was exhausted before this path could be measured.")
        else:
            assessment = assess_path(path, calculate_size=calculate_size, max_entries=max(1, remaining))
        assessments.append(assessment)
        remaining = max(0, remaining - assessment.entries_scanned)

    return AssessmentBatch(
        assessments=assessments,
        total_allocated_size_bytes=sum(item.allocated_size_bytes or 0 for item in assessments),
        all_sizes_complete=all(item.size_complete for item in assessments),
        size_accuracy="incomplete" if any(not item.size_complete for item in assessments) else (
            "estimated" if calculate_size else "metadata-only"
        ),
        warnings=list(dict.fromkeys(warning for item in assessments for warning in item.warnings)),
    )


def inventory_directory(
    path: str,
    min_size_bytes: int = 0,
    limit: int = 100,
    max_children: int = 1_000,
    max_entries_total: int = 200_000,
) -> DirectoryInventory:
    normalized = normalize_path(path)
    if limit < 1 or limit > 200:
        raise ValueError("limit must be between 1 and 200")
    if min_size_bytes < 0:
        raise ValueError("min_size_bytes cannot be negative")
    if max_children < 1 or max_children > 5_000:
        raise ValueError("max_children must be between 1 and 5000")
    if max_entries_total < 1 or max_entries_total > 2_000_000:
        raise ValueError("max_entries_total must be between 1 and 2000000")
    if not os.path.isdir(normalized):
        raise ValueError("path must be an existing directory")

    try:
        with os.scandir(normalized) as entries:
            child_paths = [entry.path for _, entry in zip(range(max_children + 1), entries)]
    except OSError as error:
        raise ValueError(f"directory cannot be read: {error}") from error

    children_complete = len(child_paths) <= max_children
    child_paths = child_paths[:max_children]
    remaining = max_entries_total
    items: list[PathAssessment] = []
    processed_children = 0
    all_measurements_complete = True
    all_warnings: list[str] = []

    for child_path in child_paths:
        if remaining <= 0:
            break
        item = assess_path(child_path, calculate_size=True, max_entries=max(1, remaining))
        processed_children += 1
        all_measurements_complete = all_measurements_complete and item.size_complete
        all_warnings.extend(item.warnings)
        remaining = max(0, remaining - item.entries_scanned)
        if (item.allocated_size_bytes or 0) >= min_size_bytes:
            items.append(item)

    items.sort(key=lambda item: item.allocated_size_bytes or 0, reverse=True)
    selected = items[:limit]
    measurement_complete = (
        children_complete
        and processed_children == len(child_paths)
        and all_measurements_complete
    )
    warnings = list(dict.fromkeys(all_warnings))
    if not children_complete:
        warnings.append("Child limit reached; not every direct child was inventoried.")
    if processed_children < len(child_paths):
        warnings.append("Shared entry budget was exhausted before every child could be measured.")

    return DirectoryInventory(
        root=normalized,
        resolved_root=os.path.realpath(normalized),
        items=selected,
        returned_items=len(selected),
        discovered_children=len(child_paths),
        children_complete=children_complete,
        measurement_complete=measurement_complete,
        remaining_entry_budget=remaining,
        size_accuracy="estimated" if measurement_complete else "incomplete",
        warnings=warnings,
    )


def create_plan(paths: list[str], calculate_size: bool, max_entries: int) -> CleanupPlan:
    batch = assess_many(paths, calculate_size=calculate_size, max_entries=max_entries)
    counts = {risk.value: 0 for risk in RiskLevel}
    for assessment in batch.assessments:
        counts[assessment.effective_risk.value] += 1

    blockers = [
        f"{item.path}: {item.recommendation}"
        for item in batch.assessments
        if item.effective_risk in {RiskLevel.PROTECTED, RiskLevel.SENSITIVE} or not item.exists
    ]
    questions = [
        "Which app created this file or folder?",
        "Is there a verified backup of its contents?",
        "Can the item be regenerated, and is the owning app currently closed?",
    ]
    if any(item.matched_rule == "sensitive.xcode-archives" for item in batch.assessments):
        questions.append("Are this archive's dSYM files still needed to symbolicate past crash reports?")

    return CleanupPlan(
        paths=batch.assessments,
        total_allocated_size_bytes=batch.total_allocated_size_bytes,
        counts_by_risk=counts,
        blockers=blockers,
        decision_questions=questions,
        size_accuracy=batch.size_accuracy,
        warnings=batch.warnings,
    )


class LargeFile(BaseModel):
    path: str
    name: str
    logical_size_bytes: int
    allocated_size_bytes: int
    modified_at: str
    effective_risk: RiskLevel
    risk_title: str
    matched_rule: str


class LargeFileReport(BaseModel):
    root: str
    files: list[LargeFile]
    min_size_bytes: int
    entries_scanned: int
    complete: bool
    size_accuracy: str
    warnings: list[str] = Field(default_factory=list)


class KnownLocation(BaseModel):
    label: str
    path: str
    exists: bool
    allocated_size_bytes: int = 0
    size_complete: bool = True
    effective_risk: RiskLevel
    risk_title: str
    matched_rule: str
    recommendation: str
    note: str


class KnownLocationReport(BaseModel):
    locations: list[KnownLocation]
    total_allocated_size_bytes: int
    all_sizes_complete: bool
    size_accuracy: str
    warnings: list[str] = Field(default_factory=list)


def find_large_files(
    path: str,
    min_size_bytes: int = 100 * 1024 * 1024,
    limit: int = 50,
    max_entries: int = 200_000,
) -> LargeFileReport:
    """Walk one volume below `path` and return the largest regular files."""
    normalized = normalize_path(path)
    if limit < 1 or limit > 500:
        raise ValueError("limit must be between 1 and 500")
    if min_size_bytes < 0:
        raise ValueError("min_size_bytes cannot be negative")
    if max_entries < 1 or max_entries > 2_000_000:
        raise ValueError("max_entries must be between 1 and 2000000")
    if not os.path.isdir(normalized):
        raise ValueError("path must be an existing directory")

    root_device = os.lstat(normalized).st_dev
    stack = [normalized]
    seen: set[tuple[int, int]] = set()
    found: list[tuple[int, str, os.stat_result]] = []
    entries = 0
    complete = True
    warnings: list[str] = []
    unreadable = 0

    while stack:
        if entries >= max_entries:
            complete = False
            warnings.append("Entry budget reached; larger files may exist beyond the scanned part.")
            break
        current = stack.pop()
        try:
            with os.scandir(current) as iterator:
                children = list(iterator)
        except OSError:
            unreadable += 1
            complete = False
            continue
        for entry in children:
            entries += 1
            try:
                info = entry.stat(follow_symlinks=False)
            except OSError:
                complete = False
                continue
            if stat.S_ISDIR(info.st_mode):
                if info.st_dev != root_device or entry.path in EXCLUDED_PATHS:
                    complete = False
                    continue
                stack.append(entry.path)
            elif stat.S_ISREG(info.st_mode):
                identity = (int(info.st_dev), int(info.st_ino))
                if info.st_nlink > 1:
                    if identity in seen:
                        continue
                    seen.add(identity)
                allocated = _allocated_bytes(info)
                if allocated >= min_size_bytes:
                    found.append((allocated, entry.path, info))

    if unreadable:
        warnings.append(f"{unreadable} director{'y' if unreadable == 1 else 'ies'} could not be read.")

    found.sort(key=lambda item: item[0], reverse=True)
    files: list[LargeFile] = []
    for allocated, file_path, info in found[:limit]:
        _, _, classification = _classifications(file_path)
        files.append(LargeFile(
            path=file_path,
            name=os.path.basename(file_path),
            logical_size_bytes=int(info.st_size),
            allocated_size_bytes=allocated,
            modified_at=datetime.fromtimestamp(info.st_mtime, tz=timezone.utc).isoformat(),
            effective_risk=classification.risk,
            risk_title=classification.risk_title,
            matched_rule=classification.matched_rule,
        ))

    return LargeFileReport(
        root=normalized,
        files=files,
        min_size_bytes=min_size_bytes,
        entries_scanned=entries,
        complete=complete,
        size_accuracy="estimated" if complete else "incomplete",
        warnings=warnings,
    )


# Well-known places that commonly grow large. Entries must not nest, or the total
# would count shared bytes twice. Risk still comes from the shared rules.
KNOWN_LOCATIONS: tuple[tuple[str, str, str], ...] = (
    ("Xcode DerivedData", "~/Library/Developer/Xcode/DerivedData", "Build and index cache; Xcode rebuilds it."),
    ("Xcode Archives", "~/Library/Developer/Xcode/Archives", "Shipped builds and dSYM files."),
    ("iOS DeviceSupport", "~/Library/Developer/Xcode/iOS DeviceSupport", "Symbols for connected device versions."),
    ("Simulator devices", "~/Library/Developer/CoreSimulator/Devices", "Manage with Xcode or `xcrun simctl delete unavailable`."),
    ("User caches", "~/Library/Caches", "App caches; the owning app can usually recreate them."),
    ("User logs", "~/Library/Logs", "Diagnostic logs."),
    ("Downloads", "~/Downloads", "User downloads; review individually."),
    ("Trash", "~/.Trash", "Already in Trash; emptying it frees the space."),
    ("npm cache", "~/.npm", "Package cache; `npm cache clean` manages it."),
    ("Gradle caches", "~/.gradle/caches", "Build cache; Gradle downloads it again."),
)


def summarize_known_locations(max_entries: int = 400_000) -> KnownLocationReport:
    if max_entries < 1 or max_entries > 2_000_000:
        raise ValueError("max_entries must be between 1 and 2000000")
    remaining = max_entries
    locations: list[KnownLocation] = []
    warnings: list[str] = []
    for label, raw_path, note in KNOWN_LOCATIONS:
        location_path = normalize_path(raw_path)
        _, _, classification = _classifications(location_path)
        exists = os.path.isdir(location_path)
        allocated = 0
        complete = True
        if exists:
            if remaining <= 0:
                complete = False
            else:
                measurement = measure_path(location_path, max_entries=remaining)
                allocated = measurement.allocated_size_bytes
                complete = measurement.complete
                remaining = max(0, remaining - measurement.entries_scanned)
        locations.append(KnownLocation(
            label=label,
            path=location_path,
            exists=exists,
            allocated_size_bytes=allocated,
            size_complete=complete,
            effective_risk=classification.risk,
            risk_title=classification.risk_title,
            matched_rule=classification.matched_rule,
            recommendation=classification.recommendation,
            note=note,
        ))
    if remaining <= 0:
        warnings.append("Shared entry budget was exhausted; some sizes are incomplete.")
    all_complete = all(item.size_complete for item in locations)
    locations.sort(key=lambda item: item.allocated_size_bytes, reverse=True)
    return KnownLocationReport(
        locations=locations,
        total_allocated_size_bytes=sum(item.allocated_size_bytes for item in locations),
        all_sizes_complete=all_complete,
        size_accuracy="estimated" if all_complete else "incomplete",
        warnings=warnings,
    )
