# Igloo AI roadmap

## Principle

Everything below runs on data Igloo captures today. The session format (posed high-resolution stills, 256x192 LiDAR depth with a per-pixel confidence map for every keyframe, camera intrinsics, tapped landmarks, marker observations, per-level plan alignment and a phase tag on every session) was designed so that each idea is a pipeline stage over `sessions/` and `derived/`, not a new capture requirement. Nothing here needs a recapture, and none of it is in the two-week MVP.

The owner trials the first four items during electrical and plumbing rough-in, in one to two months. Whoever implements them should read `docs/session-format.md` and `docs/design/pipeline-design.md` first, never modify raw sessions, and write every output under `derived/` with a `source` field and a `confirmed` flag. Sources for the models and papers named here are listed in `docs/feasibility.md`.

Effort scale: S is a day or two, M about a week, L several weeks.

## Priority items for the rough-in trial

### 1. "What am I looking at?"

**What it does.** Tap a point on a still; the tool names the element, explains how it can tell, and proposes tags. Targets: PEX vs copper vs CPVC; NM-B gauge from jacket colour; CSST gas; ABS vs PVC drain; supply vs return duct; low-voltage vs line-voltage; box types; nail plates; fire blocking. Every answer is stored as a candidate until the owner confirms it.

**Inputs.** `stills/NNN.jpg` with its pose and `K` from `stills.jsonl`; the nearest keyframe's `depth/` and `conf/` for the ray under the tap; `manifest.json` room, level and phase; `derived/align.json` for the position on the plan.

**Candidate approach.** A vision LLM (Claude or Gemini class) receives the full still plus a full-resolution crop around the tap point and a structured prompt fixed to a tag vocabulary; it returns JSON with element, material, nominal size, confidence, a short "how I can tell" explanation and the tags. Optionally SAM 3 produces a mask at the tap point first, so the model sees the region outlined and the mask is kept for the later 3D layer. Output goes to `derived/labels/<still>.json` with `source: "vlm"` and `confirmed: false`. No fine-tuning yet: the ISARC 2025 result says zero-shot detectors are weak on MEP elements, but this is a describe-one-region task, which VLMs handle far better than open-vocabulary detection.

**Rough-in trial.** Before running the model, the owner labels 50 rough-in stills (element, material, size). Run the tool on the same 50 taps and score element class, material and size separately, and count confidently wrong statements. A useful bar: 40 of 50 element classes right and zero wrong claims about gas lines. Time the confirm step; if confirming takes longer than typing the label, the UI is wrong.

**Effort.** S.

**Risk and fallback.** Confident wrong answers, especially gauge from jacket colour: the colour convention is common but not universal and varies by manufacturer and year. Mitigation: fixed vocabulary, a mandatory "how I can tell" sentence the owner can check, and a default of "unsure" when the crop is small. Fallback: the tool becomes a typing aid that only suggests tags from the vocabulary.

### 2. AI-assisted stitching and registration

**What it does.** Adds constraints between sessions and phases beyond the markers, flags misalignment, and proposes plan-corner correspondences so the owner clicks less.

**Inputs.** `rgb/` keyframes with `T_wc` and `K`; `depth/` and `conf/`; `markers.jsonl` and `derived/markers_detected.jsonl`; `mesh.obj` with `mesh_classes.u8`; `landmarks.jsonl`; `plans/<level>.json`; `derived/align.json`.

**Candidate approach.** Three pieces. (a) Within a phase: SuperPoint features matched with LightGlue between keyframe pairs from overlapping sessions; depth under each keypoint turns matches into 3D-3D correspondences, a RANSAC Umeyama fit gives a relative SE(3), and that becomes an edge in the pose graph (scipy least squares or GTSAM) beside the marker edges. Licences for SuperPoint weights and LightGlue were not covered by the research; check before product use. (b) Across phases: sparse keypoints survive only on surfaces that survive (subfloor, top plates, rough openings), so weight those edges low and keep markers primary; MASt3R or MapAnything (Apache-2.0 code, Apache weights variant) give dense two-view geometry that tolerates low-texture walls better and can take the known poses and depth as input. (c) Plan corners: slice the mesh between 1.0 and 1.5 m, project wall-classified faces onto the plan, detect lines, and propose corner-to-plan-corner matches in the style of Z-FLoc's bird's-eye line matching; the owner accepts or rejects each proposal on the existing align page.

**Rough-in trial.** Two overlapping sessions of one room in the same phase, plus one framing and one rough-in session of the same room. Metric: the spread of each marker's house-frame position across sessions before and after adding AI edges, with targets under 3 cm within a phase and under 5 cm across phases; and the fraction of auto-proposed plan corners the owner accepts unchanged.

**Effort.** M (matching S, pose graph M, corner proposals M).

**Risk and fallback.** Repetitive stud bays produce plausible wrong matches and can fold the graph; gate every AI edge with RANSAC against the marker prior and keep them switchable. Fallback is the MVP path: markers and tapped landmarks only.

### 3. Capture coaching

**What it does.** After ingest, a report says what was missed ("north wall, upper half, never closer than 2 m", "no still of the panel", "tracking limited for 14 s near the closet") and produces a re-shoot list for the next visit. Later, live HUD hints.

**Inputs.** `mesh.obj` and `mesh_classes.u8`; `frames.jsonl` (poses, `tracking`, `exp_s`, `thermal`); `rgb/` keyframes; `stills.jsonl`; `markers.jsonl`; manifest stats (limited seconds, dropped frames); the room's expected-element checklist.

**Candidate approach.** Mostly geometry, little ML. Cluster wall-classified faces into planes, grid each plane at 0.5 m, and for each cell compute the closest keyframe distance and viewing angle; flag cells never seen under 2 m or only at grazing angles over 60 degrees. Blur from Laplacian variance per keyframe (OpenCV); tracking-limited and thermal spans straight from `frames.jsonl`; marker count from `markers.jsonl`. The "no still of the panel" check needs a vision LLM pass over the stills to list what was captured against the checklist. An LLM then turns the numeric report into plain instructions ordered by walking route. Depth Anything 3 (`DA3METRIC-LARGE`, Apache-2.0) can fill LiDAR holes when judging coverage of dark or distant areas, but is optional.

**Rough-in trial.** Run on every rough-in session the same day. Measure time from ingest to report (target under 2 minutes), the number of flagged items, and on the next visit how many the owner agrees were real gaps (target 8 in 10). Track how many re-shoots the list actually caused.

**Effort.** S for the offline report, M for live HUD hints (needs on-device mesh queries and a stripped-down rule set).

**Risk and fallback.** False alarms cost trust fast; start with loose thresholds and tighten. Fallback is the manual coverage checklist strip already in the HUD design.

### 4. Auto-tagging and natural-language search

**What it does.** Every still and a sample of keyframes gets a room, phase, element tags and a one-line description. A query such as "gas line in the kitchen wall" returns photos placed on the plan with their view direction.

**Inputs.** `stills/` and sampled `rgb/` with poses; `derived/align.json` to map camera positions into the plan and hence into a room polygon; `manifest.json` phase and room; confirmed labels from item 1.

**Candidate approach.** Batch, offline, on the PC. A vision LLM writes the description and picks tags from the same vocabulary as item 1; text embeddings of descriptions plus tags go into a small index (SQLite plus numpy is enough for a few thousand photos); an image-text embedding model (CLIP or SigLIP class) can be added for purely visual queries. Query handling: an LLM extracts room, phase and element filters from the text, then ranked results are drawn on the plan inspector as pins with view cones. Confirmed labels always outrank generated ones.

**Rough-in trial.** Write 20 queries before tagging runs, with the expected photos noted. Score precision at 5 and classify each miss (wrong room, wrong element, missing tag, alignment missing).

**Effort.** M.

**Risk and fallback.** Room assignment fails when a session has no alignment yet; fall back to the manifest room, which is exact because sessions are per room. Tag noise: search over descriptions and confirmed labels only until tagging accuracy has been measured.

## Later candidates

**Plan understanding.** Extract rooms, door and window tags and electrical symbols from the plan sheets into expected-element checklists per room (receptacles, switches, fixtures, ducts, drops). Lists only: VLMs score 33 to 38% on ArchPlanVQA plan geometry, so nothing here places anything spatially, and every item is confirmable. Use pdfplumber text from vector PDFs for room names and tags where available, and give the model the legend sheet as context. Feeds item 3 and the plan-vs-built review.

**Plan-vs-built review.** Three checks. Missing receptacle: checklist versus confirmed labels per room. Wall moved more than 2 in: offset between each mesh wall plane and its plan line after alignment, with the threshold above the normal 1 to 2 in as-built deviation. Nail plates: a detector on stills at places where labelled pipes or wires cross studs, flagging crossings without a plate. Output is a per-room list with the photos, never a pass or fail.

**Per-wall change detection between phases.** Every wall is a plane in the mesh, so each phase's stills can be rectified onto the wall plane (homography from pose and plane) into a canonical square-on view; diff consecutive phases (SSIM or feature-based), cluster the changes, and have a VLM describe what was added. Depends on the protocol's same-corner, same-height stills.

**Semantic 3D layer.** Take confirmed masks (SAM 3 from item 1), cast them through the nearest keyframe's depth where confidence is high, cluster into 3D elements, and store each as a small point set or oriented box in the house frame that is clickable in the viewer. Once a few hundred confirmed labels exist, fine-tune YOLO11-nano (the ISARC 2025 winner at 23.36 FPS) to propose new elements automatically; its licence was not covered by the research, so verify Ultralytics' terms before any product use.

**As-built report generation.** Per room and wall: elements with distances from the nearest tapped corner (landmarks plus mesh), phase, photos and residual to plan. An LLM writes the narrative from structured data only; reportlab produces the PDF; the report links back to the stills.

**Stud-centre projection and measurement assistant.** From framing-phase mesh and stills, detect stud faces as vertical planar strips, compute centres and spacing, and project them onto the finished wall in the viewer or in AR; answer "how far from the corner is the next stud" from the house frame.

**AR x-ray narration.** After the finished house is aligned through openings and corners, the phone overlays earlier-phase photos and elements; a VLM narrates what is behind the pointed area from the stored labels, with distances. Depends on item 2's registration and on the viewer work.

**On-site voice notes pinned to location.** Record while capturing, transcribe on device, pin the note to the current pose and nearest element, summarise with an LLM and index it with item 4. Simple and high value; capture it early even if the AI part waits.

## Data to start collecting now

- [ ] Confirm a label for every still during review: element type, material, nominal size, and circuit or fixture if known. These become the test set for item 1 and the training set for the later detector.
- [ ] Take stills of each element type square-on and at 45 degrees, from about 1 m, with a tape in frame: PEX, copper, CPVC, ABS and PVC drain, CSST and black iron gas, NM-B of each gauge, low-voltage runs, conduit, each box type, the panel, nail plates, fire blocking, headers, blocking, supply and return ducts, dryer vent, bath fans, drain vents, shutoffs.
- [ ] Photograph every marker square-on in every session, and record its position relative to an invariant feature.
- [ ] Shoot the same wall from the same corner at the same height in every phase (change detection needs the pairs).
- [ ] Tap landmarks at every room corner and door threshold in every session.
- [ ] Keep the plan PDF plus the electrical and plumbing sheets and the legend page in the project store.
- [ ] Fill the session notes field on site; note anything the inspector or trades said.
- [ ] Freeze a test set: 50 labelled rough-in stills and 20 written search queries with expected answers, never used for tuning.
- [ ] Keep negative examples: empty stud bays, drywall-phase walls, blurry frames.

## Guardrails

- AI outputs are candidates until the owner confirms them. Every derived record carries `source`, a confidence and a `confirmed` flag with who and when; the viewer and search default to confirmed data and mark candidates visibly.
- Never present code-compliance conclusions as authoritative. The tools may list items to check with the inspector or the trades; they never say pass, fail or compliant.
- Statements about gas lines and live circuits are flagged as unverified unless confirmed by a person who looked.
- Every measurement shows its source (marker, landmark, mesh, photo ray) and an uncertainty; AI-derived geometry is never labelled as measured.
- Raw sessions are read-only; all AI outputs live under `derived/` and can be deleted and regenerated.
- Photos leave the PC only when the owner chooses a cloud model; each item above notes whether it needs a cloud API or runs locally, and a local option is kept for everything that touches the whole photo set.
