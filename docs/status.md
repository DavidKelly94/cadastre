# Status

What is built, what is not, and what is blocked. Keyed to `docs/schedule.md`'s
day plan, but this file is the honest one: the schedule says what was planned,
this says what is true.

**Update this in the same commit as the work.** A status file that lags is worse
than none, because it is believed.

Last updated: 2026-10-03, after the Scale screen was walked on the new
house's plan and the field-first decision (ADR-0031) was written.

## The short version

**The whole chain works on real data, and the phone is on both ends of it.**
A room captured on an iPhone is sent to the PC from the app, validates, gets a
plan, calibrates, aligns and renders on an inspection page that shows the room
outline, the tapped landmarks and the walk path, opens any keyframe or still at
full resolution from the spot it was taken, and that page opens in the app
(2026-10-02, over the home Wi-Fi). That is the product's spine, and it is no
longer hypothetical.

The pipeline and the Swift core are complete and tested. The capture app runs on
device and its screens exist: setup, capture HUD, session review, past captures,
plan import, plan coverage.

Three things to hold against that:

- **Accuracy is measured once, and it is good.** Three walls of an 11 ft room
  within about 8 cm of each other, from a rushed handheld pass, against the 5 to
  15 cm ADR-0026 budgets. One capture is not a distribution.
- **No alignment has yet used an independent drawing.** Every plan so far was
  derived from the same capture it was then aligned against, which tests the
  plumbing and not the pairing.
- **One project and one level are reachable**, because the Projects and Levels
  screens do not exist. A house with two floors cannot be captured as one.

## Work queue

The order things are worth doing in, kept here rather than in a chat handoff so
it survives one. Owner-side items are things only the owner can do.

1. **Photos on the phone, and to the camera roll** — the owner's ask of
   2026-09-30. Design in `docs/design/return-path-design.md` §2. **Written,
   not walked**: the Photos screen, the label, the orientation from the pose
   and the camera-roll copy exist as of 2026-09-30 and have compiled in CI at
   best. The first thing to check on a device is whether a portrait capture
   shows upright, which is the one claim no Linux test can make.
2. **The rendering back in the app** — the other ask. ADR-0028. The PC side is
   built (`serve --lan`, the write refusal, `/index.json`, Bonjour; section 14
   of the format), the inspect page works by touch at phone width, and the app
   side is **written, not walked**: the PC entry on the project screen, Bonjour
   discovery, the Test fetch and the web view per level (2026-09-30). Neither
   Bonjour nor the fetch has been tried on a real network.
3. **Free-space readout and multi-select delete** in Past captures. **Written,
   not walked** (2026-09-30): the list header says what is free against the
   2 GB floor, and Edit selects several to delete at once with their total
   size on the button. **"Delete what is already on the PC" resolved
   2026-10-01**, on the PC's own word: the index from `serve --lan` lists every
   session it ingested and whether `validate` passed, so rows are marked *on
   the PC* and one button deletes exactly the validated ones. No "shared at"
   mark was needed. Walked by nobody yet.
4. **Run `corners` and `coverage` on the real captures** in the store. Both are
   right on the synthetic room and their tolerances are guesses until a real mesh
   disagrees with them. Owner-side; one command each.
5. **The app names a plan's original `source.pdf`**, against section 13's
   `<level>.source.pdf`; two PDF levels overwrite each other's original.
   **Fixed 2026-09-30** in `PlanStore`, with the naming in the core package and
   tested; an original already on the phone keeps its old name until the plan
   is imported again, and nothing reads it meanwhile.
6. **Corner candidates on the phone** (roadmap item 5, room side), once item 4
   says the offline number earns the screen time.
7. **Captures sent from the app, from anywhere** — the owner's ask of
   2026-10-02, ADR-0029. **PC side built 2026-10-02** (`/upload/`, the pairing
   code, the inbox, `done` → ingest), tested against a synthetic capture.
   **App side written the same day, not walked**: the pairing code under PC
   (Keychain), Test checks it, *Send to the PC* from Captures and from a
   capture, three files in flight, resume from the inbox listing, the
   cellular warning, https addresses for the tailnet. Owner-side next: send
   one capture on the home Wi-Fi first, then install Tailscale on both ends,
   `tailscale serve --bg 8765` on the PC, and send one from cellular.
8. **The first loop on the phone** — the owner's ask of 2026-10-02 after the
   first round trip: calibrate, align and look, without the PC. ADR-0030 and
   `docs/design/phone-first-loop-design.md`. **Calibrate on the phone written
   2026-10-02, not walked**: the Scale screen with the loupe, the maths in the
   core package pinned to the Python's numbers, `ingest` adopting the result.
   Next: see item 9, which reshapes the align step.
9. **The capture proves itself before you leave the room** — ADR-0031, the
   owner's field-first ask of 2026-10-03: outline rooms on the plan at home,
   guided corner taps with a live placement and residual, walls shading as
   they are photographed, a per-phase stills checklist, a leave check, and
   free capture and top-ups kept as they are. Design in
   `docs/design/field-proof-design.md`. **Outlines and guided taps built
   2026-10-03, not walked**: the Outline screen and corner naming; then the
   HUD asking for corners by name, the live fit with its residual, the
   placement file written at Stop, sent with the capture and adopted by the
   PC; the snap of a corner tap to where two mesh walls meet; the plan
   inset in the HUD with the walk on it; the walls shading as the
   keyframes photograph them; and the stills checklist with the leave check
   and *Capture more*. Next: the pairing screen for free captures, then the
   server watcher.

Owner-side, unchanged since 2026-09-18: walk build 42 through New room → New
level → storey 0 and confirm two levels show as separate sections; import the
new house's real plan in the app and see whether the room-name chips appear; fix
the private `base` Actions access from `docs/transfer-runbook.md` step 12.

## Pipeline (`pipeline/`) — complete

| Command | State | Notes |
|---|---|---|
| `validate` | done | All 8 rules, `--skip-images`, `--skip-depth` |
| `synth` | done | Writes a format_version 2 session |
| `markers` | done | Generates `VH-000`–`VH-059`, PDF and PNG |
| `apriltag` | done | 36h11 via `cv2.aruco`, subpixel refinement, IPPE_SQUARE |
| `plan` | done | `add`, `calibrate`; parses `12' 6"` |
| `align` | done | Umeyama 2D, rotation and translation only |
| `inspect` | done | Level page, groups multi-phase sessions by earliest trade; every drawn keyframe and still opens at full resolution, with its look direction |
| `ingest` | done | Zip-slip and path-traversal guarded; files under the manifest's project; copies `plans/` found beside the sessions, verbatim, for levels the store lacks; takes a whole project folder at once and reports each session; writes `derived/validate.json` so the index can say what passed |
| `serve` | done | Local server for the browser pages; `--lan` serves the store to the phone with `/index.json` and Bonjour (ADR-0028), and takes captures under `/upload/` with the pairing code into an inbox (ADR-0029). **Not yet tried from a phone** |
| `corners` | prototype | Room side of roadmap item 5, offline: wall planes from the mesh, adjacent intersections, scored against the tapped corners. Right on the synthetic room; not yet run on a real capture |
| `coverage` | prototype | Per-wall meshed and photographed coverage against the tapped corners, reported as gaps in metres from a corner. Right on the synthetic room; not yet run on a real capture |

19 modules, **363 tests passing**, ruff clean.

## Swift core (`ios/VividHomeCore/`) — complete

Every module Linux-tested, `SessionUpload` and `ServerIndex` included. `Transform`, `SessionID`,
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

## The stills checklist and the leave check, written blind, 2026-10-03

ADR-0031's fourth step. The capture protocol's §4 table is now data in the
core package (`StillsChecklist`): the HUD shows a chip per item for the
pass's trades, *each wall square-on* first, and a tap on a chip takes a still
for that item and ticks it once the file is on disk. The camera button still
takes an unlabelled still. `stills.jsonl` gains `item` (additive). At Stop the
app makes the leave check (`FieldCheck`): placed or not and how well, walls
photographed out of the outline's with the worst gap in metres from a named
corner, stills ticked out of the list with what is missing. The review screen
shows the three lines at the top, green or orange, and the manifest carries
them as `field_check` (additive); the PC's index passes it through. *Capture
more* under the lines starts a top-up of the same room and trades as its own
session. Pipeline: `Still.item`, `Session.field_check`, the index field, two
tests. Core: ten tests. **Decided without the owner:** chips instead of a pick
after the shutter; markers and the dated sheet left off the list; 70% is a
photographed wall; the `walls` block is omitted rather than guessed when the
capture is not placed; sentences are made from the numbers on both ends, not
stored. Not walked; the inspect page does not show the check yet.

## The walls shade as they are photographed, written blind, 2026-10-03

ADR-0031's third step. `WallCoverage` in the core package is the photographed
half of `vividhome coverage`, live: each wall of the outline in 10 cm cells, a
cell photographed when a keyframe was within 4 m, had it inside the footprint
its image corners make on the floor, and had no other wall between. The
recorder hands every kept keyframe over; one is tested against the walls as it
arrives, and the whole set is redone when the placement moves. The inset's
walls go grey, amber and green at 30% and 70%, with a *walls 3/4* caption.
Six core tests, including an L-shaped room where the notch hides the far
wall. **Decided without the owner:** the 4 m range (the offline default) over
the 2 m the design first said; the 30% and 70% bands; no band drawn in the
camera picture yet. Not pinned to the Python on a real capture, not walked.

## The walk on the plan, in the room, written blind, 2026-10-03

ADR-0031's second step and the first level view. While a guided room is
captured the HUD shows a small plan inset under the marker strip: the room's
outline from the start, its corners ticked or lit as the chips are, and once
two corners are tapped the keyframe path, the tapped corners and the camera's
own dot, all moved into the house frame by the live fit. Fold it away with
the chevron when it is in the way of the picture. The walk comes from a hook
the recorder calls per kept keyframe; the fitting maths is `InsetFit` in the
core package, tested on Linux. Nothing is written by this; it is the owner's
view of what the fit says while they can still do something about it.

## Corner taps snap to the mesh, written blind, 2026-10-03

The third piece of ADR-0031's first step. A corner tap lands on ARKit's mesh,
which rounds corners, so a point could be a few centimetres off. Now the
faces within half a metre of the tap are gathered (`MeshProbe`, the ARKit
layer) and the core package clusters the wall faces into vertical planes,
intersects pairs that actually run to each other, and moves the point to the
nearest corner within reach, down onto the floor faces (`CornerSnap`, the
rule `corners.py` runs offline). The HUD says *snapped to the corner, 4 cm*;
a selected snapped mark offers *Unsnap*; moving a mark by hand also clears
it. `landmarks.jsonl` records `mesh_corner_snap` or the raycast. Eight core
tests on synthetic walls, clutter the mesh calls wall, and ghost crossings.

**Decided without the owner:** the snap moves a point at most 0.5 m; a
cluster under 0.05 m² of wall is furniture; it runs on every corner tap, not
only guided ones. **Not yet** pinned to the Python on one real mesh, which is
the contract-job item still open, and not walked.

## The capture places itself, written blind, 2026-10-03

The second piece of ADR-0031, and the one that moves ADR-0030's align step
into the room. When the level is calibrated and the room outlined, the HUD
replaces the landmark kind picker with the room's corners by name, lights the
next one, and a tap on the floor records that corner. After two, the phone
solves the same rigid fit `align.py` solves (`Umeyama2D` and `PlanAlignment`
in the core package, pinned to the Python's numbers to 1e-9) and the FIT
readout turns into centimetres: *Placed on the plan, 6 cm*, *Check the
corners: 18 cm off*, or *Not placed*. Every later tap, move, rename or delete
re-solves. Skip parks a corner that cannot be reached; tapping a chip out of
order says where the owner actually stands; an ellipsis brings the picker
back for a door or a window.

At Stop the placement is written as `alignments/<session-id>.json` beside
the plans, the PC's own file shape plus `source: app` and `method: guided`
(section 15), and only for a fit under the PC's 30 cm refusal. The review
screen leads with it. Sending a capture now carries that one file; the server
takes `alignments/<file>`; `ingest` adopts it when the store has no alignment
for the session and its calibration matches the plan the phone solved
against, and says why when it does not; the index reports who placed each
session. Twelve new pipeline tests and seven core tests.

**Decisions made without the owner, to revisit:** the three thresholds; the
chips replacing the picker rather than sitting beside it; writing nothing
above 30 cm rather than a file the PC would refuse; the floor height from
landmarks only, since the mesh is not read live yet.

**Not walked.** None of it has run on a phone. The first thing to check is
that a tap in a guided room gets the corner's name, and that two taps
produce a plausible residual on the real house.

## Rooms outlined on the plan, written blind, 2026-10-03

The first piece of ADR-0031. The plan screen's tray gains a row of the placed
rooms; each opens an Outline screen on the same canvas the Scale screen uses
(now `PlanPointCanvas`, shared): tap the inside corners in order around the
room, drag under the loupe, Save. Corners are named from where they sit, not
typed: NW, NE, SE, SW by bearing from the outline's centre, with a suffix for
a second corner in a quadrant, so an L-shaped room reads NW, NE, NE2, SE, SE2,
SW. The names are what the guided taps will ask for and what
`landmarks.jsonl` already records, so no new vocabulary enters the format.
`outline` and `outlined_at` are additive fields on a room pin (§13, rule 7);
moving the pin keeps the outline. `PlanFile.houseCorners(of:)` turns an
outline into house metres through the calibration, which is the input the
live solve needs next. On the PC, `validate --project` checks an outline and
`plan calibrate` keeps it, both tested.

## Calibrate on the phone, written blind, 2026-10-02

The first step of ADR-0030. The plan screen gains *Scale* (top left): tap one
end of a printed dimension, drag the ring under a loupe until the crosshair is
on the tick, the other end, the origin, type the printed length, Save. The
line under the fields shows the scale and the drawing's width in metres before
anything is written, which is the sanity check the runbook asked the owner to
do in their head. The result goes into `plans/<level>.json`, the same four
fields `plan calibrate` writes, and travels to the PC with the next capture;
`ingest` adopts it when the store's copy has no scale and no alignments, and
otherwise leaves the store's alone, with tests for all three cases.

The maths is in the core package (`PlanFile.calibrated`, `houseToPlan`,
`planToHouse`, `PlanDistance`) and its tests are pinned to numbers the Python
produced for the same inputs, to 1e-9, which is the first half of the design's
"keep the two honest" rule; the contract-job round trip comes with align.

**Found on the way:** `parse_distance` read `11'-6"`, the way every architect
prints feet and inches, as eleven feet *minus* six inches, silently, and could
not read `6 1/2"` at all. Fixed on both sides with the same cases. The owner
typed a dimension on the PC's page today; it is worth checking which form.

**Walked 2026-10-03, build 56:** the three points, the loupe and the fit all
worked on the new house's plan; a 16 ft dimension gave 22.8 mm per pixel and a
50 m sheet. The owner then asked what there is to see afterwards, and the
answer is nothing until align and the level view land, which is the next
step. The readout line was cut off at "A house is t…"; it wraps now.

**Not yet checked.** The zoomed tap positions and the pinch are the
parts no test covers: at zoom, a tap must still land on the pixel under the
finger, which depends on SwiftUI reporting gesture locations in the view's
own space under `scaleEffect`. That is the first thing to check on a device.

## The PC takes captures from the app, 2026-10-02

The owner captures on site and is not on the home network; the captures have
to reach the PC, be processed, and come back to the phone, without the Files
app and without being home. ADR-0029 decides it: phone and PC on the owner's
own tailnet, with `tailscale serve` giving the PC an HTTPS name the app can
use without an App Transport Security exception, and the app sending captures
to `vividhome serve --lan` behind a pairing code. The question of whether that
is safe in a public repository was asked and answered the same day: the code
holds nothing secret, the pairing code is generated on the PC and never
committed, and the design assumes the handler's code is read.

**Built, PC side.** `/upload/` (section 14.1 of the format): one `PUT` per
file into `<store>/.inbox/<session-id>/`, a `GET` that lists what is there so a
dropped send resumes, and `POST done` that hands the entry to `ingest`, which
moves the session into the store, validates it, imports any `plans/` beside
it and removes the inbox entry. Paths are checked as text and as paths, two
plain segments at most, `derived/` refused, a file capped at 256 MB, a short
body left under a temporary name and discarded, a session already in the
store refused. The pairing code is 16 hex characters from `secrets`, printed
by `serve --lan`, compared in constant time. The handler now speaks HTTP/1.1
with keep-alive because a capture is thousands of small requests. Twelve tests
cover it, including a full synthetic capture sent file by file and ingested.

**First run on the owner's PC, 2026-10-02.** `serve --lan` started and printed
its pairing code; it also printed five `169.254.x.x` addresses from virtual
adapters around the one that works, and said nothing while a capture arrived.
Link-local addresses are left out now, and a landed capture prints one line
with its verdict and destination. On the phone, Test answered "This phone is
not on a network" with Wi-Fi lit: iOS reports a Local Network permission
that is off as offline, and Bonjour finds nothing for the same reason. The
message now names the setting, and the setup guide's table has the row.

**The first real send worked**: Test green with the pairing code accepted, one
capture sent at 53 MB with its plan, "On the PC and validated; plan for
level-1 imported", and the *on the PC* chip afterwards. Then `plan calibrate
--web` took no clicks at all: the SVG that draws the marks sat over the plan
image and swallowed them, and the align page had the same overlay drawn below
the image instead of on it. Both pages were only ever exercised through their
CLI flags before. Fixed with `pointer-events: none` on the overlays and
checked in headless Chromium: a click puts a mark at the clicked pixel on
both pages, and the old page puts none. Two things seen and left for later:
the Bonjour entry stuck at *resolving* (likely the link-local addresses the
advert carried until this change), and the send sheet saying 49 MB then
sending 53 MB because the plan files count only in the second figure. The
sheet now counts the files the way the send does, so the two agree.

**Then the rest of the chain, by hand on the PC.** Calibrate, align (with
`--force`: the capture is of the owner's current bedroom and the plan is the
new house, so a 49 cm fit is the honest answer), inspect, and *Rendering on
the PC* on the phone showed the plan with the walk, the corners and the photo
marks, and a tap opened a keyframe. Three things seen there and fixed:

- The house screen's plan card had every room pin pushed off its bottom-right
  corner: the pins are stored in the raster's pixels (§13) and the card
  scaled them by the shrunk copy it draws. It scales by the raster now.
- A portrait keyframe opened on its side in the lightbox. The app's Photos
  screen already turns images upright from the pose; the page now carries
  the same `turn` per photo, computed by the same rule in `inspector.py`
  and tested against it, and lays the picture out at its displayed size so a
  quarter turn fits the phone's width. Checked in headless Chromium at phone
  width.
- The rendering's "From the PC, <time>" line was squeezed into a pill that
  read "Fro...". It is a footer now.

**And the owner fumbled**, which is the finding that matters most: `&&` in
PowerShell, a placeholder typed as a path, a placeholder typed as a session
id, the click pages on the port `serve --lan` holds. `docs/runbook.md` is the
result, written from that walk: two windows, a `$store` variable, every
command as typed, what each prints, what to click and why, and a table of
what went wrong. The click pages now step around a busy port by themselves.
README points at the runbook first.

**Fixed on the way.** `ingest` never wrote `derived/validate.json`; only
`validate --json` did. So after the documented flow (`ingest`, then `align`
and `inspect`) the index reported every session as `validated: null` and the
phone said *on the PC, unchecked* about captures the PC had in fact checked.
Ingest writes the report now, where the check ran.

**Written, app side, the same day.** `SessionUpload` in the core package lists
a capture's files the way the server accepts them (never `derived/`, never a
dotted name, the project's `plans/` beside it), works out what is left to send
from the PC's listing, and decodes the two answers; tested on Linux against the
documented examples. In the app, `PCLink` keeps the pairing code in the
Keychain and Test asks the PC whether it takes it, by listing an inbox entry
that cannot exist. `SessionUploader` sends three files at a time with two
retries on a network error, stops the whole send on a refused code, and hands
`done`'s one-line verdict to the row. Captures gains *Send N captures to the
PC* for the ones the PC does not list, each capture gains *Send this capture*,
and the sheet says the size and asks before sending on cellular. `PCAddress`
treats `https://` with no port as 443, so a tailnet name types as a browser
would. None of it has run: no send has reached a PC from a phone, and nothing
has been tried through Tailscale.

**Not yet.** `serve` without `--lan` still has the unauthenticated `/save` for
the calibrate and align pages, so the setup doc says to run `--lan` behind
`tailscale serve`, never plain `serve`. Backgrounding the app pauses a send;
the resume covers it, a background session does not exist yet.

## One command per visit, not per room, 2026-10-01

`ingest` refused a folder or zip holding more than one session with "ingest
them one at a time", which was the wrong shape for how the work goes: several
rooms in one visit, then everything to the PC afterwards, as this file already
said about the captures list. It now takes a session folder, a project folder
holding several, or a zip of either, ingests every session it finds, and
reports each — a session that fails validation or is already in the store is
named beside the ones that landed rather than stopping them. The plan beside
the sessions comes across once per folder. Pointing it at the project folder
copied off the phone is now the whole PC-side step for a visit.

## The lossless copy refused for a reason it named, 2026-10-01

Build 50's alert said it: *kCGImageDestinationMetadata cannot be used with
kCGImageDestinationOrientation*. ImageIO will not take the label and the
orientation in one lossless pass, and the fallback did its job — the photo
reached the camera roll re-encoded. The lossless path now runs in two passes,
orientation and date first and the label merged second, each a combination
ImageIO allows, so the next save should say "Saved to Photos." and nothing
else. If it names a refusal again, the text will say which pass.

## Deleting a capture is a thing you can find, 2026-10-01

The owner's other reaction to build 47 was that managing captures did not feel
intuitive, and Edit → select → a toolbar button at the bottom of a sheet is
easy to miss. Three changes. Every row now leads with its date, so the same
room walked three times reads as three passes rather than three copies. The
edit-mode action is a strip above the home indicator that cannot be missed,
with the count and size of what is selected, Select all, and one red button.
And a capture's own screen can delete it, with a footer that says what the PC
knows about it — validated, held but unchecked, absent, or unknown — because
that is the moment the question "is it safe to delete this?" is actually asked.
Swipe-to-delete stays. Written blind.

## The house screen leads with the plan, 2026-10-01

The owner's reaction to the house screen was that landing on a room list, with
the plan nowhere in sight, felt wrong, and that the plan and the rooms should
sit together. They should: the plan is what a house looks like and the rooms
are what is on it. Each level's section now opens with its plan as a card —
the drawing, the rooms pinned where the owner put them, shaded by how many
passes have been walked, hollow where nothing has — and tapping it opens the
full plan screen to place and correct rooms. A level with no plan gets an
*Import a plan* row instead. The room list sits under the card as before.
Written blind; the card decodes the raster off the main thread and shrinks it,
since the stored plan is up to 4096 px on a side.

## Build 47 walked, 2026-10-01

The owner walked build 47 on the phone, with no PC available, and sent
screenshots. What held and what did not:

- **The Photos screen works.** 73 keyframes of a bedroom, every 5th shown,
  upright in the grid, the landmark badge on the frame where a tap was made.
  The orientation claim no Linux test could make holds on at least this phone.
- **Save to Photos failed**: *"000015.jpg could not be read as a JPEG."* The
  thumbnail of that same file decoded, so the file was fine and the message
  blamed the wrong thing: the lossless copy-with-metadata refused. Fixed by
  falling back — re-encode with the label, then the plain bytes — and by
  reporting the real reason and which path each photo took, so the next build
  says what the phone objected to. The lossless path is still tried first.
- **`plans` appeared in Captures as an "unfinished" capture with no manifest.**
  The project folder has held `plans/` beside the sessions since ADR-0025, and
  the session lister never learned to skip it. Only folders named as a session
  id are sessions now, with a Linux test.
- **The free-space line read badly** ("capture stops starting below"). Reworded.

Two pieces of feedback that are design, not bugs, and get their own PRs: the
house screen lands on a room list with the plan nowhere in sight, when the plan
and the rooms should sit together; and managing captures (Edit, select, delete)
did not feel intuitive. Noted too: "bedroom" and "Bedroom" were typed as two
names that share one slug, so the house screen shows one lowercase row — the
data, not a display bug.

## The PC's word on what is safe to delete, 2026-10-01

The handoff of 2026-09-18 said the one bulk action that is actually safe —
"delete everything already ingested" — needed a marker written back after
`ingest`, a contract question nobody wanted to open. It did not: the return
path's index (section 14) already lists every session the PC holds and whether
`validate` passed, and the phone can read it. So Past captures now asks the PC
and marks each row *on the PC* when the PC says validated, *on the PC,
unchecked* when it holds the bytes and has not said they are good, and nothing
when it has never seen them. One button deletes exactly the validated ones from
the phone, naming the store and the time it answered; nothing is deleted on the
PC. The "shared at" mark recommended twice in this file was never built, and
that is the better outcome: a share sheet closing says nothing about what
arrived.

Two hitches flagged at merge time are fixed in the same change: the Photos
screen reads its JSONL off the main thread, and the project screen fetches the
index only when the last answer is older than a minute instead of on every
appearance, which with the PC off was a six-second timeout each time.

Written blind like the rest of the app side; the logic that decides what is
safe is in the core package with a test, including the case where the PC
holds a capture that failed validation, which must not count.

## Past captures says what is free, and deletes several at once, 2026-09-30

Queue item 3, written blind like the rest of today's iOS work. The list's
header now reads *"12.3 GB free on this iPhone; capture stops starting below
2.0 GB"* from `volumeAvailableCapacityForImportantUsage`, which is the number
that decides whether a capture can start rather than the raw volume figure,
and the floor is `HealthPolicy`'s constant rather than a second literal. Edit
turns the rows selectable; the bottom button says *Delete 3 (1.2 GB)* and asks
once before doing it. Swipe-to-delete stays. The "delete what is already on
the PC" version is still a decision, not code: nothing on the phone knows what
the PC has, and the honest signal would be an app-side "shared at" mark.

While in the same file: the app named every plan's retained original
`source.pdf` where section 13 says `<level>.source.pdf`, so two PDF levels
overwrote each other's original on the phone. The store names it for the
level now, with the naming in the core package and a test. An original
already on the phone keeps its old name until that plan is imported again;
nothing reads the file yet, so nothing is wrong meanwhile.

## The rendering back in the app, written blind, 2026-09-30

The second of ADR-0028's asks, app side. A **PC** button on the project screen
opens a sheet that lists PCs found over Bonjour (`_vividhome._tcp`), takes a
typed address, and has a *Test* that fetches `/index.json` and says what the
store holds and how old that answer is, or why nothing answered — the PC off,
the phone on cellular and a router isolating guests all look alike from the
phone, so the text tries to tell them apart. Once the index is in, each level
the PC has rendered gets a *Rendering on the PC* row that opens the served
inspect page in a web view, with the page's generation time underneath. The
address is remembered; the index is fetched again whenever the project screen
appears.

Tested on Linux: the section 14 reader against the document's own example,
including a `null` that must read as "no report" and a field the phone does
not know; and the typed-address parser. Compiled at best: the Bonjour browse
and the resolve-by-connecting trick that turns a service name into a host and
port, the fetch, and the web view. Three Info.plist entries are load-bearing
and untestable here: local-network usage, the Bonjour service type, and
`NSAllowsLocalNetworking`, without which App Transport Security refuses plain
HTTP to the PC and the symptom is an unhelpful error rather than a page.

## Photos on the phone, written blind, 2026-09-30

The first of ADR-0028's asks. A **Photos** screen, reached from a capture in
Past captures and from Session review, shows the keyframes and stills a session
holds — every 5th keyframe by default, every still always — turned the way the
phone was held, with a label that says only what the session knows: project,
level, room, trades, keyframe and time, and the landmarks tapped at that frame.
Tap one for full screen with swipe, select several, and *Save to Photos* copies
them to the camera roll with the label in the metadata, the capture's own time
as the creation date, and the EXIF orientation set so Photos shows them
upright. The JPEG bytes are copied, not re-encoded; the session is never
changed.

What can be trusted and what cannot, kept apart on purpose:

- **Tested on Linux:** the reader (time order, a still after its keyframe, a
  truncated last line skipped, landmarks attached by keyframe index), the label
  text, the taken-at arithmetic, and the orientation from the pose for six
  poses. That is `SessionPhotos`, `PhotoLabel` and `DisplayOrientation` in the
  core package.
- **Compiled at best, never run:** the screen, the thumbnail loading, the
  metadata merge and the photo-library write. The one claim that matters most
  — a portrait capture shows upright — rests on ARKit's stored image having
  its right along camera `+x` and its up along camera `+y`, which section 3
  says and no test here can check. If a device shows portrait captures lying
  on their side, the fix is one sign in `DisplayOrientation.from`.
- **Not built:** the optional burned-in caption, and an album (add-only access
  forbids reading the library, so there is none; the design says why).

The `ios-testflight` workflow now also builds from the handoff branch, so the
next push that touches `ios/` produces a build to walk.

## The PC side of the return path, 2026-09-30

ADR-0028 wants the rendering back on the phone, and the half that can be built
and tested here is the PC's. `vividhome serve --lan` now serves the store on the
home network: every interface, the addresses printed, `GET /index.json` saying
what the store holds (section 14 of the format, generated from the files on
each request so it cannot lie about them), `GET /_vividhome/ping`, and a
Bonjour advertisement as `_vividhome._tcp` so the app will find the PC without
an address being typed.

The rule that shaped it: **on the network, the server refuses every POST.** The
localhost server accepts `POST /save` so the calibrate and align pages can write
their JSON; the same endpoint reachable from the LAN would let any device in the
house put a file on the owner's PC. The refusal is tested, and `--lan` is never
the default.

What the phone can do with it today, before the app reads any of it: open the
served inspect page in Safari by address. The page now works by touch: at phone
width the session list stacks above the plan, which scrolls and pinches; each
dot has a finger-sized invisible target; a tap opens the photo, a swipe steps,
a tap outside closes; and the page opens scrolled to the walk rather than to a
blank corner of the sheet. Driven in Chromium's iPhone emulation with real
touch events, no console errors. Not yet opened on an actual phone.

Not tested: Bonjour on a real network. `zeroconf` registers in a sandbox here
without complaint, which says nothing about the Windows firewall prompt or a
router that isolates clients; the app's Test button is designed to say which.

## Coverage per wall, against the corners that were tapped, 2026-09-18

The coverage question had an analysis and no code, and the analysis was the
hard part: a percentage needs a denominator, the mesh cannot be one because it
only contains what the LiDAR saw, and the plan is not in the session. The tapped
corners are the one thing a capture carries that says what the room *is*. So
`vividhome coverage <session>` takes them in tap order — the protocol's walk
order — and walks each wall between consecutive taps in 10 cm cells, asking of
each whether a wall face meshed it and whether a keyframe photographed it:
bearing within the frame's horizontal spread, within 4 m, nothing in the way.

It prints gaps before percentages. *"corner-se -> corner-sw 4.00 m, meshed
100%, photographed 0%, not photographed 0.0..4.0 m from corner-se"* is the line
the owner reads standing in the room; "62%" is the number they cannot act on.
On the synthetic room a full circle covers every wall, a quarter turn leaves the
south wall unphotographed and the report says so, and a mesh with a wall left
out reports that wall as not meshed. **Untested on a real capture**, where the
open questions are whether 4 m and the 25 cm mesh band are right, and how often
a frame pointed at the ceiling — which the check does not catch beyond a pitch
cut-off — inflates "photographed".

What it deliberately does not do: count a wall nobody tapped, or read the room's
shape from anything but the taps. A room tapped as four corners is measured as
four walls whatever it really is. That is the honest denominator's cost, and it
is the same reason the corner proposal above exists: fewer taps skipped means a
truer footprint.

## Corners proposed from the mesh, measured before the app pays for them, 2026-09-18

Roadmap item 5's room side — fit planes to the wall-classified mesh, intersect
adjacent pairs, offer the intersections as corners to drag rather than tap — is
the owner's stated big win, and it is app work that cannot be checked here. The
roadmap's own advice is to measure before spending, so the measurement was built
first: `vividhome corners <session>` runs that geometry on the PC over a
capture's mesh and scores the result against the corners the owner tapped, as
the fraction within 20 cm plus the candidates no tap is near.

On the synthetic room it finds the four walls, ignores the 0.4 x 0.3 m "wall"
planted in the middle of it, and puts all four corners within 2 cm of the taps.
An L-shaped room in the tests gets its six corners and none of the ghosts two
crossing lines would otherwise invent, which is the part that needed a rule: two
walls propose a corner only where both actually reach it. **None of this has
touched a real mesh.** ARKit's walls are noisier, tilted and full of holes, and
the tolerances (10 degrees, 15 cm, half a square metre) are guesses until a real
session says otherwise. The store already holds captures with meshes and taps;
the number is one command away.

Two rules held on purpose. Every candidate is written with `source`, a
heuristic `confidence` and `confirmed: null`, under `derived/`, and nothing
writes to `landmarks.jsonl` — rule 9, and the roadmap's guardrail. And the
phone got nothing: no candidate is drawn until the offline number says the
approach earns its screen time.

Two side effects worth knowing. `synth` now writes the room's mesh, so `align`
reads the synthetic floor from floor faces rather than guessing it from the
lowest landmark; its tests say so. And `align.py` still carries its own small
OBJ reader from before `mesh.py` existed; it works and was left alone.

## The plan comes across with the capture, 2026-09-18

ADR-0025's promise was that the plan travels to the PC with the capture. Section
13 said, correctly until now, that it did not: the copy step was never written,
so the owner imported the same drawing twice — once in the app, to place rooms
on it, and once with `plan add` on the PC — as two copies that knew nothing of
each other.

`ingest` now copies `plans/` when it finds one beside the session it is
ingesting, which is the app's own layout. It copies the raster, the JSON and the
retained original verbatim, and only for a level the store has no plan for yet,
because the store's copy may be calibrated with alignments solved against it and
a swapped raster would move every session drawn on it. It prints what it did per
level, and `--force` stays a session flag. Calibration is still the PC's job,
so the next line it prints is the `plan calibrate` command to run.

Two things that were quietly wrong, found by making this true:

- **`plan calibrate` would have erased the app's room placements.** The pipeline
  modelled six fields and wrote back only those, so the first calibration of a
  plan the app had written would have dropped `rooms` and `source` on its way
  past — section 12's "readers ignore unknown fields" honoured by a writer that
  threw them away. `PlanCalibration` now carries every field it does not model
  and writes it back unchanged, with the six modelled fields kept first. A test
  round-trips the app's fields through `calibrate` and a raster replacement.
- **The app names the kept original `source.pdf`; section 13 says
  `<level>.source.pdf`.** `PlanImportView` builds the `source` record before the
  level slug exists. Two levels imported from PDFs would overwrite each other's
  original on the phone, and `ingest` copies the file under the name the JSON
  gives, so the store inherits the collision. An app-side fix on the iOS branch;
  the pipeline reads nothing from the original, so nothing downstream is wrong
  yet.

Not exercised on a real project folder: the SMB and USB routes copy whatever the
owner selects, and the `ShareLink` route shares one session, which carries no
`plans/`. The owner has to share or copy the project folder for the plan to be
found; `ingest` says nothing when there is nothing beside the session.

## The inspect page opens the photos, 2026-09-18

The owner's question after the first real capture was whether the images were
any good, and the honest answer was that nothing showed them. `inspect` drew a
320 px thumbnail on hover over every fifth keyframe and stopped: the page held
no `<a>` and no `href`. The full-resolution keyframes and the stills — the
product's actual record — were reachable only by opening `rgb/` and `stills/`
and guessing which index was taken where.

Now every drawn keyframe and every still links to the JPEG in the session
folder. Click a dot and the file opens in a lightbox with a plain link to it;
the arrow keys step through the capture in time order; a tick on each dot shows
which way the camera looked, so a photo can be found from the wall it shows
rather than from its index. The heading is the camera's `-z` carried through
`T_hs`, horizontal part only — a camera pointed at the floor gets no tick rather
than a spurious one. Stills are drawn as diamonds, all of them, because they are
the deliberate photographs and there are a handful per room. `--no-thumbnails`
now skips only the hover preview; the links stay, since speed is not a reason to
hide the record.

Checked in a real browser and not only by tests: the generated page was driven
in headless Chromium — hover, click, step, Escape, backdrop — with no console
errors, on a synthetic session. It has not yet been opened on a real capture,
and the thumbnail-on-hover over a 1920x1440 source has not been timed on a
real 800-keyframe room.

This is not the viewer. `web/` is not started and `docs/design/viewer-design.md`
still describes the real answer — click-to-nearest-photo with the clicked point
re-projected into each image. `inspect` remains a diagnostic page; what changed
is that a capture can be reviewed from it.

## The house screen shipped with no way to add a room, 2026-09-18

Build 41 put the project screen above capture, so the house is the root and a
room is chosen from a list. The owner opened it to test the thing it was built
for — a second level — and could not: the only route into a capture was tapping
a room that already had one, and nothing on the screen created a room or a
level.

**The screen whose entire purpose was to make a two-storey house recordable made
it impossible.** Before it, the level was a text field and any level could be
typed; after it, only levels that already existed could be reached. The app got
strictly less capable.

This is the second time, and the same shape both times. The plan screen shipped
with `place` reachable only from the drag handler of a pin that did not exist,
so a freshly imported plan offered no way to add one. Neither was caught by
brace balance, member existence, argument labels or the compiler, because none
of those ask whether a user can reach the feature. The check that would have
caught both is *walk the path a new user walks, on an empty app.*

A second bug surfaced while fixing it, one commit old and entirely mine.
`LevelRef.index` is hardcoded to `1` where a capture starts, so every manifest
ever written claims storey 1 — and the storey ordering added to `ProjectDigest`
the day before sorts on a field the app never varies. Written and tested against
fixtures that set it, used by an app that does not.

Both fixed: a New room sheet that names a room and, when needed, creates a level
with an explicit storey; and the whole `LevelRef` carried from the house screen
to the recorder instead of just its name. The storey is asked for rather than
guessed, because it cannot be derived — "Basement", "Ground" and "Lower" all
mean below and no string says so.

The level and room are now chosen in one place. They were editable on both the
house screen and the setup form, which is two screens setting the same two
strings — the shape of most of what has broken here.

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

The fourth wall is 21% longer than its opposite, and `corner 4` sits inside the
room's outline rather than on it. That was first read as a mis-tap. The owner
then said the room has a jut-out near the door and that a wall he tapped may have
been an outside one — which explains the same numbers without anyone tapping
wrong, and `corner 4` near the door is exactly where a jog's inside corner would
sit. Four corner points cannot distinguish a mis-tap from a real jog, so the
reading stands corrected: the discrepancy is unexplained by the data alone.

**Two things worth keeping.**

A bounding box is not a room. Any measure taken along the session axes is
meaningless, because those axes have no relationship to the building. Anything
that reports a dimension has to derive its own frame first.

And the opposite-wall check is weaker than it first looked, which is worth
recording because the first version of this entry oversold it. Opposite walls of
a rectangle are equal whatever the aspect or rotation, so four corners do carry
an internal consistency check needing no plan, no markers and no ground truth —
but it only ever says *these four points are not a rectangle*, and a jog is not
an error. Real rooms have bays, chimney breasts and closet bumps. ADR-0027's
claim survives: nothing in the capture can tell whether the owner tapped what
they meant to.

What it could still be good for is a prompt rather than a verdict — "these taps
do not close a rectangle; is that right?" — asked while the owner is standing in
the room and can answer. Not built, and it says nothing about rooms with more or
fewer than four corners.

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
