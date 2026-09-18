"""Static inspection pages: every aligned session drawn on its level's plan.

One self-contained HTML file per level. No build step and no external assets
beyond the plan raster, the thumbnails and the session's own JPEGs, because this
has to still open in five years from a copied folder — the whole point of the
project is a record that outlives the tooling that made it.

Geometry is done here, in Python, and baked into the page as data. The page draws
what it is given; it does not know about ``T_hs`` or metres per pixel.

Every photo the page shows is a link to the file it came from. A thumbnail on
hover says roughly what a spot looked like; the full keyframe or still is what
answers "is that a junction box or a shadow", and a record whose images cannot be
reached from the plan is a folder of files named by index.
"""

from __future__ import annotations

import html
import json
import math
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np
from numpy.typing import NDArray

from .plan import PlanCalibration, PlanError, house_to_plan, load_calibration, plan_paths
from .session import PHASE_ORDER, Session
from .transforms import mat_from_cm

__all__ = ["LevelPage", "SessionOverlay", "build_page", "levels_with_alignments"]

#: Thumbnails are generated at this width, per pipeline-design §7.
THUMBNAIL_WIDTH = 320

#: A camera pitched closer to the floor normal than this has no useful horizontal
#: heading, so none is drawn. 0.05 of a unit vector is about 3 degrees from
#: straight down.
MIN_HORIZONTAL_HEADING = 0.05


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
    stills: list[dict] = field(default_factory=list)
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
            "stills": self.stills,
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


def _thumbnail(session: Session, relative: str, target_dir: Path, name: str) -> str | None:
    """Write a 320 px thumbnail of a session image and return its path relative
    to the session root, or None when the source is missing or will not decode."""
    from PIL import Image

    source = session.resolve(relative)
    if not source.exists():
        return None
    target = target_dir / name
    if not target.exists():
        try:
            with Image.open(source) as image:
                ratio = THUMBNAIL_WIDTH / image.width
                size = (THUMBNAIL_WIDTH, max(1, round(image.height * ratio)))
                image.convert("RGB").resize(size).save(target, "JPEG", quality=80)
        except OSError:
            return None
    return f"derived/thumbs/{target.name}"


def _heading(
    calibration: PlanCalibration, t_hs: NDArray[np.float64], t_wc: NDArray[np.float64]
) -> list[float] | None:
    """Where a camera looks, as a unit vector in plan pixels.

    ARKit's camera looks down its own ``-z`` (section 3), so the forward
    direction is the negated third column of the pose's rotation, carried through
    ``T_hs`` into the house frame. The plan mapping is affine, so a direction maps
    as the difference of two mapped points, and only its horizontal part is
    meaningful on a floor plan: a camera pointed at the floor gets no heading
    rather than a spurious one.
    """
    forward_house = t_hs[:3, :3] @ t_wc[:3, :3] @ np.array([0.0, 0.0, -1.0])
    if math.hypot(forward_house[0], forward_house[2]) < MIN_HORIZONTAL_HEADING:
        return None
    foot = np.array(house_to_plan(calibration, 0.0, 0.0))
    tip = np.array(house_to_plan(calibration, forward_house[0], forward_house[2]))
    direction = tip - foot
    length = float(np.linalg.norm(direction))
    if length == 0.0:
        return None
    return [round(float(direction[0] / length), 4), round(float(direction[1] / length), 4)]


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

    # Paths in the page are relative to inspect/<level>.html, and point at the raw
    # session files themselves: the record is the JPEG on disk, not a copy of it.
    session_prefix = f"../sessions/{root.parent.name}/{root.name}"

    trajectory: list[tuple[float, float]] = []
    keyframes: list[dict] = []
    for frame in session.frames():
        pixel = to_pixels(frame.position)
        trajectory.append(pixel)
        if frame.i % thumbnail_stride != 0 or not session.resolve(frame.rgb).exists():
            continue
        entry = {
            "i": frame.i,
            "t": round(frame.t, 2),
            "u": round(pixel[0], 2),
            "v": round(pixel[1], 2),
            "heading": _heading(calibration, t_hs, frame.T_wc),
            "rgb": f"{session_prefix}/{frame.rgb}",
            "thumb": None,
        }
        if thumb_dir is not None:
            relative = _thumbnail(session, frame.rgb, thumb_dir, f"{frame.i:06d}.jpg")
            if relative:
                entry["thumb"] = f"{session_prefix}/{relative}"
        keyframes.append(entry)

    # Every still is drawn. They are the deliberate, full-resolution photographs
    # and there are a handful per room, so no stride applies.
    stills: list[dict] = []
    for still in session.stills():
        if not session.resolve(still.path).exists():
            continue
        pixel = to_pixels(still.T_wc[:3, 3])
        entry = {
            "s": still.s,
            "i": still.i,
            "t": round(still.t, 2),
            "u": round(pixel[0], 2),
            "v": round(pixel[1], 2),
            "heading": _heading(calibration, t_hs, still.T_wc),
            "path": f"{session_prefix}/{still.path}",
            "thumb": None,
        }
        if thumb_dir is not None:
            relative = _thumbnail(session, still.path, thumb_dir, f"still-{still.s:03d}.jpg")
            if relative:
                entry["thumb"] = f"{session_prefix}/{relative}"
        stills.append(entry)

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
        stills=stills,
        quality=_quality(session),
    )


def build_page(
    store: str | Path,
    level: str,
    *,
    thumbnails: bool = True,
    thumbnail_stride: int = 5,
) -> Path:
    """Write ``inspect/<level>.html`` and return its path.

    Every ``thumbnail_stride``-th keyframe is drawn on the plan and linked to its
    full-resolution JPEG; ``thumbnails`` adds the hover preview for each, which is
    the slow part because it decodes the source image.
    """
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
  .hint {{ font-size: 11px; opacity: .6; margin-top: 16px; }}
  #thumb {{ position: fixed; pointer-events: none; display: none;
            border: 1px solid #8886; border-radius: 4px; background: #000; }}
  svg {{ position: absolute; top: 0; left: 0; }}
  .photo {{ cursor: pointer; }}
  #light {{ position: fixed; inset: 0; z-index: 10; background: #000d; display: flex;
            flex-direction: column; align-items: center; justify-content: center; }}
  #light[hidden] {{ display: none; }}
  #full {{ max-width: 96vw; max-height: 88vh; object-fit: contain; }}
  #caption {{ color: #eee; padding: 10px; font-size: 13px; }}
  #caption a {{ color: #9cf; }}
</style>
<div id="panel"><h1>{title}</h1><div id="list"></div>
<div class="hint">Hover a dot for a preview, click it for the full photo. The tick
shows which way the camera looked. Diamonds are stills.</div></div>
<div id="stage"><img id="plan" alt="plan"><svg id="overlay"></svg></div>
<img id="thumb">
<div id="light" hidden>
  <img id="full" alt="">
  <div id="caption"><span id="what"></span> &middot;
    <a id="open" href="" target="_blank" rel="noopener">open the file</a> &middot;
    &larr; &rarr; step &middot; Esc closes</div>
</div>
<script>
const DATA = {data};
const NS = "http://www.w3.org/2000/svg";
const COLOURS = ["#e6550d","#3182bd","#31a354","#756bb1","#d6616b","#8c6d31"];
const hidden = new Set();

document.getElementById("plan").src = DATA.image;
const svg = document.getElementById("overlay");
svg.setAttribute("width", DATA.width);
svg.setAttribute("height", DATA.height);

// One list of photos per session, keyframes and stills together in time order,
// so the lightbox can step through a capture the way it was walked.
DATA.sessions.forEach(s => {{
  s.photos = s.keyframes.map(k => ({{ ...k, kind: "keyframe", src: k.rgb }}))
    .concat(s.stills.map(k => ({{ ...k, kind: "still", src: k.path }})))
    .sort((a, b) => a.t - b.t || a.i - b.i);
}});

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

    s.photos.forEach((photo, at) => svg.appendChild(photoMark(s, photo, at, colour)));
  }});
}}

function photoMark(session, photo, at, colour) {{
  const group = document.createElementNS(NS, "g");
  group.setAttribute("class", "photo");
  const still = photo.kind === "still";

  if (photo.heading) {{
    const reach = still ? 14 : 9;
    const tick = document.createElementNS(NS, "line");
    tick.setAttribute("x1", photo.u); tick.setAttribute("y1", photo.v);
    tick.setAttribute("x2", photo.u + photo.heading[0] * reach);
    tick.setAttribute("y2", photo.v + photo.heading[1] * reach);
    tick.setAttribute("stroke", colour);
    tick.setAttribute("stroke-width", still ? "2" : "1.5");
    group.appendChild(tick);
  }}

  let mark;
  if (still) {{
    mark = document.createElementNS(NS, "rect");
    mark.setAttribute("x", photo.u - 4.5); mark.setAttribute("y", photo.v - 4.5);
    mark.setAttribute("width", "9"); mark.setAttribute("height", "9");
    mark.setAttribute("transform", `rotate(45 ${{photo.u}} ${{photo.v}})`);
    mark.setAttribute("fill", colour);
    mark.setAttribute("stroke", "#fff"); mark.setAttribute("stroke-width", "1.5");
  }} else {{
    mark = document.createElementNS(NS, "circle");
    mark.setAttribute("cx", photo.u); mark.setAttribute("cy", photo.v); mark.setAttribute("r", "3");
    mark.setAttribute("fill", colour); mark.setAttribute("fill-opacity", "0.5");
  }}
  group.appendChild(mark);
  group.appendChild(title(caption(session, photo)));
  group.addEventListener("mouseenter", event => showThumb(event, photo.thumb));
  group.addEventListener("mouseleave", hideThumb);
  group.addEventListener("click", () => openPhoto(session, at));
  return group;
}}

function caption(session, photo) {{
  const which = photo.kind === "still" ? `still ${{photo.s}}` : `keyframe ${{photo.i}}`;
  return `${{session.room || session.session_id}} · ${{which}} · ${{photo.t.toFixed(1)}} s`;
}}

function title(text) {{
  const node = document.createElementNS(NS, "title");
  node.textContent = text;
  return node;
}}

const thumb = document.getElementById("thumb");
function showThumb(event, src) {{
  if (!src) return;
  thumb.src = src;
  thumb.style.display = "block";
  thumb.style.left = Math.min(event.clientX + 14, innerWidth - 340) + "px";
  thumb.style.top = Math.min(event.clientY + 14, innerHeight - 260) + "px";
}}
function hideThumb() {{ thumb.style.display = "none"; }}

// The lightbox shows the file itself, not a copy: #open is a plain link to the
// JPEG in the session folder, which is the record.
const light = document.getElementById("light");
const full = document.getElementById("full");
let current = null;
function openPhoto(session, at) {{
  const photo = session.photos[at];
  current = {{ session, at }};
  hideThumb();
  full.src = photo.src;
  document.getElementById("open").href = photo.src;
  document.getElementById("what").textContent = caption(session, photo);
  light.hidden = false;
}}
function closePhoto() {{
  light.hidden = true;
  full.removeAttribute("src");
  current = null;
}}
function step(delta) {{
  if (!current) return;
  const count = current.session.photos.length;
  openPhoto(current.session, (current.at + delta + count) % count);
}}
light.addEventListener("click", event => {{ if (event.target === light) closePhoto(); }});
addEventListener("keydown", event => {{
  if (light.hidden) return;
  if (event.key === "Escape") closePhoto();
  else if (event.key === "ArrowRight") step(1);
  else if (event.key === "ArrowLeft") step(-1);
}});

const list = document.getElementById("list");
let phase = null;
DATA.sessions.forEach(s => {{
  const label = s.phases.join(" · ");
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
    + `${{s.stills.length}} still(s), ${{quality.warnings ?? 0}} warning(s)</div>`;
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
