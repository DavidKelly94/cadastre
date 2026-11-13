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


def test_the_ceiling_is_read_off_the_scan_not_off_its_highest_point(store: Path):
    """The page opens a room by cutting just under the ceiling. The first real
    scan had a scrap above its ceiling, so the highest point left it closed."""
    from vividhome.model import _ceiling_height

    data = page_data(build_model(store, "main", points=False).page)
    assert data["ceiling"] == pytest.approx(data["floor"] + SynthSpec().height_m, abs=0.06)

    # A flat square at 2.4 m, and one stray triangle at 3.5 m above it.
    positions = np.array(
        [
            [0, 2.4, 0],
            [3, 2.4, 0],
            [3, 2.4, 3],
            [0, 2.4, 3],
            [1, 3.5, 1],
            [1.2, 3.5, 1],
            [1, 3.5, 1.2],
        ],
        dtype=np.float32,
    )
    indices = np.array([0, 1, 2, 0, 2, 3, 4, 5, 6], dtype=np.uint32)
    assert _ceiling_height(positions, indices, 0.0) == pytest.approx(2.4, abs=0.03)
    # Walls only, as in open framing: no ceiling to cut under.
    wall = np.array([[0, 0, 0], [3, 0, 0], [3, 2.4, 0], [0, 2.4, 0]], dtype=np.float32)
    assert _ceiling_height(wall, np.array([0, 1, 2, 0, 2, 3], dtype=np.uint32), 0.0) is None


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


# --- The keyframes in 3D (points.py) ------------------------------------------


def test_every_depth_pixel_lands_on_the_room_it_was_taken_in(tmp_path: Path):
    """The synthetic room is a box whose size is known, so a point that is not
    on a wall, the floor or the ceiling means the un-projection is wrong: an
    axis flipped, planar depth read as radial, the photo misregistered."""
    from vividhome.points import frame_points

    spec = SynthSpec(keyframes=6)
    session = Session.load(build(tmp_path / "s", spec).root)
    seen = 0
    for frame in session.frames():
        points, colors = frame_points(session, frame, max_range_m=50.0)
        assert len(points) > 0.9 * frame.dw * frame.dh, "nearly every depth pixel is valid"
        assert colors.shape == points.shape
        assert colors.min() >= 0 and colors.max() <= 255
        gaps = np.stack(
            [
                np.abs(points[:, 0]),
                np.abs(points[:, 0] - spec.width_m),
                np.abs(points[:, 1]),
                np.abs(points[:, 1] - spec.height_m),
                np.abs(points[:, 2]),
                np.abs(points[:, 2] - spec.depth_m),
            ]
        ).min(axis=0)
        assert gaps.max() < 0.01, (
            f"keyframe {frame.i}: a point {gaps.max():.3f} m off every surface"
        )
        seen += len(points)
    assert seen > 20_000


def test_points_are_merged_on_a_grid_and_moved_into_the_house(store: Path):
    from vividhome.points import VOXEL_M, session_points

    session = Session.load(store / "sessions" / "synthetic" / SESSION_ID)
    alignment = json.loads((store / "alignments" / f"{SESSION_ID}.json").read_text("utf-8"))
    t_hs = np.array(alignment["T_hs"], dtype=float).reshape(4, 4).T
    where, colors = session_points(session, t_hs, max_range_m=50.0)
    assert where.dtype == np.float32 and colors.dtype == np.uint8
    assert len(where) == len(colors) > 2_000

    # One point per grid cell: no two share a cell.
    cells = np.floor(where.astype(np.float64) / VOXEL_M).astype(np.int64)
    assert len(np.unique(cells, axis=0)) >= 0.98 * len(where)

    # Back through the placement they are on the room's box again.
    spec = SynthSpec()
    back = (where.astype(np.float64) - t_hs[:3, 3]) @ t_hs[:3, :3]
    inside = (
        (back[:, 0] > -0.02)
        & (back[:, 0] < spec.width_m + 0.02)
        & (back[:, 2] > -0.02)
        & (back[:, 2] < spec.depth_m + 0.02)
    )
    assert inside.all(), "every point is within the room it was taken in"

    # A cap is honored, evenly.
    few, _ = session_points(session, t_hs, max_range_m=50.0, limit=1000)
    assert len(few) == 1000


def test_the_3d_page_carries_the_points_and_can_be_built_without_them(store: Path):
    from vividhome.model import points_path

    result = build_model(store, "main")
    data = page_data(result.page)
    cloud = points_path(store, "main")
    assert result.points > 0 and result.points_data == cloud
    assert data["points"] == {"data": cloud.name, "count": result.points, "size": 0.015}
    assert cloud.stat().st_size == result.points * 16, "three floats and an RGBA per point"
    [session] = data["sessions"]
    assert (session["point_first"], session["point_count"]) == (0, result.points)
    raw = cloud.read_bytes()
    rgba = np.frombuffer(raw, dtype=np.uint8, offset=result.points * 12).reshape(-1, 4)
    assert (rgba[:, 3] == 255).all()

    # Without them the page falls back to the scan and the old file goes.
    plain = build_model(store, "main", points=False)
    assert plain.points == 0 and plain.points_data is None
    assert page_data(plain.page)["points"] is None
    assert not cloud.exists()
