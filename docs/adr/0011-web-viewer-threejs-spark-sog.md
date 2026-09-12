# ADR-0011: Web viewer on three.js and Spark with SOG splats

## Status

Accepted, 2026-09-11.

## Context

From week 3 the owner needs a viewer that overlays the plan, toggles phases, jumps from a 3D point to the nearest photos, measures between two clicks and shows labels, for LiDAR meshes now and per-room splats later. It must run as static files in a browser on the PC and leave a path to WebXR.

Spark (https://github.com/sparkjsdev/spark, v2.2.0, MIT, World Labs) renders Gaussian splats inside three.js scenes and reads PLY, compressed PLY, SPZ, SPLAT, KSPLAT and SOG on WebGL2 with WebXR support. The previously common `@mkkellogg/gaussian-splats-3d` is no longer actively developed and its author points to Spark (https://github.com/mkkellogg/GaussianSplats3D). SOG is an open format 15-20 times smaller than PLY: 55 MB for a 4-million-Gaussian scene that is 1 GB as PLY, produced by the open-source `splat-transform` CLI (https://blog.playcanvas.com/playcanvas-adopts-sogs-for-20x-3dgs-compression/). Consumer devices render 1-5 million splats interactively, so a house needs room-sized chunks.

## Decision

`web/` is a TypeScript app on three.js. Spark renders splats; `GLTFLoader` loads TSDF meshes as GLB; the plan raster is a textured quad in the per-level house frame; photos, poses, alignment and labels arrive as JSON and JPEG from the pipeline. Splats are delivered per room as SOG and loaded on demand. Application features (phase slider, nearest photo by minimum angular plus positional distance, two-click measurement, labels) are our code.

## Consequences

Positive:

- MIT stack on the largest WebGL ecosystem; controls, raycasting and loaders already exist.
- Assets 20 times smaller; open formats, so nothing is locked to Spark.

Negative:

- Spark is young; its LOD and streaming specifics were not verified.
- Mixing splats, meshes and photo frustums needs careful depth handling.
- Every domain feature is custom; room chunking and mobile Safari memory limits are our problem.

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| SuperSplat / PlayCanvas | An editor and engine, not an app; annotation cap of 25; no measurement tool found. |
| Babylon.js 8 | Capable splat support, smaller ecosystem for this use, no SOG streaming path at decision time. |
| Potree | Point clouds only; maintenance uncertain. |
| Native iOS or visionOS viewer first | No Mac to iterate; the web works everywhere and the AR mode comes later in the app. |
