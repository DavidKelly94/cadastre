"""3D on the PC, stage one (ADR-0036): the scanned mesh moved into the house.
The numbers in the data file are checked against the alignment they came
through, since a model drawn in the wrong place looks exactly like a right one."""

from __future__ import annotations

import json
import re
from pathlib import Path

import numpy as np
import pytest
from PIL import Image

from vividhome.align import landmark_pairs, solve, write_alignment
from vividhome.inspector import build_page
from vividhome.mesh import read_mesh
from vividhome.model import build_model, model_paths
from vividhome.plan import PlanError, add_plan, calibrate, house_to_plan, plan_to_house
from vividhome.session import Session
from vividhome.synth import SynthSpec, build
from vividhome.transforms import se2_to_mat

SESSION_ID = "20261103-141502_main_room_framing_aaaaaa"
TRANSFORM = se2_to_mat(np.radians(25.0), 1.5, 0.0, -0.5)


@pytest.fixture
def store(tmp_path: Path) -> Path:
    """A store with one placed session on a calibrated level."""
    store = tmp_path / "vividhome-data"
    truth = build(store / "sessions" / "synthetic" / SESSION_ID, SynthSpec(keyframes=12))
    source = tmp_path / "plan.png"
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
    clicks = {}
    for landmark in session.landmarks():
        house = TRANSFORM @ np.array([landmark.p_w[0], 0.0, landmark.p_w[2], 1.0])
        clicks[landmark.label] = house_to_plan(calibration, house[0], house[2])
    write_alignment(
        store, solve(session, calibration, landmark_pairs(session, calibration, clicks))
    )
    return store


def page_data(path: Path) -> dict:
    match = re.search(r"^const DATA = (\{.*\});$", path.read_text(encoding="utf-8"), re.MULTILINE)
    assert match, "the page must embed its data as a single DATA assignment"
    return json.loads(match.group(1))


def test_the_scan_is_moved_into_the_house(store: Path):
    result = build_model(store, "main")
    page, data_path = model_paths(store, "main")
    assert (result.page, result.data) == (page, data_path)
    assert result.sessions == 1 and result.skipped == []

    data = page_data(page)
    session = Session.load(store / "sessions" / "synthetic" / SESSION_ID)
    mesh = read_mesh(session)
    assert data["vertices"] == len(mesh.vertices) == result.vertices
    assert data["indices"] == mesh.faces.size == result.faces * 3

    raw = data_path.read_bytes()
    assert len(raw) == data["vertices"] * 12 + data["indices"] * 4
    positions = np.frombuffer(raw, dtype="<f4", count=data["vertices"] * 3).reshape(-1, 3)
    indices = np.frombuffer(raw, dtype="<u4", offset=data["vertices"] * 12)
    assert indices.max() < data["vertices"]
    assert np.array_equal(indices.reshape(-1, 3), mesh.faces)

    # Every vertex is where the alignment puts it: the solved transform is the
    # one the taps were generated through, so the truth is known.
    alignment = json.loads((store / "alignments" / f"{SESSION_ID}.json").read_text("utf-8"))
    t_hs = np.array(alignment["T_hs"], dtype=float).reshape(4, 4).T
    expected = mesh.vertices @ t_hs[:3, :3].T + t_hs[:3, 3]
    assert np.allclose(positions, expected, atol=1e-4)
    through_truth = mesh.vertices @ TRANSFORM[:3, :3].T + TRANSFORM[:3, 3]
    assert np.allclose(positions[:, [0, 2]], through_truth[:, [0, 2]], atol=0.02)

    assert data["low"] == pytest.approx(positions.min(axis=0), abs=1e-3)
    assert data["high"] == pytest.approx(positions.max(axis=0), abs=1e-3)
    [listed] = data["sessions"]
    assert listed["id"] == SESSION_ID
    assert (listed["first"], listed["count"]) == (0, mesh.faces.size)
    assert listed["phases"] == session.phases


def test_the_drawing_lies_under_the_rooms_where_the_calibration_puts_it(store: Path):
    from vividhome.plan import load_calibration

    build_model(store, "main")
    data = page_data(model_paths(store, "main")[0])
    calibration = load_calibration(store, "main")
    corners = data["plan"]["corners"]
    assert data["plan"]["image"] == "../plans/main.png"
    for (u, v), corner in zip([(0, 0), (1200, 0), (1200, 900), (0, 900)], corners, strict=True):
        x, z = plan_to_house(calibration, u, v)
        assert (corner[0], corner[2]) == pytest.approx((x, z), abs=1e-3)
        assert corner[1] < data["floor"], "a hair under the floor, so the scan's floor wins"


def test_the_page_needs_nothing_from_outside_and_the_level_page_links_to_it(store: Path):
    build_model(store, "main")
    page = model_paths(store, "main")[0].read_text(encoding="utf-8")
    assert "http://" not in page and "https://" not in page
    assert 'href="main.html"' in page

    level_page = build_page(store, "main", thumbnails=False).read_text(encoding="utf-8")
    assert '<a href="main-3d.html">See this level in 3D</a>' in level_page


def test_a_level_page_built_before_the_model_has_no_link(store: Path):
    assert "in 3D" not in build_page(store, "main", thumbnails=False).read_text(encoding="utf-8")


def test_a_capture_without_a_scan_is_left_out_and_said(store: Path):
    (store / "sessions" / "synthetic" / SESSION_ID / "mesh.obj").unlink()
    with pytest.raises(PlanError, match="no mesh to show"):
        build_model(store, "main")
    assert not model_paths(store, "main")[0].exists()


def test_an_uncalibrated_level_has_no_model(tmp_path: Path):
    store = tmp_path / "data"
    source = tmp_path / "plan.png"
    Image.new("RGB", (300, 200), (250, 250, 250)).save(source, "PNG")
    add_plan(store, source, "main")
    with pytest.raises(PlanError, match="not calibrated"):
        build_model(store, "main")
