"""Copying a capture off the phone into the project store.

The rule that shapes this module is that raw sessions are immutable. Ingest is
the only thing that writes one, it writes it once, and it refuses to overwrite an
existing session rather than merging into it — a half-overwritten capture is
worse than either version of it.

Sessions arrive either as a folder or as a zip from the Files app, one at a time
or a whole project folder at once: the owner's visit is several rooms and then
everything to the PC afterwards, and one command per room was friction for no
reason. When the project's ``plans/`` folder is beside the sessions — the app's
own layout, section 13 — the plan comes across with the captures, which is what
ADR-0025 promised and what saves importing the same drawing twice.
"""

from __future__ import annotations

import json
import shutil
import zipfile
from dataclasses import dataclass, field
from pathlib import Path

from .plan import PlanCalibration, alignments_using, plan_paths
from .session import Session, SessionError
from .validate import Report, validate_session, write_report

__all__ = [
    "AlignmentImport",
    "IngestBatch",
    "IngestError",
    "IngestResult",
    "PlanImport",
    "ingest",
    "ingest_inbox",
    "ingest_many",
]


class IngestError(Exception):
    """A session could not be brought into the store."""


@dataclass
class PlanImport:
    """What became of one ``plans/<level>.json`` found beside the session."""

    level: str
    imported: bool
    #: One sentence for the owner: what was copied, or why nothing was.
    reason: str
    files: list[str] = field(default_factory=list)


@dataclass
class AlignmentImport:
    """What became of the placement the app made for this capture (section 15)."""

    adopted: bool
    reason: str


@dataclass
class IngestResult:
    session_id: str
    destination: Path
    bytes_copied: int
    report: Report
    plans: list[PlanImport] = field(default_factory=list)
    alignment: AlignmentImport | None = None

    @property
    def ok(self) -> bool:
        return self.report.ok


@dataclass
class IngestBatch:
    """Every session in a source, taken one by one: what landed and what did not."""

    results: list[IngestResult] = field(default_factory=list)
    #: ``(what the session was called, why it was not ingested)``.
    failures: list[tuple[str, str]] = field(default_factory=list)
    plans: list[PlanImport] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return not self.failures and all(result.ok for result in self.results)


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


def _find_session_roots(directory: Path) -> list[Path]:
    """Every folder holding a manifest.json, which a zip may nest a level or two deep."""
    if (directory / "manifest.json").exists():
        return [directory]
    roots = sorted(path.parent for path in directory.rglob("manifest.json"))
    if not roots:
        raise IngestError("no manifest.json found; this does not look like a session")
    return roots


def _find_session_root(directory: Path) -> Path:
    """The one session in a source, for the single-session entry point."""
    roots = _find_session_roots(directory)
    if len(roots) > 1:
        names = ", ".join(str(root.relative_to(directory)) for root in roots[:4])
        raise IngestError(
            f"more than one session here ({names}); 'vividhome ingest' takes them all, "
            "or point it at one"
        )
    return roots[0]


def _directory_size(path: Path) -> int:
    return sum(item.stat().st_size for item in path.rglob("*") if item.is_file())


def _import_plans(store_root: Path, session_root: Path) -> list[PlanImport]:
    """Copy the project's plans found beside the session into the store.

    Section 13 puts ``plans/`` beside a project's sessions on the phone, and
    ADR-0025 says the plan travels to the PC with the capture. The store keeps
    one ``plans/`` for everything (a known inconsistency, section 13), so a level
    is copied only when the store has no plan for it yet: a plan already there
    may be calibrated and aligned against, and replacing its raster under those
    alignments would move every session drawn on it. Replacing one on purpose is
    ``vividhome plan add``.

    Files are copied verbatim. The app's ``rooms`` and ``source`` are part of the
    JSON and survive; nothing here rewrites what the app wrote.
    """
    # ``session_root`` may be a real session folder or any path directly under
    # the project folder; only its parent matters here.
    source_dir = session_root.parent / "plans"
    if not source_dir.is_dir():
        return []

    results: list[PlanImport] = []
    for json_path in sorted(source_dir.glob("*.json")):
        level = json_path.stem
        try:
            raw = json.loads(json_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            results.append(PlanImport(level, False, f"{json_path.name} does not parse ({error})"))
            continue
        if not isinstance(raw, dict) or raw.get("level") != level:
            found = raw.get("level") if isinstance(raw, dict) else None
            results.append(
                PlanImport(
                    level, False, f"{json_path.name} says level {found!r}, expected {level!r}"
                )
            )
            continue

        image_path, target_json = plan_paths(store_root, level)
        image_name = str(raw.get("image") or "")
        if image_name != image_path.name:
            results.append(
                PlanImport(
                    level,
                    False,
                    f"{json_path.name} names its raster {image_name!r}; "
                    f"section 13 expects {image_path.name!r}",
                )
            )
            continue
        source_image = source_dir / image_name
        if not source_image.is_file():
            results.append(
                PlanImport(level, False, f"{json_path.name} has no {image_name} beside it")
            )
            continue
        if target_json.exists():
            # ADR-0030: the phone may calibrate. A store copy that has no scale
            # and no alignments depends on nothing, so a calibrated copy from
            # the phone replaces it; a calibrated store copy is the frame its
            # alignments were solved in and stays.
            stored = _stored_calibration(target_json)
            incoming_calibrated = (
                raw.get("metres_per_pixel") is not None and raw.get("origin_px") is not None
            )
            if (
                stored is not None
                and not stored.is_calibrated
                and incoming_calibrated
                and not alignments_using(store_root, level)
            ):
                shutil.copyfile(source_image, image_path)
                shutil.copyfile(json_path, target_json)
                results.append(
                    PlanImport(
                        level,
                        True,
                        "the store's copy had no scale; replaced by the calibrated one from "
                        "the phone (ADR-0030)",
                        [image_path.name, target_json.name],
                    )
                )
                continue
            results.append(
                PlanImport(
                    level,
                    False,
                    "already in the store and left alone; "
                    "'vividhome plan add' replaces it deliberately",
                )
            )
            continue

        image_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source_image, image_path)
        shutil.copyfile(json_path, target_json)
        files = [image_path.name, target_json.name]

        # The retained original, when the app kept one. Its name comes from the
        # JSON, so it is checked to sit inside plans/ before being read: the
        # file is the owner's, but a zip's contents are only as trusted as its
        # member names, and those are already guarded.
        original = raw.get("source")
        if isinstance(original, dict) and original.get("file"):
            original_path = (source_dir / str(original["file"])).resolve()
            target_original = image_path.parent / original_path.name
            if (
                original_path.is_relative_to(source_dir.resolve())
                and original_path.is_file()
                and not target_original.exists()
            ):
                shutil.copyfile(original_path, target_original)
                files.append(target_original.name)

        results.append(
            PlanImport(
                level,
                True,
                f"copied from beside the session ({', '.join(files)}); "
                f"calibrate it with 'vividhome plan calibrate --level {level}'",
                files,
            )
        )
    return results


def _import_alignment(
    store_root: Path, session_root: Path, session_id: str
) -> AlignmentImport | None:
    """Adopt ``alignments/<session-id>.json`` found beside the session, when it
    is the app's placement of this capture and the store can use it (ADR-0031,
    section 15).

    Adopted only when the store has no alignment for the session yet, the
    level's plan in the store is calibrated, and that calibration is the one
    the phone solved against, which is the plan the phone sent beside the
    capture. Anything else is reported and left for ``vividhome align``, which
    replaces an alignment deliberately. None when the app sent nothing.
    """
    source = session_root.parent / "alignments" / f"{session_id}.json"
    if not source.is_file():
        return None
    try:
        raw = json.loads(source.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        return AlignmentImport(False, f"{source.name} does not parse ({error})")
    if (
        not isinstance(raw, dict)
        or raw.get("session_id") != session_id
        or not raw.get("level")
        or not isinstance(raw.get("T_hs"), list)
        or len(raw["T_hs"]) != 16
    ):
        return AlignmentImport(False, f"{source.name} is not an alignment file (section 15)")
    level = str(raw["level"])

    target = store_root / "alignments" / f"{session_id}.json"
    if target.exists():
        return AlignmentImport(
            False,
            "the store already has an alignment for this capture; "
            "'vividhome align' replaces it deliberately",
        )
    stored = _stored_calibration(store_root / "plans" / f"{level}.json")
    if stored is None or not stored.is_calibrated:
        return AlignmentImport(False, f"the store has no calibrated plan for level {level!r}")
    phone = _stored_calibration(session_root.parent / "plans" / f"{level}.json")
    if phone is not None and phone.is_calibrated:
        same = (
            abs(float(phone.metres_per_pixel) - float(stored.metres_per_pixel)) < 1e-9
            and tuple(float(v) for v in phone.origin_px)
            == tuple(float(v) for v in stored.origin_px)
            and abs(float(phone.rotation_deg) - float(stored.rotation_deg)) < 1e-9
        )
        if not same:
            return AlignmentImport(
                False,
                f"solved against a different calibration of level {level!r} than the "
                "store's; run 'vividhome align' on the PC",
            )

    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, target)
    rms = raw.get("rms_m")
    how = f"{float(rms):.3f} m" if isinstance(rms, (int, float)) else "no residual given"
    return AlignmentImport(
        True,
        f"placed by the app, residual {how}; 'vividhome align' replaces it deliberately",
    )


def _stored_calibration(json_path: Path) -> PlanCalibration | None:
    try:
        return PlanCalibration.from_dict(json.loads(json_path.read_text(encoding="utf-8")))
    except (OSError, json.JSONDecodeError, KeyError, TypeError, ValueError):
        return None


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

    A ``plans/`` folder beside the session (the app's layout, section 13) is
    copied into the store for every level the store has no plan for yet; see
    :func:`_import_plans`. ``force`` does not extend to plans.
    """
    store_root = _prepare_store(store)
    source = Path(source)
    staging: Path | None = None
    try:
        directory, staging = _stage(store_root, source)
        session_root = _find_session_root(directory)
        result = _ingest_root(
            store_root,
            session_root,
            source.name,
            project,
            staging=staging,
            force=force,
            keep_going=keep_going,
        )
        # Before the staging directory goes: for a zip, plans/ is only there.
        # Plans first: the placement is adopted only against the calibration
        # the store ends up with.
        result.plans = _import_plans(store_root, session_root)
        result.alignment = _import_alignment(store_root, session_root, result.session_id)
    finally:
        if staging is not None and staging.exists():
            shutil.rmtree(staging, ignore_errors=True)
    return result


def ingest_many(
    store: str | Path,
    source: str | Path,
    project: str | None = None,
    *,
    force: bool = False,
    keep_going: bool = False,
) -> IngestBatch:
    """Ingest every session in ``source`` — a session folder, a project folder,
    or a zip of either — and keep going past the ones that fail.

    One session's refusal (already in the store, failed validation) is reported
    beside the others rather than stopping the batch: the owner copied a whole
    visit off the phone and wants to know what landed, not to be told about the
    first problem and nothing else. ``plans/`` beside the sessions is imported
    once per folder that holds one.
    """
    store_root = _prepare_store(store)
    source = Path(source)
    batch = IngestBatch()
    staging: Path | None = None
    try:
        directory, staging = _stage(store_root, source)
        roots = _find_session_roots(directory)
        # Plans once per project folder, not once per session in it, and
        # first: a placement is adopted only against the calibration the
        # store ends up with.
        for parent in sorted({root.parent for root in roots}):
            batch.plans.extend(_import_plans(store_root, parent / "_"))
        for session_root in roots:
            try:
                result = _ingest_root(
                    store_root,
                    session_root,
                    session_root.name,
                    project,
                    staging=staging,
                    force=force,
                    keep_going=keep_going,
                )
            except IngestError as error:
                batch.failures.append((session_root.name, str(error)))
                continue
            result.alignment = _import_alignment(store_root, session_root, result.session_id)
            batch.results.append(result)
    finally:
        if staging is not None and staging.exists():
            shutil.rmtree(staging, ignore_errors=True)
    return batch


def ingest_inbox(store: str | Path, entry: str | Path) -> IngestResult:
    """Take a session the app uploaded (section 14.1) into the store, by moving it.

    ``entry`` is one inbox entry: the session under its own name and, beside
    it, any ``plans/`` the app sent, which is the project-folder shape the other
    entry points take. It is staging, so the session moves rather than copies,
    and the entry is removed afterwards whatever happened to it. A session that
    fails validation is kept: the phone still has the capture and the owner
    decides at the PC, where the report is, rather than the upload silently
    producing nothing.
    """
    store_root = _prepare_store(store)
    entry = Path(entry)
    try:
        session_root = _find_session_root(entry)
        result = _ingest_root(
            store_root,
            session_root,
            session_root.name,
            None,
            staging=entry,
            force=False,
            keep_going=True,
        )
        result.plans = _import_plans(store_root, session_root)
        result.alignment = _import_alignment(store_root, session_root, result.session_id)
    finally:
        shutil.rmtree(entry, ignore_errors=True)
    return result


def _prepare_store(store: str | Path) -> Path:
    """Create the store up front, so an unusable path fails here with something
    readable instead of five frames down inside pathlib's recursive mkdir.

    The case that produced this: a --store on a drive letter that does not
    exist, which raised a bare FileNotFoundError naming 'D:\\' after four
    nested tracebacks. The owner is the person who runs this command, and a
    traceback is the worst thing to hand them.
    """
    store_root = Path(store)
    try:
        store_root.mkdir(parents=True, exist_ok=True)
    except OSError as error:
        raise IngestError(
            f"cannot use {store_root} as the project store ({error.strerror or error}). "
            f"Check the drive exists and you can write to it."
        ) from error
    return store_root


def _stage(store_root: Path, source: Path) -> tuple[Path, Path | None]:
    """The directory to look for sessions in, and the staging folder if a zip
    was unpacked to make one. The caller removes the staging folder."""
    if not source.exists():
        raise IngestError(f"{source}: no such file or directory")
    if source.is_dir():
        return source, None
    if not zipfile.is_zipfile(source):
        raise IngestError(f"{source.name}: not a directory or a zip archive")
    # Staged at the store root rather than under the project directory,
    # because which project that is cannot be known until the manifest
    # inside the archive has been read.
    staging = store_root / f".ingest-{source.stem}"
    if staging.exists():
        shutil.rmtree(staging)
    staging.mkdir(parents=True)
    with zipfile.ZipFile(source) as archive:
        _safe_extract(archive, staging)
    return staging, staging


def _ingest_root(
    store_root: Path,
    session_root: Path,
    source_name: str,
    project: str | None,
    *,
    staging: Path | None,
    force: bool,
    keep_going: bool,
) -> IngestResult:
    """Copy one session folder into the store and validate it."""
    try:
        session = Session.load(session_root)
    except SessionError as error:
        raise IngestError(f"{source_name}: {error}") from error
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

    stored = Session.load(destination)
    report = validate_session(stored)
    if not report.ok and not keep_going:
        shutil.rmtree(destination)
        raise IngestError(
            f"{session_id} failed validation and was not kept:\n"
            + "\n".join(f"  {finding}" for finding in report.errors[:5])
            + "\nPass --keep-going to ingest it anyway."
        )
    # The report is the PC's word on the capture: the index serves it to the
    # phone (section 14) and inspect reads it, so it is written here, where the
    # check ran, rather than only when 'validate --json' is run by hand.
    write_report(stored, report)

    return IngestResult(
        session_id=session_id,
        destination=destination,
        bytes_copied=_directory_size(destination),
        report=report,
    )
