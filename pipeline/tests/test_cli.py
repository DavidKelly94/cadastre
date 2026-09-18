"""The CLI surface is fixed before the implementations land, so test the surface."""

from __future__ import annotations

import pytest

from vividhome import __version__
from vividhome.cli import _HANDLERS, NOT_IMPLEMENTED, build_parser, main

#: Every subcommand the MVP promises, per docs/design/pipeline-design.md §1.
MVP_COMMANDS = frozenset(
    {"ingest", "validate", "apriltag", "plan", "align", "inspect", "markers", "synth"}
)

#: Commands beyond the MVP: `corners` is the offline half of ai-roadmap item 5,
#: `coverage` the per-wall answer to "what did I miss".
EXTRA_COMMANDS = frozenset({"corners", "coverage"})


def test_help_exits_zero(capsys: pytest.CaptureFixture[str]) -> None:
    with pytest.raises(SystemExit) as exc:
        main(["--help"])
    assert exc.value.code == 0
    assert "vividhome" in capsys.readouterr().out


def test_version_reports_package_version(capsys: pytest.CaptureFixture[str]) -> None:
    with pytest.raises(SystemExit) as exc:
        main(["--version"])
    assert exc.value.code == 0
    assert __version__ in capsys.readouterr().out


def test_every_mvp_command_is_registered_and_implemented() -> None:
    """Every command the design promises exists and does real work.

    This began as a check that the stubs were all present. Nothing is stubbed
    now, so it checks the stronger thing: the parser and the dispatch table agree
    with the design, in both directions.
    """
    parser_commands = {
        choice
        for action in build_parser()._actions
        for choice in (action.choices or {})
        if isinstance(action.choices, dict)
    }
    assert parser_commands >= MVP_COMMANDS | EXTRA_COMMANDS
    assert set(_HANDLERS) == MVP_COMMANDS | EXTRA_COMMANDS


def test_a_command_without_a_handler_still_exits_cleanly(monkeypatch) -> None:
    """The NOT_IMPLEMENTED path is the guard for a parser entry added without a
    handler. It has no callers now, so it is exercised deliberately."""
    handlers = dict(_HANDLERS)
    handlers.pop("validate")
    monkeypatch.setattr("vividhome.cli._HANDLERS", handlers)
    assert main(["validate", "anything"]) == NOT_IMPLEMENTED


def test_no_command_is_an_error() -> None:
    with pytest.raises(SystemExit) as exc:
        main([])
    assert exc.value.code == 2


def test_unknown_command_is_an_error() -> None:
    with pytest.raises(SystemExit) as exc:
        main(["nope"])
    assert exc.value.code == 2


def test_plan_requires_a_sub_command() -> None:
    with pytest.raises(SystemExit) as exc:
        main(["plan"])
    assert exc.value.code == 2


def test_plan_add_then_calibrate(tmp_path, capsys: pytest.CaptureFixture[str]) -> None:
    from PIL import Image

    source = tmp_path / "plan.png"
    Image.new("RGB", (400, 300), (255, 255, 255)).save(source, "PNG")
    store = str(tmp_path / "vividhome-data")

    assert main(["--store", store, "plan", "add", str(source), "--level", "main"]) == 0
    assert "wrote" in capsys.readouterr().out

    assert (
        main(
            [
                "--store",
                store,
                "plan",
                "calibrate",
                "--level",
                "main",
                "--scale-points",
                "100,100 300,100",
                "--distance",
                "12' 6\"",
                "--origin",
                "100,100",
            ]
        )
        == 0
    )
    printed = capsys.readouterr().out
    assert "calibrated" in printed
    assert "mm per pixel" in printed


def test_plan_reports_a_bad_distance(tmp_path, capsys: pytest.CaptureFixture[str]) -> None:
    from PIL import Image

    source = tmp_path / "plan.png"
    Image.new("RGB", (40, 30), (255, 255, 255)).save(source, "PNG")
    store = str(tmp_path / "vividhome-data")
    main(["--store", store, "plan", "add", str(source), "--level", "main"])
    capsys.readouterr()

    code = main(
        [
            "--store",
            store,
            "plan",
            "calibrate",
            "--level",
            "main",
            "--scale-points",
            "0,0 10,0",
            "--distance",
            "about three metres",
            "--origin",
            "0,0",
        ]
    )
    assert code == 1
    assert "cannot read" in capsys.readouterr().err


def test_store_defaults_and_overrides() -> None:
    assert build_parser().parse_args(["validate", "s"]).store == "./vividhome-data"
    assert build_parser().parse_args(["--store", "/tmp/x", "validate", "s"]).store == "/tmp/x"


def test_validate_runs_and_reports(session_dir, capsys: pytest.CaptureFixture[str]) -> None:
    assert main(["validate", str(session_dir)]) == 0
    assert "keyframes" in capsys.readouterr().out


def test_validate_exits_one_on_a_broken_session(
    session_dir, capsys: pytest.CaptureFixture[str]
) -> None:
    (session_dir / "depth" / "000000.f32").unlink()
    assert main(["validate", str(session_dir)]) == 1
    assert "FAILED" in capsys.readouterr().out


def test_validate_writes_the_json_report(session_dir, capsys: pytest.CaptureFixture[str]) -> None:
    assert main(["validate", str(session_dir), "--json"]) == 0
    capsys.readouterr()
    assert (session_dir / "derived" / "validate.json").exists()


def test_validate_reports_a_path_that_is_not_a_session(
    tmp_path, capsys: pytest.CaptureFixture[str]
) -> None:
    assert main(["--store", str(tmp_path), "validate", "nope"]) == 1
    assert "not a session directory" in capsys.readouterr().err


def test_validate_finds_a_session_by_id_within_the_store(
    tmp_path, capsys: pytest.CaptureFixture[str]
) -> None:
    from helpers import build_session

    store = tmp_path / "vividhome-data"
    session_id = "20261103-141502_main_kitchen_k3x7qa"
    build_session(store / "sessions" / "our-house" / session_id)
    assert main(["--store", str(store), "validate", session_id]) == 0
    assert session_id in capsys.readouterr().out


def test_synth_writes_a_session_that_validates(
    tmp_path, capsys: pytest.CaptureFixture[str]
) -> None:
    from vividhome.session import Session
    from vividhome.validate import validate_session

    out = tmp_path / "synthetic"
    assert main(["synth", "--out", str(out), "--keyframes", "6"]) == 0
    assert "wrote" in capsys.readouterr().out
    assert validate_session(Session.load(out)).ok


def test_synth_rejects_a_nonsense_keyframe_count(
    tmp_path, capsys: pytest.CaptureFixture[str]
) -> None:
    assert main(["synth", "--out", str(tmp_path / "x"), "--keyframes", "0"]) == 1
    assert "at least 1" in capsys.readouterr().err


def test_apriltag_solves_a_synthetic_session(tmp_path, capsys: pytest.CaptureFixture[str]) -> None:
    out = tmp_path / "synthetic"
    assert main(["synth", "--out", str(out)]) == 0
    capsys.readouterr()

    assert main(["apriltag", str(out), "--check-anchor-frame"]) == 0
    printed = capsys.readouterr().out
    assert "VH-012" in printed
    assert "anchor frame agreement" in printed
    assert (out / "derived" / "markers_detected.json").exists()


def test_inspect_reports_when_nothing_is_aligned(
    tmp_path, capsys: pytest.CaptureFixture[str]
) -> None:
    assert main(["--store", str(tmp_path / "empty"), "inspect"]) == 1
    assert "run 'vividhome align'" in capsys.readouterr().err


def test_ingest_then_validate_by_id(tmp_path, capsys: pytest.CaptureFixture[str]) -> None:
    from vividhome.synth import SynthSpec, build

    captured = build(
        tmp_path / "capture" / "20261103-141502_main_room_framing_aaaaaa",
        SynthSpec(keyframes=4, colour_w=160, colour_h=120),
    )
    store = str(tmp_path / "vividhome-data")

    assert main(["--store", store, "ingest", str(captured.root), "--project", "our-house"]) == 0
    assert "ingested" in capsys.readouterr().out

    assert main(["--store", store, "validate", captured.root.name]) == 0
    assert "OK" in capsys.readouterr().out


def test_ingest_refuses_a_duplicate(tmp_path, capsys: pytest.CaptureFixture[str]) -> None:
    from vividhome.synth import SynthSpec, build

    captured = build(
        tmp_path / "capture" / "20261103-141502_main_room_framing_aaaaaa",
        SynthSpec(keyframes=4, colour_w=160, colour_h=120),
    )
    store = str(tmp_path / "vividhome-data")
    main(["--store", store, "ingest", str(captured.root)])
    capsys.readouterr()

    assert main(["--store", store, "ingest", str(captured.root)]) == 1
    assert "already in the store" in capsys.readouterr().err


def test_a_closed_pipe_is_not_an_error(tmp_path, monkeypatch) -> None:
    """`vividhome ... | head` closes the pipe; that is the reader's choice."""
    from vividhome import cli

    def explode(_args):
        raise BrokenPipeError

    monkeypatch.setitem(cli._HANDLERS, "validate", explode)
    monkeypatch.setattr(cli.os, "dup2", lambda *a, **k: None)
    assert cli.main(["validate", str(tmp_path)]) == cli.BROKEN_PIPE


def test_an_interrupt_exits_cleanly(
    tmp_path, monkeypatch, capsys: pytest.CaptureFixture[str]
) -> None:
    from vividhome import cli

    def explode(_args):
        raise KeyboardInterrupt

    monkeypatch.setitem(cli._HANDLERS, "validate", explode)
    assert cli.main(["validate", str(tmp_path)]) == 130
    assert "interrupted" in capsys.readouterr().err


def test_markers_writes_the_pdf_and_the_pngs(tmp_path, capsys: pytest.CaptureFixture[str]) -> None:
    assert (
        main(
            [
                "markers",
                "--out",
                str(tmp_path / "markers.pdf"),
                "--png",
                str(tmp_path / "Markers"),
                "--ids",
                "0-2",
            ]
        )
        == 0
    )
    printed = capsys.readouterr().out
    assert "3 pages" in printed
    assert "200 mm" in printed
    assert (tmp_path / "markers.pdf").exists()
    assert sorted(p.name for p in (tmp_path / "Markers").iterdir()) == [
        "VH-000.png",
        "VH-001.png",
        "VH-002.png",
    ]


def test_markers_needs_a_destination(capsys: pytest.CaptureFixture[str]) -> None:
    assert main(["markers", "--ids", "0-1"]) == 1
    assert "--out, --png, or both" in capsys.readouterr().err


def test_markers_reports_a_bad_id_range(tmp_path, capsys: pytest.CaptureFixture[str]) -> None:
    assert main(["markers", "--out", str(tmp_path / "x.pdf"), "--ids", "9-2"]) == 1
    assert "backwards" in capsys.readouterr().err


def test_plan_calibrate_says_what_is_missing_without_web(
    tmp_path, capsys: pytest.CaptureFixture[str]
) -> None:
    """Without --web the points must be given, and the message names which."""
    from PIL import Image

    source = tmp_path / "plan.png"
    Image.new("RGB", (40, 30), (255, 255, 255)).save(source, "PNG")
    store = str(tmp_path / "vividhome-data")
    main(["--store", store, "plan", "add", str(source), "--level", "main"])
    capsys.readouterr()

    assert main(["--store", store, "plan", "calibrate", "--level", "main"]) == 1
    error = capsys.readouterr().err
    assert "--scale-points" in error
    assert "--distance" in error
    assert "--origin" in error
    assert "without --web" in error


def test_validate_can_skip_the_image_and_depth_checks(
    session_dir, capsys: pytest.CaptureFixture[str]
) -> None:
    """Skipping is for long sessions and for output that has no JPEGs at all."""
    (session_dir / "rgb" / "000000.jpg").write_bytes(b"not-a-real-jpeg")

    assert main(["validate", str(session_dir)]) == 1
    capsys.readouterr()

    assert main(["validate", str(session_dir), "--skip-images"]) == 0
    printed = capsys.readouterr().out
    assert "note: images not checked" in printed
    assert "OK" in printed


class TestPairsParsing:
    """`--pairs` has to express the labels the app actually writes.

    The app labels a landmark "<room> <kind> <n>" — "bedroom corner 1" — on
    purpose, so it still means something to whoever pairs it with a drawing
    later. Splitting the whole string on whitespace made those labels
    unexpressible: the first real attempt failed with `expected 'label=x,y', got
    'bedroom'`. Nothing caught it because the app's labels and this parser were
    built apart and never run together.
    """

    def test_semicolons_separate_labels_that_contain_spaces(self):
        from vividhome.cli import _clicks

        clicks = _clicks("bedroom corner 1=890,100;bedroom window 1=1072,183")
        assert clicks == {
            "bedroom corner 1": (890.0, 100.0),
            "bedroom window 1": (1072.0, 183.0),
        }

    def test_whitespace_still_separates_labels_without_spaces(self):
        from vividhome.cli import _clicks

        assert _clicks("corner-nw=100,100 corner-ne=900,100") == {
            "corner-nw": (100.0, 100.0),
            "corner-ne": (900.0, 100.0),
        }

    def test_surrounding_space_and_trailing_separators_are_tolerated(self):
        from vividhome.cli import _clicks

        assert _clicks(" a b=1,2 ; c d=3,4 ; ") == {"a b": (1.0, 2.0), "c d": (3.0, 4.0)}

    def test_a_token_with_no_equals_is_reported_with_the_token(self):
        import pytest

        from vividhome.cli import _clicks

        with pytest.raises(ValueError, match="expected 'label=x,y'"):
            _clicks("bedroom corner 1;890,100")

    def test_an_empty_label_is_refused(self):
        import pytest

        from vividhome.cli import _clicks

        with pytest.raises(ValueError, match="expected 'label=x,y'"):
            _clicks("=890,100")

    def test_a_string_of_only_separators_is_refused(self):
        import pytest

        from vividhome.cli import _clicks

        with pytest.raises(ValueError, match="held no pairs"):
            _clicks(" ; ; ")


def test_ingest_says_what_became_of_the_plan(tmp_path, capsys: pytest.CaptureFixture[str]) -> None:
    """The plan step is the one the owner used to do twice, so its outcome is
    printed rather than left to be discovered at `plan calibrate`."""
    import json

    from PIL import Image

    from vividhome.synth import SynthSpec, build

    captured = build(
        tmp_path / "our-house" / "20261103-141502_main_room_framing_aaaaaa",
        SynthSpec(keyframes=4, colour_w=160, colour_h=120),
    )
    plans = tmp_path / "our-house" / "plans"
    plans.mkdir()
    Image.new("RGB", (100, 80), (255, 255, 255)).save(plans / "main.png", "PNG")
    (plans / "main.json").write_text(
        json.dumps({"level": "main", "image": "main.png", "rooms": []}), encoding="utf-8"
    )

    store = str(tmp_path / "store")
    assert main(["--store", store, "ingest", str(captured.root)]) == 0
    out = capsys.readouterr().out
    assert "plan main: copied from beside the session (main.png, main.json)" in out
    assert "vividhome plan calibrate --level main" in out

    assert main(["--store", store, "ingest", str(captured.root), "--force"]) == 0
    assert "plan main: already in the store and left alone" in capsys.readouterr().out


def test_corners_runs_on_a_synthetic_session(tmp_path, capsys: pytest.CaptureFixture[str]) -> None:
    from vividhome.synth import SynthSpec, build

    captured = build(
        tmp_path / "20261103-141502_main_room_framing_aaaaaa",
        SynthSpec(keyframes=2, colour_w=160, colour_h=120),
    )
    assert main(["corners", str(captured.root)]) == 0
    out = capsys.readouterr().out
    assert "4 wall plane(s)" in out
    assert "4 corner candidate(s)" in out
    assert "against 4 tapped corner(s): 4 within 0.20 m (100%)" in out
    assert "Candidates, not measurements" in out
    assert (captured.root / "derived" / "corner_candidates.json").exists()


def test_corners_says_when_there_is_no_mesh(
    session_dir, capsys: pytest.CaptureFixture[str]
) -> None:
    assert main(["corners", str(session_dir)]) == 1
    assert "no mesh.obj" in capsys.readouterr().err


def test_coverage_runs_on_a_synthetic_session(tmp_path, capsys: pytest.CaptureFixture[str]) -> None:
    from vividhome.synth import SynthSpec, build

    captured = build(
        tmp_path / "20261103-141502_main_room_framing_aaaaaa",
        SynthSpec(keyframes=24),
    )
    assert main(["coverage", str(captured.root)]) == 0
    out = capsys.readouterr().out
    assert "footprint: 4 tapped corners" in out
    assert "corner-nw -> corner-ne" in out
    assert "Measured against the corners you tapped" in out
    assert (captured.root / "derived" / "coverage.json").exists()


def test_coverage_needs_a_footprint(session_dir, capsys: pytest.CaptureFixture[str]) -> None:
    assert main(["coverage", str(session_dir)]) == 1
    assert "at least three" in capsys.readouterr().err
