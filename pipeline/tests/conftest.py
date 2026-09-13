"""A minimal, format-valid session on disk, for tests that need one now.

This is deliberately small and hand-written. `cadastre synth` will later build a
richer session with real geometry; until it exists, the loader and validator
still need something to read, and a fixture whose every number is visible in the
test file is easier to reason about when an assertion fails.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

IDENTITY_CM = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
K_ROW_MAJOR = [1451.2, 0, 960.4, 0, 1451.2, 720.1, 0, 0, 1]

DEPTH_W, DEPTH_H = 4, 3
COLOUR_W, COLOUR_H = 1920, 1440


def pose_cm(x: float, y: float, z: float) -> list[float]:
    """A translation-only pose in column-major order (translation at 12, 13, 14)."""
    values = list(IDENTITY_CM)
    values[12], values[13], values[14] = x, y, z
    return values


def write_jsonl(path: Path, rows: list[dict]) -> None:
    path.write_text("".join(json.dumps(row) + "\n" for row in rows), encoding="utf-8")


def build_session(root: Path, *, keyframes: int = 3) -> Path:
    """Write a small session and return its directory."""
    root.mkdir(parents=True, exist_ok=True)
    for sub in ("rgb", "depth", "conf", "stills"):
        (root / sub).mkdir(exist_ok=True)

    frames = []
    for i in range(keyframes):
        stem = f"{i:06d}"
        # Depth is dw*dh float32; confidence is dw*dh uint8. The validator checks
        # the byte counts, so the fixture writes the real sizes.
        (root / "depth" / f"{stem}.f32").write_bytes(b"\x00" * (DEPTH_W * DEPTH_H * 4))
        (root / "conf" / f"{stem}.u8").write_bytes(b"\x02" * (DEPTH_W * DEPTH_H))
        (root / "rgb" / f"{stem}.jpg").write_bytes(b"not-a-real-jpeg")
        frames.append(
            {
                "i": i,
                "t": round(i * 0.5, 3),
                "T_wc": pose_cm(i * 0.25, 0.0, 0.0),
                "K": K_ROW_MAJOR,
                "w": COLOUR_W,
                "h": COLOUR_H,
                "dw": DEPTH_W,
                "dh": DEPTH_H,
                "exp_s": 0.0083,
                "exp_off": 0.0,
                "tracking": "normal",
                "reason": "none",
                "thermal": "nominal",
                "rgb": f"rgb/{stem}.jpg",
                "depth": f"depth/{stem}.f32",
                "conf": f"conf/{stem}.u8",
            }
        )
    write_jsonl(root / "frames.jsonl", frames)

    (root / "stills" / "000.jpg").write_bytes(b"not-a-real-jpeg")
    write_jsonl(
        root / "stills.jsonl",
        [
            {
                "s": 0,
                "i": 1,
                "t": 0.75,
                "T_wc": pose_cm(0.25, 0.0, 0.0),
                "K": K_ROW_MAJOR,
                "w": 4032,
                "h": 3024,
                "exp_s": 0.0083,
                "exp_off": 0.0,
                "tracking": "normal",
                "reason": "none",
                "thermal": "nominal",
                "path": "stills/000.jpg",
            }
        ],
    )

    write_jsonl(
        root / "markers.jsonl",
        [
            {
                "t": 0.5,
                "i": 1,
                "marker_id": "CD-012",
                "T_wa": pose_cm(1.0, 1.2, -2.0),
                "tracked": True,
                "physical_width_m": 0.20,
            }
        ],
    )

    write_jsonl(
        root / "landmarks.jsonl",
        [
            {
                "t": 0.2,
                "i": 0,
                "label": "corner-ne",
                "kind": "corner",
                "p_w": [2.31, -1.42, -0.87],
                "method": "raycast-estimatedPlane",
            }
        ],
    )

    manifest = {
        "format_version": 1,
        "session_id": "20261103-141502_main_kitchen_electrical_k3x7qa",
        "status": "complete",
        "project": {"slug": "our-house", "name": "Our House"},
        "level": {"slug": "main", "name": "Main Floor", "index": 1},
        "room": {"slug": "kitchen", "name": "Kitchen"},
        "phase": "electrical",
        "expected_markers": ["CD-012"],
        "device": {
            "model": "iPhone16,1",
            "ios_version": "26.6",
            "app_version": "0.1.0",
            "app_build": "1",
        },
        "capture": {
            "started_at": "2026-11-03T14:15:02-05:00",
            "ended_at": "2026-11-03T14:15:04-05:00",
            "duration_s": 2.0,
            "video_format": {"w": COLOUR_W, "h": COLOUR_H, "fps": 30},
            "keyframe_policy": {
                "min_dt_s": 0.1,
                "min_translation_m": 0.10,
                "min_rotation_deg": 5.0,
            },
            "depth": {"w": DEPTH_W, "h": DEPTH_H, "dtype": "float32", "units": "m"},
            "jpeg_quality": 0.85,
            "marker_physical_width_m": 0.20,
            "scene_reconstruction": "meshWithClassification",
        },
        "coordinate_frame": {
            "name": "arkit-session",
            "up": "+y",
            "units": "m",
            "matrix_order": "column-major",
        },
        "stats": {
            "keyframes": keyframes,
            "dropped": 0,
            "stills": 1,
            "marker_observations": 1,
            "landmarks": 1,
            "tracking_limited_s": 0.0,
            "thermal_max": "nominal",
            "bytes": 0,
        },
    }
    (root / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    return root


@pytest.fixture
def session_dir(tmp_path: Path) -> Path:
    return build_session(tmp_path / "20261103-141502_main_kitchen_electrical_k3x7qa")
