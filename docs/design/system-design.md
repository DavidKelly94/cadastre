# System design

Cadastre turns a walk through a room with a LiDAR iPhone into a permanent, plan-aligned record of what is inside the walls. This document describes the whole system; the iOS app, pipeline and viewer each have their own design doc.

## 1. Goals and non-goals

Goals (MVP, two weeks):
- Capture everything needed later (posed photos, depth, mesh, markers, landmarks) with no vendor lock-in and no cloud.
- Put every session on the floor plan with a known transform, so photos can be found by location for decades.
- Be testable by the owner alone, on the phone and on a Windows PC.

Non-goals (MVP): reconstruction beyond the ARKit mesh, AI labeling, AR x-ray, accounts, sharing, Android.

## 2. Components

| Component | Runs on | Language | Responsibility |
|---|---|---|---|
| Cadastre app | iPhone 15 Pro or newer, iOS 17+ | Swift, SwiftUI, ARKit, RealityKit | Record sessions per room and pass; expose them as files |
| CadastreCore | inside the app, and on Linux CI | Swift (no ARKit/simd) | Pure logic: keyframe policy, transforms, manifest/JSONL encoding, health policy |
| Pipeline (`cadastre` CLI) | owner's PC (Windows, RTX 4070 Super) and Linux CI | Python 3.12 | Validate, detect markers, calibrate plans, align sessions, inspect; later meshes, splats, AI |
| Viewer | browser | TypeScript, three.js, Spark | Plan overlay, phases, click-to-photo, measurement (weeks 3+) |
| Docs | repo | Markdown | Contracts (session format), protocols, decisions |

## 3. Data flow

```
 Cadastre app                          Files / SMB / USB             cadastre pipeline                     viewer
 ┌─────────────────────────┐        ┌──────────────┐        ┌───────────────────────────┐        ┌────────────┐
 │ ARKit frames            │        │ sessions/    │        │ ingest + validate         │        │ plan +     │
 │  → keyframe policy      │───────▶│  <project>/  │───────▶│ apriltag → markers        │───────▶│ sessions   │
 │  → JPEG + depth + conf  │        │   <session>/ │        │ plan add/calibrate        │  JSON  │ photos     │
 │ stills, markers,        │        └──────────────┘        │ align → T_hs per session  │  GLB   │ mesh       │
 │ landmarks, mesh         │                                │ inspect → HTML            │  SOG   │ (splats)   │
 └─────────────────────────┘                                └───────────────────────────┘        └────────────┘
```

Raw sessions are immutable. Everything the pipeline computes lives in `derived/` inside the session, or in the project store (`plans/`, `alignments/`, `derived/`).

## 4. Coordinate frames and the transform chain

Three frames, all metres, all `+y` up:

1. **Session frame** `s`: ARKit world for one session; origin where the app started. Defined in `session-format.md`.
2. **House frame** `h`: one per building, shared by all sessions and all phases. `+y` up; `x` and `z` horizontal. The house origin and axes are defined by the plan calibration of the reference level (`index` 1): house `+x` is the plan image's `+u` (right), house `+z` is the plan image's `+v` (down the page). Looking down from above with `+x` to the right, `+z` points down the page, which is consistent with a right-handed `+y`-up frame.
3. **Plan pixels** `(u, v)`: one raster per level, calibrated with `metres_per_pixel`, an `origin_px` (the pixel that sits at house `(x=0, z=0)`), and `rotation_deg` (angle from image `+u` to house `+x`, normally 0 for the reference level; other levels may be rotated or offset if their sheets differ).

Mapping house → plan for a level:

```
[u]   [origin_u]   1/mpp · R(rotation) · [x]
[v] = [origin_v] +                       [z]
```

Alignment of a session to its level is a rigid 2D transform (SE(2)): yaw about `+y` plus translation in `x` and `z`, and a fixed `y` offset that puts the session's floor at the level's `floor_height_m`. It is solved from tapped landmarks (session frame) paired with plan corners (plan pixels → house metres). The result is stored as a full 4x4 `T_hs` (column-major) so no downstream code repeats the sign conventions:

```
T_hs = [ cos θ   0   sin θ   t_x ]
       [   0     1     0     t_y ]
       [ −sin θ  0   cos θ   t_z ]
       [   0     0     0      1  ]
```

`t_y = floor_height_m − y_floor_session`, where `y_floor_session` comes from `floor` landmarks or the median `y` of mesh faces classified `floor`.

Multi-level: each level has its own plan raster and `floor_height_m`. Stairs are the only reliable physical tie between levels; markers on stair landings appear in sessions of both levels.

Cross-phase: sessions of different phases are aligned to the plan independently. Marker poses (in house frame) from earlier phases are reused as extra correspondences for later phases (`cadastre align --use-markers`), which is more accurate than tapped corners once markers are established.

## 5. Accuracy budget

| Source | Typical | Mitigation |
|---|---|---|
| ARKit pose drift within a 5-minute room session | 1–3 cm, worse near featureless walls | short sessions, loop back to start, keep the mesh on |
| LiDAR depth | ±1 cm at 1–2 m, degrades past 4 m | stills taken from ≤ 1.5 m for details |
| Tapped landmark placement | 1–3 cm | tap the same physical corners every phase; ≥ 3 per room |
| Marker pose (20 cm tag) | 2–3 cm and 1–3° at 2 m; unreliable beyond 4 m | observe each marker from ≤ 2 m, square-on still |
| Plan vs as-built | 1–2 in | the plan is a reference; residuals are displayed, never hidden |

Target: locate a photographed element within ~5 cm on the plan. Good enough to know which stud bay a wire is in; not a substitute for a stud finder at the last inch.

## 6. Storage

Per 5-minute room session: 300–800 MB plus stills. A 2,500 sq ft house with 20 rooms and 6 phases is roughly 40–100 GB of raw capture. Sessions move to the PC after each site visit and are deleted from the phone. Keep two copies (PC + external drive or cloud archive); the raw sessions are the only irreplaceable asset.

## 7. Privacy and safety

Everything is local: no accounts, no telemetry, no uploads in the MVP. Sessions contain photos of the owner's own house. The app asks only for camera permission. If the project ever becomes a product, sharing and cloud sync get their own ADRs.

## 8. Failure modes and handling

| Failure | Detection | Handling |
|---|---|---|
| Tracking limited (motion, low light, featureless) | `ARCamera.trackingState` | HUD warning; frames still logged with `tracking` field; protocol says slow down and re-sweep |
| Thermal throttling | `ProcessInfo.thermalState` | `.serious` doubles keyframe thresholds; `.critical` stops the session cleanly |
| Disk full | free-space check | refuse to start below 2 GB; stop below 500 MB |
| App crash mid-session | manifest `status: incomplete` at next launch | app repairs the manifest from files present and marks `repaired` |
| Marker not seen / wrong size | pipeline residuals; `expected_markers` vs observed | validate warns; protocol requires a square-on still per marker |
| Session cannot be aligned (too few landmarks) | `cadastre align` | fall back to markers from other phases or manual trajectory drag in the inspector |
| Owner cannot get files off the phone | — | three routes documented: Files app to SMB, USB with the Apple Devices app, AirDrop-free zip share sheet |

## 9. Extension points (weeks 3+)

- **Pose graph**: nodes = sessions and markers, edges = marker observations and landmark matches; solved with least squares (scipy) to replace per-session alignment with a house-wide consistent solution.
- **TSDF meshes** (Open3D) from depth + poses, replacing the coarse ARKit mesh for the viewer.
- **Splats** (nerfstudio splatfacto or Postshot) per room, seeded with ARKit poses; delivered as SOG.
- **AI**: see `ai-roadmap.md`; all items consume the session format as-is.
- **AR x-ray**: the app relocalizes in a finished room using landmarks/plan geometry and renders earlier-phase photos and meshes through `T_hs`.

## 10. Security of the build pipeline

The only secrets are the App Store Connect API key (Admin role, stored as GitHub secrets) and the Apple team ID. They never touch the repository. Workflows write the key to the runner's temp directory and let `xcodebuild` sign with a cloud-managed certificate; nothing is cached across runs.
