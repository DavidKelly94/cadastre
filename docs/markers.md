# Markers

Printed fiducial markers tie sessions together across construction phases. ARKit cannot relocalize a room once its appearance changes (framing to drywall removes every feature it remembered), so every session must see at least two markers and the pipeline chains phases through their IDs; the plan is the final invariant frame.

## 1. Specification

A marker is a 20.0 cm square, from the centre out:

| Part | Size | Purpose |
|---|---|---|
| AprilTag 36h11 | 12.8 cm: 8 by 8 cells of 1.6 cm, outer cell ring black | Detected by the pipeline (OpenCV) in keyframes and stills; gives ID and 6-DoF pose |
| Quiet zone | 1.6 cm white border | Required by the AprilTag detector |
| High-detail ring | 2 cm band, pattern seeded by the marker ID | Gives ARKit image detection enough detail; makes each reference image unique |
| Label | `CD-017` in large type below the square | Human-readable; matches the app's marker list |

12.8 + 2 x 1.6 + 2 x 2 = 20.0 cm. IDs run `CD-000` to `CD-059` (a house needs 20 to 40). `cadastre markers` generates the PDF, one marker per Letter or A4 page, and the PNGs; the same PNGs are bundled in the app as ARKit reference images with a physical width of 0.20 m, so the print and the app setting must agree exactly.

## 2. Printing

- Print at 100% or Actual size with fit-to-page and all scaling off. Letter and A4 both work; the square nearly fills the width, so a printer that cannot print within 5 mm of the edge needs borderless mode.
- Matte paper, matte lamination pouches. No gloss: glare breaks detection for the tag and for ARKit.
- After lamination, measure the outer square: 20.0 cm (accept 19.9 to 20.1). Reprint anything else; a 2% size error becomes a 2% scale error in every pose from that marker.
- Check that the app's Settings shows marker width 20.0 cm.
- Print spares; markers get painted, kicked and covered.

## 3. Placement rules

- At least two per room, visible from the middle of the room and the doorway, 2 to 3 m apart, on different walls where possible; two on one wall constrain a pose poorly.
- Standard pair: one flat on the subfloor inside the door, 100 to 300 mm from the threshold; one on the top plate or a rough-opening jamb facing the room at 1.2 to 2.0 m, so a chest-height camera sees it square-on.
- Shared markers at stair landings and in doorways between rooms, visible from both sides, so sessions and levels chain.
- Every session must see at least two markers that the next phase's session will also see. Before a phase covers a surface, hang the replacement and capture a session that sees old and new together (the hand-off).
- Mount flat on a rigid surface: adhesive over the whole back plus a staple or screw in each corner outside the ring; a bowed marker gives a wrong pose.
- Keep 300 mm clear of where a trade will cut, nail or fasten; face them square to the room, out of direct sun and deep shadow; tell every trade the laminated squares stay.

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

Typical plan: subfloor and top plate markers at framing, a jamb marker added at insulation, slab or utility-room markers as permanent anchors for the level.

## 5. Recording positions

Record every marker's position relative to a feature that survives all phases and exists on the plan, so it can be found again or re-hung: one fixed-form sentence with ID, reference feature, offsets in millimetres from two edges, and orientation.

- `CD-012: centred on door D3 threshold, 100 mm from left jamb, flat on subfloor, label towards the room`
- `CD-017: kitchen north wall top plate, lower edge 40 mm below plate bottom, left edge 250 mm right of window W2 rough opening, facing south`

Photograph each marker with its reference feature in frame; enter the sentence and photo in the app's Markers screen and mark the position on the paper plan.

## 6. Never move a placed marker

Moving a marker silently breaks the chain between phases, with no error until alignment fails weeks later. Never move, re-stick or straighten a placed marker; if it peels, add fasteners around it without shifting it. If it is damaged, covered or gone, do not reuse its ID at a new spot.

Re-hang protocol:

1. Check the log entry and that the reference feature still exists.
2. If it can go back within 10 mm of the recorded offsets, re-hang the same ID and log "re-hung, date"; the pipeline treats it as lower confidence.
3. Otherwise hang a new ID nearby, log it, and mark the old ID "lost, date, replaced by CD-0xx".
4. Either way, record a session that sees it together with another established marker in the room, and note this in the session.

## 7. Detection range and accuracy

Tests with a 16.4 cm AprilTag report about 1.6 to 3.4 cm position and 0.8 to 3.2 degree orientation error at 2 m, and 5.8 to 12.4 cm and up to 8 degrees at 3 m; 10 to 20 cm tags stop being detected reliably beyond about 4 m. The Cadastre tag is 12.8 cm inside a 20 cm square, so treat these as optimistic: good poses come from 1 to 2 m, square-on, in even light; beyond 4 m a marker adds nothing usable and may not be detected at all.

ARKit's on-device detection tracks up to four markers at once and only needs to notice a marker; the accurate pose comes from the pipeline's PnP solve on keyframes and stills, which is why the protocol requires a still of each marker from about 1 m. Expect the pipeline to report under 3 cm pose spread per marker; over 5 cm means glare, a bowed print, a wrong size setting or motion blur.

## 8. Marker log template

Keep this table in the project notes and mirror it in the app's Markers screen.

| ID | Level | Room | Surface | Position (fixed form) | Placed | Expected until | Status | Photo | Notes |
|---|---|---|---|---|---|---|---|---|---|
| CD-012 | L1 | Kitchen | Subfloor | centred on door D3 threshold, 100 mm from left jamb, flat, label towards room | 2026-10-04 | drywall | active | IMG_0412 | |
| CD-017 | L1 | Kitchen | Top plate, N wall | lower edge 40 mm below plate bottom, 250 mm right of W2 rough opening, facing S | 2026-10-04 | insulation | active | IMG_0413 | hand-off to CD-031 before drywall |

Status values: planned, active, covered, lost, re-hung, replaced.
