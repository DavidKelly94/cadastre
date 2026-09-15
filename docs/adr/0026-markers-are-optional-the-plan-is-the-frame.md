# ADR-0026: Markers are optional; the plan and tapped landmarks carry the frame

## Status

Accepted, 2026-09-15. Supersedes [ADR-0006](0006-fiducials-and-plan-as-invariant-frame.md).

Only the requirement changes. The marker artwork, the hybrid AprilTag-plus-noise-ring design, `vividhome markers`, on-device `detectionImages` and offline `vividhome apriltag` all carry forward unchanged, and ADR-0006 remains the place to read the detection-range measurements behind them.

## Context

ADR-0006 required "at least two per room" and had phases chain through marker IDs. The owner rejects the requirement, for two reasons that are not about accuracy:

- **A homeowner cannot place markers during a walkthrough.** It is a setup step before any value appears, and it is the step most likely to stop someone using the product at all.
- **Trades remove them.** A fiducial that does not survive between phases fails at the single job it exists for.

ADR-0006 already knew this. Its negative consequences say "Trades cover or remove markers; mitigated by the placement rule, re-hang notes and **plan geometry as the final invariant**", it calls markers "weighted ties, **not ground truth**", and its own title names the plan as the invariant frame. `align.py` already leads with tapped landmarks and treats markers as an `--use-markers` option.

So this is less a reversal than a promotion: the fallback ADR-0006 named becomes the primary path, and the accelerator becomes optional.

Scope for the MVP is a **building under construction where a floor plan exists** — the owner's own site, or a builder's. Finished homes without plans are deferred; the owner's judgement is that there is little value there beyond ease of testing.

## Decision

1. **No capture requires a marker.** Nothing in the app, the pipeline or the docs treats their absence as a defect.
2. **The floor plan per level is the invariant frame**, as ADR-0006 already said. Each session aligns to it independently through tapped landmarks ([ADR-0007](0007-per-level-se2-alignment.md)), so sessions relate to each other *through the plan* rather than to each other directly. No session-to-session chaining is needed.
3. **Landmarks become load-bearing.** Alignment quality is now entirely a function of how many were tapped and whether a human can still identify them on the drawing weeks later. The app must guide their capture instead of accepting them casually, and must refuse to finish a room with too few.
4. **A plan is required for the product's value, not for a valid session.** `session-format.md` section 13 keeps `plans/` optional, because a session without one is still a correct session. But a *project* without a plan has no shared frame, and the app says so rather than letting the owner discover it after the drywall.
5. **Markers stay, as an optional accuracy add.** Somebody documenting a commercial job, or a room where the plan is known to be wrong, should still be able to use them.
6. **Mesh registration is promoted** from a week-3 roadmap item to the named path for recovering the accuracy markers were providing. The structure of a building under construction is stable even as its surfaces change, which is exactly the condition it needs.

## Consequences

Positive: nothing to place, nothing for a trade to remove, and no silent degradation when a marker goes missing. One fewer physical step between someone and a usable capture, which is the difference between a tool they use and one they mean to set up.

Negative, carried knowingly:

- **Accuracy drops by an amount nobody has measured.** ADR-0006 recorded about 3 cm at 2 m for a marker. Plan-plus-landmarks is bounded by tap precision and by how well the drawing matches what was built — plausibly 5 to 15 cm, which finds a stud bay at 16-inch centres and is marginal for a single wire. **This is a measurement, not an estimate, and it is the first thing to do once alignment runs.** Nothing downstream should quote a number until then.
- **Landmarks become a single point of failure.** A session with too few, or with labels nobody can match to the drawing later, cannot be aligned at all. Markers used to be able to rescue exactly that session.
- **The plan's accuracy becomes the ceiling on everything.** An as-drawn plan that does not match as-built puts a systematic error into every session on that level, and nothing in the system detects it.
- **The capture UI has more to do** at the moment the owner's attention is worst: standing in a noisy room, one-handed, phone up.

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| Keep markers required | The owner's objection is about adoption, not accuracy, and ADR-0006 had already conceded that trades remove them. A requirement that the environment defeats is not a requirement. |
| `ARWorldMap` relocalisation across phases | Rejected by both ADR-0005 and ADR-0006 and still rejected: it matches on appearance, and framing to drywall removes essentially every feature point. It fails exactly when it is needed. |
| Mesh registration as the frame now | The right direction and promoted above, but unbuilt and unmeasured. Making an unwritten component the foundation is how a schedule slips silently. |
| Automatic natural-feature fiducials (electrical boxes, openings) | Genuinely attractive, and ADR-0010 territory. It is model work, it is not MVP, and its output would be a candidate rather than a fact (rule 9). |
| Require a plan at the format level | Rejected: a session captured before the plan arrives is still a correct session, and making the format reject it would lose real data for a reason that resolves itself. |
