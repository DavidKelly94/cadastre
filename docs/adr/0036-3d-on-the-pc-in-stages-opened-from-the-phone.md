# ADR-0036: 3D on the PC in stages, opened from the phone

## Status

Proposed, 2026-11-13. Builds on [ADR-0009](0009-posed-photos-first-splats-later.md), [ADR-0011](0011-web-viewer-threejs-spark-sog.md) and [ADR-0028](0028-results-return-to-the-app.md).

## Context

The PC draws one thing today: a level's plan with each capture's path and photos on it. The owner wants a 3D rendering made on the PC and available on the phone. Every capture already holds what that needs: the phone's own mesh of the room, a depth map and a color image per keyframe, and where the camera was. A placed capture also has its position in the house, so rooms can be shown together.

## Decision

1. **Stage one: the scanned mesh, in the house.** For each placed capture the PC writes the phone's mesh moved into house coordinates, and a page per level that shows the rooms together in a browser. No new capture data and no GPU.
2. **Stage two: a rebuilt mesh.** The depth maps are fused into a cleaner, colored surface.
3. **Stage three: splats**, one per room, as the photoreal layer.
4. **The phone opens the PC's page**, the way it opens the level page now. A copy kept on the phone for use away from the PC is a later decision.
5. **A model is for looking, a photo is for finding.** Wires and small pipes are located from posed photos, as ADR-0009 says, and the 3D page links each place to its photos.
6. **Everything is derived.** It is written under `derived/` and the project's own folder, and can be deleted and rebuilt.

Each stage ships when it works on the captures already taken; none waits for the next.

## Consequences

Positive: something to look at after the first stage, from captures the owner already has; later stages improve it without recapturing.

Negative: the viewer's libraries must be served by the PC, since the pages may not load anything from outside; stage three's time per room is an estimate from the plan and untested on this GPU.

## Alternatives considered

| Alternative | Why not |
|---|---|
| Straight to splats | Slowest to first result, and ADR-0009 keeps them as a visual layer only. |
| Building the model on the phone | Heat and battery during capture; the PC has the GPU ([ADR-0008](0008-offline-processing-on-owner-pc.md)). |
