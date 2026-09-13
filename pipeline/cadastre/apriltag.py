"""Detecting printed markers and solving their poses in the session frame.

The rules here are from ``docs/design/pipeline-design.md`` §4. Two conventions
matter more than anything else in this file and are stated once:

- OpenCV returns corners top-left, top-right, bottom-right, bottom-left **in the
  image**, and the object points are ordered to match.
- ``solvePnP`` gives a pose in OpenCV camera axes, so moving it into the session
  frame goes through :func:`~cadastre.transforms.arkit_to_cv`, never directly.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

import cv2
import numpy as np
from numpy.typing import NDArray

from .markers import TAG_DICTIONARY, TAG_SIZE_M, marker_id
from .session import Session
from .transforms import arkit_to_cv, mat_to_cm

__all__ = [
    "R_AM",
    "AnchorAgreement",
    "MarkerSolution",
    "Observation",
    "aggregate",
    "check_anchor_frame",
    "detect",
    "solve_session",
    "write_detections",
]

#: Rejection thresholds from §4.4.
MAX_REPROJECTION_PX = 1.5
MIN_TAG_SIDE_PX = 40.0
MAX_DISTANCE_M = 4.0

#: ``T_wm = T_wa · R_AM``: ARKit's image anchor has +z toward the bottom of the
#: printed image and +y out of the face, so this turns it into the canonical
#: marker frame. From ``docs/session-format.md`` §8. The first real capture must
#: confirm it with ``--check-anchor-frame``; if the axes disagree, this constant
#: is what changes, never the app.
R_AM = np.array(
    [
        [1.0, 0.0, 0.0, 0.0],
        [0.0, 0.0, 1.0, 0.0],
        [0.0, -1.0, 0.0, 0.0],
        [0.0, 0.0, 0.0, 1.0],
    ]
)


def _object_points(tag_size_m: float) -> NDArray[np.float64]:
    """Tag corners in the canonical marker frame, in OpenCV's corner order."""
    half = tag_size_m / 2.0
    return np.array(
        [
            [-half, half, 0.0],
            [half, half, 0.0],
            [half, -half, 0.0],
            [-half, -half, 0.0],
        ]
    )


@dataclass(frozen=True)
class Observation:
    """One marker seen in one image, already in the session frame."""

    marker_id: str
    source: str
    frame_index: int
    T_wm: NDArray[np.float64]
    reprojection_px: float
    tag_side_px: float
    distance_m: float


@dataclass(frozen=True)
class MarkerSolution:
    """One marker's pose, aggregated over every accepted observation."""

    marker_id: str
    T_wm: NDArray[np.float64]
    n_obs: int
    spread_m: float
    spread_deg: float

    def to_dict(self) -> dict:
        return {
            "T_wm": mat_to_cm(self.T_wm),
            "n_obs": self.n_obs,
            "spread_m": round(self.spread_m, 6),
            "spread_deg": round(self.spread_deg, 6),
        }


@dataclass(frozen=True)
class AnchorAgreement:
    """How closely the app's ARKit anchor agrees with the solved pose."""

    marker_id: str
    translation_error_m: float
    rotation_error_deg: float
    per_axis_deg: tuple[float, float, float]


def _detector_parameters() -> cv2.aruco.DetectorParameters:
    """Detector settings, with subpixel corner refinement turned on.

    Refinement is not a default, and it is worth far more here than it costs. The
    corners a detector returns without it are quantised to whole pixels, and a
    12.8 cm tag fifty pixels across turns that quantisation into centimetres of
    position error once PnP has scaled it up by the distance.
    """
    parameters = cv2.aruco.DetectorParameters()
    parameters.cornerRefinementMethod = cv2.aruco.CORNER_REFINE_SUBPIX
    return parameters


def detect(gray: NDArray[np.uint8]) -> list[tuple[int, NDArray[np.float64]]]:
    """Find every 36h11 tag in a grayscale image, as ``(number, 4x2 corners)``."""
    detector = cv2.aruco.ArucoDetector(
        cv2.aruco.getPredefinedDictionary(TAG_DICTIONARY), _detector_parameters()
    )
    corners, ids, _ = detector.detectMarkers(gray)
    if ids is None:
        return []
    return [
        (int(tag), np.asarray(quad[0], dtype=np.float64))
        for quad, tag in zip(corners, ids.flatten(), strict=True)
    ]


def _solve_pnp(
    corners: NDArray[np.float64], k: NDArray[np.float64], tag_size_m: float
) -> tuple[NDArray[np.float64], float] | None:
    """Solve one tag's pose in OpenCV camera axes, with its reprojection error."""
    objects = _object_points(tag_size_m)
    ok, rvec, tvec = cv2.solvePnP(
        objects,
        corners.astype(np.float64),
        k,
        None,
        flags=cv2.SOLVEPNP_IPPE_SQUARE,
    )
    if not ok:
        return None

    projected, _ = cv2.projectPoints(objects, rvec, tvec, k, None)
    error = float(np.sqrt(np.mean(np.sum((projected.reshape(-1, 2) - corners) ** 2, axis=1))))

    pose = np.eye(4)
    pose[:3, :3] = cv2.Rodrigues(rvec)[0]
    pose[:3, 3] = tvec.flatten()
    return pose, error


def _mean_side(corners: NDArray[np.float64]) -> float:
    return float(np.mean([np.linalg.norm(corners[i] - corners[(i + 1) % 4]) for i in range(4)]))


def _observe(
    marker: str,
    source: str,
    frame_index: int,
    corners: NDArray[np.float64],
    k: NDArray[np.float64],
    pose_wc: NDArray[np.float64],
    tag_size_m: float,
) -> Observation | None:
    """Apply the §4.4 rejections and lift an accepted detection to the session frame."""
    side = _mean_side(corners)
    if side < MIN_TAG_SIDE_PX:
        return None

    solved = _solve_pnp(corners, k, tag_size_m)
    if solved is None:
        return None
    t_cm, error = solved
    if error > MAX_REPROJECTION_PX:
        return None

    distance = float(np.linalg.norm(t_cm[:3, 3]))
    if distance > MAX_DISTANCE_M:
        return None

    return Observation(
        marker_id=marker,
        source=source,
        frame_index=frame_index,
        T_wm=arkit_to_cv(pose_wc) @ t_cm,
        reprojection_px=error,
        tag_side_px=side,
        distance_m=distance,
    )


def solve_session(
    session: Session, *, stride: int = 1, tag_size_m: float = TAG_SIZE_M
) -> list[Observation]:
    """Detect and solve every marker across the keyframes and stills."""
    if stride < 1:
        raise ValueError(f"stride must be at least 1, got {stride}")

    observations: list[Observation] = []

    for frame in session.frames():
        if frame.i % stride:
            continue
        image = cv2.imread(str(session.resolve(frame.rgb)), cv2.IMREAD_GRAYSCALE)
        if image is None:
            continue
        for number, corners in detect(image):
            found = _observe(
                marker_id(number), frame.rgb, frame.i, corners, frame.K, frame.T_wc, tag_size_m
            )
            if found is not None:
                observations.append(found)

    for still in session.stills():
        image = cv2.imread(str(session.resolve(still.path)), cv2.IMREAD_GRAYSCALE)
        if image is None:
            continue
        for number, corners in detect(image):
            found = _observe(
                marker_id(number), still.path, still.i, corners, still.K, still.T_wc, tag_size_m
            )
            if found is not None:
                observations.append(found)

    return observations


def _angle_between(a: NDArray[np.float64], b: NDArray[np.float64]) -> float:
    """Angle in degrees between two rotation matrices."""
    cosine = (float(np.trace(a.T @ b)) - 1.0) / 2.0
    return float(np.degrees(np.arccos(min(1.0, max(-1.0, cosine)))))


def aggregate(observations: list[Observation]) -> dict[str, MarkerSolution]:
    """Combine observations per marker.

    Translation is the component-wise median, which ignores an outlier rather
    than being dragged by it — one bad detection at a glancing angle should not
    move a marker the rest agree on.

    Rotation cannot be averaged that way, so the reported rotation is the real
    observation closest to the chordal mean. That keeps it a valid rotation
    without a renormalisation step that would quietly invent an orientation
    nothing observed.
    """
    grouped: dict[str, list[Observation]] = {}
    for observation in observations:
        grouped.setdefault(observation.marker_id, []).append(observation)

    solutions: dict[str, MarkerSolution] = {}
    for marker, group in sorted(grouped.items()):
        translations = np.array([o.T_wm[:3, 3] for o in group])
        median = np.median(translations, axis=0)
        spread_m = float(np.max(np.linalg.norm(translations - median, axis=1)))

        rotations = [o.T_wm[:3, :3] for o in group]
        chordal_mean = np.mean(rotations, axis=0)
        best = min(rotations, key=lambda r: float(np.linalg.norm(r - chordal_mean)))
        spread_deg = max(_angle_between(best, r) for r in rotations)

        pose = np.eye(4)
        pose[:3, :3] = best
        pose[:3, 3] = median
        solutions[marker] = MarkerSolution(
            marker_id=marker,
            T_wm=pose,
            n_obs=len(group),
            spread_m=spread_m,
            spread_deg=spread_deg,
        )
    return solutions


def check_anchor_frame(
    session: Session, solutions: dict[str, MarkerSolution]
) -> list[AnchorAgreement]:
    """Compare the app's ARKit anchors, converted with :data:`R_AM`, against PnP.

    Run once on the first real capture. Disagreement means :data:`R_AM` is wrong,
    and the constant is what changes — never the app, whose anchors are whatever
    ARKit actually reports.
    """
    anchors: dict[str, list[NDArray[np.float64]]] = {}
    for observation in session.markers():
        anchors.setdefault(observation.marker_id, []).append(observation.T_wa @ R_AM)

    agreements: list[AnchorAgreement] = []
    for marker, solution in sorted(solutions.items()):
        if marker not in anchors:
            continue
        poses = anchors[marker]
        translation = np.median(np.array([p[:3, 3] for p in poses]), axis=0)
        rotation = poses[0][:3, :3]

        per_axis = tuple(
            float(
                np.degrees(
                    np.arccos(
                        min(1.0, max(-1.0, float(np.dot(rotation[:, a], solution.T_wm[:3, a]))))
                    )
                )
            )
            for a in range(3)
        )
        agreements.append(
            AnchorAgreement(
                marker_id=marker,
                translation_error_m=float(np.linalg.norm(translation - solution.T_wm[:3, 3])),
                rotation_error_deg=_angle_between(rotation, solution.T_wm[:3, :3]),
                per_axis_deg=per_axis,
            )
        )
    return agreements


def write_detections(session: Session, solutions: dict[str, MarkerSolution]) -> Path:
    """Write ``derived/markers_detected.json`` and return its path."""
    target = session.ensure_derived() / "markers_detected.json"
    payload = {marker: solution.to_dict() for marker, solution in sorted(solutions.items())}
    target.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    return target
