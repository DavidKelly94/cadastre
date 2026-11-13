# ADR-0034: Placement from the scan, with taps as the fallback

## Status

Accepted, 2026-11-13. First proposed as a fit made on the PC; revised before acceptance on the owner's instructions that day: the phone proposes and the owner confirms, it says when a hand is needed, every proposal has a manual override, and ceiling corners count. Extends [ADR-0007](0007-per-level-se2-alignment.md) and [ADR-0031](0031-the-capture-proves-itself-before-you-leave.md). Details in `docs/design/capture-guidance-design.md`.

## Context

A capture is placed on the plan by tapping the room's corners as the app names them. The owner would rather tap nothing, and accepts that some captures will still need taps. Every capture already builds a mesh of the walls as it runs.

A rectangular room fits its outline two or four ways round. At framing a wall is open studs, which the depth sensor sees through, and furniture hides floor corners in a finished room. The scan will find every corner, a few, or none.

## Decision

1. **The phone looks for the room's corners in its own scan** while the capture runs, and matches them to the outline. A corner is the vertical line where two walls meet, so it can be found, proposed or tapped at the floor or at the ceiling, whichever can be seen.
2. **What it finds is proposed, not placed.** Proposed marks appear in the camera view with their names and count only when the owner confirms them, together or one by one.
3. **Every proposal can be overridden by hand.** A mark can be moved, dismissed, or replaced by a tap, before or after confirming, and proposals can be switched off for a capture. A tap always wins.
4. **The phone says when a hand is needed.** A corner the scan cannot find is asked for by name, as today. When two ways round fit equally, the app shows one and asks.
5. **A confirmed proposal is recorded as one**: the landmark's `method` says the scan found it and a person confirmed it.
6. **A wall height, when the owner enters one, is a check**: the scan's floor-to-ceiling distance is compared with it, and a corner seen at both ends must stand upright.
7. **The PC checks the phone afterwards**, comparing proposals with taps on real captures, to tune the thresholds.

## Consequences

Positive: one confirmation in place of four taps where the scan can see; a person checks every placement; it falls back corner by corner at framing.

Negative: more on the capture screen; thresholds are set before any framing capture exists.

## Alternatives considered

| Alternative | Why not |
|---|---|
| Placing automatically with no confirmation | A wrong fit looks like a right one, and nobody is asked. |
| Fitting on the PC first | The answer arrives after the owner has left the room. |
