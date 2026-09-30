"""The index is what the phone reads instead of listing directories, so its
claims about the store have to be true of the files."""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pytest
from PIL import Image

from vividhome import __version__
from vividhome.index import build_index
from vividhome.plan import add_plan, calibrate
from vividhome.session import Session
from vividhome.synth import SynthSpec, build
from vividhome.validate import validate_session, write_report

SPEC = SynthSpec(keyframes=2, colour_w=160, colour_h=120)
SESSION_ID = "20261103-141502_main_room_framing_aaaaaa"


@pytest.fixture
def store(tmp_path: Path) -> Path:
    store = tmp_path / "vividhome-data"
    build(store / "sessions" / "synthetic" / SESSION_ID, SPEC)
    source = tmp_path / "plan.png"
    Image.new("RGB", (400, 300), (255, 255, 255)).save(source, "PNG")
    add_plan(store, source, "main")
    return store


def align(store: Path, session_id: str, level: str) -> None:
    (store / "alignments").mkdir(exist_ok=True)
    (store / "alignments" / f"{session_id}.json").write_text(
        json.dumps({"session_id": session_id, "level": level, "T_hs": list(np.eye(4).flatten())}),
        encoding="utf-8",
    )


def test_an_empty_store_is_an_empty_index(tmp_path: Path):
    index = build_index(tmp_path / "nothing")
    assert index["projects"] == []
    assert index["vividhome"] == __version__
    assert index["store"] == "nothing"
    assert index["generated_at"].endswith("Z")


def test_a_fresh_session_is_listed_as_unaligned_and_unvalidated(store: Path):
    [project] = build_index(store)["projects"]
    assert project["slug"] == "synthetic"
    [session] = project["sessions"]
    assert session == {
        "session_id": SESSION_ID,
        "path": f"sessions/synthetic/{SESSION_ID}",
        "level": "main",
        "aligned": False,
        "validated": None,
    }
    # The level has a plan but nothing on it yet: listed, uncalibrated, no page.
    [level] = project["levels"]
    assert level == {
        "level": "main",
        "plan": "plans/main.png",
        "calibrated": False,
        "inspect": None,
        "sessions": [],
    }


def test_the_index_follows_the_files(store: Path):
    session = Session.load(store / "sessions" / "synthetic" / SESSION_ID)
    write_report(session, validate_session(session))
    calibrate(
        store,
        "main",
        point_a=(10.0, 10.0),
        point_b=(210.0, 10.0),
        distance_m=4.0,
        origin_px=(10.0, 10.0),
    )
    align(store, SESSION_ID, "main")
    (store / "inspect").mkdir()
    (store / "inspect" / "main.html").write_text("<!doctype html>", encoding="utf-8")

    [project] = build_index(store)["projects"]
    [session_entry] = project["sessions"]
    assert session_entry["aligned"] is True
    assert session_entry["validated"] is True
    [level] = project["levels"]
    assert level["calibrated"] is True
    assert level["inspect"] == "inspect/main.html"
    assert level["sessions"] == [SESSION_ID]


def test_a_failed_validation_is_reported_as_false_not_missing(store: Path):
    session = Session.load(store / "sessions" / "synthetic" / SESSION_ID)
    (session.root / "depth" / "000001.f32").unlink()
    write_report(session, validate_session(session))
    [project] = build_index(store)["projects"]
    assert project["sessions"][0]["validated"] is False


def test_a_level_reached_only_by_alignment_is_listed(store: Path):
    """A session recorded as 'main' but aligned onto 'upper' belongs to both."""
    source = store.parent / "upper.png"
    Image.new("RGB", (100, 100), (255, 255, 255)).save(source, "PNG")
    add_plan(store, source, "upper")
    align(store, SESSION_ID, "upper")
    [project] = build_index(store)["projects"]
    assert [level["level"] for level in project["levels"]] == ["main", "upper"]
    assert project["levels"][1]["sessions"] == [SESSION_ID]
    assert project["levels"][0]["sessions"] == []


def test_staging_folders_and_stray_files_are_not_projects_or_sessions(store: Path):
    (store / "sessions" / ".ingest-capture").mkdir()
    (store / "sessions" / "synthetic" / "notes.txt").write_text("x", encoding="utf-8")
    (store / "sessions" / "synthetic" / "not-a-session").mkdir()
    [project] = build_index(store)["projects"]
    assert len(project["sessions"]) == 1


def test_a_plan_the_project_has_no_session_on_is_not_its_level(store: Path):
    """plans/ is store-wide (section 13); a level with no session of this
    project on it is somebody else's."""
    source = store.parent / "basement.png"
    Image.new("RGB", (100, 100), (255, 255, 255)).save(source, "PNG")
    add_plan(store, source, "basement")
    [project] = build_index(store)["projects"]
    assert [level["level"] for level in project["levels"]] == ["main"]
