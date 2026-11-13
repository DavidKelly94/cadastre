# ADR-0034: Placement from the scan, with taps as the fallback

## Status

Proposed, 2026-11-13. Extends [ADR-0007](0007-per-level-se2-alignment.md), which deferred automatic refinement, and [ADR-0031](0031-the-capture-proves-itself-before-you-leave.md).

## Context

A capture is placed on the plan by tapping the room's corners as the app names them: four taps for a simple room. The owner would rather tap nothing. Every capture already records the walls as a mesh, and the `corners` prototype in the pipeline finds wall planes and where they meet, but it has only run on a synthetic room. The rehearsal capture of 2026-11-13 is the first real room with a known answer: its taps placed it at 7 cm.

Two limits are known before starting. A rectangular room fits its outline two or four ways round. And at framing a wall is open studs: the depth sensor sees through it into the next room, so the walls may not be findable until drywall.

## Decision

1. **The walls found in the scan are fit to the room's outline.** The result is the same alignment file, with `method: "walls"`.
2. **Evidence before the phone.** It runs first on the PC, after the fact, on real captures that also have taps. It moves into the live capture only when it agrees with the taps within 10 cm on real rooms, framing included.
3. **Which way round is settled by what is cheapest.** A room that is not symmetric settles itself. Otherwise the phone's heading decides, once one tapped room on the level has shown which way the drawing faces. Failing that, one tap.
4. **Taps stay and taps win.** The guided taps remain. When both exist and disagree, the app says so and keeps the taps.
5. **Recording the heading is an optional field** in the manifest, added when step 3 needs it.

## Consequences

Positive: a furnished or finished room may need no taps; the fit rests on whole walls, not four points.

Negative: it may not work at framing, the phase that matters first; a wrong automatic fit is worse than no fit, so the threshold in step 2 is strict.

## Alternatives considered

| Alternative | Why not |
|---|---|
| Printed markers only ([ADR-0026](0026-markers-are-optional-the-plan-is-the-frame.md)) | Already supported and still useful; they get covered or removed as work proceeds. |
| Carrying the placement from room to room in one session | Drift grows across a house ([ADR-0005](0005-short-room-sessions-offline-registration.md)). |
