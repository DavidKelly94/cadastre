# Markers

Printed fiducial markers tie sessions together across construction phases. ARKit cannot relocalize a room once its appearance changes (framing to drywall removes every visual feature it remembered), so every session must see at least two markers, and the pipeline chains phases through marker IDs. The plan is the final invariant frame; markers are how each phase reaches it.

## 1. Specification

A marker is a 20.0 cm square with three parts, from the centre out:

| Part | Size | Purpose |
|---|---|---|
| AprilTag 36h11 | 12.8 cm: 8 by 8 cells of 1.6 cm, outer cell ring black | Detected by the pipeline (OpenCV) in keyframes and stills; gives the ID and a 6-DoF pose |
| Quiet zone | 1.6 cm white border | Required by the AprilTag detector |
| High-detail ring | 2 cm band, pattern seeded by the marker ID | Gives ARKit image detection enough detail and makes each marker's reference image unique |
| Label | `IG-017` in large type below the square | Human-readable; matches the app's marker list |

12.8 + 2 x 1.6 + 2 x 2 = 20.0 cm. IDs run `IG-000` to `IG-059` (60 markers; a house needs 20 to 40). `igloo markers` in the pipeline generates the PDF, one marker per Letter or A4 page, and the PNGs. The same PNGs are bundled in the app as ARKit reference images with a physical width of 0.20 m, so the printed size and the app setting must agree exactly.

## 2. Printing

- Print at 100% or Actual size. Turn off fit to page, shrink to fit and any scaling. Letter and A4 both work; the square nearly fills the sheet width, so a printer that cannot print within 5 mm of the edge needs borderless mode.
- Matte paper, then matte lamination pouches. No gloss: glare breaks detection for both the tag and ARKit.
- After lamination, measure the outer square with a tape. It must read 20.0 cm (accept 19.9 to 20.1). Reprint anything else; a 2% size error becomes a 2% scale error in every pose computed from that marker.
- Check that Settings in the app shows marker width 20.0 cm.
- Print spares. On a site, markers get painted, kicked and covered.

## 3. Placement rules

- At least two per room, visible from the middle of the room and from the doorway, 2 to 3 m apart, on different walls where possible. Two markers on one wall constrain a pose poorly.
- Standard pair: one flat on the subfloor by the door, inside the room, 100 to 300 mm from the threshold; one on the top plate or a rough-opening jamb, facing into the room, at 1.2 to 2.0 m height so a camera at chest height sees it square-on.
- Shared markers at stair landings and in doorways between rooms, visible from both sides, so sessions and levels chain.
- Every session must see at least two markers that the next phase's session will also see. Before a phase covers a surface, hang the replacement and capture a session that sees old and new together. This is the hand-off.
- Mount flat on a rigid surface: spray adhesive or double-sided tape over the whole back, plus a staple or screw in each corner outside the ring. A bowed marker gives a wrong pose.
- Keep 300 mm clear of where a trade will cut, nail or fasten: plate edges under future drywall screws, box locations, duct paths. Ask the framer to leave them.
- Face them square to the room; avoid direct sun on the marker and deep shadow.
- Tell every trade that the laminated squares stay.

## 4. Surfaces and the phases they survive

| Surface | Visible during | Covered at |
|---|---|---|
| Subfloor by the door threshold | framing through drywall | finish (flooring) |
| Top plate, face towards the room | framing through hvac, usually insulation | drywall |
| Door rough-opening jamb | framing through drywall | finish (door frame, casing) |
| Window rough-opening jamb | framing through drywall | finish (extension jambs) |
| Stair stringer or landing subfloor | framing through drywall | finish |
| Exterior sheathing, inside face of a stud bay | framing through hvac | insulation |
| Ceiling joist underside | framing through hvac | drywall |
| Electrical panel backer board | all phases in an unfinished utility room | never |
| Basement or garage slab, foundation wall | all phases while unfinished | basement finish |

Plan each room so that at every phase two markers are visible now and remain for the next phase. A typical room: subfloor and top plate markers at framing, a jamb marker added at insulation before drywall, slab or utility-room markers as permanent anchors for the whole level.

## 5. Recording positions

Write down every marker's position relative to a feature that survives all phases and exists on the plan, so it can be found again or re-hung. Use one sentence in a fixed form: marker ID, reference feature, offsets in millimetres from two edges, orientation.

- `IG-012: centred on door D3 threshold, 100 mm from left jamb, flat on subfloor, label towards the room`
- `IG-017: kitchen north wall top plate, lower edge 40 mm below plate bottom, left edge 250 mm right of window W2 rough opening, facing south`
- `IG-030: stair landing L1 to L2, 150 mm from nosing, centred between stringers`

Photograph each marker with its reference feature in frame, and enter the sentence and the photo in the app's Markers screen. Mark the position on the paper plan as well.

## 6. Never move a placed marker

A marker is only useful because it is in the same place in every session. Moving it silently breaks the chain between phases, with no error until alignment fails weeks later.

- Never move, re-stick or straighten a placed marker. If it is peeling, add fasteners around it without shifting it.
- If a marker is damaged, covered or gone, do not reuse its ID at a new spot.

Re-hang protocol:

1. Find the marker's line in the log and check the reference feature still exists.
2. If you can put it back within 10 mm using the recorded offsets, re-hang the same ID and add "re-hung, date" to the log. The pipeline treats it as lower confidence.
3. Otherwise hang a new ID as close as practical, log its position, and mark the old ID "lost, date, replaced by IG-0xx".
4. Either way, record a session that sees the re-hung or new marker together with at least one other established marker in the same room, and say so in the session notes.

## 7. Detection range and accuracy

Published tests with a 16.4 cm AprilTag report roughly 1.6 to 3.4 cm position error and 0.8 to 3.2 degrees orientation error at 2 m, worsening to 5.8 to 12.4 cm and up to 8 degrees at 3 m. Tags of 10 to 20 cm stop being detected reliably beyond about 4 m. The Igloo tag is 12.8 cm inside a 20 cm square, so treat those numbers as optimistic: good poses come from 1 to 2 m, square-on, in even light. A marker seen only beyond 4 m contributes nothing usable and may not be detected at all.

ARKit's on-device image detection tracks up to four markers at once and only needs to notice a marker; the accurate pose comes from the pipeline's PnP solve on keyframes and stills. This is why the protocol requires a still of each marker from about 1 m: one sharp square-on still is worth more than fifty glancing keyframes.

Expected result per session: the pipeline reports each marker's pose spread across its observations. Under 3 cm is normal. Over 5 cm means glare, a bowed print, a wrong size setting or motion blur.

## 8. Marker log template

Keep this table in the project notes and mirror it in the app's Markers screen.

| ID | Level | Room | Surface | Position (fixed form) | Placed | Expected until | Status | Photo | Notes |
|---|---|---|---|---|---|---|---|---|---|
| IG-012 | L1 | Kitchen | Subfloor | centred on door D3 threshold, 100 mm from left jamb, flat, label towards room | 2026-10-04 | drywall | active | IMG_0412 | |
| IG-017 | L1 | Kitchen | Top plate, N wall | lower edge 40 mm below plate bottom, left edge 250 mm right of W2 rough opening, facing S | 2026-10-04 | insulation | active | IMG_0413 | hand-off to IG-031 before drywall |
| IG-030 | L1 to L2 | Stair landing | Landing subfloor | 150 mm from nosing, centred between stringers | 2026-10-04 | finish | active | IMG_0420 | shared L1 and L2 |

Status values: planned, active, covered, lost, re-hung, replaced.
