"""Corner candidates from the wall mesh: the offline half of ai-roadmap item 5.

The claim under test is the one the roadmap makes — fit planes to wall faces,
intersect adjacent pairs, and the intersections are the room's corners — plus
the two things that make it wrong on a real mesh: furniture ARKit calls "wall",
and walls whose lines cross where there is no corner.
"""

from __future__ import annotations

import json
import shutil
from pathlib import Path

import numpy as np
import pytest

from vividhome.corners import (
    ACCEPT_M,
    compare_with_landmarks,
    corner_candidates,
    find_walls,
    floor_height,
    propose_corners,
    write_candidates,
)
from vividhome.mesh import FLOOR, WALL, MeshBuilder, read_mesh
from vividhome.session import Landmark, Session, SessionError
from vividhome.synth import SynthSpec, build

SPEC = SynthSpec(keyframes=2, colour_w=160, colour_h=120)


@pytest.fixture(scope="module")
def box(tmp_path_factory) -> Session:
    """The synthetic 4 x 5 m room, whose landmarks are its four floor corners."""
    root = tmp_path_factory.mktemp("corners") / "20261103-141502_main_room_framing_aaaaaa"
    return Session.load(build(root, SPEC).root)


def flat(candidates) -> list[tuple[float, float]]:
    return sorted((round(c.p_w[0], 2), round(c.p_w[2], 2)) for c in candidates)


def test_mesh_geometry_helpers():
    builder = MeshBuilder()
    builder.add_quad((0.0, 0.0, 0.0), (2.0, 0.0, 0.0), (0.0, 1.0, 0.0), WALL, cell_m=1.0)
    mesh = builder.mesh()
    assert len(mesh.faces) == 4
    assert mesh.areas().sum() == pytest.approx(2.0)
    assert np.abs(mesh.normals()[:, 2]).min() == pytest.approx(1.0), "a wall on z=0 faces along z"
    assert mesh.histogram() == {"wall": 4}


def test_the_box_room_yields_its_four_corners(box: Session):
    report = propose_corners(box)
    assert len(report.walls) == 4
    assert flat(report.candidates) == [(0.0, 0.0), (0.0, 5.0), (4.0, 0.0), (4.0, 5.0)]
    assert all(candidate.confidence > 0.95 for candidate in report.candidates)
    assert report.floor_y == pytest.approx(0.0)
    assert report.floor_source == "floor faces"
    for candidate in report.candidates:
        assert candidate.p_w[1] == pytest.approx(0.0), "candidates sit on the floor"


def test_every_tapped_corner_is_within_20_cm_of_a_candidate(box: Session):
    """The roadmap's metric, on the fixture where it must be 100%."""
    against = propose_corners(box).against_landmarks
    assert against is not None
    assert against["tapped_corners"] == 4
    assert against["matched"] == 4
    assert against["fraction"] == 1.0
    assert against["accept_m"] == ACCEPT_M
    assert against["candidates_without_a_tap"] == []
    assert all(entry["distance_m"] < 0.02 for entry in against["landmarks"])


def test_clutter_classified_as_wall_proposes_nothing(box: Session):
    """The fixture carries a 0.4 x 0.3 m 'wall' in the middle of the room.

    With the default minimum area it is not a wall at all. Even when it is let
    through as one, its line meets the real walls far from where its own faces
    reach, so the reach test refuses the ghost corners.
    """
    mesh = read_mesh(box)
    assert len(find_walls(mesh)) == 4

    walls = find_walls(mesh, min_area_m2=0.01)
    assert len(walls) == 5
    clutter = min(walls, key=lambda wall: wall.area_m2)
    assert clutter.area_m2 == pytest.approx(0.12, abs=0.01)
    candidates = corner_candidates(walls, 0.0)
    assert flat(candidates) == [(0.0, 0.0), (0.0, 5.0), (4.0, 0.0), (4.0, 5.0)]
    assert not any(clutter.id in candidate.walls for candidate in candidates)


def test_an_l_shaped_room_gets_six_corners_and_no_ghosts(tmp_path: Path):
    """A 6 x 6 room with a 3 x 3 notch: six walls, six corners, one of them
    re-entrant. The far walls' lines cross at (6, 6) and (3, 3) is a real
    corner; only the reach test tells those apart."""
    outline = [(0.0, 0.0), (6.0, 0.0), (6.0, 3.0), (3.0, 3.0), (3.0, 6.0), (0.0, 6.0)]
    builder = MeshBuilder()
    for (x0, z0), (x1, z1) in zip(outline, outline[1:] + outline[:1], strict=True):
        builder.add_quad((x0, 0.0, z0), (x1 - x0, 0.0, z1 - z0), (0.0, 2.4, 0.0), WALL)
    builder.add_quad((0.0, 0.0, 0.0), (6.0, 0.0, 0.0), (0.0, 0.0, 3.0), FLOOR)
    builder.add_quad((0.0, 0.0, 3.0), (3.0, 0.0, 0.0), (0.0, 0.0, 3.0), FLOOR)

    root = tmp_path / "20261103-141502_main_l_framing_aaaaaa"
    root.mkdir()
    builder.write(root)
    (root / "manifest.json").write_text(json.dumps({"session_id": root.name}), encoding="utf-8")

    report = propose_corners(Session.load(root))
    assert len(report.walls) == 6
    assert flat(report.candidates) == sorted(outline)
    assert report.against_landmarks is None, "no taps to score against"
    ghost = np.array([6.0, 6.0])
    assert all(
        np.linalg.norm(np.array([c.p_w[0], c.p_w[2]]) - ghost) > 1.0 for c in report.candidates
    )


def test_a_wall_straddling_zero_degrees_is_one_wall():
    """Face normals on the same wall come back pointing both ways from ARKit,
    which puts their azimuths at 0 and 180 degrees. Folding is what keeps that
    one wall from being clustered as two."""
    builder = MeshBuilder()
    # Two halves of the same wall on x = 2, wound in opposite directions.
    builder.add_quad((2.0, 0.0, 0.0), (0.0, 0.0, 2.0), (0.0, 2.0, 0.0), WALL)
    builder.add_quad((2.0, 0.0, 2.0), (0.0, 2.0, 0.0), (0.0, 0.0, 2.0), WALL)
    walls = find_walls(builder.mesh())
    assert len(walls) == 1
    assert walls[0].area_m2 == pytest.approx(8.0)
    assert walls[0].extent_m == pytest.approx((0.0, 4.0))
    assert walls[0].azimuth_deg == pytest.approx(0.0, abs=1e-6)


def test_the_floor_falls_back_to_the_wall_bottoms():
    builder = MeshBuilder()
    builder.add_quad((0.0, -0.4, 0.0), (3.0, 0.0, 0.0), (0.0, 2.0, 0.0), WALL)
    mesh = builder.mesh()
    walls = find_walls(mesh)
    assert floor_height(mesh, walls) == (pytest.approx(-0.4), "wall bottoms")
    assert floor_height(MeshBuilder().mesh(), []) == (0.0, "assumed")


def test_scoring_reports_misses_and_strays():
    candidates = corner_candidates(find_walls(read_mesh_of_box()), 0.0)
    taps = [
        Landmark(
            t=0.0,
            i=0,
            label="room corner 1",
            kind="corner",
            p_w=np.array([0.05, 0.0, 0.0]),
            method="",
        ),
        Landmark(
            t=1.0,
            i=1,
            label="room corner 2",
            kind="corner",
            p_w=np.array([2.0, 0.0, 2.5]),
            method="",
        ),
        Landmark(t=2.0, i=2, label="door", kind="door", p_w=np.array([4.0, 0.0, 0.0]), method=""),
    ]
    scored, summary = compare_with_landmarks(candidates, taps)
    assert summary["tapped_corners"] == 2, "only corners count; the door is not one"
    assert summary["matched"] == 1
    assert summary["fraction"] == 0.5
    missed = next(entry for entry in summary["landmarks"] if entry["label"] == "room corner 2")
    assert missed["within"] is False and missed["distance_m"] > 1.0
    # Three of the four candidates are nowhere near a tap; the report says which.
    assert len(summary["candidates_without_a_tap"]) == 3
    hit = next(c for c in scored if c.nearest_landmark["label"] == "room corner 1")
    assert hit.nearest_landmark["distance_m"] == pytest.approx(0.05, abs=0.01)


def read_mesh_of_box():
    builder = MeshBuilder()
    w, d, h = 4.0, 5.0, 2.5
    builder.add_quad((0.0, 0.0, 0.0), (w, 0.0, 0.0), (0.0, h, 0.0), WALL)
    builder.add_quad((w, 0.0, 0.0), (0.0, 0.0, d), (0.0, h, 0.0), WALL)
    builder.add_quad((w, 0.0, d), (-w, 0.0, 0.0), (0.0, h, 0.0), WALL)
    builder.add_quad((0.0, 0.0, d), (0.0, 0.0, -d), (0.0, h, 0.0), WALL)
    return builder.mesh()


def test_the_written_file_marks_everything_as_a_candidate(box: Session):
    """Rule 9: a candidate has a source and a confidence and nobody has confirmed
    it. And it lives under derived/, never in landmarks.jsonl."""
    before = (box.root / "landmarks.jsonl").read_bytes()
    report = propose_corners(box)
    target = write_candidates(box, report)
    assert target == box.root / "derived" / "corner_candidates.json"
    assert (box.root / "landmarks.jsonl").read_bytes() == before

    data = json.loads(target.read_text(encoding="utf-8"))
    assert data["source"] == "mesh"
    assert "not measurements" in data["note"]
    for candidate in data["candidates"]:
        assert candidate["source"] == "mesh"
        assert candidate["confirmed"] is None
        assert 0.0 <= candidate["confidence"] <= 1.0
        assert candidate["nearest_landmark"]["label"].startswith("corner-")


def test_a_session_without_a_mesh_says_so(session_dir: Path):
    with pytest.raises(SessionError, match="no mesh.obj"):
        propose_corners(Session.load(session_dir))


def test_a_classes_file_of_the_wrong_length_is_refused(box: Session, tmp_path: Path):
    copy = tmp_path / box.root.name
    shutil.copytree(box.root, copy)
    (copy / "mesh_classes.u8").write_bytes(b"\x01" * 3)
    with pytest.raises(SessionError, match="one per face"):
        read_mesh(Session.load(copy))


def test_a_face_naming_a_missing_vertex_is_refused(tmp_path: Path):
    root = tmp_path / "broken"
    root.mkdir()
    (root / "mesh.obj").write_text("v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 9\n", encoding="utf-8")
    (root / "manifest.json").write_text("{}", encoding="utf-8")
    with pytest.raises(SessionError, match="not there"):
        read_mesh(Session.load(root))


def test_a_mesh_with_no_walls_proposes_nothing(tmp_path: Path):
    root = tmp_path / "floor-only"
    root.mkdir()
    builder = MeshBuilder()
    builder.add_quad((0.0, 0.0, 0.0), (3.0, 0.0, 0.0), (0.0, 0.0, 3.0), FLOOR)
    builder.write(root)
    (root / "manifest.json").write_text("{}", encoding="utf-8")
    report = propose_corners(Session.load(root))
    assert report.walls == []
    assert report.candidates == []
    assert "0 corner candidate(s)" in report.render()
