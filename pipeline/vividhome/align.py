"""Solving the session-to-house transform for one level.

A session is recorded in its own ARKit frame, whose origin and yaw are wherever
the phone happened to start. `align` finds the rigid 2D motion that puts it on
the building's plan: ``T_hs``, stored as a full 4x4 so nothing downstream has to
repeat the sign conventions. See ``docs/design/system-design.md`` §4.

Correspondences come from tapped landmarks paired with points on the drawing, and
optionally from markers already placed in the house frame by an earlier session,
which is more accurate once markers are established.

As with `plan`, the browser page that collects the clicks is still to come; the
solving lives here so it can be tested and scripted.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path

import numpy as np
from numpy.typing import NDArray

from .plan import PlanCalibration, PlanError, plan_to_house
from .session import Session
from .transforms import embed_se2, mat_to_cm, theta_from_se2, umeyama_2d

__all__ = [
    "REFUSE_RMS_M",
    "WARN_RMS_M",
    "AlignError",
    "Alignment",
    "Correspondence",
    "floor_y_session",
    "landmark_pairs",
    "marker_pairs",
    "solve",
    "update_marker_map",
    "write_alignment",
]

#: §6: above this the fit is suspect; above the second it is not written at all.
WARN_RMS_M = 0.15
REFUSE_RMS_M = 0.30


class AlignError(Exception):
    """An alignment could not be solved or written."""


@dataclass(frozen=True)
class Correspondence:
    """One session point matched to one house point, both horizontal metres."""

    label: str
    session_xz: tuple[float, float]
    house_xz: tuple[float, float]
    source: str

    def to_dict(self) -> dict:
        return {
            "label": self.label,
            "session_xz": list(self.session_xz),
            "house_xz": list(self.house_xz),
            "source": self.source,
        }


@dataclass
class Alignment:
    session_id: str
    level: str
    T_hs: NDArray[np.float64]
    pairs: list[Correspondence]
    rms_m: float
    max_residual_m: float
    method: str
    floor_source: str
    created_at: str = field(default_factory=lambda: datetime.now(UTC).isoformat())

    @property
    def yaw_deg(self) -> float:
        return float(np.degrees(theta_from_se2(self.T_hs)))

    def to_dict(self) -> dict:
        return {
            "session_id": self.session_id,
            "level": self.level,
            "T_hs": mat_to_cm(self.T_hs),
            "pairs": [pair.to_dict() for pair in self.pairs],
            "rms_m": round(self.rms_m, 6),
            "max_residual_m": round(self.max_residual_m, 6),
            "method": self.method,
            "floor_source": self.floor_source,
            "created_at": self.created_at,
        }


def floor_y_session(session: Session) -> tuple[float, str]:
    """The session-frame height of this room's floor, and where it came from.

    Preference order is the specification's: landmarks the owner tagged as floor,
    then mesh faces classified floor. The fallback is the lowest landmark, which
    is reported as such rather than passed off as a measurement — a room whose
    floor height is a guess should say so in the alignment file.
    """
    heights = [landmark.p_w[1] for landmark in session.landmarks() if landmark.kind == "floor"]
    if heights:
        return float(np.median(heights)), "floor-landmarks"

    mesh_floor = _mesh_floor_y(session)
    if mesh_floor is not None:
        return mesh_floor, "mesh"

    all_heights = [landmark.p_w[1] for landmark in session.landmarks()]
    if all_heights:
        return float(np.min(all_heights)), "lowest-landmark"
    return 0.0, "assumed-zero"


def _mesh_floor_y(session: Session) -> float | None:
    """Median height of mesh faces classified floor, or None if unavailable."""
    mesh = session.mesh_path
    classes = session.root / "mesh_classes.u8"
    if not mesh.exists() or not classes.exists():
        return None

    vertices: list[tuple[float, float, float]] = []
    faces: list[tuple[int, int, int]] = []
    for line in mesh.read_text(encoding="utf-8").splitlines():
        if line.startswith("v "):
            parts = line.split()
            vertices.append((float(parts[1]), float(parts[2]), float(parts[3])))
        elif line.startswith("f "):
            parts = line.split()
            faces.append(tuple(int(p.split("/")[0]) - 1 for p in parts[1:4]))
    if not faces:
        return None

    labels = classes.read_bytes()
    if len(labels) != len(faces):
        return None

    FLOOR = 2
    heights = [
        np.mean([vertices[index][1] for index in face])
        for face, label in zip(faces, labels, strict=True)
        if label == FLOOR
    ]
    return float(np.median(heights)) if heights else None


def landmark_pairs(
    session: Session, calibration: PlanCalibration, clicks: dict[str, tuple[float, float]]
) -> list[Correspondence]:
    """Pair tapped landmarks with pixels clicked on the plan."""
    positions = {landmark.label: landmark.p_w for landmark in session.landmarks()}
    pairs: list[Correspondence] = []
    for label, pixel in clicks.items():
        if label not in positions:
            known = ", ".join(sorted(positions)) or "none"
            raise AlignError(f"no landmark named {label!r} in this session (have: {known})")
        point = positions[label]
        pairs.append(
            Correspondence(
                label=label,
                session_xz=(float(point[0]), float(point[2])),
                house_xz=plan_to_house(calibration, pixel[0], pixel[1]),
                source="landmark",
            )
        )
    return pairs


def _marker_map_path(store: str | Path, project: str) -> Path:
    return Path(store) / "markers" / f"{project}.json"


def _load_marker_map(store: str | Path, project: str) -> dict[str, list[float]]:
    path = _marker_map_path(store, project)
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        raise AlignError(f"{path.name}: cannot read the marker map ({error})") from error


def marker_pairs(session: Session, store: str | Path, project: str) -> list[Correspondence]:
    """Pair markers this session saw with the same markers already in the house map."""
    detected_path = session.derived / "markers_detected.json"
    if not detected_path.exists():
        raise AlignError(
            "no derived/markers_detected.json; run 'vividhome apriltag' before --use-markers"
        )
    detected = json.loads(detected_path.read_text(encoding="utf-8"))
    house = _load_marker_map(store, project)

    pairs: list[Correspondence] = []
    for marker, entry in sorted(detected.items()):
        if marker not in house:
            continue
        session_t = np.asarray(entry["T_wm"], dtype=float).reshape(4, 4, order="F")[:3, 3]
        house_t = np.asarray(house[marker]["T_hm"], dtype=float).reshape(4, 4, order="F")[:3, 3]
        pairs.append(
            Correspondence(
                label=marker,
                session_xz=(float(session_t[0]), float(session_t[2])),
                house_xz=(float(house_t[0]), float(house_t[2])),
                source="marker",
            )
        )
    return pairs


def solve(
    session: Session,
    calibration: PlanCalibration,
    pairs: list[Correspondence],
    *,
    force: bool = False,
) -> Alignment:
    """Fit ``T_hs`` from the correspondences and report how well it fits."""
    if len(pairs) < 2:
        raise AlignError(f"need at least 2 correspondences, got {len(pairs)}")

    a = np.array([pair.session_xz for pair in pairs])
    b = np.array([pair.house_xz for pair in pairs])
    rotation, translation, rms = umeyama_2d(a, b)

    floor_y, floor_source = floor_y_session(session)
    t_y = calibration.floor_height_m - floor_y

    t_hs = embed_se2(rotation, translation, ty=t_y)
    residuals = np.linalg.norm(b - (a @ rotation.T + translation), axis=1)
    max_residual = float(np.max(residuals))

    if rms > REFUSE_RMS_M and not force:
        raise AlignError(
            f"residual {rms:.3f} m is above {REFUSE_RMS_M} m; the correspondences disagree. "
            "Check the pairs, or pass --force to write it anyway."
        )

    sources = {pair.source for pair in pairs}
    method = "landmarks+markers" if len(sources) > 1 else next(iter(sources)) + "s"

    return Alignment(
        session_id=session.session_id,
        level=calibration.level,
        T_hs=t_hs,
        pairs=pairs,
        rms_m=float(rms),
        max_residual_m=max_residual,
        method=method,
        floor_source=floor_source,
    )


def write_alignment(store: str | Path, alignment: Alignment) -> Path:
    directory = Path(store) / "alignments"
    directory.mkdir(parents=True, exist_ok=True)
    target = directory / f"{alignment.session_id}.json"
    target.write_text(json.dumps(alignment.to_dict(), indent=2), encoding="utf-8")
    return target


def update_marker_map(
    store: str | Path, project: str, session: Session, alignment: Alignment
) -> list[str]:
    """Add markers this session saw, in house coordinates, to the project map.

    Only markers not already mapped are added. An established marker keeps the
    pose it was first solved with, so repeatedly aligning sessions cannot let the
    house map drift one small correction at a time.
    """
    detected_path = session.derived / "markers_detected.json"
    if not detected_path.exists():
        return []
    detected = json.loads(detected_path.read_text(encoding="utf-8"))
    house = _load_marker_map(store, project)

    added: list[str] = []
    for marker, entry in sorted(detected.items()):
        if marker in house:
            continue
        t_wm = np.asarray(entry["T_wm"], dtype=float).reshape(4, 4, order="F")
        house[marker] = {
            "T_hm": mat_to_cm(alignment.T_hs @ t_wm),
            "from_session": session.session_id,
            "level": alignment.level,
            "n_obs": entry.get("n_obs"),
        }
        added.append(marker)

    if added:
        path = _marker_map_path(store, project)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(house, indent=2, sort_keys=True), encoding="utf-8")
    return added


def project_slug(session: Session) -> str:
    project = session.manifest.get("project")
    if isinstance(project, dict) and project.get("slug"):
        return str(project["slug"])
    raise PlanError("session manifest has no project slug")
