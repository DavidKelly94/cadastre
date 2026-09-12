# Igloo schedule

Fourteen days to a usable capture app, then a roadmap keyed to construction phases. Day 0 is 2026-09-11, the day the plan was approved; day 14 is 2026-09-25. "Implementer" is the coding agent building the repository; "Owner" is the person with the phone, the accounts and the house. Every day ends with an acceptance check; if it fails, the next day starts by fixing it.

Fixed facts the schedule depends on: no Mac, so every iOS build goes through GitHub Actions and TestFlight (up to 30 minutes per build); Apple enrollment takes a day or more; framing starts no earlier than day 15.

## Days 0 to 14

| Day | Implementer | Owner | Acceptance check |
|---|---|---|---|
| 0 (09-11) | Plan approved; nothing to build. | Enroll in the Apple Developer Program (individual, $99), turn on two-factor authentication, read `docs/owner-setup.md`. | Enrollment submitted and payment confirmed by email. |
| 1 (09-12) | Repo scaffold; docs skeleton (design docs, ADRs, schedule, UI design brief, AI roadmap); `ios/project.yml`; `IglooCore` package with first tests; the three workflows; "Hello ARKit" screen with LiDAR check and build label. | None. | `core-test` green on the development branch; `ios-check` compiles for the simulator; README links every doc. |
| 2 (09-13) | First `ios-testflight` run; walk the fallback ladder if signing or upload fails; `Transform` and `KeyframePolicy` with tests; `docs/session-format.md`. | Once enrolled: App ID, app record, Admin API key, TestFlight group, four GitHub secrets (owner-setup steps 2 to 6). | Secrets present; a workflow run reaches the export step. |
| 3 (09-14) | Fix whatever build #1 needs; `FrameRecord` and `SessionManifest` with tests. | Install TestFlight and build #1; run the test plan. | **TestFlight build #1** installed; app opens, LiDAR check passes, build label matches the run number. |
| 4 (09-15) | `ARSessionController`, `SessionRecorder`, `FrameWriter`, `JPEGEncoder`, depth and confidence writing, Capture HUD; a first `igloo validate` (files present, JSONL parses). | Build #2: 1-minute capture at home, copy it to the PC, run `igloo validate`, paste the output. | A session folder with `frames.jsonl`, `rgb/`, `depth/` and `conf/` reaches the PC; `validate` passes or names specific defects. |
| 5 (09-16) | `markers.py`, `docs/markers.md`, `synth.py`, full `validate.py`, pytest on the synthetic session. | Print and laminate 20 markers; hand over the day-4 session for trimming into `samples/`. | pytest green in CI; `markers.pdf` prints at 20.0 cm; `samples/` holds a real trimmed session under 6 MB. |
| 6 (09-17) | Stills via `captureHighResolutionFrame`, `MarkerLogger`, `LandmarkLogger`, `MeshExporter`. | Install build #3 and run the test plan. | Build #3: a still with pose in `stills/`; a marker in view appears in `markers.jsonl`; a tap adds a line to `landmarks.jsonl`; `mesh.obj` is written at stop. |
| 7 (09-18) | `HealthPolicy`, interruption handling, picker persistence, Session review with Open in Files. | Build #4: a 5-minute room with markers and tapped corners; transfer and validate. | Build #4: the session finalises; review shows trajectory and counts; Open in Files works; `validate` passes; at least two marker IDs logged. |
| 8 (09-19) | `apriltag.py` with PnP, verified on `samples/` and the day-7 session. | None. | `igloo apriltag` finds every marker in the day-7 session with under 3 cm spread across observations; synthetic PnP test green. |
| 9 (09-20) | `plan.py` (add, calibrate), `align.py`, `inspector.py`. | Provide one plan PDF page and one photographed paper plan. | `plan add` and `calibrate` produce `plans/L1.json` for both inputs; `align` fits the day-7 landmarks and reports residuals; `inspect` shows the trajectory on the plan. |
| 10 (09-21) | Feedback fixes, Settings, Test plan view, Markers screen. | Install build #5 and run the test plan. | Build #5: test plan renders in-app; settings persist across launches; Markers screen lists IDs and seen counts. |
| 11 (09-22) | Crash-safe finalise, drop-rate and fps tuning. | Install build #6; force-quit mid-session once, then relaunch. | Build #6: the interrupted session is repaired on relaunch and passes `validate`; dropped-frame rate is reported in review. |
| 12 (09-23) | End-to-end review; docs updated to match the build. | Dry run: 3 rooms plus stairs at home, with markers and landmarks; transfer, validate, apriltag, align, inspect. | **Capture-ready** (definition below). |
| 13 (09-24) | Stretch: LAN upload; `docs/owner-setup.md` polish from the owner's notes. | Follow `owner-setup.md` cold and note anything unclear. | Owner confirms every step matched what they saw. |
| 14 (09-25) | Tag `v0.1`; file the weeks-3+ backlog (TSDF, pose graph, splats, viewer, AI trials). | None. | **v0.1** tagged on a commit with all three workflows green; backlog issues exist. |

"Build #2" means the second build the owner installs; the number shown in the app is the GitHub run number.

## Milestones

**TestFlight build #1 (target day 3).** The `ios-testflight` workflow archives unsigned, exports with cloud-managed signing and uploads; App Store Connect processes the build; the owner installs it from TestFlight, the app opens, the LiDAR check passes and the build label shows the run number. This proves enrollment, the App ID, the Admin API key, the four secrets and signing at once. If it slips, code work continues on `core-test` and `ios-check`; the milestone moves, the rest of the plan does not.

**Capture-ready (target day 12).** The owner can capture a room per phase with Igloo and the markers following `docs/capture-protocol.md`, get the data onto the PC, and see it on the plan. Concretely: install, onboarding passes, create project, level and room, a 2-minute session at home with 3 markers, 3 stills and 4 tapped corners, review shows trajectory, frame count, markers and landmarks, the session is visible in Files and copied to the PC; `ingest` and `validate` pass; `apriltag` finds all 3 markers with under 3 cm spread; `plan add` and `calibrate` work on one PDF page and one photographed plan; `align` fits the tapped landmarks; `inspect` shows the trajectory on the plan with thumbnails.

**v0.1 (day 14).** Everything above, tagged, with the design docs, 16 ADRs, schedule, UI brief and AI roadmap linked from the README and matching what was built. Exit criterion for the two weeks: the owner can capture a room per phase, get the data to the PC, and see it on the plan.

## Weeks 3 to 8: roadmap keyed to construction phases

Weeks 3 to 8 are ordered by dependency, not by date, because construction sets the dates. Build order: session pose graph across markers (scipy or GTSAM), Open3D TSDF meshes, per-room splats (nerfstudio splatfacto or Postshot seeded with ARKit poses) converted to SOG with `splat-transform`, the `web/` viewer (three.js plus Spark: plan overlay, phase toggle, click to nearest photos, two-click measure, labels), AI roadmap trials 1 to 4 during rough-in, then AR x-ray mode in the app.

| Construction phase | What to capture | Should have landed before the phase begins |
|---|---|---|
| Site and foundation | Under-slab plumbing, sleeves and penetrations before the pour; footing drains; utility entries; first markers on slab or foundation walls; stills of every stub-up with a tape measure. | v0.1 (capture app, markers, `validate`, `align`). If this phase starts before day 15, use the fallback capture path. |
| Framing | Every room, one session per room: walls square-on floor to ceiling, headers, blocking, nail plates, stair stringers; markers on subfloor at door thresholds, top plates and rough-opening jambs; expected marker IDs entered per room; corners and thresholds tapped. | Pose graph across markers (week 3) and TSDF meshes (weeks 3 to 4), so framing becomes the metric skeleton every later phase hangs on. |
| Electrical, plumbing and HVAC rough-in | The highest-value phase: every box, cable run, pipe, penetration, CSST gas line, duct and register, a still from about 1 m square-on with a tape in frame; one session per trade per room if trades come on different days (phase labels `electrical`, `plumbing`, `hvac`). | Pose graph and TSDF in use; first splat trial (weeks 4 to 5); viewer alpha with plan overlay and click to photo (weeks 5 to 6); AI trial 1 ("What am I looking at?") and trial 4 (auto-tagging and search) scored on these stills. |
| Insulation | Last sight of framing with everything in: a quick session per room; confirm markers on top plates and jambs are still visible. | Viewer phase toggle; AI trial 3 (capture coaching) so re-shoot lists arrive within a day, while things are still uncovered; AI trial 2 (stitching) to verify cross-session residuals. |
| Drywall | After hanging, before finish: a session per room to create the post-drywall epoch; markers on jambs and subfloor still tie it to rough-in. | Cross-phase chains through marker IDs verified with residual reports; measurement tool in the viewer; first stud-centre projection onto walls. |
| Finish | Final walk of every room, stairs and exterior; align through invariant geometry (openings, corners, stairs) against the plan; photograph each marker before removal. | Full viewer with phase slider, labels and SOG splats per room (weeks 6 to 8); AR x-ray mode in the app after that. |

## How to re-plan

The schedule assumes framing starts no earlier than day 15 (2026-09-26). If the builder moves earlier, do not compress the app work: switch to the fallback capture path in `docs/owner-setup.md` section 12 (NeRFCapture, Stray Scanner or Record3D, with the same markers and protocol), pull the marker generator and `docs/markers.md` forward to the earliest possible day, add an `ingest` converter for the chosen recorder, and keep building Igloo on the same schedule. Capture-ready then means "fallback capture-ready": markers printed, protocol read, converter and `validate` working.

Other adjustments: if Apple enrollment slips past day 3, the TestFlight milestone moves day for day and nothing else does. If a build fails twice on signing, walk the fallback ladder in ADR-0003 before touching anything else. If rough-in arrives before the pose graph or viewer exist, capture anyway; the session format guarantees that everything can be processed later without recapture.
