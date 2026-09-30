"""Ingest is the only thing that writes a raw session, so the tests are mostly
about what it refuses to do."""

from __future__ import annotations

import json
import shutil
import zipfile
from pathlib import Path

import pytest
from PIL import Image

from vividhome.ingest import IngestError, ingest
from vividhome.plan import add_plan, calibrate, load_calibration
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


def plan_beside(session: Path, level: str = "main", **overrides) -> Path:
    """Write ``plans/<level>.{png,json}`` the way the app lays a project out:
    beside the session, in the project folder (section 13)."""
    plans = session.parent / "plans"
    plans.mkdir(parents=True, exist_ok=True)
    Image.new("RGB", (300, 200), (255, 255, 255)).save(plans / f"{level}.png", "PNG")
    data = {
        "level": level,
        "image": f"{level}.png",
        "metres_per_pixel": None,
        "origin_px": None,
        "rotation_deg": 0.0,
        "floor_height_m": 0.0,
    }
    data.update(overrides)
    (plans / f"{level}.json").write_text(json.dumps(data, indent=2), encoding="utf-8")
    return plans


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


def test_the_manifest_decides_the_project(tmp_path: Path, session: Path):
    """A capture is filed under the project it says it belongs to.

    This is the bug the owner's second real session found. `ingest` filed every
    session under a --project that defaulted to "default" and never looked at the
    manifest, while `align` and the marker map read the project slug *from* the
    manifest. So a capture the app recorded under "our-house" landed in
    `sessions/default/` and everything derived from it went to `our-house/` —
    two projects for one room, and nothing said so.
    """
    store = tmp_path / "data"
    result = ingest(store, session)
    assert result.destination.parent == store / "sessions" / "synthetic"


def test_the_manifest_decides_the_project_for_a_zip(tmp_path: Path, session: Path):
    """The zip path resolves the project too, not just the directory path.

    Worth its own test because the archive has to be staged somewhere before its
    manifest can be read, so the two paths reach the project slug differently.
    """
    store = tmp_path / "data"
    archive = zip_session(session, tmp_path / "capture.zip")
    result = ingest(store, archive)
    assert result.destination.parent == store / "sessions" / "synthetic"


def test_ingest_files_a_session_where_align_will_look_for_it(tmp_path: Path, session: Path):
    """The store's shape and the session's own record of itself agree.

    Asserted against align.project_slug rather than a repeated literal, so this
    keeps holding if the two ever disagree again for some new reason.
    """
    from vividhome.align import project_slug
    from vividhome.session import Session

    store = tmp_path / "data"
    result = ingest(store, session)
    loaded = Session.load(result.destination)
    assert result.destination.parent.name == project_slug(loaded)


def test_an_explicit_project_still_overrides_the_manifest(tmp_path: Path, session: Path):
    """The flag is an override, not dead weight: it is how a session gets re-filed."""
    store = tmp_path / "data"
    result = ingest(store, session, "somewhere-else")
    assert result.destination.parent == store / "sessions" / "somewhere-else"


def test_no_staging_directory_is_left_at_the_store_root(tmp_path: Path, session: Path):
    """Staging moved to the store root when the project stopped being known up front."""
    store = tmp_path / "data"
    archive = zip_session(session, tmp_path / "capture.zip")
    ingest(store, archive)
    assert not list(store.glob(".ingest-*"))


# The plan travels with the capture (ADR-0025, section 13)


PLACEMENTS = [{"room": "room", "x": 120, "y": 80, "placed_at": "2026-09-18T10:00:00Z"}]
ORIGINAL = {"file": "main.source.pdf", "kind": "pdf", "page": 1}


def test_a_plan_beside_the_session_comes_across_verbatim(tmp_path: Path, session: Path):
    """The app already imported the drawing and placed the rooms on it; the PC
    should not have to be shown the same sheet a second time."""
    plans = plan_beside(session, "main", rooms=PLACEMENTS, source=ORIGINAL)
    (plans / "main.source.pdf").write_bytes(b"%PDF-1.4 the retained original")

    store = tmp_path / "data"
    result = ingest(store, session)
    assert result.ok

    [plan] = result.plans
    assert plan.level == "main"
    assert plan.imported
    assert plan.files == ["main.png", "main.json", "main.source.pdf"]
    assert "plan calibrate --level main" in plan.reason

    copied = store / "plans"
    assert (copied / "main.png").read_bytes() == (plans / "main.png").read_bytes()
    assert (copied / "main.source.pdf").read_bytes() == (plans / "main.source.pdf").read_bytes()
    assert json.loads((copied / "main.json").read_text(encoding="utf-8")) == json.loads(
        (plans / "main.json").read_text(encoding="utf-8")
    ), "the app's file, byte for byte in meaning: rooms and source included"

    # And the pipeline reads what came across: uncalibrated, placements intact.
    loaded = load_calibration(store, "main")
    assert not loaded.is_calibrated
    assert loaded.extra["rooms"] == PLACEMENTS


def test_the_phone_side_is_left_alone_when_the_plan_comes_across(tmp_path: Path, session: Path):
    plans = plan_beside(session, "main", rooms=PLACEMENTS)
    before = {p.name: p.read_bytes() for p in plans.iterdir()}
    ingest(tmp_path / "data", session)
    assert {p.name: p.read_bytes() for p in plans.iterdir()} == before


def test_a_plan_comes_across_from_a_zip_of_the_project_folder(tmp_path: Path, session: Path):
    """Sharing the project folder rather than one session is the layout the app
    keeps, so the plan is in the archive and has to be found there before the
    staging directory is removed."""
    plan_beside(session, "main", rooms=PLACEMENTS)
    project = session.parent
    archive = tmp_path / "project.zip"
    with zipfile.ZipFile(archive, "w") as zf:
        for item in sorted(project.rglob("*")):
            if item.is_file():
                zf.write(item, Path(project.name) / item.relative_to(project))

    store = tmp_path / "data"
    result = ingest(store, archive)
    assert result.ok
    [plan] = result.plans
    assert plan.imported
    assert load_calibration(store, "main").extra["rooms"] == PLACEMENTS
    assert not list(store.glob(".ingest-*"))


def test_a_plan_the_store_already_has_is_left_alone(tmp_path: Path, session: Path):
    """The PC's copy may be calibrated with alignments solved against it;
    replacing its raster underneath them would move every session on it."""
    store = tmp_path / "data"
    source = tmp_path / "pc-plan.png"
    Image.new("RGB", (400, 300), (250, 250, 250)).save(source, "PNG")
    add_plan(store, source, "main")
    calibrate(
        store,
        "main",
        point_a=(10.0, 10.0),
        point_b=(210.0, 10.0),
        distance_m=4.0,
        origin_px=(10.0, 10.0),
    )
    raster_before = (store / "plans" / "main.png").read_bytes()

    plan_beside(session, "main", rooms=PLACEMENTS)
    result = ingest(store, session)
    assert result.ok

    [plan] = result.plans
    assert not plan.imported
    assert "already in the store" in plan.reason
    assert (store / "plans" / "main.png").read_bytes() == raster_before
    kept = load_calibration(store, "main")
    assert kept.is_calibrated
    assert "rooms" not in kept.extra, "nothing from the phone was merged in"


def test_force_re_ingesting_a_session_does_not_extend_to_its_plan(tmp_path: Path, session: Path):
    plan_beside(session, "main", rooms=PLACEMENTS)
    store = tmp_path / "data"
    first = ingest(store, session)
    assert first.plans[0].imported

    (store / "plans" / "main.json").write_text(
        json.dumps({**json.loads((store / "plans" / "main.json").read_text()), "rooms": []}),
        encoding="utf-8",
    )
    again = ingest(store, session, force=True)
    assert again.ok
    assert not again.plans[0].imported
    assert load_calibration(store, "main").extra["rooms"] == []


def test_a_session_with_no_plans_beside_it_reports_none(tmp_path: Path, session: Path):
    result = ingest(tmp_path / "data", session)
    assert result.plans == []
    assert not (tmp_path / "data" / "plans").exists()


def test_a_plan_that_breaks_section_13_is_skipped_with_a_reason(tmp_path: Path, session: Path):
    """A bad plan file is not a reason to refuse the capture beside it."""
    plans = plan_beside(session, "upper")
    upper = json.loads((plans / "upper.json").read_text(encoding="utf-8"))
    (plans / "upper.json").write_text(json.dumps({**upper, "level": "attic"}))  # rule 1
    plan_beside(session, "basement")
    (plans / "basement.png").unlink()  # rule 2: the raster must be beside it
    plan_beside(session, "garage", image="drawing.png")
    (plans / "loft.json").write_text("{ not json", encoding="utf-8")

    store = tmp_path / "data"
    result = ingest(store, session)
    assert result.ok

    outcome = {plan.level: plan for plan in result.plans}
    assert set(outcome) == {"basement", "garage", "loft", "upper"}
    assert not any(plan.imported for plan in result.plans)
    assert "expected 'upper'" in outcome["upper"].reason
    assert "no basement.png beside it" in outcome["basement"].reason
    assert "section 13 expects 'garage.png'" in outcome["garage"].reason
    assert "does not parse" in outcome["loft"].reason
    assert not (store / "plans").exists()


def test_a_source_file_named_outside_the_plans_folder_is_not_read(tmp_path: Path, session: Path):
    """`source.file` comes from the JSON, so it is untrusted like a zip member name."""
    secret = session.parent / "secret.txt"
    secret.write_text("not a plan", encoding="utf-8")
    plan_beside(session, "main", source={"file": "../secret.txt", "kind": "pdf", "page": 1})

    store = tmp_path / "data"
    result = ingest(store, session)
    [plan] = result.plans
    assert plan.imported, "the raster and the JSON still come across"
    assert plan.files == ["main.png", "main.json"]
    assert not (store / "plans" / "secret.txt").exists()
