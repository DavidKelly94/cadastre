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
        assert lines(sample["check"], "imperial") == sample["lines"], sample["check"]
        assert lines(sample["check"], "metric") == sample["lines_metric"], sample["check"]


def test_enough_for_3d_is_measured_the_same_on_both_ends(session: Session, swift: dict):
    """The phone says before the owner leaves whether a model could be built;
    the PC measures the same walk the same way (ADR-0035)."""
    from vividhome.readiness import session_report

    ours = session_report(session)
    theirs = swift["readiness"]
    assert ours["floor"] == theirs["floor"]
    assert ours["ceiling"] == theirs["ceiling"]
    assert ours["heights"] == theirs["heights"]
    assert ours["walls_twice"] == pytest.approx(theirs.get("walls_twice"), abs=0.011)
    assert [gap["wall"] for gap in ours["gaps"]] == [gap["wall"] for gap in theirs["gaps"]]
    for mine, other in zip(ours["gaps"], theirs["gaps"], strict=True):
        assert mine["from_m"] == pytest.approx(other["from_m"], abs=0.11)
        assert mine["length_m"] == pytest.approx(other["length_m"], abs=0.11)


def test_a_length_is_written_the_same_way_on_both_ends(swift: dict):
    """Feet and inches or metric, the owner's choice, from the same meters.
    The table runs from a millimeter to a house, with the halfway cases in."""
    from vividhome import units

    assert len(swift["lengths"]) >= 40
    for sample in swift["lengths"]:
        meters = sample["meters"]
        for name in ("imperial", "metric"):
            assert units.small(meters, name) == sample[f"{name}_small"], meters
            assert units.length(meters, name) == sample[f"{name}_length"], meters
            assert units.area(meters, name) == sample[f"{name}_area"], meters
            assert units.per_pixel(meters, name) == sample[f"{name}_per_pixel"], meters


def test_an_outlines_corners_get_the_same_names_on_both_ends(swift: dict):
    """The name is what the phone asks for and writes to landmarks.jsonl, and
    what the PC looks a tap up by: computed on each end, never stored."""
    from vividhome.corners import corner_names

    assert len(swift["corner_names"]) >= 4
    for sample in swift["corner_names"]:
        assert corner_names(sample["points"]) == sample["names"], sample["points"]


def test_the_scan_goes_on_the_outline_the_same_ways_on_both_ends(session: Session, swift: dict):
    """Proposed marks (ADR-0034): the PC's check of what the phone would have
    proposed is only worth reading if it matches the way the phone matches."""
    from vividhome.corners import match_outline

    def placed(marks: list[tuple[str, float, float]]) -> tuple:
        return tuple((label, round(x, 2), round(z, 2)) for label, x, z in marks)

    assert len(swift["proposals"]) >= 2
    for sample in swift["proposals"]:
        outline = [(point["label"], point["x"], point["z"]) for point in sample["outline"]]
        theirs = {
            placed([(mark["label"], mark["x"], mark["z"]) for mark in way["marks"]])
            for way in sample["ways"]
        }
        assert theirs, "the fixture's rooms are ones the phone can match"

        # The phone's candidates through the PC's matcher: the matcher alone.
        candidates = [(x, z) for x, z in sample["candidates"]]
        match = match_outline(candidates, outline)
        assert match is not None
        ours = {
            placed([(label, *candidates[index]) for label, index in way.marks])
            for way in match.ways
        }
        assert ours == theirs
        assert list(match.missing) == sample["missing"]
        assert match.fit.rms_m == pytest.approx(sample["ways"][0]["rms_m"], abs=1e-6)

        if sample["from_mesh"]:
            # And the PC's own candidates, found in the same mesh, go on the
            # same ways: the finder and the matcher together.
            found = [(c.p_w[0], c.p_w[2]) for c in propose_corners(session).candidates]
            match = match_outline(found, outline)
            assert match is not None
            assert {
                placed([(label, *found[index]) for label, index in way.marks]) for way in match.ways
            } == theirs
