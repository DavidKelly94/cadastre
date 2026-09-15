"""Ingest is the only thing that writes a raw session, so the tests are mostly
about what it refuses to do."""

from __future__ import annotations

import shutil
import zipfile
from pathlib import Path

import pytest

from vividhome.ingest import IngestError, ingest
from vividhome.synth import SynthSpec, build

SPEC = SynthSpec(keyframes=4, colour_w=160, colour_h=120)


@pytest.fixture
def session(tmp_path: Path) -> Path:
    return build(tmp_path / "capture" / "20261103-141502_main_room_framing_aaaaaa", SPEC).root


def zip_session(session: Path, target: Path, *, prefix: str = "") -> Path:
    with zipfile.ZipFile(target, "w") as archive:
        for item in sorted(session.rglob("*")):
            if item.is_file():
                arcname = Path(prefix) / session.name / item.relative_to(session)
                archive.write(item, arcname)
    return target


def test_ingests_a_directory(tmp_path: Path, session: Path):
    store = tmp_path / "vividhome-data"
    result = ingest(store, session, "our-house")

    assert result.ok
    assert result.session_id == session.name
    assert result.destination == store / "sessions" / "our-house" / session.name
    assert (result.destination / "manifest.json").exists()
    assert result.bytes_copied > 0


def test_the_original_is_left_alone(tmp_path: Path, session: Path):
    before = sorted(p.name for p in session.iterdir())
    ingest(tmp_path / "data", session, "our-house")
    assert sorted(p.name for p in session.iterdir()) == before


def test_ingests_a_zip(tmp_path: Path, session: Path):
    archive = zip_session(session, tmp_path / "capture.zip")
    result = ingest(tmp_path / "data", archive, "our-house")
    assert result.ok
    assert (result.destination / "frames.jsonl").exists()


def test_ingests_a_zip_with_a_nested_folder(tmp_path: Path, session: Path):
    archive = zip_session(session, tmp_path / "nested.zip", prefix="Downloads/exports")
    result = ingest(tmp_path / "data", archive, "our-house")
    assert result.ok
    assert result.session_id == session.name


def test_no_staging_directory_is_left_behind(tmp_path: Path, session: Path):
    store = tmp_path / "data"
    archive = zip_session(session, tmp_path / "capture.zip")
    ingest(store, archive, "our-house")
    leftovers = list((store / "sessions" / "our-house").glob(".ingest-*"))
    assert leftovers == []


def test_an_existing_session_is_never_silently_replaced(tmp_path: Path, session: Path):
    store = tmp_path / "data"
    first = ingest(store, session, "our-house")
    marker = first.destination / "derived" / "note.txt"
    marker.parent.mkdir(parents=True, exist_ok=True)
    marker.write_text("derived work", encoding="utf-8")

    with pytest.raises(IngestError, match="already in the store"):
        ingest(store, session, "our-house")
    assert marker.exists(), "the refusal must not have touched anything"


def test_force_replaces_an_existing_session(tmp_path: Path, session: Path):
    store = tmp_path / "data"
    first = ingest(store, session, "our-house")
    stale = first.destination / "derived" / "note.txt"
    stale.parent.mkdir(parents=True, exist_ok=True)
    stale.write_text("stale", encoding="utf-8")

    again = ingest(store, session, "our-house", force=True)
    assert again.ok
    assert not stale.exists(), "force must replace, not merge"


def test_a_zip_that_escapes_the_destination_is_refused(tmp_path: Path, session: Path):
    """Member names come from whatever wrote the zip, so they are untrusted."""
    archive = tmp_path / "evil.zip"
    with zipfile.ZipFile(archive, "w") as zf:
        zf.writestr("../../pwned.txt", "nope")
        zf.writestr(f"{session.name}/manifest.json", "{}")

    with pytest.raises(IngestError, match="escapes the destination"):
        ingest(tmp_path / "data", archive, "our-house")
    assert not (tmp_path / "pwned.txt").exists()
    assert not (tmp_path.parent / "pwned.txt").exists()


def test_a_zip_containing_a_symlink_is_refused(tmp_path: Path, session: Path):
    archive = tmp_path / "link.zip"
    with zipfile.ZipFile(archive, "w") as zf:
        info = zipfile.ZipInfo(f"{session.name}/evil")
        info.external_attr = (0xA1FF) << 16  # S_IFLNK | 0777
        zf.writestr(info, "/etc/passwd")
        zf.writestr(f"{session.name}/manifest.json", "{}")

    with pytest.raises(IngestError, match="symlink"):
        ingest(tmp_path / "data", archive, "our-house")


def test_a_failing_session_is_not_kept(tmp_path: Path, session: Path):
    (session / "depth" / "000001.f32").unlink()
    store = tmp_path / "data"

    with pytest.raises(IngestError, match="failed validation"):
        ingest(store, session, "our-house")
    assert not (store / "sessions" / "our-house" / session.name).exists()


def test_keep_going_ingests_a_failing_session_anyway(tmp_path: Path, session: Path):
    """When the capture is the only one there is, losing it is the worse outcome."""
    (session / "depth" / "000001.f32").unlink()
    store = tmp_path / "data"

    result = ingest(store, session, "our-house", keep_going=True)
    assert not result.ok
    assert result.destination.exists()
    assert result.report.errors


def test_something_that_is_not_a_session_is_rejected(tmp_path: Path):
    plain = tmp_path / "holiday-photos"
    plain.mkdir()
    (plain / "beach.jpg").write_bytes(b"not a session")

    with pytest.raises(IngestError, match="does not look like a session"):
        ingest(tmp_path / "data", plain, "our-house")


def test_a_zip_with_two_sessions_is_rejected(tmp_path: Path, session: Path):
    second = session.parent / "20261103-150000_main_hall_framing_bbbbbb"
    shutil.copytree(session, second)

    archive = tmp_path / "both.zip"
    with zipfile.ZipFile(archive, "w") as zf:
        for root in (session, second):
            for item in sorted(root.rglob("*")):
                if item.is_file():
                    zf.write(item, Path(root.name) / item.relative_to(root))

    with pytest.raises(IngestError, match="one at a time"):
        ingest(tmp_path / "data", archive, "our-house")


def test_a_missing_source_is_reported(tmp_path: Path):
    with pytest.raises(IngestError, match="no such file"):
        ingest(tmp_path / "data", tmp_path / "gone", "our-house")


def test_a_file_that_is_not_an_archive_is_reported(tmp_path: Path):
    plain = tmp_path / "notes.txt"
    plain.write_text("hello", encoding="utf-8")
    with pytest.raises(IngestError, match="not a directory or a zip"):
        ingest(tmp_path / "data", plain, "our-house")


def test_the_ingested_session_is_findable_by_id(tmp_path: Path, session: Path):
    from vividhome.cli import resolve_session

    store = tmp_path / "data"
    result = ingest(store, session, "our-house")
    assert resolve_session(str(store), result.session_id) == result.destination


def test_unusable_store_gives_a_readable_error(tmp_path):
    """A store path that cannot be created fails with a message, not a traceback.

    The real case was `--store D:\\vividhome-data` on a machine with no D: drive:
    pathlib's recursive mkdir raised a bare FileNotFoundError naming the drive
    root, five frames deep. The owner runs this command.
    """
    # A file where a directory must go is the portable way to make mkdir fail.
    blocker = tmp_path / "not-a-directory"
    blocker.write_text("", encoding="utf-8")
    # The source has to exist, or the earlier check fires first and this proves
    # nothing about the store.
    source = tmp_path / "session.zip"
    source.write_text("", encoding="utf-8")

    with pytest.raises(IngestError) as caught:
        ingest(blocker, source, "default")

    message = str(caught.value)
    assert "as the project store" in message
    assert "Check the drive exists" in message
