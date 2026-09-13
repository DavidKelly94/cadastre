"""Copying a capture off the phone into the project store.

The rule that shapes this module is that raw sessions are immutable. Ingest is
the only thing that writes one, it writes it once, and it refuses to overwrite an
existing session rather than merging into it — a half-overwritten capture is
worse than either version of it.

Sessions arrive either as a folder or as a zip from the Files app.
"""

from __future__ import annotations

import shutil
import zipfile
from dataclasses import dataclass
from pathlib import Path

from .session import Session, SessionError
from .validate import Report, validate_session

__all__ = ["IngestError", "IngestResult", "ingest"]


class IngestError(Exception):
    """A session could not be brought into the store."""


@dataclass
class IngestResult:
    session_id: str
    destination: Path
    bytes_copied: int
    report: Report

    @property
    def ok(self) -> bool:
        return self.report.ok


def _safe_extract(archive: zipfile.ZipFile, destination: Path) -> None:
    """Extract every member, refusing any that would land outside `destination`.

    A zip's member names come from whatever produced the file, so an entry named
    ``../../etc/thing`` — or an absolute path, or a symlink — must not be written
    where it asks. Python's own extractall has sanitised paths since 3.12, but
    this is checked here rather than assumed, because the cost of being wrong is
    writing an attacker-chosen file onto the owner's PC.
    """
    root = destination.resolve()
    for member in archive.infolist():
        target = (destination / member.filename).resolve()
        if not target.is_relative_to(root):
            raise IngestError(f"archive entry escapes the destination: {member.filename!r}")
        # 0xA000 is S_IFLNK in the high bits of external_attr for Unix zips.
        if (member.external_attr >> 16) & 0xF000 == 0xA000:
            raise IngestError(f"archive contains a symlink, which is not read: {member.filename!r}")
    archive.extractall(destination)


def _find_session_root(directory: Path) -> Path:
    """The folder holding manifest.json, which a zip may nest a level or two deep."""
    if (directory / "manifest.json").exists():
        return directory
    candidates = sorted(directory.rglob("manifest.json"))
    if not candidates:
        raise IngestError("no manifest.json found; this does not look like a session")
    if len(candidates) > 1:
        names = ", ".join(str(path.parent.relative_to(directory)) for path in candidates[:4])
        raise IngestError(
            f"more than one session in this archive ({names}); ingest them one at a time"
        )
    return candidates[0].parent


def _directory_size(path: Path) -> int:
    return sum(item.stat().st_size for item in path.rglob("*") if item.is_file())


def ingest(
    store: str | Path,
    source: str | Path,
    project: str,
    *,
    force: bool = False,
    keep_going: bool = False,
) -> IngestResult:
    """Copy a session into ``<store>/sessions/<project>/<session-id>`` and validate it.

    ``force`` replaces an existing session outright. ``keep_going`` keeps a session
    that fails validation instead of removing it, which is what the owner wants
    when the capture is the only one they have and the alternative is losing it.
    """
    source = Path(source)
    if not source.exists():
        raise IngestError(f"{source}: no such file or directory")

    destination_root = Path(store) / "sessions" / project
    staging: Path | None = None

    try:
        if source.is_dir():
            session_root = _find_session_root(source)
        elif zipfile.is_zipfile(source):
            staging = destination_root / f".ingest-{source.stem}"
            if staging.exists():
                shutil.rmtree(staging)
            staging.mkdir(parents=True)
            with zipfile.ZipFile(source) as archive:
                _safe_extract(archive, staging)
            session_root = _find_session_root(staging)
        else:
            raise IngestError(f"{source.name}: not a directory or a zip archive")

        try:
            session_id = Session.load(session_root).session_id
        except SessionError as error:
            raise IngestError(f"{source.name}: {error}") from error

        destination = destination_root / session_id
        if destination.exists():
            if not force:
                raise IngestError(
                    f"{session_id} is already in the store. Raw sessions are never modified; "
                    "pass --force to replace it."
                )
            shutil.rmtree(destination)

        destination.parent.mkdir(parents=True, exist_ok=True)
        if staging is not None and session_root.is_relative_to(staging):
            shutil.move(str(session_root), str(destination))
        else:
            shutil.copytree(session_root, destination)
    finally:
        if staging is not None and staging.exists():
            shutil.rmtree(staging, ignore_errors=True)

    report = validate_session(Session.load(destination))
    if not report.ok and not keep_going:
        shutil.rmtree(destination)
        raise IngestError(
            f"{session_id} failed validation and was not kept:\n"
            + "\n".join(f"  {finding}" for finding in report.errors[:5])
            + "\nPass --keep-going to ingest it anyway."
        )

    return IngestResult(
        session_id=session_id,
        destination=destination,
        bytes_copied=_directory_size(destination),
        report=report,
    )
