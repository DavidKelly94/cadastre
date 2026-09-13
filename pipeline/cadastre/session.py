"""Reading a capture session from disk.

A session is immutable: this module only reads. Everything derived goes under
``<session>/derived/``, which :attr:`Session.derived` names and nothing here
creates implicitly.

Records keep the dict they were parsed from in ``raw``. Section 12 of the format
says readers must ignore fields they do not recognise, and keeping the original
means an additive field survives a load-and-report round trip instead of being
silently dropped by the first tool that touches it.
"""

from __future__ import annotations

import json
from collections.abc import Iterator
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import numpy as np
from numpy.typing import NDArray

from .transforms import K_from_list, mat_from_cm

__all__ = [
    "Frame",
    "Landmark",
    "MarkerObservation",
    "Session",
    "SessionError",
    "Still",
    "read_jsonl",
]


class SessionError(Exception):
    """A session could not be read. The message names the file and, where the
    problem is in a JSONL file, the line."""


def read_jsonl(path: Path) -> Iterator[tuple[int, dict[str, Any]]]:
    """Yield ``(line_number, object)`` for each non-empty line, 1-based.

    Line numbers are carried because every downstream error message is more use
    with one, and a validator that can only say "a line is malformed" costs the
    owner a manual search through several hundred keyframes.
    """
    if not path.exists():
        return
    with path.open("r", encoding="utf-8") as handle:
        for number, line in enumerate(handle, start=1):
            stripped = line.strip()
            if not stripped:
                continue
            try:
                parsed = json.loads(stripped)
            except json.JSONDecodeError as error:
                raise SessionError(f"{path.name}:{number}: invalid JSON: {error}") from error
            if not isinstance(parsed, dict):
                raise SessionError(f"{path.name}:{number}: expected an object")
            yield number, parsed


def _require(raw: dict[str, Any], key: str, where: str) -> Any:
    if key not in raw:
        raise SessionError(f"{where}: missing required field {key!r}")
    return raw[key]


@dataclass(frozen=True)
class Frame:
    """One line of ``frames.jsonl``."""

    i: int
    t: float
    T_wc: NDArray[np.float64]
    K: NDArray[np.float64]
    w: int
    h: int
    dw: int
    dh: int
    tracking: str
    reason: str
    thermal: str
    rgb: str
    depth: str
    conf: str
    raw: dict[str, Any] = field(repr=False, default_factory=dict)

    @classmethod
    def from_dict(cls, raw: dict[str, Any], where: str) -> Frame:
        return cls(
            i=int(_require(raw, "i", where)),
            t=float(_require(raw, "t", where)),
            T_wc=mat_from_cm(_require(raw, "T_wc", where)),
            K=K_from_list(_require(raw, "K", where)),
            w=int(_require(raw, "w", where)),
            h=int(_require(raw, "h", where)),
            dw=int(_require(raw, "dw", where)),
            dh=int(_require(raw, "dh", where)),
            tracking=str(raw.get("tracking", "normal")),
            reason=str(raw.get("reason", "none")),
            thermal=str(raw.get("thermal", "nominal")),
            rgb=str(_require(raw, "rgb", where)),
            depth=str(_require(raw, "depth", where)),
            conf=str(_require(raw, "conf", where)),
            raw=raw,
        )

    @property
    def depth_K(self) -> NDArray[np.float64]:
        """Intrinsics for the depth map, scaled from the colour intrinsics."""
        sx = self.dw / self.w
        sy = self.dh / self.h
        scaled = self.K.copy()
        scaled[0, 0] *= sx
        scaled[0, 2] *= sx
        scaled[1, 1] *= sy
        scaled[1, 2] *= sy
        return scaled

    @property
    def position(self) -> NDArray[np.float64]:
        """Camera position in the session frame."""
        return self.T_wc[:3, 3].copy()


@dataclass(frozen=True)
class Still:
    """One line of ``stills.jsonl``. No depth files."""

    s: int
    i: int
    t: float
    T_wc: NDArray[np.float64]
    K: NDArray[np.float64]
    w: int
    h: int
    path: str
    raw: dict[str, Any] = field(repr=False, default_factory=dict)

    @classmethod
    def from_dict(cls, raw: dict[str, Any], where: str) -> Still:
        return cls(
            s=int(_require(raw, "s", where)),
            i=int(raw.get("i", -1)),
            t=float(_require(raw, "t", where)),
            T_wc=mat_from_cm(_require(raw, "T_wc", where)),
            K=K_from_list(_require(raw, "K", where)),
            w=int(_require(raw, "w", where)),
            h=int(_require(raw, "h", where)),
            path=str(_require(raw, "path", where)),
            raw=raw,
        )


@dataclass(frozen=True)
class MarkerObservation:
    """One line of ``markers.jsonl``.

    ``T_wa`` is the ARKit image-anchor transform, not the canonical marker frame;
    converting it is the job of the marker code, not of loading.
    """

    t: float
    i: int
    marker_id: str
    T_wa: NDArray[np.float64]
    tracked: bool
    physical_width_m: float
    raw: dict[str, Any] = field(repr=False, default_factory=dict)

    @classmethod
    def from_dict(cls, raw: dict[str, Any], where: str) -> MarkerObservation:
        return cls(
            t=float(_require(raw, "t", where)),
            i=int(raw.get("i", -1)),
            marker_id=str(_require(raw, "marker_id", where)),
            T_wa=mat_from_cm(_require(raw, "T_wa", where)),
            tracked=bool(raw.get("tracked", True)),
            physical_width_m=float(raw.get("physical_width_m", 0.20)),
            raw=raw,
        )


@dataclass(frozen=True)
class Landmark:
    """One line of ``landmarks.jsonl``."""

    t: float
    i: int
    label: str
    kind: str
    p_w: NDArray[np.float64]
    method: str
    raw: dict[str, Any] = field(repr=False, default_factory=dict)

    @classmethod
    def from_dict(cls, raw: dict[str, Any], where: str) -> Landmark:
        position = np.asarray(_require(raw, "p_w", where), dtype=np.float64)
        if position.shape != (3,):
            raise SessionError(f"{where}: p_w must be 3 numbers, got {position.size}")
        return cls(
            t=float(_require(raw, "t", where)),
            i=int(raw.get("i", -1)),
            label=str(_require(raw, "label", where)),
            kind=str(raw.get("kind", "other")),
            p_w=position,
            method=str(raw.get("method", "")),
            raw=raw,
        )


@dataclass(frozen=True)
class Session:
    """A capture session on disk, read lazily.

    The JSONL accessors are methods rather than cached properties: a long session
    holds several hundred keyframes, and most commands want one pass rather than
    the whole list resident.
    """

    root: Path
    manifest: dict[str, Any]

    @classmethod
    def load(cls, path: str | Path) -> Session:
        root = Path(path)
        if not root.is_dir():
            raise SessionError(f"{root}: not a directory")
        manifest_path = root / "manifest.json"
        if not manifest_path.exists():
            raise SessionError(f"{root}: no manifest.json")
        try:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as error:
            raise SessionError(f"manifest.json: invalid JSON: {error}") from error
        if not isinstance(manifest, dict):
            raise SessionError("manifest.json: expected an object")
        return cls(root=root, manifest=manifest)

    # Manifest conveniences. These stay tolerant: validate is what reports a
    # missing field, so loading a broken session has to succeed far enough for
    # validate to run and say what is wrong.

    @property
    def session_id(self) -> str:
        return str(self.manifest.get("session_id", self.root.name))

    @property
    def format_version(self) -> int | None:
        value = self.manifest.get("format_version")
        return int(value) if isinstance(value, int) else None

    @property
    def status(self) -> str:
        return str(self.manifest.get("status", "unknown"))

    @property
    def phase(self) -> str:
        return str(self.manifest.get("phase", "other"))

    @property
    def expected_markers(self) -> list[str]:
        value = self.manifest.get("expected_markers", [])
        return [str(item) for item in value] if isinstance(value, list) else []

    @property
    def duration_s(self) -> float | None:
        capture = self.manifest.get("capture")
        if not isinstance(capture, dict):
            return None
        value = capture.get("duration_s")
        return float(value) if isinstance(value, int | float) else None

    # Paths

    def resolve(self, relative: str) -> Path:
        """Resolve a path recorded in a session file against the session root."""
        return self.root / relative

    @property
    def derived(self) -> Path:
        """Where the pipeline writes. Raw session files are never modified."""
        return self.root / "derived"

    def ensure_derived(self) -> Path:
        self.derived.mkdir(parents=True, exist_ok=True)
        return self.derived

    @property
    def mesh_path(self) -> Path:
        return self.root / "mesh.obj"

    # Records

    def frames(self) -> Iterator[Frame]:
        for number, raw in read_jsonl(self.root / "frames.jsonl"):
            yield Frame.from_dict(raw, f"frames.jsonl:{number}")

    def stills(self) -> Iterator[Still]:
        for number, raw in read_jsonl(self.root / "stills.jsonl"):
            yield Still.from_dict(raw, f"stills.jsonl:{number}")

    def markers(self) -> Iterator[MarkerObservation]:
        for number, raw in read_jsonl(self.root / "markers.jsonl"):
            yield MarkerObservation.from_dict(raw, f"markers.jsonl:{number}")

    def landmarks(self) -> Iterator[Landmark]:
        for number, raw in read_jsonl(self.root / "landmarks.jsonl"):
            yield Landmark.from_dict(raw, f"landmarks.jsonl:{number}")

    def trajectory(self) -> NDArray[np.float64]:
        """Camera positions for every keyframe, as an ``(n, 3)`` array."""
        positions = [frame.position for frame in self.frames()]
        return np.array(positions, dtype=np.float64) if positions else np.zeros((0, 3))
