"""Project-level validation, docs/session-format.md section 13."""

from __future__ import annotations

import json
from pathlib import Path

import cv2
import numpy as np

from vividhome.project import validate_project
from vividhome.validate import ERROR, WARN


def write_plan(plans: Path, level: str, *, width=800, height=600, **overrides) -> Path:
    plans.mkdir(parents=True, exist_ok=True)
    image = f"{level}.png"
    cv2.imwrite(str(plans / image), np.full((height, width, 3), 255, np.uint8))
    data = {
        "level": level,
        "image": image,
        "metres_per_pixel": None,
        "origin_px": None,
        "rotation_deg": 0.0,
        "floor_height_m": 0.0,
    }
    data.update(overrides)
    path = plans / f"{level}.json"
    path.write_text(json.dumps(data, indent=2), encoding="utf-8")
    return path


def session_dir(project: Path, level: str, room: str) -> Path:
    path = project / f"20261103-141502_{level}_{room}_k3x7qa"
    path.mkdir(parents=True, exist_ok=True)
    return path


def rules(report, level=ERROR) -> list[int]:
    return sorted(f.rule for f in report.findings if f.level == level)


def test_project_without_plans_is_valid(tmp_path):
    """Section 13: plans are optional and sections 1-12 work without one."""
    project = tmp_path / "our-house"
    session_dir(project, "main", "kitchen")
    report = validate_project(project)
    assert report.ok
    assert report.sessions == 1
    assert report.levels == []


def test_placed_room_within_raster_passes(tmp_path):
    project = tmp_path / "our-house"
    session_dir(project, "main", "kitchen")
    write_plan(project / "plans", "main", rooms=[{"room": "kitchen", "x": 400, "y": 300}])
    report = validate_project(project)
    assert report.ok, report.render()
    assert report.placements == 1
    assert report.levels == ["main"]


def test_room_outside_the_raster_is_an_error(tmp_path):
    """Rule 3. The bound is the image's real size, not a recorded one."""
    project = tmp_path / "our-house"
    write_plan(
        project / "plans",
        "main",
        width=800,
        height=600,
        rooms=[{"room": "kitchen", "x": 900, "y": 300}],
    )
    report = validate_project(project)
    assert 3 in rules(report)


def test_bounds_come_from_the_image_not_a_declared_size(tmp_path):
    """A stale width beside the file must not widen the check.

    plan correct rewrites the raster, so any size recorded next to it can drift.
    A point outside the real image is an error even when a field claims the
    image is bigger.
    """
    project = tmp_path / "our-house"
    write_plan(
        project / "plans",
        "main",
        width=800,
        height=600,
        raster={"w": 4000, "h": 4000},
        rooms=[{"room": "kitchen", "x": 3000, "y": 3000}],
    )
    report = validate_project(project)
    assert 3 in rules(report)


def test_duplicate_and_malformed_slugs_are_errors(tmp_path):
    """Rule 4."""
    project = tmp_path / "our-house"
    write_plan(
        project / "plans",
        "main",
        rooms=[
            {"room": "kitchen", "x": 10, "y": 10},
            {"room": "kitchen", "x": 20, "y": 20},
            {"room": "Not A Slug", "x": 30, "y": 30},
        ],
    )
    report = validate_project(project)
    assert rules(report) == [4, 4]
    assert report.placements == 1


def test_half_calibrated_plan_is_an_error(tmp_path):
    """Rule 5: a scale with no origin raises in house_to_plan far from here."""
    project = tmp_path / "our-house"
    write_plan(project / "plans", "main", metres_per_pixel=0.01)
    report = validate_project(project)
    assert 5 in rules(report)
    assert report.calibrated == []


def test_fully_calibrated_plan_is_reported_as_calibrated(tmp_path):
    project = tmp_path / "our-house"
    write_plan(project / "plans", "main", metres_per_pixel=0.01, origin_px=[100.0, 200.0])
    report = validate_project(project)
    assert report.ok, report.render()
    assert report.calibrated == ["main"]


def test_negative_scale_is_an_error(tmp_path):
    project = tmp_path / "our-house"
    write_plan(project / "plans", "main", metres_per_pixel=-0.01, origin_px=[10.0, 10.0])
    report = validate_project(project)
    assert 5 in rules(report)


def test_missing_image_is_an_error(tmp_path):
    """Rule 2."""
    project = tmp_path / "our-house"
    path = write_plan(project / "plans", "main")
    (project / "plans" / "main.png").unlink()
    report = validate_project(project)
    assert 2 in rules(report)
    assert path.exists()


def test_level_must_match_the_filename(tmp_path):
    """Rule 1. A plan renamed on disk no longer describes the level it claims."""
    project = tmp_path / "our-house"
    path = write_plan(project / "plans", "main")
    data = json.loads(path.read_text(encoding="utf-8"))
    data["level"] = "basement"
    path.write_text(json.dumps(data), encoding="utf-8")
    report = validate_project(project)
    assert 1 in rules(report)


def test_unparseable_plan_is_an_error(tmp_path):
    project = tmp_path / "our-house"
    plans = project / "plans"
    plans.mkdir(parents=True)
    (plans / "main.json").write_text("{not json", encoding="utf-8")
    report = validate_project(project)
    assert 1 in rules(report)


def test_uncaptured_and_unplaced_rooms_are_warnings_both_ways(tmp_path):
    """Rule 6. Both directions are normal mid-capture, so neither fails."""
    project = tmp_path / "our-house"
    session_dir(project, "main", "kitchen")
    write_plan(project / "plans", "main", rooms=[{"room": "garage", "x": 10, "y": 10}])
    report = validate_project(project)
    assert report.ok, report.render()
    assert rules(report, WARN) == [6, 6]
    messages = " ".join(f.message for f in report.findings)
    assert "main/garage" in messages and "main/kitchen" in messages


def test_a_plan_from_an_older_plan_add_is_valid(tmp_path):
    """Section 12: readers ignore unknown fields, and source/rooms are optional."""
    project = tmp_path / "our-house"
    write_plan(project / "plans", "main")
    report = validate_project(project)
    assert report.ok, report.render()
    assert report.placements == 0


def test_source_and_extra_fields_are_ignored(tmp_path):
    project = tmp_path / "our-house"
    write_plan(
        project / "plans",
        "main",
        source={"file": "main.source.pdf", "kind": "pdf", "page": 2},
        something_a_future_client_added=True,
    )
    report = validate_project(project)
    assert report.ok, report.render()


def test_missing_project_directory_is_an_error(tmp_path):
    report = validate_project(tmp_path / "nope")
    assert not report.ok


def test_sessions_are_counted_and_plans_dir_is_not_one(tmp_path):
    project = tmp_path / "our-house"
    session_dir(project, "main", "kitchen")
    session_dir(project, "main", "hall")
    write_plan(project / "plans", "main")
    report = validate_project(project)
    assert report.sessions == 2
