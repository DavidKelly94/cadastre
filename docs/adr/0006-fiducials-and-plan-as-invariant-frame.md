# ADR-0006: AprilTag hybrid markers, with the plan as the invariant frame

## Status

Accepted, 2026-09-11.

## Context

Captures from framing, rough-in, insulation, drywall and finish must share one coordinate frame, yet every visible surface changes between phases. ARKit's `ARWorldMap` is a visual relocaliser; Apple states: "If ARKit cannot reconcile the recorded world map with the current environment... the session remains in the relocalizing state indefinitely." ARCore Cloud Anchors require the device to "look at the same physical environment as the original hosted anchor" and expire after 1-365 days. Relocalisation degrades with appearance change over weeks and months (https://arxiv.org/pdf/2008.02004); framing to drywall removes essentially every feature point.

Printed fiducials survive if placed on material that survives. With a 16.4 cm AprilTag, published accuracy is about 1.6-3.4 cm and 0.8-3.2 degrees at 2 m, degrading to 5.8-12.4 cm at 3 m; 10-20 cm tags stop being detected beyond about 4 m. Glare kills detection, so lamination must be matte. Fiducial tracking of ongoing construction is prior art (US patents 11348322 and 12223613).

## Decision

Markers are 20 cm squares: a 12.8 cm AprilTag 36h11 (1.6 cm cells plus quiet zone), a 2 cm high-detail ring seeded by the ID so ARKit's image-detail check passes, and a label such as `IG-017`; IDs run `IG-000` to `IG-059`. The same rendering is bundled as PNG for on-device `detectionImages` (`physicalWidth` 0.20 m, at most 4 tracked) and printed by `igloo markers`. At least two per room, on surfaces that survive the next phase (subfloor at door thresholds, top plates, rough-opening jambs, panel area, slab, exterior sheathing), shared markers at stair landings, never moved, each position recorded against an invariant feature ("IG-012: centred on door D3 threshold, 100 mm from left jamb") so it can be re-hung. Offline, `igloo apriltag` detects tags with OpenCV (`DICT_APRILTAG_36h11`, `solvePnP`) and phases chain through marker IDs. The plan per level is the invariant frame: the finished house aligns to it through openings, corners and stairs.

## Consequences

Positive:

- Works across total appearance change; needs only paper, a laminator and discipline.
- Live (ARKit) and offline (OpenCV) detection from one artwork; markers also check scale.
- The plan frame outlives every marker.

Negative:

- Trades cover or remove markers; mitigated by the placement rule, re-hang notes and plan geometry as the final invariant.
- About 3 cm at 2 m and worse beyond 3 m, so markers are weighted ties, not ground truth.
- The owner must print, laminate, place and log markers; ARKit needs the exact physical size.

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| `ARWorldMap` persistence | Relocalisation fails after appearance change (Apple quote above). |
| Cloud Anchors, Geospatial or VPS | Same visual relocalisation, a cloud dependency, expiry, outdoor-only VPS. |
| GPS, UWB, BLE, Wi-Fi | 0.6-5 m indoors; iPhone UWB is device-to-device only. |
| Mesh-to-mesh ICP between phases | Fails when floors change and drywall hides framing; used only as a cross-check. |
