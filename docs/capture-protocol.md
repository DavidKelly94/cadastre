# Capture protocol

How to record a room with VividHome so the data is usable years later. Read `docs/markers.md` first: markers must be up before the first session in a room.

Rule of thumb: one room, one pass, one session, under five minutes, start and end at the door. A pass covers whatever trades are exposed that day, so if the electrician and the plumber have both been in, tick both.

## 1. Before you go

- Phone charged above 80%, power bank packed. Capture writes 2 to 3 MB/s and heats the phone.
- At least 10 GB free. A five-minute room is about 800 MB; the app refuses to start below 2 GB and stops below 500 MB.
- Last visit's sessions copied to the PC and validated, then deleted from the phone if space is tight.
- Markers placed and logged; expected IDs entered per room in the app.
- Tape measure with a metric scale, and a dated sheet: a page with date, project and phase in thick marker, shown in the first wall shot of every room.
- The one-page checklist at the end of this document, printed.
- Latest TestFlight build installed. Brightness at maximum. Do Not Disturb on: a call pauses the session.
- A work light for basements and closed rooms; low light drops tracking to limited.

## 2. Per room, per pass

If the app stops or you must leave, start a new session for the same room and say so in the notes; the pipeline joins them through the markers.

1. In the app: project, room, and every phase exposed in this pass. Check the expected marker IDs. Start capture.
2. Wait for tracking OK. If it stays limited, see section 6.
3. Stand in the doorway facing into the room, phone at chest height, dated sheet in view. Press REC.
4. Mark landmark: tap the floor at the centre of the door threshold and label it `door D3 threshold`, using the door number from the plan. Thresholds and corners drive the plan alignment, so tap the actual floor point, not the wall.
5. Slow sweep: turn through the room at chest height, about ten seconds per quarter turn, walls 1.5 to 3 m away. Then walk the perimeter slowly, phone on the wall you are passing, tilting floor to ceiling about once per stud bay.
6. At each corner, tap the floor and label it `corner NW`, `corner NE`, `corner SE` or `corner SW` by the plan's north; extra corners in an L-shaped room are `corner NW2` and so on. Same labels in every phase.
7. Each wall square-on: stand back so the wall fits floor to ceiling, tape hooked on a stud or plate and extended across the frame. Take a Still; long walls get overlapping stills every 1.5 m. Same spot and height in every phase so phases compare.
8. Detail stills: every box, pipe penetration, gas line and fitting, header, blocking, duct and register, from about 1 m, square-on, then one from an angle showing where it sits in the wall. Anything you would want to find with a drill later gets a still.
9. Marker stills: each marker in the room, square-on, from about 1 m, filling much of the frame. Wait for the HUD marker count to rise before moving on.
10. One slow pass looking up (joists, ducts, wire runs) and one looking down (subfloor penetrations, drains).
11. Walk back to the doorway, point at the starting view, hold three seconds, press STOP. Wait for finalizing.
12. Session review: check the flags. If one is red (fewer than two markers, limited tracking over 20%, loop not closed), re-shoot now; a second visit costs far more. Note anything unusual.

Move slowly throughout; fast turns, and walking while turning, lose keyframes.

## 3. Landmark labels

| What | Label shown | Where to tap |
|---|---|---|
| Room corner | `corner NW` (NE, SE, SW; NW2 for extra corners) | Floor, at the inside corner |
| Door threshold | `door D3 threshold` | Floor, centre of the opening |
| Stair | `stair top nosing`, `stair bottom nosing` | Nosing centre; ties levels together |

Stored as `corner-nw`, `door-d3` and so on (`docs/session-format.md`). Use the plan's door and window numbers; if it has none, number clockwise from the main entrance and write them on the plan.

## 4. Phase checklists

Every phase: markers, thresholds, corners, walls square-on with the tape, dated sheet, loop closed.

| Phase | Stills required | Notes |
|---|---|---|
| framing | Headers, king and jack studs, blocking, fire blocking, stair framing, top plates, anchor bolts, hold-downs, odd stud spacing | Easiest tracking. Hang top plate and jamb markers now. |
| electrical | Every box with its cable count, panel with cover off, home-run routes, nail plates, low-voltage runs, smoke and CO locations, exterior penetrations | Jacket colour identifies gauge; tape across the box height. |
| plumbing | Supply runs and manifold, drains and vents, cleanouts, shutoffs, water heater connections, hose bibs, tub and shower valves; gas line with every fitting and shutoff | Gas joints from two angles. |
| hvac | Duct trunks and branches, register and return boots, line sets, condensate, flues, ERV or HRV ducts, thermostat wires, dampers | Ducts hide wires; still the wall before and after where you can. |
| insulation | Each bay after insulation, vapour barrier seams, sealed penetrations, blocking hidden behind batts | Top plate markers may be covered; hang jamb markers now. |
| drywall | Each wall before mud, screw lines (they show stud centres), access panels, repairs | Textureless: add light, slow down, keep markers and openings in view. |
| finish | Each wall finished, every outlet, switch, fixture and register, flooring seams | Corners and thresholds must still be tapped. |

## 5. Session length and thermal rules

- Aim for 5 minutes or less; the app warns at 5 minutes and auto-stops at 10. Split a large room into two sessions that both see the same two markers.
- Drift grows with time and distance; short sessions that end where they started align best.
- The HUD shows thermal nominal, fair, serious or critical; serious halves the keyframe rate, critical stops the session. At serious, finish the wall you are on, stop, and rest the phone in shade with the screen off for five minutes. Never start on a phone hot from a sunny pocket.
- Below 500 MB free the session stops itself. Watch the free GB figure on the HUD.

## 6. Tracking limited: recovery

| Reason on HUD | Cause | Fix |
|---|---|---|
| excessive motion | Turning or walking too fast | Stop, hold still two seconds, continue at half speed |
| insufficient features | Blank wall, bare drywall, one flat surface too close | Step back, aim at edges: studs, openings, boxes, markers |
| low light | Basement, closed room, dusk | Add a work light; the phone flash does not help |
| initializing | Session just started or resumed after an interruption | Hold still, then pan slowly until OK |

Keyframes are not saved while limited, so a wall filmed in that state is missing: do it again once tracking reads OK. If tracking never recovers, stop, review, and start a new session from the doorway.

## 7. After the visit

1. Same day: copy every session folder from Files (On My iPhone, VividHome, sessions) to the PC by SMB share or USB with the Apple Devices app (`docs/owner-setup.md`).
2. Run `vividhome ingest <folder>` then `vividhome validate <session>`. Fix or re-shoot anything reported.
3. Run `vividhome apriltag <session>`; confirm every expected marker was found.
4. Mark each session transferred in the app. Delete from the phone only after validate passes and the PC copy is backed up.
5. Update the marker log with anything moved, covered or lost.

## 8. One-page checklist

Print this page.

Before

- [ ] Phone charged, power bank packed
- [ ] 10 GB or more free; last visit's sessions copied and validated
- [ ] Markers placed, logged, IDs entered per room
- [ ] Tape measure, dated sheet, work light
- [ ] Brightness at maximum, Do Not Disturb on

Each room

- [ ] Room and phase selected, expected markers checked
- [ ] Tracking OK before REC
- [ ] Doorway: dated sheet in view, REC, threshold landmark
- [ ] Slow sweep, then perimeter walk
- [ ] Corner landmarks with plan labels
- [ ] Each wall square-on, tape in frame, still
- [ ] Detail stills: boxes, penetrations, gas, headers, blocking, ducts
- [ ] Marker stills, square-on, about 1 m; count rises on HUD
- [ ] Ceiling pass, floor pass
- [ ] Back to the doorway, hold, STOP
- [ ] Review flags; re-shoot if red; add notes

After

- [ ] Copy to PC, `vividhome ingest`, `vividhome validate`
- [ ] `vividhome apriltag`; all expected markers found
- [ ] Mark transferred; update marker log
