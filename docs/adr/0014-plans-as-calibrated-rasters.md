# ADR-0014: Plans as calibrated rasters

## Status

Accepted, 2026-09-11.

## Context

The owner's plans are PDF drawings plus paper, some of which will arrive as photographs. Extracting wall geometry from these is unreliable: vector PDFs vary in drawing convention, raster parsing still leans on CubiCasa5K, a warning sign in 2026, and vision language models read architectural plans at 33-38% accuracy (ArchPlanVQA). By contrast, a human calibrating scale against a known dimension is about ten lines of code and correct; magicplan uses exactly that model ("place the scale on a known measurement"). The plan only needs to be a reference frame: as-built framing deviates 1-2 inches, the scan is the truth, and the alignment (ADR-0007) and the viewer draw on top of the plan image.

## Decision

A plan level is a raster image plus a calibration file. `igloo plan add <pdf|image> --level L1` rasterises PDF pages with pypdfium2 at 150-200 dpi (https://github.com/pypdfium2-team/pypdfium2) and applies an optional four-corner perspective correction to photographs. `igloo plan calibrate` serves a local page where the owner clicks two points, types the real dimension, and sets north and the level's floor height; the result is `plans/<level>.json` with pixels per metre, origin, rotation, floor height, source page and dpi, and the perspective corners if any. Vector walls are deferred; if they are ever extracted (pdfplumber for vector PDFs) they will be a derived layer, never the frame.

## Consequences

Positive:

- Works with every input the owner has: PDF, scan or phone photo.
- Tiny, human-readable calibration; the overlay makes an error obvious at a glance.
- The same code path for every level.

Negative:

- No wall lines to snap to or check against; automatic refinement waits.
- A corrected photograph still carries a few centimetres of distortion across a room.
- A 24x36 inch sheet at 200 dpi is 4800x7200 pixels; the viewer must downscale or tile.
- A scale error propagates to every alignment on the level; check against a second dimension string, and keep revised plans as new versioned files.

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| Vector extraction (pdfplumber, ezdxf via the ODA converter) | Only for vector inputs; conventions vary; possible later as a derived layer. |
| Learned floor-plan parsing (CubiCasa5K) | Dated and unreliable on architectural sheets. |
| Vision language model reading dimensions | 33-38% accuracy. |
| Georeferencing with GPS or compass | Useless indoors; north is set by hand for convenience only. |
| Requesting DWG or IFC from the architect | Welcome if available, not guaranteed; can be layered in later. |
