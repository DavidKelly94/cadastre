# Status

What is built, what is not, and what is blocked. Keyed to `docs/schedule.md`'s
day plan, but this file is the honest one: the schedule says what was planned,
this says what is true.

**Update this in the same commit as the work.** A status file that lags is worse
than none, because it is believed.

Last updated: 2026-09-14, after the rename to VividHome (ADR-0024).

## The short version

The pipeline is feature-complete and tested. The Swift core is complete and
tested. The iOS capture layer is written and compiles, but **has never run** —
there is no device build yet, so nothing below marked "compiles" should be read
as "works". The screens do not exist.

## Pipeline (`pipeline/`) — complete

| Command | State | Notes |
|---|---|---|
| `validate` | done | All 8 rules, `--skip-images`, `--skip-depth` |
| `synth` | done | Writes a format_version 2 session |
| `markers` | done | Generates `VH-000`–`VH-059`, PDF and PNG |
| `apriltag` | done | 36h11 via `cv2.aruco`, subpixel refinement, IPPE_SQUARE |
| `plan` | done | `add`, `calibrate`; parses `12' 6"` |
| `align` | done | Umeyama 2D, rotation and translation only |
| `inspect` | done | Level page, groups multi-phase sessions by earliest trade |
| `ingest` | done | Zip-slip and path-traversal guarded |
| `serve` | done | Local server for the browser pages |

14 modules, **232 tests passing**, ruff clean.

## Swift core (`ios/VividHomeCore/`) — complete

13 modules, 11 test files, all Linux-tested. `Transform`, `SessionID`,
`Records`, `Coding`, `KeyframePolicy`, `HealthPolicy`, `JSONLWriter`,
`RowPacker`, `SessionLayout`, `SessionLifecycle`, `BoundedWriteQueue`,
`SessionStore`, plus the `vividhome-fixture` binary the contract job runs.

## iOS capture layer (`ios/VividHome/`) — written, never run

| File | State |
|---|---|
| `ARKitBridge` | compiles |
| `ARSessionController` | compiles |
| `SessionRecorder` | compiles |
| `FrameWriter`, `JPEGEncoder`, `PixelBufferPacker` | compiles |
| `StillCapture` | compiles |
| `MarkerLogger`, `LandmarkLogger` | compiles |
| `MeshExporter` | compiles |
| `ProjectStore` | **not written** |

**Not one line of this has executed.** ARKit does not run in the simulator, and
there is no device build. Everything here is unverified behaviour behind a
successful compile.

## Screens — none built

Onboarding, ProjectPicker, Project overview, Level view, RoomPicker, Capture
HUD, Session review, Markers, Settings, Test plan. Three of them now exist in a first form: **Capture setup**, **Capture HUD**
and **Session review**. The app can record a real session to disk.

Design decisions for these are settled in `docs/ui/design-brief.md` §10.
`docs/ui/design-canvas-brief.md` is the self-contained handoff for Claude
Design. **Both it and the design brief's §2 motif are orphaned by the rename**:
the parcel/plat imagery came from the meaning of "cadastre" and needs
replacing. The tokens, type and contrast work are unaffected.

The rename also left false prose in six documents, since corrected: the sweep
replaced the old name inside sentences that were *about* that word rather than
labels for the product ("a *vividhome* is the authoritative register of what
exists on a parcel of land", "pronounced kuh-DASS-ter", the App Store clash with
app id 1507993968, the `.com`/`.io` French products). `docs/naming-investigation.md`
was rewritten as a closed record because every factual claim in it had inverted.
Identifiers were never affected — only prose. Sweep by symbol, not by word.

## First real capture, 2026-09-15

Build 23 recorded a finished room and the output was checked against the format
by hand. It passes, including the one convention most likely to be silently
wrong:

- 241 keyframes over 82.5 s, `i` contiguous, `t` non-decreasing.
- **Rotations orthonormal to 4e-7** against rule 4's 1e-3, `det(R)` exactly
  +1. That is the column-major flatten in `ARKitBridge.transform` confirmed on
  real ARKit poses: a transpose here would still have produced orthonormal
  rotations and a plausible file, and would have mirrored the whole trajectory.
- Camera path 20.68 m over a 4.6 x 1.0 x 4.0 m volume — a real walk, not a
  phone sitting still.
- Tracking `normal` on every frame; `fx` drifts 1323.6 to 1375.4 with autofocus,
  which is why the format stores `K` per frame rather than once.
- Mesh: 321,683 vertices, 580,001 faces, max OBJ face index exactly 321,683 —
  1-based with no off-by-one. `mesh_classes.u8` is exactly one byte per face and
  its histogram matches `mesh.json` exactly.

`markers.jsonl` is empty because no markers are printed yet, which is expected
and is why the session cannot be chained to another phase.

## Landmarks are visible now

The first capture exposed a real gap rather than a bug: a tapped landmark wrote
a line to a file and did nothing else. There was no way to tell a mark from a
missed tap, no way to see which corners were already done, and no reason to
trust the raycast had landed where it was aimed. They are now drawn in the AR
view, coloured by kind, with a billboarded label.

They persist for the life of the session, which is as far as ARKit's world frame
goes. **They do not carry into the next session**, and no amount of app work
changes that: the origin of each session's frame is wherever the capture
started. Tying two visits together is what printed markers are for (ADR-0006),
and placing both on a shared plan is ADR-0007 plus ADR-0025. Neither is built.

## The capture layer has a caller

Until 2026-09-15 the capture layer was 1,314 lines with **no caller**: nothing
outside `Capture/` referenced `SessionRecorder` or `ARSessionController`, and
the app's AR view built its own bare `ARSCNView`. Every part was unit tested and
none of them had ever run together.

`CaptureCoordinator` is that caller. It owns the assembly the parts assumed but
nobody had written: which writers exist, who closes them, and in what order a
session stops. Two things it settles that were genuinely ambiguous before:

- **Stills share the recorder's `FrameWriter`.** Two writers over one layout
  would mean two serial queues appending to `stills.jsonl` and two flush
  counters, so a still and a keyframe landing together could interleave
  mid-line. `SessionRecorder` now exposes its writer for that reason.
- **Markers and landmarks get their `JSONLWriter`s at start**, which also
  creates the two files. `vividhome validate` requires both to exist even when
  nothing was logged, so a session with no markers still validates rather than
  failing on a missing file.

What is built, honestly: it records, writes every file the format specifies,
logs markers and landmarks, exports the mesh, and shows what was saved. What is
not: no trajectory plot in Session review (it needs the plan work from
ADR-0025), no coverage checklist, and the HUD scrim is a fixed 72% because
nothing samples the camera feed to know when to raise it to 88%. Chrome over a
sunlit opening is the case most likely to be unreadable, and it needs a device
to judge.

## TestFlight

**Build 21 uploaded and was accepted** on 2026-09-14 — the first build to reach
TestFlight. The whole signing chain works: Admin API key, cloud signing on the
runner, export, upload. Build 21 was rejected once first, for having no app icon
at all (90713 and 90022); an interim icon fixed it.

Two things about build 21 specifically:

- **It reports itself as `1.0 (1)`.** The generated Info.plist carried XcodeGen's
  default version keys as literals, which beat the `MARKETING_VERSION` and
  `CURRENT_PROJECT_VERSION` build settings and the workflow's per-run override.
  So `manifest.json` provenance and the on-screen build number were both wrong,
  and build 22 would have been rejected as a duplicate build number. Fixed; from
  22 on the number is the run number.
- **ITMS-90984 is a warning, not a rejection.** `arkit` in
  `UIRequiredDeviceCapabilities` is unsupported on visionOS, which is correct —
  the app needs LiDAR on an iPhone. Silenced by unticking Vision Pro
  availability in App Store Connect, not by changing the app.

## Floor plans in the app

**Specified, not built, on either side.** [ADR-0025](adr/0025-plans-are-a-project-level-asset.md)
decides that the app imports, displays and places rooms on a floor plan while
alignment stays on the PC, and `docs/session-format.md` section 13 now carries
the contract for it. Nothing implements it yet:

- iOS: no plan import, no plan view, no placement UI. Two screens that do not
  exist, on top of the ten that already do not.
- Pipeline: `vividhome validate --project` does not exist, `ingest` does not copy
  a `plans/` directory, and `plan add` still assumes it creates one.

The schedule risk is real and is named in ADR-0025's consequences: this is scope
added during a 14-day sprint, deliberately. Nothing in sections 1 to 12 of the
format depends on it, and a project with no `plans/` directory stays valid, so
the capture path is not blocked by it.

## App icon

`ios/VividHome/Resources/Assets.xcassets/AppIcon.appiconset` holds an **interim**
icon: a house with a section cut out of it exposing a stud and a service run,
generated by `ios/AppIcon/generate_icon.py` from the palette tokens. It exists
because the first real TestFlight upload was rejected for having no icon at all
(App Store Connect 90713 and 90022) — the archive and the cloud signing both
succeeded, so this was the only thing between the build and TestFlight.

It is not the designed icon. The original concept — a survey benchmark on a
ruled cadastral grid — died with the rename, and this replaces it with something
that does not depend on what the product is called. Replace it when the design
canvas produces a real one.

## CI

Colours are not recorded here — they go stale within minutes and GitHub is the
source of truth. What each check *covers* is the durable fact:

| Check | Runs on | Covers |
|---|---|---|
| `swift` | every push, Linux | `VividHomeCore` unit tests. Cannot see the app target. |
| `python` | every push, Linux | ruff and the full pipeline suite. |
| `contract` | every push, Linux | `VividHomeCore` writes a session, `vividhome validate` reads it. **The only check that puts both implementations in contact.** |
| `ios-check` | **pull requests only** | `xcodebuild` of the app target. The only thing that compiles the ARKit layer, and the only check that catches a core change breaking the app. |
| `ios-testflight` | push to the work branch | No-ops: a Linux preflight gates the macOS build on `ASC_KEY_ID`. |
| `Claude Review` | pull requests | The shared review rubric. First ran 2026-09-13, having silently failed at startup before that. |

Two gaps worth knowing. `swift` passing does **not** mean the app compiles —
Linux never builds the app target, so a `VividHomeCore` change can break
`SessionRecorder` and only `ios-check` will say so. And nothing in CI runs
ARKit, so no check here can tell you the capture works.

## Blocked on the owner

1. **Four App Store Connect secrets** — `ASC_KEY_ID`, `ASC_ISSUER_ID`,
   `ASC_PRIVATE_KEY_P8`, `APPLE_TEAM_ID`. Until these exist `ios-testflight`
   no-ops and there is no build on a phone. This is the single biggest blocker:
   everything in the capture layer stays unverified without it.
2. **Register `vividhome.ai`, then the App ID** `ai.vividhome.app` (ADR-0024).
   The domain comes first: the identifier is its reverse-DNS form and the App
   ID is the point of no return. `.ai` carries a two-year minimum.
3. **The first real capture** — needed to confirm `R_am`, ARKit buffer strides
   and `ARReferenceImage` validation, and to fill `samples/`, which is empty.
4. **Print and laminate the markers** (`docs/markers.md`), verifying 20.0 cm
   with a tape.
5. **Remove `davidkelly-snoday` as a collaborator** — it still has write access.

## Known gaps

- `samples/` is empty. The schedule wanted a trimmed real session there by day 5.
- No device has ever run the app, so the test plan has never been executed.
- The design canvas does not exist; §11 of the brief holds three questions that
  need a phone in sun and in an unlit basement.
