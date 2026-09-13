# Cadastre — design canvas brief

**Self-contained. Paste this whole file into Claude Design.** It assumes no
access to this repository and repeats everything needed rather than linking.
Derived from `docs/ui/design-brief.md`, which stays the project's own record;
this is the handoff.

---

## 1. What the product is

Cadastre records a building **while it is under construction**, so the studs,
wires, pipes, gas lines and ducts hidden by finished surfaces stay findable
years later. A LiDAR iPhone walks each room once per site visit, capturing posed
colour frames, depth, high-resolution stills, tapped room landmarks and printed
marker sightings. A pipeline on a PC aligns every capture to the architectural
floor plan. A viewer later puts all of it on the plan, phase by phase.

The app being designed is **only the capture half**: the thing held in one hand
in an unfinished building.

## 2. Who uses it, and where

One person — the homeowner — walking their own house during construction.

This is the whole spine of the design, so take it literally:

- **Standing on a job site**, not at a desk. Plywood underfoot, extension cords,
  no furniture, sometimes no floor.
- **Held one-handed at arm's length**, right hand, while the other hand steadies
  or holds a tape measure. Bare hands — gloves were considered and ruled out.
- **Two lighting extremes.** Framing and roofing happen in daylight so bright the
  screen washes out. Electrical, plumbing and HVAC rough-in happen in basements
  and closed interiors with no glazing and often no lighting at all. Both are
  normal. Neither is an edge case.
- **Under time pressure and slightly awkward** — a capture takes 2 to 5 minutes
  of continuous slow walking, and stopping to read the screen breaks the capture.
- **Recording is destructive of time, not data.** A botched capture means walking
  the room again. The interface's job is to make that not happen.

## 3. Device and canvas

- iPhone 15 Pro, **portrait only**, 393 × 852 pt.
- iOS 17 minimum. Native SwiftUI — use Apple's components and metrics; this is
  not a place for a bespoke design system.
- Dynamic Type must work. Nothing may depend on text staying one size.
- Standard 44 pt minimum touch target.

## 4. Decisions already made — please do not reopen

These were settled by the owner. Design to them.

| | |
|---|---|
| **Motif** | The cadastral plat — a ruled grid of parcels, each a record. Rooms are parcels; they fill in as phases are captured. The brand and the app's main screen then show the same thing. |
| **Phase colour** | **None.** A parcel fills in fixed phase order; the phase is read from position plus label. Green/amber/red stay purely semantic — tracking, warnings, errors. A colour on screen never means a category. |
| **Coverage chips** | Fixed order, never reordering. A completed chip collapses to a narrow tick, so remaining work compresses leftward without anything moving under the thumb. |
| **Handedness** | Right-handed primary. No mirrored variant needed. |
| **Touch targets** | Standard 44 pt. No glove mode. |
| **Landmark labels** | Pre-armed and contextual — see §6. |
| **Themes** | Both light and dark, full palettes. |

## 5. Tokens

Both palettes are verified against WCAG 2.1. Ratios below are computed, not
estimated. **Three values in the light palette were found failing and are
corrected here** — they are marked ⚠ and the original is shown.

### Light

| Role | Value | Use | Contrast |
|---|---|---|---|
| surface/ground | `#F4F8FB` | Screen background | — |
| surface/raised | `#FFFFFF` | Cards, sheets | — |
| surface/outline | ⚠ `#78899A` | **Card boundaries.** Was `#C9D6E2`, which is 1.38:1 on ground — effectively invisible, and gone entirely in sun. The design leans on ruled cards rather than shadows, so this boundary carries information and needs 3:1. | 3.37 |
| surface/divider | `#C9D6E2` | Decorative rules *inside* a card only, where nothing depends on seeing them | 1.38 |
| ink/primary | `#0F1E2E` | Body text, icons | 15.8 |
| ink/secondary | `#4A5A6A` | Secondary text | 6.64 |
| accent-cool/500 | `#2E7FD0` | Selection, active chips, **large text only** | 4.15 |
| accent-cool/700 | `#1D5C9E` | Links and small blue text | 6.83 |
| accent-cool/100 | `#D6E8F8` | Tints, selected rows | — |
| accent-warm/500 | `#D9480F` | REC, primary buttons. White text on this is 4.30:1 — **large text only** (≥18.66 pt bold). Never small white text on it. | 4.30 |
| accent-warm/300 | `#FF7A3D` | Recording pulse, glow | — |
| status/ok | `#1E9E5A` | Tracking normal | 3.23 |
| status/warn | ⚠ `#B87D06` | Warnings **on light grounds**. Was `#F2B01E` at 1.79:1 — amber on near-white is invisible. | 3.29 |
| status/error | `#D3323C` | Errors, auto-stop | 4.58 |

### Dark

Derived from the light palette by inverting the ink/surface relationship while
keeping the same hue family. Two roles deliberately **flip**, noted below.

| Role | Value | Use | Contrast |
|---|---|---|---|
| surface/ground | `#0E151C` | Screen background | — |
| surface/raised | `#18222D` | Cards, sheets | — |
| surface/outline | `#526B80` | Card boundaries | 3.30 |
| ink/primary | `#E6EEF6` | Body text, icons | 15.7 |
| ink/secondary | `#A2B4C4` | Secondary text | 8.63 |
| accent-cool/500 | `#5AA3E8` | Selection, active chips | 6.00 |
| accent-cool/700 | `#8CC4F7` | **Flips lighter.** On light it was the darker blue for small text; on dark, small text needs the lighter one. | 8.70 |
| accent-cool/100 | `#17324B` | Tints, selected rows | — |
| accent-warm/500 | `#E85D22` | REC, primary buttons | — |
| — its label | `#0E151C` | **Flips to dark text.** On a dark ground the accent must be *brighter* than the surface to find the eye, so the label on it goes dark. | 5.27 |
| accent-warm/300 | `#FF8A4D` | Recording pulse, glow | — |
| status/ok | `#43D17C` | Tracking normal | 9.32 |
| status/warn | `#FFC24D` | Warnings | 11.4 |
| status/error | `#FF5A5F` | Errors | 6.02 |

### HUD overlay (both themes)

The camera view is always the background, so the HUD has its own scrim rather
than using either palette's surfaces.

| Role | Value |
|---|---|
| hud/scrim | `#0A121C` at 72%, rising to 88% when the scene under the strip is bright |
| hud/hairline | `#FFFFFF` at 12% |
| hud text | `#FFFFFF`, 18.8:1 on the 88% scrim |
| hud status | ok `#43D17C` · warn `#FFC24D` · error `#FF5A5F` |

### Type, spacing, shape

- **Type:** SF Pro via Dynamic Type. Large Title 34, Title 1 28, Title 2 22,
  Headline 17 semibold, Body 17, Subhead 15, Footnote 13, Caption 12. HUD
  numbers use **monospaced digits**, 15–17 pt semibold, never below 13 pt.
- **Spacing:** 4 pt grid — 4, 8, 12, 16, 24, 32, 48. Screen gutter 16. Card
  padding 16. Chip padding 8 × 12.
- **Radius:** chips 10, buttons 14, cards 16, sheets 24. REC/STOP is circular.
- **Elevation:** cards flat with a 1 pt outline; sheets 0 6 20 at 12% ink. **The
  HUD has no shadows at all** — scrim and hairline only.

## 6. What to draw, in priority order

### Priority 1 — the Capture HUD and its seven states

This is the only screen with real-time constraints and the only one where a
design mistake costs a re-capture rather than a tap. If nothing else gets drawn,
draw this.

```
 393 × 852 pt, portrait
┌─────────────────────────────────────────┐
│ ● OK      04:12    KF 1204    DROP 3    │ status strip: scrim, two rows,
│ 41 GB free   THERMAL nominal   MRK 2    │ monospaced digits, 13–15 pt
├─────────────────────────────────────────┤
│ ✓ Doorway  Corners 2/4  ✓N  E wall    > │ coverage chips, fixed order,
│                                         │ done ones collapse to a tick
│                                         │
│                                         │
│              (camera view)              │ ← the centre 60% is NEVER
│           ○ landmark ring               │   covered by control or text
│                                         │
│                                         │
│                                         │
│  ! Limited: excessive motion. Slower.   │ transient hint, only when needed
├─────────────────────────────────────────┤
│ [NW*] [NE] [SE] [SW] [door] [window]    │ pre-armed landmark chips, 44 pt
│ Kitchen · Electrical + Plumbing  [mesh] │ label 15 pt, mesh toggle 44 pt
│                                         │
│   [ Still ]     (  REC  )    [ Mark ]   │ Still 64, REC/STOP 88, Mark 64
└─────────────────────────────────────────┘
 Right thumb comfort zone: bottom 260 pt, within ~75 mm of the bottom-right
 corner. REC centre, Mark bottom-right (most frequent), Still bottom-left.
```

**The landmark chip strip** is the interaction to get right — it is used more
than anything else on the screen. Tapping a chip *arms* it; tapping the camera
view then places a labelled ring at that surface. The armed chip auto-advances,
so four corners is four taps with no menu and nothing covering the view. The
strip starts as the four corners and swaps once to openings (door, window,
floor, other) when Corners reaches 4/4. A chip to swap back is always present.
Six chips must fit one 44 pt row at 393 pt wide without scrolling.

**The seven states**, each its own artboard:

1. **initializing** — camera visible, strip dimmed, "Starting tracking, move the
   phone slowly", REC disabled.
2. **tracking normal** — green dot, OK, REC enabled, chips active.
3. **tracking limited** — amber dot with one reason and one short hint:
   excessive motion → "Slower"; insufficient features → "Aim at studs and
   edges"; low light → "More light"; relocalizing → "Hold still". Keyframes are
   not kept while limited, so the KF counter shows a pause glyph.
4. **recording** — REC becomes a large STOP in the same position, elapsed runs,
   ember pulse ring, haptic on start.
5. **paused** — after a call or backgrounding. "Paused", elapsed frozen, Resume
   and Stop.
6. **finalizing** — full-width non-dismissible sheet, "Finalizing: writing
   frames, exporting mesh", progress bar and counts.
7. **error** — red card naming the cause (storage below 500 MB, thermal
   critical, camera unavailable, tracking never started), with "Review what was
   saved" and "Back to room". An automatic stop is never silent.

Plus two variants: the **5-minute warning** (amber chip "5 min, wrap up", with a
haptic) and **thermal serious** ("Hot: keyframe rate halved").

Draw all seven in **both themes**, or draw them in light and provide one dark
state sheet showing which tokens change.

**Success test:** every strip value readable at arm's length in sun; STOP found
by thumb without looking; the camera centre never covered; no state needing more
than one line of text.

### Priority 2 — the nine other screens

Conventional SwiftUI lists and forms. One artboard each, plus empty and error
states where they exist.

1. **Onboarding** — build label, LiDAR capability check, permission request. Must
   show a clear wall if the phone is unsupported.
2. **Project list** — parcels motif, empty state with the faint ruled texture.
3. **Project overview** — rooms drawn as parcels, filled in proportion to phases
   captured.
4. **Level view** — rooms on a level.
5. **Room detail / RoomPicker** — level, room, **phases as multi-select chips
   defaulting to the room's last pass**, notes, expected marker IDs, Start.
6. **Session review** — stats, trajectory sketch, "Open in Files", delete.
7. **Markers** — the CD-000…CD-059 list with seen counts.
8. **Settings** — thresholds, JPEG quality, 30/60 fps, theme.
9. **Test plan** — renders a bundled per-build checklist.

A note on **phases**: a single capture routinely covers several trades at once —
electrical and plumbing are often open in the same wall. The UI must treat
multiple phases per session as the normal case, not an exception.

## 7. Marks and icon — yes, this is needed

Three related marks, all from the same motif:

1. **App icon, 1024 × 1024.** A ruled parcel grid with the surveyor's
   **triangle-and-dot benchmark** over it. Ink-blue rules on near-white. The warm
   accent does **not** appear on the icon — it is reserved for actions.
   Constraints: iOS masks it to a rounded rectangle, so no transparency and
   nothing important near the corners; it must still read at **60 pt** on a home
   screen and **29 pt** in Settings. Provide a light and a dark tinted variant.
2. **Progress glyph, 24 pt.** The same grid partly filled, used in list rows to
   show how much of a room is recorded. At 24 pt it can only be a small ruled
   square with some cells inked — the count beside it carries the precision. This
   is a distinct drawing from the icon, not a scaled-down copy.
3. **Wordmark.** "Cadastre", set in the type family above. Needed only if there
   is ever a landing page; not required for the app. If drawn, note that the
   store name is **"Cadastre: Building Record"** — bare "Cadastre" is taken.

Pronounced *kuh-DASS-ter*. Never abbreviate it to "CAD" — that is a live word in
this industry and the collision is bad.

## 8. What to report back with

1. The canvas itself, artboards named by screen and state.
2. Anything in §5 you had to change to make a screen work, and why.
3. **The two tests I cannot run.** These are the real open questions: does the
   light palette hold up on a device in direct sun at full brightness, and does
   the dark palette avoid glare in an unlit basement at night? Both need a phone,
   not a monitor. Flag anything you suspect will fail.
4. Whether six landmark chips actually fit one 44 pt row at 393 pt, and if not,
   which labels earn a place and which move behind a "more" chip.

## 9. Out of scope

No AR x-ray, no 3D viewer, no accounts, no sharing, no Android, no web surfaces
beyond the four already specified. No marketing site. The app is a recorder; it
is not trying to be a viewer as well.
