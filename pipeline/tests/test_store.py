"""One store, many projects (ADR-0033). Inside a project nothing changed, so
what is tested here is the edges: that two projects with a level of the same
name no longer share a drawing, and that a command finds the right project."""

from __future__ import annotations

import json
import shutil
import zipfile
from pathlib import Path

import pytest
from PIL import Image

from vividhome.cli import main
from vividhome.ingest import ingest
from vividhome.plan import add_plan, calibrate, load_calibration
from vividhome.store import (
    StoreError,
    build_store_index,
    delete_project,
    find_session,
    is_legacy,
    peek_project,
    project_slugs,
    project_store,
    resolve_project,
)
from vividhome.synth import SynthSpec, build

HOUSE = "20261103-141502_main_room_aaaaaa"
REHEARSAL = "20261104-090000_main_room_bbbbbb"


def capture(root: Path, session_id: str, project: str) -> Path:
    """A synthetic capture that says it belongs to ``project``."""
    path = build(root / session_id, SynthSpec(keyframes=3)).root
    manifest = json.loads((path / "manifest.json").read_text(encoding="utf-8"))
    manifest["session_id"] = session_id
    manifest["project"] = {"slug": project, "name": project.title()}
    (path / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
    return path


def plan_png(path: Path, shade: int) -> Path:
    Image.new("RGB", (300, 200), (shade, shade, shade)).save(path, "PNG")
    return path


@pytest.fixture
def store(tmp_path: Path) -> Path:
    """A store holding two projects, each with a capture on a level called main."""
    store = tmp_path / "vividhome-data"
    for session_id, project, shade in ((HOUSE, "our-house", 250), (REHEARSAL, "rehearsal", 40)):
        mine = project_store(store, project)
        ingest(mine, capture(tmp_path / "phone", session_id, project))
        add_plan(mine, plan_png(tmp_path / f"{project}.png", shade), "main")
    return store


def test_two_projects_with_a_level_of_the_same_name_keep_their_own_drawing(store: Path):
    """The fault this closes: one plans/ folder for the whole store."""
    house = project_store(store, "our-house")
    rehearsal = project_store(store, "rehearsal")
    assert (house / "plans" / "main.png").read_bytes() != (
        rehearsal / "plans" / "main.png"
    ).read_bytes()

    # Calibrating one says nothing about the other.
    calibrate(
        house, "main", point_a=(10, 10), point_b=(110, 10), distance_m=2.0, origin_px=(10, 10)
    )
    assert load_calibration(house, "main").is_calibrated
    assert not load_calibration(rehearsal, "main").is_calibrated
    assert project_slugs(store) == ["our-house", "rehearsal"]
    assert not (store / "plans").exists() and not is_legacy(store)


def test_a_session_is_found_whichever_project_holds_it(store: Path):
    assert find_session(store, HOUSE) == (
        project_store(store, "our-house") / "sessions" / "our-house" / HOUSE
    )
    assert find_session(store, REHEARSAL).parts[-4] == "rehearsal"
    assert find_session(store, "20260101-000000_main_room_zzzzzz") is None


def test_the_index_lists_every_project_with_paths_from_the_stores_top(store: Path):
    index = build_store_index(store)
    by_slug = {project["slug"]: project for project in index["projects"]}
    assert set(by_slug) == {"our-house", "rehearsal"}
    [session] = by_slug["rehearsal"]["sessions"]
    assert session["session_id"] == REHEARSAL
    assert session["path"] == f"projects/rehearsal/sessions/rehearsal/{REHEARSAL}"
    [level] = by_slug["our-house"]["levels"]
    assert level["plan"] == "projects/our-house/plans/main.png"
    assert (store / level["plan"]).is_file(), "the path works from the server's root"


def test_a_command_takes_the_only_project_and_asks_when_there_are_several(store: Path, tmp_path):
    with pytest.raises(StoreError, match="more than one project"):
        resolve_project(store, None)
    assert resolve_project(store, "rehearsal") == "rehearsal"
    with pytest.raises(StoreError, match="not a project slug"):
        resolve_project(store, "../elsewhere")

    lone = tmp_path / "lone"
    ingest(project_store(lone, "our-house"), capture(tmp_path / "p2", HOUSE, "our-house"))
    assert resolve_project(lone, None) == "our-house"
    with pytest.raises(StoreError, match="no project"):
        resolve_project(tmp_path / "empty", None)


def test_the_command_line_routes_by_project(store: Path, tmp_path: Path, capsys):
    source = plan_png(tmp_path / "upper.png", 120)
    # Two projects: a level command has to be told which.
    assert main(["--store", str(store), "plan", "add", str(source), "--level", "upper"]) == 1
    assert "more than one project" in capsys.readouterr().err
    assert (
        main(
            ["--store", str(store), "plan", "add", str(source), "--level", "upper"]
            + ["--project", "rehearsal"]
        )
        == 0
    )
    assert (project_store(store, "rehearsal") / "plans" / "upper.png").is_file()
    assert not (project_store(store, "our-house") / "plans" / "upper.png").exists()

    # A session names its own project: nothing to say.
    assert main(["--store", str(store), "validate", REHEARSAL, "--skip-images"]) == 0
    assert (find_session(store, REHEARSAL) / "derived" / "validate.json").is_file()


def test_ingest_from_the_command_line_files_by_the_manifests_project(store: Path, tmp_path: Path):
    third = capture(tmp_path / "usb", "20261105-101010_main_room_cccccc", "rehearsal")
    assert main(["--store", str(store), "ingest", str(third)]) == 0
    assert find_session(store, third.name).parts[-4] == "rehearsal"

    # A zip of a session says the same thing from inside.
    fourth = capture(tmp_path / "usb", "20261105-111111_main_room_dddddd", "our-house")
    archive = tmp_path / "capture.zip"
    with zipfile.ZipFile(archive, "w") as bundle:
        for path in fourth.rglob("*"):
            if path.is_file():
                bundle.write(path, f"{fourth.name}/{path.relative_to(fourth)}")
    assert peek_project(archive) == "our-house"
    assert peek_project(fourth) == "our-house"
    assert peek_project(tmp_path / "nothing-here") is None


def test_a_project_is_removed_whole_and_only_when_asked(store: Path, capsys):
    assert main(["--store", str(store), "project", "list"]) == 0
    listed = capsys.readouterr().out
    assert "our-house: 1 capture(s), 1 plan(s)" in listed and "rehearsal: 1 capture(s)" in listed

    # Without --yes it only says what would go.
    assert main(["--store", str(store), "project", "delete", "rehearsal"]) == 0
    assert "would remove rehearsal: 1 capture(s)" in capsys.readouterr().out
    assert project_store(store, "rehearsal").is_dir()

    assert main(["--store", str(store), "project", "delete", "rehearsal", "--yes"]) == 0
    assert "removed rehearsal: 1 capture(s), 1 plan(s)" in capsys.readouterr().out
    assert project_slugs(store) == ["our-house"]
    assert find_session(store, HOUSE) is not None, "the other project is untouched"

    with pytest.raises(StoreError, match="no project"):
        delete_project(store, "rehearsal")
    assert main(["--store", str(store), "project", "delete", "rehearsal", "--yes"]) == 1


def test_a_store_from_before_projects_is_used_as_it_is(tmp_path: Path):
    """Every store there was, and every one the other tests build: sessions/ at
    the top, no projects/. Commands run on it unrouted, and it says what it is."""
    old = tmp_path / "old"
    ingest(old, capture(tmp_path / "phone", HOUSE, "our-house"))
    assert is_legacy(old) and project_slugs(old) == []
    assert find_session(old, HOUSE) == old / "sessions" / "our-house" / HOUSE
    assert main(["--store", str(old), "validate", HOUSE, "--skip-images"]) == 0
    source = plan_png(tmp_path / "main.png", 200)
    assert main(["--store", str(old), "plan", "add", str(source), "--level", "main"]) == 0
    assert (old / "plans" / "main.png").is_file()
    [project] = build_store_index(old)["projects"]
    assert project["sessions"][0]["path"] == f"sessions/our-house/{HOUSE}"
    shutil.rmtree(old)
