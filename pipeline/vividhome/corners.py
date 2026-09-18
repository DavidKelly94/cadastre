"""Corner candidates from the wall mesh: the room side of ai-roadmap item 5, offline.

ADR-0026 made tapped corners the thing that places a capture on the plan, and
tapping every corner one-handed in a noisy room is the step most likely to be
skipped. The roadmap's answer is to propose corners from the wall mesh and let
the owner drag a few into place. That is app work, and it should not be paid for
before the idea is measured. This is the measurement: the same geometry, run on
the PC over a capture that already carries a classified mesh and the owner's own
taps, reporting how many taps a proposal would have landed within 20 cm of.

Everything here is a candidate (rule 9 of ``AGENTS.md``). A candidate carries a
source, a confidence and an empty ``confirmed``, and nothing writes one to
``landmarks.jsonl``. The confidence is a heuristic — how much wall supports each
plane and how close the two walls reach their meeting point — and never a
measurement error. A confident candidate in the wrong place is the failure the
roadmap warns about, which is why the report scores against the owner's taps
rather than trusting itself.

The geometry is two-dimensional. ARKit's ``+y`` is up and gravity-aligned
(section 3), so a wall is a line in the x-z plane and a corner is where two lines
meet at floor height.
"""

from __future__ import annotations

import json
import math
from dataclasses import dataclass, field, replace
from itertools import combinations
from pathlib import Path

import numpy as np
from numpy.typing import NDArray

from .mesh import FLOOR, WALL, Mesh, read_mesh
from .session import Landmark, Session

__all__ = [
    "CornerCandidate",
    "CornerReport",
    "WallPlane",
    "compare_with_landmarks",
    "corner_candidates",
    "find_walls",
    "floor_height",
    "propose_corners",
    "write_candidates",
]

#: Wall area at which a plane counts as fully supported. A real wall is several
#: square metres of mesh; a cabinet side misclassified as wall is a fraction of
#: one, and the difference is what keeps furniture from proposing corners.
FULL_SUPPORT_M2 = 1.0

#: The roadmap's acceptance distance: a proposal the owner would accept with a
#: drag under this counts as a hit.
ACCEPT_M = 0.20


@dataclass(frozen=True)
class WallPlane:
    """A vertical plane fitted to wall faces: a line in the x-z plane."""

    id: str
    #: Direction of the normal, folded to [0, 180): a wall has no front.
    azimuth_deg: float
    #: ``normal · (x, z) == offset`` on the plane.
    offset_m: float
    area_m2: float
    faces: int
    #: Along the tangent ``(-sin, cos)`` of the azimuth: where the wall starts and ends.
    extent_m: tuple[float, float]
    height_m: tuple[float, float]

    @property
    def normal(self) -> NDArray[np.float64]:
        angle = math.radians(self.azimuth_deg)
        return np.array([math.cos(angle), math.sin(angle)])

    @property
    def tangent(self) -> NDArray[np.float64]:
        angle = math.radians(self.azimuth_deg)
        return np.array([-math.sin(angle), math.cos(angle)])

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "azimuth_deg": round(self.azimuth_deg, 2),
            "offset_m": round(self.offset_m, 4),
            "area_m2": round(self.area_m2, 3),
            "faces": self.faces,
            "extent_m": [round(self.extent_m[0], 3), round(self.extent_m[1], 3)],
            "height_m": [round(self.height_m[0], 3), round(self.height_m[1], 3)],
        }


@dataclass(frozen=True)
class CornerCandidate:
    id: str
    p_w: tuple[float, float, float]
    walls: tuple[str, str]
    confidence: float
    nearest_landmark: dict | None = None

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "p_w": [_tidy(v) for v in self.p_w],
            "walls": list(self.walls),
            "confidence": self.confidence,
            # The roadmap's guardrail: every derived record says where it came
            # from and that nobody has confirmed it yet.
            "source": "mesh",
            "confirmed": None,
            "nearest_landmark": self.nearest_landmark,
        }


@dataclass
class CornerReport:
    session_id: str
    floor_y: float
    floor_source: str
    wall_faces: int
    walls: list[WallPlane] = field(default_factory=list)
    candidates: list[CornerCandidate] = field(default_factory=list)
    against_landmarks: dict | None = None

    def to_dict(self) -> dict:
        return {
            "session_id": self.session_id,
            "source": "mesh",
            "floor_y": round(self.floor_y, 4),
            "floor_source": self.floor_source,
            "wall_faces": self.wall_faces,
            "walls": [wall.to_dict() for wall in self.walls],
            "candidates": [candidate.to_dict() for candidate in self.candidates],
            "against_landmarks": self.against_landmarks,
            "note": (
                "Candidates, not measurements. Nothing here says a corner is where the "
                "owner would tap it; a candidate reaches landmarks.jsonl only by being "
                "dragged into place and confirmed in the app."
            ),
        }

    def render(self) -> str:
        lines = [
            f"session {self.session_id}",
            (
                f"  {len(self.walls)} wall plane(s) from {self.wall_faces} wall-classified faces; "
                f"floor at y = {self.floor_y:.3f} m ({self.floor_source})"
            ),
        ]
        for wall in self.walls:
            lines.append(
                f"  {wall.id:<3} azimuth {wall.azimuth_deg:6.1f} deg  offset {wall.offset_m:7.3f} m"
                f"  area {wall.area_m2:6.2f} m2  extent {wall.extent_m[0]:.2f}..{wall.extent_m[1]:.2f} m"
            )
        lines.append(f"  {len(self.candidates)} corner candidate(s)")
        for candidate in self.candidates:
            x, _, z = candidate.p_w
            nearest = candidate.nearest_landmark
            tail = (
                f"  nearest tap {nearest['label']} {nearest['distance_m']:.3f} m" if nearest else ""
            )
            lines.append(
                f"  {candidate.id:<3} ({x:7.3f}, {z:7.3f})  conf {candidate.confidence:.2f}"
                f"  {candidate.walls[0]} x {candidate.walls[1]}{tail}"
            )
        against = self.against_landmarks
        if against is None:
            lines.append("  no tapped corners to score against")
        else:
            lines.append(
                f"  against {against['tapped_corners']} tapped corner(s): "
                f"{against['matched']} within {against['accept_m']:.2f} m "
                f"({against['fraction'] * 100:.0f}%)"
            )
            stray = against["candidates_without_a_tap"]
            lines.append(
                f"  candidates with no tap within {against['stray_m']:.2f} m: "
                + (", ".join(stray) if stray else "none")
            )
        lines.append(
            "  Candidates, not measurements: nothing here says a corner is where the "
            "owner would tap it."
        )
        return "\n".join(lines)


def _fold(theta: NDArray[np.float64] | float) -> NDArray[np.float64]:
    """Normal directions modulo a half turn: a wall has no front.

    A value a rounding error short of a half turn folds to zero rather than
    staying at 179.999 degrees, so the same wall gets the same azimuth whichever
    way its faces happened to be wound.
    """
    folded = np.mod(np.asarray(theta, dtype=np.float64), np.pi)
    return np.where(np.isclose(folded, np.pi), 0.0, folded)


def _angular_distance(theta: NDArray[np.float64], reference: float) -> NDArray[np.float64]:
    delta = np.abs(_fold(theta) - _fold(np.array(reference)))
    return np.minimum(delta, np.pi - delta)


def find_walls(
    mesh: Mesh,
    *,
    min_area_m2: float = 0.5,
    max_tilt: float = 0.2,
    angle_tol_deg: float = 10.0,
    offset_tol_m: float = 0.15,
) -> list[WallPlane]:
    """Cluster wall-classified faces into vertical planes.

    Greedy: the largest unassigned face seeds a plane, every face within
    ``angle_tol_deg`` of its normal and ``offset_tol_m`` of its line joins, the
    plane is refitted to its members by area, membership is taken once more
    against the refit, and the process repeats. Planes with less than
    ``min_area_m2`` of wall are dropped: furniture ARKit calls "wall" is small.
    ``max_tilt`` is the largest vertical component a face normal may have and
    still count as wall — a sloped ceiling classified as wall is not a wall.
    """
    normals, areas, centroids = mesh.normals(), mesh.areas(), mesh.centroids()
    wall = (mesh.classes == WALL) & (areas > 0) & (np.abs(normals[:, 1]) <= max_tilt)
    index = np.flatnonzero(wall)
    if index.size == 0:
        return []

    theta = np.arctan2(normals[index, 2], normals[index, 0])
    area = areas[index]
    flat = centroids[index][:, [0, 2]]
    tol = math.radians(angle_tol_deg)

    def members_of(reference: float, offset: float, remaining: NDArray[np.bool_]):
        normal = np.array([math.cos(reference), math.sin(reference)])
        offsets = flat @ normal
        near = (_angular_distance(theta, reference) <= tol) & (
            np.abs(offsets - offset) <= offset_tol_m
        )
        return remaining & near

    remaining = np.ones(index.size, dtype=bool)
    planes: list[WallPlane] = []
    while remaining.any():
        seed = int(np.argmax(np.where(remaining, area, -1.0)))
        reference = float(_fold(theta[seed]))
        seed_normal = np.array([math.cos(reference), math.sin(reference)])
        members = members_of(reference, float(flat[seed] @ seed_normal), remaining)

        # Refit by area. Angles are averaged as doubled vectors so that a wall
        # straddling 0 and 180 degrees averages to itself rather than to 90.
        weights = area[members]
        doubled = 2.0 * theta[members]
        reference = float(
            _fold(
                np.arctan2(np.sum(weights * np.sin(doubled)), np.sum(weights * np.cos(doubled))) / 2
            )
        )
        normal = np.array([math.cos(reference), math.sin(reference)])
        offset = float(np.average(flat[members] @ normal, weights=weights))
        members = members_of(reference, offset, remaining)
        members[seed] = True
        remaining &= ~members

        total = float(area[members].sum())
        if total < min_area_m2:
            continue

        points = mesh.vertices[mesh.faces[index[members]]].reshape(-1, 3)
        tangent = np.array([-math.sin(reference), math.cos(reference)])
        along = points[:, [0, 2]] @ tangent
        planes.append(
            WallPlane(
                id="",
                azimuth_deg=math.degrees(reference),
                offset_m=float(np.average(flat[members] @ normal, weights=area[members])),
                area_m2=total,
                faces=int(members.sum()),
                extent_m=(float(along.min()), float(along.max())),
                height_m=(float(points[:, 1].min()), float(points[:, 1].max())),
            )
        )

    planes.sort(key=lambda plane: -plane.area_m2)
    return [replace(plane, id=f"W{n}") for n, plane in enumerate(planes, start=1)]


def floor_height(mesh: Mesh, walls: list[WallPlane]) -> tuple[float, str]:
    """Where the floor is: floor faces if any, else the bottom of the walls."""
    areas = mesh.areas()
    floor = (mesh.classes == FLOOR) & (areas > 0)
    if floor.any():
        heights = mesh.centroids()[floor, 1]
        weights = areas[floor]
        order = np.argsort(heights)
        cumulative = np.cumsum(weights[order])
        median = heights[order][np.searchsorted(cumulative, cumulative[-1] / 2)]
        return float(median), "floor faces"
    if walls:
        return min(wall.height_m[0] for wall in walls), "wall bottoms"
    return 0.0, "assumed"


def _tidy(value: float, digits: int = 4) -> float:
    """Round, and turn a -0.0 back into 0.0 so a report never prints '-0.000'."""
    return round(value, digits) + 0.0


def _gap(position: float, extent: tuple[float, float]) -> float:
    """How far outside a wall's run a point along its line falls; zero inside."""
    return max(0.0, extent[0] - position, position - extent[1])


def corner_candidates(
    walls: list[WallPlane],
    floor_y: float,
    *,
    min_angle_deg: float = 30.0,
    reach_m: float = 0.3,
    merge_m: float = 0.1,
) -> list[CornerCandidate]:
    """Intersect every pair of non-parallel walls that actually reach each other.

    Two lines always meet somewhere; the reach test is what separates a corner
    from a ghost. A wall's faces have to run to within ``reach_m`` of the
    intersection on both sides, so the far wall of an L-shaped room does not
    propose a corner in the middle of the notch. Candidates closer than
    ``merge_m`` collapse to the more confident one.
    """
    found: list[tuple[NDArray[np.float64], tuple[str, str], float]] = []
    for a, b in combinations(walls, 2):
        delta = abs(a.azimuth_deg - b.azimuth_deg)
        delta = min(delta, 180.0 - delta)
        if delta < min_angle_deg:
            continue
        point = np.linalg.solve(np.array([a.normal, b.normal]), np.array([a.offset_m, b.offset_m]))
        gap = max(
            _gap(float(point @ a.tangent), a.extent_m), _gap(float(point @ b.tangent), b.extent_m)
        )
        if gap > reach_m:
            continue
        support = min(1.0, a.area_m2 / FULL_SUPPORT_M2, b.area_m2 / FULL_SUPPORT_M2)
        confidence = round(support * (1.0 - gap / reach_m), 3)
        found.append((point, (a.id, b.id), confidence))

    found.sort(key=lambda entry: -entry[2])
    kept: list[tuple[NDArray[np.float64], tuple[str, str], float]] = []
    for point, pair, confidence in found:
        if any(np.linalg.norm(point - other[0]) < merge_m for other in kept):
            continue
        kept.append((point, pair, confidence))

    return [
        CornerCandidate(
            id=f"C{n}",
            p_w=(float(_clean_point(point)[0]), float(floor_y), float(_clean_point(point)[1])),
            walls=pair,
            confidence=confidence,
        )
        for n, (point, pair, confidence) in enumerate(kept, start=1)
    ]


def _clean_point(point: NDArray[np.float64]) -> NDArray[np.float64]:
    return np.where(np.isclose(point, 0.0), 0.0, point)


def _horizontal(a: tuple[float, float, float] | NDArray, b: NDArray) -> float:
    return float(math.hypot(a[0] - b[0], a[2] - b[2]))


def compare_with_landmarks(
    candidates: list[CornerCandidate],
    landmarks: list[Landmark],
    *,
    accept_m: float = ACCEPT_M,
    stray_m: float = 0.5,
) -> tuple[list[CornerCandidate], dict | None]:
    """Score the candidates against the corners the owner tapped.

    Horizontal distance only: taps land on the floor by protocol and candidates
    are placed at floor height, so a vertical difference is the floor estimate's
    error rather than the corner's. Returns the candidates with their nearest tap
    attached, and the summary, or None when the session has no tapped corners.
    """
    corners = [landmark for landmark in landmarks if landmark.kind == "corner"]
    if not corners:
        return candidates, None

    attached: list[CornerCandidate] = []
    for candidate in candidates:
        nearest = min(corners, key=lambda landmark: _horizontal(candidate.p_w, landmark.p_w))
        distance = _horizontal(candidate.p_w, nearest.p_w)
        attached.append(
            replace(
                candidate,
                nearest_landmark={"label": nearest.label, "distance_m": round(distance, 3)},
            )
        )

    per_landmark = []
    matched = 0
    for landmark in corners:
        if candidates:
            best = min(candidates, key=lambda candidate: _horizontal(candidate.p_w, landmark.p_w))
            distance = _horizontal(best.p_w, landmark.p_w)
            hit = distance <= accept_m
            matched += int(hit)
            per_landmark.append(
                {
                    "label": landmark.label,
                    "candidate": best.id,
                    "distance_m": round(distance, 3),
                    "within": hit,
                }
            )
        else:
            per_landmark.append(
                {"label": landmark.label, "candidate": None, "distance_m": None, "within": False}
            )

    stray = [
        candidate.id
        for candidate in attached
        if candidate.nearest_landmark and candidate.nearest_landmark["distance_m"] > stray_m
    ]
    summary = {
        "tapped_corners": len(corners),
        "accept_m": accept_m,
        "stray_m": stray_m,
        "matched": matched,
        "fraction": round(matched / len(corners), 3),
        "landmarks": per_landmark,
        "candidates_without_a_tap": stray,
    }
    return attached, summary


def propose_corners(session: Session, *, min_area_m2: float = 0.5) -> CornerReport:
    """Run the whole chain on one session: walls, floor, candidates, score."""
    mesh = read_mesh(session)
    walls = find_walls(mesh, min_area_m2=min_area_m2)
    floor_y, floor_source = floor_height(mesh, walls)
    candidates = corner_candidates(walls, floor_y)
    candidates, against = compare_with_landmarks(candidates, list(session.landmarks()))
    return CornerReport(
        session_id=session.session_id,
        floor_y=floor_y,
        floor_source=floor_source,
        wall_faces=int((mesh.classes == WALL).sum()),
        walls=walls,
        candidates=candidates,
        against_landmarks=against,
    )


def write_candidates(session: Session, report: CornerReport) -> Path:
    """Write ``derived/corner_candidates.json``. Never ``landmarks.jsonl``."""
    target = session.ensure_derived() / "corner_candidates.json"
    target.write_text(json.dumps(report.to_dict(), indent=2), encoding="utf-8")
    return target
