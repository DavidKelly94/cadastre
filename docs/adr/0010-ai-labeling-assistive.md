# ADR-0010: AI labelling is assistive, never automatic

## Status

Accepted, 2026-09-11.

## Context

Labels on this data carry safety weight: mistaking a CSST gas line for a water line matters when the owner drills into a wall years later. The evidence on automatic detection of MEP elements is poor. At ISARC 2025, a fine-tuned YOLO11-nano beat the best open-vocabulary model (Grounding DINO) by more than 85 points of precision, 82 of recall and 86 of F1, and found cable-tray fittings no open-vocabulary model detected (https://arxiv.org/abs/2501.09267). Grounding DINO 1.6 Pro and SAM 3 are annotation accelerators, not production detectors. Ray-casting 2D masks through ARKit depth gives about 90% of the value of research 3D open-vocabulary methods.

## Decision

Every AI output is a candidate: stored separately from confirmed labels, with provenance (model name and version, prompt, confidence, source photo), and nothing enters the record until the owner confirms it. The confirmation UI comes before any model work. The rough-in trial order is: (1) "What am I looking at?", tap a still and get an identification, explanation and proposed tags, scored on 50 rough-in stills against the owner's labels; (2) AI-assisted stitching, feature matches across sessions as extra pose-graph constraints and proposed plan-corner correspondences; (3) capture coaching, a re-shoot list from mesh coverage and tracking-limited spans; (4) auto-tagging and natural-language search, tested on 20 queries. Confirmed labels become the private training set for a small detector later. The session format already stores everything these need.

## Consequences

Positive:

- No unconfirmed gas or electrical label ever reaches the viewer.
- Models are swappable as they improve; the durable investment is the UI and the confirmed labels.

Negative:

- The owner labels at least 50 stills per trial; no whole-house automatic tagging in the near term.
- Candidates add a label schema with status and provenance, and small per-photo API costs.

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| Open-vocabulary detector as ground truth | More than 85 points below a fine-tuned detector; misses whole classes. |
| Fully automatic vision language tagging | Plausible text with no verification path years later. |
| Train a detector first | No dataset exists; confirmed labels have to come first. |
| 3D open-vocabulary segmentation | Research-grade and heavy; depth ray-casting gets most of the value. |
