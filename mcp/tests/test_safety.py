from __future__ import annotations

import json
import os
import tempfile
import unittest
from pathlib import Path

from luciddisk_mcp.filesystem import assess_path, create_plan, measure_path
from luciddisk_mcp.safety import RiskLevel, classify_path


class SafetyClassificationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.home = "/Users/example"

    def test_system_path_is_protected(self) -> None:
        result = classify_path("/System/Library/Frameworks", home_path=self.home)
        self.assertEqual(result.risk, RiskLevel.PROTECTED)

    def test_usr_local_is_sensitive_not_sip_protected(self) -> None:
        result = classify_path("/usr/local/bin/tool", home_path=self.home)
        self.assertEqual(result.risk, RiskLevel.SENSITIVE)

    def test_derived_data_is_rebuildable(self) -> None:
        result = classify_path(
            "/Users/example/Library/Developer/Xcode/DerivedData/App-abcd",
            home_path=self.home,
        )
        self.assertEqual(result.risk, RiskLevel.REBUILDABLE)

    def test_xcode_archives_are_sensitive(self) -> None:
        result = classify_path(
            "/Users/example/Library/Developer/Xcode/Archives/2026-08-04/App.xcarchive",
            home_path=self.home,
        )
        self.assertEqual(result.risk, RiskLevel.SENSITIVE)

    def test_unknown_home_file_requires_review(self) -> None:
        result = classify_path("/Users/example/tmp/notes.txt", home_path=self.home)
        self.assertEqual(result.risk, RiskLevel.REVIEW)

    def test_other_users_data_is_sensitive(self) -> None:
        result = classify_path("/Users/someone-else/Documents", home_path=self.home)
        self.assertEqual(result.risk, RiskLevel.SENSITIVE)

    def test_shared_deletion_safety_fixture(self) -> None:
        fixture_path = Path(__file__).resolve().parents[2] / "Tests" / "Fixtures" / "deletion-safety.json"
        cases = json.loads(fixture_path.read_text(encoding="utf-8"))

        for case in cases:
            with self.subTest(path=case["path"]):
                result = classify_path(case["path"], home_path=case["home"])
                self.assertEqual(result.risk.value, case["risk"])


class FilesystemAssessmentTests(unittest.TestCase):
    def test_assessment_measures_directory_without_changing_it(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            file_path = Path(directory) / "sample.bin"
            file_path.write_bytes(b"x" * 4096)

            result = assess_path(directory)

            self.assertTrue(result.exists)
            self.assertEqual(result.kind, "directory")
            self.assertGreaterEqual(result.logical_size_bytes or 0, 4096)
            self.assertTrue(file_path.exists())

    def test_resolved_protected_symlink_sets_effective_risk(self) -> None:
        with tempfile.TemporaryDirectory(dir=Path.cwd()) as directory:
            link = Path(directory) / "innocent-name"
            link.symlink_to("/System")

            result = assess_path(str(link), calculate_size=False)

            self.assertEqual(result.resolved_path, "/System")
            self.assertEqual(result.effective_risk, RiskLevel.PROTECTED)
            self.assertTrue(any("stricter" in warning for warning in result.warnings))

    def test_hard_link_allocated_bytes_are_counted_once(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            original = root / "original.bin"
            linked = root / "linked.bin"
            original.write_bytes(b"x" * 4096)
            os.link(original, linked)

            result = measure_path(directory)
            directory_info = os.lstat(directory)
            file_info = os.lstat(original)
            expected = directory_info.st_blocks * 512 + file_info.st_blocks * 512

            self.assertEqual(result.allocated_size_bytes, expected)
            self.assertTrue(any("hard-linked" in warning for warning in result.warnings))

    def test_budget_exhaustion_is_explicitly_incomplete(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            (Path(directory) / "child").write_text("data", encoding="utf-8")

            result = assess_path(directory, max_entries=1)

            self.assertFalse(result.size_complete)
            self.assertEqual(result.size_accuracy, "incomplete")
            self.assertTrue(any("budget" in warning.lower() for warning in result.warnings))

    def test_cleanup_plan_blocks_protected_paths(self) -> None:
        result = create_plan(["/System"], calculate_size=False, max_entries=10)
        self.assertEqual(result.counts_by_risk[RiskLevel.PROTECTED.value], 1)
        self.assertTrue(result.blockers)
        self.assertFalse(hasattr(result, "changed_files"))

    def test_invalid_shared_entry_budget_is_rejected(self) -> None:
        with self.assertRaises(ValueError):
            create_plan(["/System"], calculate_size=True, max_entries=0)


if __name__ == "__main__":
    unittest.main()
