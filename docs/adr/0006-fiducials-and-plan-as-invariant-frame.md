# ADR-0006: AprilTag hybrid markers, with the plan as the invariant frame

## Status

Superseded by [ADR-0026](0026-markers-are-optional-the-plan-is-the-frame.md), 2026-09-15: markers are no longer required, and the plan with tapped landmarks carries the frame. The artwork, the generator and both detectors below carry forward unchanged, as do the detection-range measurements.

Accepted, 2026-09-11.

## Context

Captures from framing through finish must share one coordinate frame, yet every visible surface changes between phases. ARKit's `ARWorldMap` is a visual relocaliser; Apple states: "If ARKit cannot reconcile the recorded world map with the current environment... the session remains in the relocalizing state indefinitely." ARCore Cloud Anchors have the same requirement and expire after 1-365 days. Relocalisation degrades with appearance change over weeks and months (https://arxiv.org/pdf/2008.02004); framing to drywall removes essentially every feature point.

A 16.4 cm AprilTag gives about 1.6-3.4 cm and 0.8-3.2 degrees at 2 m, 5.8-12.4 cm at 3 m, and 10-20 cm tags are lost beyond about 4 m; glare kills detection.

## Decision

Markers are 20 cm squares: a 12.8 cm AprilTag 36h11 (1.6 cm cells plus quiet zone), a 2 cm high-detail ring seeded by the ID so ARKit's image-detail check passes, and a label such as `VH-017`. The same rendering is bundled as PNG for on-device `detectionImages` (`physicalWidth` 0.20 m) and printed by `vividhome markers`. At least two per room, on surfaces that survive the next phase (subfloor at door thresholds, top plates, rough-opening jambs, sheathing), shared at stair landings, never moved, each position recorded against an invariant feature ("VH-012: centred on door D3 threshold, 100 mm from left jamb") so it can be re-hung. Offline, `vividhome apriltag` detects tags with OpenCV (`DICT_APRILTAG_36h11`, `solvePnP`) and phases chain through marker IDs. The plan per level is the invariant frame: the finished house aligns to it through openings, corners and stairs.

## Consequences

Positive:

- Works across total appearance change with paper and matte lamination.
- Live (ARKit) and offline (OpenCV) detection from one artwork; the plan frame outlives every marker.

Negative:

- Trades cover or remove markers; mitigated by the placement rule, re-hang notes and plan geometry as the final invariant.
- About 3 cm at 2 m and worse beyond, so markers are weighted ties, not ground truth.

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| `ARWorldMap` persistence | Relocalisation fails after appearance change (Apple quote above). |
| Cloud Anchors, Geospatial or VPS | Same visual relocalisation, a cloud dependency, expiry, outdoor-only VPS. |
| GPS, UWB, BLE, Wi-Fi | 0.6-5 m indoors; iPhone UWB is device-to-device only. |
