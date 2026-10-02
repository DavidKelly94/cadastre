# ADR-0030: The phone owns the record's first loop; the PC is the archive and the heavy compute

## Status

Accepted, 2026-10-02. Amends [ADR-0008](0008-offline-processing-on-owner-pc.md) (the phone only records) and decision 2 of [ADR-0028](0028-results-return-to-the-app.md) (rendering stays on the PC). [ADR-0029](0029-the-pc-is-reached-over-the-owners-tailnet.md) stands. Mechanics in `docs/design/phone-first-loop-design.md`; the file changes land in `docs/session-format.md` with the first implementation, additive, as ADR-0021 requires.

## Context

The first full round trip (2026-10-02) ran calibrate, align and inspect on the PC: a browser page, a browser page and a typed command, with the owner stumbling on each. What those three steps compute is small. Calibration is two taps and a printed distance. Alignment is a rigid 2D fit of two to four point pairs. Inspection is a polyline and some dots on a raster. The phone already holds the plan, the tapped corners, the poses and the photos, and has a screen. Everything heavy, meshes, splats, pose graphs across phases, AI labels, the browser viewer, is weeks away and stays on the PC, as does the PC's other job, holding the archive. The owner's own words: the PC does not feel necessary yet. ADR-0017 reserves a product for other homeowners, for whom "a PC is required" is the first thing that stops them.

## Decision

1. **The phone completes the first loop by itself.** Calibrate a level's plan, align a capture to it from the corners tapped during capture, and show the level with the walk, the corners and the photos, natively. No PC is needed to see a capture on the plan. Each step stays optional: the PC's commands remain for anyone who prefers a keyboard.
2. **The files are the contract.** The app writes the calibration into `plans/<level>.json`, whose fields §13 already defines. An alignment the phone makes is a project-level file, `alignments/<session-id>.json`, the same shape the PC writes plus `"source": "app"`, additive and `format_version` unchanged. It travels with the capture, and `ingest` adopts it when the store has none. Raw sessions do not change, and `derived/` stays the pipeline's.
3. **The maths lives in VividHomeCore,** tested on Linux; the Python stays the reference, and the contract job checks the two against each other on a fixture.
4. **The PC keeps** the archive and its backups, validation as the independent check, markers across phases, meshes, splats, AI, the browser viewer, and anything that takes more than seconds. ADR-0028's web view remains the way those come back.

## Consequences

Positive: a visit is complete on site, in the room; the PC becomes something run at home afterwards, not something the loop waits on; a product without a PC becomes possible without a second architecture.

Negative, carried knowingly: two implementations of calibrate, align and the plan projection, kept honest by shared fixtures; the phone's alignment is a first fit that the PC may later refine with markers or a pose graph, so the two can disagree until the PC's returns; precise taps on a phone need a magnifier; a phone that has not sent its captures holds the only copy for longer.

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| Keep the three steps on the PC behind nicer pages | Still needs the PC on site, which is the problem. |
| Everything on the phone, including validation and storage | The archive, the independent check and the heavy compute still want a machine with a disk and a GPU. |
| A cloud service to do the small steps | ADR-0012 and ADR-0029's reasoning: cost, an account, the house's photos leaving owner hardware, for maths a phone does in a millisecond. |
