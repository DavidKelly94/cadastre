"""The printed marker is a physical object the poses depend on, so the tests are
about dimensions and decodability, not about the file appearing."""

from __future__ import annotations

from pathlib import Path

import cv2
import numpy as np
import pytest

from vividhome.markers import (
    MARKER_WIDTH_M,
    NOISE_RING_M,
    PNG_PIXELS,
    QUIET_ZONE_M,
    TAG_SIZE_M,
    marker_id,
    marker_image,
    parse_ids,
    tag_number,
    write_pdf,
    write_pngs,
)


def detector() -> cv2.aruco.ArucoDetector:
    return cv2.aruco.ArucoDetector(cv2.aruco.getPredefinedDictionary(cv2.aruco.DICT_APRILTAG_36h11))


def ring_mask(side: int) -> np.ndarray:
    thickness = round(side * NOISE_RING_M / MARKER_WIDTH_M)
    mask = np.zeros((side, side), dtype=bool)
    mask[:thickness, :] = mask[-thickness:, :] = True
    mask[:, :thickness] = mask[:, -thickness:] = True
    return mask


def test_the_bands_add_up_to_the_printed_width():
    assert TAG_SIZE_M + 2 * QUIET_ZONE_M + 2 * NOISE_RING_M == pytest.approx(MARKER_WIDTH_M)


def test_the_png_is_exactly_sixty_pixels_per_centimetre():
    # The app's physicalWidth of 0.20 m has to be exact, not rounded.
    assert PNG_PIXELS / (MARKER_WIDTH_M * 100) == 60.0
    assert marker_image(0).shape == (PNG_PIXELS, PNG_PIXELS)


def test_the_tag_occupies_the_documented_fraction_of_the_square():
    image = marker_image(7)
    corners, ids, _ = detector().detectMarkers(image)
    assert ids is not None and int(ids.flatten()[0]) == 7

    side = float(np.linalg.norm(corners[0][0][0] - corners[0][0][1]))
    expected = PNG_PIXELS * TAG_SIZE_M / MARKER_WIDTH_M
    assert side == pytest.approx(expected, rel=0.01)


@pytest.mark.parametrize("number", [0, 12, 17, 59])
def test_every_generated_marker_decodes_as_itself(number: int):
    _, ids, _ = detector().detectMarkers(marker_image(number))
    assert ids is not None
    assert sorted(int(i) for i in ids.flatten()) == [number]


def test_it_still_decodes_when_the_camera_sees_it_small():
    """A marker photographed across a room is only a few hundred pixels."""
    image = marker_image(31)
    for side in (400, 200, 120):
        small = cv2.resize(image, (side, side), interpolation=cv2.INTER_AREA)
        _, ids, _ = detector().detectMarkers(small)
        assert ids is not None, f"failed to decode at {side} px"
        assert int(ids.flatten()[0]) == 31


def test_the_quiet_zone_is_actually_quiet():
    """AprilTag needs white around the black border, or detection degrades."""
    image = marker_image(5)
    ring = round(PNG_PIXELS * NOISE_RING_M / MARKER_WIDTH_M)
    quiet = round(PNG_PIXELS * QUIET_ZONE_M / MARKER_WIDTH_M)
    # A horizontal slice through the quiet band, just inside the noise ring.
    row = image[ring + quiet // 2, ring : PNG_PIXELS - ring]
    assert row.min() == 255


def test_the_noise_ring_is_dense_and_unique_per_marker():
    a, b = marker_image(12, 400), marker_image(13, 400)
    mask = ring_mask(400)
    assert not np.array_equal(a[mask], b[mask]), "two markers must not share a pattern"
    # Roughly half dark: a ring that is nearly blank gives ARKit nothing to track.
    assert 0.3 < float((a[mask] < 128).mean()) < 0.7


def test_the_noise_ring_is_deterministic():
    """The sheet must be reproducible: a reprint has to match what is on the wall."""
    assert np.array_equal(marker_image(23, 600), marker_image(23, 600))


def test_proportions_hold_at_any_resolution():
    for side in (400, 800, PNG_PIXELS):
        image = marker_image(9, side)
        assert image.shape == (side, side)
        corners, ids, _ = detector().detectMarkers(image)
        assert ids is not None, side
        measured = float(np.linalg.norm(corners[0][0][0] - corners[0][0][1]))
        assert measured / side == pytest.approx(TAG_SIZE_M / MARKER_WIDTH_M, rel=0.02)


def test_a_marker_too_small_to_be_legible_is_refused():
    with pytest.raises(ValueError, match="too small"):
        marker_image(0, 64)


# Ids


def test_marker_ids_round_trip():
    assert marker_id(17) == "VH-017"
    assert tag_number("VH-017") == 17
    with pytest.raises(ValueError, match="not a marker id"):
        tag_number("IG-017")


@pytest.mark.parametrize(
    ("spec", "expected"),
    [
        ("0-3", [0, 1, 2, 3]),
        ("3,7,12", [3, 7, 12]),
        ("0-2,10", [0, 1, 2, 10]),
        ("5", [5]),
        ("2-2", [2]),
    ],
)
def test_parse_ids(spec: str, expected: list[int]):
    assert parse_ids(spec) == expected


def test_parse_ids_rejects_nonsense():
    for bad in ["", "5-2", "1000", "abc"]:
        with pytest.raises(ValueError):
            parse_ids(bad)


# Output files


def test_write_pngs_names_files_by_marker_id(tmp_path: Path):
    written = write_pngs(tmp_path / "Markers", [0, 12])
    assert [p.name for p in written] == ["VH-000.png", "VH-012.png"]
    for path in written:
        image = cv2.imread(str(path), cv2.IMREAD_GRAYSCALE)
        assert image.shape == (PNG_PIXELS, PNG_PIXELS)
        _, ids, _ = detector().detectMarkers(image)
        assert ids is not None


def test_write_pdf_produces_one_page_per_marker(tmp_path: Path):
    import pypdfium2

    target = write_pdf(tmp_path / "markers.pdf", [0, 1, 2])
    assert target.exists()

    document = pypdfium2.PdfDocument(str(target))
    try:
        assert len(document) == 3
        page = document[0]
        # US Letter in points, so the marker's physical size can be checked.
        assert page.get_width() == pytest.approx(612, abs=1)
        assert page.get_height() == pytest.approx(792, abs=1)
    finally:
        document.close()


def test_the_pdf_marker_measures_two_hundred_millimetres(tmp_path: Path):
    """Printed at 100%, the square must be 200 mm: PnP depends on it."""
    import pypdfium2

    target = write_pdf(tmp_path / "one.pdf", [12])
    document = pypdfium2.PdfDocument(str(target))
    try:
        # pypdfium2's scale is pixels per PDF point, and a point is 1/72 inch,
        # so pixels per millimetre is scale * 72 / 25.4.
        scale = 2.0
        pixels_per_mm = scale * 72 / 25.4
        image = np.array(document[0].render(scale=scale).to_pil().convert("L"))
    finally:
        document.close()

    dark_cols = np.where((image < 200).any(axis=0))[0]
    dark_rows = np.where((image < 200).any(axis=1))[0]
    assert dark_cols.size and dark_rows.size

    width_mm = (dark_cols[-1] - dark_cols[0] + 1) / pixels_per_mm
    assert width_mm == pytest.approx(200, abs=1.0), f"printed square is {width_mm:.1f} mm"


def test_a4_is_supported_and_an_unknown_size_is_refused(tmp_path: Path):
    assert write_pdf(tmp_path / "a4.pdf", [0], page_size="a4").exists()
    with pytest.raises(ValueError, match="unknown page size"):
        write_pdf(tmp_path / "x.pdf", [0], page_size="a3")
