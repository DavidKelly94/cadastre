# Cadastre session format (format_version 1)

A **session** is one continuous capture of one room at one construction phase. The iPhone app writes it; the pipeline only reads it and writes derived data next to it. This document is the contract between the two. Keep it exact: every field, unit and axis convention below is what the pipeline assumes.

## 1. Location and naming

On the phone: `Documents/sessions/<project-slug>/<session-id>/` (visible in the Files app because the app sets `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace`).

Session ID: `<YYYYMMDD-HHMMSS>_<level>_<room>_<phase>_<id6>`

- timestamp is local time at session start;
- `<level>`, `<room>` are slugs: lowercase `a-z0-9-`, 1–24 characters, derived from the names typed by the owner (`"Main Floor"` → `main-floor`);
- `<phase>` is one of `framing`, `electrical`, `plumbing`, `hvac`, `insulation`, `drywall`, `finish`, `other`;
- `<id6>` is 6 random lowercase base-32 characters (`a-z2-7`) so two sessions started in the same second never collide.

Example: `20261103-141502_main_kitchen_electrical_k3x7qa`.

## 2. Directory layout

```
<session-id>/
  manifest.json          session metadata and statistics (written at start, rewritten at stop)
  frames.jsonl           one line per keyframe
  stills.jsonl           one line per high-resolution still
  markers.jsonl          one line per printed-marker observation
  landmarks.jsonl        one line per tapped landmark (room corner, door threshold, ...)
  log.txt                app log (free text, one event per line, timestamped)
  rgb/000123.jpg         keyframe colour image, 1920x1440 JPEG (see orientation note)
  depth/000123.f32       keyframe LiDAR depth, 256x192 Float32 little-endian, metres
  conf/000123.u8         keyframe depth confidence, 256x192 UInt8 (0 low, 1 medium, 2 high)
  stills/000.jpg         high-resolution still (device native, e.g. 4032x3024)
  panos/000.jpg          OPTIONAL, reserved and unused by the MVP (see 7)
  panos.jsonl            OPTIONAL, one line per panorama (see 7)
  mesh.obj               ARKit scene mesh at stop, world (session) coordinates, metres
  mesh_classes.u8        one byte per OBJ face, in face order (classification, see 9)
  mesh.json              mesh summary (anchor count, vertex/face counts, class histogram)
  derived/               written only by the pipeline (never by the app)
```

Keyframe file names are the zero-padded 6-digit keyframe index `i`. Still file names are the zero-padded 3-digit still index `s`.

## 3. Coordinate conventions

- **Session frame (ARKit world):** right-handed, metres, `+y` up (gravity-aligned, `worldAlignment = .gravity`), origin and yaw fixed at session start. The ground plane is `x–z`.
- **Camera frame (ARKit camera):** `+x` right, `+y` up, camera looks down `−z`. `T_wc` maps camera coordinates to world (session) coordinates: `p_w = T_wc · p_c`.
- **Matrices:** every 4x4 matrix is stored as 16 numbers in **column-major** order, the memory layout of `simd_float4x4`. Element at row `r`, column `c` is index `c*4 + r`. The translation is at indices 12, 13, 14.
- **Intrinsics `K`:** 9 numbers in **row-major** order, `[fx, 0, cx, 0, fy, cy, 0, 0, 1]`, in pixels of the image they accompany (`w`x`h`).
- **Image orientation:** ARKit's `capturedImage` is always delivered in landscape sensor orientation (1920 wide x 1440 high) regardless of how the phone is held. The app stores it **unchanged**, and `K` refers to that landscape image. Do not rotate images in the app. Viewers may rotate for display, remembering that pixel coordinates in the JSON refer to the stored image.
- **Depth registration:** the depth map covers the same field of view as the colour image at lower resolution. Depth pixel `(ud, vd)` corresponds to colour pixel `(ud * w/dw, vd * h/dh)`. Depth intrinsics are `K` scaled: `fx_d = fx * dw/w`, `cx_d = cx * dw/w`, `fy_d = fy * dh/h`, `cy_d = cy * dh/h`.
- **Depth values** are planar depth `z` (distance along the optical axis, not along the ray). Invalid pixels are `0`, `NaN` or negative; treat all three as invalid. Confidence `0` (low) should be ignored for geometry.
- **Un-projection** of colour pixel `(u, v)` (origin top-left, `v` down) with depth `d`:

  ```
  X = (u - cx) / fx * d
  Y = (v - cy) / fy * d
  p_c = [ X, -Y, -d, 1 ]          (convert image y-down / z-forward to ARKit camera y-up / z-backward)
  p_w = T_wc · p_c
  ```

- **OpenCV compatibility:** an OpenCV camera (x right, y down, z forward) relates to the ARKit camera by `T_wc_cv = T_wc · diag(1, -1, -1, 1)`. Use `T_wc_cv` whenever a pose from `cv2.solvePnP` (which is `T_c_obj` in OpenCV camera axes) must be moved to the session frame: `T_w_obj = T_wc_cv · T_c_obj`.
- **Time:** `t` is seconds since session start, from `ARFrame.timestamp` (monotonic). Wall-clock times appear only in the manifest (ISO 8601 with offset).

## 4. `manifest.json`

```json
{
  "format_version": 1,
  "session_id": "20261103-141502_main_kitchen_electrical_k3x7qa",
  "status": "complete",
  "project": { "slug": "our-house", "name": "Our House" },
  "level":   { "slug": "main", "name": "Main Floor", "index": 1 },
  "room":    { "slug": "kitchen", "name": "Kitchen" },
  "phase":   "electrical",
  "notes":   "Panel side rough-in done; plumbing not started.",
  "expected_markers": ["CD-012", "CD-013", "CD-014"],
  "device":  { "model": "iPhone16,1", "ios_version": "26.6", "app_version": "0.1.0", "app_build": "37" },
  "capture": {
    "started_at": "2026-11-03T14:15:02-05:00",
    "ended_at":   "2026-11-03T14:19:48-05:00",
    "duration_s": 286.4,
    "video_format": { "w": 1920, "h": 1440, "fps": 30 },
    "keyframe_policy": { "min_dt_s": 0.1, "min_translation_m": 0.10, "min_rotation_deg": 5.0 },
    "depth": { "w": 256, "h": 192, "dtype": "float32", "units": "m" },
    "jpeg_quality": 0.85,
    "marker_physical_width_m": 0.20,
    "scene_reconstruction": "meshWithClassification"
  },
  "coordinate_frame": { "name": "arkit-session", "up": "+y", "units": "m", "matrix_order": "column-major" },
  "stats": {
    "keyframes": 812, "dropped": 3, "stills": 14, "marker_observations": 96, "landmarks": 5,
    "tracking_limited_s": 4.2, "thermal_max": "fair", "bytes": 512345678
  }
}
```

`status` is `"incomplete"` while recording, `"complete"` after a clean stop, or `"repaired"` if the app rebuilt the manifest after a crash (stats are then recomputed from the files present).

## 5. `frames.jsonl`

One JSON object per line, in keyframe order:

```json
{"i":123,"t":12.345,"T_wc":[...16 numbers...],"K":[1451.2,0,960.4,0,1451.2,720.1,0,0,1],
 "w":1920,"h":1440,"dw":256,"dh":192,"exp_s":0.0083,"exp_off":0.0,
 "tracking":"normal","reason":"none","thermal":"nominal",
 "rgb":"rgb/000123.jpg","depth":"depth/000123.f32","conf":"conf/000123.u8"}
```

| Field | Meaning |
|---|---|
| `i` | keyframe index, 0-based, strictly increasing |
| `t` | seconds since session start |
| `T_wc` | camera-to-world pose, 16 numbers column-major |
| `K` | intrinsics for the `w`x`h` colour image |
| `w`,`h`,`dw`,`dh` | colour and depth sizes |
| `exp_s`, `exp_off` | exposure duration (s) and exposure offset (EV) from `ARCamera` |
| `tracking` | `normal`, `limited`, `notAvailable` |
| `reason` | `none`, `initializing`, `excessiveMotion`, `insufficientFeatures`, `relocalizing` |
| `thermal` | `nominal`, `fair`, `serious`, `critical` (from `ProcessInfo.thermalState`) |
| `rgb`, `depth`, `conf` | paths relative to the session directory |

Depth and confidence files are **tightly packed** row-major arrays (`dh` rows of `dw` values). The app must copy row by row from the `CVPixelBuffer`, because `CVPixelBufferGetBytesPerRow` can include padding. Read in Python with `numpy.fromfile(path, dtype='<f4').reshape(192, 256)`.

## 6. `stills.jsonl`

Same fields as a keyframe line plus `s` (still index) and `path` (`stills/000.jpg`); `w`, `h` and `K` describe the still's own resolution (ARKit provides intrinsics for the high-resolution frame). `i` is the index of the most recent keyframe at the time of capture (`-1` if none). Stills have no depth file.

## 7. `panos.jsonl` (reserved, optional)

Panoramas are **not produced by the MVP app**, but the slot is reserved now so
adding them later is additive and keeps `format_version` at 1. A reader must
tolerate the directory and the file being absent, and must ignore fields it does
not recognise.

```
panos/000.jpg          equirectangular or cylindrical panorama
panos.jsonl            one line per panorama
```

```json
{"p":0,"t":74.3,"T_wp":[...16...],"projection":"equirectangular","w":8192,"h":4096,
 "hfov_deg":360.0,"vfov_deg":180.0,"source":"stitched","frames":[812,813,814],
 "path":"panos/000.jpg"}
```

`T_wp` is the panorama-to-world pose: the origin is the optical centre the
panorama was stitched about, `+y` is up, and the `+z` axis maps to the centre
column of the image so a pixel column maps to a yaw about `+y`. `projection` is
`equirectangular` or `cylindrical`. `source` is `stitched` (assembled from the
listed `frames`, which are keyframe indices) or `native` (captured directly).
`hfov_deg` and `vfov_deg` state the real coverage, which is often less than a
full sphere.

Open question for whenever this is implemented: whether to stitch offline from
keyframes, which needs no new capture UI and reuses poses already recorded, or to
capture natively on the phone, which is sharper but adds a capture mode and a
second calibration path. Stitching offline is the cheaper first move and is why
`frames` exists.

## 8. `markers.jsonl` and `landmarks.jsonl`

Marker observation (from `ARImageAnchor` add/update events):

```json
{"t":31.02,"i":211,"marker_id":"CD-012","T_wa":[...16...],"tracked":true,"physical_width_m":0.20}
```

`T_wa` is the **ARKit image-anchor** transform: origin at the image centre, `+x` to the right of the printed image, `+z` toward the bottom of the printed image, `+y` the normal pointing out of the printed face. The pipeline converts it to the canonical marker frame used for AprilTag PnP (`+x` right, `+y` toward the top of the tag, `+z` out of the face): `T_wm = T_wa · R_am` with `R_am` the 4x4 whose 3x3 block has columns `(1,0,0)`, `(0,0,-1)`, `(0,1,0)`. The first real capture must confirm this with `cadastre apriltag --check-anchor-frame`; if the axes disagree, fix the pipeline's constant, never the app.

Landmark (from a tap on the capture screen, resolved with `ARView.raycast(allowing: .estimatedPlane, alignment: .any)`):

```json
{"t":8.7,"i":60,"label":"corner-ne","kind":"corner","p_w":[2.31,-1.42,-0.87],"method":"raycast-estimatedPlane"}
```

`kind` is `corner`, `door`, `window`, `floor` or `other`. Labels are free text but the app offers a fixed vocabulary so the same room gets the same labels in every phase (`corner-nw`, `corner-ne`, `corner-se`, `corner-sw`, `door-<name>`, `window-<name>`, `floor`).

## 9. Mesh files

`mesh.obj` contains all `ARMeshAnchor` geometries transformed into session (world) coordinates, concatenated: `v x y z` lines (metres) then `f a b c` lines (1-based indices), no normals or texture coordinates required. `mesh_classes.u8` has exactly one byte per `f` line, in the same order, holding the ARKit face classification raw value: `0` none, `1` wall, `2` floor, `3` ceiling, `4` table, `5` seat, `6` window, `7` door. `mesh.json` records `anchors`, `vertices`, `faces` and a `class_histogram`.

## 10. Sizes

Per keyframe: JPEG 250–400 KB at quality 0.85, depth 196,608 B, confidence 49,152 B. With motion-gated keyframes (typically 2–4 per second while walking, at most 10 per second) a 5-minute room is 300–800 MB plus 3–5 MB per still. The app refuses to start a session with less than 2 GB free and stops at 500 MB free.

## 11. Validation rules (`cadastre validate`)

1. `manifest.json` parses, `format_version == 1`, `status != "incomplete"` (a warning, not an error, for `repaired`).
2. Every JSONL line parses; `i` strictly increasing; `t` non-decreasing and within `[0, duration_s + 1]`.
3. Every referenced file exists; depth files are exactly `dw*dh*4` bytes; confidence files exactly `dw*dh` bytes; JPEGs decode and have the declared size.
4. Every `T_wc` rotation block is orthonormal (`|R Rᵀ − I| < 1e-3`, `det R ≈ +1`).
5. `K` has `fx, fy > 0`, `cx` within `[0, w]`, `cy` within `[0, h]`.
6. At least 80% of depth pixels valid in at least 80% of keyframes (warning otherwise).
7. Stats in the manifest match the counted files (warning otherwise).
8. Marker IDs match `CD-\d{3}`; landmarks have finite coordinates.

The command prints a summary and exits non-zero on any error.

## 12. Evolution

Additive fields keep `format_version` 1; the pipeline must ignore unknown fields. Any change to units, axes, matrix order, file encodings or file names bumps `format_version`, and the pipeline must keep reading older versions. Never rewrite raw session files; all processing output goes under `derived/`.
