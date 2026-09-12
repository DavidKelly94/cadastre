# ADR-0009: Posed photos and the LiDAR mesh are the truth; splats are a visual layer

## Status

Accepted, 2026-09-11.

## Context

The purpose is to find studs, pipes, gas lines, ducts and wires behind finished walls years later. Those elements are thin: half-inch PEX or NM-B cable is a few pixels wide at typical distance. Gaussian splats are view-dependent blobs optimised for photometric loss; a 2 px cable renders plausibly but carries no reliable metric geometry, and no study quantifies 3DGS on wires or conduit. The LiDAR mesh gives few-centimetre wall dimensions from 256x192 depth but is useless for a half-inch pipe. Classic photogrammetry is the documented failure case for construction interiors: "large textureless walls, repetitive layouts, and partial or evolving structures exacerbate the challenges of pose estimation" (https://arxiv.org/html/2509.13972v1), and dense MVS costs about an hour on a 4090 for a small set. Splats, when wanted, train in 15-20 minutes per room on the 4070 Super (Postshot is free on all tiers; gsplat is open source) and ship as SOG, 15-20 times smaller than PLY (https://blog.playcanvas.com/playcanvas-adopts-sogs-for-20x-3dgs-compression/).

## Decision

Three layers, in order of trust:

1. Posed photos: keyframes and full-resolution stills with `K` and `T_wc`. Locating an element means pixel to depth ray to a point on the plan. The capture protocol makes stills of every box, penetration, gas line, header, blocking and duct mandatory.
2. Metric skeleton: the ARKit mesh now, Open3D TSDF fusion from week 3.
3. Optional visual layer: per-room splats seeded with ARKit poses, delivered as SOG.

No COLMAP or MVS by default. Feed-forward metric methods (MapAnything, Depth Anything 3) may densify a room later, seeded with known poses and depth.

## Consequences

Positive:

- "Where is the wire" is always answered by a photo and a ray, never by a hallucinated surface.
- Value exists from v0.1 without any splat; splats are added room by room when time allows.
- Nearest-photo lookup is simple: minimum angular plus positional distance over stored poses.

Negative:

- Photorealism arrives late and per room; mesh detail is coarse.
- Still discipline rests on the owner; a missed still cannot be recovered after drywall.
- Splats seeded from drifted poses show floaters; three representations must stay aligned.

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| COLMAP, GLOMAP, RealityScan, Meshroom | Wrong default for textureless repetitive interiors; slow; kept as optional refinement. |
| Splat-first capture (Scaniverse, Polycam) | No metric guarantee on thin elements; vendor formats and pricing. |
| NeRF | Slower to train and render than splats with no advantage on the web. |
| Mesh only | Loses thin elements and appearance. |
| 360 photo pins (OpenSpace style) | No depth or measurement; the buy option, without a persistent frame. |
