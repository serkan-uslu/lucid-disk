from __future__ import annotations

import contextlib
import os
import stat
import unittest
from types import SimpleNamespace
from unittest.mock import patch

from luciddisk_mcp.filesystem import EXCLUDED_PATHS, find_large_files, measure_path


def directory(inode: int, device: int = 1) -> SimpleNamespace:
    return SimpleNamespace(st_mode=stat.S_IFDIR | 0o755, st_dev=device, st_ino=inode,
                           st_nlink=2, st_size=0, st_blocks=0, st_mtime=1_700_000_000)


def regular_file(inode: int, device: int = 1, links: int = 1) -> SimpleNamespace:
    return SimpleNamespace(st_mode=stat.S_IFREG | 0o644, st_dev=device, st_ino=inode,
                           st_nlink=links, st_size=42, st_blocks=8, st_mtime=1_700_000_000)


class FakeFilesystem:
    """Models directory aliases, which cannot be created as ordinary hard links.

    Every scanned entry and metadata call is intercepted; these tests never walk
    the host root or depend on macOS's special namespaces being present.
    """

    def __init__(self, metadata: dict[str, SimpleNamespace], children: dict[str, list[str]]) -> None:
        self.metadata = metadata
        self.children = children
        self.scanned: list[str] = []
        self.stat_calls: list[str] = []
        self.yielded = 0
        self.maximum_yields: int | None = None

    def lstat(self, path: str, **_: object) -> SimpleNamespace:
        value = self.metadata.get(os.fspath(path))
        if value is None:
            raise FileNotFoundError(os.fspath(path))
        return value

    @contextlib.contextmanager
    def scandir(self, path: str):
        self.scanned.append(path)
        if path not in self.children:
            raise AssertionError(f"Unexpected directory traversal: {path}")

        def iterator():
            for child in self.children[path]:
                self.yielded += 1
                if self.maximum_yields is not None and self.yielded > self.maximum_yields:
                    raise AssertionError("Walker eagerly consumed entries beyond its budget")

                def entry_stat(*, follow_symlinks: bool, child_path: str = child) -> SimpleNamespace:
                    assert follow_symlinks is False
                    self.stat_calls.append(child_path)
                    return self.lstat(child_path)

                yield SimpleNamespace(path=child, stat=entry_stat)

        yield iterator()

    @contextlib.contextmanager
    def installed(self):
        with patch("luciddisk_mcp.filesystem.os.lstat", self.lstat), \
             patch("luciddisk_mcp.filesystem.os.scandir", self.scandir), \
             patch("luciddisk_mcp.filesystem.os.path.isdir", lambda path: stat.S_ISDIR(self.lstat(path).st_mode)):
            yield


class DirectoryAliasRegressionTests(unittest.TestCase):
    def alias_tree(self) -> FakeFilesystem:
        return FakeFilesystem(
            {"/scan": directory(1), "/scan/actual": directory(2), "/scan/alias": directory(2),
             "/scan/actual/file.bin": regular_file(3), "/scan/alias/file.bin": regular_file(3)},
            {"/scan": ["/scan/actual", "/scan/alias"],
             "/scan/actual": ["/scan/actual/file.bin"], "/scan/alias": ["/scan/alias/file.bin"]},
        )

    def test_measure_path_visits_same_directory_identity_once_even_for_nlink_one_files(self) -> None:
        fs = self.alias_tree()
        with fs.installed():
            result = measure_path("/scan")
        self.assertEqual(result.allocated_size_bytes, 4096)
        self.assertEqual(result.logical_size_bytes, 42)
        self.assertEqual(len(fs.scanned), 2, "Only the root and one directory alias may be descended")
        self.assertFalse(result.complete)
        self.assertTrue(any("directory aliases" in warning for warning in result.warnings))

    def test_find_large_files_visits_same_directory_identity_once(self) -> None:
        fs = self.alias_tree()
        with fs.installed():
            result = find_large_files("/scan", min_size_bytes=0)
        self.assertEqual(len(result.files), 1)
        self.assertEqual(result.files[0].allocated_size_bytes, 4096)
        self.assertEqual(len(fs.scanned), 2)
        self.assertFalse(result.complete)
        self.assertTrue(any("directory aliases" in warning for warning in result.warnings))

    def test_root_identity_alias_cannot_create_a_traversal_cycle(self) -> None:
        for walk in (lambda: measure_path("/scan"), lambda: find_large_files("/scan", min_size_bytes=0)):
            with self.subTest(walk=walk):
                fs = FakeFilesystem(
                    {"/scan": directory(1), "/scan/loop": directory(1), "/scan/file.bin": regular_file(2)},
                    {"/scan": ["/scan/loop", "/scan/file.bin"]},
                )
                with fs.installed():
                    result = walk()
                self.assertEqual(fs.scanned, ["/scan"])
                self.assertFalse(result.complete)
                self.assertTrue(any("directory aliases" in warning for warning in result.warnings))

    def test_alternate_root_namespaces_are_excluded_before_they_can_steal_canonical_paths(self) -> None:
        self.assertIn("/.nofollow", EXCLUDED_PATHS)
        self.assertIn("/.resolve", EXCLUDED_PATHS)
        for walk in (lambda: measure_path("/"), lambda: find_large_files("/", min_size_bytes=0)):
            with self.subTest(walk=walk):
                fs = FakeFilesystem(
                    {"/": directory(1), "/Users": directory(2), "/.nofollow": directory(3), "/.resolve": directory(4),
                     "/Users/file.bin": regular_file(5)},
                    {"/": ["/Users", "/.nofollow", "/.resolve"], "/Users": ["/Users/file.bin"]},
                )
                with fs.installed():
                    result = walk()
                self.assertEqual(fs.scanned, ["/", "/Users"])
                if hasattr(result, "files"):
                    self.assertEqual([file.path for file in result.files], ["/Users/file.bin"])
                else:
                    self.assertEqual(result.allocated_size_bytes, 4096)
                self.assertFalse(result.complete)

    def test_explicit_excluded_root_is_not_traversed(self) -> None:
        for path in ("/.nofollow", "/.resolve"):
            for walk in (lambda: measure_path(path), lambda: find_large_files(path, min_size_bytes=0)):
                with self.subTest(path=path, walk=walk):
                    fs = FakeFilesystem({path: directory(1)}, {})
                    with fs.installed():
                        result = walk()
                    self.assertEqual(fs.scanned, [])
                    self.assertFalse(result.complete)

    def test_explicit_alias_descendant_roots_cannot_bypass_namespace_exclusion(self) -> None:
        for root in ("/.nofollow", "/.resolve"):
            for path in (root + "/Users", root + "/Users/example/Library"):
                for walk in (lambda: measure_path(path), lambda: find_large_files(path, min_size_bytes=0)):
                    with self.subTest(path=path, walk=walk):
                        fs = FakeFilesystem({path: directory(1)}, {})
                        with fs.installed():
                            result = walk()
                        self.assertEqual(fs.scanned, [])
                        self.assertFalse(result.complete)
                        self.assertTrue(any("resolution aliases" in warning for warning in result.warnings))

    def test_nested_folders_with_alias_names_are_still_scanned(self) -> None:
        for walk in (lambda: measure_path("/scan"), lambda: find_large_files("/scan", min_size_bytes=0)):
            fs = FakeFilesystem(
                {"/scan": directory(1), "/scan/.nofollow": directory(2), "/scan/.resolve": directory(3),
                 "/scan/.nofollow/file.bin": regular_file(4), "/scan/.resolve/file.bin": regular_file(5)},
                {"/scan": ["/scan/.nofollow", "/scan/.resolve"],
                 "/scan/.nofollow": ["/scan/.nofollow/file.bin"], "/scan/.resolve": ["/scan/.resolve/file.bin"]},
            )
            with fs.installed():
                result = walk()
            self.assertEqual(set(fs.scanned), {"/scan", "/scan/.nofollow", "/scan/.resolve"})
            self.assertTrue(result.complete)
            if hasattr(result, "files"):
                self.assertEqual(len(result.files), 2)
            else:
                self.assertEqual(result.allocated_size_bytes, 8192)

    def test_explicit_external_volume_and_similar_prefix_roots_remain_scannable(self) -> None:
        for path in ("/Volumes/External", "/.nofollow-backup", "/.resolve-project"):
            for walk in (lambda: measure_path(path), lambda: find_large_files(path, min_size_bytes=0)):
                with self.subTest(path=path, walk=walk):
                    child = path + "/file.bin"
                    fs = FakeFilesystem({path: directory(1, device=2), child: regular_file(2, device=2)}, {path: [child]})
                    with fs.installed():
                        result = walk()
                    self.assertEqual(fs.scanned, [path])
                    self.assertTrue(result.complete)
                    if hasattr(result, "files"):
                        self.assertEqual([file.path for file in result.files], [child])
                    else:
                        self.assertEqual(result.allocated_size_bytes, 4096)

    def test_same_inode_on_another_device_still_respects_volume_boundary(self) -> None:
        fs = FakeFilesystem(
            {"/scan": directory(1), "/scan/local": directory(2), "/scan/mounted": directory(2, device=2),
             "/scan/local/file.bin": regular_file(3)},
            {"/scan": ["/scan/local", "/scan/mounted"], "/scan/local": ["/scan/local/file.bin"]},
        )
        with fs.installed():
            result = measure_path("/scan")
        self.assertEqual(result.allocated_size_bytes, 4096)
        self.assertNotIn("/scan/mounted", fs.scanned)
        self.assertTrue(any("mounted volumes" in warning for warning in result.warnings))

    def test_find_large_files_enforces_budget_inside_a_wide_directory_without_materializing_it(self) -> None:
        paths = [f"/scan/file-{index}" for index in range(100)]
        fs = FakeFilesystem({"/scan": directory(1), **{path: regular_file(index + 2) for index, path in enumerate(paths)}},
                            {"/scan": paths})
        fs.maximum_yields = 4  # Three measured entries plus one lookahead proves truncation.
        with fs.installed():
            result = find_large_files("/scan", min_size_bytes=0, max_entries=3)
        self.assertEqual(result.entries_scanned, 3)
        self.assertEqual(len(fs.stat_calls), 3)
        self.assertEqual(len(result.files), 3)
        self.assertFalse(result.complete)
        self.assertTrue(any("budget" in warning.lower() for warning in result.warnings))

    def test_measure_path_bounds_pending_entries_by_remaining_budget(self) -> None:
        paths = [f"/scan/file-{index}" for index in range(100)]
        fs = FakeFilesystem({"/scan": directory(1), **{path: regular_file(index + 2) for index, path in enumerate(paths)}},
                            {"/scan": paths})
        fs.maximum_yields = 3  # The root consumes one of the three entries.
        with fs.installed():
            result = measure_path("/scan", max_entries=3)
        self.assertEqual(result.entries_scanned, 3)
        self.assertEqual(result.allocated_size_bytes, 8192)
        self.assertFalse(result.complete)
        self.assertTrue(any("budget" in warning.lower() for warning in result.warnings))


if __name__ == "__main__":
    unittest.main()
