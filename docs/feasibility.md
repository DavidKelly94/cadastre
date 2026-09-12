# Igloo feasibility assessment

Written 2026-09-11 from the research notes compiled that day and the approved plan. Figures are quoted from the cited sources; anything unverified at source is flagged and collected in section 9.

## 1. Question and verdict

**Question.** Can one person with an iPhone 15 Pro, PDF and paper plans and an RTX 4070 Super PC photograph a house during framing and MEP rough-in, map the captures onto the plans, and years later open a 3D view of any construction state to find studs, pipes, gas lines, ducts and wires behind finished walls? Can capture be ready in two weeks?

**Verdict: doable.** Capture, scale and location, and cross-phase alignment are solved by the phone plus discipline (one room per session, printed markers, tapped landmarks). Reconstruction, AI labeling and the viewer are offline work once the data is safe. Capture is the only non-recoverable part, so the two-week MVP is the capture app, markers, protocol and a minimal alignment pipeline, with a fallback recorder documented from day one.

## 2. What the iPhone provides

**Platform.** iOS 26 (2025-09-15) and iOS 27 (announced 2026-06-09) added no headline ARKit-on-iOS APIs [1]; ARKit is mature and effectively frozen, which suits a tool that must work for years.

**APIs.** Each frame carries a metric, gravity-aligned 6-DoF pose, intrinsics, a 1920x1440 colour image and, with `frameSemantics = [.sceneDepth]`, a 256x192 Float32 depth map in metres with per-pixel confidence (LiDAR only, iOS 14+). `captureHighResolutionFrame` returns a full-resolution still with "pose information, anchors, and frame semantics". Scene reconstruction yields classified `ARMeshAnchor`s (wall, window, floor, ceiling, door). `ARReferenceImage` detection needs the printed image's physical size and is the on-device half of the marker system. RoomPlan is not used: it fits idealized planar walls (91% AP, 90% recall at 3D IoU 0.3 [2]), and one test saw a 6.45 m wall reported as 6.821 m, about 5 cm per metre compounding [3].

**Devices.** Every Pro and Pro Max since the iPhone 12 Pro has LiDAR; no non-Pro model does. LiDAR on the iPhone 18 Pro (announced 2026-09-09) is unverified but near-certain.

**Accuracy.** Apple publishes no spec. Nominal range is about 5 m, usable to 4 m [4]. Measured: about 1 cm for features over 10 cm at object scale; about 3 cm horizontal and 7 mm vertical at room scale, with residuals up to 12 cm at longer range from drift [5]. ARKitScenes (5,047 scans, FARO ground truth) shows a working depth range of 0.5 to 6 m, median maximum near 2.4 m [6]. Scan-to-BIM pipelines on this sensor class reach 10 to 20 cm (2 sigma) end to end.

**Drift.** Among four proprietary VIO systems ARKit was the most stable, about 0.02 m/s relative pose error [7]; a corridor test in the research notes still found about 1.5 m of error after 19.1 m. Practical read: a few centimetres inside one room, tens of centimetres to over a metre across a house. Hence one room per session (2 to 5 minutes, hard stop at 10) and offline tying through markers.

**Failure modes.** A blank wall drops tracking to `limited`; bare drywall, low light and repetitive stud bays are the worst cases, so the post-drywall return visit is the hard capture. Heat limits sessions to a few minutes; the health policy throttles at thermal state `serious` and stops at `critical`.

**Why not Android, cross-platform or WebXR.** ARCore depth is depth-from-motion and imprecise on featureless walls; hardware ToF exists on about ten models, none newer than the Galaxy S20 generation, so Android cannot do metric depth capture. Only Unity AR Foundation exposes LiDAR depth, intrinsics and poses cross-platform; ViroReact has no raw depth API, Flutter's `ar_flutter_plugin` died in 2022, and WebXR depth sensing is Chrome-only because Safari implements no WebXR on iOS. With one target platform, native Swift plus ARKit is the shortest path (ADR 0001).

**Fallback recorders.** If the app slips, the protocol works with NeRFCapture (free, updated 2026-05-17) [8], Stray Scanner (open-source tooling; price unverified) [9] or Record3D (about $5 export unlock) [10]; Polycam's raw export needs the $400/yr Business tier [11].

## 3. Scale and relative location

ARKit poses are metric and gravity-aligned with the origin at session start, so scale is free and up is known. Placing a session on a plan is a 2D rigid transform per level, SE(2): x, y, yaw, plus a floor-height offset; floor-plan localization research poses it the same way [12]. Compass heading is unreliable indoors near steel and is ignored.

The MVP aligns by hand, as magicplan and OpenSpace do. The owner taps room corners and door thresholds on site (raycast landmarks) and pairs them with plan corners in a local web page; a Umeyama fit without scale gives the SE(2) (ADR 0007). Automatic refinement is deferred but charted: extract wall lines from the LiDAR mesh and match them to plan walls with horizontality-constrained ICP (0.044 m in one indoor pipeline from the research notes); zero-shot Z-FLoc reports 100% success on unseen buildings [12].

Radio does not help: GNSS is unusable indoors, BLE beacons give 3 to 5 m, Wi-Fi RTT 0.6 to 1 m, and UWB is sub-30 cm but the iPhone exposes it only through NearbyInteraction for device-to-device ranging. None places a photo on a plan at the few-centimetre level needed.

The plan is not the truth: framing tolerance allows 3/8 in out of plumb over 32 in and 1/8 in between adjacent members, and 1 to 2 in drawing-to-as-built discrepancies are normal. Alignment fits the scan's landmarks to the plan and the viewer shows residuals. Multi-storey houses need one SE(2) per level; the stair is the only reliable inter-floor tie, so shared markers go at stair landings.

## 4. Aligning across construction phases

**Why ARWorldMap and Cloud Anchors fail.** Both are visual-feature relocalizers: Apple warns the session can remain "in the relocalizing state indefinitely", ARCore requires the device to "look at the same physical environment as the original hosted anchor", and Cloud Anchors expire after 1 to 365 days. Framing to drywall destroys essentially every feature point, and relocalization degrades with appearance change even without construction [13]. Rejected (ADR 0006).

**Fiducials.** Printed AprilTags survive because the detector reads a known geometric pattern. The research notes give measured accuracy for a 16.4 cm tag of 1.6 to 3.4 cm and 0.8 to 3.2 degrees at 2 m, degrading to 5.8 to 12.4 cm and up to 8 degrees at 3 m; 10 to 20 cm tags stop being detected beyond about 4 m. A 1 degree yaw error at 5 m is 8.7 cm, so each marker is photographed square-on from about 1 m, every session sees at least two, and the pipeline aggregates PnP poses over many observations (acceptance: under 3 cm spread). Igloo's marker is a 20 cm laminated matte sheet (glare kills detection) with a 12.8 cm AprilTag 36h11 and a high-detail ring for ARKit's image-detail check; `physicalWidth` must be exact. Markers go where the surface survives the next phase (subfloor at door thresholds, top plates, rough-opening jambs, panel area, slab, exterior sheathing), are never moved, and have their position recorded relative to an invariant feature so they can be re-hung. Phases chain through marker IDs, the method of US patents 11348322 and 12223613 [14].

**The plan as the invariant frame.** Each phase is also aligned independently to the plan and cross-checked against geometry that never changes: rough openings, room corners, stair nosings. 2025 scan-versus-BIM work in the research notes reports 2 cm RMSE for such checks and warns that ICP fails vertically when floors change between epochs, so Z comes from the level height. The finished house, with every marker covered, aligns through openings and corners alone.

## 5. Reconstruction options and the chosen staging

| Option | Cost on the owner's GPU class | Role |
|---|---|---|
| Photogrammetry (COLMAP, GLOMAP, RealityScan, Meshroom) | Dense MVS on a small set took about 1 h on an RTX 4090 [15]; no 1,000 to 3,000 image consumer-GPU benchmark published | Not the default (ADR 0009) |
| LiDAR mesh (ARKit mesh, later Open3D TSDF) | Minutes on CPU; few-cm walls, poor fine detail | Metric skeleton, weeks 1 to 2 |
| Posed photos plus depth | None | Truth for anything thin |
| Gaussian splats (gsplat, Splatfacto, Postshot) | 30k iterations in 8 to 12 min on a 4090, 25 to 30 min on a 3060, about 6 GB VRAM [16][17]; estimated 15 to 20 min per room on the 4070 Super | Visual layer, weeks 3+ |
| Feed-forward (MapAnything, Depth Anything 3) | Seconds per room; attention cost is O((NL)^2), so per room then stitch [18] | Optional densification |

Construction interiors are the documented photogrammetry failure case: "large textureless walls, repetitive layouts, and partial or evolving structures exacerbate the challenges of pose estimation" [19]. GLOMAP is about 3.5x faster than COLMAP [20] and RealityScan (free under $1M revenue) imports SLAM trajectories since 2.1 [21][22], but ARKit poses are an initializer to refine, not something to rediscover, and photogrammetry stays an experiment.

Splats are a visual layer. Postshot became free after September 2025 [17]; delivery is SOG, 15 to 20x smaller than PLY (a 1 GB, 4M-Gaussian scene becomes 55 MB) [23]; the viewer is three.js plus Spark (v2.2.0, MIT; reads PLY, SPZ and SOG) [24]. Consumer devices render 1 to 5M splats, so a whole house needs room-chunked streaming.

Feed-forward models are the new option: MapAnything (Apache-2.0 code, Apache weights variant) ingests known intrinsics, poses and depth and outputs metric geometry [25]; Depth Anything 3 (2025-11-14) beats VGGT by 44.3% on pose and 25.1% on geometry, and `DA3METRIC-LARGE` is Apache-2.0 [26]. The session format already stores everything they need.

**Thin-structure caveat.** No study quantifies splat fidelity on wires, conduit or thin pipe. Splats are view-dependent blobs optimized for photometric loss: a 2 px cable renders plausibly but has no reliable metric geometry, and a 256x192 depth map cannot resolve 1/2 in PEX or 12 AWG cable either. Igloo never trusts a mesh or splat for wires or small pipe; those are located from posed stills (pixel, depth ray, house-frame point, plan), which is why square-on stills with a tape are mandatory.

**Staging.** Weeks 1 to 2: posed keyframes, stills, depth, confidence and ARKit mesh per session. Weeks 3+: pose graph across markers, Open3D TSDF meshes, per-room splats seeded with ARKit poses and exported as SOG, feed-forward densification where LiDAR is sparse.

## 6. AI labeling reality

The ISARC 2025 study on open-vocabulary detection of MEP elements [27] is the benchmark: a fine-tuned YOLO11-nano beat the best open-vocabulary model, Grounding DINO, by over 85% in precision, 82% in recall and 86% in F1, ran at 23.36 FPS, and found cable-tray fittings no open-vocabulary model detected. Grounding DINO 1.6 Pro (55.4 AP zero-shot on COCO [28]) and SAM 3 (2025-11-19, promptable concept segmentation [29]) are annotation accelerators, not production detectors for "1/2 in CSST gas line". No public dataset covers studs, outlets, boxes or PEX; the closest are a drywall analysis paper [30] and the OpenConstruction synthetic dataset [31]. VLMs also read plans badly: ArchPlanVQA puts them at 33.03 to 37.88% semantic accuracy on architectural CAD plans [32].

So labeling is assistive (ADR 0010): a vision LLM proposes captions and tags as candidates, SAM 3 turns a tap into a mask, the owner confirms, and the mask is projected through LiDAR depth into 3D, about 90% as good as research lifting methods (OpenMask3D, LangSplat, OpenSplat3D) for 5% of the work. A small YOLO11 fine-tuned on a few hundred confirmed labels is the realistic route to automation. See `docs/ai-roadmap.md`.

## 7. Floor-plan ingestion

Vector PDFs are the happy path in principle (pdfplumber exposes lines, rects, curves and edges [33]); raster parsing is weaker, with CubiCasa5K still the default dataset in 2026 [34]; and VLMs cannot be trusted for scale or dimensions [32]. So the decision (ADR 0014) is a calibrated raster per level: `igloo plan add` rasterizes a PDF page with pypdfium2 at 150 to 200 dpi or takes a photo of a paper plan with optional perspective correction; `igloo plan calibrate` has the owner click two points, type the dimension between them, and set north and the level height. Two-point calibration is about ten lines of code and correct. Scan-to-plan alignment then needs 2 to 3 picked corner correspondences; wall-line ICP and vector walls are later refinements.

## 8. Existing products and build versus buy

| Product | Price for one house | Capture | Plan pins / phase compare | iPhone only |
|---|---|---|---|---|
| OpenSpace [35] | Percent of construction volume, $10k minimum; "not the right fit for residential builders" | 360 camera | Automatic / yes | No |
| DroneDeploy Ground [36] | $4,188/yr self-serve | 360 camera | Yes / yes | No |
| HoloBuilder [37] | From $125 per user per month | 360 camera | Yes / yes | No |
| Matterport [38] | Free (1 space), Starter about $10/mo, Pro about $69/mo; pro scan $400 to 1,000 | iPhone 12 Pro+ LiDAR | Auto plan, Mattertags / separate spaces | Yes |
| Fieldwire | Free up to 3 projects; Pro $54 per user per month | Phone | Manual pins / manual | Yes |
| pin360 [39] | Free with 20 pins; GBP 19 to 29/mo | Phone or 360 | Onto your PDF / manual | Yes |
| Polycam [40] | Pro $26.99/mo or $199.99/yr | iPhone LiDAR | No / no | Yes |
| magicplan [41] | From $9.99/mo plus about $40 per project | Phone | Photos per room, imports a plan / no | Yes |

Cupix, Buildots, Doxel, Track3D and Procore sell on enterprise quotes (Procore $15 to 80k/yr) with 360 cameras.

**Cheapest 80% route.** Free Matterport with the iPhone's LiDAR, one scan per phase as its own space, Mattertags on the panel, valves and shutoffs, plus Fieldwire free or pin360 to pin square-on wall photos to the PDF: $0 to 120 per year, plus an optional professional pre-drywall scan ($400 to 1,000) as insurance. Most of the value with zero code, and the fallback if Igloo stalls.

**What Igloo adds.** One persistent coordinate frame so every phase overlays every other phase and the plan; AR see-through later on the same alignment; open data that outlives any vendor subscription. Nothing on the market gives a homeowner that at consumer prices.

**Purpose-built apps.** AsBuilt ("Carfax for homes") captures before insulation as a full service or DIY app; in pilot, price unpublished [42]. RecordSet is a free homeowner photo-record app for "conditions behind walls" with paid hosting [43]. iGUIDE sells "See Behind The Walls" shoots at about $250 to 400 [44]; Walabot DIY 2 ($149.95) is an RF wall scanner good to about 4 in [45]. All are photo records without a metric frame; none aligns phases to each other or to the plan. Given the product ambition, building is reasonable; capture readiness comes first and the buy route is the documented fallback.

## 9. Open questions and unverified items

- iPhone 18 Pro LiDAR: spec sheet not checked.
- Splat fidelity on wires, conduit and thin pipe: no quantitative study.
- COLMAP/GLOMAP and splat wall-clock on a 4070 Super: the 15 to 20 min per room figure is interpolated.
- AprilTag figures are for a 16.4 cm tag; Igloo's 12.8 cm tag and ARKit `detectionImages` on AprilTag artwork need a device test.
- Figures quoted from the research notes without a recorded URL (corridor drift, 10 to 20 cm scan-to-BIM, 0.044 m registration, 2 cm RMSE, AprilTag accuracy) should be re-sourced before external use.
- Grounding DINO 1.6 Pro pricing; Spark streaming details; RealityScan's free tier for a distributed hobby app.
- Product facts: AsBuilt's price; OpenSpace, Cupix, Track3D and Buildots quotes; an OpenSpace iPhone-only mode; Matterport Starter's space count; Stray Scanner's price.
- developers.google.com, apple.com, macrumors, 9to5mac, learn.poly.cam and ncbi were blocked by the research proxy; Apple API facts came from developer.apple.com's tutorial data feed.
- Apple Developer enrollment time (about 24 h per Apple; 2026 reports range to days), hence day-0 enrollment.

## 10. Sources

Accessed 2026-09-11 unless a publication or update date is given.

1. iOS 27 at WWDC 2026. https://www.tomsguide.com/phones/iphones/ios-27-is-official-all-the-new-upgrades-and-features-announced-at-wwdc-2026 (2026-06-09)
2. Apple RoomPlan research. https://machinelearning.apple.com/research/roomplan
3. RoomPlan test. https://www.it-jim.com/blog/roomplan-framework-by-apple/
4. iPhone LiDAR data. https://www.it-jim.com/blog/iphones-12-pro-lidar-how-to-get-and-interpret-data/
5. iPad Pro indoor mapping study. https://www.sciencedirect.com/science/article/pii/S2666165923000510 (2023)
6. ARKitScenes. https://arxiv.org/pdf/2111.08897
7. VIO benchmark, Sensors 2022. https://pmc.ncbi.nlm.nih.gov/articles/PMC9785098/ (identifier from research notes; not fetched)
8. NeRFCapture. https://apps.apple.com/us/app/nerfcapture/id6446518379 (updated 2026-05-17)
9. StrayVisualizer. https://github.com/kekeblom/StrayVisualizer (updated 2026-09-04)
10. Record3D. https://github.com/marek-simonik/record3d (updated 2026-08-27)
11. Polycam polyform. https://github.com/PolyCam/polyform
12. Z-FLoc. https://arxiv.org/abs/2606.04788 (2026-06-03)
13. Relocalization under appearance change. https://arxiv.org/pdf/2008.02004
14. US patent 11348322. https://patents.google.com/patent/US11348322 (number from research notes; not fetched)
15. COLMAP dense MVS runtime. https://github.com/colmap/colmap/issues/3210
16. nerfstudio Splatfacto. https://docs.nerf.studio/nerfology/methods/splat.html
17. Postshot. https://radiancefields.com/platforms/postshot and https://www.polyvia3d.com/guides/gaussian-splatting-tutorial
18. Feed-forward scaling. https://arxiv.org/html/2605.17478
19. BIM-Informed Visual SLAM. https://arxiv.org/html/2509.13972v1 (2025-09)
20. GLOMAP. https://demuc.de/papers/pan2024glomap.pdf (ECCV 2024)
21. RealityScan 2.0. https://www.realityscan.com/news/realityscan-20-new-release-brings-powerful-new-features-to-a-rebranded-realitycapture (2025-06)
22. RealityScan 2.2. https://www.cgchannel.com/2026/06/epic-games-releases-realityscan-2-2-with-amd-gpu-support/ (2026-06)
23. SOG compression. https://blog.playcanvas.com/playcanvas-adopts-sogs-for-20x-3dgs-compression/
24. Spark. https://github.com/sparkjsdev/spark
25. MapAnything. https://github.com/facebookresearch/map-anything
26. Depth Anything 3. https://github.com/bytedance-seed/depth-anything-3 (2025-11-14)
27. Open-vocabulary MEP detection, ISARC 2025. https://arxiv.org/abs/2501.09267
28. Grounding DINO 1.6 Pro. https://visincept.com/en/blog/6
29. SAM 3. https://ai.meta.com/research/sam3/ (2025-11-19)
30. Automatic Drywall Analysis, VISAPP 2025. https://arxiv.org/abs/2503.03422
31. OpenConstruction. https://arxiv.org/pdf/2508.11482 (2025-08)
32. ArchPlanVQA. https://ascelibrary.com/doi/abs/10.1061/JCCEE5.CPENG-7571 (2026)
33. pdfplumber. https://github.com/jsvine/pdfplumber
34. CubiCasa5K. https://github.com/CubiCasa/CubiCasa5k
35. OpenSpace pricing. openspace.ai/smb-pricing-webpage and capterra.com/p/191822/OpenSpace
36. DroneDeploy pricing and StructionSite migration. dronedeploy.com/pricing and help.dronedeploy.com
37. HoloBuilder pricing. capterra.com/p/268432/HoloBuilder
38. Matterport pricing, LiDAR accuracy, job-site guide. checkthat.ai/brands/matterport/pricing, matterport.com/blog/lidar-accuracy, support.matterport.com
39. pin360. pin360.io
40. Polycam, App Store id1532482376. apps.apple.com
41. magicplan plan import. help.magicplan.app/import-and-digitalize-an-existing-floor-plan
42. AsBuilt. asbuilt.dev
43. RecordSet. recordset.com
44. iGUIDE pricing. goiguide.com/pricing
45. Walabot DIY 2. walabot.com
