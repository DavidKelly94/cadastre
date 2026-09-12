# Viewer design (weeks 3+)

Browser viewer for browsing a house across construction phases: plan overlay, per-phase meshes and photos, click-to-nearest-photo, measurement. Built after the capture app and pipeline v0 exist; this document fixes the direction so the pipeline emits the right data from the start.

## 1. Stack

- **three.js** (WebGL2) for scene, plan plane, meshes, photo frustums, measurement.
- **Spark** (`@sparkjsdev/spark`) for Gaussian splats; formats PLY/SPZ/SOG, SOG preferred (15–20x smaller than PLY).
- **Vite + TypeScript**, no framework required; a small UI layer (vanilla or Preact) for the side panel.
- Static hosting: files on disk opened through a local server (`igloo serve`) or any static host later.

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
