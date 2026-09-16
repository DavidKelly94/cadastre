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
| `ingest` | done | Zip-slip and path-traversal guarded; files under the manifest's project |
| `serve` | done | Local server for the browser pages |

14 modules, **260 tests passing**, ruff clean.

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
`docs/ui/design-canvas-brief.md` is the self-contained handoff for the design
canvas, and **it is current again**: the orphaned parcel/plat motif is replaced
by the section cut — a wall face with a piece cut away showing framing and a
service run — which describes what the product does rather than what it is
called. It also now carries ADR-0026 (landmarks load-bearing, markers optional),
editable landmarks, and the two plan screens from ADR-0025. `design-brief.md`
§2 still holds the old motif and is the historical record.

The canvas is re-seeded and live, with its artboards under `docs/ui/canvas/`:
five HUD states, four screens, the two plan screens and a marks sheet. The
built page is not committed — it is ~2.5 MB of editor payload, and
`docs/ui/canvas/README.md` says which direction edits may travel so a canvas
edit and a repository edit do not silently overwrite each other.

The canvas the owner produced under the old name is superseded: it carries a
CADASTRE wordmark and CD-NNN marker ids, and its Session review caption says
plan alignment happens on the PC with no plan surface anywhere in ten screens.

Two things in the new canvas are unverified and deliberately so: whether the
section cut still reads as a wall rather than a progress bar at the 64 px size
used in room rows, and whether HUD chrome survives a real camera feed — the
scrim is a fixed 72% and needs a device in a dark room with a bright window.

The rename also left false prose in six documents, since corrected: the sweep
replaced the old name inside sentences that were *about* that word rather than
labels for the product ("a *vividhome* is the authoritative register of what
exists on a parcel of land", "pronounced kuh-DASS-ter", the App Store clash with
app id 1507993968, the `.com`/`.io` French products). `docs/naming-investigation.md`
was rewritten as a closed record because every factual claim in it had inverted.
Identifiers were never affected — only prose. Sweep by symbol, not by word.

## Markers are optional as of 2026-09-15

[ADR-0026](adr/0026-markers-are-optional-the-plan-is-the-frame.md) supersedes
ADR-0006's "at least two per room". The owner's objection was about adoption
rather than accuracy: a homeowner cannot place markers during a walkthrough, and
trades remove them. ADR-0006 had already conceded the second point and already
named the plan as the invariant frame, so this promotes its stated fallback to
the primary path.

What this changes in the code, beyond the docs:

- **Landmarks are load-bearing.** Session review now treats zero landmarks as a
  hard failure and fewer than three as an error, where markers-absent used to
  carry that weight and is now neutral.
- **The capture measures alignment quality, not a count**
  ([ADR-0027](adr/0027-alignment-quality-not-a-landmark-count.md)). `AlignmentQuality`
  in the core package scores spread and non-collinearity, with 14 tests on Linux
  CI including the claim the ADR rests on: two well-spread points beat three in
  a corner, which the old count rule got backwards. The HUD shows `FIT` and
  names what would help next; review judges the arrangement.
  **It measures geometry, never correctness** — a well-conditioned set of points
  that are all in the wrong place scores full marks, and the reading must never
  be read as saying the owner tapped what they meant.
- **Landmarks are editable and labelled usefully.** Tap a mark to select it,
  tap a surface to move it, rename or delete it. Labels carry the room slug
  (`kitchen corner 2`) rather than `corner-3`, because the only context a person
  pairing them with a plan has is the label itself. Nothing is written until the
  session stops, which is what makes correction free.
- **Still to do:** the HUD advises but does not yet refuse — a capture with an
  impossible fit can still be stopped and saved. `docs/ai-roadmap.md` item 5 is
  the next step, where the app proposes candidates from the wall mesh to drag
  rather than asking for taps at all.
- **Unmeasured:** the accuracy cost. Markers gave about 3 cm at 2 m. Plan plus
  landmarks is plausibly 5-15 cm and nobody has measured it. First thing to do
  once alignment runs; nothing should quote a number before then.

MVP scope is a building under construction where a plan exists. Finished homes
without plans are deferred.

## Plans label their own rooms, so the app reads them

`PlanLabelReader` runs Vision's text recognition over an imported plan and
offers the room names it finds, positioned where the label sits. Tapping one
places it there; dragging corrects it. Typing a room is still supported — a
hallway may not be labelled on the drawing at all — but a typed room is nudged
onto the plan, because a room with no placement produces a capture that cannot
reach the record (ADR-0026).

**Candidates are never written to `plans/<level>.json`.** They live in memory
and are recomputed on import. That is what keeps rule 9 true — an inference is
not a fact until a human accepts it — without adding a `confirmed` flag to the
contract that could disagree with the placements beside it. Accepting is the
drag, so confirming and correcting are one gesture rather than an approval step.

Unverified: how well it reads a phone photo of a drawing taped to a stud wall,
which is the case that matters and the one no amount of local reasoning settles.
The stop list is deliberately short — "store" and "office" are rooms — so expect
some title-block text to come through and need ignoring.

## Two UX findings from the first real use

Both from the owner running the app the way it will actually be used, and both
worse than they look.

**A capture could only be shared in the moment after it was stopped.** Session
review held the only share affordance, and Done returned to setup with no way
back. That is the wrong shape for the work — several rooms in one visit, then
everything to the PC afterwards — and it made review's checks something to read
immediately or lose. `SessionListView` lists every capture on the phone, with
its numbers, a share sheet and a delete. `SessionStore` in the core package
already had `sessions`, `manifest`, `countedStats` and `delete`; like the capture
layer before it, nothing had ever called them.

**The room was typed even when it was already placed on the plan.** Not a
convenience question: the room slug is the join key between a session and its
placement, so "Bedroom" and "bedroom 2" slugify differently and the capture then
belongs to a room nothing else knows about. Once a room is on the plan it is
picked from a list; typing is the exception, for a room that is genuinely new.
The plan screen can name one, which is also the right moment since you are
looking at the drawing.

## First accuracy number, and a measure that lied about it, 2026-09-16

The full path ran on a real capture: `plan add`, `calibrate`, `align`,
`inspect`, 6 correspondences, rms 0.2 cm. That residual is circular and means
nothing — the plan was drawn from the same taps it was then aligned against.

The number that does mean something came from a tape measure. The owner said the
room was about 11 x 11 ft. A helper script reported **20.6 x 14.6 ft**, which
looked like a capture that was badly wrong.

It was not. The script reported the axis-aligned bounding box of a room sitting
**42 degrees** off the session axes, and ARKit's yaw is whichever way the phone
happened to be facing at record time, so that angle is arbitrary and usually
nonzero. Measuring the walls instead:

```
corner 1 -> corner 2   3.12 m   10.2 ft
corner 2 -> corner 3   3.21 m   10.5 ft
corner 3 -> corner 4   3.18 m   10.4 ft
corner 4 -> corner 1   3.87 m   12.7 ft
```

**Three walls of an 11 ft room within 3 inches of each other, from a handheld
capture the owner described as rushed and sloppy.** That is the first evidence
that the capture geometry is good enough for the product to work, and it is
better than ADR-0026's 5 to 15 cm expectation.

The fourth wall is 21% longer than its opposite, and the render shows why:
`corner 4` sits inside the room rather than on its boundary. One mis-tap, plainly
visible in the data.

**Two things worth keeping.**

A bounding box is not a room. Any measure taken along the session axes is
meaningless, because those axes have no relationship to the building. Anything
that reports a dimension has to derive its own frame first.

And the check that found the mis-tap is one ADR-0027 said could not exist. That
ADR is right that `AlignmentQuality` measures the arrangement of the taps and
never whether they are correct — but **opposite walls of a rectangle are equal
whatever its aspect or rotation**, so a 4-corner room carries an internal
consistency check that needs no plan, no markers and no ground truth. Here it
reads 2% on one pair and 17% on the other. Worth considering for the capture HUD,
where it could catch the mis-tap while the owner is still standing in the room;
it is not built, and it does not apply to rooms that are not quadrilaterals.

## `align --pairs` could not express a single real label, 2026-09-16

The first attempt to align a real capture against a plan:

```
vividhome align: expected 'label=x,y', got 'bedroom'
```

The app labels a landmark `"<room-slug> <kind> <n>"` — `bedroom corner 1` — on
purpose: a label has to mean something to whoever pairs it with a drawing weeks
later, and `corner-3` does not. `--pairs` split its whole argument on
whitespace, which turns one such label into three tokens. So the scriptable
alignment path could not accept any label the app has ever written.

It separates on `;` now, keeping whitespace for labels that do not need it.

Two things worth keeping from this rather than just the fix:

**Neither half was wrong on its own.** The app's labelling is well reasoned and
commented; the parser's syntax is the obvious one. They were written apart and
never run together, which is the same shape as every other bug this week — the
session-to-project filing, the manifest fields, the contract claiming `ingest`
copies plans. What is missing is not care in either place but a path that
crosses both.

**`--web` was unaffected**, because it passes labels as JSON rather than
re-parsing a flat string. The bug is in the format, not the idea.

While fixing it, section 8 was found to document a landmark vocabulary the app
does not use (`corner-nw`, `corner-ne`, ...) and to claim labels are stable
across phases. They are not: the number is tap order within a session, so the
same corner can be `bedroom corner 1` in framing and `bedroom corner 3` in
rough-in. Alignment does not care — each session solves against the plan, never
against another session's labels — but the claim was false and is now removed
rather than quietly relied on.

## The manifest recorded "iPhone" as the device, 2026-09-15

Checking which build had produced a capture showed what else the manifest was
saying:

```
app_build app_version ios_version model
--------- ----------- ----------- -----
37        0.1.0       26.6.2      iPhone
```

`session-format.md` §4 gives `"model": "iPhone16,1"`. The app was writing
`UIDevice.current.model`, which is the string "iPhone" on every iPhone ever
made, so every session so far records nothing about the hardware.

It matters for this record specifically rather than as tidiness: LiDAR sensor
generation varies by model and depth quality with it, and a reader years from
now has no other way to know what produced the depth they are looking at. Raw
sessions are immutable, so every session written this way is permanently missing
it — the same shape of loss as the absolute-timestamp sessions.

Now read from `uname`. The decoding of its fixed-width `machine` buffer lives in
`HardwareIdentifier` in the core package with six tests, because that is the
part that can be quietly wrong: read the full width instead of stopping at the
terminator and the identifier carries trailing NULs, which prints as
"iPhone16,1" in a log and compares unequal to it.

**Nothing would have caught this.** `validate.py` does not inspect `device` at
all, so no rule was broken; it surfaced only because a command run to check the
build number happened to print the whole object. Sessions 33 through 37 keep the
generic string and cannot be corrected.

## Ingest filed sessions under the wrong project, 2026-09-15

Build 37's capture ingested clean — rule 2 silent, the timestamp fix confirmed on
real data rather than only in tests. The run showed a second bug on its way past:

```
ingested 20260915-152407_level-1_bedroom_2hhv3k
  C:\Users\David\claude projects\sessions\default\20260915-152407_...
```

`default`, for a capture the app recorded under `our-house`. `ingest` filed every
session under a `--project` flag that defaulted to `"default"` and never read the
manifest, while `align` and the marker map take the project slug *from* the
manifest (`align.project_slug`). So the capture went to one project and
everything derived from it would have gone to another, with nothing to say so.

It would not have surfaced until `plan add` and `align`, as a room whose plan
could not be found — a confusing failure a long way from its cause.

The manifest now decides, and `--project` is an override for re-filing one
deliberately. The regression test asserts against `align.project_slug` rather
than a repeated literal, so it keeps holding if the two ever diverge again for
some new reason.

**What this says about the earlier "no association" report.** The owner imported
a plan and saw nothing connect. That was diagnosed as the missing placement UI
and fixed there. This is a second, independent break in the same chain, in the
pipeline rather than the app, and it was found by running the thing rather than
by reading it.

## The app wrote absolute timestamps, 2026-09-15

The first session the owner put through `vividhome ingest` was **rejected**, and
correctly:

```
ERROR rule 2: frame 0: t=113885.284590708 is beyond duration_s + 1
```

`t` is *seconds since session start* (`session-format.md` §3 and §5). The app was
writing `ARFrame.timestamp` unchanged, which is time since the device booted — so
a phone up for 31 hours wrote `t = 113885` into a session lasting forty seconds.
Every `t` was wrong: keyframes, stills, marker sightings, tapped landmarks.

Fixed by `SessionTimeline` in the core package, which holds the session's zero
and is the only thing that converts. All four writers now share it.

**Why CI could not have caught this.** The `contract` job writes a session with
`vividhome-fixture` and validates it, but that fixture's times are relative by
construction (`Double(index) * 0.5`). The app's `SessionRecorder` has never been
validated by anything — it cannot run on Linux. Moving the conversion into the
core package is what closes the gap, and is rule 3 of `AGENTS.md` doing exactly
what it is for.

The hand-check of the earlier capture missed it too: `t` was verified
non-decreasing, never against the bound.

**Sessions captured before this are not recoverable.** Raw sessions are immutable
(rule 6), the times are wrong in every line, and no reader can guess the origin.
Re-capture; `--keep-going` will ingest an old one for poking at, but it will not
align.

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

## Landmarks and markers are visible now

The first capture exposed a real gap rather than a bug: a tapped landmark wrote
a line to a file and did nothing else. There was no way to tell a mark from a
missed tap, no way to see which corners were already done, and no reason to
trust the raycast had landed where it was aimed. They are now drawn in the AR
view, coloured by kind, with a billboarded label.

A detected marker is drawn too — a translucent square on the marker's own plane
at its real 20 cm size, with its `VH-NNN` label — so a sighting is visible where
it happens rather than only as a chip in the status strip. The square sitting
square on the printed marker is also the quickest check that detection is
working and that the printed size is right: if it floats or is the wrong size,
the print was scaled.

Landmarks persist for the life of the session, which is as far as ARKit's world
frame goes. **They do not carry into the next session**, and no amount of app work
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

- iOS: **built.** `PlanFile` in the core package (12 tests on Linux CI),
  `PlanStore` on disk, plus Plan import and Plan coverage. Import takes a PDF
  page or a photo, keeps the original beside the raster, and downsamples to a
  4096 px long edge. Coverage draws the level with each room where the owner put
  it, dragged to correct.
- Placing a room is a tap: pick a room from the tray of ones not on the plan
  yet, then tap where it is; drag any pin to correct it. The first version
  shipped **without** this — the only call to `place` was inside an existing
  pin's drag handler, so a freshly imported plan showed no pins and offered no
  way to add one. A screen whose one action was unreachable.
- Unbuilt on the app side: only one project and one level are reachable, since
  the Projects and Levels screens do not exist. Coverage counts *sessions* per
  room rather than distinct trades, which under-counts a room walked twice in
  one phase — honest, and cheaper than opening every manifest.
- Pipeline: **`vividhome validate --project` is built** (`vividhome/project.py`,
  16 tests), covering section 13's six rules. `ingest` still does not copy a
  `plans/` directory from a phone, so for now a plan reaches the store through
  `plan add` on the PC.

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
