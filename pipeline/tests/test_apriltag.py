"""apriltag is checked against synth's ground truth, which is the whole reason
synth exists: a recovered pose is compared with the pose that drew the tag."""

from __future__ import annotations

import json

import numpy as np
import pytest

from cadastre.apriltag import (
    MAX_DISTANCE_M,
    MIN_TAG_SIDE_PX,
    R_AM,
    aggregate,
    check_anchor_frame,
    solve_session,
    write_detections,
)
from cadastre.session import Session
from cadastre.synth import build

#: The accuracy docs/design/pipeline-design.md §9 asks of this fixture.
TOLERANCE_M = 0.01
TOLERANCE_DEG = 1.0


@pytest.fixture(scope="module")
def synth(tmp_path_factory):
    return build(tmp_path_factory.mktemp("apriltag") / "20261103-141502_main_room_framing_aaaaaa")


@pytest.fixture(scope="module")
def solved(synth):
    return aggregate(solve_session(Session.load(synth.root)))


def rotation_error_deg(a: np.ndarray, b: np.ndarray) -> float:
    cosine = (float(np.trace(a[:3, :3].T @ b[:3, :3])) - 1.0) / 2.0
    return float(np.degrees(np.arccos(min(1.0, max(-1.0, cosine)))))


def test_r_am_matches_the_documented_columns():
    # session-format.md §8: columns (1,0,0), (0,0,-1), (0,1,0).
    np.testing.assert_allclose(R_AM[:3, 0], [1, 0, 0])
    np.testing.assert_allclose(R_AM[:3, 1], [0, 0, -1])
    np.testing.assert_allclose(R_AM[:3, 2], [0, 1, 0])
    np.testing.assert_allclose(R_AM[:3, :3] @ R_AM[:3, :3].T, np.eye(3), atol=1e-12)
    assert np.linalg.det(R_AM[:3, :3]) == pytest.approx(1.0)


def test_every_marker_is_found(synth, solved):
    assert set(solved) == set(synth.marker_poses)
    for solution in solved.values():
        assert solution.n_obs >= 3


def test_recovered_poses_match_the_ground_truth(synth, solved):
    for marker, solution in solved.items():
        truth = synth.marker_poses[marker]
        offset = float(np.linalg.norm(solution.T_wm[:3, 3] - truth[:3, 3]))
        angle = rotation_error_deg(solution.T_wm, truth)
        assert offset < TOLERANCE_M, f"{marker} is {offset * 100:.2f} cm out"
        assert angle < TOLERANCE_DEG, f"{marker} is {angle:.2f} deg out"


def test_spread_is_reported_and_small(solved):
    for solution in solved.values():
        assert 0.0 < solution.spread_m < 0.05
        assert 0.0 < solution.spread_deg < 5.0


def test_observations_pass_the_rejection_thresholds(synth):
    for observation in solve_session(Session.load(synth.root)):
        assert observation.reprojection_px <= 1.5
        assert observation.tag_side_px >= MIN_TAG_SIDE_PX
        assert observation.distance_m <= MAX_DISTANCE_M


def test_stride_reduces_the_work(synth):
    every = solve_session(Session.load(synth.root))
    strided = solve_session(Session.load(synth.root), stride=4)
    assert len(strided) < len(every)
    assert all(o.frame_index % 4 == 0 for o in strided if o.source.startswith("rgb/"))


def test_stride_must_be_positive(synth):
    with pytest.raises(ValueError, match="at least 1"):
        solve_session(Session.load(synth.root), stride=0)


def test_a_tag_that_is_too_small_is_rejected(synth):
    """A distant tag fails the 40 px rule, so nothing is solved from it."""
    far = build(
        synth.root.parent / "far",
        type(synth.spec)(keyframes=8, path_radius_m=0.05, focal_px=90, colour_w=160, colour_h=120),
    )
    assert solve_session(Session.load(far.root)) == []


def test_median_translation_ignores_an_outlier(synth, solved):
    """One bad detection must not drag a marker the others agree on."""
    marker = next(iter(solved))
    observations = [o for o in solve_session(Session.load(synth.root)) if o.marker_id == marker]
    assert len(observations) >= 3

    rogue = observations[0]
    displaced = rogue.T_wm.copy()
    displaced[:3, 3] += np.array([1.0, 0.0, 0.0])
    poisoned = [*observations, type(rogue)(**{**rogue.__dict__, "T_wm": displaced})]

    clean = aggregate(observations)[marker]
    with_outlier = aggregate(poisoned)[marker]
    moved = float(np.linalg.norm(with_outlier.T_wm[:3, 3] - clean.T_wm[:3, 3]))
    assert moved < 0.02, f"a 1 m outlier moved the median by {moved * 100:.1f} cm"
    assert with_outlier.spread_m > 0.5, "the outlier must still show up in the spread"


def test_anchor_frame_agrees_with_pnp(synth, solved):
    """The app's ARKit anchors, converted with R_AM, must land on the PnP poses.

    synth writes the anchor frame rather than the marker frame, so this compares
    two independent paths to the same pose and would fail if R_AM were wrong.
    """
    agreements = check_anchor_frame(Session.load(synth.root), solved)
    assert len(agreements) == len(solved)
    for agreement in agreements:
        assert agreement.translation_error_m < TOLERANCE_M
        assert agreement.rotation_error_deg < TOLERANCE_DEG
        assert all(axis < TOLERANCE_DEG for axis in agreement.per_axis_deg)


def test_a_wrong_r_am_would_be_caught(synth, solved, monkeypatch):
    """The check has to be capable of failing, or it proves nothing."""
    import cadastre.apriltag as module

    wrong = np.eye(4)  # the identity: treat the anchor frame as the marker frame
    monkeypatch.setattr(module, "R_AM", wrong)
    agreements = module.check_anchor_frame(Session.load(synth.root), solved)
    assert agreements
    assert any(a.rotation_error_deg > 45.0 for a in agreements)


def test_write_detections_lands_under_derived(synth, solved):
    session = Session.load(synth.root)
    target = write_detections(session, solved)
    assert target == synth.root / "derived" / "markers_detected.json"

    payload = json.loads(target.read_text(encoding="utf-8"))
    assert set(payload) == set(solved)
    for marker, entry in payload.items():
        assert len(entry["T_wm"]) == 16
        assert entry["n_obs"] == solved[marker].n_obs
        assert entry["spread_m"] >= 0
        assert entry["spread_deg"] >= 0
