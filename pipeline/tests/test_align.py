"""align is checked by choosing a T_hs, deriving the clicks from it, and asking
whether the solver gets it back."""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pytest
from PIL import Image

from vividhome.align import (
    REFUSE_RMS_M,
    AlignError,
    floor_y_session,
    landmark_pairs,
    marker_pairs,
    solve,
    update_marker_map,
    write_alignment,
)
from vividhome.plan import add_plan, calibrate, house_to_plan
from vividhome.session import Session
from vividhome.synth import SynthSpec, build
from vividhome.transforms import mat_to_cm, se2_to_mat, theta_from_se2


@pytest.fixture(scope="module")
def scene(tmp_path_factory):
    """A synthetic session plus a calibrated plan, in one store."""
    root = tmp_path_factory.mktemp("align")
    truth = build(root / "20261103-141502_main_room_framing_aaaaaa", SynthSpec(keyframes=12))
    store = root / "vividhome-data"

    source = root / "plan.png"
    Image.new("RGB", (1200, 900), (255, 255, 255)).save(source, "PNG")
    add_plan(store, source, "main")
    calibration = calibrate(
        store,
        "main",
        point_a=(100.0, 100.0),
        point_b=(600.0, 100.0),
        distance_m=5.0,
        origin_px=(100.0, 100.0),
        floor_height_m=0.0,
    )
    return truth, store, calibration


def clicks_for(session: Session, calibration, transform: np.ndarray) -> dict:
    """Where each landmark would be clicked on the plan, under `transform`."""
    out = {}
    for landmark in session.landmarks():
        house = transform @ np.array([landmark.p_w[0], 0.0, landmark.p_w[2], 1.0])
        out[landmark.label] = house_to_plan(calibration, house[0], house[2])
    return out


def test_recovers_a_known_se2_within_a_millimetre(scene):
    truth, _store, calibration = scene
    session = Session.load(truth.root)

    for degrees, tx, tz in [(0.0, 0.0, 0.0), (37.0, 2.5, -1.25), (-115.0, -4.0, 8.5)]:
        expected = se2_to_mat(np.radians(degrees), tx, 0.0, tz)
        pairs = landmark_pairs(session, calibration, clicks_for(session, calibration, expected))
        alignment = solve(session, calibration, pairs)

        offset = float(np.linalg.norm(alignment.T_hs[:3, 3] - expected[:3, 3]))
        yaw = abs(np.degrees(theta_from_se2(alignment.T_hs)) - degrees)
        assert offset < 0.001, f"{degrees} deg: translation out by {offset * 1000:.3f} mm"
        assert yaw < 0.01, f"{degrees} deg: yaw out by {yaw:.4f} deg"
        assert alignment.rms_m < 1e-9


def test_the_transform_maps_landmarks_onto_their_plan_points(scene):
    truth, _store, calibration = scene
    session = Session.load(truth.root)
    expected = se2_to_mat(np.radians(20.0), 1.0, 0.0, 2.0)
    pairs = landmark_pairs(session, calibration, clicks_for(session, calibration, expected))
    alignment = solve(session, calibration, pairs)

    for pair in pairs:
        mapped = alignment.T_hs @ [pair.session_xz[0], 0.0, pair.session_xz[1], 1.0]
        assert mapped[0] == pytest.approx(pair.house_xz[0], abs=1e-9)
        assert mapped[2] == pytest.approx(pair.house_xz[1], abs=1e-9)


def test_noise_shows_up_as_residual_rather_than_being_absorbed(scene):
    truth, _store, calibration = scene
    session = Session.load(truth.root)
    expected = se2_to_mat(np.radians(10.0), 0.5, 0.0, 0.5)

    clicks = clicks_for(session, calibration, expected)
    # Move one click by 20 pixels, which at 0.01 m/px is 20 cm.
    label = next(iter(clicks))
    clicks[label] = (clicks[label][0] + 20.0, clicks[label][1])

    alignment = solve(session, calibration, landmark_pairs(session, calibration, clicks))
    assert alignment.rms_m > 0.05
    assert alignment.max_residual_m >= alignment.rms_m


def test_a_hopeless_fit_is_refused_unless_forced(scene):
    truth, _store, calibration = scene
    session = Session.load(truth.root)
    labels = [landmark.label for landmark in session.landmarks()]
    # Clicks in an order that no rigid motion can satisfy.
    scrambled = {
        labels[0]: (100.0, 100.0),
        labels[1]: (900.0, 800.0),
        labels[2]: (120.0, 780.0),
        labels[3]: (880.0, 120.0),
    }
    pairs = landmark_pairs(session, calibration, scrambled)

    with pytest.raises(AlignError, match="above 0.3"):
        solve(session, calibration, pairs)

    forced = solve(session, calibration, pairs, force=True)
    assert forced.rms_m > REFUSE_RMS_M


def test_at_least_two_correspondences_are_needed(scene):
    truth, _store, calibration = scene
    session = Session.load(truth.root)
    one = dict(list(clicks_for(session, calibration, np.eye(4)).items())[:1])
    with pytest.raises(AlignError, match="at least 2"):
        solve(session, calibration, landmark_pairs(session, calibration, one))


def test_an_unknown_landmark_is_named(scene):
    truth, _store, calibration = scene
    session = Session.load(truth.root)
    with pytest.raises(AlignError, match="corner-nowhere"):
        landmark_pairs(session, calibration, {"corner-nowhere": (10.0, 10.0)})


# Floor height


def test_floor_height_prefers_floor_landmarks(tmp_path: Path):
    result = build(tmp_path / "s", SynthSpec(keyframes=3))
    path = result.root / "landmarks.jsonl"
    rows = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()]
    rows.append(
        {
            "t": 1.0,
            "i": 0,
            "label": "floor",
            "kind": "floor",
            "p_w": [1.0, -0.35, 1.0],
            "method": "raycast-estimatedPlane",
        }
    )
    path.write_text("".join(json.dumps(r) + "\n" for r in rows), encoding="utf-8")

    height, source = floor_y_session(Session.load(result.root))
    assert source == "floor-landmarks"
    assert height == pytest.approx(-0.35)


def test_floor_height_falls_back_to_the_mesh(tmp_path: Path):
    result = build(tmp_path / "s", SynthSpec(keyframes=3))
    # Two faces: one floor (class 2) at y = -0.5, one wall (class 1) at y = 1.
    (result.root / "mesh.obj").write_text(
        "v 0 -0.5 0\nv 1 -0.5 0\nv 0 -0.5 1\nv 0 1 0\nv 1 1 0\nv 0 1 1\nf 1 2 3\nf 4 5 6\n",
        encoding="utf-8",
    )
    (result.root / "mesh_classes.u8").write_bytes(bytes([2, 1]))

    height, source = floor_y_session(Session.load(result.root))
    assert source == "mesh"
    assert height == pytest.approx(-0.5)


def test_floor_height_says_when_it_is_guessing(tmp_path: Path):
    result = build(tmp_path / "s", SynthSpec(keyframes=3))
    height, source = floor_y_session(Session.load(result.root))
    # synth tags its corners as corners, not floor, and writes no mesh.
    assert source == "lowest-landmark"
    assert height == pytest.approx(0.0)


def test_t_y_puts_the_session_floor_at_the_level_height(scene, tmp_path: Path):
    truth, store, _ = scene
    session = Session.load(truth.root)
    raised = calibrate(
        store,
        "main",
        point_a=(100.0, 100.0),
        point_b=(600.0, 100.0),
        distance_m=5.0,
        origin_px=(100.0, 100.0),
        floor_height_m=3.2,
        force=True,
    )
    pairs = landmark_pairs(session, raised, clicks_for(session, raised, np.eye(4)))
    alignment = solve(session, raised, pairs)
    # The session floor is at y = 0, so t_y must lift it to 3.2.
    assert alignment.T_hs[1, 3] == pytest.approx(3.2)

    # Put the calibration back for other tests in the module.
    calibrate(
        store,
        "main",
        point_a=(100.0, 100.0),
        point_b=(600.0, 100.0),
        distance_m=5.0,
        origin_px=(100.0, 100.0),
        floor_height_m=0.0,
        force=True,
    )


# Markers


def test_marker_pairs_require_detections(scene, tmp_path: Path):
    _truth, store, _ = scene
    fresh = build(tmp_path / "nodetect", SynthSpec(keyframes=3))
    with pytest.raises(AlignError, match="run 'vividhome apriltag'"):
        marker_pairs(Session.load(fresh.root), store, "synthetic")


def test_markers_are_added_to_the_house_map_then_reused(tmp_path: Path):
    from vividhome.apriltag import aggregate, solve_session, write_detections

    result = build(tmp_path / "s")
    session = Session.load(result.root)
    store = tmp_path / "vividhome-data"

    source = tmp_path / "plan.png"
    Image.new("RGB", (1200, 900), (255, 255, 255)).save(source, "PNG")
    add_plan(store, source, "main")
    calibration = calibrate(
        store,
        "main",
        point_a=(100.0, 100.0),
        point_b=(600.0, 100.0),
        distance_m=5.0,
        origin_px=(100.0, 100.0),
    )

    write_detections(session, aggregate(solve_session(session)))

    expected = se2_to_mat(np.radians(25.0), 1.5, 0.0, -0.5)
    pairs = landmark_pairs(session, calibration, clicks_for(session, calibration, expected))
    alignment = solve(session, calibration, pairs)

    # Nothing in the map yet, so no marker correspondences are available.
    assert marker_pairs(session, store, "synthetic") == []

    added = update_marker_map(store, "synthetic", session, alignment)
    assert set(added) == set(result.marker_poses)

    # Now the same markers can be used as correspondences, and they land where
    # the alignment put them.
    reused = marker_pairs(session, store, "synthetic")
    assert {pair.label for pair in reused} == set(result.marker_poses)
    for pair in reused:
        mapped = alignment.T_hs @ [pair.session_xz[0], 0.0, pair.session_xz[1], 1.0]
        assert mapped[0] == pytest.approx(pair.house_xz[0], abs=1e-9)
        assert mapped[2] == pytest.approx(pair.house_xz[1], abs=1e-9)


def test_an_established_marker_is_not_moved_by_a_later_session(tmp_path: Path):
    """The house map must not drift one small correction at a time."""
    from vividhome.apriltag import aggregate, solve_session, write_detections

    result = build(tmp_path / "s")
    session = Session.load(result.root)
    store = tmp_path / "vividhome-data"
    source = tmp_path / "plan.png"
    Image.new("RGB", (1200, 900), (255, 255, 255)).save(source, "PNG")
    add_plan(store, source, "main")
    calibration = calibrate(
        store,
        "main",
        point_a=(100.0, 100.0),
        point_b=(600.0, 100.0),
        distance_m=5.0,
        origin_px=(100.0, 100.0),
    )
    write_detections(session, aggregate(solve_session(session)))

    first = solve(
        session,
        calibration,
        landmark_pairs(session, calibration, clicks_for(session, calibration, np.eye(4))),
    )
    update_marker_map(store, "synthetic", session, first)
    before = json.loads((store / "markers" / "synthetic.json").read_text(encoding="utf-8"))

    shifted = se2_to_mat(np.radians(90.0), 10.0, 0.0, 10.0)
    second = solve(
        session,
        calibration,
        landmark_pairs(session, calibration, clicks_for(session, calibration, shifted)),
    )
    added = update_marker_map(store, "synthetic", session, second)

    assert added == [], "already-mapped markers must not be re-added"
    after = json.loads((store / "markers" / "synthetic.json").read_text(encoding="utf-8"))
    assert after == before


def test_write_alignment_records_the_transform_and_the_pairs(scene):
    truth, store, calibration = scene
    session = Session.load(truth.root)
    expected = se2_to_mat(np.radians(12.0), 0.25, 0.0, 0.75)
    pairs = landmark_pairs(session, calibration, clicks_for(session, calibration, expected))
    alignment = solve(session, calibration, pairs)

    target = write_alignment(store, alignment)
    assert target == store / "alignments" / f"{session.session_id}.json"

    stored = json.loads(target.read_text(encoding="utf-8"))
    assert stored["session_id"] == session.session_id
    assert stored["level"] == "main"
    assert stored["T_hs"] == mat_to_cm(alignment.T_hs)
    assert len(stored["pairs"]) == len(pairs)
    assert stored["method"] == "landmarks"
    assert stored["floor_source"] == "lowest-landmark"
    assert stored["created_at"]
