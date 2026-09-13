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
    ["validate", "some-session"],
    ["apriltag", "some-session"],
    ["plan", "add", "plan.pdf", "--level", "main"],
    ["plan", "correct", "plan.jpg", "--level", "main"],
    ["plan", "calibrate", "--level", "main"],
    ["align", "some-session", "--level", "main"],
    ["inspect"],
    ["markers"],
    ["synth", "--out", "out"],
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


def test_every_mvp_command_is_covered() -> None:
    assert {argv[0] for argv in STUB_INVOCATIONS} == MVP_COMMANDS


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
