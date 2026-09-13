"""Printed marker geometry and bitmaps.

The full PDF and PNG generation lands with the ``markers`` command. What is here
now is the piece more than one module needs: the AprilTag bitmap itself.

It lives here rather than in ``synth`` because the design is explicit that the
bundled PNGs, the printed sheet and anything that renders a tag must come from
one generator. If the synthetic session drew its own tags, a change to the
dictionary or the border would make the tests agree with themselves and disagree
with the paper on the wall.
"""

from __future__ import annotations

import cv2
import numpy as np
from numpy.typing import NDArray

__all__ = [
    "MARKER_WIDTH_M",
    "TAG_DICTIONARY",
    "TAG_SIZE_M",
    "marker_id",
    "tag_bitmap",
    "tag_number",
]

#: The printed marker is 20 cm square; the black AprilTag inside it is 12.8 cm.
#: Both numbers are physical and appear in the manifest and in PnP.
MARKER_WIDTH_M = 0.20
TAG_SIZE_M = 0.128

#: The AprilTag family the app and the pipeline agree on.
TAG_DICTIONARY = cv2.aruco.DICT_APRILTAG_36h11


def marker_id(number: int) -> str:
    """``12`` becomes ``CD-012``."""
    if not 0 <= number <= 999:
        raise ValueError(f"marker number out of range: {number}")
    return f"CD-{number:03d}"


def tag_number(value: str) -> int:
    """``CD-012`` becomes ``12``. Raises on anything else."""
    if len(value) != 6 or not value.startswith("CD-") or not value[3:].isdigit():
        raise ValueError(f"not a marker id: {value!r}")
    return int(value[3:])


def tag_bitmap(number: int, side_px: int = 400) -> NDArray[np.uint8]:
    """The AprilTag bitmap for a marker, as a single-channel image.

    The returned square is the 12.8 cm black tag, border included. It carries no
    quiet zone: whatever it is drawn onto supplies that, exactly as the white
    margin around the printed marker does.
    """
    if side_px < 8:
        raise ValueError(f"side_px too small to hold a 36h11 tag: {side_px}")
    dictionary = cv2.aruco.getPredefinedDictionary(TAG_DICTIONARY)
    return cv2.aruco.generateImageMarker(dictionary, number, side_px)
