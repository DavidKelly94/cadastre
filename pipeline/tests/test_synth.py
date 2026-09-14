"""The synthetic session is the fixture every later feature is tested against, so
its own geometry has to be checked against the numbers that produced it."""

from __future__ import annotations

from pathlib import Path

import cv2
import numpy as np
import pytest

from vividhome.markers import marker_id
from vividhome.session import Session
from vividhome.synth import SynthSpec, _project, _tag_corners_world, build
from vividhome.validate import validate_session


@pytest.fixture(scope="module")
def synth(tmp_path_factory):
    root = tmp_path_factory.mktemp("synth") / "20261103-141502_main_room_framing_aaaaaa"
    return build(root)


def detector() -> cv2.aruco.ArucoDetector:
    return cv2.aruco.ArucoDetector(cv2.aruco.getPredefinedDictionary(cv2.aruco.DICT_APRILTAG_36h11))


def test_the_generated_session_validates(synth):
    report = validate_session(Session.load(synth.root))
    assert report.ok, [str(f) for f in report.findings if f.level == "ERROR"]
    assert report.keyframes == synth.spec.keyframes


def test_it_writes_every_file_the_format_expects(synth):
    for name in (
        "manifest.json",
        "frames.jsonl",
        "stills.jsonl",
        "markers.jsonl",
        "landmarks.jsonl",
    ):
        assert (synth.root / name).exists(), name
    for i in range(synth.spec.keyframes):
        stem = f"{i:06d}"
        assert (synth.root / "rgb" / f"{stem}.jpg").exists()
        assert (synth.root / "depth" / f"{stem}.f32").exists()
        assert (synth.root / "conf" / f"{stem}.u8").exists()


def test_poses_are_rigid_and_at_eye_height(synth):
    for pose in synth.poses:
        rotation = pose[:3, :3]
        np.testing.assert_allclose(rotation @ rotation.T, np.eye(3), atol=1e-9)
        assert np.linalg.det(rotation) == pytest.approx(1.0, abs=1e-9)
        assert pose[1, 3] == pytest.approx(synth.spec.eye_height_m)


def test_the_camera_stays_inside_the_room(synth):
    for pose in synth.poses:
        x, _, z = pose[:3, 3]
        assert 0.0 < x < synth.spec.width_m
        assert 0.0 < z < synth.spec.depth_m


def test_depth_is_consistent_with_the_room_geometry(synth):
    spec = synth.spec
    longest = float(np.hypot(spec.width_m, spec.depth_m))
    varied = 0
    for i in range(spec.keyframes):
        values = np.fromfile(synth.root / "depth" / f"{i:06d}.f32", dtype="<f4")
        assert values.size == spec.depth_w * spec.depth_h
        assert np.all(np.isfinite(values))
        assert values.min() > 0.0, "every ray must hit a surface from inside a closed box"
        assert values.max() <= longest + 1e-3
        if values.max() - values.min() > 0.1:
            varied += 1
    # A camera looking at a corner sees two walls, so most frames are not flat.
    assert varied > spec.keyframes // 2


def test_confidence_matches_the_depth_map_size(synth):
    spec = synth.spec
    data = (synth.root / "conf" / "000000.u8").read_bytes()
    assert len(data) == spec.depth_w * spec.depth_h


def test_the_rendered_tags_are_actually_detectable(synth):
    """The whole point of rendering tags is that a detector finds them."""
    found: dict[int, int] = {}
    for i in range(synth.spec.keyframes):
        image = cv2.imread(str(synth.root / "rgb" / f"{i:06d}.jpg"), cv2.IMREAD_GRAYSCALE)
        _, ids, _ = detector().detectMarkers(image)
        if ids is not None:
            for tag in ids.flatten():
                found[int(tag)] = found.get(int(tag), 0) + 1

    for number in synth.spec.marker_numbers:
        assert number in found, f"tag {number} was never detected"
        assert found[number] >= 3, f"tag {number} needs enough observations to aggregate"


def test_detected_tag_corners_land_where_the_geometry_says(synth):
    """Detected corners must match the reprojection of the known tag corners.

    Comparing against the projection rather than against `fx * size / distance`
    matters: that formula needs depth along the optical axis, not Euclidean
    range, and an off-axis tag legitimately measures larger than the range form
    predicts. Reprojecting tests the whole chain — marker pose, camera pose,
    axis conventions, projection — with no approximation to argue about.
    """
    spec = synth.spec
    checked = 0
    for i in range(spec.keyframes):
        image = cv2.imread(str(synth.root / "rgb" / f"{i:06d}.jpg"), cv2.IMREAD_GRAYSCALE)
        corners, ids, _ = detector().detectMarkers(image)
        if ids is None:
            continue
        for quad, tag in zip(corners, ids.flatten(), strict=True):
            pose = synth.marker_poses[marker_id(int(tag))]
            expected = _project(spec, synth.poses[i], _tag_corners_world(pose))
            assert expected is not None

            detected = np.asarray(quad[0], dtype=float)
            # Centroids are order-independent, so they compare directly.
            np.testing.assert_allclose(detected.mean(axis=0), expected.mean(axis=0), atol=2.0)
            assert _mean_edge(detected) == pytest.approx(_mean_edge(expected), rel=0.05)
            checked += 1
    assert checked >= 6


def _mean_edge(quad: np.ndarray) -> float:
    return float(np.mean([np.linalg.norm(quad[a] - quad[(a + 1) % 4]) for a in range(4)]))


def test_marker_observations_reference_the_frames_that_saw_them(synth):
    session = Session.load(synth.root)
    frame_indices = {frame.i for frame in session.frames()}
    observations = list(session.markers())
    assert observations
    for observation in observations:
        assert observation.i in frame_indices
        assert observation.marker_id in synth.marker_poses
        assert observation.physical_width_m == pytest.approx(0.20)


def test_landmarks_are_the_four_room_corners_at_floor_level(synth):
    session = Session.load(synth.root)
    landmarks = {landmark.label: landmark.p_w for landmark in session.landmarks()}
    assert set(landmarks) == {"corner-nw", "corner-ne", "corner-se", "corner-sw"}
    for position in landmarks.values():
        assert position[1] == pytest.approx(0.0)
    np.testing.assert_allclose(
        landmarks["corner-se"], [synth.spec.width_m, 0.0, synth.spec.depth_m]
    )


def test_marker_poses_sit_on_the_walls_facing_into_the_room(synth):
    spec = synth.spec
    for pose in synth.marker_poses.values():
        rotation = pose[:3, :3]
        np.testing.assert_allclose(rotation @ rotation.T, np.eye(3), atol=1e-9)
        assert np.linalg.det(rotation) == pytest.approx(1.0, abs=1e-9)
        # Upright: the marker's +y is world up.
        np.testing.assert_allclose(rotation[:, 1], [0.0, 1.0, 0.0], atol=1e-9)
        # On a wall: one horizontal coordinate is at a room boundary.
        x, _, z = pose[:3, 3]
        assert min(abs(x), abs(x - spec.width_m), abs(z), abs(z - spec.depth_m)) < 1e-9


def test_the_recorded_anchor_frame_differs_from_the_marker_frame(synth):
    """The app writes ARKit's image-anchor transform, not the canonical marker frame.

    If synth wrote the marker frame directly, `apriltag --check-anchor-frame`
    would be comparing a value against itself and could never catch a wrong R_am.
    """
    session = Session.load(synth.root)
    for observation in session.markers():
        marker = synth.marker_poses[observation.marker_id]
        np.testing.assert_allclose(observation.T_wa[:3, 3], marker[:3, 3], atol=1e-9)
        assert not np.allclose(observation.T_wa[:3, :3], marker[:3, :3])
        # Still a rotation, and the anchor's +y is the marker's face normal.
        rotation = observation.T_wa[:3, :3]
        np.testing.assert_allclose(rotation @ rotation.T, np.eye(3), atol=1e-9)
        np.testing.assert_allclose(rotation[:, 1], marker[:3, 2], atol=1e-9)


def test_a_smaller_session_can_be_requested(tmp_path: Path):
    result = build(tmp_path / "small", SynthSpec(keyframes=4, colour_w=160, colour_h=120))
    assert len(result.poses) == 4
    assert validate_session(Session.load(result.root)).ok
