"""One store, many projects (ADR-0033).

Until 2026-11-13 the store kept one ``plans/`` folder, one ``alignments/`` and
one ``inspect/`` for everything in it, so two projects with a level of the same
name shared a drawing. Now each project is a store of its own under
``<store>/projects/<project>/``, with the layout every module already reads::

    <store>/
      .inbox/                      uploads in flight (section 14.1)
      .pairing-code
      projects/
        our-house/
          sessions/our-house/<session-id>/
          plans/  alignments/  inspect/  markers/
        rehearsal/
          ...

Inside a project nothing changed, which is the point: ``ingest``, ``plan``,
``align``, ``inspect`` and ``model`` are handed a project's folder and work as
they did. Only the edges know there is more than one: the server, which routes
an upload by the project its manifest names and indexes every project; and
the command line, which picks the project before it calls anything.

A store from before this has ``sessions/`` at its top. It is not migrated:
the owner chose to start again (2026-11-13). It is noticed and said.
"""

from __future__ import annotations

import json
import re
import shutil
import zipfile
from pathlib import Path
from typing import Any

from .index import build_index

PROJECTS = "projects"
#: What a session is filed under when its manifest names no project.
DEFAULT_PROJECT = "default"
SLUG = re.compile(r"^[a-z0-9-]{1,24}$")


class StoreError(Exception):
    """The store cannot answer: no such project, or more than one to choose from."""


def project_store(store: str | Path, project: str) -> Path:
    """The folder that is ``project``'s own store. Not created here."""
    if not SLUG.match(project):
        raise StoreError(f"{project!r} is not a project slug (lowercase letters, digits, dashes)")
    return Path(store) / PROJECTS / project


def project_slugs(store: str | Path) -> list[str]:
    root = Path(store) / PROJECTS
    if not root.is_dir():
        return []
    return sorted(
        child.name for child in root.iterdir() if child.is_dir() and SLUG.match(child.name)
    )


def is_legacy(store: str | Path) -> bool:
    """Whether this is a store from before projects: ``sessions/`` at its top."""
    return (Path(store) / "sessions").is_dir()


LEGACY_NOTE = (
    "this store has captures at its top, from before projects; they stay where they are. "
    "Captures sent from now on are kept per project under projects/. For a clean start, "
    "point --store at a new, empty folder."
)


def resolve_project(store: str | Path, project: str | None) -> str:
    """The project a command means: the one named, or the only one there is."""
    if project:
        if not SLUG.match(project):
            raise StoreError(f"{project!r} is not a project slug")
        return project
    found = project_slugs(store)
    if len(found) == 1:
        return found[0]
    if not found:
        raise StoreError(
            f"no project in {store} yet; send a capture from the phone, or name one with --project"
        )
    raise StoreError(f"more than one project here ({', '.join(found)}); say which with --project")


def find_session(store: str | Path, session_id: str) -> Path | None:
    """A session's folder, whichever project holds it; or, in a store with no
    projects, wherever it sits under ``sessions/``."""
    for pattern in (f"{PROJECTS}/*/sessions/*/{session_id}", f"sessions/*/{session_id}"):
        matches = sorted(Path(store).glob(pattern))
        if matches:
            return matches[0]
    return None


def store_of(store: str | Path, path: str | Path) -> Path | None:
    """The project store a path lies in, when it lies in one of this store's."""
    root = (Path(store) / PROJECTS).resolve()
    try:
        relative = Path(path).resolve().relative_to(root)
    except ValueError:
        return None
    return root / relative.parts[0] if relative.parts else None


def manifest_project(manifest: dict[str, Any]) -> str | None:
    project = manifest.get("project")
    if isinstance(project, dict) and project.get("slug") and SLUG.match(str(project["slug"])):
        return str(project["slug"])
    return None


def peek_project(source: str | Path) -> str | None:
    """The project the first session in ``source`` says it belongs to.

    ``source`` is what ``ingest`` takes: a session folder, a project folder,
    or a zip of either. Read before anything is copied, because which
    project's store receives it has to be known first.
    """
    source = Path(source)
    try:
        if source.is_dir():
            candidates = [source / "manifest.json", *sorted(source.glob("*/manifest.json"))]
            for candidate in candidates:
                if candidate.is_file():
                    return manifest_project(json.loads(candidate.read_text(encoding="utf-8")))
        elif zipfile.is_zipfile(source):
            with zipfile.ZipFile(source) as archive:
                names = sorted(
                    (name for name in archive.namelist() if name.endswith("manifest.json")),
                    key=lambda name: name.count("/"),
                )
                if names:
                    return manifest_project(json.loads(archive.read(names[0]).decode("utf-8")))
    except (OSError, ValueError, zipfile.BadZipFile):
        return None
    return None


def build_store_index(store: str | Path) -> dict[str, Any]:
    """Section 14's index over every project, with each page's path from the
    store's top, which is what the server serves from."""
    store = Path(store)
    merged = build_index(store)
    projects = list(merged.get("projects") or [])
    for slug in project_slugs(store):
        prefix = f"{PROJECTS}/{slug}/"
        for project in build_index(project_store(store, slug)).get("projects") or []:
            for level in project.get("levels") or []:
                for key in ("plan", "inspect"):
                    if level.get(key):
                        level[key] = prefix + level[key]
            for session in project.get("sessions") or []:
                if session.get("path"):
                    session["path"] = prefix + session["path"]
            projects.append(project)
    merged["projects"] = projects
    return merged


def delete_project(store: str | Path, project: str) -> dict[str, int]:
    """Remove a project from the store: its captures, plans, placements and
    pages. Returns what went, counted before it went."""
    target = project_store(store, project)
    if not target.is_dir():
        raise StoreError(f"no project {project!r} in {store}")
    sessions = len(list(target.glob("sessions/*/*/manifest.json")))
    plans = len(list(target.glob("plans/*.json")))
    size = sum(path.stat().st_size for path in target.rglob("*") if path.is_file())
    shutil.rmtree(target)
    return {"sessions": sessions, "plans": plans, "bytes": size}
