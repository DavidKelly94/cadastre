# Pipeline design (`igloo` CLI)

Python 3.12 package in `pipeline/`, managed with `uv`. Runs on the owner's Windows PC (RTX 4070 Super) and on Linux CI. MVP scope: validate sessions, detect markers, calibrate plans, align sessions to plans, inspect. Later: pose graph, TSDF meshes, splats, AI.

Dependencies (MVP): `numpy`, `opencv-python-headless` (AprilTag detection via `cv2.aruco`, PnP, perspective warp), `pypdfium2` (PDF rasterizing), `reportlab` (marker PDFs), `pillow`. Dev: `pytest`, `ruff`. No GPU dependency in the MVP.

## 1. Layout

```
pipeline/
  pyproject.toml            [project] name = "igloo"; [project.scripts] igloo = "igloo.cli:main"
  igloo/
    __init__.py
    cli.py                  argparse subcommands: ingest, validate, apriltag, plan, align, inspect, markers, synth
    session.py              Session dataclass: load manifest/JSONL, resolve paths, matrix helpers
    transforms.py           column-major ↔ numpy, ARKit↔OpenCV camera, unproject, SE(2) embed, Umeyama 2D
    validate.py             rules from session-format.md §11
    ingest.py               copy/unzip into the project store, then validate
    apriltag.py             detection, PnP, aggregation, anchor-frame check
    plan.py                 rasterize PDF/photo, perspective correction, calibration page, plan.json
    align.py                landmarks ↔ plan corners → T_hs; residual report; --use-markers
    inspector.py            static HTML per level + serve
    markers.py              marker PDF + PNG generator
    synth.py                synthetic sessions for tests
    web/                    static HTML/JS for calibrate, align, inspect (no build step)
    serve.py                tiny http.server: GET static files, POST /save → JSON on disk
  tests/
    test_transforms.py test_validate.py test_apriltag.py test_align.py test_plan.py test_markers.py
    conftest.py             builds a synthetic session in tmp_path
```

Project store (default `./igloo-data`, override with `--store`):

```
igloo-data/
  sessions/<project>/<session-id>/        raw sessions (copied in by ingest)
  plans/<level>.png  plans/<level>.json    calibrated rasters
  alignments/<session-id>.json            T_hs + residuals
  markers/<project>.json                  marker poses in house frame (accumulated)
  inspect/<level>.html                    generated pages
```

## 2. Core math (`transforms.py`)

- `mat_from_cm(list16) -> np.ndarray(4,4)`: `np.array(list16).reshape(4, 4, order='F')`. `mat_to_cm(M) -> list`: `M.flatten(order='F').tolist()`.
- `K_from_list(list9) -> np.ndarray(3,3)`: `np.array(list9).reshape(3, 3)`.
- `arkit_to_cv(T_wc) = T_wc @ np.diag([1, -1, -1, 1])`.
- `unproject(u, v, d, K) -> p_c_arkit`: `X=(u-cx)/fx*d; Y=(v-cy)/fy*d; return [X, -Y, -d]`.
- `se2_to_mat(theta, tx, ty, tz)`: the 4x4 in `system-design.md` §4.
- `umeyama_2d(A, B)`: `A`, `B` are `(n,2)` arrays (session `(x,z)` and house `(x,z)`); returns `R (2,2)`, `t (2,)`, `rms`. Centroid-subtract, `H = A0.T @ B0`, SVD `U,S,Vt`; `d = sign(det(Vt.T @ U.T))`; `R = Vt.T @ diag(1,d) @ U.T`; `t = b̄ − R ā`. `theta = atan2(R[1,0], R[0,0])` is then mapped into the y-rotation form: with session horizontal coordinates `(x, z)` and house `(x, z)`, the 4x4 rows/cols `(0, 2)` receive `R` directly and `t` fills `(t_x, t_z)`.

Unit tests: round trips, known rotations, `umeyama_2d` recovers a synthetic transform to 1e-9, unproject/reproject identity.

## 3. `validate`

Implements `session-format.md` §11 exactly; prints a table (keyframes, stills, markers by ID with observation counts, landmarks by label, tracking-limited seconds, depth validity %, bytes) and `OK` / `WARN` / `ERROR` lines; exit code 1 on any error. `--json` writes `derived/validate.json`.

## 4. `apriltag`

1. For each keyframe (optionally every `--stride` frames) and every still: `cv2.imread`, grayscale, `cv2.aruco.ArucoDetector(cv2.aruco.getPredefinedDictionary(cv2.aruco.DICT_APRILTAG_36h11), params).detectMarkers(gray)`. Tag ID `n` maps to marker `IG-{n:03d}`.
2. Corner order from OpenCV is top-left, top-right, bottom-right, bottom-left in the image. Object points for a tag of side `s` (the AprilTag black square is 12.8 cm of the 20 cm marker; use `tag_size_m = 0.128` by default, overridable) in the canonical marker frame (`+x` right, `+y` up, `+z` out of the face, origin at centre): `(-s/2, +s/2, 0), (+s/2, +s/2, 0), (+s/2, -s/2, 0), (-s/2, -s/2, 0)`.
3. `cv2.solvePnP(obj, corners, K, None, flags=cv2.SOLVEPNP_IPPE_SQUARE)` → `T_cm` (OpenCV camera ← marker). Session pose: `T_wm = arkit_to_cv(T_wc) @ T_cm`.
4. Reject observations with reprojection error > 1.5 px, tag side < 40 px in the image, or estimated distance > 4 m.
5. Aggregate per marker: translation = component-wise median; rotation = the observation whose rotation is closest to the chordal mean (or quaternion averaging); report spread (max deviation from median) and count. Write `derived/markers_detected.json`: `{marker_id: {T_wm, n_obs, spread_m, spread_deg}}`.
6. `--check-anchor-frame`: compares ARKit `markers.jsonl` anchors (converted with `R_am` from `session-format.md` §8) against PnP results and prints the per-axis agreement; used once on the first real capture to confirm the anchor-frame constant.

Bundled marker PNGs must be generated by the same `markers.py` so on-device detection and offline detection refer to the same physical geometry.

## 5. `plan`

- `plan add <file> --level <slug> [--page N] [--dpi 200]`: PDF → PNG via `pypdfium2` (`page.render(scale=dpi/72)`); image → PNG copy. Writes `plans/<level>.png` and a stub `plans/<level>.json` with `{"level": ..., "image": ..., "metres_per_pixel": null, "origin_px": null, "rotation_deg": 0, "floor_height_m": 0}`.
- `plan correct <file> --level <slug>`: for photographed paper plans; opens the local page to click the four sheet corners, then `cv2.getPerspectiveTransform` + `warpPerspective` to a rectangle.
- `plan calibrate --level <slug>`: opens `web/calibrate.html` served by `serve.py`; the owner clicks two points and types the real distance (feet-inches or metres), clicks the origin point, optionally sets north/rotation and floor height; the page POSTs the JSON and the CLI writes `plans/<level>.json`. Scale cannot be edited after alignments exist (recalibrating invalidates them; the CLI refuses unless `--force`).

## 6. `align`

- `align <session-id> --level <slug>`: loads landmarks and the calibrated plan; opens `web/align.html`: left the plan raster, right a top-down plot of the session (trajectory, landmarks with labels, mesh floor outline if `mesh.obj` exists). The owner clicks landmark ↔ plan point pairs (≥ 2, ideally ≥ 3). The page POSTs pairs; the CLI runs `umeyama_2d`, computes `t_y` from `floor` landmarks or mesh floor faces, writes `alignments/<session-id>.json`:

```json
{"session_id": "...", "level": "main", "T_hs": [16 numbers column-major], "pairs": [...],
 "rms_m": 0.032, "max_residual_m": 0.05, "method": "landmarks", "created_at": "..."}
```

- `--use-markers`: adds correspondences from `markers/<project>.json` (house-frame marker poses from earlier aligned sessions) matched by ID with this session's `derived/markers_detected.json`; markers seen in this session but not yet in the house map are added to it after alignment.
- Residual warnings: `rms_m > 0.15` warns; `> 0.30` refuses to write without `--force`.

## 7. `inspect`

Generates `inspect/<level>.html`: the plan raster as background, each aligned session's trajectory (poses transformed by `T_hs`, projected to plan pixels), landmarks, markers, and keyframe thumbnails on hover (small JPEG thumbnails generated into `derived/thumbs/` at 320 px wide). A side panel lists sessions by phase with the quality report from `validate`. Pure static HTML + inline JS; `igloo inspect --serve` runs `serve.py`.

## 8. `markers`

`markers --out markers.pdf --png ios/Igloo/Resources/Markers --ids 0-59`. For each ID: a 20 cm square at 100% scale on Letter/A4 (reportlab, `mm` units): 12.8 cm AprilTag 36h11 (`cv2.aruco.generateImageMarker(dict, id, 640)` gives the tag bitmap; border/quiet zone 1.6 cm), a 2 cm outer ring of high-detail deterministic noise seeded by the ID (for ARKit image detection), a 1 cm white margin, and the label `IG-017` in a large sans font below the tag. The PNG export renders the identical 20 cm square at 1200x1200 px (60 px/cm) so `physicalWidth` in the app equals 0.20 m exactly.

## 9. `synth`

`synth --out <dir>`: writes a small format-valid session: a circular trajectory of 30 keyframes in a 4x5 m room, flat depth maps with a synthetic floor and walls, blank JPEGs with two AprilTags warped into them at known poses (`cv2.warpPerspective` of the generated tag bitmaps), four corner landmarks at known positions, and a manifest. Tests use it to check `validate` (passes), `apriltag` (recovers the tag poses within 1 cm / 1°), `align` (recovers a known SE(2) within 1 mm), and `inspect` (produces HTML).

## 10. Later (weeks 3+, own design docs when started)

- `graph`: pose graph over sessions and markers (scipy least squares).
- `mesh`: Open3D TSDF integration per session; GLB export for the viewer.
- `splat`: nerfstudio dataset export (`transforms.json` with depth) and SOG conversion.
- `label`: vision-LLM tagging, SAM-assisted masks, projection through depth.
- `import-nerfcapture` / `import-record3d`: converters for the fallback capture apps.
