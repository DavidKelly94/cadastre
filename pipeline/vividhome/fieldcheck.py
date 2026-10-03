"""The app's leave check, read on the PC (section 4 ``field_check``, ADR-0031).

The app writes numbers and makes its three sentences from them with
``FieldCheck.lines`` in the Swift core package. This is the same rule in
Python, word for word, so the inspect page and the index say what the review
screen said. The ``contract`` CI job holds the two together on sample checks
and on the checklist's names (``tests/test_contract.py``); a change to either
side's wording has to land on both, which is the point.
"""

from __future__ import annotations

import math
from typing import Any

__all__ = ["CHECKLIST", "EVERY_PHASE", "PHASE_ITEMS", "lines", "short_corner"]

#: Required in every phase, before the phase's own items (StillsChecklist.everyPhase).
EVERY_PHASE: list[tuple[str, str]] = [("wall", "Each wall square-on with the tape")]

#: The capture protocol's section 4 table, as StillsChecklist.items(for:) holds it,
#: in CapturePhase order.
PHASE_ITEMS: dict[str, list[tuple[str, str]]] = {
    "framing": [
        ("headers", "Headers"),
        ("king-jack-studs", "King and jack studs"),
        ("blocking", "Blocking"),
        ("fire-blocking", "Fire blocking"),
        ("stair-framing", "Stair framing"),
        ("top-plates", "Top plates"),
        ("anchor-bolts", "Anchor bolts"),
        ("hold-downs", "Hold-downs"),
        ("odd-stud-spacing", "Odd stud spacing"),
    ],
    "electrical": [
        ("boxes", "Every box with its cable count"),
        ("panel", "Panel with the cover off"),
        ("home-runs", "Home-run routes"),
        ("nail-plates", "Nail plates"),
        ("low-voltage", "Low-voltage runs"),
        ("smoke-co", "Smoke and CO locations"),
        ("exterior-penetrations", "Exterior penetrations"),
    ],
    "plumbing": [
        ("supply", "Supply runs and manifold"),
        ("drains-vents", "Drains and vents"),
        ("cleanouts", "Cleanouts"),
        ("shutoffs", "Shutoffs"),
        ("water-heater", "Water heater connections"),
        ("hose-bibs", "Hose bibs"),
        ("tub-shower-valves", "Tub and shower valves"),
        ("gas", "Gas line with every fitting and shutoff"),
    ],
    "hvac": [
        ("ducts", "Duct trunks and branches"),
        ("boots", "Register and return boots"),
        ("line-sets", "Line sets"),
        ("condensate", "Condensate"),
        ("flues", "Flues"),
        ("erv-hrv", "ERV or HRV ducts"),
        ("thermostat-wires", "Thermostat wires"),
        ("dampers", "Dampers"),
    ],
    "insulation": [
        ("bays", "Each bay after insulation"),
        ("vapour-barrier", "Vapour barrier seams"),
        ("sealed-penetrations", "Sealed penetrations"),
        ("hidden-blocking", "Blocking hidden behind batts"),
    ],
    "drywall": [
        ("screw-lines", "Screw lines"),
        ("access-panels", "Access panels"),
        ("repairs", "Repairs"),
    ],
    "finish": [
        ("outlets-switches", "Every outlet and switch"),
        ("fixtures-registers", "Every fixture and register"),
        ("flooring-seams", "Flooring seams"),
    ],
    "other": [],
}

#: Every item by id, in the order StillsChecklist.all lists them.
CHECKLIST: dict[str, str] = dict(EVERY_PHASE)
for _items in PHASE_ITEMS.values():
    for _id, _name in _items:
        CHECKLIST.setdefault(_id, _name)


def short_corner(label: str) -> str:
    """``corner-ne2`` reads as ``NE2``; FieldCheck.short."""
    trimmed = label.removeprefix("corner-")
    return trimmed.upper()


def _centimetres(metres: float | None) -> int:
    # Swift's .rounded() is to-nearest-away-from-zero; Python's round() is not.
    return math.floor((metres or 0.0) * 100 + 0.5)


def _metres(value: float) -> str:
    return f"{value:.1f} m"


def _placement_line(placement: dict[str, Any]) -> dict[str, Any]:
    status = placement.get("status")
    centimetres = _centimetres(placement.get("rms_m"))
    if status == "placed":
        return {"text": f"Placed on the plan, {centimetres} cm", "ok": True}
    if status == "check":
        return {"text": f"Check the corners: {centimetres} cm off", "ok": False}
    if status == "not_placed":
        return {"text": f"Not placed: {centimetres} cm off, a corner is wrong", "ok": False}
    if status == "untapped":
        return {"text": "Not placed: tap two corners", "ok": False}
    return {"text": "Not placed yet: no outline for this room", "ok": False}


def _walls_line(walls: dict[str, Any] | None) -> dict[str, Any]:
    if not isinstance(walls, dict):
        return {"text": "Walls photographed: unknown until the capture is placed", "ok": False}
    photographed = int(walls.get("photographed", 0))
    total = int(walls.get("total", 0))
    text = f"Walls photographed: {photographed} of {total}"
    gaps = walls.get("gaps") or []
    if gaps:
        worst = gaps[0]
        corners = [short_corner(part) for part in str(worst.get("wall", "")).split("->")]
        wall_name = (
            f"{corners[0]}–{corners[1]} wall" if len(corners) == 2 else str(worst.get("wall", ""))
        )
        text += (
            f"; {wall_name}, {_metres(float(worst.get('length_m', 0)))} not photographed"
            f" from {_metres(float(worst.get('from_m', 0)))} past "
            + (corners[0] if corners else "its first corner")
        )
        if len(gaps) > 1:
            text += f" (+{len(gaps) - 1} more)"
    return {"text": text, "ok": photographed == total}


def _stills_line(stills: dict[str, Any]) -> dict[str, Any]:
    total = int(stills.get("total", 0))
    if total <= 0:
        return {"text": "Stills: no list for these trades", "ok": True}
    done = int(stills.get("done", 0))
    missing = [str(item) for item in stills.get("missing") or []]
    text = f"Stills: {done} of {total} on the list"
    if missing:
        text += "; missing " + ", ".join(CHECKLIST.get(item, item) for item in missing[:3])
        if len(missing) > 3:
            text += f" (+{len(missing) - 3} more)"
    return {"text": text, "ok": not missing}


def lines(check: dict[str, Any]) -> list[dict[str, Any]]:
    """The three lines of the review screen, from a manifest's ``field_check``.

    Each is ``{"text": ..., "ok": bool}``, green when ok and orange otherwise, in
    the order the screen shows them: placement, walls, stills.
    """
    placement = check.get("placement") if isinstance(check.get("placement"), dict) else {}
    stills = check.get("stills") if isinstance(check.get("stills"), dict) else {}
    return [_placement_line(placement), _walls_line(check.get("walls")), _stills_line(stills)]
