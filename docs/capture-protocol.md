# Capture protocol

How to record a room with Igloo so the data is usable years later. Read `docs/markers.md` first: markers must be up before the first session in a room.

Rule of thumb: one room, one phase, one session, under five minutes, start and end at the door.

## 1. Before you go

- Phone charged above 80%, power bank in the bag. Capture writes 2 to 3 MB/s and heats the phone.
- At least 10 GB free (Settings, General, iPhone Storage). A five-minute room is about 800 MB. The app refuses to start below 2 GB and stops itself below 500 MB.
- Sessions from the last visit already copied to the PC and validated, then deleted from the phone if space is tight.
- Markers placed and logged, and the expected IDs entered for each room in the app.
- Tape measure with a metric scale, and a dated sheet: a page with the date, project and phase in thick marker. It appears in the first wall shot of every room.
- A print of the one-page checklist at the end of this document.
- Latest TestFlight build installed and opened once on Wi-Fi. Screen brightness at maximum. Do Not Disturb on: a call pauses the session.
- A work light for basements and closed rooms. Low light drops tracking to limited.

## 2. Per room, per phase

Do the whole procedure in one session. If the app stops or you must leave, start a new session for the same room and say so in the notes; the pipeline joins them through the markers.

1. In the app: project, room, phase. Check the expected marker IDs. Start capture.
2. Wait for the status to read tracking OK. If it stays limited, see section 6.
3. Stand in the doorway facing into the room, phone at chest height, dated sheet in view. Press REC.
4. Mark landmark: tap the floor at the centre of the door threshold and label it `door D3 threshold`, using the door number from the plan. Thresholds and corners drive the plan alignment, so tap the actual floor point, not the wall.
5. Slow sweep: turn through the room at chest height, about ten seconds per quarter turn, walls 1.5 to 3 m away. Then walk the perimeter slowly, phone on the wall you are passing, tilting floor to ceiling about once per stud bay.
6. At each room corner, tap the floor at the corner and label it `corner NW`, `corner NE`, `corner SE` or `corner SW` by the plan's north. Extra corners in an L-shaped room are `corner NW2` and so on. Use the same labels in every phase.
7. Each wall square-on: stand back so the wall fits floor to ceiling, tape hooked on a stud or plate and extended across the frame. Take a Still. Long walls get overlapping stills every 1.5 m. Shoot from the same spot and height in every phase so phases compare.
8. Detail stills: one Still of every box, pipe penetration, gas line and fitting, header, blocking, duct and register, from about 1 m, square-on, then one from an angle that shows where it sits in the wall. Anything you would want to find with a drill later gets a still.
9. Marker stills: each marker in the room, square-on, from about 1 m, filling a good part of the frame. Wait for the HUD marker count to rise before moving on.
10. One slow pass looking up (joists, ducts, wire runs) and one looking down (subfloor penetrations, drains).
11. Walk back to the doorway, point at the same view as at the start, hold for three seconds, press STOP. Wait for finalizing to finish.
12. Session review: check the flags. If one is red (fewer than two markers, limited tracking over 20%, loop not closed), re-shoot now; a second visit costs far more. Add notes about anything unusual.

Move slowly throughout. Fast turns, or walking while turning, cause excessive motion and lost keyframes. Do not point at a blank surface for long; bare drywall or one flat wall gives the tracker nothing to hold.

## 3. Landmark labels

| What | Label shown | Where to tap |
|---|---|---|
| Room corner | `corner NW` (NE, SE, SW; NW2 for extra corners) | Floor, at the inside corner |
| Door threshold | `door D3 threshold` | Floor, centre of the opening |
| Window | `window W2 sill` (optional) | Sill centre |
| Stair | `stair top nosing`, `stair bottom nosing` | Nosing centre; ties levels together |

The app stores these as `corner-nw`, `door-d3` and so on (see `docs/session-format.md`). Use the plan's door and window numbers. If the plan has none, number them clockwise from the main entrance and write the numbers on the plan.

## 4. Phase checklists

Every phase: markers, thresholds, corners, walls square-on with the tape, dated sheet, loop closed.

| Phase | Stills required | Notes |
|---|---|---|
| framing | Every header, king and jack studs at openings, blocking, fire blocking, stair framing, top plates, anchor bolts, hold-downs, any odd stud spacing | Feature-rich, tracking is easiest here. Hang top plate and jamb markers now. |
| electrical | Every box with its cable count, panel with the cover off, home-run routes, nail plates, low-voltage runs, smoke and CO locations, exterior penetrations | Cable jacket colour identifies gauge; keep the tape across the box height. |
| plumbing | Every supply run and manifold, drain and vent, cleanout, shutoff, water heater and softener connection, hose bib, tub and shower valve; the gas line with every fitting and shutoff | Gas joints get stills from two angles. |
| hvac | Every duct trunk and branch, register and return boot, line set, condensate, flue, ERV or HRV duct, thermostat wire, damper | Ducts hide wires; still the wall before and after where you can. |
| insulation | Each bay after insulation, vapour barrier seams, sealed penetrations, blocking hidden behind batts | Top plate markers may be covered; hang jamb markers now if not already. |
| drywall | Each wall before mud, screw lines (they show stud centres), access panels, repairs | Textureless, expect limited tracking: add light, slow down, keep markers and openings in view. |
| finish | Each wall finished, every outlet, switch, fixture and register, flooring seams | Last chance to tie finish to the plan: corners and thresholds must still be tapped. |

## 5. Session length and thermal rules

- Aim for 5 minutes or less; the app warns at 5 minutes and auto-stops at 10. Split a large room into two sessions that both see the same two markers.
- Drift grows with time and distance. Short sessions that end where they started align best.
- The HUD shows thermal nominal, fair, serious or critical. At serious the keyframe rate is halved; at critical the session stops. If it reaches serious, finish the wall you are on, stop, and rest the phone in shade with the screen off for five minutes. Never start on a phone that is hot from a sunny pocket.
- Below 500 MB free the session stops itself. Watch the free GB figure on the HUD.

## 6. Tracking limited: recovery

| Reason on HUD | Cause | Fix |
|---|---|---|
| excessive motion | Turning or walking too fast | Stop, hold still two seconds, continue at half speed |
| insufficient features | Blank wall, bare drywall, one flat surface too close | Step back, aim at edges: studs, openings, boxes, markers |
| low light | Basement, closed room, dusk | Add a work light; the phone flash does not help |
| initializing | Session just started or resumed after an interruption | Hold still, then pan slowly until OK |

Keyframes are not saved while limited, so a wall filmed in that state is missing. If limited lasted more than a few seconds on a wall, do that wall again once tracking reads OK. If tracking never recovers, stop, review, and start a new session from the doorway.

## 7. After the visit

1. Same day: copy every session folder from Files (On My iPhone, Igloo, sessions) to the PC over the SMB share or by USB with the Apple Devices app. Details in `docs/owner-setup.md`.
2. On the PC run `igloo ingest <folder>` then `igloo validate <session>`. Fix or re-shoot anything it reports.
3. Run `igloo apriltag <session>` and confirm every expected marker was found.
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

- [ ] Copy to PC, `igloo ingest`, `igloo validate`
- [ ] `igloo apriltag`; all expected markers found
- [ ] Mark transferred; update marker log
