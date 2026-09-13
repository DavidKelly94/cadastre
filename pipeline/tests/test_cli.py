"""The CLI surface is fixed before the implementations land, so test the surface."""

from __future__ import annotations

import pytest

from cadastre import __version__
from cadastre.cli import NOT_IMPLEMENTED, build_parser, main

#: Every subcommand the MVP promises, per docs/design/pipeline-design.md §1.
MVP_COMMANDS = frozenset(
    {"ingest", "validate", "apriltag", "plan", "align", "inspect", "markers", "synth"}
)

#: A minimal valid invocation of each subcommand, including both plan sub-commands.
STUB_INVOCATIONS = [
    ["ingest", "some-session"],
    ["apriltag", "some-session"],
    ["plan", "add", "plan.pdf", "--level", "main"],
    ["plan", "correct", "plan.jpg", "--level", "main"],
    ["plan", "calibrate", "--level", "main"],
    ["align", "some-session", "--level", "main"],
    ["inspect"],
    ["markers"],
]


def test_help_exits_zero(capsys: pytest.CaptureFixture[str]) -> None:
    with pytest.raises(SystemExit) as exc:
        main(["--help"])
    assert exc.value.code == 0
    assert "cadastre" in capsys.readouterr().out


def test_version_reports_package_version(capsys: pytest.CaptureFixture[str]) -> None:
    with pytest.raises(SystemExit) as exc:
        main(["--version"])
    assert exc.value.code == 0
    assert __version__ in capsys.readouterr().out


#: Subcommands that now do real work, so they are not in STUB_INVOCATIONS.
IMPLEMENTED = frozenset({"validate", "synth"})


def test_every_mvp_command_is_covered() -> None:
    assert {argv[0] for argv in STUB_INVOCATIONS} | IMPLEMENTED == MVP_COMMANDS


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


@pytest.mark.parametrize("argv", STUB_INVOCATIONS, ids=lambda a: " ".join(a[:2]))
def test_stub_reports_not_implemented(argv: list[str], capsys: pytest.CaptureFixture[str]) -> None:
    assert main(argv) == NOT_IMPLEMENTED
    assert "not implemented" in capsys.readouterr().err


def test_store_defaults_and_overrides() -> None:
    assert build_parser().parse_args(["validate", "s"]).store == "./cadastre-data"
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

    store = tmp_path / "cadastre-data"
    session_id = "20261103-141502_main_kitchen_electrical_k3x7qa"
    build_session(store / "sessions" / "our-house" / session_id)
    assert main(["--store", str(store), "validate", session_id]) == 0
    assert session_id in capsys.readouterr().out


def test_synth_writes_a_session_that_validates(
    tmp_path, capsys: pytest.CaptureFixture[str]
) -> None:
    from cadastre.session import Session
    from cadastre.validate import validate_session

    out = tmp_path / "synthetic"
    assert main(["synth", "--out", str(out), "--keyframes", "6"]) == 0
    assert "wrote" in capsys.readouterr().out
    assert validate_session(Session.load(out)).ok


def test_synth_rejects_a_nonsense_keyframe_count(
    tmp_path, capsys: pytest.CaptureFixture[str]
) -> None:
    assert main(["synth", "--out", str(tmp_path / "x"), "--keyframes", "0"]) == 1
    assert "at least 1" in capsys.readouterr().err
