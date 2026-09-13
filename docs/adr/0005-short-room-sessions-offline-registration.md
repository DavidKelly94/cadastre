# ADR-0005: One room per session, registration offline

## Status

Superseded by [ADR-0022](0022-session-is-one-pass-carrying-phases.md), 2026-09-13, on the phase clause only: a session is one room in one **pass**, carrying a set of phases. Every other decision below stands and is carried forward.

Accepted, 2026-09-11.

## Context

ARKit tracking is accurate to about 1-3 cm inside a room but drifts: a benchmark of four VIO systems measured about 0.02 m/s relative pose error for ARKit (Sensors 2022, https://pmc.ncbi.nlm.nih.gov/articles/PMC9785098/), a corridor test found about 1.5 m of error after 19.1 m, and an indoor mapping study reports up to 12 cm residuals at longer ranges (https://www.sciencedirect.com/science/article/pii/S2666165923000510). A whole-house walk ends tens of centimetres to more than a metre off. Thermal and storage limits point the same way: LiDAR, camera and mesh at 30 fps heat the phone (Apple keeps RoomPlan sessions under about 5 minutes), and a session writes about 800 MB per 5 minutes.

## Decision

A session is one room in one phase, targeting 2-5 minutes, with a hard stop at 10 minutes or below 500 MB free (`HealthPolicy`). Each session has its own ARKit world frame with origin at the start; the app never tries to relocalise into a previous session. The owner starts at the doorway, sees at least two markers, taps landmarks and finishes where they started. Registration into the per-level house frame happens offline from markers, landmarks and plan corners (ADR-0006, ADR-0007); from week 3 a pose graph over marker observations ties all sessions of a level together.

## Consequences

Positive:

- Drift stays at room scale, a few centimetres.
- Thermal state, storage and crash exposure are bounded; a bad session is redone in five minutes.
- No `ARWorldMap` persistence or cross-session state in the app.

Negative:

- A house produces 10-20 sessions per phase; hallways and stairs need their own sessions with shared markers.
- Neighbouring rooms overlap little, so alignment depends on markers and landmarks, not visual overlap.
- A house-wide consistent model waits for the week-3 pose graph, and the protocol relies on owner discipline.

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| One continuous whole-house session | Metre-level drift, thermal shutdown and one multi-gigabyte session at risk from a crash. |
| `ARWorldMap` relocalisation between sessions | Works only within a phase; can relocalise indefinitely and fails after appearance change (ADR-0006). |
| Several rooms per session under the cap | Allowed for small connected spaces, but naming and coverage tracking are per room. |
