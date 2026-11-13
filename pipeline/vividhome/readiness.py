"""Whether a capture holds enough to build a 3D model from (ADR-0035).

The pipeline's side of ``ModelReadiness.swift``: the same measures from the
same camera poses, so the PC can check what the phone claimed in
``field_check.model`` and compare the two over many captures. The contract job
runs both on one session.

A stretch of wall counts as seen twice when the places it was photographed
from span a useful angle and one of them was close. The floor and the ceiling
count as seen when enough keyframes were tilted at them from more than one
spot. Every threshold is a first guess.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Any

from .coverage import CELL_M, DEFAULT_RANGE_M, _cameras, footprint
from .session import Session, SessionError

VIEW_SPREAD_DEG = 20.0
NEAR_M = 2.5
PITCH_DEG = 25.0
PITCHED_KEYFRAMES = 10
PITCHED_SQUARES = 3
SQUARE_M = 0.5
HEIGHT_STEP_M = 0.4
HEIGHT_SHARE = 0.15
WALLS_TWICE_ENOUGH = 0.70
MINIMUM_GAP_M = 0.3
GAPS_KEPT = 3


@dataclass
class WallViews:
    start: str
    end: str
    length: float
    low: list[float]
    high: list[float]
    nearest: list[float]
    start_x: float
    start_z: float
    direction_x: float
    direction_z: float

    @property
    def cells(self) -> int:
        return len(self.low)

    @property
    def seen_twice(self) -> list[bool]:
        spread = math.radians(VIEW_SPREAD_DEG)
        return [
            self.low[cell] <= self.high[cell]
            and self.high[cell] - self.low[cell] >= spread
            and self.nearest[cell] <= NEAR_M
            for cell in range(self.cells)
        ]

    @property
    def gaps(self) -> list[tuple[float, float]]:
        twice = self.seen_twice
        out: list[tuple[float, float]] = []
        index = 0
        while index < len(twice):
            if twice[index]:
                index += 1
                continue
            begin = index
            while index < len(twice) and not twice[index]:
                index += 1
            start = begin * CELL_M
            out.append((start, min(index * CELL_M, self.length) - start))
        return out


def walls(outline: list[tuple[str, float, float]]) -> list[WallViews]:
    """The walls of an outline of ``(label, x, z)`` corners, nothing seen yet."""
    out: list[WallViews] = []
    if len(outline) < 2:
        return out
    for index, (label, ax, az) in enumerate(outline):
        end_label, bx, bz = outline[(index + 1) % len(outline)]
        dx, dz = bx - ax, bz - az
        length = math.sqrt(dx * dx + dz * dz)
        if length <= 0:
            continue
        cells = max(1, math.ceil(length / CELL_M))
        out.append(
            WallViews(
                start=label,
                end=end_label,
                length=length,
                low=[1.0] * cells,
                high=[-1.0] * cells,
                nearest=[math.inf] * cells,
                start_x=ax,
                start_z=az,
                direction_x=dx / length,
                direction_z=dz / length,
            )
        )
    return out


def _visible(
    ax: float, az: float, bx: float, bz: float, segments: list[tuple[float, ...]], skip: int
) -> bool:
    def cross(ux: float, uz: float, vx: float, vz: float) -> float:
        return ux * vz - uz * vx

    for index, (cx, cz, dx, dz) in enumerate(segments):
        if index == skip:
            continue
        d1 = cross(dx - cx, dz - cz, ax - cx, az - cz)
        d2 = cross(dx - cx, dz - cz, bx - cx, bz - cz)
        d3 = cross(bx - ax, bz - az, cx - ax, cz - az)
        d4 = cross(bx - ax, bz - az, dx - ax, dz - az)
        if d1 * d2 < 0 and d3 * d4 < 0:
            return False
    return True


def add(
    camera: tuple[float, float, float, float, float],
    into: list[WallViews],
    range_m: float = DEFAULT_RANGE_M,
) -> None:
    """Add what one camera ``(x, z, forward_x, forward_z, spread)`` photographs."""
    x, z, forward_x, forward_z, spread = camera
    cos_limit = math.cos(spread)
    segments = [
        (
            wall.start_x,
            wall.start_z,
            wall.start_x + wall.direction_x * wall.length,
            wall.start_z + wall.direction_z * wall.length,
        )
        for wall in into
    ]
    for index, wall in enumerate(into):
        for cell in range(wall.cells):
            along = min((cell + 0.5) * CELL_M, wall.length)
            cx = wall.start_x + along * wall.direction_x
            cz = wall.start_z + along * wall.direction_z
            vx, vz = cx - x, cz - z
            distance = math.sqrt(vx * vx + vz * vz)
            if distance <= 0 or distance > range_m:
                continue
            if (vx * forward_x + vz * forward_z) / distance < cos_limit:
                continue
            if not _visible(x, z, cx, cz, segments, index):
                continue
            angle = math.atan2(
                wall.direction_x * -vz - wall.direction_z * -vx,
                wall.direction_x * -vx + wall.direction_z * -vz,
            )
            if wall.low[cell] > wall.high[cell]:
                wall.low[cell] = wall.high[cell] = angle
            else:
                wall.low[cell] = min(wall.low[cell], angle)
                wall.high[cell] = max(wall.high[cell], angle)
            wall.nearest[cell] = min(wall.nearest[cell], distance)


def _nearest(value: float) -> int:
    return math.floor(value + 0.5)


def report(
    views: list[tuple[float, float, float, float]], wall_views: list[WallViews] | None
) -> dict[str, Any]:
    """``field_check.model`` from keyframe views ``(x, y, z, forward_y)`` and
    the walls, or None for the walls when the capture is not placed."""
    down = math.sin(math.radians(PITCH_DEG))

    def seen(test) -> bool:
        count = 0
        squares: set[tuple[int, int]] = set()
        for x, _, z, forward_y in views:
            if not test(forward_y):
                continue
            count += 1
            squares.add((math.floor(x / SQUARE_M), math.floor(z / SQUARE_M)))
        return count >= PITCHED_KEYFRAMES and len(squares) >= PITCHED_SQUARES

    floor = seen(lambda forward_y: forward_y <= -down)
    ceiling = seen(lambda forward_y: forward_y >= down)

    heights = False
    if views:
        ordered = sorted(view[1] for view in views)
        middle = len(ordered) // 2
        median = (
            ordered[middle] if len(ordered) % 2 else (ordered[middle - 1] + ordered[middle]) / 2
        )
        apart = sum(1 for view in views if abs(view[1] - median) >= HEIGHT_STEP_M)
        heights = apart >= HEIGHT_SHARE * len(views)

    walls_twice: float | None = None
    gaps: list[dict[str, Any]] = []
    if wall_views:
        cells = sum(wall.cells for wall in wall_views)
        twice = sum(sum(wall.seen_twice) for wall in wall_views)
        walls_twice = 0.0 if cells == 0 else _nearest(twice / cells * 100) / 100
        runs = []
        for order, wall in enumerate(wall_views):
            for start, length in wall.gaps:
                if length < MINIMUM_GAP_M:
                    continue
                runs.append(
                    (
                        order,
                        {
                            "wall": f"{wall.start}->{wall.end}",
                            "from_m": _nearest(start * 10) / 10,
                            "length_m": _nearest(length * 10) / 10,
                        },
                    )
                )
        runs.sort(key=lambda run: (-run[1]["length_m"], run[0], run[1]["from_m"]))
        gaps = [gap for _, gap in runs[:GAPS_KEPT]]
    return {
        "walls_twice": walls_twice,
        "floor": floor,
        "ceiling": ceiling,
        "heights": heights,
        "gaps": gaps,
    }


def enough(model: dict[str, Any]) -> bool:
    return (
        float(model.get("walls_twice") or 0.0) >= WALLS_TWICE_ENOUGH
        and bool(model.get("floor"))
        and bool(model.get("ceiling"))
    )


def session_views(session: Session) -> list[tuple[float, float, float, float]]:
    views = []
    for frame in session.frames():
        forward = -frame.T_wc[:3, 2]
        length = math.sqrt(float(forward @ forward))
        views.append(
            (
                float(frame.T_wc[0, 3]),
                float(frame.T_wc[1, 3]),
                float(frame.T_wc[2, 3]),
                float(forward[1]) / length if length > 0 else 0.0,
            )
        )
    return views


def session_report(session: Session, *, range_m: float = DEFAULT_RANGE_M) -> dict[str, Any]:
    """Measure a session against its own tapped corners, in the session frame.

    The corners in tap order are the footprint ``coverage.py`` uses, so the
    walls here are the walls there. A session with fewer than three tapped
    corners has no walls to measure and reports the rest.
    """
    wall_views: list[WallViews] | None
    try:
        corners = footprint(session)
    except SessionError:
        wall_views = None
    else:
        wall_views = walls(
            [(corner.label, float(corner.p_w[0]), float(corner.p_w[2])) for corner in corners]
        )
        cameras, _ = _cameras(session)
        for position, forward, spread in cameras:
            add(
                (
                    float(position[0]),
                    float(position[1]),
                    float(forward[0]),
                    float(forward[1]),
                    float(spread),
                ),
                wall_views,
                range_m,
            )
    return report(session_views(session), wall_views)
