"""The field maths on the phone against the pipeline it was ported from.

``CornerSnap`` and ``WallCoverage`` in the Swift core package are ports of
``corners.py`` and ``coverage.py``, written blind. The ``contract`` CI job has
``vividhome-fixture`` write a session with a classified room mesh and run both
on it, leaving its answers in a JSON file; these tests run the Python on the
same session and hold the two together. Skipped unless that output exists,
which locally means running the fixture first::

    swift run --package-path ios/VividHomeCore vividhome-fixture /tmp/fixture /tmp/fixture.json
    VIVIDHOME_CONTRACT_SESSION=/tmp/fixture VIVIDHOME_CONTRACT_JSON=/tmp/fixture.json \\
        uv run pytest tests/test_contract.py
"""

from __future__ import annotations

import json
import math
import os
from pathlib import Path

import pytest

from vividhome.corners import propose_corners
from vividhome.coverage import wall_coverage
from vividhome.fieldcheck import CHECKLIST, lines
from vividhome.session import Session

SESSION = os.environ.get("VIVIDHOME_CONTRACT_SESSION")
RESULTS = os.environ.get("VIVIDHOME_CONTRACT_JSON")

pytestmark = pytest.mark.skipif(
    not SESSION or not RESULTS,
    reason="set VIVIDHOME_CONTRACT_SESSION and VIVIDHOME_CONTRACT_JSON to vividhome-fixture's output",
)


@pytest.fixture(scope="module")
def session() -> Session:
    return Session.load(Path(SESSION or ""))


@pytest.fixture(scope="module")
def swift() -> dict:
    return json.loads(Path(RESULTS or "").read_text(encoding="utf-8"))


def test_the_snap_lands_where_the_pipeline_proposes_the_corners(session: Session, swift: dict):
    report = propose_corners(session)
    assert report.floor_source == "floor faces"
    assert len(report.candidates) == 4, [c.p_w for c in report.candidates]

    assert len(swift["snaps"]) == 4
    for snap in swift["snaps"]:
        assert snap["position"] is not None, (
            f"{snap['label']}: the phone found no corner to snap to"
        )
        x, y, z = snap["position"]
        nearest = min(report.candidates, key=lambda c: math.hypot(c.p_w[0] - x, c.p_w[2] - z))
        assert math.hypot(nearest.p_w[0] - x, nearest.p_w[2] - z) < 0.01, (snap, nearest)
        assert abs(nearest.p_w[1] - y) < 0.01, (snap, nearest)
        assert snap["floor_source"] == "floor-faces"
        # The taps were placed a few centimetres off on purpose; a snap that
        # moved nothing would mean it kept the tap.
        assert snap["moved_by"] > 0.03

    # And the pipeline agrees the taps were near its corners.
    assert report.against_landmarks is not None
    assert report.against_landmarks["matched"] == 4


def test_the_live_coverage_is_the_offline_coverage(session: Session, swift: dict):
    report = wall_coverage(session)
    assert report.range_m == swift["range_m"]
    assert report.keyframes_used == swift["keyframes_used"]
    assert report.keyframes_total == swift["keyframes_total"]

    by_wall = {(wall["start"], wall["end"]): wall for wall in swift["coverage"]}
    assert set(by_wall) == {(wall.start, wall.end) for wall in report.walls}
    for wall in report.walls:
        other = by_wall[(wall.start, wall.end)]
        assert wall.length_m == pytest.approx(other["length_m"], abs=1e-6)
        assert wall.photographed_fraction == pytest.approx(other["photographed_fraction"], abs=1e-9)
        gaps = wall.gaps(wall.photographed)
        assert len(gaps) == len(other["not_photographed_m"]), (wall.start, gaps, other)
        for (start, end), (other_start, other_end) in zip(
            gaps, other["not_photographed_m"], strict=True
        ):
            assert start == pytest.approx(other_start, abs=0.011)
            assert end == pytest.approx(other_end, abs=0.011)

    # The walk went along the north wall, so it is the one that is photographed.
    north = next(wall for wall in report.walls if wall.start == "corner-nw")
    assert north.photographed_fraction > 0.9


def test_the_checklist_and_the_leave_checks_sentences_read_the_same_on_both_ends(swift: dict):
    """The stills checklist is the protocol's table on both sides, and the review
    screen's three lines are made from the manifest's numbers by both sides."""
    assert [item["id"] for item in swift["checklist"]] == list(CHECKLIST)
    assert {item["id"]: item["name"] for item in swift["checklist"]} == CHECKLIST
    assert len(swift["field_checks"]) >= 5
    for sample in swift["field_checks"]:
        assert lines(sample["check"]) == sample["lines"], sample["check"]
