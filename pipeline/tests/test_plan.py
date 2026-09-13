"""Plans: rasterising, the metres-to-pixels mapping, and the recalibration guard."""

from __future__ import annotations

import json
import math
from pathlib import Path

import cv2
import numpy as np
import pytest
from PIL import Image

from cadastre.plan import (
    PlanCalibration,
    PlanError,
    add_plan,
    calibrate,
    correct_perspective,
    house_to_plan,
    load_calibration,
    parse_distance,
    plan_paths,
    plan_to_house,
)


@pytest.fixture
def store(tmp_path: Path) -> Path:
    return tmp_path / "cadastre-data"


def make_png(path: Path, size=(400, 300)) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.new("RGB", size, (255, 255, 255)).save(path, "PNG")
    return path


def make_pdf(path: Path, pages: int = 2) -> Path:
    from reportlab.lib.pagesizes import letter
    from reportlab.pdfgen import canvas

    path.parent.mkdir(parents=True, exist_ok=True)
    pdf = canvas.Canvas(str(path), pagesize=letter)
    for index in range(pages):
        pdf.drawString(100, 700, f"page {index + 1}")
        pdf.showPage()
    pdf.save()
    return path


def calibrated(store: Path, level: str = "main", **kwargs) -> PlanCalibration:
    add_plan(store, make_png(store.parent / "src.png"), level)
    defaults = {
        "point_a": (100.0, 100.0),
        "point_b": (300.0, 100.0),  # 200 px
        "distance_m": 4.0,  # so 0.02 m/px
        "origin_px": (100.0, 100.0),
    }
    return calibrate(store, level, **{**defaults, **kwargs})


# Distances


@pytest.mark.parametrize(
    ("text", "metres"),
    [
        ("3.81m", 3.81),
        ("381cm", 3.81),
        ("3810mm", 3.81),
        ("3.81", 3.81),
        ("12' 6\"", 3.8100),
        ("12'", 3.6576),
        ('6"', 0.1524),
        ("  2.5 m ".replace(" m", "m").strip(), 2.5),
    ],
)
def test_parse_distance(text: str, metres: float):
    assert parse_distance(text) == pytest.approx(metres, abs=1e-4)


def test_parse_distance_rejects_nonsense():
    for bad in ["", "   ", "about three metres", "m"]:
        with pytest.raises((PlanError, ValueError)):
            parse_distance(bad)


# Adding


def test_add_png_writes_the_raster_and_a_stub_calibration(store: Path):
    result = add_plan(store, make_png(store.parent / "plan.png"), "main")
    image_path, json_path = plan_paths(store, "main")
    assert image_path.exists()
    assert json_path.exists()
    assert not result.is_calibrated

    stored = json.loads(json_path.read_text(encoding="utf-8"))
    assert stored["level"] == "main"
    assert stored["metres_per_pixel"] is None
    assert stored["origin_px"] is None
    assert stored["rotation_deg"] == 0
    assert stored["floor_height_m"] == 0


def test_add_converts_a_jpeg_to_png(store: Path, tmp_path: Path):
    source = tmp_path / "plan.jpg"
    Image.new("RGB", (120, 90), (200, 200, 200)).save(source, "JPEG")
    add_plan(store, source, "upper")
    image_path, _ = plan_paths(store, "upper")
    with Image.open(image_path) as image:
        assert image.format == "PNG"
        assert image.size == (120, 90)


def test_add_rasterises_a_pdf_page_at_the_requested_dpi(store: Path, tmp_path: Path):
    source = make_pdf(tmp_path / "plans.pdf", pages=2)
    add_plan(store, source, "main", page=1, dpi=100)
    image_path, _ = plan_paths(store, "main")
    with Image.open(image_path) as image:
        # US Letter is 8.5 x 11 inches, so 100 dpi is about 850 x 1100.
        assert image.size[0] == pytest.approx(850, abs=4)
        assert image.size[1] == pytest.approx(1100, abs=4)


def test_add_rejects_a_page_that_does_not_exist(store: Path, tmp_path: Path):
    source = make_pdf(tmp_path / "plans.pdf", pages=2)
    with pytest.raises(PlanError, match="page 5"):
        add_plan(store, source, "main", page=5)


def test_add_rejects_a_missing_file(store: Path, tmp_path: Path):
    with pytest.raises(PlanError, match="no such file"):
        add_plan(store, tmp_path / "nope.png", "main")


def test_replacing_the_raster_keeps_an_existing_calibration(store: Path):
    before = calibrated(store)
    after = add_plan(store, make_png(store.parent / "rescan.png"), "main")
    assert after.is_calibrated
    assert after.metres_per_pixel == before.metres_per_pixel
    assert after.origin_px == before.origin_px


# Calibration and the mapping


def test_calibration_scale_comes_from_the_clicked_points(store: Path):
    result = calibrated(store)
    assert result.metres_per_pixel == pytest.approx(4.0 / 200.0)
    assert result.is_calibrated


def test_the_origin_pixel_is_the_house_origin(store: Path):
    result = calibrated(store)
    assert plan_to_house(result, 100.0, 100.0) == pytest.approx((0.0, 0.0))
    assert house_to_plan(result, 0.0, 0.0) == pytest.approx((100.0, 100.0))


def test_house_and_plan_round_trip(store: Path):
    for rotation in (0.0, 17.5, -90.0, 180.0):
        result = calibrated(store, rotation_deg=rotation, force=True)
        for x, z in [(0.0, 0.0), (3.0, -2.5), (-1.25, 7.75)]:
            u, v = house_to_plan(result, x, z)
            back = plan_to_house(result, u, v)
            assert back == pytest.approx((x, z), abs=1e-9)


def test_distance_is_preserved_by_the_mapping(store: Path):
    result = calibrated(store, rotation_deg=31.0, force=True)
    a = house_to_plan(result, 0.0, 0.0)
    b = house_to_plan(result, 3.0, 4.0)
    pixels = math.dist(a, b)
    assert pixels * result.metres_per_pixel == pytest.approx(5.0, abs=1e-9)


def test_an_uncalibrated_level_cannot_be_mapped(store: Path):
    add_plan(store, make_png(store.parent / "plan.png"), "main")
    stub = load_calibration(store, "main")
    with pytest.raises(PlanError, match="not calibrated"):
        house_to_plan(stub, 1.0, 1.0)
    with pytest.raises(PlanError, match="not calibrated"):
        plan_to_house(stub, 1.0, 1.0)


def test_calibrate_rejects_degenerate_input(store: Path):
    add_plan(store, make_png(store.parent / "plan.png"), "main")
    with pytest.raises(PlanError, match="same pixel"):
        calibrate(
            store,
            "main",
            point_a=(10.0, 10.0),
            point_b=(10.0, 10.0),
            distance_m=1.0,
            origin_px=(0.0, 0.0),
        )
    with pytest.raises(PlanError, match="must be positive"):
        calibrate(
            store,
            "main",
            point_a=(10.0, 10.0),
            point_b=(20.0, 10.0),
            distance_m=0.0,
            origin_px=(0.0, 0.0),
        )


def test_a_level_without_a_plan_cannot_be_loaded(store: Path):
    with pytest.raises(PlanError, match="run 'cadastre plan add'"):
        load_calibration(store, "basement")


# The recalibration guard


def _write_alignment(store: Path, session_id: str, level: str) -> None:
    directory = store / "alignments"
    directory.mkdir(parents=True, exist_ok=True)
    (directory / f"{session_id}.json").write_text(
        json.dumps({"session_id": session_id, "level": level}), encoding="utf-8"
    )


def test_recalibration_is_refused_once_alignments_exist(store: Path):
    calibrated(store)
    _write_alignment(store, "20261103-141502_main_kitchen_electrical_k3x7qa", "main")

    with pytest.raises(PlanError, match="already has alignments"):
        calibrated(store)


def test_force_allows_recalibration(store: Path):
    calibrated(store)
    _write_alignment(store, "session-a", "main")
    result = calibrated(store, distance_m=8.0, force=True)
    assert result.metres_per_pixel == pytest.approx(8.0 / 200.0)


def test_an_alignment_for_another_level_does_not_block(store: Path):
    calibrated(store)
    _write_alignment(store, "session-a", "upper")
    assert calibrated(store, distance_m=6.0).metres_per_pixel == pytest.approx(6.0 / 200.0)


def test_first_calibration_is_never_blocked(store: Path):
    add_plan(store, make_png(store.parent / "plan.png"), "main")
    _write_alignment(store, "session-a", "main")
    # Nothing was calibrated yet, so there is nothing to invalidate.
    assert calibrated(store).is_calibrated


# Perspective correction


def test_perspective_correction_rectifies_a_known_quad(tmp_path: Path):
    # A white rectangle drawn as a skewed quad comes back square.
    source = tmp_path / "photo.png"
    canvas = np.zeros((400, 400, 3), dtype=np.uint8)
    quad = np.array([[60, 40], [340, 90], [320, 350], [80, 300]], dtype=np.int32)
    cv2.fillPoly(canvas, [quad], (255, 255, 255))
    cv2.imwrite(str(source), canvas)

    target = correct_perspective(
        source, tmp_path / "flat.png", [tuple(map(float, p)) for p in quad]
    )
    result = cv2.imread(str(target), cv2.IMREAD_GRAYSCALE)
    # After rectifying, the sheet fills the frame: the corners are white too.
    assert result[2, 2] > 200
    assert result[-3, -3] > 200
    assert float(np.mean(result > 200)) > 0.95


def test_perspective_correction_needs_four_corners(tmp_path: Path):
    source = make_png(tmp_path / "photo.png")
    with pytest.raises(PlanError, match="expected 4 corners"):
        correct_perspective(source, tmp_path / "out.png", [(0.0, 0.0), (1.0, 1.0)])


def test_perspective_correction_rejects_a_non_image(tmp_path: Path):
    bad = tmp_path / "not-an-image.png"
    bad.write_bytes(b"nope")
    with pytest.raises(PlanError, match="not an image"):
        correct_perspective(bad, tmp_path / "out.png", [(0.0, 0.0)] * 4)
