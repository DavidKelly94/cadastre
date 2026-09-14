"""Static inspection pages: every aligned session drawn on its level's plan.

One self-contained HTML file per level. No build step and no external assets
beyond the plan raster and the thumbnails, because this has to still open in five
years from a copied folder — the whole point of the project is a record that
outlives the tooling that made it.

Geometry is done here, in Python, and baked into the page as data. The page draws
what it is given; it does not know about ``T_hs`` or metres per pixel.
"""

from __future__ import annotations

import html
import json
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np

from .plan import PlanCalibration, PlanError, house_to_plan, load_calibration, plan_paths
from .session import PHASE_ORDER, Session
from .transforms import mat_from_cm

__all__ = ["LevelPage", "SessionOverlay", "build_page", "levels_with_alignments"]

#: Thumbnails are generated at this width, per pipeline-design §7.
THUMBNAIL_WIDTH = 320


#: Phases in build order, so the side panel reads chronologically rather than
#: alphabetically. Anything unrecognised sorts last.
@dataclass
class SessionOverlay:
    """One aligned session, already projected into plan pixels."""

    session_id: str
    room: str
    phases: list[str]
    trajectory: list[tuple[float, float]]
    landmarks: list[dict]
    markers: list[dict]
    keyframes: list[dict]
    quality: dict = field(default_factory=dict)

    def to_dict(self) -> dict:
        return {
            "session_id": self.session_id,
            "room": self.room,
            "phases": self.phases,
            "trajectory": [[round(u, 2), round(v, 2)] for u, v in self.trajectory],
            "landmarks": self.landmarks,
            "markers": self.markers,
            "keyframes": self.keyframes,
            "quality": self.quality,
        }


@dataclass
class LevelPage:
    level: str
    image: str
    image_size: tuple[int, int]
    sessions: list[SessionOverlay]

    def to_dict(self) -> dict:
        return {
            "level": self.level,
            "image": self.image,
            "width": self.image_size[0],
            "height": self.image_size[1],
            "sessions": [session.to_dict() for session in self.sessions],
        }


def _alignments(store: Path) -> list[dict]:
    directory = store / "alignments"
    if not directory.is_dir():
        return []
    out = []
    for path in sorted(directory.glob("*.json")):
        try:
            out.append(json.loads(path.read_text(encoding="utf-8")))
        except json.JSONDecodeError:
            continue
    return out


def levels_with_alignments(store: str | Path) -> list[str]:
    """Levels that have at least one aligned session."""
    levels = {alignment.get("level") for alignment in _alignments(Path(store))}
    return sorted(level for level in levels if level)


def _find_session(store: Path, session_id: str) -> Path | None:
    matches = sorted(store.glob(f"sessions/*/{session_id}"))
    return matches[0] if len(matches) == 1 else None


def _quality(session: Session) -> dict:
    """The validate summary, reusing a written report rather than redoing the work."""
    report_path = session.derived / "validate.json"
    if report_path.exists():
        try:
            data = json.loads(report_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            data = None
        if isinstance(data, dict):
            return {
                "ok": data.get("ok"),
                "keyframes": data.get("keyframes"),
                "errors": len([f for f in data.get("findings", []) if f.get("level") == "ERROR"]),
                "warnings": len([f for f in data.get("findings", []) if f.get("level") == "WARN"]),
            }

    # No stored report: count what is cheap and say the rest is unknown. Decoding
    # every JPEG to fill a side panel would make the page slow to build for no
    # gain the owner asked for.
    from .validate import validate_session

    report = validate_session(session, check_images=False, check_depth=False)
    return {
        "ok": report.ok,
        "keyframes": report.keyframes,
        "errors": len(report.errors),
        "warnings": len(report.warnings),
    }


def _thumbnail(session: Session, relative_rgb: str, target_dir: Path) -> str | None:
    """Write a 320 px thumbnail and return its path relative to the session root."""
    from PIL import Image

    source = session.resolve(relative_rgb)
    if not source.exists():
        return None
    target = target_dir / Path(relative_rgb).with_suffix(".jpg").name
    if not target.exists():
        try:
            with Image.open(source) as image:
                ratio = THUMBNAIL_WIDTH / image.width
                size = (THUMBNAIL_WIDTH, max(1, round(image.height * ratio)))
                image.convert("RGB").resize(size).save(target, "JPEG", quality=80)
        except OSError:
            return None
    return f"derived/thumbs/{target.name}"


def _overlay(
    store: Path,
    calibration: PlanCalibration,
    alignment: dict,
    *,
    thumbnails: bool,
    thumbnail_stride: int,
) -> SessionOverlay | None:
    session_id = alignment.get("session_id")
    if not session_id:
        return None
    root = _find_session(store, session_id)
    if root is None:
        return None

    session = Session.load(root)
    t_hs = mat_from_cm(alignment["T_hs"])

    def to_pixels(point_session: np.ndarray) -> tuple[float, float]:
        house = t_hs @ np.array([point_session[0], point_session[1], point_session[2], 1.0])
        return house_to_plan(calibration, house[0], house[2])

    thumb_dir = session.ensure_derived() / "thumbs" if thumbnails else None
    if thumb_dir is not None:
        thumb_dir.mkdir(parents=True, exist_ok=True)

    trajectory: list[tuple[float, float]] = []
    keyframes: list[dict] = []
    session_prefix = f"../sessions/{root.parent.name}/{root.name}"
    for frame in session.frames():
        pixel = to_pixels(frame.position)
        trajectory.append(pixel)
        if thumb_dir is not None and frame.i % thumbnail_stride == 0:
            relative = _thumbnail(session, frame.rgb, thumb_dir)
            if relative:
                keyframes.append(
                    {
                        "i": frame.i,
                        "u": round(pixel[0], 2),
                        "v": round(pixel[1], 2),
                        "thumb": f"{session_prefix}/{relative}",
                    }
                )

    landmarks = []
    for landmark in session.landmarks():
        u, v = to_pixels(landmark.p_w)
        landmarks.append(
            {"label": landmark.label, "kind": landmark.kind, "u": round(u, 2), "v": round(v, 2)}
        )

    markers = []
    detected = session.derived / "markers_detected.json"
    if detected.exists():
        try:
            payload = json.loads(detected.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            payload = {}
        for marker, entry in sorted(payload.items()):
            pose = mat_from_cm(entry["T_wm"])
            u, v = to_pixels(pose[:3, 3])
            markers.append({"id": marker, "u": round(u, 2), "v": round(v, 2)})

    room = session.manifest.get("room")
    return SessionOverlay(
        session_id=session_id,
        room=str(room.get("name", "")) if isinstance(room, dict) else "",
        phases=session.phases,
        trajectory=trajectory,
        landmarks=landmarks,
        markers=markers,
        keyframes=keyframes,
        quality=_quality(session),
    )


def build_page(
    store: str | Path,
    level: str,
    *,
    thumbnails: bool = True,
    thumbnail_stride: int = 5,
) -> Path:
    """Write ``inspect/<level>.html`` and return its path."""
    store = Path(store)
    calibration = load_calibration(store, level)
    if not calibration.is_calibrated:
        raise PlanError(f"level {level!r} is not calibrated; nothing can be placed on it")

    image_path, _ = plan_paths(store, level)
    if not image_path.exists():
        raise PlanError(f"level {level!r} has no raster at {image_path}")

    from PIL import Image

    with Image.open(image_path) as image:
        size = image.size

    overlays = []
    for alignment in _alignments(store):
        if alignment.get("level") != level:
            continue
        overlay = _overlay(
            store,
            calibration,
            alignment,
            thumbnails=thumbnails,
            thumbnail_stride=max(1, thumbnail_stride),
        )
        if overlay is not None:
            overlays.append(overlay)

    overlays.sort(key=lambda o: (_phase_rank(o.phases), o.room, o.session_id))
    page = LevelPage(
        level=level, image=f"../plans/{image_path.name}", image_size=size, sessions=overlays
    )

    target = store / "inspect" / f"{level}.html"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(_render(page), encoding="utf-8")
    return target


def _phase_rank(phases: list[str]) -> int:
    """Sort a multi-phase session by its earliest trade.

    A pass covering electrical and plumbing belongs with the electrical work,
    not after the plumbing: sorting by the earliest phase keeps the level page
    in the order the building was actually built.
    """
    ranks = [PHASE_ORDER.index(p) for p in phases if p in PHASE_ORDER]
    return min(ranks) if ranks else len(PHASE_ORDER)


def _render(page: LevelPage) -> str:
    data = json.dumps(page.to_dict(), separators=(",", ":"))
    title = html.escape(f"VividHome — {page.level}")
    return f"""<!doctype html>
<meta charset="utf-8">
<title>{title}</title>
<style>
  :root {{ color-scheme: light dark; }}
  body {{ margin: 0; font: 14px system-ui, sans-serif; display: flex; height: 100vh; }}
  #panel {{ width: 300px; overflow-y: auto; padding: 16px; border-right: 1px solid #8884; }}
  #stage {{ flex: 1; overflow: auto; position: relative; }}
  h1 {{ font-size: 16px; margin: 0 0 12px; }}
  .phase {{ font-size: 11px; text-transform: uppercase; letter-spacing: .08em;
            opacity: .6; margin: 14px 0 4px; }}
  .session {{ padding: 6px 8px; border-radius: 6px; cursor: pointer; }}
  .session:hover {{ background: #8882; }}
  .session.off {{ opacity: .35; }}
  .id {{ font-family: ui-monospace, monospace; font-size: 11px; opacity: .7;
         word-break: break-all; }}
  .bad {{ color: #c0392b; }}
  #thumb {{ position: fixed; pointer-events: none; display: none;
            border: 1px solid #8886; border-radius: 4px; background: #000; }}
  svg {{ position: absolute; top: 0; left: 0; }}
</style>
<div id="panel"><h1>{title}</h1><div id="list"></div></div>
<div id="stage"><img id="plan" alt="plan"><svg id="overlay"></svg></div>
<img id="thumb">
<script>
const DATA = {data};
const NS = "http://www.w3.org/2000/svg";
const COLOURS = ["#e6550d","#3182bd","#31a354","#756bb1","#d6616b","#8c6d31"];
const hidden = new Set();

document.getElementById("plan").src = DATA.image;
const svg = document.getElementById("overlay");
svg.setAttribute("width", DATA.width);
svg.setAttribute("height", DATA.height);

function draw() {{
  svg.textContent = "";
  DATA.sessions.forEach((s, index) => {{
    if (hidden.has(s.session_id)) return;
    const colour = COLOURS[index % COLOURS.length];

    if (s.trajectory.length > 1) {{
      const path = document.createElementNS(NS, "polyline");
      path.setAttribute("points", s.trajectory.map(p => p.join(",")).join(" "));
      path.setAttribute("fill", "none");
      path.setAttribute("stroke", colour);
      path.setAttribute("stroke-width", "2");
      path.setAttribute("stroke-opacity", "0.85");
      svg.appendChild(path);
    }}

    s.landmarks.forEach(l => {{
      const dot = document.createElementNS(NS, "circle");
      dot.setAttribute("cx", l.u); dot.setAttribute("cy", l.v); dot.setAttribute("r", "4");
      dot.setAttribute("fill", colour);
      dot.appendChild(title(`${{l.label}} (${{l.kind}})`));
      svg.appendChild(dot);
    }});

    s.markers.forEach(m => {{
      const box = document.createElementNS(NS, "rect");
      box.setAttribute("x", m.u - 5); box.setAttribute("y", m.v - 5);
      box.setAttribute("width", "10"); box.setAttribute("height", "10");
      box.setAttribute("fill", "none");
      box.setAttribute("stroke", colour);
      box.setAttribute("stroke-width", "2");
      box.appendChild(title(m.id));
      svg.appendChild(box);
    }});

    s.keyframes.forEach(k => {{
      const dot = document.createElementNS(NS, "circle");
      dot.setAttribute("cx", k.u); dot.setAttribute("cy", k.v); dot.setAttribute("r", "3");
      dot.setAttribute("fill", colour); dot.setAttribute("fill-opacity", "0.5");
      dot.style.cursor = "pointer";
      dot.addEventListener("mouseenter", event => showThumb(event, k.thumb));
      dot.addEventListener("mouseleave", hideThumb);
      svg.appendChild(dot);
    }});
  }});
}}

function title(text) {{
  const node = document.createElementNS(NS, "title");
  node.textContent = text;
  return node;
}}

const thumb = document.getElementById("thumb");
function showThumb(event, src) {{
  thumb.src = src;
  thumb.style.display = "block";
  thumb.style.left = Math.min(event.clientX + 14, innerWidth - 340) + "px";
  thumb.style.top = Math.min(event.clientY + 14, innerHeight - 260) + "px";
}}
function hideThumb() {{ thumb.style.display = "none"; }}

const list = document.getElementById("list");
let phase = null;
DATA.sessions.forEach(s => {{
  const label = s.phases.join(" \u00b7 ");
  if (label !== phase) {{
    phase = label;
    const heading = document.createElement("div");
    heading.className = "phase";
    heading.textContent = label;
    list.appendChild(heading);
  }}
  const row = document.createElement("div");
  row.className = "session";
  const quality = s.quality || {{}};
  const flag = quality.ok === false ? '<span class="bad">errors</span>' : "";
  row.innerHTML = `<div>${{s.room || "(room)"}} ${{flag}}</div>`
    + `<div class="id">${{s.session_id}}</div>`
    + `<div class="id">${{quality.keyframes ?? "?"}} keyframes, `
    + `${{quality.warnings ?? 0}} warning(s)</div>`;
  row.addEventListener("click", () => {{
    if (hidden.has(s.session_id)) hidden.delete(s.session_id);
    else hidden.add(s.session_id);
    row.classList.toggle("off");
    draw();
  }});
  list.appendChild(row);
}});

draw();
</script>
"""
