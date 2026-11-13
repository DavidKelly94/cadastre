# Next steps after the rehearsal

Written 2026-11-13, at the owner's request, **before** any of items 3 to 5 is
built: "let's create the plan and ADRs before we start execution, because I
may run against my token limits". Each item below is sized so that a session
starting cold can pick it up from this page, the ADR it names and
`docs/status.md`. Nothing here is a record of work done; `docs/status.md` is.

The owner accepted all five ADRs later the same day, after changing
ADR-0034: the phone proposes corner marks and the owner confirms them, every
proposal can be overridden by hand, and ceiling corners count. The detail for
items 3 and 4 is in `docs/design/capture-guidance-design.md`, which also sets
the order they are built in.

## Where things stand

- A level sets itself up from the architect's PDF (ADR-0032), on the phone.
- A guided capture is placed on the plan before leaving the room (ADR-0031).
- The PC takes the capture, adopts the placement and draws the level's page,
  with no command typed. Rehearsed end to end at home on 2026-11-13: 7 cm.
- Not yet done on site: any capture in the real house. Framing starts the
  week of 2026-11-16.

## Order

| # | Item | ADR | Before framing? |
|---|---|---|---|
| 0 | American spelling | none | no |
| 1 | A floor number for a level made from a plan | none | yes, before the basement is added |
| 2 | Projects: make, name, delete | [0033](adr/0033-projects-are-made-named-and-removed-in-the-app.md) | useful, not required |
| 3 | Proposed corner marks, confirmed by the owner | [0034](adr/0034-placement-from-the-scan-taps-as-the-fallback.md) | no: taps already place a capture |
| 4 | A capture complete enough for 3D | [0035](adr/0035-a-capture-complete-enough-for-3d.md) | **yes if possible**: it changes what is recorded |
| 5a | 3D on the PC, stage one | [0036](adr/0036-3d-on-the-pc-in-stages-opened-from-the-phone.md) | no |
| 5b | Exterior | [0037](adr/0037-the-exterior-is-captured-one-face-at-a-time.md) | no, unless sheathing goes on first |

Only item 4 changes what a framing capture contains. If it cannot be built
in time, the owner can follow its pattern by hand: around the room along the
walls facing inward, then the middle, then again with the phone raised.

## 0. American spelling

The owner asked on 2026-11-13 to drop British spellings. `AGENTS.md` now says
so for everything new, and the text the owner reads on the phone and in the
PC's output was converted with the move to feet and inches the same day (see
`docs/status.md`). Comments and older documents are converted when they are
next edited. Names fixed by the format stay: `metres_per_pixel` and its relatives
are a contract (rule 2), and renaming them is a format version decision
nobody has asked for.

## 1. A floor number for a level made from a plan

**Why.** Every level has a number that orders the floors: 0 for the ground
floor, -1 for a basement, 1 for the floor above. The app asks for it when a
level is created through *New room*. *Add a level from a plan* does not ask,
and writes 0, because the plan file has nowhere to keep it. The real house
has a basement; its captures would all say 0, and a capture's manifest is
never edited afterwards.

**What it changes.** Two optional fields in `plans/<level>.json`, `name` and
`index`, described in `docs/session-format.md` section 13; readers that do
not know them ignore them, so the format version stays. *Add a level from a
plan* asks for the name and the floor number together. The pipeline already
writes back fields it does not model.

**Verified by.** A core test that a plan file round-trips the two fields and
that a level made from a plan carries its number into a capture's manifest;
a pipeline test that `plan calibrate` keeps them.

**Done 2026-11-13**, on the owner's yes that day. See `docs/status.md`.

## 2. Projects (ADR-0033)

Steps, each its own pull request:

1. Pipeline: move plans, alignments, marker maps and pages under the project,
   with a migration that is safe to run twice. Every test that builds a store
   moves with it.
2. Format: `project.json`, optional, in section 13.
3. Core: a project list read from the folders on disk; create, rename,
   delete, with the count of captures the PC has not confirmed.
4. App: the list as the first screen; the capture coordinator takes its
   project from it and stops naming one itself
   (`CaptureCoordinator.projectSlug`).
5. `vividhome project delete` on the PC.

**Verified by.** Linux tests for 1 to 3; the owner makes a "Rehearsal"
project, moves nothing, and deletes it.

The rehearsal level beside the main floor is deleted by hand by the owner,
not migrated.

## 3 and 4. Capture guidance (ADR-0034, ADR-0035)

Built in the order of `docs/design/capture-guidance-design.md` section 5:
the completeness measure and its screen first, because they change what a
framing capture contains; then the corner finder, the proposed marks with
their override, ceiling taps, and wall height. Seven pull requests, each
leaving the app working.

The first framing captures are made with taps, as today. They are the
evidence the corner finder is tuned against.

## 5a. 3D on the PC, stage one (ADR-0036)

**Stage one built 2026-11-13**; see `docs/status.md`. Steps 1 to 3 below are
done, with the link on the level page standing in for a change to the app.

1. `vividhome model --level <level>`: each placed capture's `mesh.obj` moved
   into house coordinates, written as one file per level under the project.
2. A viewer page beside the level page, with its library served by the PC.
3. The phone's *Rendering on the PC* offers it.
4. Stages two and three are planned when stage one has been looked at.

## 5b. Exterior (ADR-0037)

1. The drawing reader proposes the building's outer line.
2. A face is a room whose outline is one stretch of that line.
3. Guidance by photographed length. Tried first on the owner's current
   house, as the room rehearsal was.

## What the owner decides

Nothing is waiting on the owner. The rehearsal level is theirs to delete by
hand (answered 2026-11-13), so the migration in item 2 moves nothing.
