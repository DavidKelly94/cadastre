# VividHome feasibility assessment

Written 2026-09-11 from that day's research notes and the approved plan. Figures are quoted from the cited sources; unverified items are collected in section 9.

## 1. Question and verdict

**Question.** Can one person with an iPhone 15 Pro, PDF and paper plans and an RTX 4070 Super PC photograph a house during framing and MEP rough-in, map the captures onto the plans, and years later open a 3D view of any construction state to find studs, pipes, gas lines, ducts and wires behind finished walls, with capture ready in two weeks?

**Verdict: doable.** Capture, scale and location, and cross-phase alignment are solved by the phone plus discipline (one room per session, printed markers, tapped landmarks); reconstruction, AI labeling and the viewer are offline work once the data is safe. Capture is the only non-recoverable part, so the two-week MVP is the capture app, markers, protocol and minimal alignment, with a fallback recorder documented from day one.

## 2. What the iPhone provides

**APIs.** ARKit gained no headline iOS APIs in iOS 26 or 27 [1] and is effectively frozen. Each frame carries a metric, gravity-aligned 6-DoF pose, intrinsics, a 1920x1440 colour image and, with `frameSemantics = [.sceneDepth]`, a 256x192 Float32 depth map in metres with per-pixel confidence (LiDAR only). `captureHighResolutionFrame` returns a posed full-resolution still. Scene reconstruction yields classified `ARMeshAnchor`s; `ARReferenceImage` detection (needing the printed image's physical size) is the on-device half of the marker system. RoomPlan is not used: it fits idealized planar walls (91% AP, 90% recall at 3D IoU 0.3 [2]) and one test saw a 6.45 m wall reported as 6.821 m [3].

**Devices.** Every Pro and Pro Max since the iPhone 12 Pro has LiDAR, no non-Pro model does, and the iPhone 18 Pro (announced 2026-09-09) is unverified but near-certain.

**Accuracy.** Apple publishes no spec; nominal range is about 5 m, usable to 4 m [4]. Measured: about 1 cm for features over 10 cm at object scale; about 3 cm horizontal and 7 mm vertical at room scale, with residuals up to 12 cm at longer range from drift [5]. ARKitScenes (5,047 scans, FARO ground truth) shows a working depth range of 0.5 to 6 m, median maximum near 2.4 m [6].

**Drift and failure modes.** ARKit was the most stable of four proprietary VIO systems, about 0.02 m/s relative pose error [7], yet a corridor test in the research notes found about 1.5 m of error after 19.1 m: centimetres inside one room, up to a metre across a house. Hence one room per session (2 to 5 minutes, hard stop at 10) and offline tying through markers. Blank walls drop tracking to `limited`, so bare drywall, low light and repetitive stud bays make the post-drywall visit the hard capture; heat caps sessions at minutes (throttle at thermal `serious`, stop at `critical`).

**Why not Android, cross-platform or WebXR.** ARCore depth is depth-from-motion and imprecise on featureless walls, and hardware ToF exists on about ten models, none newer than the Galaxy S20 generation, so Android cannot do metric depth capture. Only Unity AR Foundation exposes LiDAR depth, intrinsics and poses cross-platform; ViroReact and the dead `ar_flutter_plugin` do not, and Safari implements no WebXR. Native Swift plus ARKit is the shortest path (ADR 0001).

**Fallback recorders.** NeRFCapture (free) [8], Stray Scanner (open-source tooling; price unverified) [9] or Record3D (about $5 export unlock) [10] can run the same protocol if the app slips.

## 3. Scale and relative location

ARKit poses are metric and gravity-aligned, so scale is free and up is known; placing a session on a plan is a 2D rigid transform per level, SE(2): x, y, yaw, plus a floor-height offset, as in floor-plan localization research [11].

The MVP aligns by hand, as magicplan and OpenSpace do: the owner taps room corners and door thresholds on site (raycast landmarks) and pairs them with plan corners in a local web page, and a Umeyama fit without scale gives the SE(2) (ADR 0007). Automatic refinement is deferred but charted: LiDAR-mesh wall lines matched to plan walls with horizontality-constrained ICP (0.044 m in one indoor pipeline in the research notes; zero-shot Z-FLoc reports 100% success on unseen buildings [11]).

Radio does not help: GNSS is unusable indoors, BLE beacons give 3 to 5 m, Wi-Fi RTT 0.6 to 1 m, and UWB is sub-30 cm but the iPhone exposes it only for device-to-device ranging; none places a photo on a plan at the few-centimetre level needed.

The plan is not the truth: framing tolerance allows 3/8 in out of plumb over 32 in and 1/8 in between adjacent members, so 1 to 2 in as-built discrepancies are normal; alignment fits the scan's landmarks and the viewer shows residuals. The stair is the only reliable inter-floor tie, so shared markers go at stair landings.

## 4. Aligning across construction phases

**Why ARWorldMap and Cloud Anchors fail.** Both are visual-feature relocalizers: Apple warns the session can remain "in the relocalizing state indefinitely", ARCore needs the device to see the same environment, and Cloud Anchors expire after 1 to 365 days. Framing to drywall destroys essentially every feature point; relocalization degrades with appearance change even without construction [12]. Rejected (ADR 0006).

**Fiducials.** The research notes give measured AprilTag accuracy for a 16.4 cm tag of 1.6 to 3.4 cm and 0.8 to 3.2 degrees at 2 m, degrading to 5.8 to 12.4 cm and up to 8 degrees at 3 m; 10 to 20 cm tags stop being detected beyond about 4 m. So markers are photographed square-on from about 1 m, every session sees at least two, and the pipeline aggregates PnP poses over many observations. VividHome's marker is a 20 cm laminated matte sheet with a 12.8 cm AprilTag 36h11 and a high-detail ring for ARKit's image-detail check; `physicalWidth` must be exact. Markers go where the surface survives the next phase (subfloor, top plates, jambs, slab, sheathing), are never moved, and their position is recorded relative to an invariant feature for re-hanging. Phases chain through marker IDs, as in US patents 11348322 and 12223613 [13].

**The plan as the invariant frame.** Each phase is also aligned independently to the plan and cross-checked against geometry that never changes (rough openings, room corners, stair nosings); scan-versus-BIM work in the research notes reports 2 cm RMSE for such checks and warns that ICP fails vertically when floors change, so Z comes from the level height. The finished house, every marker covered, aligns through openings and corners alone.

## 5. Reconstruction options and the chosen staging

| Option | Cost on the owner's GPU class | Role and timing |
|---|---|---|
| Photogrammetry (COLMAP, GLOMAP, RealityScan, Meshroom) | About 1 h dense MVS on a small set on an RTX 4090 [14]; no consumer-GPU benchmark at 1,000 to 3,000 images | Not the default (ADR 0009) |
| LiDAR mesh (ARKit mesh, then Open3D TSDF) | Minutes on CPU; few-cm walls, poor fine detail | Metric skeleton, weeks 1 to 2 |
| Posed photos plus depth | None | Truth for anything thin |
| Gaussian splats (gsplat, Splatfacto, Postshot) as SOG | 30k iterations in 8 to 12 min on a 4090, 25 to 30 min on a 3060, about 6 GB VRAM [15][16]; estimated 15 to 20 min per room on the 4070 Super | Visual layer, weeks 3+ |
| Feed-forward (MapAnything, Depth Anything 3) | Seconds per room; attention cost is O((NL)^2), so per room then stitch [17] | Optional densification, weeks 3+ |

Construction interiors are the documented photogrammetry failure case ("large textureless walls, repetitive layouts, and partial or evolving structures exacerbate the challenges of pose estimation" [18]); GLOMAP is 3.5x faster than COLMAP [19] and RealityScan (free under $1M revenue) imports SLAM trajectories [20], but with ARKit poses already known, photogrammetry stays an experiment.

Splats are a visual layer: Postshot is free since September 2025 [16], SOG is 15 to 20x smaller than PLY (1 GB of 4M Gaussians becomes 55 MB) [21], the viewer is three.js plus Spark (v2.2.0, MIT) [22], and a whole house needs room-chunked streaming since devices render 1 to 5M splats.

Feed-forward models are the new option: MapAnything (Apache-2.0 code, Apache weights variant) ingests known intrinsics, poses and depth and outputs metric geometry [23]; Depth Anything 3 (2025-11-14) beats VGGT by 44.3% on pose and 25.1% on geometry, and `DA3METRIC-LARGE` is Apache-2.0 [24].

**Thin-structure caveat.** No study quantifies splat fidelity on wires, conduit or thin pipe; splats are photometric blobs, so a 2 px cable renders plausibly without reliable geometry, and a 256x192 depth map cannot resolve 1/2 in PEX or 12 AWG cable either. VividHome locates those from posed stills (pixel, depth ray, house-frame point, plan), never from a mesh or splat, hence the mandatory square-on stills with a tape.

## 6. AI labeling reality

The ISARC 2025 study on open-vocabulary detection of MEP elements [25] is the benchmark: a fine-tuned YOLO11-nano beat the best open-vocabulary model, Grounding DINO, by over 85% in precision, 82% in recall and 86% in F1 at 23.36 FPS. Grounding DINO 1.6 Pro (55.4 AP zero-shot on COCO [26]) and SAM 3 (2025-11-19, promptable concept segmentation [27]) are annotation accelerators, not production detectors for "1/2 in CSST gas line". No public dataset covers studs, outlets, boxes or PEX, and VLMs read plans badly: ArchPlanVQA puts them at 33.03 to 37.88% semantic accuracy on architectural CAD plans [28].

So labeling is assistive (ADR 0010): a vision LLM proposes tags as candidates, SAM 3 turns a tap into a mask, the owner confirms, and the mask is projected through LiDAR depth into 3D (about 90% as good as research lifting methods for 5% of the work); a small YOLO11 fine-tuned on confirmed labels comes later.

## 7. Floor-plan ingestion

Vector PDFs are the happy path (pdfplumber exposes lines, rects, curves and edges [29]); raster parsing is weaker, with CubiCasa5K still the default dataset in 2026 [30]; and VLMs cannot be trusted for scale or dimensions [28]. So the decision (ADR 0014) is a calibrated raster per level: `vividhome plan add` rasterizes a PDF page with pypdfium2 at 150 to 200 dpi or takes a photo of a paper plan with optional perspective correction, and `vividhome plan calibrate` has the owner click two points, type the dimension between them, and set north and the level height. Two-point calibration is about ten lines of code and correct.

## 8. Existing products and build versus buy

| Product (capture device) | Price for one house | Plan pins / phase compare | iPhone only |
|---|---|---|---|
| OpenSpace, DroneDeploy Ground, HoloBuilder (360 camera) [31][32][33] | $10k minimum, percent of construction volume, "not the right fit for residential builders"; $4,188/yr; from $125 per user per month. Cupix, Buildots, Doxel, Track3D and Procore quote enterprise prices (Procore $15 to 80k/yr) | Automatic / yes | No |
| Matterport (iPhone 12 Pro+ LiDAR) [34] | Free (1 space), Starter about $10/mo, Pro about $69/mo; pro scan $400 to 1,000 | Auto plan, Mattertags / separate spaces | Yes |
| Fieldwire, pin360 (phone) [35] | Fieldwire free up to 3 projects, Pro $54 per user per month; pin360 free with 20 pins, GBP 19 to 29/mo | Manual pins onto your PDF / manual | Yes |
| magicplan (phone) [36] | From $9.99/mo plus about $40 per project | Per room, imports a plan / no | Yes |

**Cheapest 80% route.** Free Matterport with the iPhone's LiDAR, one scan per phase as its own space, Mattertags on the panel, valves and shutoffs, plus Fieldwire free or pin360 to pin square-on wall photos to the PDF: $0 to 120 per year, plus an optional professional pre-drywall scan ($400 to 1,000).

**What VividHome adds.** One persistent coordinate frame so every phase overlays every other phase and the plan, AR see-through later on the same alignment, and open data that outlives any vendor subscription; nothing on the market gives a homeowner that at consumer prices.

**Purpose-built apps.** AsBuilt ("Carfax for homes") captures before insulation, full service or DIY; in pilot, price unpublished [37]. RecordSet is a free homeowner photo-record app for "conditions behind walls" with paid hosting [38]. iGUIDE sells "See Behind The Walls" shoots at about $250 to 400 [39]; Walabot DIY 2 ($149.95) is an RF wall scanner good to about 4 in [40]. All are photo records without a metric frame. Building is therefore reasonable, with the buy route above as the day-one fallback.

## 9. Open questions and unverified items

- iPhone 18 Pro LiDAR: spec sheet not checked.
- Splat fidelity on wires, conduit and thin pipe: no quantitative study.
- Wall-clock on a 4070 Super: the 15 to 20 min per room splat figure is interpolated.
- AprilTag figures are for a 16.4 cm tag; VividHome's 12.8 cm tag and ARKit `detectionImages` on AprilTag artwork need a device test.
- Figures from the research notes without a recorded URL (corridor drift, 0.044 m registration, 2 cm RMSE, AprilTag accuracy) should be re-sourced before external use.
- Grounding DINO 1.6 Pro pricing; Spark streaming details; RealityScan's free tier for a distributed hobby app.
- AsBuilt's price; OpenSpace, Cupix, Track3D and Buildots quotes; an OpenSpace iPhone-only mode; Matterport Starter's space count; Stray Scanner's price.

## 10. Sources

Accessed 2026-09-11 unless dated.

1. iOS 27 coverage. https://www.tomsguide.com/phones/iphones/ios-27-is-official-all-the-new-upgrades-and-features-announced-at-wwdc-2026 (2026-06-09)
2. Apple RoomPlan research. https://machinelearning.apple.com/research/roomplan
3. RoomPlan test. https://www.it-jim.com/blog/roomplan-framework-by-apple/
4. iPhone LiDAR data. https://www.it-jim.com/blog/iphones-12-pro-lidar-how-to-get-and-interpret-data/
5. iPad Pro LiDAR study. https://www.sciencedirect.com/science/article/pii/S2666165923000510 (2023)
6. ARKitScenes. https://arxiv.org/pdf/2111.08897
7. VIO benchmark, Sensors 2022. https://pmc.ncbi.nlm.nih.gov/articles/PMC9785098/ (identifier from research notes; not fetched)
8. NeRFCapture. https://apps.apple.com/us/app/nerfcapture/id6446518379 (updated 2026-05-17)
9. StrayVisualizer. https://github.com/kekeblom/StrayVisualizer (updated 2026-09-04)
10. Record3D. https://github.com/marek-simonik/record3d (updated 2026-08-27)
11. Z-FLoc. https://arxiv.org/abs/2606.04788 (2026-06-03)
12. Relocalization drift. https://arxiv.org/pdf/2008.02004
13. Patent 11348322. https://patents.google.com/patent/US11348322 (number from research notes; not fetched)
14. COLMAP MVS runtime. https://github.com/colmap/colmap/issues/3210
15. nerfstudio Splatfacto. https://docs.nerf.studio/nerfology/methods/splat.html
16. Postshot. https://radiancefields.com/platforms/postshot and https://www.polyvia3d.com/guides/gaussian-splatting-tutorial
17. Feed-forward scaling. https://arxiv.org/html/2605.17478
18. BIM-informed SLAM. https://arxiv.org/html/2509.13972v1 (2025-09)
19. GLOMAP. https://demuc.de/papers/pan2024glomap.pdf (ECCV 2024)
20. RealityScan 2.0. https://www.realityscan.com/news/realityscan-20-new-release-brings-powerful-new-features-to-a-rebranded-realitycapture (2025-06)
21. SOG compression. https://blog.playcanvas.com/playcanvas-adopts-sogs-for-20x-3dgs-compression/
22. Spark. https://github.com/sparkjsdev/spark
23. MapAnything. https://github.com/facebookresearch/map-anything
24. Depth Anything 3. https://github.com/bytedance-seed/depth-anything-3 (2025-11-14)
25. ISARC 2025 MEP study. https://arxiv.org/abs/2501.09267
26. Grounding DINO 1.6 Pro. https://visincept.com/en/blog/6
27. SAM 3. https://ai.meta.com/research/sam3/ (2025-11-19)
28. ArchPlanVQA. https://ascelibrary.com/doi/abs/10.1061/JCCEE5.CPENG-7571 (2026)
29. pdfplumber. https://github.com/jsvine/pdfplumber
30. CubiCasa5K. https://github.com/CubiCasa/CubiCasa5k
31. OpenSpace pricing. openspace.ai/smb-pricing-webpage and capterra.com/p/191822/OpenSpace
32. DroneDeploy pricing. dronedeploy.com/pricing and help.dronedeploy.com
33. HoloBuilder pricing. capterra.com/p/268432/HoloBuilder
34. Matterport pricing and guides. checkthat.ai/brands/matterport/pricing, matterport.com/blog/lidar-accuracy, support.matterport.com
35. pin360. pin360.io
36. magicplan plan import. help.magicplan.app/import-and-digitalize-an-existing-floor-plan
37. AsBuilt. asbuilt.dev
38. RecordSet. recordset.com
39. iGUIDE pricing. goiguide.com/pricing
40. Walabot DIY 2. walabot.com
