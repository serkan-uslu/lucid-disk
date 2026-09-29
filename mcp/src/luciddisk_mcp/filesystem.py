from __future__ import annotations

import os
import stat
from datetime import datetime, timezone
from pathlib import Path

from pydantic import BaseModel, Field

from .safety import RISK_PRIORITY, RISK_TITLES, RiskLevel, SafetyClassification, classify_path, normalize_path


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

        result.allocated_size_bytes += _allocated_bytes(info)

        if stat.S_ISLNK(info.st_mode):
            result.logical_size_bytes += int(info.st_size)
            continue

        if not stat.S_ISDIR(info.st_mode):
            continue

        try:
            with os.scandir(current) as entries:
                for entry in entries:
                    stack.append(entry.path)
        except OSError as error:
            result.complete = False
            if len(result.errors) < 20:
                result.errors.append(f"{current}: {error.strerror or error}")

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
            reasons=[*classification.reasons, "Yol şu anda dosya sisteminde bulunamadı."],
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
            reasons=["Yolun bilgileri okunamadığı için güvenli karar verilemiyor."],
            recommendation="İzinleri ve yolu Finder'da doğrulamadan işlem yapmayın.",
            matched_rule="unreadable_path",
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
        logical_size_bytes=measurement.logical_size_bytes if measurement else int(info.st_size),
        allocated_size_bytes=measurement.allocated_size_bytes if measurement else _allocated_bytes(info),
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
        "Bu dosyayı veya klasörü hangi uygulama oluşturdu?",
        "İçeriğin doğrulanmış bir yedeği var mı?",
        "Öğe yeniden üretilebilir mi ve ilgili uygulama şu anda kapalı mı?",
    ]
    if any(item.matched_rule == "xcode_archives" for item in batch.assessments):
        questions.append("Bu arşivin dSYM dosyalarına geçmiş crash raporları için ihtiyaç var mı?")

    return CleanupPlan(
        paths=batch.assessments,
        total_allocated_size_bytes=batch.total_allocated_size_bytes,
        counts_by_risk=counts,
        blockers=blockers,
        decision_questions=questions,
        size_accuracy=batch.size_accuracy,
        warnings=batch.warnings,
    )
