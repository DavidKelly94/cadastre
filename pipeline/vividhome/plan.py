"""Architectural plans: rasterising them and calibrating them to house metres.

A calibrated plan is what turns a click on an image into a position in the house
frame, so `align` can pair a tapped room corner with a point on the drawing.

The mapping is the one in ``docs/design/system-design.md`` §4::

    [u]   [origin_u]   1/mpp · R(rotation) · [x]
    [v] = [origin_v] +                       [z]

Two things here are deliberately not browser work. The design has the owner click
points on a served page, and that page is still to come — but the arithmetic
behind it, and a way to drive it without a browser, live here. Keeping the
geometry out of the page means it can be tested, and means a plan can be
calibrated from a script or a saved set of points rather than only by hand.
"""

from __future__ import annotations

import json
import math
import shutil
from dataclasses import dataclass, field, replace
from pathlib import Path
from typing import Any

import cv2
import numpy as np
from numpy.typing import NDArray

__all__ = [
    "PlanCalibration",
    "PlanError",
    "add_plan",
    "calibrate",
    "correct_perspective",
    "house_to_plan",
    "load_calibration",
    "parse_distance",
    "plan_to_house",
    "save_calibration",
]


class PlanError(Exception):
    """A plan could not be added, read or calibrated."""


@dataclass(frozen=True)
class PlanCalibration:
    """``plans/<level>.json``.

    ``metres_per_pixel`` and ``origin_px`` are None until the level is calibrated;
    ``add_plan`` writes the stub so the file exists and says what is missing.
    """

    level: str
    image: str
    metres_per_pixel: float | None = None
    origin_px: tuple[float, float] | None = None
    rotation_deg: float = 0.0
    floor_height_m: float = 0.0
    #: Everything else in the file: the app's ``source`` and ``rooms`` (section
    #: 13), and whatever a later client adds. Section 12 says readers ignore
    #: unknown fields, but a writer that dropped them would make ``plan
    #: calibrate`` erase the owner's room placements on its way past, so they
    #: ride along and are written back untouched.
    extra: dict[str, Any] = field(default_factory=dict, compare=False)

    #: The fields this class models; anything else in the file is ``extra``.
    FIELDS = frozenset(
        {"level", "image", "metres_per_pixel", "origin_px", "rotation_deg", "floor_height_m"}
    )

    @property
    def is_calibrated(self) -> bool:
        return self.metres_per_pixel is not None and self.origin_px is not None

    def to_dict(self) -> dict:
        return {
            "level": self.level,
            "image": self.image,
            "metres_per_pixel": self.metres_per_pixel,
            "origin_px": list(self.origin_px) if self.origin_px else None,
            "rotation_deg": self.rotation_deg,
            "floor_height_m": self.floor_height_m,
            **{key: value for key, value in self.extra.items() if key not in self.FIELDS},
        }

    @classmethod
    def from_dict(cls, raw: dict) -> PlanCalibration:
        origin = raw.get("origin_px")
        return cls(
            level=str(raw["level"]),
            image=str(raw["image"]),
            metres_per_pixel=raw.get("metres_per_pixel"),
            origin_px=(float(origin[0]), float(origin[1])) if origin else None,
            rotation_deg=float(raw.get("rotation_deg", 0.0)),
            floor_height_m=float(raw.get("floor_height_m", 0.0)),
            extra={key: value for key, value in raw.items() if key not in cls.FIELDS},
        )


def plans_dir(store: str | Path) -> Path:
    return Path(store) / "plans"


def plan_paths(store: str | Path, level: str) -> tuple[Path, Path]:
    """The image and the calibration file for a level."""
    directory = plans_dir(store)
    return directory / f"{level}.png", directory / f"{level}.json"


def parse_distance(value: str) -> float:
    """Parse a real-world distance in metres or in feet and inches.

    The owner is measuring a house with a tape, so ``12' 6"`` has to work as well
    as ``3.81m``. A bare number is metres, because the rest of the system is
    metric and a silent unit change would be worse than a rejected input.
    """
    text = value.strip().lower().replace("’", "'").replace("”", '"').replace("″", '"')
    if not text:
        raise PlanError("empty distance")

    if text.endswith("mm"):
        return float(text[:-2]) / 1000.0
    if text.endswith("cm"):
        return float(text[:-2]) / 100.0
    if text.endswith("m"):
        return float(text[:-1])

    if "'" in text or '"' in text:
        feet = 0.0
        inches = 0.0
        if "'" in text:
            head, _, text = text.partition("'")
            feet = float(head) if head.strip() else 0.0
        rest = text.replace('"', "").strip()
        if rest:
            inches = float(rest)
        return feet * 0.3048 + inches * 0.0254

    try:
        return float(text)
    except ValueError as error:
        raise PlanError(f"cannot read {value!r} as a distance") from error


def add_plan(
    store: str | Path, source: str | Path, level: str, *, page: int = 1, dpi: int = 200
) -> PlanCalibration:
    """Rasterise a PDF page or copy an image into the store, with a stub calibration."""
    source = Path(source)
    if not source.exists():
        raise PlanError(f"{source}: no such file")

    image_path, json_path = plan_paths(store, level)
    image_path.parent.mkdir(parents=True, exist_ok=True)

    if source.suffix.lower() == ".pdf":
        _render_pdf(source, image_path, page=page, dpi=dpi)
    else:
        _copy_as_png(source, image_path)

    calibration = PlanCalibration(level=level, image=image_path.name)
    if json_path.exists():
        # Adding a new raster for a level that is already calibrated keeps the
        # calibration: the owner is usually replacing a scan of the same sheet.
        existing = load_calibration(store, level)
        calibration = replace(existing, image=image_path.name)
    save_calibration(store, calibration)
    return calibration


def _render_pdf(source: Path, target: Path, *, page: int, dpi: int) -> None:
    import pypdfium2

    document = pypdfium2.PdfDocument(str(source))
    try:
        if not 1 <= page <= len(document):
            raise PlanError(f"{source.name} has {len(document)} page(s); asked for page {page}")
        rendered = document[page - 1].render(scale=dpi / 72.0)
        rendered.to_pil().convert("RGB").save(target, "PNG")
    finally:
        document.close()


def _copy_as_png(source: Path, target: Path) -> None:
    if source.suffix.lower() == ".png":
        shutil.copyfile(source, target)
        return
    from PIL import Image

    try:
        with Image.open(source) as image:
            image.convert("RGB").save(target, "PNG")
    except OSError as error:
        raise PlanError(f"{source.name}: not an image this can read ({error})") from error


def load_calibration(store: str | Path, level: str) -> PlanCalibration:
    _, json_path = plan_paths(store, level)
    if not json_path.exists():
        raise PlanError(f"level {level!r} has no plan; run 'vividhome plan add' first")
    try:
        return PlanCalibration.from_dict(json.loads(json_path.read_text(encoding="utf-8")))
    except (json.JSONDecodeError, KeyError, TypeError) as error:
        raise PlanError(f"{json_path.name}: cannot read calibration ({error})") from error


def save_calibration(store: str | Path, calibration: PlanCalibration) -> Path:
    _, json_path = plan_paths(store, calibration.level)
    json_path.parent.mkdir(parents=True, exist_ok=True)
    json_path.write_text(json.dumps(calibration.to_dict(), indent=2), encoding="utf-8")
    return json_path


def _alignments_using(store: str | Path, level: str) -> list[Path]:
    """Alignment files that were solved against this level."""
    directory = Path(store) / "alignments"
    if not directory.is_dir():
        return []
    found = []
    for path in sorted(directory.glob("*.json")):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            continue
        if data.get("level") == level:
            found.append(path)
    return found


def calibrate(
    store: str | Path,
    level: str,
    *,
    point_a: tuple[float, float],
    point_b: tuple[float, float],
    distance_m: float,
    origin_px: tuple[float, float],
    rotation_deg: float = 0.0,
    floor_height_m: float = 0.0,
    force: bool = False,
) -> PlanCalibration:
    """Set the scale, origin and rotation for a level.

    ``point_a`` and ``point_b`` are two pixels the owner clicked on a known
    distance — a dimension string on the drawing, a wall they measured. The scale
    follows from the pixel distance between them.

    Recalibrating invalidates every alignment solved against this level, so it is
    refused while any exist unless ``force`` is set. Silently changing the scale
    under an alignment would move a session without anything saying so.
    """
    pixels = math.dist(point_a, point_b)
    if pixels <= 0:
        raise PlanError("the two scale points are the same pixel")
    if distance_m <= 0:
        raise PlanError(f"distance must be positive, got {distance_m}")

    existing = load_calibration(store, level)
    if existing.is_calibrated and not force:
        blocked = _alignments_using(store, level)
        if blocked:
            names = ", ".join(path.stem for path in blocked)
            raise PlanError(
                f"level {level!r} already has alignments ({names}); "
                "recalibrating invalidates them. Pass --force to do it anyway."
            )

    calibration = replace(
        existing,
        metres_per_pixel=distance_m / pixels,
        origin_px=(float(origin_px[0]), float(origin_px[1])),
        rotation_deg=float(rotation_deg),
        floor_height_m=float(floor_height_m),
    )
    save_calibration(store, calibration)
    return calibration


def _rotation(rotation_deg: float) -> NDArray[np.float64]:
    angle = math.radians(rotation_deg)
    c, s = math.cos(angle), math.sin(angle)
    return np.array([[c, -s], [s, c]])


def house_to_plan(calibration: PlanCalibration, x: float, z: float) -> tuple[float, float]:
    """House metres to plan pixels."""
    if not calibration.is_calibrated:
        raise PlanError(f"level {calibration.level!r} is not calibrated")
    origin = np.asarray(calibration.origin_px, dtype=float)
    pixel = origin + (_rotation(calibration.rotation_deg) @ np.array([x, z])) / (
        calibration.metres_per_pixel
    )
    return float(pixel[0]), float(pixel[1])


def plan_to_house(calibration: PlanCalibration, u: float, v: float) -> tuple[float, float]:
    """Plan pixels to house metres."""
    if not calibration.is_calibrated:
        raise PlanError(f"level {calibration.level!r} is not calibrated")
    origin = np.asarray(calibration.origin_px, dtype=float)
    offset = (np.array([u, v]) - origin) * calibration.metres_per_pixel
    house = _rotation(-calibration.rotation_deg) @ offset
    return float(house[0]), float(house[1])


def correct_perspective(
    source: str | Path,
    target: str | Path,
    corners: list[tuple[float, float]],
    *,
    output_size: tuple[int, int] | None = None,
) -> Path:
    """Rectify a photographed plan from its four sheet corners.

    ``corners`` are top-left, top-right, bottom-right, bottom-left as clicked on
    the photograph. The output keeps the mean width and height of the quad, so a
    plan photographed square comes back unchanged rather than being stretched to
    some arbitrary rectangle.
    """
    if len(corners) != 4:
        raise PlanError(f"expected 4 corners, got {len(corners)}")

    source = Path(source)
    image = cv2.imread(str(source))
    if image is None:
        raise PlanError(f"{source.name}: not an image this can read")

    quad = np.array(corners, dtype=np.float32)
    if output_size is None:
        width = round((np.linalg.norm(quad[1] - quad[0]) + np.linalg.norm(quad[2] - quad[3])) / 2)
        height = round((np.linalg.norm(quad[3] - quad[0]) + np.linalg.norm(quad[2] - quad[1])) / 2)
        output_size = (max(width, 1), max(height, 1))

    w, h = output_size
    destination = np.array([[0, 0], [w - 1, 0], [w - 1, h - 1], [0, h - 1]], dtype=np.float32)
    warped = cv2.warpPerspective(image, cv2.getPerspectiveTransform(quad, destination), (w, h))

    target = Path(target)
    target.parent.mkdir(parents=True, exist_ok=True)
    cv2.imwrite(str(target), warped)
    return target
