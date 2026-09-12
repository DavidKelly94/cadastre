# Igloo AI roadmap

## Principle

Everything below runs on data Igloo captures today. The session format (posed high-resolution stills, 256x192 LiDAR depth with per-pixel confidence for every keyframe, intrinsics, tapped landmarks, marker observations, per-level plan alignment and a phase tag on every session) was designed so each idea is a pipeline stage over `sessions/` and `derived/`, not a new capture requirement. Nothing here needs a recapture, and none of it is in the two-week MVP.

The owner trials the first four items during electrical and plumbing rough-in, in one to two months. Implementers should read `docs/session-format.md` first, never modify raw sessions, and write every output under `derived/` with a `source` field and a `confirmed` flag. Sources for the models named here are in `docs/feasibility.md`. Effort: S is a day or two, M about a week, L several weeks.

## Priority items for the rough-in trial

### 1. "What am I looking at?"

**What it does.** Tap a point on a still; the tool names the element, explains how it can tell, and proposes tags: PEX vs copper vs CPVC, NM-B gauge from jacket colour, CSST gas, ABS vs PVC drain, supply vs return duct, low-voltage vs line-voltage, box types, nail plates, fire blocking. Every answer is a candidate until the owner confirms it.

**Inputs.** `stills/NNN.jpg` with pose and `K` from `stills.jsonl`; the nearest keyframe's `depth/` and `conf/` for the ray under the tap; `manifest.json` room, level and phase; `derived/align.json` for the plan position.

**Candidate approach.** A vision LLM (Claude or Gemini class) gets the full still, a full-resolution crop around the tap and a prompt fixed to a tag vocabulary, and returns JSON with element, material, nominal size, confidence, a short "how I can tell" and tags. Optionally SAM 3 masks the tapped region first, so the model sees it outlined and the mask is kept for the later 3D layer. Output: `derived/labels/<still>.json` with `source: "vlm"`, `confirmed: false`. No fine-tuning yet: describing one region is a task VLMs handle far better than the open-vocabulary detection the ISARC 2025 study found weak.

**Rough-in trial.** The owner labels 50 rough-in stills first (element, material, size). Run the tool on the same 50 taps; score element class, material and size separately and count confidently wrong statements. Bar: 40 of 50 element classes right and zero wrong claims about gas lines. If confirming is slower than typing the label, the UI is wrong.

**Effort.** S.

**Risk and fallback.** Confident wrong answers, especially gauge from jacket colour, a convention that varies by manufacturer and year. Mitigation: fixed vocabulary, mandatory "how I can tell", default "unsure" on small crops. Fallback: a typing aid that only suggests vocabulary tags.

### 2. AI-assisted stitching and registration

**What it does.** Adds constraints between sessions and phases beyond the markers, flags misalignment, and proposes plan-corner correspondences so the owner clicks less.

**Inputs.** `rgb/` keyframes with `T_wc` and `K`; `depth/` and `conf/`; `markers.jsonl` and `derived/markers_detected.jsonl`; `mesh.obj` with `mesh_classes.u8`; `landmarks.jsonl`; `plans/<level>.json`; `derived/align.json`.

**Candidate approach.** (a) Within a phase: SuperPoint features matched with LightGlue between keyframe pairs of overlapping sessions; depth under each keypoint makes 3D-3D correspondences, a RANSAC Umeyama fit gives a relative SE(3), and that becomes an edge in the pose graph (scipy least squares or GTSAM) beside the marker edges. SuperPoint and LightGlue licences were not covered by the research; check before product use. (b) Across phases: keypoints survive only on surfaces that survive (subfloor, top plates, rough openings), so weight those edges low and keep markers primary; MASt3R or MapAnything (Apache-2.0 code, Apache weights variant) give dense two-view geometry that tolerates low-texture walls and can take known poses and depth as input. (c) Plan corners: slice the mesh at 1.0 to 1.5 m, project wall faces onto the plan, detect lines and propose corner matches in the style of Z-FLoc's bird's-eye line matching; the owner accepts or rejects each on the align page.

**Rough-in trial.** Two overlapping sessions of one room in the same phase, plus a framing and a rough-in session of the same room. Metric: each marker's house-frame position spread across sessions before and after adding AI edges (targets under 3 cm within a phase, under 5 cm across), and the fraction of proposed plan corners accepted unchanged.

**Effort.** M (matching S, pose graph M, corner proposals M).

**Risk and fallback.** Repetitive stud bays produce plausible wrong matches that can fold the graph; gate every AI edge with RANSAC against the marker prior and keep them switchable. Fallback is the MVP path: markers and tapped landmarks only.

### 3. Capture coaching

**What it does.** After ingest, a report says what was missed ("north wall, upper half, never closer than 2 m", "no still of the panel", "tracking limited for 14 s near the closet") and produces a re-shoot list for the next visit. Later, live HUD hints.

**Inputs.** `mesh.obj` and `mesh_classes.u8`; `frames.jsonl` (poses, `tracking`, `exp_s`, `thermal`); `rgb/` keyframes; `stills.jsonl`; `markers.jsonl`; manifest stats; the room's expected-element checklist.

**Candidate approach.** Mostly geometry. Cluster wall faces into planes, grid each at 0.5 m, and per cell compute the closest keyframe distance and viewing angle; flag cells never seen under 2 m or only at grazing angles over 60 degrees. Blur from Laplacian variance (OpenCV); tracking-limited and thermal spans from `frames.jsonl`; marker count from `markers.jsonl`. "No still of the panel" needs a vision LLM pass over the stills against the checklist. An LLM turns the numeric report into plain instructions ordered by walking route. Depth Anything 3 (`DA3METRIC-LARGE`, Apache-2.0) can optionally fill LiDAR holes in dark or distant areas.

**Rough-in trial.** Run on every rough-in session the same day. Measure time from ingest to report (target under 2 minutes), flagged items, and on the next visit how many the owner agrees were real gaps (target 8 in 10).

**Effort.** S for the offline report, M for live HUD hints.

**Risk and fallback.** False alarms cost trust fast; start with loose thresholds and tighten. Fallback is the manual coverage checklist strip already in the HUD design.

### 4. Auto-tagging and natural-language search

**What it does.** Every still and a sample of keyframes gets a room, phase, element tags and a one-line description. A query such as "gas line in the kitchen wall" returns photos placed on the plan with their view direction.

**Inputs.** `stills/` and sampled `rgb/` with poses; `derived/align.json` to map camera positions into a room polygon on the plan; `manifest.json` phase and room; confirmed labels from item 1.

**Candidate approach.** Batch, offline, on the PC. A vision LLM writes the description and picks tags from item 1's vocabulary; text embeddings go into a small index (SQLite plus numpy is enough for a few thousand photos); a CLIP or SigLIP class image-text embedding can be added for visual queries. An LLM extracts room, phase and element filters from the query; ranked results are drawn on the plan inspector as pins with view cones. Confirmed labels always outrank generated ones.

**Rough-in trial.** Write 20 queries before tagging runs, with expected photos noted. Score precision at 5 and classify each miss (wrong room, wrong element, missing tag, alignment missing).

**Effort.** M.

**Risk and fallback.** Room assignment fails without alignment; fall back to the manifest room, which is exact because sessions are per room. Tag noise: search over descriptions and confirmed labels only until accuracy is measured.

## Later candidates

**Plan understanding.** Extract rooms, door and window tags and electrical symbols from the plan sheets into expected-element checklists per room. Lists only: VLMs score 33 to 38% on ArchPlanVQA plan geometry, so nothing here places anything spatially, and every item is confirmable. Use pdfplumber text from vector PDFs for room names and tags and give the model the legend sheet. Feeds item 3 and the review below.

**Plan-vs-built review.** Missing receptacle: checklist versus confirmed labels per room. Wall moved more than 2 in: offset between each mesh wall plane and its plan line after alignment, above the normal 1 to 2 in as-built deviation. Nail plates: a detector on stills where labelled pipes or wires cross studs, flagging crossings without a plate. Output is a per-room list with photos, never a pass or fail.

**Per-wall change detection between phases.** Each phase's stills are rectified onto the wall plane (homography from pose and plane) into a canonical square-on view; diff consecutive phases (SSIM or feature-based), cluster the changes, and have a VLM describe what was added. Depends on the protocol's same-corner, same-height stills.

**Semantic 3D layer.** Cast confirmed masks (SAM 3, from item 1) through the nearest keyframe's depth where confidence is high, cluster into 3D elements, and store each as a point set or oriented box in the house frame, clickable in the viewer. With a few hundred confirmed labels, fine-tune YOLO11-nano (the ISARC 2025 winner at 23.36 FPS) to propose new elements; its licence was not covered by the research, so verify Ultralytics' terms before product use.

**As-built report generation.** Per room and wall: elements with distances from the nearest tapped corner (landmarks plus mesh), phase, photos and residual to plan. An LLM writes the narrative from structured data only; reportlab produces the PDF with links back to the stills.

**Stud-centre projection and measurement assistant.** From framing-phase mesh and stills, detect stud faces as vertical planar strips, compute centres and spacing, and project them onto the finished wall in the viewer or AR; answer "how far from the corner is the next stud" from the house frame.

**AR x-ray narration.** Once the finished house is aligned through openings and corners, the phone overlays earlier-phase photos and elements, and a VLM narrates what is behind the pointed area from stored labels, with distances. Depends on item 2 and the viewer.

**On-site voice notes pinned to location.** Record while capturing, transcribe on device, pin the note to the current pose and nearest element, summarise with an LLM and index it with item 4. Simple and high value; capture the audio early even if the AI part waits.

## Data to start collecting now

- [ ] A confirmed label for every still at review: element type, material, nominal size, circuit or fixture if known. Test set for item 1, training set for the later detector.
- [ ] Stills of each element type square-on and at 45 degrees from about 1 m with a tape in frame: PEX, copper, CPVC, ABS and PVC drain, CSST and black iron gas, NM-B of each gauge, low-voltage, conduit, each box type, the panel, nail plates, fire blocking, headers, blocking, supply and return ducts, dryer vent, bath fans, drain vents, shutoffs.
- [ ] Every marker photographed square-on in every session, position recorded relative to an invariant feature.
- [ ] The same wall from the same corner at the same height in every phase.
- [ ] Landmarks tapped at every room corner and door threshold.
- [ ] The plan PDF, electrical and plumbing sheets and the legend page in the project store.
- [ ] Session notes filled on site, including what the inspector or trades said.
- [ ] A frozen test set: 50 labelled rough-in stills and 20 written queries with expected answers, never used for tuning.
- [ ] Negative examples: empty stud bays, drywall-phase walls, blurry frames.

## Guardrails

- AI outputs are candidates until the owner confirms them; every derived record carries `source`, a confidence and a `confirmed` flag with who and when, and the viewer and search default to confirmed data.
- Never present code-compliance conclusions as authoritative: the tools may list items to check with the inspector or trades, never pass, fail or compliant.
- Statements about gas lines and live circuits stay flagged unverified until a person who looked confirms them.
- Every measurement shows its source (marker, landmark, mesh, photo ray) and an uncertainty; AI-derived geometry is never labelled as measured.
- Raw sessions are read-only; AI outputs live under `derived/` and can be regenerated.
- Photos leave the PC only when the owner chooses a cloud model; each item notes whether it needs a cloud API or runs locally.
