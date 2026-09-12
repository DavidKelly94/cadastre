# ADR-0008: Offline processing on the owner's PC

## Status

Accepted, 2026-09-11.

## Context

The owner has a Windows PC with an RTX 4070 Super (12 GB) and no Mac. The scope is a personal tool first, with no accounts or cloud in the MVP. Everything beyond capture is heavy: TSDF fusion, a pose graph, Gaussian splats (Splatfacto trains 30k iterations in 8-12 minutes on a 4090 and 25-30 minutes on a 3060 at about 6 GB VRAM, so 15-20 minutes per room here, https://docs.nerf.studio/nerfology/methods/splat.html), segmentation and vision models. The phone is thermally limited to sessions under 10 minutes and its mesh is "not intended to reflect in real time", so on-device processing would compete with capture.

## Decision

The phone only records. All processing runs offline on the PC through the `igloo` CLI (Python 3.12, `uv`; `ingest`, `validate`, `apriltag`, `plan add`, `plan calibrate`, `align`, `inspect`, `markers`), with local pages served by `python -m http.server` for calibration, alignment and inspection. Sessions reach the PC through the Files app (SMB share or USB with the Apple Devices app); LAN upload is a day-13 stretch. Raw sessions are the archive and are never modified; every output under `derived/` is reproducible. No server, no accounts, no telemetry.

## Consequences

Positive:

- A 12 GB GPU and unlimited time for free; algorithms can be rerun on old captures whenever they improve.
- Photos of the owner's house never leave owner hardware.
- Nothing to host or secure; the pipeline is testable on Linux CI with `opencv-python-headless` and synthetic sessions.

Negative:

- A manual transfer and `validate` step after every site visit.
- Windows friction: `uv` solves Python, but CUDA tools such as nerfstudio in weeks 3+ may be easier under WSL2.
- No feedback on site beyond in-app statistics; capture coaching is a roadmap item.
- Backups are the owner's job: the PC copy plus one external copy.

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| On-device reconstruction (RoomPlan, Object Capture, Scaniverse) | Thermal limits, idealised walls, no cross-phase frame. |
| Cloud GPU or vendor cloud (Polycam Business $400/yr, Matterport Pro about $69/month) | Recurring cost, multi-gigabyte uploads, lock-in; may still be used ad hoc for a big splat batch. |
| Home server with a web app | Over-engineering for one user; static pages suffice. |
| Processing on a Mac | There is no Mac. |
