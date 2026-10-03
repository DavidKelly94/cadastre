# Proving the capture in the field: outlines, guided taps, live coverage, the leave check

Design for [ADR-0031](../adr/0031-the-capture-proves-itself-before-you-leave.md), 2026-10-03. It replaces §3 of `phone-first-loop-design.md` (align on the phone) with a version that happens during capture, and takes over the live half of `ai-roadmap.md` item 3. Nothing here is built yet. The mechanics are the implementer's; the decision is in the ADR.

## 1. Goals and non-goals

Goals: when the owner walks out of a room, the app has already said whether the capture is placed on the plan and what was missed; nothing in that depends on the PC; a free capture with no guidance remains one tap away; every file written is one the pipeline already reads, or an additive field.

Non-goals: markers (optional, ADR-0026); identifying elements in stills (roadmap item 1); anything that needs the GPU.

## 2. Room outlines on the plan

**Built 2026-10-03, walked by nobody.** `PlanOutlineView` from the plan screen's room chips, on the same `PlanPointCanvas` the Scale screen uses; `RoomOutline` in the core names the corners and `PlanFile.houseCorners(of:)` projects them for the solve; `validate --project` checks an outline (rule 7); `plan calibrate` on the PC keeps it.

**Where.** The plan screen, where rooms are placed as pins today. A placed room gains *Outline*: tap its corners on the drawing in order, with the loupe from the Scale screen, and close the shape. Three corners minimum; the usual room is four to eight.

**What it writes.** `rooms[].outline` in `plans/<level>.json`, a list of `[u, v]` plan pixels in order, plus `outlined_at`. Additive to §13; a reader that does not know `outline` ignores it. The pin stays what it is: the room's label position. The outline is the plan's statement of where the corners are, and the house-frame position of each corner follows from the calibration through `plan_to_house`.

**Naming.** Corners are named from the outline's geometry, not typed: the compass label the capture protocol already uses (`corner-nw`, `corner-ne`, ...) assigned by each corner's bearing from the room's centre, with a numeric suffix when a room has two corners in one quadrant. The same name is what the HUD asks for and what `landmarks.jsonl` records, so a landmark label in a session is a key into the outline.

**Done at home.** Outlining is preparation, like calibrating. The house screen says which rooms have an outline and which do not, and a room without one captures in free mode (§6).

## 3. Guided taps and live placement

**Built 2026-10-03, walked by nobody.** What landed, and the calls made without the owner:

- The corner chips replace the kind picker while a room is guided; an ellipsis button brings the picker back for a door or a window and *Back to the corners* returns. A chip can be tapped out of order (the owner stands where they stand) and *Skip* parks the one asked for.
- The solve runs after every landmark change; the FIT readout shows the residual in centimetres and the line under the strip says *Placed on the plan, 6 cm*, *Check the corners: 18 cm off* or *Not placed*. Thresholds: under 10 cm placed, under the PC's 30 cm refusal check, above that not placed.
- The file is written at Stop only for a fit under the 30 cm refusal; the review screen says what happened either way. The floor height comes from floor-tagged landmarks, else the lowest landmark; the mesh route the PC has is not on the phone yet.
- The snap is built: `CornerSnap` in the core package clusters the wall faces within half a metre of the tap into vertical planes, as `find_walls` does, intersects pairs that actually reach each other, and takes the nearest corner within reach; the floor is the floor faces' median height, else the walls' bottoms. `MeshProbe` in the ARKit layer gathers the faces. The HUD says how far the point moved, and *Unsnap* on a selected mark puts it back; `method` records `mesh_corner_snap` or the raycast. Tested on synthetic walls, clutter and ghost crossings, and held against `corners.py` on the fixture room by the `contract` CI job (`tests/test_contract.py`); not yet compared on a real mesh.
- `ingest` adopts the file when the store has no alignment for the session and its calibration matches the plan beside the capture; the index says `alignment_source: app`.

**The ask.** When a capture starts in a room with an outline, the landmark strip shows the room's corners as chips in outline order with the next one highlighted: *Tap the NW corner*. The owner stands at that corner and taps the floor where the walls meet, as now. A chip can be skipped (a corner hidden behind a stack of drywall) and comes back later.

**The snap.** A tap raycasts to the mesh as today. Then, within 0.5 m of the hit, the app fits planes to the wall-classified mesh faces and, where two walls meet the floor, moves the point to that intersection (the rule `corners.py` runs offline, ported to the core package and tested against it). The snap is shown: the mark slides, and a long press puts it back. `landmarks.jsonl` records `method: "snap"` or `"tap"`, which is the field the record already has.

**The solve.** After two corners, the phone solves the rigid 2D fit between the tapped positions (session metres) and the outline's corners (house metres via the calibration), the same closed form as `align.py`, in the core package. The HUD shows the residual in centimetres and a verdict: *placed* under 10 cm, *check* to 30 cm, *not placed* above. A third corner is asked for whenever the verdict is not *placed* or ADR-0027's geometry says the two are too close together. Every new tap re-solves.

**What it writes.** On Stop, `sessions/<project>/alignments/<session-id>.json`, ADR-0030's file, with `"source": "app"` and `"method": "guided"`. `ingest` adopts it as that design says. The capture is placed before the PC ever sees it; the PC's `align` becomes the way to redo one.

**Live view.** Once placed, a small plan inset in the HUD shows the room's outline with the walk drawn on it so far. That is the first version of the level view, and the one the owner looks at while standing in the room. *Built 2026-10-03:* `PlanInsetView`, 132 pt square under the marker strip, foldable; the outline from the start, the corners ticked or lit as the chips are, and once placed the keyframe path, the tapped corners and the camera, moved into the house frame by the live fit. The walk comes from a per-keyframe hook on the recorder; the camera dot refreshes once a second with the rest of the strip. The fitting maths (`InsetFit`) is in the core package and tested.

## 4. Live coverage

**Built 2026-10-03, walked by nobody.** `WallCoverage` in the core package is `coverage.py`'s rule for the photographed half: 10 cm cells along each wall of the outline, a cell photographed when a keyframe was within 4 m (the offline default, not the 2 m this section first said), had it inside the footprint its image corners make on the floor, and had no other wall of the room between. The recorder hands every kept keyframe to the coordinator, which keeps its footprint in the session frame; one camera is tested against the walls as it arrives, and the whole set is redone when the placement moves. The inset's walls shade grey, amber and green at 30% and 70%, with a *walls 3/4* caption; the camera band in the picture is not built. The mesh half of the offline report stays offline. Tested on a square and an L-shaped room, and held against `coverage.py` on the fixture room by the `contract` CI job; not yet compared on one real capture.

**What is measured.** For each wall of the outline, the segment between consecutive corners, the fraction of its length that a keyframe has photographed from within 2 m and within 60 degrees of square-on. The same definition as `vividhome coverage`, computed on the phone from the poses the session is writing, against the outline rather than the mesh, because the mesh cannot say what was missed. Height is ignored in this version; the PC's report keeps the upper-half case.

**How it shows.** Each wall of the plan inset shades from grey to green as it is covered, and the camera view draws a faint band along a wall's foot while the owner is looking at it: grey where it has not been photographed close enough, green where it has. Approximate on purpose, and labelled *coverage*, never *done*.

**Cost.** Per keyframe, one test per wall: a few hundred operations a second, nothing against the capture's own work.

## 5. The stills checklist and the leave check

**Built 2026-10-03, walked by nobody.** `StillsChecklist` in the core package is the protocol's §4 table as data, one list per phase, the common *each wall square-on* item first and an item two trades share listed once. The HUD shows the list as chips above the buttons, each ticked once a still for it is on disk; a tap on a chip takes the still for that item, so the list is both the reminder and the shutter, and the camera button still takes a still with no label. `stills.jsonl` carries `item`. At Stop the coordinator makes a `FieldCheck` from the placement, the walls' live coverage and the stills taken; the review screen shows its three lines at the top, green or orange, and the manifest carries it as `field_check`. *Capture more* under the lines starts a top-up: the same room and trades, its own session, guided again (§6). `ingest`'s index passes `field_check` through for the inspect page to use later. **Decided without the owner:** chips rather than a pick after the shutter, because one tap per still is what a cold site allows; marker stills and the dated sheet left off the list (markers are optional, the sheet is in the video); a wall counts as photographed from 70%, the inset's green band; the `walls` block is omitted when the capture is not placed rather than guessed; the lines are made from the numbers by the core package on both ends rather than stored as text. Tested on Linux (checklist contents, progress, the file's keys, the three lines). The inspect page shows the three lines per session, made from the manifest's numbers by `fieldcheck.py`, the Python twin of `FieldCheck.lines`; the `contract` job holds the twins and the checklist's names together.

**The checklist.** `capture-protocol.md` §4 already lists the stills each phase requires. It moves into the app as data, one list per phase, shown in the HUD's stills control: tap *Still* and pick what it is (panel, box, header, duct...), or skip the pick. A still carries its item in `stills.jsonl` as an additive `item` field. The checklist shows what is ticked.

**The leave check.** Stop opens the review screen, which already exists; it gains three lines at the top, each green or orange:

- *Placed on the plan, residual 6 cm* or *Not placed: tap two corners*;
- *Walls photographed: 4 of 5; north wall, 1.9 m from the NE corner, not photographed*;
- *Stills: 7 of 11 on the electrical list; missing panel, home runs, smoke locations*.

Under them, *Capture more*, which starts a top-up session for the same room and phase (§6). The three lines are written into the manifest at Stop as an additive `field_check` object, so the PC's index and the inspect page can show them.

## 6. Free capture and top-ups

**Built 2026-10-03, walked by nobody.** `PlanPlacementView`, reached from a past capture (*Place on the plan*, or *Adjust the placement* once there is one): the capture's landmarks as chips, the drawing on the canvas the Scale and Outline screens use, tap a chip then its place on the drawing, two pairs minimum, the fit and its verdict live with the HUD's thresholds and each pair's residual on its chip. *Place* writes ADR-0030's file with `method: paired`; an existing placement loads as its pairs so it can be adjusted, and *Replace* overwrites. The capture's detail screen says *Placed during capture, 6 cm*, *Placed paired on the plan, 12 cm* or *Not placed*. Top-ups: *Capture more* on the review screen starts one (§5), and **a capture reads the room's earlier captures with it** (built the same day, `RoomHistory` in the core package): when a capture starts, the complete captures of the same room and level sharing a trade are gathered; their keyframes, moved into the house frame by their own placements, shade the walls before the top-up is itself placed; their walks draw faintly on the inset; their stills tick the checklist; and the leave check names them in `field_check.together`, so a top-up's check describes the room. A capture with no placement contributes only its stills. The PC's `coverage` command still reads one session. **Decided without the owner:** pairing is by landmark label, so two landmarks with one label are one chip; the floor height is the landmark rule (floor-tagged, else lowest), the mesh route is not on the phone; a fit above the PC's refusal cannot be written, as for a guided capture; the screen is reached from the capture rather than offered right after Stop, since a guided capture no longer needs it there.

**Free capture** is today's capture: no outline, no guidance. The owner picks it by capturing a room that has no outline, or by turning guidance off at setup. The keyframes, stills, mesh and landmarks are written exactly as now; nothing about the record changes. What changes is that placement happens later: pair after Stop on the phone (the screen `phone-first-loop-design.md` §3 described, kept for this case), or on the PC, or never. A free capture still browses in Photos and still counts in coverage once placed.

**A top-up** is a second, usually short, session of the same room and phase: the re-shoot the leave check asked for, or an extra still noticed on the way out. It is its own session (ADR-0022, one pass per session; raw sessions are immutable, so nothing is appended to the first). Its keyframes are not merged with the first capture's: the plan view draws both walks, and the coverage check and the checklist read every session of that room and phase together, so a top-up closes the gaps of the capture before it. Placement for a top-up is guided again, two corners, which takes seconds; a top-up with no corners is placed by the PC later from overlap, or stays unplaced and is still browsable.

## 7. Files

| What | Where | Status |
|---|---|---|
| Room outline | `plans/<level>.json`, `rooms[].outline` and `outlined_at` | new, additive, §13 |
| Corner names | `landmarks.jsonl` `label`, as the protocol already names them | unchanged |
| Snap | `landmarks.jsonl` `method` | existing field, new value |
| Placement | `alignments/<session-id>.json`, `source: app`, `method: guided` | ADR-0030's file |
| Still item | `stills.jsonl` `item` | new, additive |
| Leave check | `manifest.json` `field_check` | new, additive |

Every addition keeps `format_version` at 3 and lands in `session-format.md` with the first implementation (ADR-0021).

## 8. Sequencing

1. Outlines on the plan, corner naming, and the guided taps with the live solve and residual. This is ADR-0030's align step, moved into the capture.
2. The plan inset with the walk, which is the first level view.
3. Live wall coverage against the outline.
4. The stills checklist and the leave check.
5. The pairing screen for free captures, and the top-up flow.
6. The server watcher on the PC, now that a capture arrives placed.

**Step 6 built 2026-10-03.** Not a second process: `serve --lan` already sees every arrival, so it renders. When `ingest` adopts the placement a capture arrived with, the server queues that level's inspection page on a background thread (one page per level however many captures land together) and the receipt says `inspect: queued`; the index's `inspect` for the level says when the page exists, which is when the app's *Rendering on the PC* row is current. `align` on the PC draws the page too when it writes, unless `--no-inspect`. **Decided without the owner:** rendering inside `serve` rather than a `vividhome watch` command, because a folder watcher would be a second thing to start and the server is the thing that knows a capture landed; a capture that is not placed renders nothing, since the page would not change; the reply to the phone does not wait for the page, since thumbnails take a minute and the uploader would give up. Tested: a placed capture arriving over the upload endpoint ends with the page written and listed by the index.

## 9. Risks

- **The plan is wrong.** A room built 20 cm off the drawing shows as a 20 cm residual, and the app cannot tell a bad tap from a bad plan. The verdict says *check*, not *wrong*, and the PC's corner comparison (`corners.py`) later says which.
- **Snapping to the wrong thing.** A stack of drywall against the wall makes a plane. The snap moves a point at most 0.5 m, shows itself, and can be undone with a long press.
- **Screen clutter.** The HUD already carries counts, tracking and a landmark strip. The chips replace the kind picker while a room is guided; the inset is small and collapsible; nothing new appears while the owner is looking through the camera except the wall band.
- **Free captures looking second-class.** They are the same record. The leave check says *not placed yet* in orange, not *failed*.
