"""The scene mesh a session carries: ``mesh.obj`` and ``mesh_classes.u8``.

Section 9 of the format. Vertices are session (world) coordinates in metres,
faces are 1-based triangles, and the classes file holds one ARKit classification
byte per face, in face order. Nothing here interprets the mesh; it reads it,
offers the per-face geometry every consumer needs, and can write one, which is
how ``synth`` and the tests get a room with known walls.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np
from numpy.typing import NDArray

from .session import Session, SessionError

__all__ = [
    "CEILING",
    "CLASS_NAMES",
    "DOOR",
    "FLOOR",
    "NONE",
    "SEAT",
    "TABLE",
    "WALL",
    "WINDOW",
    "Mesh",
    "MeshBuilder",
    "read_mesh",
]

#: ARKit face classification raw values, as section 9 lists them.
NONE, WALL, FLOOR, CEILING, TABLE, SEAT, WINDOW, DOOR = range(8)
CLASS_NAMES = ("none", "wall", "floor", "ceiling", "table", "seat", "window", "door")


@dataclass(frozen=True)
class Mesh:
    """Triangles in session coordinates with one class byte per face."""

    vertices: NDArray[np.float64]
    faces: NDArray[np.int64]
    classes: NDArray[np.uint8]

    def corners(self) -> NDArray[np.float64]:
        """The three vertices of every face, ``(faces, 3, 3)``."""
        return self.vertices[self.faces]

    def normals(self) -> NDArray[np.float64]:
        """Unit face normals; zero for a degenerate face. Winding is whatever the
        app wrote, so a consumer that cares about direction folds them itself."""
        corners = self.corners()
        cross = np.cross(corners[:, 1] - corners[:, 0], corners[:, 2] - corners[:, 0])
        length = np.linalg.norm(cross, axis=1)
        safe = np.where(length > 0, length, 1.0)
        return np.where(length[:, None] > 0, cross / safe[:, None], 0.0)

    def areas(self) -> NDArray[np.float64]:
        corners = self.corners()
        cross = np.cross(corners[:, 1] - corners[:, 0], corners[:, 2] - corners[:, 0])
        return 0.5 * np.linalg.norm(cross, axis=1)

    def centroids(self) -> NDArray[np.float64]:
        return self.corners().mean(axis=1)

    def histogram(self) -> dict[str, int]:
        counts = np.bincount(self.classes, minlength=len(CLASS_NAMES))
        return {name: int(counts[value]) for value, name in enumerate(CLASS_NAMES) if counts[value]}


def read_mesh(session: Session) -> Mesh:
    """Read the session's mesh, or raise :class:`SessionError` saying what is wrong."""
    path = session.mesh_path
    if not path.exists():
        raise SessionError(
            f"{session.root.name}: no mesh.obj; the app writes one at stop "
            "when scene reconstruction is on"
        )

    vertices: list[tuple[float, float, float]] = []
    faces: list[tuple[int, int, int]] = []
    with path.open("r", encoding="utf-8") as handle:
        for number, line in enumerate(handle, start=1):
            parts = line.split()
            if not parts or parts[0].startswith("#"):
                continue
            if parts[0] == "v":
                if len(parts) < 4:
                    raise SessionError(f"mesh.obj:{number}: a vertex needs three numbers")
                vertices.append((float(parts[1]), float(parts[2]), float(parts[3])))
            elif parts[0] == "f":
                if len(parts) != 4:
                    raise SessionError(f"mesh.obj:{number}: expected a triangle")
                # ``f 1/2/3`` forms carry texture and normal indices this never
                # uses; the vertex index is the first field.
                faces.append(tuple(int(part.split("/")[0]) - 1 for part in parts[1:4]))

    face_array = np.array(faces, dtype=np.int64).reshape(-1, 3)
    if face_array.size and (face_array.min() < 0 or face_array.max() >= len(vertices)):
        raise SessionError("mesh.obj: a face refers to a vertex that is not there")

    classes_path = session.root / "mesh_classes.u8"
    if classes_path.exists():
        classes = np.fromfile(classes_path, dtype=np.uint8)
    else:
        classes = np.zeros(len(faces), dtype=np.uint8)
    if len(classes) != len(faces):
        raise SessionError(
            f"mesh_classes.u8 has {len(classes)} bytes for {len(faces)} faces; "
            "section 9 requires exactly one per face"
        )

    return Mesh(
        vertices=np.array(vertices, dtype=np.float64).reshape(-1, 3),
        faces=face_array,
        classes=classes,
    )


@dataclass
class MeshBuilder:
    """Assemble a mesh from rectangles and write it the way the app does.

    Each rectangle is split into a grid of triangles, because a real ARKit wall
    is hundreds of small faces rather than one big one, and anything that
    clusters faces into planes should be exercised on that shape.
    """

    vertices: list[tuple[float, float, float]] = field(default_factory=list)
    faces: list[tuple[int, int, int]] = field(default_factory=list)
    classes: list[int] = field(default_factory=list)

    def add_quad(
        self,
        origin: tuple[float, float, float],
        edge_u: tuple[float, float, float],
        edge_v: tuple[float, float, float],
        cls: int,
        *,
        cell_m: float = 0.5,
    ) -> None:
        """A rectangle spanned by two edges from ``origin``, in cells of ``cell_m``."""
        p0, u, v = (np.array(x, dtype=np.float64) for x in (origin, edge_u, edge_v))
        nu = max(1, int(np.ceil(np.linalg.norm(u) / cell_m)))
        nv = max(1, int(np.ceil(np.linalg.norm(v) / cell_m)))
        base = len(self.vertices)
        for a in range(nu + 1):
            for b in range(nv + 1):
                point = p0 + u * (a / nu) + v * (b / nv)
                self.vertices.append((float(point[0]), float(point[1]), float(point[2])))
        for a in range(nu):
            for b in range(nv):
                i = base + a * (nv + 1) + b
                j = i + nv + 1
                self.faces.append((i, j, i + 1))
                self.faces.append((i + 1, j, j + 1))
                self.classes.extend((cls, cls))

    def mesh(self) -> Mesh:
        return Mesh(
            vertices=np.array(self.vertices, dtype=np.float64).reshape(-1, 3),
            faces=np.array(self.faces, dtype=np.int64).reshape(-1, 3),
            classes=np.array(self.classes, dtype=np.uint8),
        )

    def write(self, root: Path) -> None:
        """Write ``mesh.obj``, ``mesh_classes.u8`` and ``mesh.json`` under ``root``."""
        lines = [f"v {x:.4f} {y:.4f} {z:.4f}\n" for x, y, z in self.vertices]
        lines += [f"f {a + 1} {b + 1} {c + 1}\n" for a, b, c in self.faces]
        (root / "mesh.obj").write_text("".join(lines), encoding="utf-8")
        (root / "mesh_classes.u8").write_bytes(bytes(self.classes))
        summary = {
            "anchors": 1,
            "vertices": len(self.vertices),
            "faces": len(self.faces),
            "class_histogram": self.mesh().histogram(),
        }
        (root / "mesh.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
