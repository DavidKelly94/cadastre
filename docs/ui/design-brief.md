# VividHome design brief

Handoff for Claude Design. This document is self-contained: it carries every fact needed to design the app without access to the rest of the repository. Behaviour follows the approved project plan of 2026-09-11; where the plan is silent, this brief makes a proposal and says so.

## 1. Product

VividHome (bundle ID `ai.vividhome.app`, repository `DavidKelly94/cadastre`) is an iPhone app that records a building while it is under construction, so the structure and services hidden by finished surfaces stay findable afterwards: studs, wires, pipes, gas lines, ducts. On an iPhone 15 Pro or newer (LiDAR required, iOS 17 minimum) it uses ARKit to record posed colour frames, LiDAR depth, high-resolution stills, tapped landmarks and printed-marker sightings into an open session folder, one session per room per construction phase. A pipeline on the owner's PC aligns sessions to the architectural plan and later builds a 3D viewer. No accounts, no cloud; sessions are plain folders visible in the Files app.

The product is broader than that first release. It is a queryable record of a building spanning construction and ownership: inspecting work as it happens and comparing phases matter as much as the later search behind a finished surface, the captured photos and panoramas are an answer surface rather than only texture for a model, and the long-term direction is coordination with builders and clients, with markup as a major feature. Design the shell so those fit, but do not design them yet; the screens below are the ones being built.

A note on the name, because it shapes the visuals. A *vividhome* is the authoritative register of what exists on a parcel of land: who holds it, where the boundaries run, what stands on it. The product borrows that idea and applies it to a building rather than to land. Pronounced "kuh-DASS-ter". Because the word is unfamiliar to most people, the wordmark should always appear with its line on first touch, something in the spirit of "the permanent register of your building", and the product is never abbreviated to "CAD", which already means something else in this industry.

Users and setting. The first user is the owner, standing in a house under construction: dust, bright sun through unglazed openings, dim basements, compressor and saw noise, debris underfoot. The phone is held up at chest height, usually one-handed, sometimes in a work glove; the other hand may hold a tape measure. Attention is split between screen and floor. Later users are other homeowners and small builders doing the same job with less patience for setup.

## 2. Visual theme (proposal)

> **⚠ The motif below is orphaned and must be replaced.** It was derived from the
> meaning of the word *cadastre* — the register of what exists on a parcel — so rooms
> drawn as parcels, the ruled-grid icon and the survey benchmark all rested on a name
> the product no longer has ([ADR-0024](../adr/0024-name-vividhome.md)). The argument
> that "the brand and the product's main screen agree" no longer holds. Everything
> else here stands: the tokens, type scale, spacing and contrast ratios were verified
> numerically and are unaffected. Only the motif and the icon direction in §10.8 need
> rethinking, and any design canvas seeded from the old brief needs re-seeding.


The brand has no established visual identity, so this section is a starting point the designer may change. Keep the contrast requirements in sections 7 and 8.

Motif: **the register itself**. A cadastral plat divides ground into bounded parcels, each one a cell with a record behind it. Here the parcels are rooms on a level, and each carries its record of phases, photos and marks. That gives the app icon (a small ruled parcel grid, a few cells, one filled), the project overview (rooms drawn as parcels, filled in proportion to phase coverage), and a quiet texture for empty states (faint ruled parcel lines). The motif has a real advantage over an arbitrary one: it is already what the plan view looks like, so the brand and the product's main screen agree instead of competing.

Phases are the second dimension of that grid. A parcel filling in as framing, electrical, plumbing and the rest are captured reads as a record being completed, which is exactly what is happening.

Surfaces: near-white paper grounds and a single cool ink-blue, with one warm accent reserved for record and primary actions so the eye always finds the one thing to press. The reference is a survey drawing rather than a consumer app: ruled, precise, quiet, with ink on paper as the dominant relationship. High contrast for direct sun: dark text on near-white cards, no light grey on white, visible outlines. Cards are ruled rectangles with a hairline border rather than soft floating shapes. Status colours (green, amber, red) are semantic: dots, icons and chip tints only; text on light surfaces stays ink.

Starter tokens. Every ratio below was computed against WCAG 2.1 rather than
estimated, and three values were corrected when that measurement was first run on 2026-09-13; the dark palette lives in
[design-canvas-brief.md](design-canvas-brief.md) §5.

Starter tokens:

| Role | Value | Use |
|---|---|---|
| surface/ground | #F4F8FB | Screen background |
| surface/raised | #FFFFFF | Cards, sheets |
| surface/outline | **#78899A** | Card boundaries. Was `#C9D6E2`, measured at 1.38:1 on the ground — below the 3:1 that a boundary carrying information needs, and invisible in sun |
| surface/divider | #C9D6E2 | Decorative rules inside a card only, where nothing depends on seeing them |
| ink/primary | #0F1E2E | Body text, icons |
| ink/secondary | #4A5A6A | Secondary text (6.6:1 on surface/ground) |
| accent-cool/500 | #2E7FD0 | Brand ink-blue: selection, active chips, large text only |
| accent-cool/700 | #1D5C9E | Links and small blue text (6.8:1 on white) |
| accent-cool/100 | #D6E8F8 | Tints, selected rows |
| accent-warm/500 | #D9480F | REC, primary buttons. White on it measures 4.30:1, which passes for large text (>=18.66 pt bold) and fails for normal text — never small white text on this |
| accent-warm/300 | #FF7A3D | Recording pulse, glow |
| status/ok | #1E9E5A, HUD #43D17C | Tracking normal |
| status/warn | **#B87D06** on light, HUD #FFC24D | Tracking limited, 5-minute warning, thermal serious. #F2B01E measured 1.79:1 on the ground — amber on near-white is invisible; it survives only on the HUD scrim |
| status/error | #D3323C, HUD #FF5A5F | Errors, auto-stop |
| hud/scrim | #0A121C at 72% | Translucent strips over the camera; rises to 88% when the scene under the strip is bright |
| hud/hairline | #FFFFFF at 12% | Strip edges |

Type: SF Pro (system font) through Dynamic Type styles: Large Title 34, Title 1 28, Title 2 22, Headline 17 semibold, Body 17, Subhead 15, Footnote 13, Caption 12. HUD numbers use monospaced digits, 15 to 17 pt semibold, white on scrim, never below 13 pt.

Spacing: 4-pt grid, steps 4, 8, 12, 16, 24, 32, 48; screen gutter 16; card padding 16; chip padding 8 by 12. Radius: chips 10, buttons 14, cards 16, sheets 24; REC/STOP is circular. Elevation: cards flat with a 1-pt outline and a 0 2 8 shadow at 8% ink; sheets 0 6 20 at 12%; the HUD has no shadows, only scrim and hairline.

## 3. Information architecture

```
Projects
  Project (name, address, created)
    Levels (L1, L2, basement, garage; height in m)
      Rooms (name, expected marker IDs, notes)
        Sessions (one per room per capture pass)
Markers (VH-000 to VH-059)
Settings
Test plan
```

Phases in order: framing, electrical, plumbing, hvac, insulation, drywall, finish, other. **A session carries a set of phases, not one** ([ADR-0022](../adr/0022-session-is-one-pass-carrying-phases.md)): concurrent rough-in is normal, so one pass often covers electrical and plumbing together. A room may also have several sessions covering the same phase (re-shoots). A session folder is named `<YYYYMMDD-HHMMSS>_<level>_<room>_<id6>` — the phases are in the manifest, not the folder name, because they can be corrected after the capture.

Navigation is a single NavigationStack, no tab bar in the MVP. Markers and Settings are toolbar items on the Project list; Test plan is reached from Settings and from the build label on Onboarding.

## 4. Screens

Each screen lists purpose, primary action, content, states and success criteria. Code names in parentheses.

### Onboarding

Purpose: confirm the phone can capture and teach the protocol in under a minute.
Primary action: Continue, then Create first project.
Content: three gates, then three cards. Gates: LiDAR and ARKit support (hard stop with a plain message on unsupported phones), camera permission (explain why before the system prompt), free storage. Cards: "One room, one session, start at the door"; "Tap corners and door thresholds, walk slowly"; "Two markers in every room, a still of everything you will want to find later". Build label and Test plan link at the bottom.
States: checking, unsupported device, permission denied (with Open Settings), ready.
Success: a supported phone reaches the Project list in under 60 s; an unsupported phone gets a reason, not a crash.

### Project list and empty state (ProjectPicker)

Purpose: pick or create a project.
Primary action: New project.
Content: one card per project: name, rooms captured out of total, last session date, storage used, a small vividhome of completed phase courses. Empty state: an outline vividhome with one block, "No projects yet", New project, a link to the protocol.
States: empty, populated.
Success: one tap opens the current project; the empty state explains what a project is.

### Project overview

Purpose: what has been captured in which phase, and what still needs transferring.
Primary action: Capture (opens the last room used, or Room detail).
Content: rooms by phases coverage grid grouped by level (dot: none, captured, transferred), storage used and free, sessions not yet transferred, Add level, Add room.
States: no rooms, partial coverage, storage low (below 2 GB free, capture disabled with a message), all transferred.
Success: "which rooms still need an electrical session?" is answered without scrolling.

### Level view

Purpose: the rooms of one level and the shared markers at its stairs.
Primary action: Add room, or Capture on a room row.
Content: level name and height, room rows with phase coverage blocks, expected markers per room, shared stair-landing markers. The MVP app does not show the plan raster; plans live on the PC.
States: empty level, populated.
Success: adding a room is one screen; coverage rows wrap rather than truncate at accessibility text sizes.

### Room detail (RoomPicker)

Purpose: prepare a session for this room and phase.
Primary action: Start capture (ember).
Content: phase picker (eight phases as block chips); sessions grouped by phase with date, duration, keyframes, quality flags and transferred state; expected marker IDs as chips from the Markers list; notes; the phase checklist that will appear on the HUD.
States: no sessions, sessions present, expected markers missing (warn, allow), storage refused (below 2 GB), phase already captured (allow a re-shoot with a note).
Success: room, phase and markers chosen in under 15 s with one hand.

### Capture HUD (CaptureView)

Purpose: record one room while showing only what affects the result.
Primary action: REC, which becomes STOP in the same position while recording.
Content. Top status strip: tracking quality with reason, elapsed, keyframes kept, dropped frames, free GB, thermal state, markers seen (count; IDs on tap). Coverage chip strip: the phase checklist as chips (Doorway, Corners 0/4, N wall, E wall, S wall, W wall, Stills, Markers 0/2, Loop), ticked automatically where the app can tell and by tap otherwise. Bottom bar: Still, REC/STOP, Mark landmark, mesh toggle (live LiDAR mesh wireframe as a coverage aid, off by default), room and phase label. Mark landmark uses a **pre-armed, contextual label** (§10.7): a chip strip above the bottom bar holds the vocabulary, tapping a chip arms it, and tapping the camera view places a ring at the surface already labelled. The armed chip auto-advances, and the strip itself swaps from the four corners to the openings once Corners reads 4/4. Four corners is four taps, no sheet ever covers the camera, and the row never scrolls. An Undo chip stays for 5 s.

```
 iPhone 15 Pro portrait, 393 x 852 pt
+-----------------------------------------+
| * OK      04:12   KF 1204   DROP 3      |  top status strip: scrim, two rows,
| 41 GB free   THERMAL nominal   MRK 2    |  monospaced digits, 13-15 pt
+-----------------------------------------+
| Doorway/  Corners 2/4  N wall/  E wall >|  coverage chips, horizontal scroll
|                                         |
|                                         |
|                                         |
|                                         |
|                 (camera)                |  the centre 60% of the view is
|            o landmark ring              |  never covered by control or text
|                                         |
|                                         |
|                                         |
|                                         |
|  ! Limited: excessive motion. Slower.   |  transient hint, only when needed
+-----------------------------------------+
| Kitchen . Electrical            [mesh]  |  label 15 pt, mesh toggle 44 pt
|                                         |
|   [ Still ]     (  REC  )    [ Mark ]   |  Still 64 pt, REC/STOP 88 pt, Mark 64 pt
|                                         |
+-----------------------------------------+
 Thumb reach, right hand: the comfortable zone is the bottom 260 pt within
 about 75 mm of the bottom-right corner. REC/STOP at bottom centre, Mark at
 bottom right (most frequent), Still at bottom left (a stretch). The top
 strip is read-only. A left-hand setting mirrors the bar.
```

States, each drawn on the HUD state sheet:

- initializing: camera visible, strip dimmed, "Starting tracking, move the phone slowly", REC disabled.
- tracking normal: green dot and OK, REC enabled, chips active.
- tracking limited, with one reason: excessive motion, insufficient features, low light, or initializing (relocalizing after an interruption). Amber dot, the reason, a short hint (Slower; Aim at studs and edges; More light; Hold still). Keyframes are not kept while limited, so the KF counter shows a pause glyph.
- recording: REC becomes a large STOP, elapsed runs, ember pulse ring, haptic on start. At 5:00 an amber chip "5 min, wrap up" with a haptic. Thermal serious adds "Hot: keyframe rate halved".
- paused: after a phone call or backgrounding. "Paused" on the strip, elapsed frozen, Resume and Stop; resuming passes back through initializing or limited.
- finalizing with progress: full-width sheet "Finalizing: writing frames, exporting mesh" with a progress bar and counts, not dismissible, then Session review.
- error: red card naming the cause (storage below 500 MB, thermal critical, camera unavailable, tracking never started) with Review what was saved and Back to room. An automatic stop is never silent.

Success: every strip value is readable at arm's length in sun; STOP is found by thumb without looking; the camera centre is never covered; no state needs more than one line of text.

### Session review (SessionReview)

Purpose: judge the session before leaving the room, and get it onto the PC.
Primary action: Done (keep); Re-shoot is offered when a flag is red.
Content: stats (duration, keyframes, dropped, limited seconds, max thermal, size), a top-down trajectory sketch with landmark rings and marker squares, keyframe thumbnails, stills grid, markers seen (IDs, sightings), landmarks with editable labels, quality flags, notes, then Open in Files, Share (zip), Delete (confirm).
Quality flags, amber or red: fewer than 2 markers seen, expected marker not seen, no stills, limited tracking over 20%, dropped frames over 5%, loop not closed (end more than 1 m from start), under 60 s, thermal serious.
States: clean, flagged, transferred (a checkbox the owner sets after copying; a later LAN upload may set it), deleted.
Success: a flagged session is obvious within 2 s; the folder is reachable in Files in two taps.

### Markers

Purpose: which markers exist, where each hangs, and whether it is being seen.
Primary action: Add placement note (with photo).
Content: VH-000 to VH-059 with status (unused, placed, covered, lost), level, room and surface, the placement note in the fixed form "centred on door D3 threshold, 100 mm from left jamb", photo, seen in N sessions, last seen. Print instructions (100% scale, matte lamination, verify 20.0 cm with a tape). A marker preview with a warning that on-screen size is not true size.
States: none placed, placed, expected but never seen (warn).
Success: the owner can find where VH-017 should be while standing in the house.

### Settings

Purpose: tuning and diagnostics for the owner, not for later users.
Primary action: none; it is a form.
Content: keyframe thresholds (interval 100 ms, distance 0.10 m, rotation 5 degrees), JPEG quality 0.85, 30 or 60 fps (30 default, thermal note), marker physical width 20.0 cm (must match the print), health limits read-only (warn 5 min, stop 10 min, refuse start below 2 GB, stop below 500 MB), left-hand layout, haptics, sounds, reset onboarding, build label, Test plan, Open sessions folder.
States: defaults, modified (Reset to defaults visible).
Success: nothing changes by accident with a glove; risky values carry a note.

### Test plan (TestPlan)

Purpose: the owner's script for testing each TestFlight build.
Primary action: Copy results.
Content: the checklist bundled with the build as sections of items with Pass, Fail, Skip and a note; build label at the top; Copy results produces markdown for a GitHub issue.
States: untouched, partially done, complete.
Success: a full test pass is recorded one-handed and pasted in one action.

## 5. Web surfaces

Built later in the pipeline as plain HTML pages served locally, no framework. They share the token set but stay minimal.

1. Plan calibration. The plan raster (a rasterized PDF page or a photographed paper plan) fills the view. The owner clicks two points and types the real distance between them (two-point scale), drags a north arrow, and enters the level height in metres. Save writes `plans/<level>.json`; show pixels per metre and a 1 m check bar.
2. Alignment correspondence picker. Left: the session's tapped landmarks as a labelled top-down sketch. Right: the plan raster. Click a landmark, then its plan corner, to make a pair. After two pairs show the fit and the residual per pair in centimetres, highlighting residuals over 10 cm. Save writes `derived/align.json`.
3. Session inspector. Per level: the plan raster with every session's trajectory (colour by phase), marker squares with IDs, landmark rings, keyframe thumbnails on hover, and a quality report table with the Session review flags. Filters: phase, room, date.
4. 3D viewer (later). A three.js scene with the plan on the floor, a phase slider that fades between captures, click any point to open the nearest photos, two-click measurement, labels. Design the chrome only; the 3D content is data.

## 6. Key flows

First run

1. Install from TestFlight, open VividHome.
2. Onboarding: LiDAR check passes, allow camera, read the three cards.
3. New project: name. Add level L1 with its height. Add the first room.
4. Land on Project overview with an empty coverage grid.

Capture a room

1. Project overview, tap the room, Room detail.
2. Choose the phase, confirm expected marker IDs, Start capture.
3. HUD initializing, then tracking OK. Stand in the doorway.
4. REC. Haptic. Mark landmark: door threshold.
5. Slow sweeps at chest height; each wall square-on floor to ceiling; tap each corner; Still on every box, pipe, duct and header; Still of each marker from about 1 m. Chips tick.
6. Return to the doorway, STOP. Finalizing shows progress.
7. Session review opens.

Review and transfer a session

1. Read the flags. Red: re-shoot while still in the room. Amber: add a note.
2. Add notes (what changed, what to look for later).
3. Later: Open in Files, copy the session folder to the PC (SMB share, or the Apple Devices app on Windows).
4. On the PC run `vividhome ingest` then `vividhome validate`.
5. Mark the session transferred in Session review.

Place and register markers

1. On the PC run `vividhome markers`, print at 100%, laminate matte, measure 20.0 cm.
2. Hang two or more per room following `docs/markers.md`.
3. Markers screen: add a placement note and photo per ID.
4. Room detail: enter the expected IDs.
5. The first session sees them and "seen in N sessions" increments.

## 7. Platform constraints

- iOS Human Interface Guidelines; SwiftUI-native components only (List, NavigationStack, sheets, toolbars, SF Symbols). No custom navigation or tab bars.
- Dynamic Type everywhere outside the HUD; layouts wrap rather than truncate.
- Touch targets at least 44 by 44 pt; HUD buttons larger (Still and Mark 64 pt, REC/STOP 88 pt).
- The HUD is dark translucent strips over the live camera; the rest of the app is light.
- Haptics on record start, stop, still captured, landmark placed, marker first seen, 5-minute warning and auto-stop.
- Portrait only; one-handed reach for anything pressed during recording.
- Readable at maximum brightness in direct sun: at least 4.5:1 for text and 3:1 for controls, no thin weights on the HUD.
- Minimal text on the HUD: symbols with one-word labels, numbers with units.
- iPhone 15 Pro (393 by 852 pt) is the reference device; layouts must also fit Pro Max sizes.

## 8. Accessibility and safety

- Never obstruct the centre of the camera view; all chrome sits in the top and bottom bands.
- STOP is large, central and works with a glove. No long press, swipe or two-finger gesture for any capture action.
- Colour is never the only signal: status chips carry a symbol and a word.
- Thermal serious, thermal critical, the 5-minute warning, low storage and auto-stop each get a distinct haptic pattern plus an optional sound; site noise makes sound unreliable, so the haptic is primary.
- VoiceOver labels on every control; the status strip reads as one element.
- Reduce Motion disables the recording pulse.
- Landmark taps need an undo; taps on the camera view do nothing unless Mark is armed.
- The screen stays on during capture; elapsed time is always visible so a stuck session is noticed.

## 9. Deliverables

The design is a **canvas**: one pan-and-zoom board of artboards, edited in place
rather than exported and re-imported. That is what the tooling produces, and it
suits a design that is still moving.

1. One artboard per screen in §4, at iPhone 15 Pro portrait (393 by 852 pt),
   including empty and error states.
2. The seven Capture HUD states as their own artboard group, plus the 5-minute
   warning and the thermal variant. This group is the priority: it is the only
   screen with real-time constraints, and a mistake there costs a re-capture
   rather than a tap.
3. Both palettes. Every artboard that differs between light and dark gets both;
   the rest state which tokens change.
4. App icon artboard, 1024 by 1024, light and dark tinted variants.
5. Web layouts for the four surfaces in §5, 1440 pt wide.
6. `vividhome-tokens.json` generated into the repository from the agreed palette,
   with a short usage note. A token file is code rather than a design artifact,
   so it belongs in the repo and in review, not in an export folder.

PNG and PDF export on demand, for anything that has to leave the canvas.

## 10. Answered by the owner, 2026-09-13

These were open questions; they are now decisions. Anything still open is in §11.

1. **Light chrome, plus a dark theme.** Rough-in happens in unlit basements and
   closed interiors, so a near-white screen at full brightness is not usable for
   the phases this product exists to record. Two full palettes, both meeting the
   contrast requirements in §§7 and 8.
2. **No colour per phase.** A parcel fills in phase order and the phase is read
   from position plus label. Green, amber and red stay semantic — tracking,
   warnings, errors — so a colour on screen never means a category. This also
   survives a session carrying several phases at once, which per-phase hues
   would not.
3. **The progress glyph** is the parcel grid partly filled, matching the icon
   and §2's motif. At 24 pt in a list row it reads as a small ruled square with
   some cells inked; the count beside it carries the precision.
4. **Coverage chips keep a fixed order and shrink when complete.** Position
   stays stable so it can be learned, and finished work compresses to a tick
   rather than reordering the strip under the thumb mid-capture.
5. **Right-handed layout is primary.** Mark bottom-right, Still bottom-left, as
   drawn in §4. A mirrored variant is not required for the MVP.
6. **No glove mode.** Bare hands, standard 44 pt minimum targets. The capture
   bar is already oversized for the actions that matter while recording.
7. **Landmark labels are pre-armed and contextual.** A chip strip above the
   bottom bar holds the vocabulary; tapping a chip arms it, tapping the surface
   places it, and the selection auto-advances. The strip starts as the four
   corners (NW → NE → SE → SW) and swaps to openings — door, window, floor,
   other — once Corners reads 4/4, which the HUD already tracks. Four corners
   is four taps, nothing covers the camera, and six chips fit one 44 pt row on a
   393 pt screen without scrolling. The strip changes exactly once per room, at
   a moment the owner caused; a chip to swap back is always present. The label
   sheet in §4 is replaced by this.
8. **App icon: the parcel grid with a survey benchmark mark** — the ruled plat
   with the surveyor's triangle-and-dot over it. Ink-blue rules on near-white;
   the warm accent is reserved for record and primary actions and does not
   appear on the icon.

## 11. Still open

1. Does anything in the token set fail in direct sun at full brightness? Please
   test on a device, not a monitor. Nothing in this document can settle it.
2. The dark palette needs the same test in the opposite condition: an unlit
   basement at night, where the failure is glare rather than washout.
3. The pre-armed landmark chips need a vocabulary that fits one row without
   scrolling at 44 pt. If it does not fit, which labels earn a place and which
   move behind a "more" chip?
