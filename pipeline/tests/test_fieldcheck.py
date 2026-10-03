"""The leave check's sentences, pinned to the strings the Swift tests pin
(StillsChecklistTests), so the PC says what the review screen said."""

from __future__ import annotations

from vividhome.fieldcheck import CHECKLIST, PHASE_ITEMS, lines, short_corner


def test_the_checklist_has_one_name_per_id_and_no_commas():
    ids = [item for items in PHASE_ITEMS.values() for item, _ in items]
    assert len(set(ids)) == len(ids)
    assert next(iter(CHECKLIST)) == "wall"
    assert len(CHECKLIST) == 1 + len(ids)
    assert all("," not in name for name in CHECKLIST.values())
    assert CHECKLIST["panel"] == "Panel with the cover off"


def test_a_placed_capture_with_a_gap_and_missing_stills():
    check = {
        "placement": {"status": "placed", "rms_m": 0.0, "corners": 3},
        "walls": {
            "photographed": 3,
            "total": 4,
            "gaps": [{"wall": "corner-ne->corner-se", "from_m": 1.0, "length_m": 3.0}],
        },
        "stills": {
            "done": 5,
            "total": 8,
            "missing": ["low-voltage", "smoke-co", "exterior-penetrations"],
        },
        "checked_at": "2026-10-03T18:00:00Z",
        "together": [],
    }
    assert lines(check) == [
        {"text": "Placed on the plan, 0 cm", "ok": True},
        {
            "text": "Walls photographed: 3 of 4; NE–SE wall, 3.0 m not photographed from 1.0 m past NE",
            "ok": False,
        },
        {
            "text": "Stills: 5 of 8 on the list; missing Low-voltage runs, Smoke and CO locations, "
            "Exterior penetrations",
            "ok": False,
        },
    ]


def test_a_free_capture_is_not_placed_yet_rather_than_failed():
    check = {
        "placement": {"status": "free", "corners": 0},
        "walls": None,
        "stills": {"done": 0, "total": 0, "missing": []},
    }
    assert lines(check) == [
        {"text": "Not placed yet: no outline for this room", "ok": False},
        {"text": "Walls photographed: unknown until the capture is placed", "ok": False},
        {"text": "Stills: no list for these trades", "ok": True},
    ]


def test_check_untapped_and_more_than_three_missing():
    check = {
        "placement": {"status": "check", "rms_m": 0.18, "corners": 2},
        "walls": {
            "photographed": 4,
            "total": 5,
            "gaps": [
                {"wall": "corner-nw->corner-ne", "from_m": 1.9, "length_m": 0.8},
                {"wall": "corner-se->corner-sw", "from_m": 0.0, "length_m": 0.5},
            ],
        },
        "stills": {"done": 7, "total": 11, "missing": ["panel", "home-runs", "smoke-co", "boxes"]},
    }
    first, second, third = lines(check)
    assert first == {"text": "Check the corners: 18 cm off", "ok": False}
    assert second["text"] == (
        "Walls photographed: 4 of 5; NW–NE wall, 0.8 m not photographed from 1.9 m past NW (+1 more)"
    )
    assert third["text"] == (
        "Stills: 7 of 11 on the list; missing Panel with the cover off, Home-run routes, "
        "Smoke and CO locations (+1 more)"
    )
    assert lines({"placement": {"status": "untapped", "corners": 1}, "stills": {"total": 0}})[
        0
    ] == {
        "text": "Not placed: tap two corners",
        "ok": False,
    }
    assert lines({"placement": {"status": "not_placed", "rms_m": 0.314}})[0]["text"] == (
        "Not placed: 31 cm off, a corner is wrong"
    )
    assert short_corner("corner-ne2") == "NE2"
    assert short_corner("kitchen corner 1") == "KITCHEN CORNER 1"
    assert lines({})[0]["text"] == "Not placed yet: no outline for this room"
