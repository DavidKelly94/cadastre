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
    corner_names,
    find_walls,
    floor_height,
    match_outline,
    propose_corners,
    room_outline,
    write_candidates,
)
from vividhome.mesh import FLOOR, NONE, WALL, MeshBuilder, read_mesh
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


# --- What the phone would have proposed (ADR-0034) ---------------------------

#: The synthetic room on a drawing at 1 cm a pixel: 4 m across, 5 m down the
#: page, its north-west corner at pixel (100, 100).
ROOM_PIXELS = [[100, 100], [500, 100], [500, 600], [100, 600]]
L_METERS = [(0.0, 0.0), (6.0, 0.0), (6.0, 3.0), (3.0, 3.0), (3.0, 6.0), (0.0, 6.0)]


def store_with_outline(store: Path, outline: list | None = ROOM_PIXELS) -> Path:
    plans = store / "plans"
    plans.mkdir(parents=True)
    room = {"room": "room", "x": 300, "y": 350}
    if outline is not None:
        room["outline"] = outline
    plan = {
        "level": "main",
        "image": "main.png",
        "metres_per_pixel": 0.01,
        "origin_px": [100, 100],
        "rotation_deg": 0.0,
        "rooms": [room],
    }
    (plans / "main.json").write_text(json.dumps(plan), encoding="utf-8")
    return store


def moved(points: list[tuple[float, float]], turn_deg: float, dx: float, dz: float):
    """The same corners as a scan would hold them: turned and shifted."""
    angle = np.radians(turn_deg)
    c, s = np.cos(angle), np.sin(angle)
    return [(c * x - s * z + dx, s * x + c * z + dz) for x, z in points]


def test_corners_are_named_as_the_phone_names_them():
    assert corner_names(ROOM_PIXELS) == ["corner-nw", "corner-ne", "corner-se", "corner-sw"]
    # The L of the phone's own test (RoomOutlineTests): the quarter is decided
    # by the center, and the suffixes count up in outline order.
    ell = [[0, 0], [400, 0], [400, 150], [250, 150], [250, 400], [0, 400]]
    assert corner_names(ell) == [
        "corner-nw",
        "corner-ne",
        "corner-ne2",
        "corner-ne3",
        "corner-se",
        "corner-sw",
    ]
    assert corner_names([[0, 0], [1, 1]]) == [], "two points are not an outline"


def test_the_outline_comes_out_of_the_plan_in_house_meters(tmp_path: Path):
    store = store_with_outline(tmp_path / "store")
    outline = room_outline(store, "main", "room")
    assert [label for label, _, _ in outline] == [
        "corner-nw",
        "corner-ne",
        "corner-se",
        "corner-sw",
    ]
    assert [(x, z) for _, x, z in outline] == pytest.approx(
        [(0.0, 0.0), (4.0, 0.0), (4.0, 5.0), (0.0, 5.0)]
    )
    assert room_outline(store, "main", "kitchen") is None
    assert room_outline(store, "upper", "room") is None
    assert room_outline(store_with_outline(tmp_path / "bare", None), "main", "room") is None


def test_a_room_that_fits_one_way_is_matched_wherever_the_scan_started():
    outline = [(f"c{n}", x, z) for n, (x, z) in enumerate(L_METERS)]
    # Five of the six corners, turned and shifted, and a cabinet's corner.
    scan = moved(L_METERS[:5], 137.0, -2.0, 9.5) + [(40.0, 40.0)]
    match = match_outline(scan, outline)
    assert match is not None
    assert match.fit.marks == (("c0", 0), ("c1", 1), ("c2", 2), ("c3", 3), ("c4", 4))
    assert match.fit.rms_m == pytest.approx(0.0, abs=1e-9)
    assert match.missing == ("c5",)
    assert match.alternatives == (), "an L only goes on one way round"


def test_a_rectangle_fits_two_ways_and_neither_is_chosen():
    outline = [("nw", 0.0, 0.0), ("ne", 4.0, 0.0), ("se", 4.0, 5.0), ("sw", 0.0, 5.0)]
    match = match_outline(moved([(x, z) for _, x, z in outline], 30.0, 1.0, 2.0), outline)
    assert match is not None
    assert len(match.fit.marks) == 4 and match.missing == ()
    assert len(match.ways) == 2
    assert {way.marks for way in match.ways} == {
        (("nw", 0), ("ne", 1), ("se", 2), ("sw", 3)),
        (("nw", 2), ("ne", 3), ("se", 0), ("sw", 1)),
    }


def test_one_corner_or_a_room_of_another_size_is_no_match():
    outline = [("nw", 0.0, 0.0), ("ne", 4.0, 0.0), ("se", 4.0, 5.0), ("sw", 0.0, 5.0)]
    assert match_outline([(0.0, 0.0)], outline) is None
    assert match_outline([(0.0, 0.0), (7.0, 0.0), (7.0, 9.0), (0.0, 9.0)], outline) is None


def test_the_proposal_is_held_against_the_taps(box: Session, tmp_path: Path, monkeypatch):
    """The fixture's taps are its four corners, by the outline's names, so the
    proposal the phone would have made lands on every one of them, and of the
    two ways a rectangle fits, the taps say which."""
    monkeypatch.setenv("VIVIDHOME_UNITS", "imperial")
    report = propose_corners(box, store=store_with_outline(tmp_path / "store"))
    outline = report.against_outline
    assert outline is not None
    assert (outline["room"], outline["corners"], outline["found"]) == ("room", 4, 4)
    assert outline["ways"] == 2 and outline["way"] in (1, 2)
    assert outline["missing"] == []
    assert [mark["label"] for mark in outline["marks"]] == [
        "corner-nw",
        "corner-ne",
        "corner-se",
        "corner-sw",
    ]
    assert all(mark["tap_distance_m"] < 0.02 for mark in outline["marks"])

    text = report.render()
    assert "the phone would have proposed 4 of 4 corners, 2 ways round" in text
    assert f"way {outline['way']} of 2 is the one the taps agree with" in text
    assert "0 in from the tap" in text
    assert propose_corners(box).against_outline is None, "no store, nothing to match"
    assert "no outline for this room" in propose_corners(box).render()


def test_open_framing_falls_back_to_every_vertical_face(tmp_path: Path):
    """ARKit rarely calls studs a wall. With next to nothing classified, the
    phone fits walls to every vertical face, and so does this."""
    builder = MeshBuilder()
    for (x0, z0), (x1, z1) in zip(L_METERS, L_METERS[1:] + L_METERS[:1], strict=True):
        builder.add_quad((x0, 0.0, z0), (x1 - x0, 0.0, z1 - z0), (0.0, 2.4, 0.0), NONE)
    root = tmp_path / "20261103-141502_main_room_framing_bbbbbb"
    root.mkdir()
    builder.write(root)
    manifest = {"session_id": root.name, "level": {"slug": "main"}, "room": {"slug": "room"}}
    (root / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
    pixels = [[100 + 100 * x, 100 + 100 * z] for x, z in L_METERS]

    session = Session.load(root)
    assert find_walls(read_mesh(session)) == []
    report = propose_corners(session, store=store_with_outline(tmp_path / "store", pixels))
    assert report.wall_source == "every vertical face"
    assert len(report.walls) == 6
    assert report.against_outline["found"] == 6
    assert report.against_outline["ways"] == 1
    assert report.against_outline["way"] is None, "nobody tapped, so nothing to agree with"
    assert all(mark["tap_distance_m"] is None for mark in report.against_outline["marks"])
    assert "every vertical face was used" in report.render()
