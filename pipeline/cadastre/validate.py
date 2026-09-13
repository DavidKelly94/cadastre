"""Session validation: the rules in ``docs/session-format.md`` §11, in order.

The point of this command is to tell the owner, before they leave the building,
whether a capture is usable. So the report distinguishes three things:

- **ERROR** — the session cannot be processed. Exit code 1.
- **WARN** — it can be processed but something is worth knowing.
- **OK** — a rule was checked and passed.

Rules 6 and 7 are warnings by specification, not errors: a session with patchy
depth or stale manifest statistics is still worth aligning.
"""

from __future__ import annotations

import json
import math
from collections import Counter
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

import numpy as np

from .session import Frame, Session, SessionError

__all__ = ["Finding", "Report", "validate_session"]

#: Rule 4: how far the rotation block may drift from orthonormal.
ROTATION_TOLERANCE = 1e-3

#: Rule 6: a keyframe is "good" when this fraction of its depth pixels are valid,
#: and the session passes when this fraction of keyframes are good.
DEPTH_VALID_FRACTION = 0.80
GOOD_KEYFRAME_FRACTION = 0.80

ERROR = "ERROR"
WARN = "WARN"
OK = "OK"


@dataclass(frozen=True)
class Finding:
    level: str
    rule: int
    message: str

    def __str__(self) -> str:
        return f"{self.level:<5} rule {self.rule}: {self.message}"


@dataclass
class Report:
    session_id: str
    findings: list[Finding] = field(default_factory=list)
    keyframes: int = 0
    stills: int = 0
    marker_observations: int = 0
    landmarks: int = 0
    markers_by_id: dict[str, int] = field(default_factory=dict)
    landmarks_by_label: dict[str, int] = field(default_factory=dict)
    tracking_limited_s: float = 0.0
    depth_valid_fraction: float | None = None
    bytes_on_disk: int = 0

    def add(self, level: str, rule: int, message: str) -> None:
        self.findings.append(Finding(level, rule, message))

    @property
    def errors(self) -> list[Finding]:
        return [f for f in self.findings if f.level == ERROR]

    @property
    def warnings(self) -> list[Finding]:
        return [f for f in self.findings if f.level == WARN]

    @property
    def ok(self) -> bool:
        return not self.errors

    @property
    def exit_code(self) -> int:
        return 1 if self.errors else 0

    def to_dict(self) -> dict[str, Any]:
        data = asdict(self)
        data["findings"] = [asdict(f) for f in self.findings]
        data["ok"] = self.ok
        return data

    def render(self) -> str:
        """The human-readable summary the command prints."""
        lines = [
            f"session {self.session_id}",
            f"  keyframes            {self.keyframes}",
            f"  stills               {self.stills}",
            f"  marker observations  {self.marker_observations}",
            f"  landmarks            {self.landmarks}",
            f"  tracking limited     {self.tracking_limited_s:.1f} s",
        ]
        if self.depth_valid_fraction is not None:
            lines.append(f"  depth valid          {self.depth_valid_fraction * 100:.1f} %")
        lines.append(f"  bytes                {self.bytes_on_disk}")
        if self.markers_by_id:
            lines.append("  markers:")
            lines += [
                f"    {marker_id}  {count} observations"
                for marker_id, count in sorted(self.markers_by_id.items())
            ]
        if self.landmarks_by_label:
            lines.append("  landmarks:")
            lines += [
                f"    {label}  {count}" for label, count in sorted(self.landmarks_by_label.items())
            ]
        lines.append("")
        lines += [str(finding) for finding in self.findings]
        lines.append("")
        lines.append("OK" if self.ok else f"FAILED with {len(self.errors)} error(s)")
        return "\n".join(lines)


def _is_marker_id(value: str) -> bool:
    """Rule 8: marker ids match ``CD-\\d{3}``."""
    return len(value) == 6 and value.startswith("CD-") and value[3:].isdigit()


def _rotation_is_orthonormal(matrix: np.ndarray) -> bool:
    rotation = matrix[:3, :3]
    if not np.all(np.isfinite(rotation)):
        return False
    product = rotation @ rotation.T
    if np.max(np.abs(product - np.eye(3))) >= ROTATION_TOLERANCE:
        return False
    return float(np.linalg.det(rotation)) > 0


def _check_frame_geometry(report: Report, frame: Frame) -> None:
    if not _rotation_is_orthonormal(frame.T_wc):
        report.add(ERROR, 4, f"frame {frame.i}: T_wc rotation is not orthonormal")

    fx, fy = frame.K[0, 0], frame.K[1, 1]
    cx, cy = frame.K[0, 2], frame.K[1, 2]
    if not (fx > 0 and fy > 0):
        report.add(ERROR, 5, f"frame {frame.i}: fx and fy must be positive")
    elif not (0 <= cx <= frame.w and 0 <= cy <= frame.h):
        report.add(
            ERROR, 5, f"frame {frame.i}: principal point ({cx:.1f}, {cy:.1f}) outside the image"
        )


def _check_frame_files(
    report: Report, session: Session, frame: Frame, *, check_images: bool
) -> int:
    """Rule 3 for one keyframe. Returns the bytes accounted for."""
    total = 0
    expected = {
        frame.depth: frame.dw * frame.dh * 4,
        frame.conf: frame.dw * frame.dh,
    }
    for relative, size in expected.items():
        path = session.resolve(relative)
        if not path.exists():
            report.add(ERROR, 3, f"frame {frame.i}: missing {relative}")
            continue
        actual = path.stat().st_size
        total += actual
        if actual != size:
            report.add(ERROR, 3, f"frame {frame.i}: {relative} is {actual} bytes, expected {size}")

    rgb_path = session.resolve(frame.rgb)
    if not rgb_path.exists():
        report.add(ERROR, 3, f"frame {frame.i}: missing {frame.rgb}")
        return total
    total += rgb_path.stat().st_size
    if check_images:
        _check_image(report, rgb_path, frame.rgb, frame.w, frame.h, f"frame {frame.i}")
    return total


def _check_image(
    report: Report, path: Path, relative: str, width: int, height: int, where: str
) -> None:
    try:
        from PIL import Image
    except ImportError:  # pragma: no cover - Pillow is a declared dependency
        return
    try:
        with Image.open(path) as image:
            size = image.size
            image.verify()
    except Exception as error:  # noqa: BLE001 - any decode failure is the same finding
        report.add(ERROR, 3, f"{where}: {relative} does not decode ({error})")
        return
    if size != (width, height):
        report.add(
            ERROR,
            3,
            f"{where}: {relative} is {size[0]}x{size[1]}, manifest says {width}x{height}",
        )


def _depth_valid_fraction(path: Path, dw: int, dh: int) -> float | None:
    """Fraction of depth pixels that are usable: finite and strictly positive."""
    try:
        values = np.fromfile(path, dtype="<f4")
    except OSError:
        return None
    if values.size != dw * dh:
        return None
    finite = np.isfinite(values)
    return float(np.count_nonzero(finite & (values > 0)) / values.size)


def validate_session(
    session: Session, *, check_images: bool = True, check_depth: bool = True
) -> Report:
    """Run every rule in §11 and return the report."""
    report = Report(session_id=session.session_id)

    # Rule 1: the manifest.
    if session.format_version is None:
        report.add(ERROR, 1, "manifest has no format_version")
    elif session.format_version != 1:
        report.add(ERROR, 1, f"unsupported format_version {session.format_version}")
    else:
        report.add(OK, 1, "manifest reads as format_version 1")

    status = session.status
    if status == "incomplete":
        report.add(ERROR, 1, "session status is incomplete: recording did not finish")
    elif status == "repaired":
        report.add(WARN, 1, "session was repaired after a crash; statistics were recomputed")
    elif status != "complete":
        report.add(ERROR, 1, f"unknown session status {status!r}")

    duration = session.duration_s
    upper_time = (duration + 1.0) if duration is not None else None

    # Rules 2 to 6 over the keyframes, in one pass.
    previous_i: int | None = None
    previous_t: float | None = None
    good_keyframes = 0
    measured_keyframes = 0
    valid_fractions: list[float] = []
    total_bytes = 0

    try:
        for frame in session.frames():
            report.keyframes += 1

            if previous_i is not None and frame.i <= previous_i:
                report.add(ERROR, 2, f"keyframe index {frame.i} does not increase")
            previous_i = frame.i

            if previous_t is not None and frame.t < previous_t:
                report.add(ERROR, 2, f"frame {frame.i}: t goes backwards")
            previous_t = frame.t
            if frame.t < 0:
                report.add(ERROR, 2, f"frame {frame.i}: t is negative")
            elif upper_time is not None and frame.t > upper_time:
                report.add(ERROR, 2, f"frame {frame.i}: t={frame.t} is beyond duration_s + 1")

            if frame.tracking != "normal":
                report.tracking_limited_s += 0.0  # accumulated below from timestamps

            _check_frame_geometry(report, frame)
            total_bytes += _check_frame_files(report, session, frame, check_images=check_images)

            if check_depth:
                fraction = _depth_valid_fraction(session.resolve(frame.depth), frame.dw, frame.dh)
                if fraction is not None:
                    measured_keyframes += 1
                    valid_fractions.append(fraction)
                    if fraction >= DEPTH_VALID_FRACTION:
                        good_keyframes += 1
    except SessionError as error:
        report.add(ERROR, 2, str(error))
        return report

    report.tracking_limited_s = _tracking_limited_seconds(session)

    if report.keyframes == 0:
        report.add(ERROR, 2, "no keyframes")
    else:
        report.add(OK, 2, f"{report.keyframes} keyframes in order")

    if measured_keyframes:
        report.depth_valid_fraction = float(np.mean(valid_fractions))
        share = good_keyframes / measured_keyframes
        if share < GOOD_KEYFRAME_FRACTION:
            report.add(
                WARN,
                6,
                f"only {share * 100:.0f}% of keyframes have "
                f"{DEPTH_VALID_FRACTION * 100:.0f}% valid depth",
            )
        else:
            report.add(OK, 6, f"{share * 100:.0f}% of keyframes have good depth")

    # Stills.
    try:
        for still in session.stills():
            report.stills += 1
            path = session.resolve(still.path)
            if not path.exists():
                report.add(ERROR, 3, f"still {still.s}: missing {still.path}")
                continue
            total_bytes += path.stat().st_size
            if check_images:
                _check_image(report, path, still.path, still.w, still.h, f"still {still.s}")
    except SessionError as error:
        report.add(ERROR, 2, str(error))

    # Rule 8: markers and landmarks.
    marker_counts: Counter[str] = Counter()
    try:
        for observation in session.markers():
            report.marker_observations += 1
            marker_counts[observation.marker_id] += 1
            if not _is_marker_id(observation.marker_id):
                report.add(ERROR, 8, f"marker id {observation.marker_id!r} does not match CD-NNN")
    except SessionError as error:
        report.add(ERROR, 2, str(error))
    report.markers_by_id = dict(marker_counts)

    label_counts: Counter[str] = Counter()
    try:
        for landmark in session.landmarks():
            report.landmarks += 1
            label_counts[landmark.label] += 1
            if not all(math.isfinite(value) for value in landmark.p_w):
                report.add(ERROR, 8, f"landmark {landmark.label!r} has non-finite coordinates")
    except SessionError as error:
        report.add(ERROR, 2, str(error))
    report.landmarks_by_label = dict(label_counts)

    if not report.errors:
        report.add(OK, 8, "marker ids and landmark coordinates are well formed")

    # Rule 7: manifest statistics against what was counted.
    report.bytes_on_disk = total_bytes
    _check_stats(report, session)

    expected_markers = set(session.expected_markers)
    seen = set(marker_counts)
    missing = sorted(expected_markers - seen)
    if missing:
        report.add(WARN, 7, f"expected markers not seen: {', '.join(missing)}")

    return report


def _tracking_limited_seconds(session: Session) -> float:
    """Seconds spent in a tracking state other than normal.

    Measured between consecutive keyframes, so it is an approximation bounded by
    the keyframe rate rather than a true integral over ARKit frames.
    """
    total = 0.0
    previous_t: float | None = None
    previous_limited = False
    for frame in session.frames():
        if previous_t is not None and previous_limited:
            total += frame.t - previous_t
        previous_t = frame.t
        previous_limited = frame.tracking != "normal"
    return total


def _check_stats(report: Report, session: Session) -> None:
    stats = session.manifest.get("stats")
    if not isinstance(stats, dict):
        report.add(WARN, 7, "manifest has no stats block")
        return
    counted = {
        "keyframes": report.keyframes,
        "stills": report.stills,
        "marker_observations": report.marker_observations,
        "landmarks": report.landmarks,
    }
    mismatched = [
        f"{name}: manifest {stats.get(name)}, counted {value}"
        for name, value in counted.items()
        if isinstance(stats.get(name), int) and stats.get(name) != value
    ]
    if mismatched:
        report.add(
            WARN, 7, "manifest statistics disagree with the files (" + "; ".join(mismatched) + ")"
        )
    else:
        report.add(OK, 7, "manifest statistics match the files")


def write_report(session: Session, report: Report) -> Path:
    """Write ``derived/validate.json`` and return its path."""
    target = session.ensure_derived() / "validate.json"
    target.write_text(json.dumps(report.to_dict(), indent=2), encoding="utf-8")
    return target
