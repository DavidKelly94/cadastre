"""The inspection page is where a projection error becomes visible, so the tests
check the numbers baked into it rather than only that a file appeared."""

from __future__ import annotations

import json
import re
from pathlib import Path

import numpy as np
import pytest
from PIL import Image

from cadastre.align import landmark_pairs, solve, update_marker_map, write_alignment
from cadastre.apriltag import aggregate, solve_session, write_detections
from cadastre.inspector import build_page, levels_with_alignments
from cadastre.plan import PlanError, add_plan, calibrate, house_to_plan
from cadastre.session import Session
from cadastre.synth import SynthSpec, build
from cadastre.transforms import se2_to_mat
from cadastre.validate import validate_session, write_report

SESSION_ID = "20261103-141502_main_room_framing_aaaaaa"
TRANSFORM = se2_to_mat(np.radians(25.0), 1.5, 0.0, -0.5)


@pytest.fixture(scope="module")
def store(tmp_path_factory) -> Path:
    """A store with one aligned session on a calibrated level."""
    root = tmp_path_factory.mktemp("inspect")
    store = root / "cadastre-data"
    truth = build(store / "sessions" / "synthetic" / SESSION_ID, SynthSpec(keyframes=12))

    source = root / "plan.png"
    Image.new("RGB", (1200, 900), (250, 250, 250)).save(source, "PNG")
    add_plan(store, source, "main")
    calibration = calibrate(
        store,
        "main",
        point_a=(100.0, 100.0),
        point_b=(600.0, 100.0),
        distance_m=5.0,
        origin_px=(100.0, 100.0),
    )

    session = Session.load(truth.root)
    write_report(session, validate_session(session))
    write_detections(session, aggregate(solve_session(session)))

    clicks = {}
    for landmark in session.landmarks():
        house = TRANSFORM @ np.array([landmark.p_w[0], 0.0, landmark.p_w[2], 1.0])
        clicks[landmark.label] = house_to_plan(calibration, house[0], house[2])

    alignment = solve(session, calibration, landmark_pairs(session, calibration, clicks))
    write_alignment(store, alignment)
    update_marker_map(store, "synthetic", session, alignment)
    return store


def page_data(path: Path) -> dict:
    match = re.search(r"^const DATA = (\{.*\});$", path.read_text(encoding="utf-8"), re.MULTILINE)
    assert match, "the page must embed its data as a single DATA assignment"
    return json.loads(match.group(1))


def test_levels_with_alignments(store: Path):
    assert levels_with_alignments(store) == ["main"]


def test_the_page_is_written_and_self_contained(store: Path):
    target = build_page(store, "main", thumbnails=False)
    assert target == store / "inspect" / "main.html"

    text = target.read_text(encoding="utf-8")
    assert text.startswith("<!doctype html>")
    # No external assets beyond the plan raster and thumbnails: the record has to
    # outlive the tooling, so no CDN and no build step.
    assert "http://" not in text.replace("http://www.w3.org/2000/svg", "")
    assert "https://" not in text
    assert "<script src" not in text
    assert "<link" not in text


def test_the_plan_is_referenced_relatively_and_resolves(store: Path):
    target = build_page(store, "main", thumbnails=False)
    data = page_data(target)
    assert data["image"] == "../plans/main.png"
    assert (target.parent / data["image"]).resolve().exists()
    assert (data["width"], data["height"]) == (1200, 900)


def test_landmarks_are_projected_to_the_pixels_they_were_clicked_at(store: Path):
    """The overlay must land back on the clicks the alignment was solved from."""
    from cadastre.plan import load_calibration

    calibration = load_calibration(store, "main")
    session = Session.load(store / "sessions" / "synthetic" / SESSION_ID)

    data = page_data(build_page(store, "main", thumbnails=False))
    drawn = {entry["label"]: (entry["u"], entry["v"]) for entry in data["sessions"][0]["landmarks"]}

    for landmark in session.landmarks():
        house = TRANSFORM @ np.array([landmark.p_w[0], 0.0, landmark.p_w[2], 1.0])
        expected = house_to_plan(calibration, house[0], house[2])
        assert drawn[landmark.label] == pytest.approx(expected, abs=0.02)


def test_the_trajectory_has_one_point_per_keyframe(store: Path):
    data = page_data(build_page(store, "main", thumbnails=False))
    session = data["sessions"][0]
    assert len(session["trajectory"]) == 12
    for u, v in session["trajectory"]:
        assert 0 <= u <= data["width"]
        assert 0 <= v <= data["height"]


def test_markers_are_drawn_where_the_house_map_puts_them(store: Path):
    from cadastre.plan import load_calibration

    calibration = load_calibration(store, "main")
    house_map = json.loads((store / "markers" / "synthetic.json").read_text(encoding="utf-8"))
    data = page_data(build_page(store, "main", thumbnails=False))
    drawn = {entry["id"]: (entry["u"], entry["v"]) for entry in data["sessions"][0]["markers"]}

    assert set(drawn) == set(house_map)
    for marker, entry in house_map.items():
        pose = np.array(entry["T_hm"], dtype=float).reshape(4, 4, order="F")
        expected = house_to_plan(calibration, pose[0, 3], pose[2, 3])
        assert drawn[marker] == pytest.approx(expected, abs=0.02)


def test_the_quality_summary_comes_from_the_validate_report(store: Path):
    data = page_data(build_page(store, "main", thumbnails=False))
    quality = data["sessions"][0]["quality"]
    assert quality["ok"] is True
    assert quality["keyframes"] == 12
    assert quality["errors"] == 0


def test_thumbnails_are_written_and_referenced(store: Path):
    data = page_data(build_page(store, "main", thumbnails=True, thumbnail_stride=4))
    keyframes = data["sessions"][0]["keyframes"]
    assert keyframes, "expected some hover thumbnails"
    assert all(k["i"] % 4 == 0 for k in keyframes)

    target = store / "inspect" / "main.html"
    for entry in keyframes:
        resolved = (target.parent / entry["thumb"]).resolve()
        assert resolved.exists(), entry["thumb"]
        with Image.open(resolved) as image:
            assert image.width == 320


def test_thumbnails_can_be_skipped(store: Path):
    data = page_data(build_page(store, "main", thumbnails=False))
    assert data["sessions"][0]["keyframes"] == []


def test_an_uncalibrated_level_is_refused(tmp_path: Path):
    store = tmp_path / "data"
    source = tmp_path / "plan.png"
    Image.new("RGB", (100, 100), (255, 255, 255)).save(source, "PNG")
    add_plan(store, source, "upper")
    with pytest.raises(PlanError, match="not calibrated"):
        build_page(store, "upper")


def test_a_level_with_no_plan_is_refused(tmp_path: Path):
    with pytest.raises(PlanError, match="run 'cadastre plan add'"):
        build_page(tmp_path / "data", "basement")


def test_an_alignment_whose_session_is_missing_is_skipped(store: Path, tmp_path: Path):
    """A store can outlive a session folder; the page should still build."""
    orphan = store / "alignments" / "20261103-999999_main_ghost_framing_zzzzzz.json"
    orphan.write_text(
        json.dumps(
            {
                "session_id": "20261103-999999_main_ghost_framing_zzzzzz",
                "level": "main",
                "T_hs": list(np.eye(4).flatten(order="F")),
            }
        ),
        encoding="utf-8",
    )
    try:
        data = page_data(build_page(store, "main", thumbnails=False))
        assert len(data["sessions"]) == 1
    finally:
        orphan.unlink()
