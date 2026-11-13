"""The keyframes in 3D: every depth pixel placed in the house with its color.

Each keyframe holds a depth map, a photograph taken through the same lens and
the camera's position (sections 3 and 5). So each depth pixel is a point in
the room, and the photograph says what color it is. Put through the capture's
placement, the points of every keyframe land in the house, and merged on a
small grid they make a colored cloud of the room: what the photographs saw,
where they saw it.

This is ADR-0036's second look at a room, between the phone's gray scan and
splats. It needs no GPU. It is for looking at: a pipe is still found in a
photograph (ADR-0009).
"""

from __future__ import annotations

import numpy as np
from numpy.typing import NDArray

from .session import Session

#: The grid points are merged on. A depth pixel two meters away covers under
#: a centimeter, so this keeps most of what the sensor resolved.
VOXEL_M = 0.015
#: Section 3: confidence 0 is ignored for geometry. 2 is high.
MIN_CONFIDENCE = 2
#: Past this the sensor's depth is not worth drawing.
MAX_RANGE_M = 4.5
MIN_RANGE_M = 0.15
#: Per capture, so one long capture cannot make a page nothing can open.
LIMIT = 1_500_000

_BITS = 21
_OFFSET = 1 << (_BITS - 1)


def _keys(cells: NDArray[np.int64]) -> NDArray[np.int64]:
    """One number per grid cell, from its three integer coordinates."""
    shifted = cells + _OFFSET
    return (shifted[:, 0] << (2 * _BITS)) | (shifted[:, 1] << _BITS) | shifted[:, 2]


class _Cloud:
    """Points merged on a grid: per cell, the sums that give a mean."""

    def __init__(self, voxel_m: float):
        self.voxel = voxel_m
        self.keys = np.empty(0, dtype=np.int64)
        self.position = np.empty((0, 3), dtype=np.float64)
        self.color = np.empty((0, 3), dtype=np.float64)
        self.count = np.empty(0, dtype=np.float64)
        self._pending: list[tuple[NDArray, NDArray, NDArray, NDArray]] = []
        self._waiting = 0

    def add(self, points: NDArray[np.float64], colors: NDArray[np.float64]) -> None:
        if len(points) == 0:
            return
        keys = _keys(np.floor(points / self.voxel).astype(np.int64))
        self._pending.append((keys, points, colors, np.ones(len(points))))
        self._waiting += len(points)
        if self._waiting > 2_000_000:
            self._merge()

    def _merge(self) -> None:
        if not self._pending:
            return
        keys = np.concatenate([self.keys, *(entry[0] for entry in self._pending)])
        position = np.concatenate([self.position, *(entry[1] for entry in self._pending)])
        color = np.concatenate([self.color, *(entry[2] for entry in self._pending)])
        count = np.concatenate([self.count, *(entry[3] for entry in self._pending)])
        self._pending = []
        self._waiting = 0
        unique, inverse = np.unique(keys, return_inverse=True)
        size = len(unique)
        self.keys = unique
        self.count = np.bincount(inverse, weights=count, minlength=size)
        self.position = np.stack(
            [np.bincount(inverse, weights=position[:, axis], minlength=size) for axis in range(3)],
            axis=1,
        )
        self.color = np.stack(
            [np.bincount(inverse, weights=color[:, axis], minlength=size) for axis in range(3)],
            axis=1,
        )

    def result(self, limit: int) -> tuple[NDArray[np.float32], NDArray[np.uint8]]:
        self._merge()
        if len(self.keys) == 0:
            return np.empty((0, 3), dtype=np.float32), np.empty((0, 3), dtype=np.uint8)
        # Sums throughout: a new point is a sum of one, and a cell merged a
        # second time adds its sum and its count, so the mean is never taken
        # of means.
        position = self.position / self.count[:, None]
        color = self.color / self.count[:, None]
        if len(position) > limit:
            keep = np.linspace(0, len(position) - 1, limit).astype(np.int64)
            position, color = position[keep], color[keep]
        return position.astype(np.float32), np.clip(color + 0.5, 0, 255).astype(np.uint8)


def frame_points(
    session: Session,
    frame,
    *,
    min_confidence: int = MIN_CONFIDENCE,
    max_range_m: float = MAX_RANGE_M,
) -> tuple[NDArray[np.float64], NDArray[np.float64]]:
    """One keyframe's valid depth pixels as points in the session frame, with
    the photograph's color at each. Empty when a file is missing or unreadable.
    """
    from PIL import Image

    empty = (np.empty((0, 3)), np.empty((0, 3)))
    depth_path = session.resolve(frame.depth)
    conf_path = session.resolve(frame.conf)
    rgb_path = session.resolve(frame.rgb)
    if not (depth_path.exists() and rgb_path.exists()):
        return empty
    dw, dh = int(frame.dw), int(frame.dh)
    depth = np.fromfile(depth_path, dtype="<f4")
    if depth.size != dw * dh:
        return empty
    depth = depth.reshape(dh, dw).astype(np.float64)
    valid = np.isfinite(depth) & (depth > MIN_RANGE_M) & (depth <= max_range_m)
    if conf_path.exists():
        confidence = np.fromfile(conf_path, dtype=np.uint8)
        if confidence.size == dw * dh:
            valid &= confidence.reshape(dh, dw) >= min_confidence
    if not valid.any():
        return empty

    try:
        with Image.open(rgb_path) as image:
            # Let the JPEG decoder shrink it on the way in: the photograph is
            # only needed at the depth map's size.
            image.draft("RGB", (dw * 2, dh * 2))
            colors = np.asarray(image.convert("RGB").resize((dw, dh)), dtype=np.float64)
    except OSError:
        return empty

    # Section 3: depth intrinsics are K scaled to the depth map, depth is
    # planar, image v runs down, and the ARKit camera looks down its own -z
    # with +y up.
    fx = frame.K[0, 0] * dw / frame.w
    fy = frame.K[1, 1] * dh / frame.h
    cx = frame.K[0, 2] * dw / frame.w
    cy = frame.K[1, 2] * dh / frame.h
    vs, us = np.nonzero(valid)
    d = depth[vs, us]
    camera = np.stack([(us - cx) / fx * d, -(vs - cy) / fy * d, -d], axis=1)
    world = camera @ frame.T_wc[:3, :3].T + frame.T_wc[:3, 3]
    return world, colors[vs, us]


def session_points(
    session: Session,
    t_hs: NDArray[np.float64],
    *,
    voxel_m: float = VOXEL_M,
    min_confidence: int = MIN_CONFIDENCE,
    max_range_m: float = MAX_RANGE_M,
    stride: int = 1,
    limit: int = LIMIT,
) -> tuple[NDArray[np.float32], NDArray[np.uint8]]:
    """A capture's colored points in house coordinates: ``(N, 3)`` float32
    positions and ``(N, 3)`` uint8 colors, one per ``voxel_m`` grid cell that
    any keyframe's depth landed in, colored by the mean of what landed there.
    """
    cloud = _Cloud(voxel_m)
    rotation, shift = t_hs[:3, :3], t_hs[:3, 3]
    for number, frame in enumerate(session.frames()):
        if number % max(1, stride):
            continue
        world, colors = frame_points(
            session, frame, min_confidence=min_confidence, max_range_m=max_range_m
        )
        if len(world):
            cloud.add(world @ rotation.T + shift, colors)
    return cloud.result(limit)
