"""What the store holds, for a client that cannot list directories.

``GET /index.json`` on ``vividhome serve``, section 14 of the format. The app on
the phone has to know what the PC has rendered without guessing file names, so
this walks the store and says: which projects, which sessions, which of them are
aligned and validated, which levels have a plan and an inspection page. It is
generated on request from the files and never stored, so it cannot be stale
against the store it describes; ``generated_at`` is when the client asked.
"""

from __future__ import annotations

import json
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from . import __version__
from .plan import PlanCalibration

__all__ = ["build_index"]


def _read_json(path: Path) -> dict | None:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    return data if isinstance(data, dict) else None


def _alignments(store: Path) -> dict[str, str]:
    """Session id to the level it was aligned on."""
    out: dict[str, str] = {}
    directory = store / "alignments"
    if directory.is_dir():
        for path in sorted(directory.glob("*.json")):
            data = _read_json(path)
            if data and data.get("session_id") and data.get("level"):
                out[str(data["session_id"])] = str(data["level"])
    return out


def _plans(store: Path) -> dict[str, dict[str, Any]]:
    out: dict[str, dict[str, Any]] = {}
    directory = store / "plans"
    if directory.is_dir():
        for path in sorted(directory.glob("*.json")):
            data = _read_json(path)
            if not data:
                continue
            try:
                calibration = PlanCalibration.from_dict(data)
            except (KeyError, TypeError, ValueError):
                continue
            out[path.stem] = {
                "plan": f"plans/{calibration.image}",
                "calibrated": calibration.is_calibrated,
            }
    return out


def _session_entry(store: Path, project: str, session_dir: Path) -> dict[str, Any]:
    manifest = _read_json(session_dir / "manifest.json") or {}
    level = manifest.get("level")
    level_slug = str(level.get("slug")) if isinstance(level, dict) and level.get("slug") else None
    if level_slug is None:
        parts = session_dir.name.split("_")
        level_slug = parts[1] if len(parts) == 4 else None

    report = _read_json(session_dir / "derived" / "validate.json")
    validated = bool(report.get("ok")) if report and "ok" in report else None

    return {
        "session_id": session_dir.name,
        "path": f"sessions/{project}/{session_dir.name}",
        "level": level_slug,
        "aligned": False,
        "validated": validated,
    }


def build_index(store: str | Path) -> dict[str, Any]:
    """Describe the store as section 14 specifies."""
    store = Path(store)
    alignments = _alignments(store)
    plans = _plans(store)

    projects = []
    sessions_root = store / "sessions"
    if sessions_root.is_dir():
        for project_dir in sorted(sessions_root.iterdir()):
            if not project_dir.is_dir() or project_dir.name.startswith("."):
                continue
            sessions = []
            for session_dir in sorted(project_dir.iterdir()):
                if not session_dir.is_dir() or not (session_dir / "manifest.json").exists():
                    continue
                entry = _session_entry(store, project_dir.name, session_dir)
                entry["aligned"] = entry["session_id"] in alignments
                sessions.append(entry)

            # A level belongs to a project through its sessions: the ones recorded
            # on it, and the ones aligned to it. The store's plans/ is not scoped
            # by project (section 13), so this is how the index scopes it.
            level_slugs = {s["level"] for s in sessions if s["level"]}
            level_slugs |= {alignments[s["session_id"]] for s in sessions if s["aligned"]}
            levels = []
            for slug in sorted(level_slugs & plans.keys()):
                page = store / "inspect" / f"{slug}.html"
                levels.append(
                    {
                        "level": slug,
                        "plan": plans[slug]["plan"],
                        "calibrated": plans[slug]["calibrated"],
                        "inspect": f"inspect/{slug}.html" if page.exists() else None,
                        "sessions": [
                            s["session_id"]
                            for s in sessions
                            if alignments.get(s["session_id"]) == slug
                        ],
                    }
                )
            projects.append({"slug": project_dir.name, "levels": levels, "sessions": sessions})

    return {
        "vividhome": __version__,
        "generated_at": datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "store": store.name,
        "projects": projects,
    }
