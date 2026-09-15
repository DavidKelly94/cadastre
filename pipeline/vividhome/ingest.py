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


def manifest_project(session: Session) -> str | None:
    """The project slug the capture says it belongs to, or None if it does not say.

    The manifest is the contract (section 4), and the app writes the project it
    captured under. Reading it here is what keeps the store's shape and the
    session's own record of itself from disagreeing.
    """
    project = session.manifest.get("project")
    if isinstance(project, dict) and project.get("slug"):
        return str(project["slug"])
    return None


def ingest(
    store: str | Path,
    source: str | Path,
    project: str | None = None,
    *,
    force: bool = False,
    keep_going: bool = False,
) -> IngestResult:
    """Copy a session into ``<store>/sessions/<project>/<session-id>`` and validate it.

    ``project`` overrides where the session is filed. Left as None, the session's
    own manifest decides, which is what should normally happen: ``align`` and the
    marker map read the project slug from the manifest, so filing a session
    anywhere else puts the capture and everything derived from it under two
    different projects.

    ``force`` replaces an existing session outright. ``keep_going`` keeps a session
    that fails validation instead of removing it, which is what the owner wants
    when the capture is the only one they have and the alternative is losing it.
    """
    source = Path(source)
    if not source.exists():
        raise IngestError(f"{source}: no such file or directory")

    store_root = Path(store)

    # Create the store up front, so an unusable path fails here with something
    # readable instead of five frames down inside pathlib's recursive mkdir.
    # The case that produced this: a --store on a drive letter that does not
    # exist, which raised a bare FileNotFoundError naming 'D:\\' after four
    # nested tracebacks. The owner is the person who runs this command, and a
    # traceback is the worst thing to hand them.
    try:
        store_root.mkdir(parents=True, exist_ok=True)
    except OSError as error:
        raise IngestError(
            f"cannot use {store_root} as the project store ({error.strerror or error}). "
            f"Check the drive exists and you can write to it."
        ) from error

    staging: Path | None = None

    try:
        if source.is_dir():
            session_root = _find_session_root(source)
        elif zipfile.is_zipfile(source):
            # Staged at the store root rather than under the project directory,
            # because which project that is cannot be known until the manifest
            # inside the archive has been read.
            staging = store_root / f".ingest-{source.stem}"
            if staging.exists():
                shutil.rmtree(staging)
            staging.mkdir(parents=True)
            with zipfile.ZipFile(source) as archive:
                _safe_extract(archive, staging)
            session_root = _find_session_root(staging)
        else:
            raise IngestError(f"{source.name}: not a directory or a zip archive")

        try:
            session = Session.load(session_root)
        except SessionError as error:
            raise IngestError(f"{source.name}: {error}") from error
        session_id = session.session_id

        # An explicit --project wins, then the manifest, then "default" for a
        # session old enough not to name one.
        resolved = project or manifest_project(session) or "default"
        destination_root = store_root / "sessions" / resolved
        destination_root.mkdir(parents=True, exist_ok=True)

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
