"""A synthetic capture session with known geometry.

Everything downstream — ``apriltag``, ``plan``, ``align``, ``inspect`` — needs a
session whose right answer is known before it can be tested at all. This builds
one: a real room, real poses, ray-cast depth and tags actually rendered into the
images, so a test can assert a recovered pose against the pose that produced it
rather than against whatever the code happened to return.

The room is an axis-aligned box with the floor at ``y = 0``. The camera walks a
circle at eye height looking outward at the walls, which is what puts markers in
frame. Session frame conventions are those of ``docs/session-format.md`` §3.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

import cv2
import numpy as np
from numpy.typing import NDArray

from .markers import TAG_SIZE_M, marker_id, tag_bitmap
from .transforms import mat_to_cm

__all__ = ["SynthSpec", "SyntheticSession", "build"]


@dataclass(frozen=True)
class SynthSpec:
    """Everything the generated room is made of. Defaults are the documented 4x5 m."""

    width_m: float = 4.0
    depth_m: float = 5.0
    height_m: float = 2.5
    #: 48 rather than the 30 the design sketched: a 65 degree field of view sweeping
    #: a full turn leaves each marker in frame only briefly, and 30 keyframes yields
    #: two or three observations per marker, too few to exercise the median
    #: aggregation apriltag does. 48 gives at least three each and still builds in
    #: about a tenth of a second.
    keyframes: int = 48
    eye_height_m: float = 1.5
    path_radius_m: float = 1.2
    colour_w: int = 640
    colour_h: int = 480
    depth_w: int = 80
    depth_h: int = 60
    focal_px: float = 500.0
    duration_s: float = 15.0
    #: Tag numbers placed on the z = 0 and x = 0 walls respectively.
    marker_numbers: tuple[int, int] = (12, 13)
    stills: int = 1

    @property
    def centre(self) -> tuple[float, float]:
        return self.width_m / 2.0, self.depth_m / 2.0


@dataclass(frozen=True)
class SyntheticSession:
    """Where the session was written, and the ground truth it was built from."""

    root: Path
    spec: SynthSpec
    poses: list[NDArray[np.float64]]
    marker_poses: dict[str, NDArray[np.float64]]
    landmarks: dict[str, NDArray[np.float64]]

    @property
    def session_id(self) -> str:
        return self.root.name


def _intrinsics(spec: SynthSpec) -> NDArray[np.float64]:
    return np.array(
        [
            [spec.focal_px, 0.0, spec.colour_w / 2.0],
            [0.0, spec.focal_px, spec.colour_h / 2.0],
            [0.0, 0.0, 1.0],
        ]
    )


def _look_outward_pose(position: NDArray[np.float64], yaw: float) -> NDArray[np.float64]:
    """An ARKit camera pose at ``position`` looking horizontally along ``yaw``.

    ARKit's camera looks down its own ``-z``, so the forward direction is the
    negated third column. ``+y`` stays world up, which keeps the horizon level —
    the phone is held upright while walking a room.
    """
    forward = np.array([np.sin(yaw), 0.0, -np.cos(yaw)])
    up = np.array([0.0, 1.0, 0.0])
    right = np.cross(forward, up)
    right /= np.linalg.norm(right)
    camera_up = np.cross(right, forward)

    pose = np.eye(4)
    pose[:3, 0] = right
    pose[:3, 1] = camera_up
    pose[:3, 2] = -forward
    pose[:3, 3] = position
    return pose


def _marker_pose(centre: NDArray[np.float64], normal: NDArray[np.float64]) -> NDArray[np.float64]:
    """A marker flat on a wall, upright, facing ``normal`` into the room.

    The canonical marker frame is ``+x`` right across the face, ``+y`` toward the
    top, ``+z`` out of the face, so the columns are built to be right-handed with
    ``+y`` world up.
    """
    z_axis = normal / np.linalg.norm(normal)
    y_axis = np.array([0.0, 1.0, 0.0])
    x_axis = np.cross(y_axis, z_axis)
    x_axis /= np.linalg.norm(x_axis)

    pose = np.eye(4)
    pose[:3, 0] = x_axis
    pose[:3, 1] = y_axis
    pose[:3, 2] = z_axis
    pose[:3, 3] = centre
    return pose


def _ray_depths(spec: SynthSpec, pose: NDArray[np.float64]) -> NDArray[np.float32]:
    """Planar depth for every depth pixel, by intersecting the room box.

    Planar, not radial: the format stores distance along the optical axis, so the
    ray parameter is scaled by the ray's own z component.
    """
    fx = spec.focal_px * spec.depth_w / spec.colour_w
    fy = spec.focal_px * spec.depth_h / spec.colour_h
    cx = spec.depth_w / 2.0
    cy = spec.depth_h / 2.0

    us, vs = np.meshgrid(np.arange(spec.depth_w), np.arange(spec.depth_h))
    # Image y-down and z-forward to the ARKit camera's y-up, z-backward.
    dirs_cam = np.stack(
        [
            (us - cx) / fx,
            -(vs - cy) / fy,
            -np.ones_like(us, dtype=np.float64),
        ],
        axis=-1,
    )
    dirs_world = dirs_cam @ pose[:3, :3].T
    origin = pose[:3, 3]

    # Nearest positive intersection with any of the six planes.
    best = np.full(dirs_world.shape[:2], np.inf)
    planes = (
        (0, 0.0),
        (0, spec.width_m),
        (1, 0.0),
        (1, spec.height_m),
        (2, 0.0),
        (2, spec.depth_m),
    )
    for axis, value in planes:
        direction = dirs_world[..., axis]
        with np.errstate(divide="ignore", invalid="ignore"):
            t = (value - origin[axis]) / direction
        t = np.where(np.abs(direction) < 1e-9, np.inf, t)
        t = np.where(t > 1e-6, t, np.inf)

        # inf * 0 is NaN, so evaluate the hit point with a finite stand-in and
        # let the finiteness of t decide whether the plane was hit at all.
        finite = np.isfinite(t)
        point = origin + dirs_world * np.where(finite, t, 0.0)[..., None]
        inside = finite.copy()
        for other in (0, 1, 2):
            if other == axis:
                continue
            limit = (spec.width_m, spec.height_m, spec.depth_m)[other]
            inside &= (point[..., other] >= -1e-6) & (point[..., other] <= limit + 1e-6)
        best = np.where(inside & (t < best), t, best)

    # t is measured along a ray whose z component is -1 in camera axes, so the
    # planar depth is exactly t.
    depth = np.where(np.isfinite(best), best, 0.0)
    return depth.astype("<f4")


def _project(
    spec: SynthSpec, pose: NDArray[np.float64], points_w: NDArray[np.float64]
) -> NDArray[np.float64] | None:
    """Project world points into the image, or None if any is behind the camera."""
    world_from_camera = pose
    camera_from_world = np.linalg.inv(world_from_camera)
    homogeneous = np.hstack([points_w, np.ones((len(points_w), 1))])
    in_camera = homogeneous @ camera_from_world.T

    # ARKit camera looks down -z, so a visible point has negative z.
    z = -in_camera[:, 2]
    if np.any(z <= 1e-3):
        return None
    u = spec.focal_px * (in_camera[:, 0] / z) + spec.colour_w / 2.0
    v = spec.focal_px * (-in_camera[:, 1] / z) + spec.colour_h / 2.0
    return np.stack([u, v], axis=-1)


def _tag_corners_world(marker_pose: NDArray[np.float64]) -> NDArray[np.float64]:
    """The tag's four corners in the OpenCV order: TL, TR, BR, BL of the printed face."""
    half = TAG_SIZE_M / 2.0
    local = np.array(
        [
            [-half, half, 0.0],
            [half, half, 0.0],
            [half, -half, 0.0],
            [-half, -half, 0.0],
        ]
    )
    return (marker_pose[:3, :3] @ local.T).T + marker_pose[:3, 3]


def _render_frame(
    spec: SynthSpec,
    pose: NDArray[np.float64],
    marker_poses: dict[str, NDArray[np.float64]],
) -> tuple[NDArray[np.uint8], list[str]]:
    """A wall-coloured image with every visible tag warped into place."""
    image = np.full((spec.colour_h, spec.colour_w), 210, dtype=np.uint8)
    visible: list[str] = []

    for identifier, marker_pose in marker_poses.items():
        # Skip a marker the camera is behind: its face normal must point back.
        to_camera = pose[:3, 3] - marker_pose[:3, 3]
        if float(np.dot(to_camera, marker_pose[:3, 2])) <= 0.0:
            continue

        projected = _project(spec, pose, _tag_corners_world(marker_pose))
        if projected is None:
            continue
        if np.any(projected < -spec.colour_w) or np.any(projected > 2 * spec.colour_w):
            continue

        number = int(identifier[3:])
        bitmap = tag_bitmap(number, 400)
        source = np.array(
            [[0, 0], [400 - 1, 0], [400 - 1, 400 - 1], [0, 400 - 1]], dtype=np.float32
        )
        transform = cv2.getPerspectiveTransform(source, projected.astype(np.float32))
        warped = cv2.warpPerspective(
            bitmap,
            transform,
            (spec.colour_w, spec.colour_h),
            flags=cv2.INTER_NEAREST,
            borderMode=cv2.BORDER_CONSTANT,
            borderValue=0,
        )
        mask = cv2.warpPerspective(
            np.full((400, 400), 255, dtype=np.uint8),
            transform,
            (spec.colour_w, spec.colour_h),
            flags=cv2.INTER_NEAREST,
            borderMode=cv2.BORDER_CONSTANT,
            borderValue=0,
        )
        if not np.any(mask):
            continue
        image = np.where(mask > 0, warped, image)
        visible.append(identifier)

    return image, visible


def build(out: Path | str, spec: SynthSpec | None = None) -> SyntheticSession:
    """Write a synthetic session under ``out`` and return its ground truth."""
    spec = spec or SynthSpec()
    root = Path(out)
    for sub in ("rgb", "depth", "conf", "stills"):
        (root / sub).mkdir(parents=True, exist_ok=True)

    k = _intrinsics(spec)
    k_list = [float(v) for v in k.flatten()]
    cx_room, cz_room = spec.centre

    # Deliberately offset along each wall rather than sitting at the foot of the
    # perpendicular from the camera path. A marker at that foot is viewed exactly
    # head-on, and a fronto-parallel square is the worst case for PnP orientation:
    # the position is well constrained but the out-of-plane rotation barely is.
    # No real marker would be so conveniently placed, and a fixture built on that
    # one geometry would understate what the solver can do.
    marker_poses = {
        marker_id(spec.marker_numbers[0]): _marker_pose(
            np.array([cx_room + 0.9, 1.4, 0.0]), np.array([0.0, 0.0, 1.0])
        ),
        marker_id(spec.marker_numbers[1]): _marker_pose(
            np.array([0.0, 1.4, cz_room + 1.1]), np.array([1.0, 0.0, 0.0])
        ),
    }

    poses: list[NDArray[np.float64]] = []
    frame_rows: list[dict] = []
    marker_rows: list[dict] = []

    for i in range(spec.keyframes):
        fraction = i / spec.keyframes
        yaw = 2.0 * np.pi * fraction
        position = np.array(
            [
                cx_room + spec.path_radius_m * np.sin(yaw),
                spec.eye_height_m,
                cz_room - spec.path_radius_m * np.cos(yaw),
            ]
        )
        pose = _look_outward_pose(position, yaw)
        poses.append(pose)

        t = round(fraction * spec.duration_s, 4)
        stem = f"{i:06d}"

        image, visible = _render_frame(spec, pose, marker_poses)
        cv2.imwrite(str(root / "rgb" / f"{stem}.jpg"), image, [cv2.IMWRITE_JPEG_QUALITY, 92])

        depth = _ray_depths(spec, pose)
        (root / "depth" / f"{stem}.f32").write_bytes(depth.tobytes())
        confidence = np.where(depth > 0, 2, 0).astype(np.uint8)
        (root / "conf" / f"{stem}.u8").write_bytes(confidence.tobytes())

        frame_rows.append(
            {
                "i": i,
                "t": t,
                "T_wc": mat_to_cm(pose),
                "K": k_list,
                "w": spec.colour_w,
                "h": spec.colour_h,
                "dw": spec.depth_w,
                "dh": spec.depth_h,
                "exp_s": 0.0083,
                "exp_off": 0.0,
                "tracking": "normal",
                "reason": "none",
                "thermal": "nominal",
                "rgb": f"rgb/{stem}.jpg",
                "depth": f"depth/{stem}.f32",
                "conf": f"conf/{stem}.u8",
            }
        )

        for identifier in visible:
            # The app records the ARKit image-anchor transform. The anchor frame
            # has +z toward the bottom of the printed image and +y out of the
            # face, so it is the marker frame turned about its own x axis; the
            # pipeline undoes this with R_am. Writing it turned is what makes
            # --check-anchor-frame a real check rather than a tautology.
            anchor = marker_poses[identifier].copy()
            rotation = anchor[:3, :3].copy()
            anchor[:3, 1] = rotation[:, 2]
            anchor[:3, 2] = -rotation[:, 1]
            marker_rows.append(
                {
                    "t": t,
                    "i": i,
                    "marker_id": identifier,
                    "T_wa": mat_to_cm(anchor),
                    "tracked": True,
                    "physical_width_m": 0.20,
                }
            )

    landmarks = {
        "corner-nw": np.array([0.0, 0.0, 0.0]),
        "corner-ne": np.array([spec.width_m, 0.0, 0.0]),
        "corner-se": np.array([spec.width_m, 0.0, spec.depth_m]),
        "corner-sw": np.array([0.0, 0.0, spec.depth_m]),
    }
    landmark_rows = [
        {
            "t": round(0.5 * index, 3),
            "i": index,
            "label": label,
            "kind": "corner",
            "p_w": [float(v) for v in position],
            "method": "raycast-estimatedPlane",
        }
        for index, (label, position) in enumerate(landmarks.items())
    ]

    still_rows = []
    for s in range(spec.stills):
        pose = poses[min(s * 7, len(poses) - 1)]
        image, _ = _render_frame(spec, pose, marker_poses)
        cv2.imwrite(str(root / "stills" / f"{s:03d}.jpg"), image)
        still_rows.append(
            {
                "s": s,
                "i": min(s * 7, spec.keyframes - 1),
                "t": round(min(s * 7, spec.keyframes - 1) / spec.keyframes * spec.duration_s, 4),
                "T_wc": mat_to_cm(pose),
                "K": k_list,
                "w": spec.colour_w,
                "h": spec.colour_h,
                "exp_s": 0.0083,
                "exp_off": 0.0,
                "tracking": "normal",
                "reason": "none",
                "thermal": "nominal",
                "path": f"stills/{s:03d}.jpg",
            }
        )

    _write_jsonl(root / "frames.jsonl", frame_rows)
    _write_jsonl(root / "stills.jsonl", still_rows)
    _write_jsonl(root / "markers.jsonl", marker_rows)
    _write_jsonl(root / "landmarks.jsonl", landmark_rows)

    total_bytes = sum(p.stat().st_size for p in root.rglob("*") if p.is_file())
    manifest = {
        "format_version": 1,
        "session_id": root.name,
        "status": "complete",
        "project": {"slug": "synthetic", "name": "Synthetic"},
        "level": {"slug": "main", "name": "Main Floor", "index": 1},
        "room": {"slug": "room", "name": "Room"},
        "phase": "framing",
        "notes": "Generated by cadastre synth. Not a real capture.",
        "expected_markers": sorted(marker_poses),
        "device": {
            "model": "synthetic",
            "ios_version": "0",
            "app_version": "0.1.0",
            "app_build": "0",
        },
        "capture": {
            "started_at": "2026-11-03T14:15:02-05:00",
            "ended_at": "2026-11-03T14:15:17-05:00",
            "duration_s": spec.duration_s,
            "video_format": {"w": spec.colour_w, "h": spec.colour_h, "fps": 30},
            "keyframe_policy": {
                "min_dt_s": 0.1,
                "min_translation_m": 0.10,
                "min_rotation_deg": 5.0,
            },
            "depth": {
                "w": spec.depth_w,
                "h": spec.depth_h,
                "dtype": "float32",
                "units": "m",
            },
            "jpeg_quality": 0.92,
            "marker_physical_width_m": 0.20,
            "scene_reconstruction": "meshWithClassification",
        },
        "coordinate_frame": {
            "name": "arkit-session",
            "up": "+y",
            "units": "m",
            "matrix_order": "column-major",
        },
        "stats": {
            "keyframes": len(frame_rows),
            "dropped": 0,
            "stills": len(still_rows),
            "marker_observations": len(marker_rows),
            "landmarks": len(landmark_rows),
            "tracking_limited_s": 0.0,
            "thermal_max": "nominal",
            "bytes": total_bytes,
        },
    }
    (root / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")

    return SyntheticSession(
        root=root,
        spec=spec,
        poses=poses,
        marker_poses=marker_poses,
        landmarks=landmarks,
    )


def _write_jsonl(path: Path, rows: list[dict]) -> None:
    path.write_text(
        "".join(json.dumps(row, sort_keys=True) + "\n" for row in rows), encoding="utf-8"
    )
