"""Captures the app sends, staged in an inbox until ingest takes them (ADR-0029).

The server side of section 14.1. The shape is set by two facts: a capture is
hundreds of files and hundreds of megabytes, so it arrives one file per request
and a send that drops resumes from what is already here; and the server is
reachable from beyond localhost, so everything that lands is treated as hostile
until ``ingest`` has validated it. The inbox is staging under the store, never
the store: raw sessions are still written only by ``ingest``, once, by moving
the finished inbox entry into place.

The pairing code is the lock on the door. It is generated here, printed by
``serve --lan``, typed into the app, and lives in ``<store>/.pairing-code``; it is
never in the repository, and the checks below assume this file's code is read.
"""

from __future__ import annotations

import hmac
import os
import re
import secrets
import shutil
import tempfile
from pathlib import Path
from typing import Any, BinaryIO

from .ingest import IngestError, ingest_inbox

__all__ = [
    "INBOX",
    "MAX_FILE_BYTES",
    "PAIRING_FILE",
    "Inbox",
    "UploadError",
    "code_matches",
    "display_code",
    "ensure_pairing_code",
    "read_pairing_code",
]

#: Session ids as section 1 writes them; anything else is refused before it
#: becomes a directory name.
SESSION_ID = re.compile(r"^\d{8}-\d{6}_[a-z0-9-]{1,24}_[a-z0-9-]{1,24}_[a-z2-7]{6}$")

#: One path segment: plain characters, never starting with a dot.
SEGMENT = re.compile(r"^[A-Za-z0-9_-][A-Za-z0-9_.-]*$")

#: The most one PUT may carry. A keyframe is under half a megabyte, a still a
#: few, and the sample session's mesh is tens; this leaves room without letting
#: one request fill the disk.
MAX_FILE_BYTES = 256 * 1024 * 1024

PAIRING_FILE = ".pairing-code"
INBOX = ".inbox"
CHUNK = 1024 * 1024


class UploadError(Exception):
    """A request that was refused, with the HTTP status it earns."""

    def __init__(self, status: int, message: str):
        super().__init__(message)
        self.status = status
        self.message = message


# --- The pairing code -------------------------------------------------------


def _normalise(code: str) -> str:
    return re.sub(r"[\s-]", "", code).lower()


def read_pairing_code(store: str | Path) -> str | None:
    """The store's code, or None when none has been issued."""
    path = Path(store) / PAIRING_FILE
    try:
        code = _normalise(path.read_text(encoding="utf-8"))
    except OSError:
        return None
    return code or None


def ensure_pairing_code(store: str | Path) -> str:
    """The store's code, issued now if it has none. Owner-readable only where
    the filesystem can say so."""
    existing = read_pairing_code(store)
    if existing:
        return existing
    code = secrets.token_hex(8)
    path = Path(store) / PAIRING_FILE
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(code + "\n", encoding="utf-8")
    try:
        os.chmod(path, 0o600)
    except OSError:  # pragma: no cover - Windows
        pass
    return code


def display_code(code: str) -> str:
    """``3f9a1c2b7e4d0a61`` as ``3f9a-1c2b-7e4d-0a61``, for reading off a screen."""
    code = _normalise(code)
    return "-".join(code[i : i + 4] for i in range(0, len(code), 4))


def code_matches(expected: str, presented: str | None) -> bool:
    """Constant-time comparison, forgiving of case, spaces and dashes."""
    if not presented:
        return False
    return hmac.compare_digest(_normalise(expected), _normalise(presented))


# --- The inbox --------------------------------------------------------------


class Inbox:
    """Where uploads land: ``<store>/.inbox/<session-id>/`` holds the session
    under its own name and, beside it, any ``plans/`` the app sent, so that the
    finished entry is exactly the project-folder shape ``ingest`` already takes."""

    def __init__(self, store: str | Path):
        self.store = Path(store).resolve()
        self.root = self.store / INBOX

    @staticmethod
    def check_id(session_id: str) -> str:
        if not SESSION_ID.match(session_id):
            raise UploadError(400, f"{session_id!r} is not a session id (section 1)")
        return session_id

    def in_store(self, session_id: str) -> bool:
        """Whether the store already holds the session, under any project."""
        sessions = self.store / "sessions"
        if not sessions.is_dir():
            return False
        return any(
            (project / session_id).is_dir()
            for project in sessions.iterdir()
            if project.is_dir() and not project.name.startswith(".")
        )

    def entry(self, session_id: str) -> Path:
        return self.root / self.check_id(session_id)

    def listing(self, session_id: str) -> dict[str, Any]:
        """What the inbox holds for a session, so a client can resume."""
        entry = self.entry(session_id)
        if self.in_store(session_id):
            return {"session_id": session_id, "state": "ingested", "files": {}}
        files: dict[str, int] = {}
        session_dir = entry / session_id
        if session_dir.is_dir():
            for path in session_dir.rglob("*"):
                if path.is_file() and not path.name.endswith(".part"):
                    files[path.relative_to(session_dir).as_posix()] = path.stat().st_size
        for beside in ("plans", "alignments"):
            directory = entry / beside
            if directory.is_dir():
                for path in directory.iterdir():
                    if path.is_file() and not path.name.endswith(".part"):
                        files[f"{beside}/{path.name}"] = path.stat().st_size
        state = "partial" if files else "none"
        return {"session_id": session_id, "state": state, "files": files}

    def target(self, session_id: str, relative: str) -> Path:
        """Where a session-relative path lands, or an UploadError saying why not.

        The path comes from the network, so it is checked as text before it is
        resolved and checked again as a path: two plain segments at most, none
        dotted, ``derived/`` refused because only the pipeline writes it, and
        the result must sit inside this session's entry.
        """
        entry = self.entry(session_id)
        segments = relative.split("/")
        if not 1 <= len(segments) <= 2 or not all(SEGMENT.match(s) for s in segments):
            raise UploadError(400, f"{relative!r} is not a session-relative path (section 2)")
        if segments[0] == "derived":
            raise UploadError(400, "derived/ is written only by the pipeline")
        if segments[0] in ("plans", "alignments"):
            # Beside the session, not in it: the project's plan (section 13)
            # and the capture's own placement (section 15).
            if len(segments) != 2:
                raise UploadError(400, f"{segments[0]}/ holds files, not a file")
            target = entry / segments[0] / segments[1]
        else:
            target = entry / session_id / Path(*segments)
        if not target.resolve().is_relative_to(entry.resolve()):  # pragma: no cover - belt
            raise UploadError(400, "path escapes the inbox")
        return target

    def store_file(self, session_id: str, relative: str, body: BinaryIO, length: int) -> int:
        """Write exactly ``length`` bytes from ``body`` into place, atomically.

        A temporary file beside the target takes the bytes and is renamed over
        it at the end, so a connection that drops halfway leaves nothing under
        the final name, and the listing never reports a half file as whole.
        """
        if length < 0:
            raise UploadError(400, "bad Content-Length")
        if length > MAX_FILE_BYTES:
            raise UploadError(413, f"a file is at most {MAX_FILE_BYTES // (1024 * 1024)} MB")
        if self.in_store(session_id):
            raise UploadError(409, f"{session_id} is already in the store; nothing is replaced")
        target = self.target(session_id, relative)
        target.parent.mkdir(parents=True, exist_ok=True)

        fd, temp_name = tempfile.mkstemp(
            prefix=target.name + ".", suffix=".part", dir=target.parent
        )
        temp = Path(temp_name)
        remaining = length
        try:
            with os.fdopen(fd, "wb") as out:
                while remaining > 0:
                    chunk = body.read(min(CHUNK, remaining))
                    if not chunk:
                        raise UploadError(400, "the body ended before Content-Length was reached")
                    out.write(chunk)
                    remaining -= len(chunk)
            os.replace(temp, target)
        except BaseException:
            temp.unlink(missing_ok=True)
            raise
        return length

    def finish(self, session_id: str) -> dict[str, Any]:
        """Hand the entry to ingest and report what became of it (section 14.1)."""
        entry = self.entry(session_id)
        if self.in_store(session_id):
            raise UploadError(409, f"{session_id} is already in the store")
        if not (entry / session_id / "manifest.json").is_file():
            raise UploadError(
                400, f"nothing to ingest: {session_id} has no manifest.json in the inbox"
            )
        for leftover in entry.rglob("*.part"):
            leftover.unlink(missing_ok=True)
        try:
            result = ingest_inbox(self.store, entry)
        except IngestError as error:
            raise UploadError(400, str(error)) from error
        return {
            "session_id": result.session_id,
            "ingested": True,
            "validated": result.ok,
            "destination": result.destination.relative_to(self.store).as_posix(),
            "errors": [str(finding) for finding in result.report.errors[:5]],
            "warnings": len(result.report.warnings),
            "plans": [
                {"level": plan.level, "imported": plan.imported, "reason": plan.reason}
                for plan in result.plans
            ],
            "alignment": (
                {"adopted": result.alignment.adopted, "reason": result.alignment.reason}
                if result.alignment is not None
                else None
            ),
        }

    def discard(self, session_id: str) -> None:
        """Remove an entry, whatever it holds."""
        shutil.rmtree(self.entry(session_id), ignore_errors=True)
