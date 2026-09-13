"""Coordinate conversions shared by every pipeline command.

The conventions all come from ``docs/session-format.md`` §3 and
``docs/design/system-design.md`` §4. They are gathered here so no other module
repeats a sign or an axis order.

Two storage orders sit side by side in a session file and must not be confused:
a 4x4 transform is 16 numbers in **column-major** order, while ``K`` is 9 numbers
in **row-major** order.
"""

from __future__ import annotations

from collections.abc import Sequence

import numpy as np
from numpy.typing import NDArray

__all__ = [
    "ARKIT_TO_CV",
    "K_from_list",
    "arkit_to_cv",
    "embed_se2",
    "mat_from_cm",
    "mat_to_cm",
    "se2_to_mat",
    "theta_from_se2",
    "umeyama_2d",
    "unproject",
]

#: Diagonal that maps the ARKit camera (x right, y up, z backward) to the OpenCV
#: camera (x right, y down, z forward). It is its own inverse.
ARKIT_TO_CV = np.diag([1.0, -1.0, -1.0, 1.0])


def mat_from_cm(values: Sequence[float]) -> NDArray[np.float64]:
    """Build a 4x4 from the 16 column-major numbers stored in a session file."""
    array = np.asarray(values, dtype=np.float64)
    if array.size != 16:
        raise ValueError(f"expected 16 numbers in column-major order, got {array.size}")
    return array.reshape(4, 4, order="F")


def mat_to_cm(matrix: NDArray[np.float64]) -> list[float]:
    """Flatten a 4x4 back to the 16 column-major numbers the format stores."""
    array = np.asarray(matrix, dtype=np.float64)
    if array.shape != (4, 4):
        raise ValueError(f"expected a 4x4 matrix, got shape {array.shape}")
    return array.flatten(order="F").tolist()


def K_from_list(values: Sequence[float]) -> NDArray[np.float64]:
    """Build the 3x3 intrinsics from the 9 row-major numbers stored in a frame."""
    array = np.asarray(values, dtype=np.float64)
    if array.size != 9:
        raise ValueError(f"expected 9 numbers in row-major order, got {array.size}")
    return array.reshape(3, 3)


def arkit_to_cv(t_wc: NDArray[np.float64]) -> NDArray[np.float64]:
    """Convert an ARKit camera-to-world pose to OpenCV camera axes.

    ``T_wc_cv = T_wc @ diag(1, -1, -1, 1)``. Use this whenever a pose from
    ``cv2.solvePnP`` has to be moved into the session frame:
    ``T_w_obj = arkit_to_cv(T_wc) @ T_c_obj``.
    """
    return np.asarray(t_wc, dtype=np.float64) @ ARKIT_TO_CV


def unproject(u: float, v: float, d: float, k: NDArray[np.float64]) -> NDArray[np.float64]:
    """Un-project a colour pixel to a point in ARKit camera coordinates.

    ``(u, v)`` has its origin at the top left with ``v`` increasing downwards, and
    ``d`` is planar depth in metres. The ``-Y, -d`` flips convert the image's
    y-down, z-forward convention to the ARKit camera's y-up, z-backward one.
    """
    fx, fy = k[0, 0], k[1, 1]
    cx, cy = k[0, 2], k[1, 2]
    x = (u - cx) / fx * d
    y = (v - cy) / fy * d
    return np.array([x, -y, -d], dtype=np.float64)


def se2_to_mat(theta: float, tx: float, ty: float, tz: float) -> NDArray[np.float64]:
    """Build the 4x4 ``T_hs`` for a yaw about ``+y`` and a translation.

    The layout is fixed by ``docs/design/system-design.md`` §4::

        [ cos t   0   sin t   tx ]
        [   0     1     0     ty ]
        [ -sin t  0   cos t   tz ]
        [   0     0     0      1 ]
    """
    c = np.cos(theta)
    s = np.sin(theta)
    return np.array(
        [
            [c, 0.0, s, tx],
            [0.0, 1.0, 0.0, ty],
            [-s, 0.0, c, tz],
            [0.0, 0.0, 0.0, 1.0],
        ],
        dtype=np.float64,
    )


def embed_se2(
    rotation: NDArray[np.float64], translation: NDArray[np.float64], ty: float = 0.0
) -> NDArray[np.float64]:
    """Embed a horizontal 2D rotation and translation into a 4x4 ``T_hs``.

    ``rotation`` is the 2x2 acting on ``(x, z)`` and ``translation`` the matching
    ``(t_x, t_z)``, as returned by :func:`umeyama_2d`. They go into rows and
    columns 0 and 2, which is what makes the result agree with
    :func:`se2_to_mat` without anyone having to extract an angle first.
    """
    rotation = np.asarray(rotation, dtype=np.float64)
    translation = np.asarray(translation, dtype=np.float64)
    if rotation.shape != (2, 2):
        raise ValueError(f"expected a 2x2 rotation, got shape {rotation.shape}")
    if translation.shape != (2,):
        raise ValueError(f"expected 2 translation components, got shape {translation.shape}")

    matrix = np.eye(4, dtype=np.float64)
    matrix[0, 0] = rotation[0, 0]
    matrix[0, 2] = rotation[0, 1]
    matrix[2, 0] = rotation[1, 0]
    matrix[2, 2] = rotation[1, 1]
    matrix[0, 3] = translation[0]
    matrix[1, 3] = ty
    matrix[2, 3] = translation[1]
    return matrix


def theta_from_se2(matrix: NDArray[np.float64]) -> float:
    """Recover the yaw from a ``T_hs`` built by :func:`se2_to_mat` or :func:`embed_se2`.

    With the layout above, ``sin t`` is at ``[0, 2]`` and ``cos t`` at ``[0, 0]``.
    Note the sign: reading ``[2, 0]`` instead, as an angle-from-rotation formula
    written for an ``(x, y)`` plane would, returns ``-theta``.
    """
    return float(np.arctan2(matrix[0, 2], matrix[0, 0]))


def umeyama_2d(
    a: NDArray[np.float64], b: NDArray[np.float64]
) -> tuple[NDArray[np.float64], NDArray[np.float64], float]:
    """Least-squares rigid 2D fit taking points ``a`` onto points ``b``.

    Both are ``(n, 2)`` arrays of horizontal ``(x, z)`` coordinates: ``a`` in the
    session frame, ``b`` in the house frame. Returns the 2x2 rotation, the
    2-vector translation and the RMS residual in metres.

    Rotation only, no scale: the phone's own scale is metric, so a fitted scale
    would absorb real error instead of reporting it. The reflection guard keeps
    the result a rotation when the correspondences are nearly collinear.
    """
    a = np.asarray(a, dtype=np.float64)
    b = np.asarray(b, dtype=np.float64)
    if a.shape != b.shape:
        raise ValueError(f"point sets must have the same shape, got {a.shape} and {b.shape}")
    if a.ndim != 2 or a.shape[1] != 2:
        raise ValueError(f"expected (n, 2) arrays, got shape {a.shape}")
    if a.shape[0] < 2:
        raise ValueError("at least two correspondences are required")

    centroid_a = a.mean(axis=0)
    centroid_b = b.mean(axis=0)
    a0 = a - centroid_a
    b0 = b - centroid_b

    h = a0.T @ b0
    u, _, vt = np.linalg.svd(h)
    d = np.sign(np.linalg.det(vt.T @ u.T))
    rotation = vt.T @ np.diag([1.0, d]) @ u.T
    translation = centroid_b - rotation @ centroid_a

    residuals = b - (a @ rotation.T + translation)
    rms = float(np.sqrt(np.mean(np.sum(residuals**2, axis=1))))
    return rotation, translation, rms
