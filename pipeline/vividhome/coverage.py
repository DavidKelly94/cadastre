"""Capture coverage per wall, against the footprint the owner tapped.

A percentage needs a denominator, and the only honest one a capture carries is
the room the owner declared: the corners they tapped, in the order they walked
them. The mesh cannot be the denominator — ARKit meshes only what the LiDAR saw,
so a wall nobody pointed the phone at is simply absent from it — and the plan is
not in the session. So this reads the footprint from the corner landmarks, walks
each wall between consecutive taps in 10 cm cells, and asks two questions of
each cell: did the LiDAR mesh it (wall-classified faces along that stretch), and
did a keyframe photograph it (inside a camera's horizontal spread, within range,
not through another wall). It reports gaps in metres from a named corner before
any percentage, because "1.9 m not photographed from corner NE" is something a
person can act on while standing in the room and "62%" is not.

It says nothing about walls the owner did not tap. That is the point, and it is
also the limit: a room tapped as four corners is measured as four walls whatever
its real shape.
"""

from __future__ import annotations

import json
import math
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np
from numpy.typing import NDArray

from .mesh import WALL, read_mesh
from .session import Landmark, Session, SessionError

__all__ = [
    "CoverageReport",
    "WallCoverage",
    "footprint",
    "wall_coverage",
    "write_coverage",
]

#: Resolution along a wall. Finer than any gap worth reporting.
CELL_M = 0.10

#: How far a keyframe can be from a wall and still count as having photographed
#: it. LiDAR depth is trusted to about 5 m; a wall further away than this is a
#: smear of pixels, not a record.
DEFAULT_RANGE_M = 4.0

#: How far off the wall line a mesh face may sit and still be that wall.
MESH_BAND_M = 0.25

#: A camera whose forward direction has less horizontal component than this is
#: pointed at the floor or the ceiling and is not counted as photographing walls.
MIN_HORIZONTAL_FORWARD = 0.3


@dataclass(frozen=True)
class WallCoverage:
    """One wall between two consecutive tapped corners."""

    start: str
    end: str
    length_m: float
    meshed: NDArray[np.bool_]
    photographed: NDArray[np.bool_]

    @property
    def cells(self) -> int:
        return int(self.meshed.size)

    @property
    def meshed_fraction(self) -> float:
        return float(self.meshed.mean()) if self.cells else 0.0

    @property
    def photographed_fraction(self) -> float:
        return float(self.photographed.mean()) if self.cells else 0.0

    def gaps(self, mask: NDArray[np.bool_]) -> list[tuple[float, float]]:
        """Runs of uncovered cells as ``(from_m, to_m)`` measured from ``start``."""
        out: list[tuple[float, float]] = []
        run_start: int | None = None
        for index, covered in enumerate(list(mask) + [True]):
            if not covered and run_start is None:
                run_start = index
            elif covered and run_start is not None:
                out.append(
                    (round(run_start * CELL_M, 2), round(min(index * CELL_M, self.length_m), 2))
                )
                run_start = None
        return out

    def to_dict(self) -> dict:
        return {
            "start": self.start,
            "end": self.end,
            "length_m": round(self.length_m, 3),
            "meshed_fraction": round(self.meshed_fraction, 3),
            "photographed_fraction": round(self.photographed_fraction, 3),
            "not_meshed_m": [list(gap) for gap in self.gaps(self.meshed)],
            "not_photographed_m": [list(gap) for gap in self.gaps(self.photographed)],
        }


@dataclass
class CoverageReport:
    session_id: str
    corners: list[str]
    range_m: float
    keyframes_used: int
    keyframes_total: int
    has_mesh: bool
    walls: list[WallCoverage] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "session_id": self.session_id,
            "source": "landmarks+mesh+frames",
            "denominator": "the corners the owner tapped, in tap order",
            "corners": self.corners,
            "range_m": self.range_m,
            "keyframes_used": self.keyframes_used,
            "keyframes_total": self.keyframes_total,
            "has_mesh": self.has_mesh,
            "walls": [wall.to_dict() for wall in self.walls],
            "note": (
                "Measured against the corners the owner tapped, not the room: a wall that "
                "was not tapped is not counted. Photographed means a keyframe had the "
                "wall's bearing in frame within range with nothing in the way; it does not "
                "check the frame's pitch, so it can overcount."
            ),
        }

    def render(self) -> str:
        total = sum(wall.length_m for wall in self.walls)
        lines = [
            f"session {self.session_id}",
            (
                f"  footprint: {len(self.corners)} tapped corners "
                f"({', '.join(self.corners)}), {total:.1f} m of wall"
            ),
            (
                f"  keyframes used: {self.keyframes_used} of {self.keyframes_total} "
                f"(range {self.range_m:.1f} m)"
                + ("" if self.has_mesh else "; no mesh, so nothing counts as meshed")
            ),
        ]
        width = max(len(f"{w.start} -> {w.end}") for w in self.walls) if self.walls else 0
        for wall in self.walls:
            name = f"{wall.start} -> {wall.end}".ljust(width)
            line = (
                f"  {name}  {wall.length_m:5.2f} m   meshed {wall.meshed_fraction * 100:4.0f}%"
                f"   photographed {wall.photographed_fraction * 100:4.0f}%"
            )
            for label, mask in (
                ("not meshed", wall.meshed),
                ("not photographed", wall.photographed),
            ):
                gaps = wall.gaps(mask)
                if gaps:
                    described = ", ".join(f"{a:.1f}..{b:.1f} m" for a, b in gaps[:3])
                    more = f" (+{len(gaps) - 3} more)" if len(gaps) > 3 else ""
                    line += f"   {label} {described} from {wall.start}{more}"
            lines.append(line)
        lines.append(
            "  Measured against the corners you tapped, not the room. A wall you did not "
            "tap is not counted."
        )
        return "\n".join(lines)


def footprint(session: Session) -> list[Landmark]:
    """The tapped corners in tap order, which the protocol makes the walk order."""
    corners = sorted(
        (landmark for landmark in session.landmarks() if landmark.kind == "corner"),
        key=lambda landmark: (landmark.t, landmark.i),
    )
    if len(corners) < 3:
        raise SessionError(
            f"{session.root.name}: {len(corners)} tapped corner(s); a footprint needs at "
            "least three, so there is nothing honest to measure coverage against"
        )
    return corners


def _cameras(session: Session) -> tuple[list[tuple[NDArray, NDArray, float]], int]:
    """Horizontal position, forward direction and half-spread per usable keyframe.

    The spread is taken from the four image-corner rays projected onto the floor,
    so a phone held upright (whose wide axis is vertical) gets its narrow field
    of view sideways, as it should, and a pitched camera gets the wider footprint
    its frustum really has on the plan.
    """
    cameras = []
    total = 0
    for frame in session.frames():
        total += 1
        rotation = frame.T_wc[:3, :3]
        forward = -rotation[:, 2]
        horizontal = math.hypot(forward[0], forward[2])
        if horizontal < MIN_HORIZONTAL_FORWARD:
            continue
        forward_flat = np.array([forward[0], forward[2]]) / horizontal

        tan_x = frame.w / (2.0 * frame.K[0, 0])
        tan_y = frame.h / (2.0 * frame.K[1, 1])
        spread = 0.0
        for sx in (-1.0, 1.0):
            for sy in (-1.0, 1.0):
                ray = rotation @ np.array([sx * tan_x, sy * tan_y, -1.0])
                flat = np.array([ray[0], ray[2]])
                if np.linalg.norm(flat) == 0.0:
                    continue
                flat /= np.linalg.norm(flat)
                angle = abs(
                    math.atan2(
                        forward_flat[0] * flat[1] - forward_flat[1] * flat[0],
                        float(forward_flat @ flat),
                    )
                )
                spread = max(spread, angle)
        cameras.append((frame.T_wc[[0, 2], 3].copy(), forward_flat, spread))
    return cameras, total


def _visible(origin: NDArray, targets: NDArray, edges: NDArray) -> NDArray[np.bool_]:
    """Which segments origin→target cross none of ``edges`` (proper crossings only)."""
    if edges.size == 0:
        return np.ones(len(targets), dtype=bool)
    a = origin[None, None, :]
    b = targets[:, None, :]
    c = edges[None, :, 0, :]
    d = edges[None, :, 1, :]

    def cross(u: NDArray, v: NDArray) -> NDArray:
        return u[..., 0] * v[..., 1] - u[..., 1] * v[..., 0]

    d1 = cross(d - c, a - c)
    d2 = cross(d - c, b - c)
    d3 = cross(b - a, c - a)
    d4 = cross(b - a, d - a)
    crossing = (d1 * d2 < 0) & (d3 * d4 < 0)
    return ~crossing.any(axis=1)


def wall_coverage(session: Session, *, range_m: float = DEFAULT_RANGE_M) -> CoverageReport:
    corners = footprint(session)
    polygon = np.array([[c.p_w[0], c.p_w[2]] for c in corners], dtype=np.float64)
    count = len(polygon)
    edges = np.stack([polygon, np.roll(polygon, -1, axis=0)], axis=1)

    mesh = read_mesh(session) if session.mesh_path.exists() else None
    wall_faces = None
    if mesh is not None:
        keep = (mesh.classes == WALL) & (mesh.areas() > 0)
        wall_faces = mesh.corners()[keep][:, :, [0, 2]]

    cameras, total = _cameras(session)
    cos_limits = [(position, forward, math.cos(spread)) for position, forward, spread in cameras]

    walls: list[WallCoverage] = []
    for index in range(count):
        start, end = polygon[index], polygon[(index + 1) % count]
        length = float(np.linalg.norm(end - start))
        if length == 0.0:
            continue
        direction = (end - start) / length
        cells = max(1, math.ceil(length / CELL_M))
        along = np.minimum((np.arange(cells) + 0.5) * CELL_M, length)
        centres = start[None, :] + along[:, None] * direction[None, :]

        meshed = np.zeros(cells, dtype=bool)
        if wall_faces is not None and len(wall_faces):
            relative = wall_faces - start[None, None, :]
            projected = relative @ direction
            offset = np.abs(relative[..., 0] * direction[1] - relative[..., 1] * direction[0])
            near = (
                (offset.max(axis=1) <= MESH_BAND_M)
                & (projected.max(axis=1) >= -MESH_BAND_M)
                & (projected.min(axis=1) <= length + MESH_BAND_M)
            )
            lo = projected[near].min(axis=1)[:, None]
            hi = projected[near].max(axis=1)[:, None]
            cell_lo = (np.arange(cells) * CELL_M)[None, :]
            cell_hi = cell_lo + CELL_M
            meshed = ((lo <= cell_hi) & (hi >= cell_lo)).any(axis=0) if near.any() else meshed

        photographed = np.zeros(cells, dtype=bool)
        others = np.delete(edges, index, axis=0)
        for position, forward, cos_limit in cos_limits:
            vectors = centres - position[None, :]
            distance = np.linalg.norm(vectors, axis=1)
            in_range = (distance > 0) & (distance <= range_m)
            if not in_range.any():
                continue
            bearing = (vectors[in_range] / distance[in_range][:, None]) @ forward
            candidates = np.flatnonzero(in_range)[bearing >= cos_limit]
            if candidates.size == 0:
                continue
            seen = _visible(position, centres[candidates], others)
            photographed[candidates[seen]] = True

        walls.append(
            WallCoverage(
                start=corners[index].label,
                end=corners[(index + 1) % count].label,
                length_m=length,
                meshed=meshed,
                photographed=photographed,
            )
        )

    return CoverageReport(
        session_id=session.session_id,
        corners=[corner.label for corner in corners],
        range_m=range_m,
        keyframes_used=len(cameras),
        keyframes_total=total,
        has_mesh=mesh is not None,
        walls=walls,
    )


def write_coverage(session: Session, report: CoverageReport) -> Path:
    target = session.ensure_derived() / "coverage.json"
    target.write_text(json.dumps(report.to_dict(), indent=2), encoding="utf-8")
    return target
