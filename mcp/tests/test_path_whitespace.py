import os
from pathlib import Path
from unittest.mock import patch

import pytest

from luciddisk_mcp.filesystem import assess_many, assess_path, create_plan, inventory_directory, measure_path
from luciddisk_mcp.safety import normalize_path


@pytest.mark.parametrize('name', ['same-name ', ' same-name', '\tsame-name\t', 'same-name\n', ' '])
def test_significant_whitespace_preserves_the_requested_item(tmp_path, name):
    neighbor = tmp_path / name.strip() if name.strip() else tmp_path / 'neighbor'
    neighbor.write_bytes(b'n' * 4096)
    target = tmp_path / name
    target.write_bytes(b't' * 12288)
    expected = target.lstat().st_blocks * 512
    assert normalize_path(str(target)) == str(target)
    result = assess_path(str(target))
    assert result.path == str(target)
    assert result.name == name
    assert result.logical_size_bytes == 12288
    assert result.allocated_size_bytes == expected
    assert measure_path(str(target)).allocated_size_bytes == expected
    assert create_plan([str(target)], True, 100).total_allocated_size_bytes == expected
    assert assess_many([str(target)], True, 100).assessments[0].path == str(target)


@pytest.mark.parametrize('name', [' file ', '\tfile', 'file\n', ' '])
def test_relative_whitespace_names_do_not_get_trimmed(tmp_path, monkeypatch, name):
    monkeypatch.chdir(tmp_path)
    Path(name).write_bytes(b'correct')
    assert normalize_path(name) == str(tmp_path / name)
    assert assess_path(name).logical_size_bytes == 7


def test_empty_input_rejected_but_ordinary_normalization_preserved(tmp_path):
    with pytest.raises(ValueError, match='must not be empty'):
        normalize_path('')
    with patch.dict(os.environ, {'HOME': str(tmp_path)}):
        assert normalize_path('~/Documents ') == str(tmp_path / 'Documents ')
    assert normalize_path(str(tmp_path / 'one' / '..' / 'file ')) == str(tmp_path / 'file ')


def test_directory_inventory_keeps_trailing_space_root(tmp_path):
    target = tmp_path / 'folder '
    target.mkdir()
    (target / 'only-here').write_bytes(b'fixture')
    (tmp_path / 'folder').mkdir()
    inventory = inventory_directory(str(target))
    assert inventory.root == str(target)
    assert [item.name for item in inventory.items] == ['only-here']
