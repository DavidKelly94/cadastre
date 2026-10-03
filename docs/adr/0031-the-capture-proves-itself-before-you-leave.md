# ADR-0031: The capture proves itself before you leave the room

## Status

Accepted, 2026-10-03. Extends [ADR-0026](0026-markers-are-optional-the-plan-is-the-frame.md), [ADR-0027](0027-alignment-quality-not-a-landmark-count.md) and [ADR-0030](0030-the-phone-owns-the-first-loop.md); it changes the shape of ADR-0030's align step and takes over the live half of roadmap item 3 (capture coaching). Mechanics in `docs/design/field-proof-design.md`.

## Context

Construction keeps going. A wall that was open on Tuesday is closed on Thursday, so a capture is often the only one there will be, and a capture that cannot be placed on the plan, or that missed the north wall, is found out at home, too late. Today the app proves two things in the field: that the tapped corners are spread enough for a fit (ADR-0027), and counts of keyframes, stills and landmarks. It cannot say whether the corners tapped are the corners the plan has, that is decided later when they are paired; and counts say that something was captured, not what was missed. The geometric coverage check exists only on the PC, afterwards. The owner's question on 2026-10-03: is the point marking good, is the progress good, given one shot?

## Decision

1. **The room is outlined on the plan before the visit.** Each room's corners are marked on the calibrated drawing, with the loupe, at home. The outline is the plan's statement of where the corners are.
2. **Taps in the field are guided and placed live.** The HUD names the next corner to tap from the outline; after two, the app solves the placement on the phone and shows the residual, and asks for a third when the fit is weak. A tap snaps to where the mesh's wall planes meet when they do. The owner leaves the room knowing the capture is placed.
3. **Coverage is shown live, and checked before leaving.** Walls shade in the camera view as they are photographed within range; a per-phase stills checklist comes from the capture protocol; a leave check lists what to re-shoot while the wall is still open.
4. **Free capture stays.** A room with no outline, a quick top-up, a space not on the plan: the same capture with no guidance, placed later or never. A top-up is its own session, and the plan view and the coverage check read every session of a room and phase together.
5. **The files stay the contract.** Outlines are an additive field in `plans/<level>.json`; placements are ADR-0030's alignment file; the leave check's result is an additive field in the manifest. `format_version` stays.

## Consequences

Positive: a capture is known to be good before the trade covers it; the PC's align page becomes a fallback; the re-shoot list arrives while the re-shoot is still possible.

Negative, carried knowingly: outlining rooms is work before the visit, and a plan that disagrees with what was built produces an honest but unhelpful residual; live coverage from ARKit's mesh is approximate and must say so; more on screen during capture, on a site that is bright, dusty and one-handed.

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| Pair the corners after Stop, on the phone | Still finds a bad tap after the walk; the guided tap finds it during. |
| Markers everywhere for placement | ADR-0026: trades remove them; they stay optional for accuracy. |
| Coverage from the PC's report, next visit | The next visit may be too late; that report stays for what the phone cannot judge. |
