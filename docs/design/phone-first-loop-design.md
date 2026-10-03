# The first loop on the phone: calibrate, align and look, without the PC

Design for [ADR-0030](../adr/0030-the-phone-owns-the-first-loop.md), 2026-10-02. The mechanics here are the implementer's and may change; the decision they serve is in the ADR. Nothing here is built yet.

## 1. Goals and non-goals

Goals: a capture is on the plan before the owner leaves the room, with no PC involved; the files the phone writes are the ones the PC already reads, so the PC adopts them rather than redoing them; every piece of maths is in the core package and tested on Linux against the pipeline's answer.

Non-goals: validation on the phone beyond what the app already counts (the PC's `validate` stays the independent check); markers, meshes, splats and anything from ADR-0009's later layers; replacing the PC's pages, which stay for the keyboard route and for batch work.

## 2. Calibrate on the phone

**Built 2026-10-02, walked by nobody.** `PlanCalibrateView`, reached from the plan screen's *Scale* button; the maths in `PlanFile.calibrated` and `PlanDistance`, pinned to the Python's numbers; `ingest` adopts the result. Differences from the sketch below: a tap places a point and dragging it shows the loupe, rather than a loupe during a press, so a pan and a placement cannot be confused.

**Where.** The level's plan screen, which already places room pins (`PlanCoverageView`). A *Scale and origin* mode with the same three taps as the PC's page:

1. one end of a printed dimension line;
2. the other end, then the printed length typed as written (`25' 0"`, `3.81m`), parsed in the core package by the same rules as `plan.py`;
3. the house origin.

Rotation and floor height are fields with defaults of 0, as on the PC. Each tap goes through a magnifier (a loupe above the finger, as iOS text selection does), because a dimension tick is a few pixels wide and a fingertip is forty. Pinch to zoom is already there.

**What it writes.** `metres_per_pixel`, `origin_px`, `rotation_deg` and `floor_height_m` into `plans/<level>.json`, the app's own file (§13). `PlanFile` already models them. The scale sanity check the runbook describes is shown on screen: the drawing's width in metres from the numbers just entered.

**On the PC.** `ingest` copies `plans/` for levels the store lacks, verbatim, which already carries a calibration. New rule: when the store's copy is uncalibrated and has no alignments, a calibrated copy from the phone replaces it; once alignments exist the store's calibration is the frame they were solved in and stays, as `plan calibrate` already refuses without `--force`.

## 3. Align on the phone

**Superseded in shape by [ADR-0031](../adr/0031-the-capture-proves-itself-before-you-leave.md) and `field-proof-design.md`, 2026-10-03:** the pairing moves into the capture, guided by a room outline on the plan, and solves live. The screen below is kept for free captures that have no outline.

**When.** First as a screen reached from a capture (Captures, the capture, *Place on the plan*), and later offered right after Stop, when the corners are fresh. The pairing is the PC page's, natively: the plan on top, a top-down plot of the walk with the tapped corners below, tap a corner, tap its place on the plan, two pairs minimum. The plan taps use the magnifier.

**The solver.** Rigid 2D fit (rotation and translation, no scale), the same Umeyama-style closed form as `align.py`, in VividHomeCore as `PlanAlignment.solve(pairs:)`. Inputs are session `(x, z)` for each landmark and house `(x, z)` from the plan tap through `plan_to_house`, which also moves to the core package. Outputs `T_hs`, the per-pair residuals, the RMS and the maximum, with the same 0.3 m refusal and the same wording the PC uses. The floor height comes from the mesh when the session has one, else the lowest landmark, as `floor_y_session` does; port that rule too.

**What it writes.** `sessions/<project>/alignments/<session-id>.json`, beside `plans/`: the PC's shape (`session_id`, `level`, `T_hs` column-major, `pairs`, `rms_m`, `max_residual_m`, `method`, `floor_source`, `created_at`) plus `"source": "app"`. A session-level file would break rule 6 (raw sessions are immutable) and `derived/` is the pipeline's, so it is project-level, like the plan.

**To the PC.** The uploader already sends `plans/<file>` beside a capture; it sends `alignments/<session-id>.json` the same way (§14.1 gains the path). `ingest` adopts an alignment when the store has none for that session and the store's calibration is the one the phone used (same `metres_per_pixel` and `origin_px`), and says so. `vividhome align` on the PC overwrites it deliberately, as now. The index reports `aligned` as before and adds `alignment_source`.

## 4. Look on the phone

**The level view.** A native screen replacing the web view for this loop: the plan raster with pinch and pan, each aligned capture's walk as a polyline, a dot per keyframe at a stride and a diamond per still, a tick for the heading, the tapped corners, colour per phase with a toggle. Tapping a dot opens the existing `PhotoDetailView`, which already turns the photo upright and labels it. Everything the inspect page computes in Python (`house_to_plan`, the heading projection, the photo list) moves to the core package; the page's own JavaScript is small and stays as it is for the browser.

**What stays a web view.** Whatever the PC renders beyond this: the 3D viewer, meshes, splats, labels (ADR-0011, ADR-0028). *Rendering on the PC* keeps its row.

## 5. Keeping the two honest

The contract job (ADR-0021) already runs the `vividhome-fixture` binary and validates its output with the pipeline. It gains a round trip for this: the fixture writes a calibrated plan and an alignment solved from known pairs; the pipeline recomputes both from the same inputs and the numbers must agree to 1e-6, and `inspect` must draw the fixture's walk at the pixels the core package predicts. Any drift between the Swift and the Python fails CI, not a visit.

## 6. Sequencing

1. **Calibrate on the phone.** Smallest, and it removes the PC from the first visit's critical path on its own: a capture sent with a calibrated plan needs only `align` and `inspect` on the PC.
2. **Align and the level view**, together: a solved alignment with nothing to show it on is not a feature.
3. **The alignment to the PC**: the upload path, `ingest` adoption, the index field, the contract round trip.
4. **Pairing right after Stop**, once the screen has been used a few times.

## 7. Risks

- **Two implementations drift.** Mitigated by §5; the Python stays the reference and the Swift is checked against it in CI.
- **Precision.** A 20 mm-per-pixel plan makes a five-pixel tap error 10 cm. The magnifier and pinch zoom are not optional; the residual the solver reports is what tells the owner to try again.
- **The phone's fit versus the PC's.** When the PC later refines an alignment with markers, the phone keeps showing its own until it next fetches the index. The level view shows which it is drawing.
- **The only copy.** Nothing here changes the rule that a capture is deleted from the phone only on the PC's word; a visit that never reaches the PC stays on the phone, and the free-space line keeps saying so.
