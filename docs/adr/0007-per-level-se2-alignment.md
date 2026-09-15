# ADR-0007: Per-level SE(2) alignment from tapped landmarks and plan corners

## Status

Accepted, 2026-09-11.

## Context

ARKit poses are metric and gravity-aligned (`worldAlignment = .gravity`), so the scale, roll and pitch of a session are already known. Placing a session on a plan level is a 2D rigid transform, x, y and yaw, plus a floor-height offset per level; floor-plan localisation research poses the problem as SE(2), with stairs as the only reliable tie between levels. Compass heading (`.gravityAndHeading`) is unreliable indoors near steel, so yaw must come from correspondences. Automatic methods exist: Z-FLoc (https://arxiv.org/abs/2606.04788) matches lines on a bird's-eye projection zero-shot, and wall-line ICP pipelines report about 4 cm. Framing tolerances allow 1-2 inch deviations from the plan, so any fit shows residuals; the plan is a reference, the scan is the truth.

## Decision

The house frame per level is SE(2) plus a z offset. While capturing, the owner taps room corners and door thresholds; `LandmarkLogger` raycasts against estimated planes and stores a label and world point in `landmarks.jsonl`. `vividhome align <session> --level L1` opens a local page to pair landmarks with plan corners and fits the transform with Umeyama's method without scale, writing `derived/align.json` with per-pair residuals. Sessions without landmarks inherit the frame through shared markers (ADR-0006). Automatic refinement (wall-line ICP or a Z-FLoc-style matcher) is deferred to weeks 3+ as roadmap item 2 and will only ever propose correspondences for the owner to confirm.

## Consequences

Positive:

- About ten lines of deterministic linear algebra, covered by `synth.py` tests.
- Tapping four corners on site is cheap and captures intent: which corner is which.

Negative:

- Manual pairing for every session with landmarks.
- Raycast accuracy on estimated planes is a few centimetres; a wrong label gives a silently bad fit, caught only by residuals and the inspector overlay.
- A miscalibrated plan scale corrupts every alignment on that level (ADR-0014).

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| 3D similarity transform with scale | Scale, roll and pitch are already known; extra freedom only absorbs noise. |
| Automatic wall-line matching now | A week of work with unknown failure cases on partial framing; deferred. |
| Marker frame only, no plan | Loses the invariant reference the finished house and the AR view depend on. |
