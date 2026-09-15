# ADR-0027: The capture asks for alignment quality, not a landmark count

## Status

Accepted, 2026-09-15. Extends [ADR-0007](0007-per-level-se2-alignment.md) and [ADR-0026](0026-markers-are-optional-the-plan-is-the-frame.md); supersedes neither. The solver, the frame and the decision that landmarks carry the alignment are all unchanged. What changes is what the app asks the owner for.

## Context

ADR-0026 made tapped landmarks the only thing placing a capture on the plan, and the app took the simplest reading of that: count them, refuse below three, prompt for corners.

**A count is the wrong measure.** `umeyama_2d` fits a 2D rigid transform from point-to-point correspondences and needs two. What determines whether the fit is any good is not how many there are but how they are arranged:

- **Spread.** Two points at opposite ends of a room pin the rotation far better than five in one corner. A short lever arm turns tap error into angle error.
- **Collinearity.** Points along one wall leave the perpendicular direction poorly determined. `umeyama_2d` has a reflection guard for exactly this case, which keeps the result a rotation — it does not make it a good one.

So three taps in one corner pass the current rule and produce a worthless fit, while two at opposite ends of a great room fail it and produce a good one. The rule rejects the better capture.

**Corners are not special either.** They satisfy spread and identifiability conveniently, and that is the whole of their merit. In a framed house they carry a specific problem: an interior corner is two or three studs, and the plan is drawn to finished faces or to stud lines depending on the sheet. That is a half-inch to two inches of disagreement, **consistent in sign**, which the fit absorbs as translation instead of reporting as residual. A door threshold or rough-opening centre is a definite feature in both the room and the drawing.

**More points genuinely help.** As-built deviation from the drawing runs one to two inches per wall and is roughly independent per wall — a large term against the 5 to 15 cm ADR-0026 expects overall. Independent errors average down, so four to six well-spread points beat two precise ones. This is the opposite of the intuition that a few careful taps suffice.

## Decision

1. **The app measures the conditioning of the fit, not the number of taps.** From the landmarks placed so far it computes how well-determined a 2D rigid transform would be, and shows that as a quality reading. This is geometry on points the app already holds; no model is involved.
2. **The quality reading replaces the count as the gate.** A capture is refused for a set that cannot produce a checkable fit, not for having fewer than three of something.
3. **The app names where the next point would help most**, rather than asking for "corners". It knows the room's extent from the mesh and the points already placed.
4. **Openings are preferred to corners where both are available**, because a corner in framing is ambiguous against a drawing in a way an opening is not.
5. **Walls stay the automatic path, not the tap path.** A point on a wall is a point-to-line constraint the current solver cannot take. Wall-classified mesh faces are already captured, so walls are where derived candidates come from ([`ai-roadmap.md` item 5](../ai-roadmap.md)), not something to ask the owner to tap.

## Consequences

Positive: the gate finally measures what it was standing in for; a capture is not refused for being well-placed and sparse; the prompt can be specific rather than generic; and the quality number is the honest input to measuring ADR-0026's unmeasured accuracy cost, because a residual is only meaningful against a known-conditioned fit.

Negative, carried knowingly:

- **A number invites over-trust.** A well-conditioned fit of points that are all in the wrong place scores well. Conditioning measures the *geometry* of the correspondences, never whether the owner tapped the thing they meant; nothing in the app can check that second thing, and the reading must not imply otherwise.
- **It is computed in the session frame before any plan pairing exists.** The app scores the arrangement of the tapped points alone; the plan-side points are chosen later on the PC, and a badly chosen pairing there can still ruin a well-conditioned capture.
- **More prompting during capture**, at the moment attention is worst — standing in a noisy room, one-handed. The prompt has to earn its place or it becomes something to dismiss.
- **A second definition of "good enough" now exists**, in the app and in `align`. They must not drift; the app's measure is deliberately the cheaper, weaker one and never reports a residual, which only the PC can compute.

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| Keep the count, raise it to four or five | Cheap, and still wrong in the same direction: it would reject two well-placed points and accept five useless ones. A bad measure tuned is still a bad measure. |
| Require specific labelled points per room (four corners, every door) | Predictable and checkable, but it forces the same set on a hallway and an L-shaped great room, and a rectangular room does not need four corners when two opposite ones carry it. |
| Score it on the PC and report back | Correct and far too late: the only moment a missing point can be added is while the owner is still in the room. |
| Fit a point-to-line solver so walls can be tapped | A real improvement to the solver and a change to ADR-0007's decision, not to the capture UI. Worth considering when wall candidates are derived automatically; not now. |
| Leave it and rely on the derived candidates of roadmap item 5 | That work needs this measure anyway to decide which candidates to propose, and it is not MVP. |
