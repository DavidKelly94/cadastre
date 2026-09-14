# ADR-0025: The floor plan is a project-level asset the app carries

## Status

Accepted, 2026-09-14. Extends [ADR-0007](0007-per-level-se2-alignment.md) rather than superseding it: the per-level SE(2) fit, the landmark-to-plan correspondences and the Umeyama solve all stay on the PC, unchanged. What changes is that the plan itself is no longer something the phone has never seen.

## Context

The app answers "what have I covered?" as a count: `Kitchen 2/6`, `Basement 3/18`. A count cannot say *where*, and where is the whole question. Standing in the house is the only moment a missed corner can still be recorded, and the owner discovers the gap days later on the PC, after the drywall is up.

This was a scoping decision, not an oversight: `docs/plan.md` put plan work on the web surfaces and the design brief followed. The canvas that came back has ten screens and mentions a plan once, as a caption under the session trajectory — *"Plan alignment happens on the PC."* The canvas is faithful to the brief; the brief was wrong.

ADR-0007 still holds for the part it covers: picking correspondences and reading residuals wants a large screen, and a phone at arm's length in a dusty house is a bad place for precise work. But *alignment* and *display* were conflated. Showing a plan and marking which room is which needs no transform at all.

## Decision

The floor plan is a **project-level asset**, stored beside sessions and carried by the app.

1. **Import, per level.** A PDF page or a photograph of a paper plan. The app keeps the original and a normalised raster.
2. **Display, per level.** The plan is viewable in the app, zoomable, with rooms drawn on it.
3. **Tap to place a room.** The owner taps where a room is. Rooms then shade by capture state per phase, so coverage is answered spatially, on site.
4. **No transform is solved on the phone.** A tapped placement is a human-declared association between a room and a spot on a drawing. It is not a calibration, not a correspondence, and the pipeline must never consume it as one.
5. **Scale calibration and alignment stay on the PC**, per ADR-0007. Moving two-point scale to the phone later is possible without changing anything decided here; it is deferred, not rejected.
6. **The contract grows, the version does not.** [ADR-0021](0021-session-format-is-the-only-cross-language-contract.md) makes `docs/session-format.md` the only cross-language contract, so a plan written by the app and read by the pipeline is specified there rather than in a second document. The addition is project-level and touches no session field, so `format_version` stays 3.

Sessions remain immutable (rule 6). A plan is neither session data nor derived data; it sits at project scope, where the pipeline store already expects `plans/<level>.png` and `plans/<level>.json`.

## Consequences

Positive: the coverage question gets a spatial answer at the moment it can still be acted on; the plan travels to the PC with the capture instead of arriving separately by some other route; the pipeline starts from a plan that is already associated with rooms; and no second contract document comes into existence.

Negative, carried knowingly:

- **A tapped placement looks more authoritative than it is.** It is a fingertip on a drawing, and someone will eventually read it as survey data. Mitigated by keeping it in its own file with its own name, never in `align.json`, and by `validate` refusing to treat it as a correspondence — but the risk is real and is the reason point 4 is written as a prohibition rather than a note.
- **The app gains a file type it does not understand.** A multi-page plan set needs a page picker, and a photographed plan needs perspective correction the phone will not do.
- **Storage grows** by a raster per level, on a device already budgeting 800 MB per room.
- **Two new screens inside a 14-day sprint**, when ten are already unbuilt. Scope added on purpose, with the schedule risk named in `docs/status.md`.

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| Leave plans on the PC, improve the per-room checklist instead | Cheapest, and it was the status quo. A better checklist is still a list; it cannot show that the far corner of a room was never walked. |
| Solve the full alignment on the phone | Contradicts ADR-0007 for its stated reasons, and correspondence picking on a 6-inch screen in a dusty house is the part most likely to go badly. |
| Add two-point scale calibration on the phone now | Not rejected, deferred. It removes a desktop step but adds an on-site step that is easy to get wrong, and it can be added later without changing the store shape. |
| Store the plan inside each session folder | Violates rule 6 by putting non-session data in an immutable session, and duplicates one drawing across every capture in the project. |
| A second contract document for project-level files | Exactly what ADR-0021 exists to prevent: two contracts drift, and a new client would have to find both. |
