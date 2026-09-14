# VividHome schedule

Fourteen days to a usable capture app, then a roadmap keyed to construction phases. Day 0 is 2026-09-11, the day the plan was approved; day 14 is 2026-09-25. "Implementer" is the coding agent building the repository; "Owner" has the phone, the accounts and the house. If a day's acceptance check fails, the next day starts by fixing it.

## Days 0 to 14

| Day | Implementer | Owner | Acceptance check |
|---|---|---|---|
| 0 (09-11) | Plan approved; nothing to build. | Enroll in the Apple Developer Program (individual, $99); turn on two-factor authentication; read `docs/owner-setup.md`. | Enrollment submitted and payment confirmed by email. |
| 1 (09-12) | Repo scaffold; docs skeleton; `ios/project.yml`; `VividHomeCore` with first tests; the three workflows; "Hello ARKit" screen with LiDAR check and build label. | None. | `core-test` green; `ios-check` compiles for the simulator; README links every doc. |
| 2 (09-13) | First `ios-testflight` run; walk the fallback ladder if signing or upload fails; `Transform` and `KeyframePolicy` with tests; `docs/session-format.md`. | Once enrolled: App ID, app record, Admin API key, TestFlight group, four GitHub secrets (owner-setup steps 2 to 6). | Secrets present; a workflow run reaches the export step. |
| 3 (09-14) | Fix whatever build #1 needs; `FrameRecord` and `SessionManifest` with tests. | Install TestFlight and build #1; run the test plan. | **TestFlight build #1** installed; app opens, LiDAR check passes, build label matches the run number. |
| 4 (09-15) | `ARSessionController`, `SessionRecorder`, `FrameWriter`, `JPEGEncoder`, depth and confidence writing, Capture HUD; a first `vividhome validate`. | Build #2: 1-minute capture at home; copy to the PC; run `vividhome validate`; paste the output. | A session with `frames.jsonl`, `rgb/`, `depth/` and `conf/` reaches the PC; `validate` passes or names specific defects. |
| 5 (09-16) | `markers.py`, `docs/markers.md`, `synth.py`, full `validate.py`, pytest on the synthetic session. | Print and laminate 20 markers; hand over the day-4 session for `samples/`. | pytest green in CI; `markers.pdf` prints at 20.0 cm; `samples/` holds a trimmed real session under 6 MB. |
| 6 (09-17) | Stills via `captureHighResolutionFrame`, `MarkerLogger`, `LandmarkLogger`, `MeshExporter`. | Build #3: run the test plan. | A still with pose in `stills/`; a marker in view appears in `markers.jsonl`; a tap adds a landmark; `mesh.obj` written at stop. |
| 7 (09-18) | `HealthPolicy`, interruption handling, picker persistence, Session review with Open in Files. | Build #4: a 5-minute room with markers and tapped corners; transfer and validate. | Session finalises; review shows trajectory and counts; Open in Files works; `validate` passes; at least two marker IDs logged. |
| 8 (09-19) | `apriltag.py` with PnP, verified on `samples/` and the day-7 session. | None. | `vividhome apriltag` finds every marker in the day-7 session with under 3 cm spread; synthetic PnP test green. |
| 9 (09-20) | `plan.py` (add, calibrate), `align.py`, `inspector.py`. | Provide one plan PDF page and one photographed paper plan. | `plan add` and `calibrate` produce `plans/L1.json` for both inputs; `align` fits the day-7 landmarks and reports residuals; `inspect` shows the trajectory on the plan. |
| 10 (09-21) | Feedback fixes, Settings, Test plan view, Markers screen. | Build #5: run the test plan. | Test plan renders in-app; settings persist across launches; Markers screen lists IDs and seen counts. |
| 11 (09-22) | Crash-safe finalise, drop-rate and fps tuning. | Build #6: force-quit mid-session once, then relaunch. | The interrupted session is repaired on relaunch and passes `validate`; dropped-frame rate shown in review. |
| 12 (09-23) | End-to-end review; docs updated to match the build. | Dry run: 3 rooms plus stairs at home with markers and landmarks; transfer, validate, apriltag, align, inspect. | **Capture-ready** (definition below). |
| 13 (09-24) | Stretch: LAN upload; `docs/owner-setup.md` polish from the owner's notes. | Follow `owner-setup.md` cold and note anything unclear. | Owner confirms every step matched what they saw. |
| 14 (09-25) | Tag `v0.1`; file the weeks-3+ backlog. | None. | **v0.1** tagged on a commit with all three workflows green; backlog issues exist. |

## Milestones

**TestFlight build #1 (target day 3).** `ios-testflight` archives unsigned, exports with cloud-managed signing and uploads; the owner installs the processed build, the app opens, the LiDAR check passes and the build label shows the run number. This proves enrollment, the App ID, the Admin key, the secrets and signing at once.

**Capture-ready (target day 12).** The owner can capture a room per phase following `docs/capture-protocol.md`, get the data onto the PC, and see it on the plan. Concretely: a 2-minute session at home with 3 markers, 3 stills and 4 tapped corners; review shows trajectory, frame count, markers and landmarks; the session is copied to the PC; `ingest` and `validate` pass; `apriltag` finds all 3 markers with under 3 cm spread; `plan add` and `calibrate` work on a PDF page and a photographed plan; `align` fits the landmarks; `inspect` shows the trajectory on the plan.

**v0.1 (day 14).** Everything above, tagged, with the design docs, 16 ADRs, schedule, UI brief and AI roadmap linked from the README and matching what was built.

## Weeks 3 to 8: roadmap keyed to construction phases

Ordered by dependency, because construction sets the dates. Build order: session pose graph across markers (scipy or GTSAM); Open3D TSDF meshes; per-room splats (splatfacto or Postshot, seeded with ARKit poses) as SOG; the `web/` viewer (three.js plus Spark); AI roadmap trials 1 to 4 during rough-in; then AR x-ray mode in the app.

| Construction phase | What to capture | Should have landed before the phase begins |
|---|---|---|
| Site and foundation | Under-slab plumbing, sleeves and penetrations before the pour; utility entries; first markers on slab or foundation walls; stills of every stub-up with a tape. | v0.1. If this phase starts before day 15, use the fallback capture path. |
| Framing | One session per room: walls square-on floor to ceiling, headers, blocking, nail plates; markers on subfloor at door thresholds, top plates and rough-opening jambs; corners and thresholds tapped. | Pose graph across markers (week 3) and TSDF meshes (weeks 3 to 4): framing becomes the metric skeleton for every later phase. |
| Electrical, plumbing and HVAC rough-in | The highest-value phase: a still of every box, cable run, pipe, penetration, CSST gas line, duct and register from about 1 m with a tape in frame; one session per trade per room when trades come on different days. | First splat trial (weeks 4 to 5); viewer alpha with plan overlay and click to photo (weeks 5 to 6); AI trial 1 ("What am I looking at?") and trial 4 (auto-tagging and search) scored on these stills. |
| Insulation | Last sight of framing with everything in: a quick session per room; confirm markers are still visible. | Viewer phase toggle; AI trial 3 (capture coaching) so re-shoot lists arrive while things are still uncovered; AI trial 2 (stitching) to verify cross-session residuals. |
| Drywall | After hanging, before finish: a session per room; markers on jambs and subfloor still tie it to rough-in. | Cross-phase chains through marker IDs verified with residual reports; measurement tool in the viewer; first stud-centre projection onto walls. |
| Finish | Final walk of every room, stairs and exterior; align through invariant geometry (openings, corners, stairs) against the plan; photograph markers before removal. | Full viewer with phase slider, labels and SOG splats per room (weeks 6 to 8); AR x-ray mode in the app after that. |

## How to re-plan

The schedule assumes framing starts no earlier than day 15 (2026-09-26). If the builder moves earlier, do not compress the app work: switch to the fallback capture path in `docs/owner-setup.md` section 12 (a free ARKit recorder with the same markers and protocol), pull the marker generator and `docs/markers.md` forward, add an `ingest` converter for the chosen recorder, and keep building VividHome on the same schedule. Capture-ready then means markers printed, protocol read, converter and `validate` working.

If Apple enrollment slips past day 3, the TestFlight milestone moves day for day and nothing else does. If a build fails twice on signing, walk the fallback ladder in ADR-0003. If rough-in arrives before the pose graph or viewer exist, capture anyway; the session format allows processing later without recapture.
