"""Fixtures. The builders live in helpers.py so tests can import them too."""

from __future__ import annotations

from pathlib import Path

import pytest
from helpers import build_session


@pytest.fixture
def session_dir(tmp_path: Path) -> Path:
    return build_session(tmp_path / "20261103-141502_main_kitchen_electrical_k3x7qa")
