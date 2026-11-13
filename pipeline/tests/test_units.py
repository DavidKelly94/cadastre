"""Lengths as the owner reads them. The app writes the same text from the same
numbers (Units.swift); the contract job compares the two over a table."""

from __future__ import annotations

import pytest

from vividhome import units
from vividhome.units import IMPERIAL, METRIC


@pytest.mark.parametrize(
    ("meters", "imperial", "metric"),
    [
        (0.0, "0 in", "0 cm"),
        (0.006, "1/4 in", "1 cm"),
        (0.068, "2 3/4 in", "7 cm"),
        (0.0762, "3 in", "8 cm"),
        (0.18, "7 in", "18 cm"),
        (0.30, "11 3/4 in", "30 cm"),
        (0.314, "1 ft", "31 cm"),
    ],
)
def test_a_small_distance(meters: float, imperial: str, metric: str):
    assert units.small(meters, IMPERIAL) == imperial
    assert units.small(meters, METRIC) == metric


@pytest.mark.parametrize(
    ("meters", "imperial", "metric"),
    [
        (0.2, "8 in", "0.2 m"),
        (0.3048, "1 ft", "0.3 m"),
        (0.8, "2 ft 7 in", "0.8 m"),
        (1.9, "6 ft 3 in", "1.9 m"),
        (3.1242, "10 ft 3 in", "3.1 m"),
        (33.2, "108 ft 11 in", "33.2 m"),
    ],
)
def test_a_length(meters: float, imperial: str, metric: str):
    assert units.length(meters, IMPERIAL) == imperial
    assert units.length(meters, METRIC) == metric


def test_an_area_and_a_plan_scale():
    assert units.area(10.0, IMPERIAL) == "108 sq ft"
    assert units.area(10.0, METRIC) == "10.0 m²"
    assert units.per_pixel(0.0127, IMPERIAL) == "0.50 in per pixel"
    assert units.per_pixel(0.0127, METRIC) == "12.7 mm per pixel"
    assert units.per_pixel(0.0017, IMPERIAL) == "0.07 in per pixel"


def test_imperial_unless_the_environment_says_otherwise(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.delenv(units.ENVIRONMENT, raising=False)
    assert units.default() == IMPERIAL
    monkeypatch.setenv(units.ENVIRONMENT, "Metric")
    assert units.default() == METRIC
    monkeypatch.setenv(units.ENVIRONMENT, "furlongs")
    assert units.default() == IMPERIAL
