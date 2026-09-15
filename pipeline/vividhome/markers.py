"""Printed marker geometry, bitmaps, and the printable sheet.

One generator for everything that renders a tag: the printed PDF the owner tapes
to a stud, the PNGs the app bundles as ARKit reference images, and the tags the
synthetic session draws. A change to the dictionary or the border has to move all
three together, or the tests agree with themselves and disagree with the paper on
the wall.

The 20 cm marker is built from the inside out::

    12.8 cm  AprilTag 36h11, black border included
    + 1.6 cm quiet zone on each side, white
    + 2.0 cm noise ring on each side, deterministic from the id
    = 20.0 cm

The noise ring is what ARKit's image detection tracks. An AprilTag alone is poor
as a reference image — the family is designed for a detector that knows the
geometry, not for feature matching — so the ring supplies the dense, unrepeating
detail ``ARImageTrackingConfiguration`` needs, and seeding it from the id keeps
every marker distinguishable from every other one.
"""

from __future__ import annotations

from collections.abc import Sequence
from pathlib import Path

import cv2
import numpy as np
from numpy.typing import NDArray
from PIL import Image

__all__ = [
    "MARKER_WIDTH_M",
    "NOISE_RING_M",
    "PNG_PIXELS",
    "QUIET_ZONE_M",
    "TAG_DICTIONARY",
    "TAG_SIZE_M",
    "marker_id",
    "marker_image",
    "parse_ids",
    "tag_bitmap",
    "tag_number",
    "write_pdf",
    "write_pngs",
]

#: The printed marker is 20 cm square; the black AprilTag inside it is 12.8 cm.
#: Both numbers are physical and appear in the manifest and in PnP.
MARKER_WIDTH_M = 0.20
TAG_SIZE_M = 0.128

#: White margin between the tag and the noise ring.
QUIET_ZONE_M = 0.016

#: Outer ring of deterministic noise, for ARKit image detection.
NOISE_RING_M = 0.020

#: The PNG export is exactly 60 px/cm, so 20 cm is 1200 px and the app's
#: physicalWidth of 0.20 m is exact rather than rounded.
PNG_PIXELS = 1200

#: The AprilTag family the app and the pipeline agree on.
TAG_DICTIONARY = cv2.aruco.DICT_APRILTAG_36h11


def marker_id(number: int) -> str:
    """``12`` becomes ``VH-012``."""
    if not 0 <= number <= 999:
        raise ValueError(f"marker number out of range: {number}")
    return f"VH-{number:03d}"


def tag_number(value: str) -> int:
    """``VH-012`` becomes ``12``. Raises on anything else."""
    if len(value) != 6 or not value.startswith("VH-") or not value[3:].isdigit():
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


def parse_ids(spec: str) -> list[int]:
    """Parse ``0-59`` or ``3,7,12`` or a mixture into a sorted list of ids."""
    numbers: set[int] = set()
    for part in spec.replace(" ", "").split(","):
        if not part:
            continue
        if "-" in part.lstrip("-"):
            start, _, end = part.partition("-")
            first, last = int(start), int(end)
            if last < first:
                raise ValueError(f"range {part!r} runs backwards")
            numbers.update(range(first, last + 1))
        else:
            numbers.add(int(part))
    if not numbers:
        raise ValueError(f"no ids in {spec!r}")
    for number in numbers:
        if not 0 <= number <= 999:
            raise ValueError(f"marker number out of range: {number}")
    return sorted(numbers)


def _noise_ring(number: int, side_px: int, ring_px: int, block_px: int) -> NDArray[np.uint8]:
    """A deterministic blocky pattern filling the outer ring.

    Blocks rather than per-pixel noise: a printer and a phone camera both blur
    single pixels away, and a pattern that survives neither would be decoration.
    The seed is the marker id, so the sheet is reproducible and two markers never
    share a pattern.
    """
    generator = np.random.default_rng(seed=number)
    blocks = max(1, side_px // block_px)
    coarse = generator.integers(0, 2, size=(blocks, blocks), dtype=np.uint8) * 255
    pattern = np.kron(coarse, np.ones((block_px, block_px), dtype=np.uint8))[:side_px, :side_px]

    ring = np.full((side_px, side_px), 255, dtype=np.uint8)
    ring[:ring_px, :] = pattern[:ring_px, :]
    ring[-ring_px:, :] = pattern[-ring_px:, :]
    ring[:, :ring_px] = pattern[:, :ring_px]
    ring[:, -ring_px:] = pattern[:, -ring_px:]
    return ring


def marker_image(number: int, side_px: int = PNG_PIXELS) -> NDArray[np.uint8]:
    """The complete 20 cm marker as a single-channel image.

    Every band is sized from the physical dimensions, so the proportions hold at
    any resolution and the printed sheet and the bundled PNG are the same artwork.
    """
    if side_px < 200:
        raise ValueError(f"side_px too small for a legible marker: {side_px}")

    ring_px = round(side_px * NOISE_RING_M / MARKER_WIDTH_M)
    quiet_px = round(side_px * QUIET_ZONE_M / MARKER_WIDTH_M)
    tag_px = side_px - 2 * (ring_px + quiet_px)

    image = _noise_ring(number, side_px, ring_px, block_px=max(2, side_px // 100))
    offset = ring_px + quiet_px
    image[offset : offset + tag_px, offset : offset + tag_px] = tag_bitmap(number, tag_px)
    return image


def write_pngs(
    directory: str | Path, numbers: Sequence[int], side_px: int = PNG_PIXELS
) -> list[Path]:
    """Write ``VH-000.png`` and friends, the images the app bundles."""
    target = Path(directory)
    target.mkdir(parents=True, exist_ok=True)
    written = []
    for number in numbers:
        path = target / f"{marker_id(number)}.png"
        cv2.imwrite(str(path), marker_image(number, side_px))
        written.append(path)
    return written


def write_pdf(path: str | Path, numbers: Sequence[int], *, page_size: str = "letter") -> Path:
    """Write the printable sheet: one marker per page, at 100% scale.

    The square is placed by physical size in millimetres, so a page printed
    without scaling gives a marker that measures exactly 20 cm on a ruler. That
    measurement is the whole basis of the PnP solve, so anything that quietly
    scales it — "fit to page" in a print dialog — invalidates every pose.
    """
    from reportlab.lib.pagesizes import A4, LETTER
    from reportlab.lib.units import mm
    from reportlab.lib.utils import ImageReader
    from reportlab.pdfgen import canvas

    sizes = {"letter": LETTER, "a4": A4}
    if page_size.lower() not in sizes:
        raise ValueError(f"unknown page size {page_size!r}; use letter or a4")
    width, height = sizes[page_size.lower()]

    side_mm = MARKER_WIDTH_M * 1000.0
    if side_mm * mm > min(width, height):
        raise ValueError("the marker does not fit on this page size")

    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    pdf = canvas.Canvas(str(target), pagesize=(width, height))

    for number in numbers:
        identifier = marker_id(number)
        image = marker_image(number, PNG_PIXELS)
        reader = ImageReader(Image.fromarray(image).convert("RGB"))

        x = (width - side_mm * mm) / 2.0
        y = height - side_mm * mm - 20 * mm
        pdf.drawImage(reader, x, y, width=side_mm * mm, height=side_mm * mm)

        pdf.setFont("Helvetica-Bold", 36)
        pdf.drawCentredString(width / 2.0, y - 18 * mm, identifier)
        pdf.setFont("Helvetica", 9)
        pdf.drawCentredString(
            width / 2.0,
            y - 26 * mm,
            "Print at 100% (no scaling). The square must measure 200 mm on a ruler.",
        )
        pdf.showPage()

    pdf.save()
    return target
