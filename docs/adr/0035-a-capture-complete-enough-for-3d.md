# ADR-0035: A capture complete enough for 3D

## Status

Accepted, 2026-11-13, by the owner the day it was proposed ("the ADRs look pretty good"). Extends [ADR-0031](0031-the-capture-proves-itself-before-you-leave.md).

## Context

The capture's live guidance answers one question: has each wall been photographed. The rehearsal on 2026-11-13 passed it, four walls of four, from 275 keyframes taken standing near the middle of the room and turning. That is enough to find a pipe in a photo. It is thin for a 3D model: turning on the spot gives almost no change of viewpoint, and both a rebuilt mesh and a splat need each surface seen from more than one place.

What is recorded at framing is all there will ever be of framing. The 3D work in [ADR-0036](0036-3d-on-the-pc-in-stages-opened-from-the-phone.md) can be built afterwards; the capture cannot be repeated.

## Decision

1. **Guidance gains a second measure: viewpoints.** For each stretch of wall, whether it has been seen from at least two positions a useful angle apart, and whether the floor and the ceiling have been seen at all.
2. **The capture says what is missing, in words and on the plan.** "East wall, from one spot only", "Ceiling not seen": the owner asked for the phone to say what it still needs, not only how much.
3. **The leave check gains one line**, "Enough for 3D", green or orange. It advises and never blocks: a capture that only finds things in photos is still a good capture.
4. **Nothing new is recorded.** The measure is computed from the camera positions the session already holds. `field_check` gains optional keys.
5. **The thresholds are guesses** until models have been built from real captures, and are revisited then.

## Consequences

Positive: the owner knows before leaving the room whether a 3D model is likely to work; the framing captures are worth more later.

Negative: a longer walk per room; one more thing on the capture screen; thresholds set before there is evidence.

## Alternatives considered

| Alternative | Why not |
|---|---|
| A fixed walking pattern to follow | Rooms differ; saying what is missing lets the owner close it any way that suits the room. |
| Leave guidance as it is and judge on the PC | The PC's answer arrives after the room can no longer be walked. |
| Record video continuously | Much more storage and heat for frames that mostly repeat ([ADR-0004](0004-session-format-posed-rgbd-keyframes.md)). |
