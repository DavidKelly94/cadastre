"""Project-level validation: ``docs/session-format.md`` section 13.

Everything in :mod:`vividhome.validate` checks one session. This checks what sits
beside the sessions — currently the floor plans a phone or ``plan add`` put in
``plans/`` — and the one relationship between the two: which rooms have been
captured and which have been placed on a drawing.

The rules are section 13's, numbered as it numbers them, so a finding can be
read against the contract rather than against this file.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from .plan import PlanCalibration
from .validate import ERROR, WARN, Finding

#: A level or room slug, as section 1 defines it.
SLUG = re.compile(r"^[a-z0-9-]{1,24}$")


@dataclass
class ProjectReport:
    """The project-level counterpart to :class:`vividhome.validate.Report`."""

    project: str
    findings: list[Finding] = field(default_factory=list)
    levels: list[str] = field(default_factory=list)
    calibrated: list[str] = field(default_factory=list)
    placements: int = 0
    sessions: int = 0

    def add(self, level: str, rule: int, message: str) -> None:
        self.findings.append(Finding(level, rule, message))

    @property
    def errors(self) -> list[Finding]:
        return [f for f in self.findings if f.level == ERROR]

    @property
    def ok(self) -> bool:
        return not self.errors

    @property
    def exit_code(self) -> int:
        return 1 if self.errors else 0

    def to_dict(self) -> dict[str, Any]:
        return {
            "project": self.project,
            "levels": self.levels,
            "calibrated": self.calibrated,
            "placements": self.placements,
            "sessions": self.sessions,
            "findings": [
                {"level": f.level, "rule": f.rule, "message": f.message} for f in self.findings
            ],
            "ok": self.ok,
        }

    def render(self) -> str:
        lines = [
            f"project {self.project}",
            f"  levels with a plan   {len(self.levels)}"
            + (f"  ({', '.join(self.levels)})" if self.levels else ""),
            f"  calibrated           {len(self.calibrated)}"
            + (f"  ({', '.join(self.calibrated)})" if self.calibrated else ""),
            f"  room placements      {self.placements}",
            f"  sessions             {self.sessions}",
            "",
        ]
        lines += [str(finding) for finding in self.findings]
        lines.append("")
        lines.append("OK" if self.ok else f"FAILED with {len(self.errors)} error(s)")
        return "\n".join(lines)


def _image_size(path: Path) -> tuple[int, int] | None:
    """Pixel size of the raster, or None when it will not decode.

    Read from the image rather than from a field beside it. A recorded width can
    drift from the file it describes — ``plan correct`` rewrites the raster — and
    then every bounds check silently uses the wrong extent.
    """
    try:
        import cv2
        import numpy as np

        data = np.fromfile(str(path), dtype=np.uint8)
        image = cv2.imdecode(data, cv2.IMREAD_UNCHANGED)
    except Exception:  # noqa: BLE001 - any decode failure is the same finding
        return None
    if image is None:
        return None
    return int(image.shape[1]), int(image.shape[0])


def _captured_rooms(project_dir: Path) -> tuple[set[tuple[str, str]], int]:
    """``(level, room)`` pairs that have at least one session, and the count.

    Parsed from directory names rather than by opening every manifest: section 1
    puts the level and room in the session id precisely so this is cheap, and a
    project mid-capture can hold hundreds of sessions.
    """
    pairs: set[tuple[str, str]] = set()
    count = 0
    for child in sorted(project_dir.iterdir()):
        if not child.is_dir() or child.name == "plans":
            continue
        parts = child.name.split("_")
        if len(parts) != 4:
            continue
        count += 1
        pairs.add((parts[1], parts[2]))
    return pairs, count


def validate_project(project_dir: str | Path) -> ProjectReport:
    """Check one project directory against section 13."""
    root = Path(project_dir)
    report = ProjectReport(project=root.name)

    if not root.is_dir():
        report.add(ERROR, 13, f"{root} is not a directory")
        return report

    captured, session_count = _captured_rooms(root)
    report.sessions = session_count

    plans = root / "plans"
    if not plans.is_dir():
        # Explicitly fine: section 13 says a project with no plans is valid, and
        # everything in sections 1 to 12 works without one.
        return report

    placed: set[tuple[str, str]] = set()

    for json_path in sorted(plans.glob("*.json")):
        level = json_path.stem
        try:
            raw = json.loads(json_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            report.add(ERROR, 1, f"{json_path.name}: does not parse ({error})")
            continue

        if raw.get("level") != level:
            report.add(
                ERROR, 1, f"{json_path.name}: level is {raw.get('level')!r}, expected {level!r}"
            )

        report.levels.append(level)

        try:
            calibration = PlanCalibration.from_dict(raw)
        except (KeyError, TypeError, ValueError) as error:
            report.add(ERROR, 1, f"{json_path.name}: unreadable calibration ({error})")
            continue

        # Rule 5: half-calibrated is an error, not a warning. house_to_plan
        # raises on it far from here, and a plan that claims a scale with no
        # origin is more dangerous than one that claims nothing.
        mpp, origin = calibration.metres_per_pixel, calibration.origin_px
        if (mpp is None) != (origin is None):
            report.add(
                ERROR,
                5,
                f"{json_path.name}: half-calibrated — "
                f"metres_per_pixel is {mpp!r} and origin_px is {origin!r}",
            )
        elif mpp is not None:
            if mpp <= 0:
                report.add(ERROR, 5, f"{json_path.name}: metres_per_pixel must be positive")
            else:
                report.calibrated.append(level)

        image_path = plans / calibration.image
        if not image_path.is_file():
            report.add(ERROR, 2, f"{json_path.name}: image {calibration.image} is missing")
            continue

        size = _image_size(image_path)
        if size is None:
            report.add(ERROR, 2, f"{json_path.name}: image {calibration.image} does not decode")
            continue
        width, height = size

        seen: set[str] = set()
        for index, entry in enumerate(raw.get("rooms") or []):
            if not isinstance(entry, dict):
                report.add(ERROR, 4, f"{json_path.name}: rooms[{index}] is not an object")
                continue
            room = str(entry.get("room", ""))
            if not SLUG.match(room):
                report.add(ERROR, 4, f"{json_path.name}: rooms[{index}] has a bad slug {room!r}")
                continue
            if room in seen:
                report.add(ERROR, 4, f"{json_path.name}: room {room!r} is placed twice")
                continue
            seen.add(room)

            try:
                x, y = float(entry["x"]), float(entry["y"])
            except (KeyError, TypeError, ValueError):
                report.add(ERROR, 3, f"{json_path.name}: room {room!r} has no usable x/y")
                continue
            if not (0 <= x <= width and 0 <= y <= height):
                report.add(
                    ERROR,
                    3,
                    f"{json_path.name}: room {room!r} at ({x:.0f}, {y:.0f}) "
                    f"is outside the {width}x{height} raster",
                )
                continue

            report.placements += 1
            placed.add((level, room))

    # Rule 6: both directions are warnings. A room placed before it is captured
    # is the normal order of work, and a room captured before anyone placed it
    # is what happens when the plan arrives late.
    for level, room in sorted(placed - captured):
        report.add(WARN, 6, f"{level}/{room} is placed on the plan but has no session")
    for level, room in sorted(captured - placed):
        report.add(WARN, 6, f"{level}/{room} has a session but is not placed on any plan")

    return report
