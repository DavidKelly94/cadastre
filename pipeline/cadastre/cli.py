"""Command-line entry point.

Every subcommand of the MVP is registered here so the surface is fixed before the
implementations land; each one currently exits with NOT_IMPLEMENTED. Implementation
order is in docs/design/pipeline-design.md: transforms, session, validate, synth,
markers, apriltag, plan, align, inspector, ingest.
"""

from __future__ import annotations

import argparse
import sys
from collections.abc import Sequence
from pathlib import Path

from . import __version__

#: Exit code for a subcommand that is registered but not yet implemented.
NOT_IMPLEMENTED = 2

#: Default project store, relative to the working directory.
DEFAULT_STORE = "./cadastre-data"


def _add_ingest(sub: argparse._SubParsersAction) -> None:
    p = sub.add_parser("ingest", help="copy or unzip a session into the store, then validate")
    p.add_argument("source", help="session directory or .zip produced by the app")
    p.add_argument("--project", default="default", help="project the session belongs to")


def _add_validate(sub: argparse._SubParsersAction) -> None:
    p = sub.add_parser("validate", help="check a session against docs/session-format.md")
    p.add_argument("session", help="session directory or id within the store")
    p.add_argument("--json", action="store_true", help="also write derived/validate.json")


def _add_apriltag(sub: argparse._SubParsersAction) -> None:
    p = sub.add_parser("apriltag", help="detect printed markers and solve their poses")
    p.add_argument("session", help="session directory or id within the store")
    p.add_argument("--stride", type=int, default=1, help="use every Nth keyframe")
    p.add_argument(
        "--tag-size",
        type=float,
        default=0.128,
        help="AprilTag black-square side in metres (the 20 cm marker carries 12.8 cm of tag)",
    )
    p.add_argument(
        "--check-anchor-frame",
        action="store_true",
        help="compare ARKit marker anchors against the solved poses and report per-axis agreement",
    )


def _add_plan(sub: argparse._SubParsersAction) -> None:
    p = sub.add_parser("plan", help="import, correct and calibrate architectural plans")
    plan_sub = p.add_subparsers(dest="plan_command", required=True)

    add = plan_sub.add_parser("add", help="rasterize a PDF or image into the store")
    add.add_argument("file", help="source PDF or image")
    add.add_argument("--level", required=True, help="level slug, e.g. main")
    add.add_argument("--page", type=int, default=1, help="page number for a PDF source")
    add.add_argument("--dpi", type=int, default=200, help="rasterizing resolution")

    correct = plan_sub.add_parser("correct", help="perspective-correct a photographed plan")
    correct.add_argument("file", help="source image")
    correct.add_argument("--level", required=True, help="level slug")
    correct.add_argument(
        "--corners",
        required=True,
        help="the four sheet corners as 'x,y x,y x,y x,y': top-left, top-right, "
        "bottom-right, bottom-left",
    )

    calibrate = plan_sub.add_parser("calibrate", help="set scale, origin and rotation for a level")
    calibrate.add_argument("--level", required=True, help="level slug")
    calibrate.add_argument(
        "--scale-points", required=True, help="two pixels a known distance apart, 'x,y x,y'"
    )
    calibrate.add_argument(
        "--distance", required=True, help="the real distance between them, e.g. 3.81m or 12' 6\""
    )
    calibrate.add_argument("--origin", required=True, help="the pixel at house (0, 0), 'x,y'")
    calibrate.add_argument(
        "--rotation-deg", type=float, default=0.0, help="angle from image +u to house +x"
    )
    calibrate.add_argument("--floor-height", type=float, default=0.0, help="level height in metres")
    calibrate.add_argument(
        "--force",
        action="store_true",
        help="recalibrate even though alignments exist, invalidating them",
    )


def _add_align(sub: argparse._SubParsersAction) -> None:
    p = sub.add_parser("align", help="solve the session-to-house transform for one level")
    p.add_argument("session_id", help="session id within the store")
    p.add_argument("--level", required=True, help="level slug")
    p.add_argument(
        "--use-markers",
        action="store_true",
        help="add correspondences from house-frame marker poses seen in earlier sessions",
    )
    p.add_argument("--force", action="store_true", help="write even when the residual is too large")


def _add_inspect(sub: argparse._SubParsersAction) -> None:
    p = sub.add_parser("inspect", help="generate the per-level inspection page")
    p.add_argument("--level", help="level slug; omit to generate every calibrated level")
    p.add_argument("--serve", action="store_true", help="serve the pages instead of only writing")


def _add_markers(sub: argparse._SubParsersAction) -> None:
    p = sub.add_parser("markers", help="generate the printable marker PDF and the bundled PNGs")
    p.add_argument("--out", help="destination PDF path")
    p.add_argument("--png", help="destination directory for the PNG exports")
    p.add_argument("--ids", default="0-59", help="inclusive id range, e.g. 0-59")


def _add_synth(sub: argparse._SubParsersAction) -> None:
    p = sub.add_parser("synth", help="write a synthetic, format-valid session for tests")
    p.add_argument("--out", required=True, help="destination directory")
    p.add_argument("--keyframes", type=int, help="number of keyframes (default: the documented 48)")


def build_parser() -> argparse.ArgumentParser:
    """Build the full argument parser, with every MVP subcommand registered."""
    parser = argparse.ArgumentParser(
        prog="cadastre",
        description="Validate, solve and align Cadastre capture sessions.",
    )
    parser.add_argument("--version", action="version", version=f"cadastre {__version__}")
    parser.add_argument(
        "--store",
        default=DEFAULT_STORE,
        help=f"project store directory (default: {DEFAULT_STORE})",
    )

    sub = parser.add_subparsers(dest="command", required=True, metavar="command")
    for add in (
        _add_ingest,
        _add_validate,
        _add_apriltag,
        _add_plan,
        _add_align,
        _add_inspect,
        _add_markers,
        _add_synth,
    ):
        add(sub)
    return parser


def resolve_session(store: str, value: str) -> Path:
    """Find a session from a path, or from an id inside the store.

    A path is used as given. Otherwise the value is treated as a session id and
    looked up under ``<store>/sessions/<project>/<id>``, so the owner can name a
    session the way it appears in a report rather than by typing its full path.
    """
    direct = Path(value)
    if direct.is_dir():
        return direct
    matches = sorted(Path(store).glob(f"sessions/*/{value}"))
    if len(matches) == 1:
        return matches[0]
    if len(matches) > 1:
        found = ", ".join(str(match) for match in matches)
        raise FileNotFoundError(f"{value!r} matches more than one session: {found}")
    raise FileNotFoundError(f"{value!r} is not a session directory or an id in {store}")


def _run_validate(args: argparse.Namespace) -> int:
    from .session import Session, SessionError
    from .validate import validate_session, write_report

    try:
        session = Session.load(resolve_session(args.store, args.session))
    except (FileNotFoundError, SessionError) as error:
        print(f"cadastre validate: {error}", file=sys.stderr)
        return 1

    report = validate_session(session)
    print(report.render())
    if args.json:
        target = write_report(session, report)
        print(f"\nwrote {target}")
    return report.exit_code


def _points(value: str, count: int) -> list[tuple[float, float]]:
    """Parse ``'x,y x,y'`` into pixel pairs."""
    parts = value.replace(",", " ").split()
    if len(parts) != count * 2:
        raise ValueError(f"expected {count} 'x,y' point(s), got {value!r}")
    numbers = [float(part) for part in parts]
    return [(numbers[i * 2], numbers[i * 2 + 1]) for i in range(count)]


def _run_plan(args: argparse.Namespace) -> int:
    from .plan import (
        PlanError,
        add_plan,
        calibrate,
        correct_perspective,
        parse_distance,
        plan_paths,
    )

    try:
        if args.plan_command == "add":
            result = add_plan(args.store, args.file, args.level, page=args.page, dpi=args.dpi)
            image_path, json_path = plan_paths(args.store, args.level)
            print(f"wrote {image_path}")
            print(f"wrote {json_path}")
            if not result.is_calibrated:
                print(f"\nnext: cadastre plan calibrate --level {args.level} ...")
            return 0

        if args.plan_command == "correct":
            image_path, _ = plan_paths(args.store, args.level)
            target = correct_perspective(args.file, image_path, _points(args.corners, 4))
            print(f"wrote {target}")
            return 0

        result = calibrate(
            args.store,
            args.level,
            point_a=_points(args.scale_points, 2)[0],
            point_b=_points(args.scale_points, 2)[1],
            distance_m=parse_distance(args.distance),
            origin_px=_points(args.origin, 1)[0],
            rotation_deg=args.rotation_deg,
            floor_height_m=args.floor_height,
            force=args.force,
        )
    except (PlanError, ValueError) as error:
        print(f"cadastre plan: {error}", file=sys.stderr)
        return 1

    print(f"level {result.level} calibrated")
    print(f"  {result.metres_per_pixel * 1000:.4f} mm per pixel")
    print(f"  origin at pixel {result.origin_px[0]:.1f}, {result.origin_px[1]:.1f}")
    print(f"  rotation {result.rotation_deg:.2f} deg, floor {result.floor_height_m:.3f} m")
    return 0


def _run_apriltag(args: argparse.Namespace) -> int:
    from .apriltag import aggregate, check_anchor_frame, solve_session, write_detections
    from .session import Session, SessionError

    try:
        session = Session.load(resolve_session(args.store, args.session))
    except (FileNotFoundError, SessionError) as error:
        print(f"cadastre apriltag: {error}", file=sys.stderr)
        return 1

    observations = solve_session(session, stride=args.stride, tag_size_m=args.tag_size)
    solutions = aggregate(observations)
    if not solutions:
        print("no markers detected")
        return 0

    print(f"{len(observations)} accepted observations of {len(solutions)} markers")
    for marker, solution in solutions.items():
        x, y, z = solution.T_wm[:3, 3]
        print(
            f"  {marker}  n={solution.n_obs:<3d} "
            f"({x:+.3f}, {y:+.3f}, {z:+.3f}) m  "
            f"spread {solution.spread_m * 100:.1f} cm / {solution.spread_deg:.1f} deg"
        )

    if args.check_anchor_frame:
        print("\nanchor frame agreement (ARKit anchors via R_am, against PnP):")
        for agreement in check_anchor_frame(session, solutions):
            axes = ", ".join(f"{value:.2f}" for value in agreement.per_axis_deg)
            print(
                f"  {agreement.marker_id}  "
                f"{agreement.translation_error_m * 100:.2f} cm  "
                f"{agreement.rotation_error_deg:.2f} deg  per-axis [{axes}]"
            )

    print(f"\nwrote {write_detections(session, solutions)}")
    return 0


def _run_synth(args: argparse.Namespace) -> int:
    from .synth import SynthSpec, build

    # `is not None`, not truthiness: --keyframes 0 is a value the user typed and
    # must reach the check below, not silently fall back to the default.
    spec = SynthSpec(keyframes=args.keyframes) if args.keyframes is not None else SynthSpec()
    if spec.keyframes < 1:
        print("cadastre synth: --keyframes must be at least 1", file=sys.stderr)
        return 1
    result = build(Path(args.out), spec)
    print(f"wrote {result.root} ({spec.keyframes} keyframes)")
    for identifier in sorted(result.marker_poses):
        print(f"  marker {identifier}")
    return 0


#: Subcommands that are implemented. Everything else still exits NOT_IMPLEMENTED.
_HANDLERS = {
    "validate": _run_validate,
    "synth": _run_synth,
    "apriltag": _run_apriltag,
    "plan": _run_plan,
}


def main(argv: Sequence[str] | None = None) -> int:
    """Parse arguments and dispatch. Returns the process exit code."""
    args = build_parser().parse_args(argv)

    handler = _HANDLERS.get(args.command)
    if handler is not None:
        return handler(args)

    name = args.command
    if getattr(args, "plan_command", None):
        name = f"{args.command} {args.plan_command}"
    print(f"cadastre {name}: not implemented", file=sys.stderr)
    return NOT_IMPLEMENTED


if __name__ == "__main__":  # pragma: no cover - exercised via the console script
    raise SystemExit(main())
