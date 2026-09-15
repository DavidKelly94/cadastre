"""Loading is tolerant by design: validate is what reports a broken session, so
load has to get far enough for validate to run and say what is wrong."""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pytest

from vividhome.session import Session, SessionError, read_jsonl


def test_loads_the_manifest(session_dir: Path):
    session = Session.load(session_dir)
    assert session.format_version == 3
    assert session.session_id == "20261103-141502_main_kitchen_k3x7qa"
    assert session.status == "complete"
    assert session.phases == ["electrical", "plumbing"]
    assert session.expected_markers == ["VH-012"]
    assert session.duration_s == 2.0


def test_reads_frames_with_matrices_already_converted(session_dir: Path):
    frames = list(Session.load(session_dir).frames())
    assert [f.i for f in frames] == [0, 1, 2]
    assert frames[0].T_wc.shape == (4, 4)
    assert frames[0].K.shape == (3, 3)
    # Translation is at column-major indices 12, 13, 14.
    np.testing.assert_allclose(frames[1].position, [0.25, 0.0, 0.0])
    assert frames[0].K[0, 0] == pytest.approx(48.4)


def test_reads_the_other_record_types(session_dir: Path):
    session = Session.load(session_dir)

    stills = list(session.stills())
    assert len(stills) == 1
    assert stills[0].s == 0
    assert stills[0].w == 128

    markers = list(session.markers())
    assert [m.marker_id for m in markers] == ["VH-012"]
    assert markers[0].tracked is True
    np.testing.assert_allclose(markers[0].T_wa[:3, 3], [1.0, 1.2, -2.0])

    landmarks = list(session.landmarks())
    assert landmarks[0].kind == "corner"
    np.testing.assert_allclose(landmarks[0].p_w, [2.31, -1.42, -0.87])


def test_trajectory_is_one_row_per_keyframe(session_dir: Path):
    trajectory = Session.load(session_dir).trajectory()
    assert trajectory.shape == (3, 3)
    np.testing.assert_allclose(trajectory[:, 0], [0.0, 0.25, 0.5])


def test_depth_intrinsics_scale_with_the_depth_resolution(session_dir: Path):
    frame = next(Session.load(session_dir).frames())
    sx = frame.dw / frame.w
    sy = frame.dh / frame.h
    assert frame.depth_K[0, 0] == pytest.approx(frame.K[0, 0] * sx)
    assert frame.depth_K[0, 2] == pytest.approx(frame.K[0, 2] * sx)
    assert frame.depth_K[1, 1] == pytest.approx(frame.K[1, 1] * sy)
    assert frame.depth_K[1, 2] == pytest.approx(frame.K[1, 2] * sy)
    # The colour intrinsics must not be mutated in the process.
    assert frame.K[0, 0] == pytest.approx(48.4)


def test_paths_resolve_against_the_session_root(session_dir: Path):
    session = Session.load(session_dir)
    frame = next(session.frames())
    assert session.resolve(frame.rgb) == session_dir / "rgb" / "000000.jpg"
    assert session.resolve(frame.depth).exists()
    assert session.derived == session_dir / "derived"


def test_derived_is_not_created_until_asked(session_dir: Path):
    session = Session.load(session_dir)
    assert not session.derived.exists()
    assert session.ensure_derived().is_dir()


def test_unknown_fields_are_preserved_in_raw(session_dir: Path):
    # Section 12: additive fields keep format_version 1 and must survive a read.
    path = session_dir / "landmarks.jsonl"
    row = json.loads(path.read_text(encoding="utf-8").strip())
    row["confidence"] = 0.9
    path.write_text(json.dumps(row) + "\n", encoding="utf-8")

    landmark = next(Session.load(session_dir).landmarks())
    assert landmark.label == "corner-ne"
    assert landmark.raw["confidence"] == 0.9


def test_missing_optional_files_read_as_empty(session_dir: Path):
    (session_dir / "markers.jsonl").unlink()
    assert list(Session.load(session_dir).markers()) == []


def test_blank_lines_are_skipped(session_dir: Path):
    path = session_dir / "landmarks.jsonl"
    path.write_text("\n" + path.read_text(encoding="utf-8") + "\n\n", encoding="utf-8")
    assert len(list(Session.load(session_dir).landmarks())) == 1


def test_malformed_json_names_the_file_and_line(session_dir: Path):
    path = session_dir / "frames.jsonl"
    lines = path.read_text(encoding="utf-8").splitlines()
    lines[1] = "{not json"
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")

    with pytest.raises(SessionError, match=r"frames\.jsonl:2"):
        list(Session.load(session_dir).frames())


def test_missing_required_field_names_the_file_and_line(session_dir: Path):
    path = session_dir / "frames.jsonl"
    rows = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()]
    del rows[2]["T_wc"]
    path.write_text("".join(json.dumps(r) + "\n" for r in rows), encoding="utf-8")

    with pytest.raises(SessionError, match=r"frames\.jsonl:3.*T_wc"):
        list(Session.load(session_dir).frames())


def test_landmark_with_a_bad_position_is_rejected(session_dir: Path):
    path = session_dir / "landmarks.jsonl"
    row = json.loads(path.read_text(encoding="utf-8").strip())
    row["p_w"] = [1.0, 2.0]
    path.write_text(json.dumps(row) + "\n", encoding="utf-8")

    with pytest.raises(SessionError, match="p_w must be 3 numbers"):
        list(Session.load(session_dir).landmarks())


def test_load_rejects_a_directory_that_is_not_a_session(tmp_path: Path):
    with pytest.raises(SessionError, match="not a directory"):
        Session.load(tmp_path / "nope")

    empty = tmp_path / "empty"
    empty.mkdir()
    with pytest.raises(SessionError, match="no manifest.json"):
        Session.load(empty)


def test_load_reports_a_broken_manifest(session_dir: Path):
    (session_dir / "manifest.json").write_text("{oops", encoding="utf-8")
    with pytest.raises(SessionError, match="manifest.json: invalid JSON"):
        Session.load(session_dir)


def test_a_manifest_missing_fields_still_loads(tmp_path: Path):
    # validate is what reports this, so load must not raise first.
    root = tmp_path / "sparse"
    root.mkdir()
    (root / "manifest.json").write_text("{}", encoding="utf-8")
    session = Session.load(root)
    assert session.format_version is None
    assert session.status == "unknown"
    assert session.duration_s is None
    assert session.session_id == "sparse"


def test_read_jsonl_rejects_a_non_object_line(tmp_path: Path):
    path = tmp_path / "rows.jsonl"
    path.write_text("[1, 2, 3]\n", encoding="utf-8")
    with pytest.raises(SessionError, match="expected an object"):
        list(read_jsonl(path))
