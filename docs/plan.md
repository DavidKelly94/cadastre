# VividHome — capture your house during construction, see behind the walls forever

> **Changes since approval.** This document records the plan as approved on 2026-09-11 and its
> decision table is left as written, including the working name of the time. Four things have
> changed since, each with a decision record:
>
> - The product is a queryable record of a building spanning construction and ownership, not only
>   a look behind walls ([ADR-0017](adr/0017-product-scope-record-and-collaboration.md)).
> - The repositories stay public through the build sprint, then go private
>   ([ADR-0018](adr/0018-staged-private-and-runner-budget.md)).
> - The product is named **VividHome** ([ADR-0019](adr/0019-name-cadastre.md)), with the bundle
>   identifier `ai.vividhome.app` ([ADR-0024](adr/0024-name-vividhome.md), which
>   replaced an identifier rooted in the owner's name). Identifiers below carry the new name; the
>   decision table does not.
> - Both repositories moved to `DavidKelly94` ([transfer runbook](transfer-runbook.md)). The
>   repository itself is still named `DavidKelly94/cadastre`: the product rename landed after the
>   transfer, and renaming it cuts off an in-flight agent session's GitHub access, so it waits for
>   the end of the sprint.


## Context

The project starts from an empty public repo. The owner is about to build a house and wants to photograph it during framing, electrical rough-in, plumbing and HVAC, map those captures onto the architectural plans, and years later open a 3D view of any construction state to find studs, pipes, gas lines, ducts and wires behind finished walls. They asked how doable this is, what the phone can do, and what is needed for scale and location. They also want design docs, a schedule, ADRs, a UI brief they can hand to Claude Design, a brand-themed name, and a captured AI roadmap to trial during rough-in.

Decisions made with the owner on 2026-09-11:

| Question | Answer | Consequence |
|---|---|---|
| Capture phone | iPhone 15 Pro or newer (LiDAR, A17 Pro+) | Native ARKit: metric poses, LiDAR depth + mesh, high-res posed stills. Android/cross-platform ruled out. |
| Plans | PDF drawings + paper/photos | Plan = scaled raster image per level; vector walls deferred. |
| Construction status | Not started | Time to build a capture app before framing; data is perishable once framing starts. |
| Scope | Personal tool first, product later | Open data format, small app, no accounts/cloud in MVP. |
| Dev machine | No Mac; cloud macOS CI | GitHub Actions `macos-26` runners build + upload to TestFlight. Repo is public → macOS minutes free. Needs a paid Apple Developer account ($99/yr). |
| Compute | PC with RTX 4070 Super (12 GB) | Offline reconstruction, splats and AI run on the PC. |
| Deadline | **Usable capture app in 2 weeks** | MVP = capture app + markers + protocol + minimal ingest/alignment. Reconstruction and viewer follow during construction. |
| Stack | "Go with what makes sense; you do the work; I must be able to test easily" | Native Swift/SwiftUI + ARKit; Python pipeline; TypeScript/three.js viewer later. Testing = TestFlight builds with an in-app per-build test plan. |
| Name / brand | **Igloo**, on the brand in use at the time, which has no strong theme yet | Design brief proposes the theme; repo stays `homescanner` until the owner renames it. |

## Feasibility verdict

**Doable. The risky parts are known and each has a mitigation.** Six pieces; the first three are solved by the phone plus discipline, the last three are offline work that can happen after capture.

1. **Capture — solved by ARKit on a LiDAR iPhone.** Each frame gives a metric 6-DoF camera pose, intrinsics, a 1920×1440 color image and a 256×192 LiDAR depth map with per-pixel confidence. `captureHighResolutionFrame` gives full-resolution stills with pose. Scene reconstruction gives a live classified mesh. Accuracy is ~±1–3 cm inside a room but drifts tens of cm to >1 m over a whole-house walk, so: **one room per session (2–5 min)** and tie sessions together offline.
2. **Scale and relative location — solved.** ARKit poses are metric and gravity-aligned, so aligning a session to a plan is a 2D rigid transform per level (x, y, yaw). The owner taps room corners/door thresholds *in the app while on site* (raycast landmarks) and matches them to plan corners in a web UI. GPS/UWB/Wi-Fi/BLE are useless indoors; ignored. As-built framing deviates 1–2 in from plans, so the plan is a reference and the scan is the truth.
3. **Cross-phase alignment — solvable with fiducials, not with ARKit relocalization.** ARWorldMap/Cloud Anchors are visual relocalizers and will not survive framing → drywall. Instead: printed 20 cm AprilTag-based markers, laminated matte, on surfaces that survive the next phase (subfloor at door thresholds, top plates, rough-opening jambs, panel area, slab, exterior sheathing). Every session sees ≥2 markers; phases chain through marker IDs offline; the finished house aligns via invariant geometry (openings, corners, stairs) against the plan, which is the invariant frame for everything.
4. **Reconstruction — staged.** Weeks 3+: LiDAR mesh per session (ARKit's mesh, later Open3D TSDF) as the metric skeleton; posed photos as the source of truth; per-room Gaussian splats (gsplat/Postshot on the 4070 Super, ~15–20 min/room) as a photorealistic layer delivered as SOG (~20× smaller than PLY). **Never trust a mesh or splat for wires or ½" PEX**; locate those from posed photos (pixel → depth ray → point on the plan). Classic photogrammetry is the wrong default for textureless, repetitive interiors.
5. **AI labeling — assistive, not automatic.** Open-vocabulary detectors are poor on MEP elements (a fine-tuned YOLO11-nano beat Grounding DINO by >85% precision in a 2025 ISARC study). Vision LLM captions/tags + SAM-style click-to-mask + human confirmation, projected through depth into 3D; fine-tune a small detector later on the owner's confirmed labels.
6. **Viewer — custom on standard parts.** three.js + Spark for splats/meshes; plan overlay, phase toggle, click-to-nearest-photo and measurement are app code. AR "x-ray" on the phone comes later on the same alignment.

**Build vs buy.** The cheapest existing route (~$0–120/yr): free Matterport iPhone-LiDAR scans per phase + Fieldwire/pin360 free to pin square-on wall photos to the PDF. That is ~80% of the value with zero code. What nothing on the market gives a homeowner: one persistent coordinate frame across phases + plan overlay + future AR see-through, under the owner's control. Given the product ambition, building is reasonable, **but capture readiness comes first**: the fallback path (below) is in place from day 1 regardless of app progress.

## Architecture

```
iPhone 15 Pro — VividHome app (Swift/SwiftUI + ARKit)     PC (RTX 4070 Super) — pipeline (Python)            Browser (TypeScript)
┌────────────────────────────────┐   Files app /   ┌──────────────────────────────────────┐        ┌────────────────────────┐
│ project/level/room/phase       │   USB / SMB     │ vividhome ingest → validate              │        │ web/ viewer (weeks 3+) │
│ session recorder: RGB keyframes│ ──────────────▶ │ → apriltag poses → align (SE2/level) │ ─────▶ │ three.js + Spark       │
│ + depth + confidence + pose + K│  session dirs   │ → inspector (plan + trajectories)    │  JSON  │ plan overlay, phases,  │
│ high-res posed stills          │                 │ → (later) TSDF mesh, pose graph,     │  GLB   │ click→photos, measure  │
│ tapped landmarks (corners)     │                 │   splats → SOG, AI labels            │  SOG   │ labels, AR x-ray data  │
│ marker (image) detection       │                 └──────────────────────────────────────┘        └────────────────────────┘
│ ARKit mesh export              │
└────────────────────────────────┘
```

Coordinate frames: **session** (ARKit world: metres, +y up, gravity-aligned, origin at session start, camera looks −z) → **house** (one per level: SE(2) + floor-height offset; markers, landmarks and plan corners live here) → **plan pixels** (per-level raster + scale + origin + rotation). Transforms are explicit 4×4 matrices in JSON; nothing is baked into images.

## 2-week MVP scope

**In:** VividHome iOS app on TestFlight; open session format; marker generator + placement protocol; capture protocol; pipeline `ingest`, `validate`, `apriltag`, `plan calibrate`, `align`, `inspect`; all docs below; fallback capture path documented day 1.

**Out (weeks 3+):** TSDF meshing, pose graph, splats, AI features, full 3D viewer, AR x-ray, LAN upload (day-13 stretch only), accounts/cloud, Android.

## Documentation deliverables

Written in the first two days so they guide the build, kept current after:

| Doc | Purpose |
|---|---|
| `docs/feasibility.md` | This assessment with sources (phone capabilities, products, reconstruction, alignment). |
| `docs/design/system-design.md` | Components, data flow, coordinate frames, storage estimates, privacy, failure modes. |
| `docs/design/ios-app-design.md` | Modules, ARKit session lifecycle, keyframe policy, writer backpressure, markers, landmarks, mesh export, health policy, state machine. |
| `docs/design/pipeline-design.md` | CLI + inspector design; the math (Umeyama SE(2) fit, PnP tag pose, drift handling); weeks-3+ extension points. |
| `docs/design/viewer-design.md` | Weeks-3+ viewer: three.js + Spark, plan overlay, phases, click→photo, measurement, packaging. |
| `docs/session-format.md`, `docs/capture-protocol.md`, `docs/markers.md`, `docs/owner-setup.md` | Specs and runbooks. |
| `docs/schedule.md` | 14-day schedule, milestones, owner tasks; weeks-3–8 roadmap keyed to construction phases. |
| `docs/adr/README.md` + `docs/adr/NNNN-*.md` | MADR-format ADRs (status, context, decision, consequences, alternatives). |
| `docs/ui/design-brief.md` | Self-contained Claude Design handoff (contents below). |
| `docs/ai-roadmap.md` | AI feature ideas with inputs, approach, rough-in trial, effort, risk. |

ADRs: 0001 native Swift/SwiftUI + ARKit over RN/Flutter/Unity/WebXR · 0002 iOS builds on GitHub Actions + TestFlight with an XcodeGen-generated project (no Mac) · 0003 unsigned archive + cloud-managed signed export via ASC API key; fastlane match fallback · 0004 session format = per-frame files + JSONL (JPEG, Float32 depth, UInt8 confidence, 4×4 poses), not video/vendor formats · 0005 one room per session, offline registration · 0006 AprilTag hybrid markers + plan as the invariant frame; ARWorldMap/Cloud Anchors rejected · 0007 per-level SE(2) alignment from tapped landmarks ↔ plan corners; auto-refinement deferred · 0008 offline processing on the owner's PC · 0009 posed photos + LiDAR mesh are truth, splats are a visual layer, no photogrammetry by default · 0010 AI labeling is assistive · 0011 viewer on three.js + Spark + SOG · 0012 monorepo; sessions in app Documents exposed to Files; no accounts · 0013 iOS 17 minimum, LiDAR required · 0014 plans as calibrated rasters · 0015 name "Igloo" on the brand of the time, superseded by 0019 and then 0020, then 0023 (name VividHome, bundle ID `ai.vividhome.app`) · 0016 core logic in a pure-Swift package tested on Linux CI.

`docs/ui/design-brief.md` contains: product one-liner and audience (owner on a dusty, bright, noisy site, one-handed, phone held up; later other homeowners); proposed theme (cadastral blocks as motif — each phase a course of blocks, the finished house the dome — **orphaned by the rename**, see `docs/status.md`; ice-white/blue surfaces with one warm accent for record/primary actions; high outdoor contrast; rounded block-like cards); information architecture (Projects → Levels → Rooms → Sessions by phase; Markers; Settings; Test plan); every screen with purpose, primary action, content, states and success criteria — Onboarding (LiDAR check, camera permission, 3-card protocol tutorial), Project list + empty state, Project overview (per-phase coverage by room, storage, transfer status), Level view, Room detail (sessions by phase, checklist, notes, expected markers), **Capture HUD** (tracking quality with reasons, elapsed/keyframes/dropped/free GB/thermal, markers seen, coverage checklist strip, REC, Still, Mark landmark, mesh toggle, room/phase label; states: initializing, tracking normal/limited, recording, paused, finalizing with progress, error), Session review (top-down trajectory, thumbnails, stills, markers, landmarks, quality flags, notes, Open in Files/share/delete), Markers (IDs, placement notes, seen-in-N-sessions, print instructions), Settings, Test plan; web surfaces (plan calibration two-point scale, alignment correspondence picker, session inspector, later 3D viewer with phase slider, click-to-photo, measure); platform constraints (iOS HIG, SwiftUI-native components, Dynamic Type, ≥44 pt targets, dark HUD over camera, haptics on capture events, thumb reach for REC/Still, portrait-first); requested deliverables (iPhone 15 Pro portrait mockups per screen, HUD state sheet, app icon, web layouts, design tokens, PNG/PDF export); open questions.

## Repo layout

```
vividhome/
  README.md
  docs/  feasibility.md  design/  adr/  ui/design-brief.md  ai-roadmap.md  schedule.md
         session-format.md  capture-protocol.md  markers.md  owner-setup.md  testplans/
  ios/
    project.yml                       # XcodeGen spec (single source of truth; project generated on the runner)
    ExportOptions.plist               # app-store-connect, destination upload, automatic signing
    VividHome/                            # app target: SwiftUI + thin ARKit layer
      App/VividHomeApp.swift  AppConfig.swift
      Capture/{ARSessionController,SessionRecorder,FrameWriter,JPEGEncoder,MarkerLogger,LandmarkLogger,MeshExporter}.swift
      Screens/{Onboarding,ProjectPicker,RoomPicker,Capture,SessionReview,Markers,Settings,TestPlan}View.swift
      Resources/{Markers/VH-000..059.png, TestPlan.md}
    VividHomeCore/                        # SwiftPM, pure Swift (no ARKit/simd): tests run on Linux
      Package.swift  Sources/VividHomeCore/{Transform,KeyframePolicy,FrameRecord,SessionManifest,JSONLWriter,HealthPolicy}.swift  Tests/
  pipeline/
    pyproject.toml                    # uv; numpy, opencv-python-headless, pypdfium2, reportlab
    vividhome/{ingest,validate,apriltag,plan,align,inspector,markers,synth}.py   tests/
  samples/                            # one trimmed real session (≤10 frames, <6 MB) for pipeline tests
  web/                                # weeks 3+
  .github/workflows/{core-test.yml, ios-check.yml, ios-testflight.yml}
```

## iOS app (VividHome)

- **Project**: XcodeGen pinned to the latest release (2.46.x; downloaded release asset with sha256 check, `brew install xcodegen` fallback). `project.yml`: iOS 17.0 target, Swift 5 language mode (avoids strict-concurrency compile failures we cannot iterate locally), `CODE_SIGN_STYLE Automatic`, team/build number from env, Info keys `NSCameraUsageDescription`, `UIFileSharingEnabled`, `LSSupportsOpeningDocumentsInPlace`, `ITSAppUsesNonExemptEncryption=false` (avoids the TestFlight compliance stall), `UIRequiredDeviceCapabilities [arkit]`, portrait only. System frameworks + the static VividHomeCore package only; **no embedded frameworks** (they would break the unsigned-archive/signed-export flow).
- **Screens** (`NavigationStack`): Onboarding → ProjectPicker → RoomPicker (level, room, phase `framing|electrical|plumbing|hvac|insulation|drywall|finish|other`, notes, expected marker IDs) → CaptureView (`ARView` in `UIViewRepresentable`; HUD as in the design brief; buttons REC / Still / Mark landmark / Stop) → SessionReview (stats, trajectory sketch, "Open in Files" via `shareddocuments://`, delete) → Markers → Settings (thresholds, JPEG quality, 30/60 fps) → TestPlan (renders the bundled per-build checklist).
- **ARSessionController**: `ARWorldTrackingConfiguration` with `frameSemantics = [.sceneDepth]` (raw + confidence, best for offline fusion), `sceneReconstruction = .meshWithClassification`, `environmentTexturing = .none`, `worldAlignment = .gravity`, a 30 fps 1920×1440 video format (thermal), `detectionImages` built at launch from the bundled marker PNGs (`physicalWidth` 0.20 m, validated), `maximumNumberOfTrackedImages = 4`; capability guards with a clear message on unsupported devices.
- **SessionRecorder** (`session(_:didUpdate:)`): `KeyframePolicy.shouldKeep` (VividHomeCore; Δt ≥ 100 ms and moved > 0.10 m or rotated > 5°, tracking `.normal`). On keep: copy depth (256×192 Float32) and confidence (UInt8) synchronously (~250 KB), retain the `capturedImage` pixel buffer (never the `ARFrame`), enqueue a job.
- **FrameWriter**: serial utility queue + semaphore(2); a third in-flight job drops the frame and increments `dropped` (backpressure never blocks ARKit). **JPEGEncoder**: one Metal-backed `CIContext`, `CIImage(cvPixelBuffer:)` → `jpegRepresentation` at quality 0.85 (~10 ms/frame; Metal handles YCbCr→RGB). **JSONLWriter** appends via `FileHandle`, fsync every 50 lines.
- **Stills**: `captureHighResolutionFrame` → `stills/NNN.jpg` + `stills.jsonl`. **MarkerLogger**: `ARImageAnchor` add/update → `markers.jsonl`. **LandmarkLogger**: tap → `arView.raycast(allowing: .estimatedPlane, alignment: .any)` → `landmarks.jsonl` (label such as "corner NW", "door D3 threshold", world point) — the correspondences for plan alignment. **MeshExporter** at stop: `ARMeshAnchor`s → world-space `mesh.obj` + `mesh_classes.u8` (one byte per face).
- **HealthPolicy** (VividHomeCore): refuse start < 2 GB free; warn at 5 min; auto-stop at 10 min or < 500 MB; `thermalState .serious` doubles keyframe thresholds, `.critical` stops; idle timer disabled; manifest written at start and finalized at stop; unfinished sessions repaired on next launch.
- **Storage/transfer**: `Documents/sessions/<project>/<session>/`, visible in Files. To the PC: Files → SMB share on the PC, or USB via the Apple Devices app on Windows. LAN upload is a day-13 stretch.

## Session format (`docs/session-format.md`)

```
sessions/<project>/<YYYYMMDD-HHMMSS>_<level>_<room>_<id6>/
  manifest.json  frames.jsonl  stills.jsonl  markers.jsonl  landmarks.jsonl  log.txt
  rgb/000123.jpg   depth/000123.f32 (256×192 row-major Float32 metres, 0 = invalid)   conf/000123.u8
  stills/000.jpg   mesh.obj   mesh_classes.u8
```
`frames.jsonl` line: `{"i":123,"t":12.345,"T_wc":[16 floats, column-major],"K":[fx,0,cx,0,fy,cy,0,0,1],"w":1920,"h":1440,"dw":256,"dh":192,"exp_s":0.0083,"tracking":"normal","thermal":"nominal","rgb":"rgb/000123.jpg","depth":"depth/000123.f32","conf":"conf/000123.u8"}`.
Conventions: ARKit world y-up, gravity-aligned, metres, origin at session start; `T_wc` = camera→world; camera looks −z (OpenCV: `T_cv = T_wc · diag(1,−1,−1,1)`); `K` is for the landscape captured image; depth intrinsics = `K` scaled by 256/1920. `manifest.json` carries `format_version`, ids, project/level/room/phase/notes, device model, iOS, app version/build, start/end, keyframe policy, video format, expected markers, stats (keyframes, dropped, limited seconds, max thermal). The pipeline never modifies raw sessions; derived data goes under `derived/`.

## CI and TestFlight (facts verified 2026-09-11)

- `core-test.yml` — `ubuntu-latest`, `container: swift:6.1`: `swift test` for VividHomeCore, `swift-format lint --strict`, `uv run pytest` for the pipeline. Runs on every push; this is the fast signal.
- `ios-check.yml` — PR/manual on `macos-26`: XcodeGen, `xcodebuild build` for `generic/platform=iOS Simulator` with `CODE_SIGNING_ALLOWED=NO`.
- `ios-testflight.yml` — push to the dev branch filtered on `ios/**` + `workflow_dispatch`; `macos-26` (GA 2026-02-26; image 20260907 has Xcode 26.6 default), `timeout-minutes: 30`, cancel-in-progress: `xcode-select` Xcode 26.6 → write `$RUNNER_TEMP/AuthKey.p8` → `xcodebuild archive` **unsigned** (`CODE_SIGNING_ALLOWED=NO`, `DEVELOPMENT_TEAM`, `CURRENT_PROJECT_VERSION=${{ github.run_number }}`) → `xcodebuild -exportArchive -exportOptionsPlist ios/ExportOptions.plist -allowProvisioningUpdates -authenticationKeyPath/-authenticationKeyID/-authenticationKeyIssuerID` (cloud-managed Apple Distribution certificate, no keychain/p12). `ExportOptions.plist`: `method app-store-connect`, `destination upload`, `signingStyle automatic`, `teamID`, `testFlightInternalTestingOnly true`, `manageAppVersionAndBuildNumber false`, `uploadSymbols true`.
- Cloud signing needs an **Admin-role** API key (otherwise "Cloud signing permission error"). Fallback ladder if upload or signing misbehaves: (1) `destination export` + `apple-actions/upload-testflight-build`; (2) archive with API-key cloud signing; (3) fastlane `match` with git storage on a `certs` branch of this repo + `upload_to_testflight(api_key:)` (adds `MATCH_PASSWORD`).
- Secrets: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY_P8` (full .p8 text), `APPLE_TEAM_ID`. Minutes: standard runners are free on public repos (private would be ~200 real macOS min/month on Free).
- Owner steps, all on the web (`docs/owner-setup.md`): enroll in the Apple Developer Program (individual, $99; Apple says ~24 h, 2026 reports range to days, so **day 0**) → Identifiers: App ID `ai.vividhome.app` → App Store Connect → Integrations → API key, role Admin, download .p8 once → My Apps → New App "VividHome" → TestFlight internal group with automatic distribution → install TestFlight on the phone → add the four GitHub secrets. Claude reads job logs via the GitHub API and fixes CI without owner involvement.
- Every build ships `TestPlan.md` (rendered in-app and in the TestFlight notes) as the owner's test script.

## Pipeline v0 (`pipeline/`, Python 3.12, uv, CLI `vividhome`)

- `vividhome ingest <dir|zip>` copy into the project store + `validate` (schema, JSONL parse, files exist and sizes, monotonic timestamps, orthonormal rotations, depth stats, marker/landmark counts) — the owner runs this after every capture and pastes the output.
- `vividhome apriltag <session>`: OpenCV `aruco` `DICT_APRILTAG_36h11` detection on keyframes + stills, `solvePnP` with `K` (note OpenCV's corner order), per-tag pose aggregated in the session frame → `derived/markers_detected.jsonl`.
- `vividhome plan add <pdf|image> --level L1` (pypdfium2 raster at 150–200 dpi; photos get optional 4-corner perspective correction) and `vividhome plan calibrate` (local page: click two points, type the dimension, set north and level height → `plans/<level>.json`).
- `vividhome align <session> --level L1`: local page to pair tapped landmarks with plan corners → Umeyama SE(2) without scale → `derived/align.json`.
- `vividhome inspect`: static HTML per level (plan raster, trajectories, markers, landmarks, thumbnails on hover, quality report) served with `python -m http.server`.
- `vividhome markers`: marker PDF generator (below). Tests: `synth.py` builds a synthetic session (known trajectory, warped AprilTags via `cv2.warpPerspective`, depth) for deterministic pytest coverage of validate/apriltag/align.

## Fiducials and capture protocol

- Marker sheet (Letter/A4): 20 cm square = 12.8 cm AprilTag 36h11 (1.6 cm cells + quiet zone) + a 2 cm high-detail ring seeded by ID (satisfies ARKit's image-detail check) + label "VH-017"; the same rendering is bundled as PNG for on-device detection. Print at 100%, matte lamination, verify size with a tape.
- Placement (`docs/markers.md`): ≥2 per room (subfloor by the door, top plate or jamb visible from the room), shared markers at stair landings, IDs entered in RoomPicker, never move a placed marker; record each marker's position relative to an invariant feature ("VH-012: centred on door D3 threshold, 100 mm from left jamb") so it can be re-hung.
- Capture (`docs/capture-protocol.md`): one session per room per pass, carrying every phase exposed (ADR-0022); start at the doorway; slow chest-height sweeps; each wall square-on floor-to-ceiling with a tape measure in frame; stills of every box, pipe penetration, gas line, header, blocking, duct and of each marker square-on from ~1 m; tap landmarks at room corners and door thresholds; finish where you started.
- **Fallback if the app slips**: same protocol with a free ARKit raw-recorder (NeRFCapture, free, updated May 2026; or Stray Scanner / Record3D ~$5 export unlock) plus the markers; `ingest` gains a converter and the format doc is unchanged.

## AI roadmap (outside the 2 weeks; trial during rough-in in 1–2 months)

Captured in `docs/ai-roadmap.md` with inputs, approach, rough-in trial, effort and risk per item. The session format is designed so all of these run on data captured now, without recapturing. Priority for the rough-in trial:

1. **"What am I looking at?"** Tap a still → vision LLM identifies and explains the element (PEX vs copper vs CPVC; NM-B gauge from jacket colour; CSST gas; ABS/PVC drain; supply vs return duct; low-voltage vs line-voltage; box types; nail plates; fire blocking) and proposes tags stored as *candidates* until confirmed. Trial: 50 rough-in stills vs the owner's labels.
2. **AI-assisted stitching / registration.** Feature matching between keyframes across sessions and phases (LightGlue/SuperPoint or MASt3R/MapAnything-style) adds constraints to the pose graph, flags misalignment, and auto-proposes plan-corner correspondences from the mesh. Trial: two overlapping sessions of a room; marker residual before/after.
3. **Capture coaching.** Post-session coverage analysis from mesh + poses ("north wall upper half never closer than 2 m", "no still of the panel"), blur and tracking-limited spans → re-shoot list; later live HUD hints.
4. **Auto-tagging + natural-language search.** Room (from location), phase, element tags and a description per photo; queries like "gas line in the kitchen wall" answer with photos on the plan. Trial: 20 queries.

Later: plan understanding (rooms, door/window tags, electrical symbols → expected-element checklists; VLMs are weak on plan geometry, so lists only with confirmation); plan-vs-built review (missing receptacle, wall moved > 2 in, nail plates where pipes/wires cross studs); per-wall change detection between phases; semantic 3D layer (SAM masks through depth → clickable pipes/wires/studs; small detector fine-tuned on confirmed labels); as-built report per room/wall with measurements from corners; stud-centre projection onto finished walls; AR x-ray narration; on-site voice notes pinned to location.

## 14-day schedule (detail in `docs/schedule.md`)

| Day | Claude builds | Owner does | Milestone |
|---|---|---|---|
| 0 | — | Enroll in Apple Developer Program; 2FA on Apple Account; buy/print supplies later | |
| 1 | Repo scaffold, docs skeleton (design docs, ADR set, schedule, UI brief, AI roadmap), `project.yml`, VividHomeCore, workflows, "Hello ARKit" screen with LiDAR check + build label; `core-test` green | | |
| 2–3 | First `ios-testflight` run; walk the fallback ladder if needed; VividHomeCore `Transform`/`KeyframePolicy`/`FrameRecord`/`SessionManifest` + tests; `session-format.md` | Create App ID, app record, Admin API key, TestFlight group; add secrets; install build #1 | **TestFlight build #1** |
| 4 | Recorder, writer, JPEG, depth/conf, HUD | 1-min capture at home → run `vividhome validate` | Build #2 |
| 5 | `markers.py`, `markers.md`, `synth.py`, `validate.py`, pytest | Print + laminate markers; copy a sample session into `samples/` | |
| 6 | Stills, MarkerLogger, LandmarkLogger, MeshExporter | | Build #3 |
| 7 | HealthPolicy, interruption handling, picker persistence, SessionReview + Open in Files | 5-min room with markers + landmarks | Build #4 |
| 8 | `apriltag.py` + PnP verified on samples | | |
| 9 | `plan.py`, `align.py`, `inspector.py` | Provide a plan PDF page + a photographed paper plan | |
| 10 | Feedback fixes, Settings, TestPlan view, Markers screen | | Build #5 |
| 11 | Crash-safe finalize, drop-rate/fps tuning | | Build #6 |
| 12 | End-to-end review | Dry run: 3 rooms + stairs at home; sessions shown on the plan | **Capture-ready** |
| 13 | Stretch: LAN upload; `owner-setup.md` polish | | |
| 14 | Tag v0.1; weeks-3+ backlog (TSDF, pose graph, splats, viewer, AI trials) | | v0.1 |

## Weeks 3–8 (during construction)

Session pose graph across markers (scipy/GTSAM) → Open3D TSDF meshes → per-room splats (nerfstudio splatfacto or Postshot, seeded with ARKit poses) → SOG via splat-transform → `web/` viewer (three.js + Spark: plan overlay, phase toggle, click→nearest photos, two-click measure, labels) → AI roadmap items 1–4 trialled at rough-in → AR x-ray mode in the app.

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| Enrollment or CI signing delays the first TestFlight build | Day-0 enrollment; build #1 is the day-2/3 milestone so problems surface early; Admin key; no embedded frameworks; documented fallback ladder; unsigned simulator build keeps code iteration unblocked. |
| Claude cannot run the app; ARKit bugs only show on device | Thin ARKit layer following Apple's documented patterns; all logic in VividHomeCore tested on Linux every push; per-build test plan; owner tests at home first; `validate` catches format issues immediately; per-session `log.txt` + TestFlight crash reports. |
| TestFlight processing stalls | `testFlightInternalTestingOnly`, unique run-number builds, never block on one build. |
| Framing starts before the app is ready | Fallback recorder + markers + protocol ready day 1; `ingest` converter if used. |
| Pose drift over long sessions | One room per session, 10-min hard stop, loop back to start, ≥2 markers per session, offline pose graph in weeks 3+. |
| Markers lost or covered | "Survives the next phase" placement rule, positions recorded relative to invariant features, re-hang protocol, plan geometry as the final invariant. |
| Thermal / storage (~2–3 MB/s, ~800 MB per 5-min room) | 30 fps format, motion-gated keyframes, bounded writer, thermal policy, disk guards, offload after each visit. |
| Thin elements invisible in mesh/splats | Mandatory posed stills; the viewer locates via photo pixel → depth ray, never the mesh alone. |
| Plans differ from as-built | Plan is a reference; alignment fits scan landmarks; viewer shows residuals. |
| XcodeGen breakage | Pinned binary + checksum, brew fallback, generated `.xcodeproj` uploaded as a CI artifact for diagnosis. |

## Verification

- **CI:** `core-test.yml` (Swift tests on Linux + swift-format + pytest with synthetic sessions) and `ios-check.yml` green on every push to `claude/construction-3d-mapping-app-nzm3bb`; `ios-testflight.yml` produces a processed TestFlight build.
- **Device (owner, per TestFlight test plan):** install → onboarding passes LiDAR/permission checks → create project/level/room → 2-min session at home with 3 markers, 3 stills, 4 tapped corners → review shows trajectory, frame count, markers, landmarks → session visible in Files → copied to the PC.
- **Pipeline (PC):** `vividhome ingest` + `validate` pass on the real session; `apriltag` finds all 3 markers with < 3 cm spread across observations; `plan add` + `calibrate` on one PDF page and one photographed paper plan; `align` from the tapped landmarks; `inspect` shows the trajectory on the plan with thumbnails.
- **Docs:** design docs, 16 ADRs, schedule, UI brief and AI roadmap exist, are linked from the README, and match what was built.
- **Exit criterion for the 2 weeks:** the owner can capture a room per phase with VividHome and the markers following the protocol, get the data onto the PC, and see it on the plan.
