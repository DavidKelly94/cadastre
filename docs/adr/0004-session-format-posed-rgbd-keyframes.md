# ADR-0004: Session format is posed RGB-D keyframes in per-frame files with JSONL sidecars

## Status

Accepted, 2026-09-11.

## Context

Captured data is perishable (framing is covered within weeks) and must stay readable for years, on a PC, in Python, with standard tools. The phone writes 2-3 MB/s, about 800 MB per 5-minute room, and can be stopped mid-session by a crash or a thermal or disk guard. ARKit provides per frame a 1920x1440 colour image, a 256x192 Float32 depth map in metres, a UInt8 confidence map, a 4x4 camera transform, 3x3 intrinsics, exposure and tracking state. Apple's ARKitScenes (https://github.com/apple/ARKitScenes) and the Stray Scanner tooling (https://github.com/kekeblom/StrayVisualizer) use the same per-frame layout, as do the fallback recorders.

## Decision

A session is a directory `sessions/<project>/<YYYYMMDD-HHMMSS>_<level>_<room>_<phase>_<id6>/` with `manifest.json`, `frames.jsonl`, `stills.jsonl`, `markers.jsonl`, `landmarks.jsonl`, `log.txt`, `rgb/NNNNNN.jpg` (quality 0.85), `depth/NNNNNN.f32` (256x192 row-major Float32 metres, 0 = invalid), `conf/NNNNNN.u8`, `stills/NNN.jpg`, `mesh.obj` and `mesh_classes.u8`. Only keyframes are stored (`KeyframePolicy`: at least 100 ms apart and moved more than 0.10 m or rotated more than 5 degrees, tracking normal).

Each `frames.jsonl` line carries `i`, `t`, `T_wc` (16 floats, column-major, camera to world), `K`, image and depth sizes, `exp_s`, `tracking`, `thermal` and the three file paths. Conventions: ARKit world, y up, gravity-aligned, metres, origin at session start, camera looking along -z (`T_cv = T_wc * diag(1,-1,-1,1)` for OpenCV); `K` is for the landscape image; depth intrinsics are `K` scaled by 256/1920. `manifest.json` carries `format_version`, identifiers, device, app build, keyframe policy, expected markers and statistics. Raw sessions are never modified; derived data goes under `derived/`.

## Consequences

Positive:

- Readable from any language; nothing is baked into images.
- Append-only JSONL with fsync every 50 lines survives crashes; a dropped frame corrupts nothing.
- Lossless depth; easy to trim for fixtures (`samples/` holds at most 10 frames, under 6 MB).
- Every AI roadmap item can run on data captured now.

Negative:

- Thousands of small files copy slowly over SMB or USB; zip before transfer.
- No temporal compression, so about 800 MB per room.
- `format_version` must stay in step across app, pipeline and samples.

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| HEVC video plus a pose track | Poses drift from frames on drops; a crash truncates the container; keyframes must be re-extracted lossily. |
| Vendor formats (`.r3d`, Polycam raw) | Tied to another app's conventions and pricing; accepted only as fallback inputs through a converter. |
| HDF5 or one container per session | Needs a library on both sides and is fragile when writing stops abruptly. |
| Video only, poses from photogrammetry | Throws away free metric poses and depth (ADR-0009). |
