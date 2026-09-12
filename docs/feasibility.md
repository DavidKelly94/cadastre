# Igloo feasibility assessment

Written 2026-09-11 from the research notes compiled that day and the approved plan. Numbers are quoted from the cited sources; anything the research could not check at source is marked unverified and collected in section 9.

## 1. Question and verdict

**Question.** Can one person with an iPhone 15 Pro, PDF and paper plans and a PC with an RTX 4070 Super photograph a house during framing, electrical, plumbing and HVAC rough-in, map those captures onto the architectural plans, and years later open a 3D view of any construction state to find studs, pipes, gas lines, ducts and wires behind finished walls? Can the capture side be ready in two weeks?

**Verdict: doable.** There are six pieces: capture, scale and location, cross-phase alignment, reconstruction, AI labeling and a viewer. The first three are solved by the phone plus discipline (one room per session, printed markers, tapped landmarks). The last three are offline work on the PC that can happen after the data is safe. The only non-recoverable part is capture: once drywall goes up the information is gone. So the two-week MVP is a capture app, a marker kit, a protocol and a minimal alignment pipeline, with a documented fallback recorder from day one.

## 2. What the iPhone provides

**Platform.** iOS 26 shipped 2025-09-15 and iOS 27 was announced at WWDC on 2026-06-09; neither added headline ARKit-on-iOS APIs, and Apple's AR effort has moved to visionOS and RealityKit [1]. ARKit for iOS is mature and effectively frozen, which suits a tool that has to keep working for years.

**APIs used.** Per frame, `ARWorldTrackingConfiguration` delivers a metric, gravity-aligned 6-DoF camera pose, the intrinsics, a 1920x1440 colour image and, with `frameSemantics = [.sceneDepth]`, a 256x192 Float32 depth map in metres plus a per-pixel confidence map (LiDAR only, iOS 14+). `captureHighResolutionFrame` returns a full-resolution still and, in Apple's words, "populates the frame's properties other than pixel data, including pose information, anchors, and frame semantics", so stills are posed. Scene reconstruction yields `ARMeshAnchor`s with per-face classification (wall, window, table, seat, floor, ceiling, door), though Apple notes mesh updates are "not intended to reflect in real time". `ARReferenceImage` detection needs the printed image's physical size and is the on-device half of the marker system. RoomPlan (iOS 16+, LiDAR only) is not used: it fits idealized planar walls (Apple reports 91% AP and 90% recall at 3D IoU 0.3 [2]), and an independent test saw a 6.45 m wall reported as 6.821 m, about plus or minus 5 cm per metre compounding [3]. Object Capture is for objects, not houses.

**Devices.** Every Pro and Pro Max since the iPhone 12 Pro (2020) has LiDAR; no non-Pro iPhone does, including the iPhone 17, 17e and Air. The iPhone 18 Pro was announced 2026-09-09; that its spec sheet lists LiDAR is unverified but near-certain after six years of continuity.

**Accuracy.** Apple publishes no accuracy spec. Nominal LiDAR range is about 5 m, usable to about 4 m [4]. Measured: about plus or minus 1 cm for features larger than 10 cm at object scale; about plus or minus 3 cm horizontal and 7 mm vertical at room scale in good conditions, with residuals up to 12 cm at longer range because of drift [5]. Apple's ARKitScenes dataset (5,047 scans, FARO ground truth) confirms a working depth range of about 0.5 to 6 m with a median maximum near 2.4 m [6]. Scan-to-BIM pipelines on this sensor class land at 10 to 20 cm (2 sigma) end to end.

**Drift.** In a benchmark of four proprietary VIO systems ARKit was the most stable at about 0.02 m/s relative pose error [7]; a corridor test in the research notes still found about 1.5 m of error after a 19.1 m walk for ARKit versus about 0.5 m for ARCore. Practical read: a few centimetres inside one room, tens of centimetres to more than a metre over a whole-house walk. Hence one room per session (2 to 5 minutes, hard stop at 10) and offline tying of sessions through markers.

**Failure modes.** Pointing at a blank wall drops tracking to `limited`. Bare drywall, low light and repetitive stud bays are the worst cases; unfinished framing is feature-rich, so the post-drywall return visit is the hard capture. Long sessions heat the phone: Apple's own RoomPlan guidance keeps sessions under about 5 minutes, and Igloo's health policy doubles keyframe thresholds at thermal state `serious` and stops at `critical`.

**Why not Android, cross-platform or WebXR.** ARCore's Depth API is depth-from-motion, best between 0.5 and 5 m and imprecise on featureless walls; as of May 2026 over 88% of active ARCore devices support it, almost all in software. Hardware ToF exists on about ten models, none newer than the Galaxy S20 generation; the S25 Ultra and S26 have neither ToF nor LiDAR. Android cannot do metric depth capture for this job. Of the cross-platform stacks only Unity AR Foundation 6.x exposes LiDAR depth, intrinsics and per-frame poses; ViroReact has no raw depth or mesh API, Flutter's `ar_flutter_plugin` has been dead since November 2022, and the WebXR depth-sensing draft (W3C, 2025-12-10) ships only in Chrome and Android XR because Safari implements no WebXR on iOS. With one target platform, native Swift plus ARKit is the shortest path (ADR 0001).

**Fallback recorders.** If the app slips, the same protocol works with a free ARKit raw recorder: NeRFCapture (free; App Store build 2026-05-17, repository 2026-08-19) [8], Stray Scanner with its open-source StrayVisualizer tooling (RGB, metric depth, confidence, intrinsics, odometry, IMU; app price unverified) [9], or Record3D (`.r3d` with JSON poses and intrinsics, about $5 export unlock, read natively by nerfstudio) [10]. Polycam's raw export needs the $400/yr Business tier [11] and Scaniverse exports no per-frame depth.

## 3. Scale and relative location

ARKit poses are metric and gravity-aligned with the origin at session start, so scale is free and "up" is known. Placing a session on a plan is therefore a 2D rigid transform per level, SE(2): x, y and yaw, plus a floor-height offset. Floor-plan localization research poses the problem the same way [12]. Compass heading (`.gravityAndHeading`) is unreliable indoors near steel and is ignored; yaw comes from correspondences.

The MVP does this by hand, which is also what commercial tools do: magicplan has the user place a scale on a known measurement, OpenSpace asks for a start point on the plan and a heading. In Igloo the owner taps room corners and door thresholds on site (raycast landmarks with labels), then pairs them with plan corners in a local web page; a Umeyama fit without scale gives the SE(2) (ADR 0007). Automatic refinement is deferred but well charted: slice the LiDAR mesh horizontally, extract wall lines and match them to plan walls with horizontality-constrained ICP. One indoor pipeline in the research notes reports 0.044 m registration accuracy, and the zero-shot Z-FLoc method (2026-06-03) reports 100% success on unseen buildings from a bird's-eye line projection [12].

Radio positioning does not help. GNSS is unusable indoors; BLE beacons give 3 to 5 m; Wi-Fi RTT about 0.6 to 1 m; UWB is sub-30 cm but the iPhone exposes it only through NearbyInteraction for device-to-device ranging, so it would need installed anchors. None places a photo on a plan at the few-centimetre level the use case needs. VIO plus LiDAR odometry, loop-closed offline and anchored by markers and explicit alignment, is the only workable path.

The plan is not the truth. Residential framing tolerance allows 3/8 in out of plumb over 32 in and 1/8 in between adjacent members, and 1 to 2 in discrepancies between drawing and as-built are normal. The alignment fits the scan's landmarks to the plan and the viewer shows the residuals; the scan is the record, the plan is the reference frame. Multi-storey houses need one SE(2) per level, and the stair is the only reliable inter-floor tie, so shared markers go at stair landings.

## 4. Aligning across construction phases

**Why ARWorldMap and Cloud Anchors fail.** Both are visual-feature relocalizers. Apple: "If ARKit cannot reconcile the recorded world map with the current environment ... the session remains in the relocalizing state indefinitely." ARCore requires the device to "look at the same physical environment as the original hosted anchor", and Cloud Anchors expire after 1 to 365 days. Framing to drywall destroys essentially every feature point, and relocalization degrades with appearance change over weeks and months even without construction [13]. Rejected (ADR 0006).

**Fiducials.** Printed AprilTags survive because the detector reads a known geometric pattern, not learned features. The research notes give measured accuracy for a 16.4 cm tag of about 1.6 to 3.4 cm in position and 0.8 to 3.2 degrees at 2 m, degrading to 5.8 to 12.4 cm and up to 8 degrees at 3 m; 10 to 20 cm tags stop being detected beyond about 4 m. A 1 degree yaw error at 5 m is already 8.7 cm, so the protocol photographs each marker square-on from about 1 m, every session sees at least two markers, and the pipeline aggregates PnP poses over many observations (acceptance: under 3 cm spread). Igloo's marker is a 20 cm laminated matte sheet (glare kills detection) carrying a 12.8 cm AprilTag 36h11 plus a high-detail ring that satisfies ARKit's image-detail check for on-device `detectionImages`, whose `physicalWidth` must be entered exactly; larger markers track far better. Markers go on surfaces that survive the next phase: subfloor at door thresholds, top plates, rough-opening jambs, the panel area, slab and exterior sheathing. A placed marker is never moved, and its position is recorded relative to an invariant feature so it can be re-hung. Phases chain through marker IDs, the method of US patents 11348322 and 12223613, "Tracking an ongoing construction by using fiducial markers" [14].

**The plan as the invariant frame.** Markers are belt; the plan is braces. Each phase is aligned independently to the plan and cross-checked against geometry that does not change: rough openings, room corners, stair nosings. 2025 scan-versus-BIM work in the research notes reports 2 cm RMSE for this kind of check, with the warning that ICP fails vertically when floor surfaces change between epochs (subfloor, then finish floor), so Z is taken from the level height rather than fitted. The finished house, where every marker is covered, aligns through openings and corners alone.

## 5. Reconstruction options and the chosen staging

| Option | What it gives | Cost on the owner's GPU class | Role in Igloo |
|---|---|---|---|
| Photogrammetry (COLMAP, GLOMAP, RealityScan, Meshroom) | Geometry from photos alone | Dense MVS on a small set took about 1 h on an RTX 4090 [15]; no 1,000 to 3,000 image consumer-GPU benchmark published | Not the default (ADR 0009) |
| LiDAR mesh (ARKit mesh, later Open3D TSDF) | Few-cm walls, floors, openings; about 5 m range; poor fine detail | Seconds to minutes, CPU | Metric skeleton, weeks 1 to 2 |
| Posed photos plus depth | Pixel to depth ray to point on the plan | None | Source of truth for anything thin |
| Gaussian splats (gsplat, nerfstudio Splatfacto, Postshot) | Photorealistic view synthesis | 30k iterations in 8 to 12 min on a 4090, 25 to 30 min on a 3060, about 6 GB VRAM [16][17]; estimated 15 to 20 min per room on the 4070 Super | Visual layer per room, weeks 3+ |
| Feed-forward (MapAnything, Depth Anything 3, pi3) | Dense metric geometry from a set of frames | Seconds per room; attention cost grows as O((NL)^2), so per room then stitch [18] | Optional densification, weeks 3+ |

Construction interiors are the documented failure case for photogrammetry: "large textureless walls, repetitive layouts, and partial or evolving structures exacerbate the challenges of pose estimation", and repetitive structures fold onto themselves [19]. GLOMAP is about 3.5x faster than COLMAP at equal or better accuracy [20], and COLMAP can take ARKit poses as priors, but field reports are rough, so ARKit poses are an initializer to refine rather than something to rediscover. RealityScan is free under $1M annual revenue and $1,250 per seat above; 2.1 (November 2025) imports SLAM trajectories and COLMAP scenes, and 2.2 shipped 2026-06-24 [21][22]. All of this stays available as an experiment, not a dependency.

Splats are the visual layer only. Postshot became free across all tiers after September 2025 [17], and delivery is SOG, 15 to 20x smaller than PLY (a 1 GB, 4M-Gaussian scene becomes 55 MB), produced with the open `splat-transform` CLI [23]. The viewer is three.js plus Spark (v2.2.0, MIT; reads PLY, SPZ, SPLAT, KSPLAT and SOG over WebGL2 and WebXR) [24]; the older GaussianSplats3D library is no longer developed and points to Spark. Consumer devices render 1 to 5M splats interactively, so a whole house needs room-chunked streaming.

Feed-forward models are the interesting new option. MapAnything (3DV 2026; Apache-2.0 code with an Apache weights variant) optionally ingests known intrinsics, poses and depth and outputs metric geometry [25]; Depth Anything 3 (2025-11-14) beats VGGT by 44.3% on pose and 25.1% on geometry, and its `DA3METRIC-LARGE` weights are Apache-2.0 [26]. They slot in after the MVP because the session format already stores everything they take as input.

**Thin-structure caveat.** No study quantifies splat fidelity on wires, conduit or thin pipe. Splats are view-dependent blobs optimized for photometric loss: a 2 px cable renders plausibly but carries no reliable metric geometry, and a 256x192 depth map cannot resolve 1/2 in PEX or 12 AWG cable either. Igloo therefore never trusts a mesh or a splat for wires or small pipe; those are located from posed stills (pixel, depth ray, point in the house frame, plan). This is why square-on stills with a tape measure are mandatory in the protocol.

**Staging.** Weeks 1 to 2: posed keyframes, stills, depth, confidence and the ARKit mesh per session. Weeks 3+: pose graph across markers (scipy or GTSAM), Open3D TSDF meshes, per-room splats seeded with ARKit poses and exported as SOG, feed-forward densification where the LiDAR is sparse.

## 6. AI labeling reality

The relevant benchmark is the ISARC 2025 study "Are Open-Vocabulary Models Ready for Detection of MEP Elements on Construction Sites" [27]: a fine-tuned YOLO11-nano beat the best open-vocabulary model, Grounding DINO, by more than 85% in precision, 82% in recall and 86% in F1, ran at 23.36 FPS, and found cable-tray fittings that no open-vocabulary model detected. Grounding DINO 1.6 Pro (55.4 AP zero-shot on COCO [28]) and SAM 3 (2025-11-19, promptable concept segmentation [29]) are annotation accelerators, not production detectors for "1/2 in CSST gas line". There is no public dataset of studs, outlets, junction boxes or PEX; the closest are an automatic drywall analysis paper (VISAPP 2025) [30] and the OpenConstruction synthetic dataset (August 2025) [31]. Vision-language models also read plans badly: ArchPlanVQA finds general-purpose VLMs at 33.03 to 37.88% semantic accuracy on architectural CAD plans [32].

So labeling is assistive (ADR 0010): a vision LLM proposes captions and tags stored as candidates, SAM 3 turns a tap into a mask, the owner confirms, and the mask is projected through LiDAR depth into 3D. Ray-casting 2D masks through ARKit depth is about 90% as good as the research lifting methods (OpenMask3D, LangSplat, Gaussian Grouping, OpenSplat3D) for about 5% of the work. Once a few hundred confirmed labels exist, a small YOLO11 detector fine-tuned on them is the realistic route to automation. Details are in `docs/ai-roadmap.md`.

## 7. Floor-plan ingestion

Vector PDFs are the happy path in principle: pdfplumber exposes lines, rects, curves and edges [33]. Raster plan parsing is weaker; CubiCasa5K is still the default dataset in 2026, which is a warning sign [34]. And VLMs cannot be trusted for scale or dimensions [32].

The decision (ADR 0014) is to treat every plan as a calibrated raster per level: `igloo plan add` rasterizes a PDF page with pypdfium2 at 150 to 200 dpi, or takes a photo of a paper plan with optional four-corner perspective correction; `igloo plan calibrate` asks the owner to click two points and type the dimension string between them, then set north and the level height. Two-point calibration is about ten lines of code and is correct, which the automatic alternatives are not. Scan-to-plan alignment then needs only 2 to 3 user-picked corner correspondences; wall-line ICP and vector wall extraction are later refinements.

## 8. Existing products and build versus buy

| Product | Price for one house | Capture | Pin to plan | Phase compare | iPhone only |
|---|---|---|---|---|---|
| OpenSpace [35] | Percent of construction volume, $10k minimum; $2 to 5k per project per month cited; "not the right fit for residential builders" | 360 camera | Yes, automatic | Yes | No |
| DroneDeploy Ground (ex-StructionSite) [36] | Self-serve $4,188/yr | 360 camera | Yes | Yes | No |
| HoloBuilder / FARO Sphere XG [37] | From $125 per user per month | 360 camera plus app | Yes | Yes | No |
| Matterport [38] | Free (1 space), Starter about $10/mo, Pro about $69/mo; Pro3 camera $5,995; pro scan service $400 to 1,000 per home | iPhone 12 Pro+ LiDAR on Free and Starter | Auto plan with camera positions, Mattertags | Separate spaces per phase | Yes |
| Cupix, Buildots, Doxel, Reconstruct, Track3D, Procore | Enterprise quotes; Buildots and Doxel about $0.03 to 0.08 per sq ft per scan; Procore $15 to 80k/yr | 360 camera | Yes | Yes | No |
| Fieldwire | Free up to 3 projects, 100 sheets, 5 users; Pro $54 per user per month | Phone | Manual pins | Manual | Yes |
| pin360 [39] | Free project with 20 pins; from GBP 19 to 29/mo | Phone or 360 | Onto your PDF | Manual | Yes |
| Polycam [40] | Pro $26.99/mo or $199.99/yr | iPhone LiDAR | No | No | Yes |
| magicplan [41] | From $9.99/mo plus about $40 per project overages | Phone | Photos per room; imports and scales a plan | No | Yes |

**Cheapest 80% route.** A free Matterport account with the iPhone's LiDAR, one scan per phase saved as its own space, Mattertags on the panel, valves and shutoffs, plus Fieldwire free or pin360 to pin square-on wall photos to the PDF. Total $0 to 120 per year, plus an optional one-time professional pre-drywall scan ($400 to 1,000) as insurance. This gets most of the value with zero code and is the fallback if Igloo stalls.

**What Igloo adds.** One persistent coordinate frame so every phase overlays every other phase and the plan; a true AR see-through later on the same alignment; and data in an open format that outlives any vendor's subscription. Nothing on the market gives a homeowner cross-phase spatial overlay plus AR see-through at consumer prices.

**Purpose-built apps.** AsBuilt (asbuilt.dev, "Carfax for homes") captures before insulation as a full service or DIY app; it is in pilot and its price is not published [42]. RecordSet (recordset.com) is a homeowner photo-record app for "conditions behind walls"; the app is free, hosting and publishing are paid [43]. iGUIDE sells "See Behind The Walls" shoots at about $250 to 400 per project [44], and Walabot DIY 2 ($149.95) is an RF wall scanner good to about 4 in, a useful complement in the finished house [45]. All of these are photo records without a metric frame; none aligns phases to each other or to the plan.

Given the product ambition, building is reasonable. Capture readiness comes first, and the buy route above is the documented fallback from day one.

## 9. Open questions and unverified items

- iPhone 18 Pro LiDAR: spec sheet not checked (near-certain).
- Splat fidelity on wires, conduit and thin pipe: no quantitative study found.
- Wall-clock for COLMAP or GLOMAP on 1,000 to 3,000 images, and splat training time, on an RTX 4070 Super specifically: the 15 to 20 min per room figure is interpolated from 3060 and 4090 numbers.
- AprilTag accuracy figures are for a 16.4 cm tag; Igloo's tag is 12.8 cm inside a 20 cm sheet, so detection range needs a device test, as does ARKit `detectionImages` reliability on AprilTag-style artwork (the reason for the high-detail ring).
- Several figures come from the research notes without a recorded URL (corridor drift test, 10 to 20 cm scan-to-BIM, 0.044 m wall-line registration, 2 cm scan-versus-BIM RMSE, the AprilTag accuracy table) and should be re-sourced before being quoted outside this repo.
- Grounding DINO 1.6 Pro pricing; Spark 2.x LOD and streaming details; Potree maintenance; whether RealityScan's free tier permits a distributed hobby app.
- Product facts: AsBuilt's price; real OpenSpace, Cupix, Track3D and Buildots quotes; whether OpenSpace has an iPhone-only mode; Matterport Starter's exact space count; Stray Scanner's price; UnLoc's recall figures.
- Research access: developers.google.com, apple.com, macrumors, 9to5mac, learn.poly.cam and ncbi were blocked by the research proxy; Apple API facts came from developer.apple.com's tutorial data feed; the VIO benchmark is cited by PMC identifier.
- Apple Developer Program enrollment time (Apple says about 24 h; 2026 reports range to days), hence day-0 enrollment.

## 10. Sources

1. Tom's Guide, iOS 27 announced at WWDC 2026. https://www.tomsguide.com/phones/iphones/ios-27-is-official-all-the-new-upgrades-and-features-announced-at-wwdc-2026 (published 2026-06-09)
2. Apple Machine Learning Research, RoomPlan. https://machinelearning.apple.com/research/roomplan (accessed 2026-09-11)
3. it-jim, RoomPlan framework by Apple. https://www.it-jim.com/blog/roomplan-framework-by-apple/ (accessed 2026-09-11)
4. it-jim, iPhone 12 Pro LiDAR data. https://www.it-jim.com/blog/iphones-12-pro-lidar-how-to-get-and-interpret-data/ (accessed 2026-09-11)
5. iPad Pro LiDAR indoor mapping study. https://www.sciencedirect.com/science/article/pii/S2666165923000510 (published 2023, accessed 2026-09-11)
6. ARKitScenes paper. https://arxiv.org/pdf/2111.08897 (accessed 2026-09-11)
7. VIO benchmark, Sensors 2022, PMC9785098. https://pmc.ncbi.nlm.nih.gov/articles/PMC9785098/ (identifier from the research notes; site not reachable during research)
8. NeRFCapture. https://github.com/jc211/NeRFCapture (updated 2026-08-19); https://apps.apple.com/us/app/nerfcapture/id6446518379 (updated 2026-05-17)
9. StrayVisualizer. https://github.com/kekeblom/StrayVisualizer (updated 2026-09-04)
10. Record3D. https://github.com/marek-simonik/record3d (updated 2026-08-27)
11. Polycam polyform raw export. https://github.com/PolyCam/polyform (accessed 2026-09-11)
12. Z-FLoc, zero-shot floor-plan localization. https://arxiv.org/abs/2606.04788 (published 2026-06-03)
13. Long-term visual relocalization under appearance change. https://arxiv.org/pdf/2008.02004 (accessed 2026-09-11)
14. US patent 11348322, tracking construction with fiducial markers. https://patents.google.com/patent/US11348322 (number from the research notes; not fetched)
15. COLMAP issue 3210, dense MVS runtime. https://github.com/colmap/colmap/issues/3210 (accessed 2026-09-11)
16. nerfstudio Splatfacto. https://docs.nerf.studio/nerfology/methods/splat.html (accessed 2026-09-11)
17. Postshot on Radiance Fields. https://radiancefields.com/platforms/postshot (accessed 2026-09-11); 3060 timing from https://www.polyvia3d.com/guides/gaussian-splatting-tutorial (accessed 2026-09-11)
18. Feed-forward scaling caveat. https://arxiv.org/html/2605.17478 (accessed 2026-09-11)
19. BIM-Informed Visual SLAM. https://arxiv.org/html/2509.13972v1 (published 2025-09)
20. GLOMAP, ECCV 2024. https://demuc.de/papers/pan2024glomap.pdf (accessed 2026-09-11)
21. RealityScan 2.0 release. https://www.realityscan.com/news/realityscan-20-new-release-brings-powerful-new-features-to-a-rebranded-realitycapture (published 2025-06)
22. RealityScan 2.2 release. https://www.cgchannel.com/2026/06/epic-games-releases-realityscan-2-2-with-amd-gpu-support/ (published 2026-06)
23. PlayCanvas adopts SOG. https://blog.playcanvas.com/playcanvas-adopts-sogs-for-20x-3dgs-compression/ (accessed 2026-09-11)
24. Spark renderer. https://github.com/sparkjsdev/spark (accessed 2026-09-11)
25. MapAnything. https://github.com/facebookresearch/map-anything (arXiv 2509.13414, accessed 2026-09-11)
26. Depth Anything 3. https://github.com/bytedance-seed/depth-anything-3 (published 2025-11-14)
27. Open-vocabulary models for MEP detection, ISARC 2025. https://arxiv.org/abs/2501.09267 (accessed 2026-09-11)
28. Grounding DINO 1.6 Pro. https://visincept.com/en/blog/6 (accessed 2026-09-11)
29. SAM 3. https://ai.meta.com/research/sam3/ (published 2025-11-19)
30. Automatic Drywall Analysis, VISAPP 2025. https://arxiv.org/abs/2503.03422 (accessed 2026-09-11)
31. OpenConstruction dataset. https://arxiv.org/pdf/2508.11482 (published 2025-08)
32. ArchPlanVQA, J. Computing in Civil Engineering 40(5), 2026. https://ascelibrary.com/doi/abs/10.1061/JCCEE5.CPENG-7571 (accessed 2026-09-11)
33. pdfplumber. https://github.com/jsvine/pdfplumber (accessed 2026-09-11)
34. CubiCasa5K. https://github.com/CubiCasa/CubiCasa5k (accessed 2026-09-11)
35. OpenSpace pricing. openspace.ai/smb-pricing-webpage and capterra.com/p/191822/OpenSpace (accessed 2026-09-11)
36. DroneDeploy pricing and StructionSite migration. dronedeploy.com/pricing and help.dronedeploy.com (accessed 2026-09-11)
37. HoloBuilder pricing. capterra.com/p/268432/HoloBuilder (accessed 2026-09-11)
38. Matterport pricing, LiDAR accuracy and job-site scanning guide. checkthat.ai/brands/matterport/pricing, matterport.com/blog/lidar-accuracy, support.matterport.com (accessed 2026-09-11)
39. pin360. pin360.io (accessed 2026-09-11)
40. Polycam, App Store id1532482376. apps.apple.com (accessed 2026-09-11)
41. magicplan, import and scale an existing plan. help.magicplan.app/import-and-digitalize-an-existing-floor-plan (accessed 2026-09-11)
42. AsBuilt. asbuilt.dev (accessed 2026-09-11)
43. RecordSet. recordset.com (accessed 2026-09-11)
44. iGUIDE pricing. goiguide.com/pricing (accessed 2026-09-11)
45. Walabot DIY 2. walabot.com (accessed 2026-09-11)
