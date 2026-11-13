"""Enough for 3D (ADR-0035): the pipeline's side of ModelReadiness.swift, on
the same small room its tests use."""

from __future__ import annotations

import math

from vividhome.fieldcheck import lines
from vividhome.readiness import GAPS_KEPT, add, enough, report, walls

ROOM = [
    ("corner-nw", 0.0, 0.0),
    ("corner-ne", 4.0, 0.0),
    ("corner-se", 4.0, 3.0),
    ("corner-sw", 0.0, 3.0),
]


def camera(x: float, z: float, angle: float) -> tuple[float, float, float, float, float]:
    return (x, z, math.cos(angle), math.sin(angle), math.pi / 6)


def turning(x: float, z: float) -> list[tuple[float, float, float, float, float]]:
    return [camera(x, z, math.radians(step)) for step in range(0, 360, 5)]


def level(count: int, height: float = 1.4) -> list[tuple[float, float, float, float]]:
    return [(index * 0.3, height, 1.0, 0.0) for index in range(count)]


def measured(cameras) -> list:
    out = walls(ROOM)
    for one in cameras:
        add(one, out)
    return out


def test_turning_on_the_spot_is_not_enough():
    model = report(level(72), measured(turning(2.0, 1.5)))
    assert model["walls_twice"] == 0.0
    assert not enough(model)
    assert len(model["gaps"]) == GAPS_KEPT
    assert model["gaps"][0] == {"wall": "corner-nw->corner-ne", "from_m": 0.0, "length_m": 4.0}


def test_walking_along_the_walls_sees_them_from_two_places():
    stops = [
        (0.6, 0.6), (1.3, 0.6), (2.0, 0.6), (2.7, 0.6), (3.4, 0.6), (3.4, 1.5),
        (3.4, 2.4), (2.7, 2.4), (2.0, 2.4), (1.3, 2.4), (0.6, 2.4), (0.6, 1.5),
    ]  # fmt: skip
    cameras = [one for x, z in stops for one in turning(x, z)]
    assert report(level(40), measured(cameras))["walls_twice"] >= 0.9


def test_floor_ceiling_and_heights():
    tilt = math.sin(math.radians(30))
    spread = [(index * 0.6, 1.4, 0.1, -tilt) for index in range(12)]
    assert report(spread, None)["floor"]
    assert not report([(0.1, 1.4, 0.1, -tilt)] * 12, None)["floor"], "one spot is one look"
    assert not report(spread[:6], None)["floor"]
    up = report([(x, y, z, tilt) for x, y, z, _ in spread], None)
    assert up["ceiling"] and not up["floor"]
    assert not report(level(40), None)["heights"]
    assert report(level(32) + level(8, 2.0), None)["heights"]
    assert report(level(40), None)["walls_twice"] is None


def test_the_leave_check_gains_a_line_only_when_the_capture_measured_it():
    base = {"placement": {"status": "placed", "rms_m": 0.05, "corners": 4}, "stills": {"total": 0}}
    assert len(lines(base)) == 3
    thin = {**base, "model": {"walls_twice": 0.62, "floor": True, "ceiling": False}}
    assert lines(thin)[3] == {
        "text": "Not enough for 3D yet: walls seen from two spots: 62%; ceiling not seen",
        "ok": False,
    }
    good = {**base, "model": {"walls_twice": 0.9, "floor": True, "ceiling": True}}
    assert lines(good)[3] == {"text": "Enough for 3D", "ok": True}
    free = {**base, "model": {"walls_twice": None, "floor": True, "ceiling": True}}
    assert lines(free)[3]["text"] == (
        "Not enough for 3D yet: walls unknown until the capture is placed"
    )
