"""How a length is written for the owner to read.

Everything on disk is in meters (``docs/session-format.md``) and every
threshold is in meters. This is only the last step, the text: the owner builds
in feet and inches and asked on 2026-11-13 for both ends to speak that way,
with metric still available.

The app writes the same text from the same numbers (``Units.swift``) and the
contract job compares the two, so the rounding is spelled out here rather than
left to a format string: ``floor(x + 0.5)`` on both sides.
"""

from __future__ import annotations

import math
import os

IMPERIAL = "imperial"
METRIC = "metric"
CHOICES = (IMPERIAL, METRIC)

#: What a command uses when it is not told: the environment, else imperial.
ENVIRONMENT = "VIVIDHOME_UNITS"

_METERS_PER_INCH = 0.0254
_QUARTERS = ("", "1/4", "1/2", "3/4")


def default() -> str:
    chosen = os.environ.get(ENVIRONMENT, "").strip().lower()
    return chosen if chosen in CHOICES else IMPERIAL


def _nearest(value: float) -> int:
    return math.floor(value + 0.5)


def small(meters: float | None, units: str) -> str:
    """A small distance, such as a fit: ``7 cm`` or ``2 3/4 in``."""
    value = abs(meters or 0.0)
    if units == METRIC:
        return f"{_nearest(value * 100)} cm"
    quarters = _nearest(value / _METERS_PER_INCH * 4)
    if quarters >= 48:
        return length(value, units)
    whole, part = divmod(quarters, 4)
    if not _QUARTERS[part]:
        return f"{whole} in"
    return f"{_QUARTERS[part]} in" if whole == 0 else f"{whole} {_QUARTERS[part]} in"


def length(meters: float | None, units: str) -> str:
    """A length along a wall: ``1.2 m`` or ``3 ft 11 in``."""
    value = abs(meters or 0.0)
    if units == METRIC:
        tenths = _nearest(value * 10)
        return f"{tenths // 10}.{tenths % 10} m"
    inches = _nearest(value / _METERS_PER_INCH)
    feet, rest = divmod(inches, 12)
    if feet == 0:
        return f"{rest} in"
    return f"{feet} ft" if rest == 0 else f"{feet} ft {rest} in"


def area(square_meters: float | None, units: str) -> str:
    """A floor area: ``10.0 m²`` or ``108 sq ft``."""
    value = abs(square_meters or 0.0)
    if units == METRIC:
        tenths = _nearest(value * 10)
        return f"{tenths // 10}.{tenths % 10} m²"
    return f"{_nearest(value / (0.3048 * 0.3048))} sq ft"


def per_pixel(meters_per_pixel: float | None, units: str) -> str:
    """A plan's scale: ``12.7 mm per pixel`` or ``0.50 in per pixel``."""
    value = abs(meters_per_pixel or 0.0)
    if units == METRIC:
        tenths = _nearest(value * 10_000)
        return f"{tenths // 10}.{tenths % 10} mm per pixel"
    hundredths = _nearest(value / _METERS_PER_INCH * 100)
    return f"{hundredths // 100}.{hundredths % 100:02d} in per pixel"
