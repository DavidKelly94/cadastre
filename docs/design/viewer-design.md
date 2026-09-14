# Viewer design (weeks 3+)

Browser viewer for browsing a house across construction phases: plan overlay, per-phase meshes and photos, click-to-nearest-photo, measurement. Built after the capture app and pipeline v0 exist; this document fixes the direction so the pipeline emits the right data from the start.

## 1. Stack

- **three.js** (WebGL2) for scene, plan plane, meshes, photo frustums, measurement.
- **Spark** (`@sparkjsdev/spark`) for Gaussian splats; formats PLY/SPZ/SOG, SOG preferred (15–20x smaller than PLY).
- **Vite + TypeScript**, no framework required; a small UI layer (vanilla or Preact) for the side panel.
- Static hosting: files on disk opened through a local server (`vividhome serve`) or any static host later.

## 2. Data package per level (emitted by the pipeline)

```
viewer-data/<project>/
  index.json                       levels, phases, sessions, plan calibration, house-frame marker map
  plans/<level>.png                calibrated raster
  sessions/<session-id>/
    meta.json                      T_hs, phase, room, stats
    frames.json                    keyframe poses (house frame) + thumbnail paths + K
    stills.json                    still poses + paths
    thumbs/…jpg  rgb/…jpg  stills/…jpg
    mesh.glb                       ARKit or TSDF mesh in house frame (trimesh OBJ→GLB)
    splat.sog                      optional
```

Photo poses are pre-transformed into the house frame so the viewer never needs `T_hs`.

## 3. Scene

- World = house frame (`+y` up, metres). The plan raster is a textured plane at `y = floor_height_m − 0.01` per level, sized by `metres_per_pixel`, positioned so `origin_px` lands at `(0, 0)`, rotated by `rotation_deg`.
- Meshes per session, colour by phase, toggled by phase and room. Optional splats (Spark) per room.
- Camera: orbit controls with a top-down preset; level switcher moves the camera and hides other levels.
- Photo frustums: small wire pyramids at each still (always) and keyframe (when zoomed in); click → opens the photo panel.

## 4. Interactions

- **Phase toggle/slider**: show sessions of the selected phase(s); "compare" mode splits the viewport (framing left, drywall right) with linked cameras.
- **Click-to-nearest-photo**: raycast the click against meshes → 3D point; rank photos by `distance(camera_position, point)` and `angle(camera_forward, point − camera_position)`; show the best 6 with the clicked point re-projected into each photo (using `K` and the inverse pose) as a crosshair.
- **Measure**: two clicks on meshes → distance in metres and feet-inches; optional snap to plan corners.
- **Search** (later, AI roadmap): text query → photo list.
- **Labels** (later): clickable 3D segments with type and notes.

## 5. Performance budgets

- Per level: ≤ 2 M triangles on screen (decimate TSDF meshes with Open3D before export), ≤ 5 M splats (room-chunked, load on demand).
- Thumbnails 320 px for hover, full JPEG on click.
- Keep everything static and cacheable; no server logic.

## 6. AR x-ray (later, in the app)

The app will need: the house-frame marker map and landmarks for relocalization in a finished room, per-phase meshes as GLB, and the still index. All are produced by this same package. Rendering earlier-phase photos as projected textures onto the current wall uses `K`, the still pose and `T_hs`, exactly as the viewer's re-projection does.

## 7. Markup and panoramas (later, sketched here so the data package does not have to change twice)

**Markup layer.** Marks live in the house frame, not in a photo, so one mark renders in the 3D view, on the plan and over any phase's imagery. Expect `marks.json` per project alongside `index.json`: an id, a target (`point`, `region` or `element`), the house-frame geometry, level, room, phase, author, created time, text, a resolved flag and photo references. The viewer draws them as pins in 3D and on the plan, with a filter by phase and by resolved state. Two consequences for the current design: pins need to be pickable at the same time as meshes, so keep a single raycast path that can hit either; and mark geometry must be re-projected when an alignment changes, which is why marks store house-frame coordinates rather than screen or image coordinates.

**Panorama viewer.** A pano is an equirectangular or cylindrical image with a pose (`docs/session-format.md` §7). Rendering one is a textured sphere or cylinder at `T_wp` with the camera at its centre, and the useful trick is that the viewer already knows every keyframe and still pose, so it can place clickable hotspots for nearby photos inside the pano and hand the user back to the 3D view at the same heading. Panoramas are also the natural entry point for a room: show the pano first, let the user look around, then step into geometry.

**Both are additive.** Neither changes the existing package layout: `marks.json` is a new file, and panoramas are new entries in a session's directory plus a `panos` array in `frames.json`'s sibling. The viewer should ignore both when absent.
