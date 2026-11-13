# ADR-0032: The drawing sets itself up

## Status

Accepted, 2026-11-13, on the owner's instruction that day ("do it for the phone first"). Extends [ADR-0014](0014-plans-as-calibrated-rasters.md), [ADR-0030](0030-the-phone-owns-the-first-loop.md) and [ADR-0031](0031-the-capture-proves-itself-before-you-leave.md): the plan's scale and the rooms' outlines keep their meaning and their fields, and gain a second way of being filled in.

## Context

Setting a level up by hand is about eighty taps: three points and a typed distance for the scale, then a pin and four to eight corners per room. The owner called it click heavy on 2026-11-12, and it is work the architect already did. A sheet exported from CAD carries its text, the printed scale, every dimension, the room names, and the walls as filled shapes. On the owner's first-floor sheet a prototype read the scale from the title block and the page size, found two lines exactly the printed length apart for 162 of 162 dimensions (a wrong scale matches about a fifth by chance), and outlined 14 of 18 rooms from their labels, because the walls are drawn continuous with the doors laid on top.

## Decision

1. **The app reads a vector PDF's own geometry.** The scale comes from the title-block note and the page size, tested against the sheet's dimensions. Rooms come from their labels; each outline is the fill from a label out to the walls.
2. **It runs on the phone and nothing is uploaded.** The geometry is in the pure-Swift core, tested on Linux. Lifting text, fills and lines out of the PDF needs Apple's frameworks; that reader is a separate target, tested on the macOS runner.
3. **What it reads is a proposal.** The owner sees it and chooses what to apply. A scale the dimensions contradict is never written, and an existing calibration is never replaced.
4. **The manual screens stay** for scans, photographs and sheets whose walls are bare lines.
5. **No new fields.** The result is the calibration and `rooms[].outline` the plan file already has.

## Consequences

Positive: a level is set up by importing its PDF and confirming; the scale rests on many dimensions instead of one pair of taps; nothing leaves the device.

Negative: it depends on how a sheet was drawn and proposes nothing on others; an open-plan space is pinned, not outlined; the PDF reader cannot be compiled or run in the agent environment.

## Alternatives considered

| Alternative | Why not |
|---|---|
| A vision model reading the sheet | Needed for scans, not for vector sheets; costs an upload and a key. Kept as the later fallback. |
| Reading it on the PC first | Faster to build, but setup is done on the phone and the owner chose the phone. |
| Detecting walls in the raster | Doors reopen every room once the sheet is flattened. |
