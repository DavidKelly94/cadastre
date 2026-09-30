"""Per-wall coverage against the tapped footprint.

The synthetic room is walked in a full circle looking outward, so every wall is
photographed and meshed; the tests then take keyframes and walls away and check
the report names what is missing, in metres from a corner."""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pytest

from vividhome.coverage import CELL_M, _visible, footprint, wall_coverage, write_coverage
from vividhome.mesh import FLOOR, WALL, MeshBuilder
from vividhome.session import Session, SessionError
from vividhome.synth import SynthSpec, build

SPEC = SynthSpec(keyframes=24)


@pytest.fixture
def room(tmp_path: Path) -> Session:
    root = tmp_path / "20261103-141502_main_room_framing_aaaaaa"
    return Session.load(build(root, SPEC).root)


def by_name(report) -> dict[str, object]:
    return {f"{wall.start} -> {wall.end}": wall for wall in report.walls}


def test_a_full_walk_covers_every_wall(room: Session):
    report = wall_coverage(room)
    assert report.corners == ["corner-nw", "corner-ne", "corner-se", "corner-sw"]
    assert report.keyframes_used == report.keyframes_total == 24
    assert report.has_mesh
    assert [wall.length_m for wall in report.walls] == pytest.approx([4.0, 5.0, 4.0, 5.0])
    for wall in report.walls:
        assert wall.meshed_fraction == 1.0, wall.start
        assert wall.photographed_fraction == 1.0, wall.start
        assert wall.gaps(wall.photographed) == []


def test_a_partial_walk_names_the_walls_it_missed(room: Session):
    """Keep the first six keyframes: a quarter turn from the north wall, looking
    outward. The report has to say which walls were not photographed and where,
    while the mesh — which is the whole room — stays fully meshed."""
    frames = (room.root / "frames.jsonl").read_text(encoding="utf-8").splitlines()
    (room.root / "frames.jsonl").write_text("\n".join(frames[:6]) + "\n", encoding="utf-8")

    report = wall_coverage(room)
    assert report.keyframes_total == 6
    walls = by_name(report)
    assert all(wall.meshed_fraction == 1.0 for wall in report.walls)

    seen = {name: wall.photographed_fraction for name, wall in walls.items()}
    assert seen["corner-nw -> corner-ne"] > 0.5, "the north wall is where the walk starts"
    assert seen["corner-se -> corner-sw"] < 0.3, "the south wall is behind the camera"
    south = walls["corner-se -> corner-sw"]
    gaps = south.gaps(south.photographed)
    assert gaps, "a wall mostly unphotographed reports where"
    assert gaps[-1][1] == pytest.approx(south.length_m)
    text = report.render()
    assert "not photographed" in text
    assert "from corner-se" in text


def test_a_wall_missing_from_the_mesh_is_reported_as_not_meshed(tmp_path: Path):
    """Three walls meshed, the fourth never scanned. No keyframes at all, so
    nothing is photographed either, and the report must not pretend."""
    root = tmp_path / "20261103-141502_main_room_framing_aaaaaa"
    root.mkdir()
    builder = MeshBuilder()
    w, d, h = 4.0, 5.0, 2.5
    builder.add_quad((0.0, 0.0, 0.0), (w, 0.0, 0.0), (0.0, h, 0.0), WALL)
    builder.add_quad((w, 0.0, 0.0), (0.0, 0.0, d), (0.0, h, 0.0), WALL)
    builder.add_quad((0.0, 0.0, d), (0.0, 0.0, -d), (0.0, h, 0.0), WALL)  # z = D wall left out
    builder.add_quad((0.0, 0.0, 0.0), (w, 0.0, 0.0), (0.0, 0.0, d), FLOOR)
    builder.write(root)
    (root / "manifest.json").write_text(json.dumps({"session_id": root.name}), encoding="utf-8")
    taps = [
        ("corner-nw", [0.0, 0.0, 0.0]),
        ("corner-ne", [w, 0.0, 0.0]),
        ("corner-se", [w, 0.0, d]),
        ("corner-sw", [0.0, 0.0, d]),
        ("door-1", [2.0, 0.0, 0.0]),
    ]
    (root / "landmarks.jsonl").write_text(
        "".join(
            json.dumps(
                {
                    "t": float(n),
                    "i": n,
                    "label": label,
                    "kind": "door" if label.startswith("door") else "corner",
                    "p_w": point,
                }
            )
            + "\n"
            for n, (label, point) in enumerate(taps)
        ),
        encoding="utf-8",
    )

    report = wall_coverage(Session.load(root))
    assert report.corners == ["corner-nw", "corner-ne", "corner-se", "corner-sw"], (
        "doors are not corners"
    )
    assert report.keyframes_total == 0
    walls = by_name(report)
    assert walls["corner-se -> corner-sw"].meshed_fraction == 0.0
    assert walls["corner-se -> corner-sw"].gaps(walls["corner-se -> corner-sw"].meshed) == [
        (0.0, 4.0)
    ]
    for name in ("corner-nw -> corner-ne", "corner-ne -> corner-se", "corner-sw -> corner-nw"):
        assert walls[name].meshed_fraction == 1.0, name
    assert all(wall.photographed_fraction == 0.0 for wall in report.walls)
    assert "not meshed 0.0..4.0 m from corner-se" in report.render()


def test_a_wall_behind_another_wall_is_not_photographed():
    """Occlusion is what stops an L-shaped room's far wall from counting as seen
    through the wall of the notch."""
    origin = np.array([0.0, 0.0])
    targets = np.array([[2.0, 0.0], [2.0, 3.0]])
    blocker = np.array([[[1.0, -1.0], [1.0, 1.0]]])
    assert list(_visible(origin, targets, blocker)) == [False, True]
    assert list(_visible(origin, targets, np.zeros((0, 2, 2)))) == [True, True]


def test_a_camera_pointed_at_the_floor_does_not_count(room: Session):
    frames = [json.loads(line) for line in (room.root / "frames.jsonl").read_text().splitlines()]
    down = np.eye(4)
    down[:3, :3] = np.array([[1.0, 0.0, 0.0], [0.0, 0.0, -1.0], [0.0, 1.0, 0.0]])  # -z -> -y
    down[:3, 3] = [2.0, 1.5, 2.5]
    for frame in frames:
        frame["T_wc"] = down.flatten(order="F").tolist()
    (room.root / "frames.jsonl").write_text(
        "".join(json.dumps(frame) + "\n" for frame in frames), encoding="utf-8"
    )
    report = wall_coverage(room)
    assert report.keyframes_used == 0
    assert all(wall.photographed_fraction == 0.0 for wall in report.walls)


def test_range_limits_what_counts_as_photographed(room: Session):
    """The synthetic walk is 1.2 m from the centre of a 4 x 5 m room, so the far
    end of every wall is more than 2 m from every camera on the near side."""
    close = wall_coverage(room, range_m=1.0)
    assert all(wall.photographed_fraction < 1.0 for wall in close.walls)
    assert any(wall.photographed_fraction > 0.0 for wall in close.walls)


def test_fewer_than_three_corners_is_refused(session_dir: Path):
    with pytest.raises(SessionError, match="at least three"):
        footprint(Session.load(session_dir))


def test_the_written_report_names_its_denominator(room: Session):
    target = write_coverage(room, wall_coverage(room))
    assert target == room.root / "derived" / "coverage.json"
    data = json.loads(target.read_text(encoding="utf-8"))
    assert "tapped" in data["denominator"]
    assert len(data["walls"]) == 4
    assert data["walls"][0]["not_photographed_m"] == []
    assert data["walls"][0]["length_m"] == pytest.approx(4.0)
    assert CELL_M == 0.1
