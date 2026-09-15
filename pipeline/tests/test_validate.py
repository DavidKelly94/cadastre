"""Every rule in session-format.md §11 gets a test that breaks it."""

from __future__ import annotations

import json
from pathlib import Path

import pytest
from helpers import DEPTH_H, DEPTH_W, pose_cm, write_depth, write_jpeg, write_jsonl

from vividhome.session import Session
from vividhome.validate import ERROR, WARN, validate_session, write_report


def report_for(path: Path):
    return validate_session(Session.load(path))


def rules(findings, level: str) -> set[int]:
    return {f.rule for f in findings if f.level == level}


def read_rows(path: Path) -> list[dict]:
    return [
        json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()
    ]


def patch_manifest(root: Path, **changes) -> None:
    path = root / "manifest.json"
    manifest = json.loads(path.read_text(encoding="utf-8"))
    manifest.update(changes)
    path.write_text(json.dumps(manifest), encoding="utf-8")


def test_a_good_session_passes(session_dir: Path):
    report = report_for(session_dir)
    assert report.ok, [str(f) for f in report.findings]
    assert report.exit_code == 0
    assert report.keyframes == 3
    assert report.stills == 1
    assert report.marker_observations == 1
    assert report.landmarks == 1
    assert report.markers_by_id == {"VH-012": 1}
    assert report.landmarks_by_label == {"corner-ne": 1}
    assert report.bytes_on_disk > 0


def test_rule_1_rejects_a_wrong_format_version(session_dir: Path):
    patch_manifest(session_dir, format_version=4)
    report = report_for(session_dir)
    assert not report.ok
    assert 1 in rules(report.findings, ERROR)


def test_rule_1_rejects_a_superseded_version(session_dir: Path):
    """Versions 1 and 2 are refused rather than migrated.

    ADR-0022 changed the session id and replaced the single ``phase`` with a
    list; ADR-0024 then changed the marker prefix. Both were safe without a
    migration because neither version was ever captured on a device, so
    refusing them outright is the honest behaviour: a file claiming version 1
    or 2 is a mistake, not old data.
    """
    for superseded in (1, 2):
        patch_manifest(session_dir, format_version=superseded)
        report = report_for(session_dir)
        assert not report.ok, f"version {superseded} should be refused"
        assert 1 in rules(report.findings, ERROR)


def test_rule_1_rejects_missing_or_unknown_phases(session_dir: Path):
    patch_manifest(session_dir, phases=[])
    assert not report_for(session_dir).ok

    patch_manifest(session_dir, phases=["framing", "painting"])
    report = report_for(session_dir)
    assert not report.ok
    assert any("painting" in f.message for f in report.errors)


def test_rule_1_accepts_several_phases_in_one_pass(session_dir: Path):
    """Concurrent trades are the normal case, not an anomaly (ADR-0022)."""
    patch_manifest(session_dir, phases=["electrical", "plumbing", "hvac"])
    report = report_for(session_dir)
    assert report.ok


def test_rule_1_rejects_an_incomplete_session(session_dir: Path):
    patch_manifest(session_dir, status="incomplete")
    report = report_for(session_dir)
    assert not report.ok
    assert any("did not finish" in f.message for f in report.errors)


def test_rule_1_warns_about_a_repaired_session(session_dir: Path):
    patch_manifest(session_dir, status="repaired")
    report = report_for(session_dir)
    assert report.ok, "repaired is a warning, not an error"
    assert 1 in rules(report.findings, WARN)


def test_rule_2_rejects_indices_that_do_not_increase(session_dir: Path):
    path = session_dir / "frames.jsonl"
    rows = read_rows(path)
    rows[2]["i"] = rows[1]["i"]
    write_jsonl(path, rows)
    report = report_for(session_dir)
    assert 2 in rules(report.findings, ERROR)


def test_rule_2_rejects_time_going_backwards(session_dir: Path):
    path = session_dir / "frames.jsonl"
    rows = read_rows(path)
    rows[2]["t"] = 0.0
    write_jsonl(path, rows)
    report = report_for(session_dir)
    assert any("backwards" in f.message for f in report.errors)


def test_rule_2_rejects_time_past_the_duration(session_dir: Path):
    path = session_dir / "frames.jsonl"
    rows = read_rows(path)
    rows[2]["t"] = 999.0
    write_jsonl(path, rows)
    report = report_for(session_dir)
    assert any("beyond duration_s" in f.message for f in report.errors)


def test_rule_2_rejects_a_session_with_no_keyframes(session_dir: Path):
    (session_dir / "frames.jsonl").write_text("", encoding="utf-8")
    report = report_for(session_dir)
    assert any("no keyframes" in f.message for f in report.errors)


def test_rule_3_rejects_a_missing_file(session_dir: Path):
    (session_dir / "depth" / "000001.f32").unlink()
    report = report_for(session_dir)
    assert any("missing depth/000001.f32" in f.message for f in report.errors)


def test_rule_3_rejects_a_wrong_sized_depth_file(session_dir: Path):
    (session_dir / "depth" / "000001.f32").write_bytes(b"\x00" * 8)
    report = report_for(session_dir)
    assert any("expected" in f.message and "bytes" in f.message for f in report.errors)


def test_rule_3_rejects_a_wrong_sized_confidence_file(session_dir: Path):
    (session_dir / "conf" / "000000.u8").write_bytes(b"\x02" * (DEPTH_W * DEPTH_H + 5))
    report = report_for(session_dir)
    assert 3 in rules(report.findings, ERROR)


def test_rule_3_rejects_an_undecodable_jpeg(session_dir: Path):
    (session_dir / "rgb" / "000000.jpg").write_bytes(b"not-a-real-jpeg")
    report = report_for(session_dir)
    assert any("does not decode" in f.message for f in report.errors)


def test_rule_3_rejects_a_jpeg_of_the_wrong_size(session_dir: Path):
    write_jpeg(session_dir / "rgb" / "000000.jpg", 32, 24)
    report = report_for(session_dir)
    assert any("manifest says" in f.message for f in report.errors)


def test_rule_4_rejects_a_non_orthonormal_rotation(session_dir: Path):
    path = session_dir / "frames.jsonl"
    rows = read_rows(path)
    scaled = list(pose_cm(0.0, 0.0, 0.0))
    scaled[0] = 2.0  # scales the x axis, so R Rt is no longer the identity
    rows[1]["T_wc"] = scaled
    write_jsonl(path, rows)
    report = report_for(session_dir)
    assert any("not orthonormal" in f.message for f in report.errors)


def test_rule_4_rejects_a_reflection(session_dir: Path):
    path = session_dir / "frames.jsonl"
    rows = read_rows(path)
    reflected = list(pose_cm(0.0, 0.0, 0.0))
    reflected[0] = -1.0  # orthonormal, but det is -1
    rows[1]["T_wc"] = reflected
    write_jsonl(path, rows)
    report = report_for(session_dir)
    assert 4 in rules(report.findings, ERROR)


def test_rule_5_rejects_a_non_positive_focal_length(session_dir: Path):
    path = session_dir / "frames.jsonl"
    rows = read_rows(path)
    rows[0]["K"] = [0, 0, 32.2, 0, 48.4, 24.1, 0, 0, 1]
    write_jsonl(path, rows)
    report = report_for(session_dir)
    assert any("fx and fy" in f.message for f in report.errors)


def test_rule_5_rejects_a_principal_point_outside_the_image(session_dir: Path):
    path = session_dir / "frames.jsonl"
    rows = read_rows(path)
    rows[0]["K"] = [48.4, 0, 9999.0, 0, 48.4, 24.1, 0, 0, 1]
    write_jsonl(path, rows)
    report = report_for(session_dir)
    assert any("outside the image" in f.message for f in report.errors)


def test_rule_6_warns_about_patchy_depth_without_failing(session_dir: Path):
    for i in range(3):
        write_depth(session_dir / "depth" / f"{i:06d}.f32", DEPTH_W, DEPTH_H, valid_fraction=0.25)
    report = report_for(session_dir)
    assert report.ok, "patchy depth is a warning, not an error"
    assert 6 in rules(report.findings, WARN)
    assert report.depth_valid_fraction == pytest.approx(0.25, abs=0.05)


def test_rule_7_warns_when_stats_disagree(session_dir: Path):
    manifest = json.loads((session_dir / "manifest.json").read_text(encoding="utf-8"))
    manifest["stats"]["keyframes"] = 99
    (session_dir / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
    report = report_for(session_dir)
    assert report.ok, "stale statistics are a warning, not an error"
    assert any("disagree" in f.message for f in report.warnings)


def test_rule_7_warns_about_expected_markers_that_were_not_seen(session_dir: Path):
    patch_manifest(session_dir, expected_markers=["VH-012", "VH-099"])
    report = report_for(session_dir)
    assert report.ok
    assert any("VH-099" in f.message for f in report.warnings)


def test_rule_8_rejects_a_bad_marker_id(session_dir: Path):
    path = session_dir / "markers.jsonl"
    rows = read_rows(path)
    rows[0]["marker_id"] = "IG-012"
    write_jsonl(path, rows)
    report = report_for(session_dir)
    assert any("VH-NNN" in f.message for f in report.errors)


def test_rule_8_rejects_non_finite_landmark_coordinates(session_dir: Path):
    # NaN is not valid JSON, so write it the way a real file would carry it.
    (session_dir / "landmarks.jsonl").write_text(
        '{"t":0.2,"i":0,"label":"corner-ne","kind":"corner","p_w":[1.0,NaN,3.0],'
        '"method":"raycast-estimatedPlane"}\n',
        encoding="utf-8",
    )
    report = report_for(session_dir)
    assert any("non-finite" in f.message for f in report.errors)


def test_a_malformed_line_is_reported_with_its_location(session_dir: Path):
    path = session_dir / "frames.jsonl"
    lines = path.read_text(encoding="utf-8").splitlines()
    lines[1] = "{broken"
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    report = report_for(session_dir)
    assert not report.ok
    assert any("frames.jsonl:2" in f.message for f in report.errors)


def test_report_renders_and_serialises(session_dir: Path):
    report = report_for(session_dir)
    text = report.render()
    assert "keyframes" in text
    assert "VH-012" in text
    assert text.strip().endswith("OK")

    data = report.to_dict()
    assert data["ok"] is True
    assert data["keyframes"] == 3
    assert isinstance(data["findings"], list)
    json.dumps(data)  # must be serialisable


def test_write_report_lands_under_derived(session_dir: Path):
    session = Session.load(session_dir)
    target = write_report(session, validate_session(session))
    assert target == session_dir / "derived" / "validate.json"
    assert json.loads(target.read_text(encoding="utf-8"))["ok"] is True


def test_image_and_depth_checks_can_be_skipped(session_dir: Path):
    (session_dir / "rgb" / "000000.jpg").write_bytes(b"not-a-real-jpeg")
    report = validate_session(Session.load(session_dir), check_images=False)
    assert report.ok, "skipping image checks must skip the decode failure too"
