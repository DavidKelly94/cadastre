# Capture guidance: proposed corner marks, and what is still missing

Design for [ADR-0034](../adr/0034-placement-from-the-scan-taps-as-the-fallback.md) and [ADR-0035](../adr/0035-a-capture-complete-enough-for-3d.md), written 2026-11-13 before any of it is built. It extends `field-proof-design.md`, whose guided taps, live placement, wall coverage and leave check all stay. Every number below is a first guess, marked as one, to be set from real captures.

Units in this document follow the code: meters, session frame `+y` up, house frame as in `docs/session-format.md` section 3.

## 1. Goals and non-goals

Goals: where the scan can see a room's corners, the owner confirms marks instead of tapping them; where it cannot, the app says which corner it needs; a mark can always be overridden by hand; the capture says what a 3D model still lacks, by name, while the room can still be walked.

Non-goals: placing a capture with nobody confirming it; deciding anything about a building from the scan (rule 9); splats or meshing (ADR-0036); rooms with no outline, which keep today's free capture and gain only the parts of section 3 that need no outline.

## 2. Proposed corner marks (ADR-0034)

### 2.1 A corner is a vertical line

Two walls meet in a vertical line. On the plan that line is one point, so evidence from any height counts: the floor corner, the ceiling corner, the top plates of a framed wall. The finder therefore works on wall planes, not on floor points, and reports each corner as a plan position `(x, z)` with the heights at which it was seen.

This is what makes framing plausible at all. Studs are see-through, but the bottom plate, the top plate and the stud faces of one wall lie in one plane.

### 2.2 Finding walls in the live mesh

`CornerSnap` already fits vertical planes to the mesh faces within half a meter of a tap, and `corners.py` does the same over a whole mesh (`find_walls`, `corner_candidates`). The new core type `CornerFinder` is the whole-room version in Swift:

1. Take mesh faces as `CornerSnap.Face`. Keep faces whose normal is within 0.2 of horizontal. Use faces classed wall first; if they cover less than 2 m² in total, use every vertical face, since ARKit rarely classes open framing as wall.
2. Cluster into planes as `find_walls` does: by direction within 10 degrees and offset within 0.15 m, weighted by area, refit once.
3. Keep a plane with at least 0.5 m² of support (first guess; framing may need less).
4. Intersect each pair of planes between 60 and 120 degrees apart. A crossing is a **candidate** when both planes have support within 0.5 m of it. Record the lowest and highest supported height at the crossing.

### 2.3 Matching candidates to the outline

The outline's corners in house meters come from `PlanFile.houseCorners(of:)`. A rigid motion on the plan (rotation and shift, never a mirror) is fixed by two matched corners, so:

1. For every pair of candidates and every pair of outline corners whose separations agree within 0.15 m, form the motion that maps one pair onto the other.
2. Count candidates that land within 0.15 m of an outline corner: the inliers. Score by inlier count, then by RMS.
3. The best motion gives the **proposal**: each inlier becomes a mark named for its outline corner.
4. If another motion has the same inlier count and an RMS within 0.03 m, the room is **symmetric as seen**. Keep both.

One candidate alone proposes nothing. The solve that follows confirmation is the existing `PlanAlignment.solve`, unchanged.

### 2.4 What the owner sees

- **Proposed marks** in the camera view: a dashed ring with the corner's name, drawn at the floor end if seen there, otherwise at the ceiling end. A banner: "Found 3 of 4 corners" with **Confirm**.
- **Confirm** turns every proposed mark into a placed one, exactly as if tapped. Tapping a single proposed mark confirms that one.
- **Override, always.** Drag a mark to move it. Tap its name to dismiss it. Tap the real corner to replace it; a tap wins over a proposal at any time, before or after confirming. A switch on the capture screen turns proposals off for this capture, which leaves today's guided taps.
- **A hand is needed** is said by name: "NE corner: the scan cannot see it. Tap it, at the floor or the ceiling." Shown when a corner has no candidate after its two walls are each at least half photographed, or when fewer than two corners have candidates after a minute.
- **Which way round.** For a symmetric room the app shows one fit and asks: "Is NW here?" with **Yes** and **Other way**. If one tapped room on the level has already fixed how the drawing faces, the phone's heading picks the fit to show first; it still asks.
- **A fit that looks wrong** (RMS over 0.10 m after confirming) says so in the existing FIT readout and suggests re-tapping the worst corner.

### 2.5 Floor and ceiling, and wall height

- A manual tap may land on a ceiling corner. Today the floor's height is taken from the corner taps, so a ceiling tap must not be mistaken for a floor one: the landmark gains an optional `"end": "ceiling"`; absent means floor. `PlanAlignment.floorY` ignores ceiling ends.
- A corner seen at both ends must stand upright: if the two ends differ by more than 0.05 m on the plan, the mark is shown in orange, "floor and ceiling disagree".
- A level may carry an optional `wall_height_m` in its plan file, entered by the owner. When present, the scan's floor-to-ceiling distance is compared with it (a difference over 0.10 m is reported, not acted on), and a corner seen at one end is looked for at the other. The same number later sets how levels stack in 3D (ADR-0036).

### 2.6 What is recorded

- A confirmed proposal is a line in `landmarks.jsonl` like a tap, with `"method": "mesh_corner_proposed"` beside the existing `mesh_corner_snap`. A proposal that was moved by hand records `"method": "mesh_corner_proposed_moved"`. A dismissed proposal records nothing.
- `field_check.placement` gains optional `proposed` and `tapped` counts, so the PC can compare the two over many captures.
- Additions to `docs/session-format.md`, all optional, version unchanged: the two `method` values, `end` on a landmark, `wall_height_m` on a plan, the two counts.

## 3. What is still missing (ADR-0035)

### 3.1 The measures

All from what a capture already holds: keyframe poses, intrinsics, and the room outline when there is one.

| Measure | Definition (first guesses) | Needs an outline |
|---|---|---|
| Wall seen twice | Per 0.10 m wall cell, as `WallCoverage` has them: the bearings from which it was photographed span at least 20 degrees, and one view was within 2.5 m | yes |
| Floor seen | At least 10 keyframes pitched 25 degrees or more downward, from at least 3 different half-meter squares | no |
| Ceiling seen | The same, pitched upward | no |
| Two heights | At least 15 percent of keyframes 0.4 m or more above or below the median camera height | no |
| Ground covered | Share of half-meter squares within 1 m of a wall that the camera stood in | yes |

"Enough for 3D" is green when wall cells seen twice reach 70 percent and floor and ceiling are both seen; orange otherwise. Two heights and ground covered are advice only.

### 3.2 Saying what is missing

The capture screen gains one row, labeled 3D, beside the existing LIST row: `Walls 62%`, `Floor`, `Ceiling`, each ticking as it is met. Under it, at most two lines naming the largest gaps, worst first, in the wall names the leave check already uses:

- "East wall, 1.2 m from the NE corner: seen from one spot. Step sideways and look again."
- "Ceiling not seen. Tilt up as you walk."
- "Floor not seen."

The plan inset shades each wall in three states instead of two: not photographed, photographed, seen twice. The leave check gains the line "Enough for 3D" with the same gaps. It never blocks Stop.

### 3.3 What is recorded

`field_check` gains an optional `model` object: `walls_twice` (0 to 1), `floor`, `ceiling`, `heights` (booleans), and `gaps` (the longest stretches of wall not seen twice, as numbers; the lines shown are made from them at display time, so they follow the reader's units). The PC recomputes the same numbers in `fieldcheck.py`, and the contract job compares the two, as it does for coverage today.

## 4. Where the code goes

| Piece | Where | Tested |
|---|---|---|
| `CornerFinder`: walls, candidates | `ios/VividHomeCore` | Linux, on the synthetic room mesh the fixture already writes |
| `CornerMatch`: candidates to outline, symmetry | `ios/VividHomeCore` | Linux: rectangle (symmetric), L-shape (not), a hidden corner, clutter |
| `ModelReadiness`: section 3.1 | `ios/VividHomeCore` | Linux: turning on the spot fails, a walk along the walls passes |
| The same three in Python | `pipeline/vividhome` (`corners.py`, `fieldcheck.py`) | pytest, and the contract job |
| Gathering faces, drawing marks, the banner and the 3D row | `ios/VividHome` (`CaptureCoordinator`, `CaptureHUDView`, `MeshVisual`) | compiles in CI; walked by the owner |

Rule 3 holds: the ARKit layer gathers faces and draws; every decision is in the core.

## 5. Order of work

Each line is one pull request, and each leaves the app working.

1. `ModelReadiness` in the core and in Python, with the contract comparison. **Built 2026-11-13**, and wired a little further than planned: the capture records `model` at Stop and the review screen shows the fourth line with up to two things to do, since that costs no new screen. "Ground covered" from section 3.1 is not built.
2. The 3D row, the two lines of gaps, the three-state inset, the leave-check line.
3. `CornerFinder` and `CornerMatch` in the core, with the Python twin run over the rehearsal capture on the owner's PC.
4. Proposed marks on the capture screen: draw, confirm, override, the off switch.
5. Ceiling taps and `end`; the upright check.
6. `wall_height_m`: entry on the plan screen, the comparison.
7. Heading, only if symmetric rooms prove common.

Steps 1 and 2 come first because they change what a framing capture contains; the rest change how it is placed, which taps already do.

## 6. Risks

- **Framing.** Nothing here has seen open studs. If the plane finder fails there, the owner still gets the names of the corners to tap, which is today's flow. The first framing captures, with taps, are the evidence for step 3.
- **A confident wrong match.** A room with two walls of nearly equal length can match the wrong pair. The confirmation is the guard, and the RMS readout after it.
- **Thresholds set blind.** Every number in sections 2 and 3 is a guess. They live as named constants in the core so the PC's comparison can move them.
- **Screen load.** The capture screen gains a banner and a row. If it is too much on site, the 3D row collapses to one chip.
- **Battery and heat.** The finder runs on a snapshot of the mesh every two seconds at most, off the main thread, and stops once every corner is placed.
