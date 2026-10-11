from __future__ import annotations

import errno
import os
import stat
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from luciddisk_mcp.filesystem import assess_many, assess_path, create_plan


def allocated_bytes(path: Path) -> int:
    info = path.lstat()
    return info.st_blocks * 512


class AssessmentBatchTotalTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.root = Path(self.temporary_directory.name)

    def file(self, name: str, size: int = 4096) -> Path:
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b"x" * size)
        return path

    def test_parent_and_child_directory_total_is_independent_of_path_order(self) -> None:
        child_file = self.file("parent/child/file.bin")
        sibling_file = self.file("parent/sibling.bin", 8192)
        parent = child_file.parent.parent
        child = child_file.parent
        expected = allocated_bytes(child_file) + allocated_bytes(sibling_file)
        standalone = {str(path): assess_path(str(path)) for path in (parent, child)}

        for paths in ([parent, child], [child, parent]):
            with self.subTest(paths=paths):
                result = assess_many([str(path) for path in paths], calculate_size=True, max_entries=100)
                self.assertEqual(result.total_allocated_size_bytes, expected)
                self.assertTrue(result.all_sizes_complete)
                self.assertEqual(result.size_accuracy, "estimated")
                self.assertTrue(any("The batch total counts each observed" in warning for warning in result.warnings))
                for assessment in result.assessments:
                    self.assertEqual(assessment, standalone[assessment.path])

    def test_parent_and_direct_file_do_not_double_count_single_link_file(self) -> None:
        file_path = self.file("parent/file.bin")
        self.assertEqual(file_path.lstat().st_nlink, 1)

        for paths in ([file_path.parent, file_path], [file_path, file_path.parent]):
            with self.subTest(paths=paths):
                result = assess_many([str(path) for path in paths], calculate_size=True, max_entries=100)
                self.assertEqual(result.total_allocated_size_bytes, allocated_bytes(file_path))
                self.assertEqual([item.allocated_size_bytes for item in result.assessments],
                                 [allocated_bytes(file_path)] * 2)
                self.assertTrue(result.all_sizes_complete)

    def test_repeated_file_and_directory_preserve_each_assessment_size(self) -> None:
        file_path = self.file("parent/file.bin")
        for path in (file_path, file_path.parent):
            with self.subTest(path=path):
                standalone = assess_path(str(path))
                result = assess_many([str(path)] * 3, calculate_size=True, max_entries=100)
                self.assertEqual(result.total_allocated_size_bytes, allocated_bytes(file_path))
                self.assertEqual(result.assessments, [standalone] * 3)

    def test_symlinked_parent_aliases_deduplicate_single_link_descendants(self) -> None:
        child = self.file("canonical/child.bin")
        alias = self.root / "alias"
        alias.symlink_to(child.parent, target_is_directory=True)
        paths = [str(child.parent), str(alias / child.name)]
        self.assertEqual(child.lstat().st_nlink, 1)

        for selection in (paths, list(reversed(paths))):
            with self.subTest(paths=selection):
                result = assess_many(selection, calculate_size=True, max_entries=100)
                self.assertEqual(result.total_allocated_size_bytes, allocated_bytes(child))
                self.assertEqual(result.assessments, [assess_path(path) for path in selection])
                self.assertTrue(result.all_sizes_complete)

    def test_disjoint_paths_with_similar_prefixes_are_added(self) -> None:
        first = self.file("folder/first.bin")
        second = self.file("folder-copy/second.bin", 8192)
        result = assess_many([str(first.parent), str(second.parent)], calculate_size=True, max_entries=100)
        self.assertEqual(result.total_allocated_size_bytes, allocated_bytes(first) + allocated_bytes(second))
        self.assertTrue(result.all_sizes_complete)

    def test_hard_links_are_deduplicated_across_files_and_directories(self) -> None:
        original = self.file("left/original.bin")
        local_alias = original.parent / "local-alias.bin"
        other_alias = self.root / "right" / "other-alias.bin"
        other_alias.parent.mkdir()
        os.link(original, local_alias)
        os.link(original, other_alias)

        for paths in ([original, other_alias], [original.parent, other_alias.parent],
                      [other_alias.parent, original.parent]):
            with self.subTest(paths=paths):
                result = assess_many([str(path) for path in paths], calculate_size=True, max_entries=100)
                self.assertEqual(result.total_allocated_size_bytes, allocated_bytes(original))
                self.assertTrue(result.all_sizes_complete)
                for assessment in result.assessments:
                    self.assertEqual(assessment, assess_path(assessment.path))

    def test_symlink_identities_are_counted_without_traversing_targets(self) -> None:
        target = self.file("outside/large.bin", 32768)
        folder = self.root / "selected"
        folder.mkdir()
        first = folder / "first-link"
        second = folder / "second-link"
        dangling = folder / "dangling-link"
        first.symlink_to(target.parent, target_is_directory=True)
        second.symlink_to(target.parent, target_is_directory=True)
        dangling.symlink_to(self.root / "missing")

        # Short symlinks use zero blocks on some filesystems. Give each link a
        # nonzero allocation so duplicate counting cannot pass invisibly.
        def allocation(info: os.stat_result) -> int:
            return 512 if stat.S_ISLNK(info.st_mode) else info.st_blocks * 512

        for paths in ([folder, first, second, first, dangling], [first, second, dangling, folder, first]):
            with self.subTest(paths=paths), patch("luciddisk_mcp.filesystem._allocated_bytes", allocation):
                result = assess_many([str(path) for path in paths], calculate_size=True, max_entries=100)
                self.assertEqual(result.total_allocated_size_bytes, 3 * 512)
                self.assertTrue(result.all_sizes_complete)
                for assessment in result.assessments:
                    self.assertEqual(assessment, assess_path(assessment.path))

        with patch("luciddisk_mcp.filesystem._allocated_bytes", allocation):
            result = assess_many([str(first), str(target)], calculate_size=True, max_entries=100)
            self.assertEqual(result.total_allocated_size_bytes, 512 + allocated_bytes(target))

    def test_metadata_only_deduplicates_direct_entries_and_does_not_measure_directories(self) -> None:
        original = self.file("folder/original.bin")
        alias = original.parent / "alias.bin"
        link = original.parent / "symlink"
        os.link(original, alias)
        link.symlink_to(original)
        paths = [original.parent, original, alias, original, link, link]

        with patch("luciddisk_mcp.filesystem.measure_path", side_effect=AssertionError("Unexpected traversal")):
            result = assess_many([str(path) for path in paths], calculate_size=False, max_entries=1)
            standalone = [assess_path(str(path), calculate_size=False) for path in paths]

        self.assertEqual(result.assessments, standalone)
        self.assertIsNone(result.assessments[0].allocated_size_bytes)
        self.assertEqual(result.total_allocated_size_bytes, allocated_bytes(original) + allocated_bytes(link))
        self.assertTrue(result.all_sizes_complete)
        self.assertEqual(result.size_accuracy, "metadata-only")

    def test_same_inode_on_different_devices_counts_as_separate_files(self) -> None:
        first = self.file("first.bin")
        second = self.file("second.bin")
        real_lstat = os.lstat

        def metadata(path: str, **kwargs: object):
            info = real_lstat(path, **kwargs)
            if os.fspath(path) not in (str(first), str(second)):
                return info
            return SimpleNamespace(st_dev=1 if os.fspath(path) == str(first) else 2, st_ino=123,
                                   st_mode=info.st_mode, st_nlink=1, st_size=4096, st_blocks=8,
                                   st_mtime=info.st_mtime)

        for calculate_size in (True, False):
            with self.subTest(calculate_size=calculate_size), patch("luciddisk_mcp.filesystem.os.lstat", metadata):
                result = assess_many([str(first), str(second)], calculate_size=calculate_size, max_entries=100)
                self.assertEqual(result.total_allocated_size_bytes, 8192)
                self.assertTrue(result.all_sizes_complete)

    def test_exhausted_budget_excludes_later_file_metadata_from_total(self) -> None:
        measured = self.file("measured.bin")
        unmeasured = self.file("unmeasured.bin", 8192)
        result = assess_many([str(measured), str(unmeasured)], calculate_size=True, max_entries=1)

        self.assertEqual(result.total_allocated_size_bytes, allocated_bytes(measured))
        self.assertTrue(result.assessments[0].size_complete)
        self.assertFalse(result.assessments[1].size_complete)
        self.assertEqual(result.assessments[1].allocated_size_bytes, allocated_bytes(unmeasured))
        self.assertFalse(result.all_sizes_complete)
        self.assertEqual(result.size_accuracy, "incomplete")
        self.assertTrue(any("Shared entry budget" in warning for warning in result.warnings))

    def test_unmeasured_descendant_is_not_added_after_parent_uses_budget(self) -> None:
        child = self.file("parent/child.bin")
        result = assess_many([str(child.parent), str(child)], calculate_size=True, max_entries=1)
        self.assertEqual(result.total_allocated_size_bytes, 0)
        self.assertFalse(result.all_sizes_complete)
        self.assertTrue(all(not item.size_complete for item in result.assessments))
        self.assertEqual(result.size_accuracy, "incomplete")

    def test_incomplete_parent_does_not_erase_previously_measured_child(self) -> None:
        child = self.file("parent/child.bin")
        result = assess_many([str(child), str(child.parent)], calculate_size=True, max_entries=2)
        self.assertEqual(result.total_allocated_size_bytes, allocated_bytes(child))
        self.assertTrue(result.assessments[0].size_complete)
        self.assertFalse(result.assessments[1].size_complete)
        self.assertFalse(result.all_sizes_complete)

    def test_duplicate_paths_still_consume_the_shared_measurement_budget(self) -> None:
        child = self.file("parent/child.bin")
        result = assess_many([str(child)] * 3, calculate_size=True, max_entries=2)
        self.assertEqual(result.total_allocated_size_bytes, allocated_bytes(child))
        self.assertEqual([item.size_complete for item in result.assessments], [True, True, False])
        self.assertFalse(result.all_sizes_complete)
        self.assertEqual(result.size_accuracy, "incomplete")

    def test_missing_path_keeps_batch_incomplete_and_adds_no_size(self) -> None:
        existing = self.file("existing.bin")
        missing = self.root / "missing.bin"
        result = assess_many([str(missing), str(existing), str(existing)], calculate_size=True, max_entries=100)
        self.assertEqual(result.total_allocated_size_bytes, allocated_bytes(existing))
        self.assertFalse(result.all_sizes_complete)
        self.assertFalse(result.assessments[0].exists)
        self.assertEqual(result.size_accuracy, "incomplete")

    def test_failed_measurement_does_not_count_successful_preliminary_metadata(self) -> None:
        file_path = self.file("file.bin")
        real_lstat = os.lstat
        reads = 0

        def metadata(path: str, **kwargs: object):
            nonlocal reads
            reads += 1
            if reads > 1:
                raise PermissionError(errno.EACCES, "Permission denied", path)
            return real_lstat(path, **kwargs)

        with patch("luciddisk_mcp.filesystem.os.path.realpath", return_value=str(file_path)), \
             patch("luciddisk_mcp.filesystem.os.lstat", metadata):
            result = assess_many([str(file_path)], calculate_size=True, max_entries=100)

        self.assertEqual(reads, 2)
        self.assertEqual(result.total_allocated_size_bytes, 0)
        self.assertTrue(result.assessments[0].exists)
        self.assertTrue(result.assessments[0].scan_errors)
        self.assertFalse(result.all_sizes_complete)
        self.assertEqual(result.size_accuracy, "incomplete")

    def test_cleanup_plan_uses_the_same_unique_total_and_path_assessments(self) -> None:
        child = self.file("parent/child.bin")
        paths = [str(child.parent), str(child), str(child)]
        for calculate_size, budget in ((True, 100), (True, 1), (False, 100)):
            with self.subTest(calculate_size=calculate_size, budget=budget):
                batch = assess_many(paths, calculate_size=calculate_size, max_entries=budget)
                plan = create_plan(paths, calculate_size=calculate_size, max_entries=budget)
                self.assertEqual(plan.total_allocated_size_bytes, batch.total_allocated_size_bytes)
                self.assertEqual(plan.paths, batch.assessments)
                self.assertEqual(plan.size_accuracy, batch.size_accuracy)
                self.assertEqual(plan.warnings, batch.warnings)
                self.assertEqual(sum(plan.counts_by_risk.values()), len(paths))
                self.assertTrue(plan.requires_explicit_user_decision)
                self.assertTrue(child.exists())


if __name__ == "__main__":
    unittest.main()
