# ADR-0028: Results return to the app, and the phone reads the record it wrote

## Status

Accepted, 2026-09-30. Decision 3 (LAN only, nothing written over the network) is amended by [ADR-0029](0029-the-pc-is-reached-over-the-owners-tailnet.md); the rest stands. Extends [ADR-0008](0008-offline-processing-on-owner-pc.md) (processing stays on the PC) and [ADR-0011](0011-web-viewer-threejs-spark-sog.md) (the viewer is a browser app). The asks are the owner's; the mechanics are in `docs/design/return-path-design.md` and may change without a new record.

## Context

ADR-0008 made the phone a recorder and the PC the only place anything is computed or seen. Right for the sprint, wrong for the product: the owner walks the house with the phone, and the phone can show neither the photos it just took nor the plan the PC placed them on. Two asks, stated on 2026-09-30: see a capture's keyframes on the phone, labelled, and save them to the camera roll; and see the rendering — sessions on the plan now, meshes and splats later — in the app, with the PC allowed to do the rendering. For testing, the home network with the PC on is enough.

## Decision

1. **The app reads its own record.** It shows a session's keyframes and stills from the files it holds, labelled from the session itself (project, level, room, phases, time, keyframe index, taps made there), and copies them to the camera roll as ordinary photos carrying that label in their metadata. Copies only; the session stays immutable (rule 6).
2. **Rendering stays on the PC and returns over the home network.** `vividhome serve` publishes the store's derived output on the LAN; the app finds the PC, fetches what a project needs and caches it. The first form is the served pages in a web view, so the phone shows the viewer the browser shows. A native renderer comes later only if that proves not enough.
3. **LAN only, for now.** PC on, same network, no accounts, nothing reachable from outside the house. A relay or sync service is a separate decision.
4. **The contract stays where it is.** What the app reads from the PC is specified in `docs/session-format.md` as an additive section when the first implementation lands, `format_version` unchanged, as ADR-0025 did under ADR-0021.

## Consequences

Positive: captures get checked where the house is; the plan with photos on it reaches the person standing in the room; sharing a photo costs nothing; the viewer is written once.

Negative, carried knowingly: a plaintext server on the home network, so `serve` must refuse writes whenever it listens beyond localhost; the PC has to be found, which means Bonjour and its entitlements; cached results go stale and the app must show their age; a web view is not AR; a camera-roll copy can lose its label to another app and is never the record.

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| Sync results through a cloud service | Against ADR-0008 and ADR-0012 for now: cost, an account, the house's photos leaving owner hardware. |
| Render on the phone | Thermal limits during capture, a 12 GB GPU idle on the desk. |
| Copy results back by AirDrop or Files | Works by hand today, which is why nothing comes back: no index, no freshness. |
| Native viewer in the app first | Two viewers before the pipeline's outputs settle; the web view reuses ADR-0011's. |
