# VividHome AI roadmap

## Principle

Everything below runs on data VividHome captures today: the session format (posed high-resolution stills, 256x192 LiDAR depth with per-pixel confidence for every keyframe, intrinsics, tapped landmarks, marker observations, per-level plan alignment and a phase tag on every session) was designed so each idea is a pipeline stage over `sessions/` and `derived/`, not a new capture requirement; none of it needs a recapture or is in the two-week MVP.

The owner trials the first four items during electrical and plumbing rough-in in one to two months. Implementers: read `docs/session-format.md` first, never modify raw sessions, write outputs under `derived/` with `source` and `confirmed` fields. Model sources are in `docs/feasibility.md`. Effort: S is days, M about a week, L several weeks.

## Priority items for the rough-in trial

### 1. "What am I looking at?"

**What it does.** Tap a point on a still; the tool names the element, explains how it can tell, and proposes tags: PEX vs copper vs CPVC, NM-B gauge from jacket colour, CSST gas, ABS vs PVC drain, supply vs return duct, low-voltage vs line-voltage, box types, nail plates, fire blocking. Every answer is a candidate until the owner confirms it.

**Inputs.** `stills/NNN.jpg` with pose and `K` (`stills.jsonl`); the nearest keyframe's `depth/` and `conf/` for the ray under the tap; room, level and phase from `manifest.json`; `derived/align.json` for the plan position.

**Candidate approach.** A vision LLM (Claude or Gemini class) gets the still, a full-resolution crop around the tap and a prompt fixed to a tag vocabulary, and returns JSON: element, material, nominal size, confidence, a short "how I can tell", tags. SAM 3 can mask the tapped region first, outlining it for the model and keeping the mask for the 3D layer. Output: `derived/labels/<still>.json`, `source: "vlm"`, `confirmed: false`. No fine-tuning yet: describing one region suits VLMs far better than the open-vocabulary detection ISARC 2025 found weak.

**Rough-in trial.** The owner labels 50 rough-in stills first (element, material, size), then runs the tool on the same taps; score element class, material and size separately and count confidently wrong statements. Bar: 40 of 50 element classes right, zero wrong claims about gas lines.

**Effort.** S.

**Risk and fallback.** Confident wrong answers, especially gauge from jacket colour (the convention is not universal); mitigate with the fixed vocabulary, the mandatory "how I can tell" and a default "unsure" on small crops. Fallback: a typing aid suggesting vocabulary tags.

### 2. AI-assisted stitching and registration

**What it does.** Adds constraints between sessions and phases beyond the markers, flags misalignment, and proposes plan-corner correspondences.

**Inputs.** `rgb/` keyframes with `T_wc` and `K`, `depth/`, `conf/`, `markers.jsonl`, `derived/markers_detected.jsonl`, `mesh.obj`, `mesh_classes.u8`, `landmarks.jsonl`, `plans/<level>.json`, `derived/align.json`.

**Candidate approach.** (a) Within a phase: SuperPoint features matched with LightGlue between keyframes of overlapping sessions; depth under each keypoint gives 3D-3D correspondences, a RANSAC Umeyama fit gives a relative SE(3), and that becomes a pose-graph edge (scipy or GTSAM) beside the marker edges (licences not covered by the research; check before product use). (b) Across phases: keypoints survive only on surfaces that survive (subfloor, top plates, rough openings), so weight those edges low and keep markers primary; MASt3R or MapAnything (Apache-2.0 code, Apache weights variant) give dense two-view geometry that tolerates low-texture walls and accepts known poses and depth. (c) Plan corners: slice the mesh at 1.0 to 1.5 m, project wall faces onto the plan, detect lines and propose corner matches Z-FLoc style for the owner to accept or reject on the align page.

**Rough-in trial.** Two overlapping sessions of one room in one phase, plus a framing and a rough-in session of the same room. Metric: each marker's house-frame position spread across sessions before and after AI edges (targets under 3 cm within a phase, under 5 cm across) and the fraction of proposed plan corners accepted unchanged.

**Effort.** M (matching S, pose graph M, corner proposals M).

**Risk and fallback.** Repetitive stud bays produce plausible wrong matches that can fold the graph; gate every AI edge with RANSAC against the marker prior and keep them switchable. Fallback: markers and tapped landmarks only, the MVP path.

### 3. Capture coaching

**What it does.** After ingest, a report lists what was missed ("north wall, upper half, never closer than 2 m", "no still of the panel") as a re-shoot list for the next visit; later, live HUD hints.

**Inputs.** `mesh.obj`, `mesh_classes.u8`, `frames.jsonl` (poses, `tracking`, `exp_s`, `thermal`), `rgb/`, `stills.jsonl`, `markers.jsonl`, the room's expected-element checklist.

**Candidate approach.** Mostly geometry: cluster wall faces into planes, grid each at 0.5 m, and per cell compute the closest keyframe distance and viewing angle; flag cells never seen under 2 m or only at grazing angles over 60 degrees. Blur via Laplacian variance (OpenCV); tracking-limited and thermal spans from `frames.jsonl`. "No still of the panel" needs a vision LLM pass over the stills against the checklist; an LLM then writes plain instructions ordered by walking route. Depth Anything 3 (`DA3METRIC-LARGE`, Apache-2.0) can optionally fill LiDAR holes.

**Rough-in trial.** Run on every rough-in session the same day; measure time from ingest to report (target under 2 minutes), flagged items, and how many the owner agrees were real gaps on the next visit (target 8 in 10).

**Effort.** S for the offline report, M for live HUD hints.

**Risk and fallback.** False alarms cost trust fast; start loose and tighten. Fallback: the manual coverage checklist strip already in the HUD design.

### 4. Auto-tagging and natural-language search

**What it does.** Every still and a sample of keyframes gets a room, phase, element tags and a one-line description, so "gas line in the kitchen wall" returns photos placed on the plan with their view direction.

**Inputs.** `stills/` and sampled `rgb/` with poses, `derived/align.json` (camera position to room polygon), `manifest.json` phase and room, confirmed labels from item 1.

**Candidate approach.** Batch, offline, on the PC: a vision LLM writes the description and picks tags from item 1's vocabulary; text embeddings go into a small index (SQLite plus numpy suffices), with an optional CLIP or SigLIP class image-text embedding for visual queries. An LLM extracts room, phase and element filters from the query; ranked results appear on the plan inspector as pins with view cones, confirmed labels outranking generated ones.

**Rough-in trial.** Write 20 queries before tagging runs, with expected photos noted. Score precision at 5 and classify each miss (wrong room, wrong element, missing tag, alignment missing).

**Effort.** M.

**Risk and fallback.** Room assignment fails without alignment; fall back to the manifest room, exact because sessions are per room. Tag noise: search over descriptions and confirmed labels only until accuracy is measured.

### 5. Predicted landmarks, so capture stops being tap-heavy

**Why it moved up.** [ADR-0026](adr/0026-markers-are-optional-the-plan-is-the-frame.md) made tapped landmarks the only thing that places a capture on the plan. That puts the whole alignment on a manual, repetitive act performed one-handed in a noisy room — the worst place to ask for precision, and the thing most likely to be skipped. Anything that turns "tap every corner" into "confirm these" improves accuracy and adoption at the same time.

**What it does.** Two halves that meet in the middle. On the plan: read the drawing and propose named points — "kitchen NW corner", "bedroom 2 door threshold" — so the owner never types a label and the pipeline gets labels that are matchable months later. In the room: when a room is selected, propose where its corners are so the owner drags a few candidates into place instead of tapping each from nothing.

**Inputs.** `plans/<level>.png` and `<level>.json`; `mesh.obj` with `mesh_classes.u8` (wall faces are already captured and classified); optionally ARKit vertical planes, which are currently switched off.

**Plan side: built, 2026-09-15.** `PlanLabelReader` in the app runs `VNRecognizeTextRequest` over the imported raster and offers what it finds as room candidates the owner taps to place and drags to correct. Candidates are held in memory and never written to `plans/<level>.json`, which is what keeps rule 9 true without a `confirmed` flag in the contract that could drift from what it describes. What remains is the room side below, and using polygon geometry rather than only label position.

**Candidate approach, plan side.** Mostly classical and all on-device. `VNRecognizeTextRequest` reads room names off an architect's sheet; `VNDetectContoursRequest` gives room polygons whose vertices *are* the corners; the nearest text to a polygon names it, and compass sense on the sheet turns a vertex into "NW". A vector PDF short-circuits most of this — pdfplumber already gives text with positions (see Plan understanding below). No model is required for the common case, which is the point: a plan is a drawing made of lines and labels, not a photograph to be interpreted.

**Candidate approach, room side.** Fit planes to `wall`-classified mesh faces and intersect adjacent pairs; each intersection that also meets the floor plane is a corner candidate with a confidence from the inlier count. This costs nothing extra to capture because the mesh is already written. Turning on `planeDetection = [.vertical]` would give the same thing live rather than offline, at a frame-time cost that `docs/design/ios-app-design.md` deliberately avoided — measure before spending it.

**Not RoomPlan.** It is the obvious suggestion and this project already rejected it twice, on measurements: it fits *idealised* planar walls, and a test saw a 6.45 m wall reported as 6.821 m ([ADR-0001](adr/0001-native-swift-arkit.md), `feasibility.md`). A 37 cm error is an order of magnitude worse than what alignment needs, so its corners cannot be correspondences. Its *topology* — how many walls a room has and roughly where they meet — may still be sound, and if this item is ever attempted it is worth re-testing on framing rather than assumed; but nothing should depend on its geometry.

**Everything proposed is a candidate.** Rule 9 of `AGENTS.md`, and here it is also the interaction: a predicted corner is drawn unconfirmed, and dragging it into place *is* the confirmation. A candidate nobody confirms never reaches `landmarks.jsonl`. This is why the editable-landmark work is the prerequisite — without cheap correction, a wrong prediction is worse than no prediction.

**Rough-in trial.** One room with an architect's PDF and one photographed paper plan. Metrics: the fraction of room names OCR'd correctly, the fraction of proposed corners the owner accepts with a drag under 20 cm, and taps per room against the manual baseline.

**Effort.** M (plan side S if the PDF is vector, M if photographed; room side M).

**Risk and fallback.** Repetitive rooms and a plan that does not match as-built both produce confident wrong proposals, and a proposal that looks authoritative is more dangerous than an empty screen — an owner who drags a corner "into place" against a wrong prediction has anchored on it. Draw candidates in a distinctly unconfirmed style, never pre-confirm, and keep the count low. Fallback is the MVP path: tap every landmark by hand.

## Later candidates

**Plan understanding.** Extract rooms, door and window tags and electrical symbols into expected-element checklists per room, using pdfplumber text from vector PDFs and the legend sheet as context. Lists only, since VLMs score 33 to 38% on ArchPlanVQA plan geometry: nothing is placed spatially and every item is confirmable. Feeds item 3 and the review below.

**Plan-vs-built review.** Missing receptacle: checklist versus confirmed labels per room. Wall moved more than 2 in: offset between each mesh wall plane and its plan line after alignment, above the normal 1 to 2 in as-built deviation. Nail plates: a detector on stills where labelled pipes or wires cross studs. Output is a per-room list with photos, never pass or fail.

**Per-wall change detection between phases.** Rectify each phase's stills onto the wall plane (homography from pose and plane) into a canonical square-on view, diff consecutive phases (SSIM or feature-based), cluster the changes, and have a VLM describe what was added; needs the protocol's same-corner, same-height stills.

**Semantic 3D layer.** Cast confirmed masks (SAM 3, item 1) through the nearest keyframe's depth where confidence is high, cluster into 3D elements stored as point sets or oriented boxes in the house frame, clickable in the viewer. With a few hundred confirmed labels, fine-tune YOLO11-nano (the ISARC 2025 winner, 23.36 FPS) to propose elements; its licence was not covered by the research, so verify Ultralytics' terms before product use.

**As-built report generation.** Per room and wall: elements with distances from the nearest tapped corner (landmarks plus mesh), phase, photos and residual to plan; an LLM writes the narrative from structured data only and reportlab produces the PDF, linked to the stills.

**Stud-centre projection and measurement assistant.** Detect stud faces in framing-phase mesh and stills as vertical planar strips, compute centres and spacing, and project them onto the finished wall in the viewer or AR to answer "how far from the corner is the next stud".

**AR x-ray narration.** Once the finished house is aligned through openings and corners, the phone overlays earlier-phase photos and elements and a VLM narrates what is behind the pointed area from stored labels, with distances; depends on item 2 and the viewer.

**Spatial markup and annotation.** A mark belongs to a place, not to a photo: store each one against a house-frame point plus the plan position, so it shows on every phase, in the 3D view and on the plan sheet, and survives a re-alignment. An annotation carries a target (point, region or element), an author, a phase, free text and optional photo references. The AI role is small and worth keeping small: summarise a thread, group marks that concern the same element, and draft a mark from dictated speech. The data model is the hard part and is deliberately independent of any model.

**Builder and client sharing.** Coordination means other people see the record, which the MVP architecture does not allow: ADR-0012 chose no accounts and no cloud. Sharing needs a scope per recipient (a room, a phase, a mark thread), a read-only view that does not leak the rest of the house, and an identity for attribution. That is a future ADR superseding the no-accounts clause, not an incremental feature, and it should not be started before the capture and alignment layers are trusted.

**Question answering over panoramas.** `docs/session-format.md` §7 reserves the panorama slot. A pano answers "what did this corner look like" in one image where a still answers only for one direction, so it is a better retrieval unit for a room-level question. Treat a pano as a first-class searchable item with its own pose, and when answering, cite the pano plus the yaw the answer refers to so the viewer can point the camera there.

**On-site voice notes pinned to location.** Record while capturing, transcribe on device, pin the note to the current pose and nearest element, summarise with an LLM and index it with item 4; simple and high value, so capture audio early even if the AI waits.

## Data to start collecting now

- [ ] A confirmed label for every still at review: element type, material, nominal size, circuit or fixture if known.
- [ ] Stills of each element type square-on and at 45 degrees from about 1 m with a tape in frame: PEX, copper, CPVC, ABS and PVC drain, CSST and black iron gas, NM-B of each gauge, low-voltage, conduit, each box type, the panel, nail plates, fire blocking, headers, ducts, drain vents, shutoffs.
- [ ] Every marker photographed square-on each session, position noted relative to an invariant feature.
- [ ] The same wall from the same corner and height in every phase, and landmarks tapped at every room corner and door threshold.
- [ ] Plan PDF, electrical and plumbing sheets and the legend page in the project store.
- [ ] Session notes filled on site, including what inspectors or trades said.
- [ ] A frozen test set: 50 labelled rough-in stills and 20 written queries with expected answers, never used for tuning.
- [ ] Negative examples: empty stud bays, drywall-phase walls, blurry frames.

## Guardrails

- AI outputs are candidates until the owner confirms them; every derived record carries `source`, confidence and `confirmed` (who, when), and the viewer and search default to confirmed data.
- Never present code-compliance conclusions as authoritative: tools may list items to check with the inspector or trades, never pass, fail or compliant.
- Gas-line and live-circuit statements stay flagged unverified until a person who looked confirms them.
- Every measurement shows its source (marker, landmark, mesh, photo ray) and an uncertainty; AI-derived geometry is never labelled as measured.
- Raw sessions are read-only; AI outputs live under `derived/` and can be regenerated.
- Photos leave the PC only when the owner chooses a cloud model.
