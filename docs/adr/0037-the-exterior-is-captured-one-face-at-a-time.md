# ADR-0037: The exterior is captured one face at a time

## Status

Accepted, 2026-11-13, by the owner the day it was proposed ("the ADRs look pretty good"). Extends [ADR-0005](0005-short-room-sessions-offline-registration.md).

## Context

The owner expects to need the outside of the house as well: sheathing, flashing, where services enter. The room capture does not carry over. The depth sensor reaches about five meters and is weakened by sunlight, so most of a wall seen from the yard has no depth. There is no room outline to tap corners against. And a walk around the whole house drifts, which is why interiors are one room per session.

The drawing does help: the reader in [ADR-0032](0032-the-drawing-sets-itself-up.md) already finds the walls, so the building's outer line is available for each level.

## Decision

1. **One capture per face of the house**, named for the way it faces. It is a room like any other in the session format, so nothing in the format changes.
2. **A face is placed by the building's outside corners**: two taps, matched to the outer wall line read from the drawing. The reader gains that outer line.
3. **Photos are the record.** Depth is kept where the sensor reports confidence and ignored elsewhere.
4. **Guidance counts the length of the face photographed**, not walls meshed.
5. **Any 3D of the exterior comes from the photos**, at stage three of [ADR-0036](0036-3d-on-the-pc-in-stages-opened-from-the-phone.md), not from the phone's mesh.
6. **Upper walls and the roof are out of reach** from the ground and are not solved here.

## Consequences

Positive: the exterior joins the same plan, phases and pages as the rooms; no new file types.

Negative: placement from two far-apart corners is less certain than a room's four; coverage outdoors has not been tried at all; the roof stays unrecorded.

## Alternatives considered

| Alternative | Why not |
|---|---|
| One loop around the house | Drift over that distance, with no walls close enough to correct it. |
| A drone | A different tool, license and data path; out of scope for a phone app. |
