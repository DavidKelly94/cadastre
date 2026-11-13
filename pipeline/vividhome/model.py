"""3D on the PC, stage one: the scanned mesh, in the house (ADR-0036).

Every capture carries the phone's own mesh of the room, in the session's
coordinates, and a placed capture has the transform that puts it in the house.
This moves each placed capture's mesh into house coordinates and writes one
page per level that shows the rooms together, standing on the level's drawing.

Nothing here needs a GPU on the PC or anything the capture does not already
hold, and nothing is fetched from outside: the page draws with the browser's
own WebGL, so it opens the same on the phone through ``serve --lan``. It is a
model for looking at. Finding a pipe is done from the posed photos (ADR-0009),
which the level page links to.

Everything written is derived: ``inspect/<level>-3d.html`` and
``inspect/<level>-3d.bin`` can be deleted and rebuilt.
"""

from __future__ import annotations

import html
import json
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np

from . import units
from .inspector import _alignments, _find_session, _phase_rank
from .mesh import read_mesh
from .plan import PlanError, load_calibration, plan_paths, plan_to_house
from .points import VOXEL_M, session_points
from .session import Session, SessionError
from .transforms import mat_from_cm

#: One tint per capture, cycled. Walls take it; floors and ceilings stay gray.
PALETTE = (
    (0.36, 0.62, 0.90),
    (0.93, 0.56, 0.26),
    (0.35, 0.78, 0.52),
    (0.84, 0.42, 0.62),
    (0.60, 0.52, 0.88),
    (0.86, 0.76, 0.32),
    (0.36, 0.76, 0.78),
    (0.88, 0.44, 0.40),
)


@dataclass
class ModelResult:
    """What ``build_model`` wrote, and what it left out and why."""

    page: Path
    data: Path
    sessions: int
    vertices: int
    faces: int
    skipped: list[str] = field(default_factory=list)
    #: Colored points from the keyframes, and the file they are in; 0 and
    #: None when the level was built without them.
    points: int = 0
    points_data: Path | None = None


def model_paths(store: str | Path, level: str) -> tuple[Path, Path]:
    directory = Path(store) / "inspect"
    return directory / f"{level}-3d.html", directory / f"{level}-3d.bin"


def points_path(store: str | Path, level: str) -> Path:
    return Path(store) / "inspect" / f"{level}-3d-points.bin"


def build_model(store: str | Path, level: str, *, points: bool = True) -> ModelResult:
    """Write the level's 3D page and its data, and say what went into it.

    ``points`` adds the keyframes themselves: every depth pixel in the house
    with its photograph's color (``points.py``). It is the slower part, a
    second or two per hundred keyframes.

    Raises :class:`PlanError` when the level is not calibrated, or when no
    placed capture on it has a mesh: there is then nothing to show.
    """
    store = Path(store)
    calibration = load_calibration(store, level)
    if not calibration.is_calibrated:
        raise PlanError(f"level {level!r} is not calibrated; nothing can be placed on it")
    image_path, _ = plan_paths(store, level)

    entries = []
    skipped: list[str] = []
    for alignment in _alignments(store):
        if alignment.get("level") != level:
            continue
        session_id = str(alignment.get("session_id", ""))
        root = _find_session(store, session_id)
        if root is None:
            skipped.append(f"{session_id}: not in the store")
            continue
        try:
            session = Session.load(root)
            mesh = read_mesh(session)
        except SessionError as error:
            skipped.append(f"{session_id}: {error}")
            continue
        if len(mesh.faces) == 0:
            skipped.append(f"{session_id}: an empty mesh")
            continue
        t_hs = mat_from_cm(alignment["T_hs"])
        moved = mesh.vertices @ t_hs[:3, :3].T + t_hs[:3, 3]
        entries.append((session, moved.astype(np.float32), mesh.faces.astype(np.uint32), t_hs))

    if not entries:
        reason = "; ".join(skipped) if skipped else "no placed capture on it"
        raise PlanError(f"level {level!r} has no mesh to show ({reason})")

    def room_of(session: Session) -> str:
        room = session.manifest.get("room")
        name = str(room.get("name", "")) if isinstance(room, dict) else ""
        return name or session.root.name

    entries.sort(
        key=lambda entry: (_phase_rank(entry[0].phases), room_of(entry[0]), entry[0].root.name)
    )

    positions = []
    indices = []
    sessions = []
    vertex_offset = 0
    index_offset = 0
    cloud_positions = []
    cloud_colors = []
    point_offset = 0
    for order, (session, moved, faces, t_hs) in enumerate(entries):
        positions.append(moved)
        indices.append(faces + vertex_offset)
        entry = {
            "id": session.root.name,
            "room": room_of(session),
            "phases": list(session.phases),
            "first": index_offset,
            "count": int(faces.size),
            "faces": len(faces),
            "color": list(PALETTE[order % len(PALETTE)]),
            "point_first": point_offset,
            "point_count": 0,
        }
        if points:
            where, colors = session_points(session, t_hs)
            cloud_positions.append(where)
            cloud_colors.append(colors)
            entry["point_count"] = len(where)
            point_offset += len(where)
        sessions.append(entry)
        vertex_offset += len(moved)
        index_offset += int(faces.size)

    all_positions = np.concatenate(positions)
    all_indices = np.concatenate(indices).reshape(-1)
    low = all_positions.min(axis=0)
    high = all_positions.max(axis=0)

    plan = None
    if image_path.exists():
        from PIL import Image

        with Image.open(image_path) as image:
            width, height = image.size
        # The drawing as a floor: its four corners in house meters, a hair
        # under the level's floor so the scan's own floor wins where both are.
        floor = float(calibration.floor_height_m)
        corners = []
        for u, v in ((0, 0), (width, 0), (width, height), (0, height)):
            x, z = plan_to_house(calibration, u, v)
            corners.append([round(x, 4), round(floor - 0.02, 4), round(z, 4)])
        plan = {"image": f"../plans/{image_path.name}", "corners": corners}

    page_path, data_path = model_paths(store, level)
    page_path.parent.mkdir(parents=True, exist_ok=True)
    with data_path.open("wb") as handle:
        handle.write(all_positions.astype("<f4").tobytes())
        handle.write(all_indices.astype("<u4").tobytes())

    # The keyframes' points: positions, then one RGBA per point, so both
    # blocks stay aligned to four bytes.
    cloud_path = points_path(store, level)
    if point_offset:
        where = np.concatenate(cloud_positions).astype("<f4")
        rgba = np.full((point_offset, 4), 255, dtype=np.uint8)
        rgba[:, :3] = np.concatenate(cloud_colors)
        with cloud_path.open("wb") as handle:
            handle.write(where.tobytes())
            handle.write(rgba.tobytes())
    elif cloud_path.exists():
        cloud_path.unlink()

    data = {
        "level": level,
        "points": {"data": cloud_path.name, "count": point_offset, "size": VOXEL_M}
        if point_offset
        else None,
        "data": data_path.name,
        "vertices": len(all_positions),
        "indices": len(all_indices),
        "low": [round(float(value), 4) for value in low],
        "high": [round(float(value), 4) for value in high],
        "floor": float(calibration.floor_height_m),
        "units": units.default(),
        "sessions": sessions,
        "plan": plan,
        "level_page": f"{level}.html",
    }
    page_path.write_text(_render(data), encoding="utf-8")
    return ModelResult(
        page=page_path,
        data=data_path,
        sessions=len(sessions),
        vertices=len(all_positions),
        faces=len(all_indices) // 3,
        skipped=skipped,
        points=point_offset,
        points_data=cloud_path if point_offset else None,
    )


def _render(data: dict) -> str:
    title = html.escape(f"VividHome — {data['level']} in 3D")
    return (
        _PAGE.replace("__TITLE__", title)
        .replace("__LEVEL_PAGE__", html.escape(data["level_page"]))
        .replace("__DATA__", json.dumps(data, separators=(",", ":")))
    )


_PAGE = """<!doctype html>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no">
<title>__TITLE__</title>
<style>
  :root { color-scheme: light dark; }
  html, body { height: 100%; }
  body { margin: 0; font: 14px system-ui, sans-serif; display: flex; overflow: hidden; }
  #panel { width: 280px; overflow-y: auto; padding: 16px; border-right: 1px solid #8884;
           box-sizing: border-box; }
  #stage { flex: 1; position: relative; min-width: 0; min-height: 0; background: #1b2026; }
  canvas { width: 100%; height: 100%; display: block; touch-action: none; }
  h1 { font-size: 16px; margin: 0 0 10px; }
  a { color: inherit; }
  .row { display: flex; align-items: center; gap: 8px; padding: 4px 0; }
  .swatch { width: 12px; height: 12px; border-radius: 3px; flex: none; }
  .name { font-weight: 600; }
  .sub { font-size: 11px; opacity: .65; }
  .hint { font-size: 11px; opacity: .65; margin-top: 14px; line-height: 1.45; }
  .tools { margin: 12px 0; display: grid; gap: 8px; }
  .tools label { display: flex; align-items: center; gap: 8px; }
  input[type=range] { flex: 1; min-width: 0; }
  button { font: inherit; padding: 5px 10px; }
  #note { position: absolute; left: 12px; right: 12px; bottom: 12px; color: #eee;
          background: #000a; padding: 10px 12px; border-radius: 8px; display: none; }
  @media (max-width: 720px) {
    body { flex-direction: column; }
    #panel { width: auto; max-height: 38vh; border-right: 0; border-bottom: 1px solid #8884; }
  }
</style>
<div id="panel">
  <h1>__TITLE__</h1>
  <div><a href="__LEVEL_PAGE__">Back to the plan and the photos</a></div>
  <div class="tools">
    <label id="pointsRow"><input type="checkbox" id="points" checked> The photos, as colored points</label>
    <label><input type="checkbox" id="mesh"> The phone's scan, as a surface</label>
    <label><input type="checkbox" id="floors" checked> The drawing as the floor</label>
    <label>Cut above <input type="range" id="cut"> <span id="cutValue"></span></label>
    <div><button id="top">From above</button> <button id="side">From the side</button></div>
  </div>
  <div id="list"></div>
  <div class="hint">Drag to turn. Scroll or pinch to zoom. Shift-drag, or two fingers, to move.
  The points are what the keyframes saw, each where its depth put it. Good for the shape and
  the look of a room, not for finding a pipe: the photos on the plan page are the record.</div>
</div>
<div id="stage"><canvas id="gl"></canvas><div id="note"></div></div>
<script>
const DATA = __DATA__;
const canvas = document.getElementById("gl");
const note = document.getElementById("note");
function say(text) { note.textContent = text; note.style.display = "block"; }

function feet(m) {
  if (DATA.units !== "imperial") return m.toFixed(1) + " m";
  const inches = Math.floor(m / 0.0254 + 0.5);
  const ft = Math.floor(inches / 12), rest = inches % 12;
  return ft === 0 ? rest + " in" : (rest === 0 ? ft + " ft" : ft + " ft " + rest + " in");
}

// --- A little matrix arithmetic: column-major 4x4, as WebGL wants. ----------
function multiply(a, b) {
  const o = new Float32Array(16);
  for (let c = 0; c < 4; c++) for (let r = 0; r < 4; r++) {
    let s = 0;
    for (let k = 0; k < 4; k++) s += a[k * 4 + r] * b[c * 4 + k];
    o[c * 4 + r] = s;
  }
  return o;
}
function perspective(fovy, aspect, near, far) {
  const f = 1 / Math.tan(fovy / 2), o = new Float32Array(16);
  o[0] = f / aspect; o[5] = f; o[10] = (far + near) / (near - far); o[11] = -1;
  o[14] = 2 * far * near / (near - far);
  return o;
}
function sub(a, b) { return [a[0] - b[0], a[1] - b[1], a[2] - b[2]]; }
function cross(a, b) {
  return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
}
function unit(a) { const l = Math.hypot(a[0], a[1], a[2]) || 1; return [a[0] / l, a[1] / l, a[2] / l]; }
function dot(a, b) { return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]; }
function lookAt(eye, target, up) {
  const f = unit(sub(target, eye)), s = unit(cross(f, up)), u = cross(s, f);
  return new Float32Array([
    s[0], u[0], -f[0], 0, s[1], u[1], -f[1], 0, s[2], u[2], -f[2], 0,
    -dot(s, eye), -dot(u, eye), dot(f, eye), 1]);
}

// --- The view: turning about a point on the level. ---------------------------
const size = sub(DATA.high, DATA.low);
const span = Math.max(size[0], size[2], 1);
const view = {
  target: [(DATA.low[0] + DATA.high[0]) / 2, DATA.floor + 1.0, (DATA.low[2] + DATA.high[2]) / 2],
  distance: span * 1.5, yaw: 0, pitch: 1.05,
};
function eye() {
  const c = Math.cos(view.pitch), s = Math.sin(view.pitch);
  return [view.target[0] + view.distance * c * Math.sin(view.yaw),
          view.target[1] + view.distance * s,
          view.target[2] + view.distance * c * Math.cos(view.yaw)];
}

const gl = canvas.getContext("webgl2", { antialias: true });
let dirty = true;
function redraw() { dirty = true; }

function program(vertex, fragment) {
  const p = gl.createProgram();
  for (const [type, source] of [[gl.VERTEX_SHADER, vertex], [gl.FRAGMENT_SHADER, fragment]]) {
    const shader = gl.createShader(type);
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(shader));
    gl.attachShader(p, shader);
  }
  gl.linkProgram(p);
  if (!gl.getProgramParameter(p, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(p));
  return p;
}

const MESH_VS = `#version 300 es
in vec3 aPos; uniform mat4 uMVP; out vec3 vPos;
void main() { vPos = aPos; gl_Position = uMVP * vec4(aPos, 1.0); }`;
// The face's direction comes from how the position changes across the pixel,
// so nothing but positions has to be sent. Walls take the capture's tint;
// anything flat stays gray. Above the cut nothing is drawn, which opens a
// room with a ceiling; flat faces at the floor step aside for the drawing.
const MESH_FS = `#version 300 es
precision highp float;
in vec3 vPos; uniform vec3 uColor; uniform float uCut; uniform float uFloor; uniform float uHideFloor;
out vec4 o;
void main() {
  if (vPos.y > uCut) discard;
  vec3 n = normalize(cross(dFdx(vPos), dFdy(vPos)));
  float flat_ = smoothstep(0.6, 0.8, abs(n.y));
  if (uHideFloor > 0.5 && flat_ > 0.5 && vPos.y < uFloor + 0.25) discard;
  vec3 base = mix(uColor, vec3(0.62, 0.64, 0.67), flat_);
  float light = 0.42 + 0.58 * abs(dot(n, normalize(vec3(0.35, 0.8, 0.5))));
  o = vec4(base * light, 1.0);
}`;
// The keyframes' points: each a small square, larger when nearer, in the color
// its photograph had there.
const POINT_VS = `#version 300 es
in vec3 aPos; in vec4 aColor; uniform mat4 uMVP; uniform float uScale;
out vec3 vColor; out vec3 vPos;
void main() {
  vPos = aPos; vColor = aColor.rgb;
  gl_Position = uMVP * vec4(aPos, 1.0);
  gl_PointSize = clamp(uScale / max(gl_Position.w, 0.05), 1.5, 24.0);
}`;
const POINT_FS = `#version 300 es
precision highp float;
in vec3 vColor; in vec3 vPos; uniform float uCut; uniform float uFloor; uniform float uHideFloor;
out vec4 o;
void main() {
  if (vPos.y > uCut) discard;
  if (uHideFloor > 0.5 && vPos.y < uFloor + 0.06) discard;
  o = vec4(vColor, 1.0);
}`;
const PLAN_VS = `#version 300 es
in vec3 aPos; in vec2 aUV; uniform mat4 uMVP; out vec2 vUV;
void main() { vUV = aUV; gl_Position = uMVP * vec4(aPos, 1.0); }`;
const PLAN_FS = `#version 300 es
precision highp float;
in vec2 vUV; uniform sampler2D uPlan; out vec4 o;
void main() { o = texture(uPlan, vUV); }`;

const shown = DATA.sessions.map(() => true);
let cut = DATA.high[1] + 0.05;
let mesh = null, plan = null, cloud = null;

function startPoints(buffer) {
  const count = DATA.points.count;
  const cloudProgram = program(POINT_VS, POINT_FS);
  const vao = gl.createVertexArray();
  gl.bindVertexArray(vao);
  gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(buffer, 0, count * 3), gl.STATIC_DRAW);
  const at = gl.getAttribLocation(cloudProgram, "aPos");
  gl.enableVertexAttribArray(at);
  gl.vertexAttribPointer(at, 3, gl.FLOAT, false, 0, 0);
  gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
  gl.bufferData(gl.ARRAY_BUFFER, new Uint8Array(buffer, count * 12, count * 4), gl.STATIC_DRAW);
  const color = gl.getAttribLocation(cloudProgram, "aColor");
  gl.enableVertexAttribArray(color);
  gl.vertexAttribPointer(color, 4, gl.UNSIGNED_BYTE, true, 0, 0);
  gl.bindVertexArray(null);
  cloud = { program: cloudProgram, vao };
  redraw();
}

function start(buffer) {
  const positions = new Float32Array(buffer, 0, DATA.vertices * 3);
  const indices = new Uint32Array(buffer, DATA.vertices * 12, DATA.indices);
  const meshProgram = program(MESH_VS, MESH_FS);
  const vao = gl.createVertexArray();
  gl.bindVertexArray(vao);
  gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
  gl.bufferData(gl.ARRAY_BUFFER, positions, gl.STATIC_DRAW);
  const at = gl.getAttribLocation(meshProgram, "aPos");
  gl.enableVertexAttribArray(at);
  gl.vertexAttribPointer(at, 3, gl.FLOAT, false, 0, 0);
  gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, gl.createBuffer());
  gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, indices, gl.STATIC_DRAW);
  gl.bindVertexArray(null);
  mesh = { program: meshProgram, vao };

  if (DATA.plan) {
    const image = new Image();
    image.onload = () => {
      const planProgram = program(PLAN_VS, PLAN_FS);
      const planVao = gl.createVertexArray();
      gl.bindVertexArray(planVao);
      const c = DATA.plan.corners;
      const quad = new Float32Array([
        ...c[0], 0, 0, ...c[1], 1, 0, ...c[2], 1, 1, ...c[0], 0, 0, ...c[2], 1, 1, ...c[3], 0, 1]);
      gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
      gl.bufferData(gl.ARRAY_BUFFER, quad, gl.STATIC_DRAW);
      const p = gl.getAttribLocation(planProgram, "aPos"), uv = gl.getAttribLocation(planProgram, "aUV");
      gl.enableVertexAttribArray(p);
      gl.vertexAttribPointer(p, 3, gl.FLOAT, false, 20, 0);
      gl.enableVertexAttribArray(uv);
      gl.vertexAttribPointer(uv, 2, gl.FLOAT, false, 20, 12);
      gl.bindVertexArray(null);
      const texture = gl.createTexture();
      gl.bindTexture(gl.TEXTURE_2D, texture);
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, image);
      gl.generateMipmap(gl.TEXTURE_2D);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
      plan = { program: planProgram, vao: planVao, texture };
      redraw();
    };
    image.src = DATA.plan.image;
  }
  redraw();
}

function draw() {
  requestAnimationFrame(draw);
  if (!dirty || !mesh) return;
  dirty = false;
  const ratio = Math.min(window.devicePixelRatio || 1, 2);
  const w = Math.max(1, Math.round(canvas.clientWidth * ratio));
  const h = Math.max(1, Math.round(canvas.clientHeight * ratio));
  if (canvas.width !== w || canvas.height !== h) { canvas.width = w; canvas.height = h; }
  gl.viewport(0, 0, w, h);
  gl.clearColor(0.105, 0.125, 0.15, 1);
  gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
  gl.enable(gl.DEPTH_TEST);
  gl.disable(gl.CULL_FACE);
  const mvp = multiply(
    perspective(0.9, w / h, Math.max(0.05, view.distance / 200), view.distance * 20 + span * 4),
    lookAt(eye(), view.target, [0, 1, 0]));

  if (plan) {
    gl.useProgram(plan.program);
    gl.uniformMatrix4fv(gl.getUniformLocation(plan.program, "uMVP"), false, mvp);
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, plan.texture);
    gl.uniform1i(gl.getUniformLocation(plan.program, "uPlan"), 0);
    gl.bindVertexArray(plan.vao);
    gl.drawArrays(gl.TRIANGLES, 0, 6);
  }

  const hideFloor = plan && document.getElementById("floors").checked ? 1 : 0;
  // The scan as a surface when asked for, or when there are no points to show.
  if (document.getElementById("mesh").checked || !cloud) {
    gl.useProgram(mesh.program);
    gl.uniformMatrix4fv(gl.getUniformLocation(mesh.program, "uMVP"), false, mvp);
    gl.uniform1f(gl.getUniformLocation(mesh.program, "uCut"), cut);
    gl.uniform1f(gl.getUniformLocation(mesh.program, "uFloor"), DATA.floor);
    gl.uniform1f(gl.getUniformLocation(mesh.program, "uHideFloor"), hideFloor);
    gl.bindVertexArray(mesh.vao);
    DATA.sessions.forEach((session, index) => {
      if (!shown[index]) return;
      gl.uniform3fv(gl.getUniformLocation(mesh.program, "uColor"), session.color);
      gl.drawElements(gl.TRIANGLES, session.count, gl.UNSIGNED_INT, session.first * 4);
    });
    gl.bindVertexArray(null);
  }

  if (cloud && document.getElementById("points").checked) {
    gl.useProgram(cloud.program);
    gl.uniformMatrix4fv(gl.getUniformLocation(cloud.program, "uMVP"), false, mvp);
    gl.uniform1f(gl.getUniformLocation(cloud.program, "uCut"), cut);
    gl.uniform1f(gl.getUniformLocation(cloud.program, "uFloor"), DATA.floor);
    gl.uniform1f(gl.getUniformLocation(cloud.program, "uHideFloor"), hideFloor);
    // A point the size of its grid cell on screen, and a little over, so
    // neighbors close up into a surface.
    gl.uniform1f(gl.getUniformLocation(cloud.program, "uScale"),
      DATA.points.size * 1.6 * h / (2 * Math.tan(0.45)));
    gl.bindVertexArray(cloud.vao);
    DATA.sessions.forEach((session, index) => {
      if (!shown[index] || !session.point_count) return;
      gl.drawArrays(gl.POINTS, session.point_first, session.point_count);
    });
    gl.bindVertexArray(null);
  }
}

// --- The list, the cut and the two views. -----------------------------------
const list = document.getElementById("list");
DATA.sessions.forEach((session, index) => {
  const row = document.createElement("label");
  row.className = "row";
  const box = document.createElement("input");
  box.type = "checkbox";
  box.checked = true;
  box.addEventListener("change", () => { shown[index] = box.checked; redraw(); });
  const swatch = document.createElement("span");
  swatch.className = "swatch";
  swatch.style.background = "rgb(" + session.color.map(v => Math.round(v * 255)).join(",") + ")";
  const text = document.createElement("span");
  const name = document.createElement("div");
  name.className = "name";
  name.textContent = session.room;
  const sub_ = document.createElement("div");
  sub_.className = "sub";
  sub_.textContent = session.phases.join(" + ") + " · " +
    (session.point_count ? session.point_count.toLocaleString() + " points" :
     session.faces.toLocaleString() + " faces");
  text.append(name, sub_);
  row.append(box, swatch, text);
  list.append(row);
});

const cutSlider = document.getElementById("cut");
cutSlider.min = DATA.floor + 0.3;
cutSlider.max = DATA.high[1] + 0.05;
cutSlider.step = 0.05;
// A room with a ceiling opens a little below it; open framing has none to cut.
cut = Math.min(Number(cutSlider.max), Math.max(DATA.floor + 1.2, DATA.high[1] - 0.35));
cutSlider.value = cut;
function showCut() { document.getElementById("cutValue").textContent = feet(cut - DATA.floor); }
cutSlider.addEventListener("input", () => { cut = Number(cutSlider.value); showCut(); redraw(); });
showCut();
document.getElementById("floors").addEventListener("change", redraw);
document.getElementById("points").addEventListener("change", redraw);
document.getElementById("mesh").addEventListener("change", redraw);
if (!DATA.points) {
  document.getElementById("pointsRow").style.display = "none";
  document.getElementById("mesh").checked = true;
}
document.getElementById("top").addEventListener("click", () => { view.yaw = 0; view.pitch = 1.5; redraw(); });
document.getElementById("side").addEventListener("click", () => { view.yaw = 0.6; view.pitch = 0.5; redraw(); });

// --- Turning, zooming and moving, with a mouse or with fingers. --------------
const pointers = new Map();
let pinch = 0;
function pan(dx, dy) {
  const k = view.distance / Math.max(canvas.clientHeight, 1) * 1.1;
  const right = [Math.cos(view.yaw), 0, -Math.sin(view.yaw)];
  const ahead = [Math.sin(view.yaw), 0, Math.cos(view.yaw)];
  view.target[0] -= (right[0] * dx + ahead[0] * dy) * k;
  view.target[2] -= (right[2] * dx + ahead[2] * dy) * k;
}
canvas.addEventListener("pointerdown", event => {
  canvas.setPointerCapture(event.pointerId);
  pointers.set(event.pointerId, [event.clientX, event.clientY]);
  pinch = 0;
});
canvas.addEventListener("pointermove", event => {
  const before = pointers.get(event.pointerId);
  if (!before) return;
  const dx = event.clientX - before[0], dy = event.clientY - before[1];
  pointers.set(event.pointerId, [event.clientX, event.clientY]);
  if (pointers.size === 1) {
    if (event.shiftKey || event.buttons === 2) pan(dx, dy);
    else {
      view.yaw -= dx * 0.006;
      view.pitch = Math.min(1.55, Math.max(0.05, view.pitch + dy * 0.006));
    }
  } else if (pointers.size === 2) {
    const [a, b] = [...pointers.values()];
    const apart = Math.hypot(a[0] - b[0], a[1] - b[1]);
    if (pinch > 0 && apart > 0) view.distance = Math.max(0.3, view.distance * pinch / apart);
    pinch = apart;
    pan(dx / 2, dy / 2);
  }
  redraw();
});
for (const name of ["pointerup", "pointercancel"]) {
  canvas.addEventListener(name, event => { pointers.delete(event.pointerId); pinch = 0; });
}
canvas.addEventListener("wheel", event => {
  event.preventDefault();
  view.distance = Math.max(0.3, view.distance * Math.exp(event.deltaY * 0.0012));
  redraw();
}, { passive: false });
canvas.addEventListener("contextmenu", event => event.preventDefault());
addEventListener("resize", redraw);

if (!gl) {
  say("This browser cannot draw 3D (no WebGL 2).");
} else {
  fetch(DATA.data).then(response => {
    if (!response.ok) throw new Error(response.status);
    return response.arrayBuffer();
  }).then(start).catch(() => {
    say("The model's data did not load. Open this page through the PC's server " +
        "(vividhome serve), not as a file.");
  });
  if (DATA.points) {
    fetch(DATA.points.data).then(response => response.ok ? response.arrayBuffer() : null)
      .then(buffer => { if (buffer) startPoints(buffer); });
  }
  draw();
}
</script>
"""
