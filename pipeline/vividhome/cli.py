"""Command-line entry point.

Every subcommand of the MVP is registered here so the surface is fixed before the
implementations land; each one currently exits with NOT_IMPLEMENTED. Implementation
order is in docs/design/pipeline-design.md: transforms, session, validate, synth,
markers, apriltag, plan, align, inspector, ingest.
"""

from __future__ import annotations

import argparse
import contextlib
import os
import sys
from collections.abc import Sequence
from pathlib import Path

from . import __version__

#: Exit code for a subcommand that is registered but not yet implemented.
NOT_IMPLEMENTED = 2

#: Default project store, relative to the working directory.
DEFAULT_STORE = "./vividhome-data"


def _add_ingest(sub: argparse._SubParsersAction) -> None:
    p = sub.add_parser("ingest", help="copy or unzip a session into the store, then validate")
    p.add_argument("source", help="session directory or .zip produced by the app")
    p.add_argument("--project", default="default", help="project the session belongs to")
    p.add_argument("--force", action="store_true", help="replace a session already in the store")
    p.add_argument(
        "--keep-going",
        action="store_true",
        help="keep the session even if it fails validation",
    )


def _add_validate(sub: argparse._SubParsersAction) -> None:
    p = sub.add_parser("validate", help="check a session against docs/session-format.md")
    p.add_argument("session", help="session directory or id within the store")
    p.add_argument("--json", action="store_true", help="also write derived/validate.json")
    p.add_argument(
        "--skip-images",
        action="store_true",
        help="do not decode the JPEGs (much faster on a long session)",
    )
    p.add_argument(
        "--skip-depth", action="store_true", help="do not read the depth maps for rule 6"
    )


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
        "--web", action="store_true", help="click the points in a browser instead"
    )
    calibrate.add_argument("--port", type=int, default=8765, help="port for --web")
    calibrate.add_argument("--scale-points", help="two pixels a known distance apart, 'x,y x,y'")
    calibrate.add_argument(
        "--distance", help="the real distance between them, e.g. 3.81m or 12' 6\""
    )
    calibrate.add_argument("--origin", help="the pixel at house (0, 0), 'x,y'")
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
        "--pairs",
        help="landmark to plan-pixel pairs, 'label=x,y label=x,y' (at least two, "
        "or use --use-markers)",
    )
    p.add_argument("--web", action="store_true", help="click the pairs in a browser instead")
    p.add_argument("--port", type=int, default=8765, help="port for --web")
    p.add_argument(
        "--use-markers",
        action="store_true",
        help="add correspondences from house-frame marker poses seen in earlier sessions",
    )
    p.add_argument("--force", action="store_true", help="write even when the residual is too large")


def _add_inspect(sub: argparse._SubParsersAction) -> None:
    p = sub.add_parser("inspect", help="generate the per-level inspection page")
    p.add_argument("--level", help="level slug; omit to generate every aligned level")
    p.add_argument("--serve", action="store_true", help="serve the pages after writing them")
    p.add_argument("--port", type=int, default=8765, help="port for --serve")
    p.add_argument(
        "--no-thumbnails", action="store_true", help="skip the hover thumbnails (faster)"
    )
    p.add_argument("--thumbnail-stride", type=int, default=5, help="thumbnail every Nth keyframe")


def _add_markers(sub: argparse._SubParsersAction) -> None:
    p = sub.add_parser("markers", help="generate the printable marker PDF and the bundled PNGs")
    p.add_argument("--out", help="destination PDF path")
    p.add_argument("--png", help="destination directory for the PNG exports")
    p.add_argument("--ids", default="0-59", help="ids, e.g. 0-59 or 3,7,12")
    p.add_argument(
        "--page-size", default="letter", choices=["letter", "a4"], help="paper size for the PDF"
    )


def _add_synth(sub: argparse._SubParsersAction) -> None:
    p = sub.add_parser("synth", help="write a synthetic, format-valid session for tests")
    p.add_argument("--out", required=True, help="destination directory")
    p.add_argument("--keyframes", type=int, help="number of keyframes (default: the documented 48)")


def build_parser() -> argparse.ArgumentParser:
    """Build the full argument parser, with every MVP subcommand registered."""
    parser = argparse.ArgumentParser(
        prog="vividhome",
        description="Validate, solve and align VividHome capture sessions.",
    )
    parser.add_argument("--version", action="version", version=f"vividhome {__version__}")
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
        print(f"vividhome validate: {error}", file=sys.stderr)
        return 1

    report = validate_session(
        session, check_images=not args.skip_images, check_depth=not args.skip_depth
    )
    if args.skip_images or args.skip_depth:
        skipped = ", ".join(
            name for name, on in (("images", args.skip_images), ("depth", args.skip_depth)) if on
        )
        print(f"note: {skipped} not checked\n")
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


def _calibrate_in_browser(args: argparse.Namespace):
    """Serve calibrate.html and turn what the owner clicked into arguments."""
    from .plan import load_calibration, parse_distance
    from .webflow import collect, stage

    existing = load_calibration(args.store, args.level)
    task = stage(
        args.store,
        "calibrate.html",
        {
            "level": args.level,
            "image": f"../plans/{existing.image}",
            "rotation_deg": existing.rotation_deg,
            "floor_height_m": existing.floor_height_m,
        },
    )
    result = collect(args.store, task, port=args.port)
    if result is None:
        print("vividhome plan: nothing was saved", file=sys.stderr)
        return None
    return (
        tuple(result["point_a"]),
        tuple(result["point_b"]),
        tuple(result["origin_px"]),
        parse_distance(str(result["distance"])),
        float(result.get("rotation_deg", 0.0)),
        float(result.get("floor_height_m", 0.0)),
    )


def _align_in_browser(args: argparse.Namespace, session, calibration):
    """Serve align.html and turn the clicked pairs into landmark correspondences."""
    from .align import landmark_pairs
    from .webflow import collect, stage

    landmarks = [
        {"label": landmark.label, "xz": [landmark.p_w[0], landmark.p_w[2]]}
        for landmark in session.landmarks()
    ]
    room = session.manifest.get("room")
    task = stage(
        args.store,
        "align.html",
        {
            "session_id": session.session_id,
            "room": room.get("name") if isinstance(room, dict) else "",
            "level": calibration.level,
            "image": f"../plans/{calibration.image}",
            "landmarks": landmarks,
            "trajectory": [[float(p[0]), float(p[2])] for p in session.trajectory()],
        },
    )
    result = collect(args.store, task, port=args.port)
    if result is None:
        print("vividhome align: nothing was saved", file=sys.stderr)
        return None
    clicks = {pair["label"]: tuple(pair["pixel"]) for pair in result.get("pairs", [])}
    return landmark_pairs(session, calibration, clicks)


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
                print(f"\nnext: vividhome plan calibrate --level {args.level} ...")
            return 0

        if args.plan_command == "correct":
            image_path, _ = plan_paths(args.store, args.level)
            target = correct_perspective(args.file, image_path, _points(args.corners, 4))
            print(f"wrote {target}")
            return 0

        if args.web:
            clicked = _calibrate_in_browser(args)
            if clicked is None:
                return 1
            point_a, point_b, origin, distance, rotation, floor = clicked
        else:
            missing = [
                name
                for name, value in (
                    ("--scale-points", args.scale_points),
                    ("--distance", args.distance),
                    ("--origin", args.origin),
                )
                if not value
            ]
            if missing:
                raise ValueError(f"{', '.join(missing)} required without --web")
            point_a, point_b = _points(args.scale_points, 2)
            origin = _points(args.origin, 1)[0]
            distance = parse_distance(args.distance)
            rotation, floor = args.rotation_deg, args.floor_height

        result = calibrate(
            args.store,
            args.level,
            point_a=point_a,
            point_b=point_b,
            distance_m=distance,
            origin_px=origin,
            rotation_deg=rotation,
            floor_height_m=floor,
            force=args.force,
        )
    except (PlanError, ValueError) as error:
        print(f"vividhome plan: {error}", file=sys.stderr)
        return 1

    print(f"level {result.level} calibrated")
    print(f"  {result.metres_per_pixel * 1000:.4f} mm per pixel")
    print(f"  origin at pixel {result.origin_px[0]:.1f}, {result.origin_px[1]:.1f}")
    print(f"  rotation {result.rotation_deg:.2f} deg, floor {result.floor_height_m:.3f} m")
    return 0


def _run_markers(args: argparse.Namespace) -> int:
    from .markers import parse_ids, write_pdf, write_pngs

    if not args.out and not args.png:
        print("vividhome markers: give --out, --png, or both", file=sys.stderr)
        return 1

    try:
        numbers = parse_ids(args.ids)
        if args.out:
            target = write_pdf(args.out, numbers, page_size=args.page_size)
            print(f"wrote {target} ({len(numbers)} pages, {args.page_size})")
            print("  print at 100% with no scaling; the square must measure 200 mm")
        if args.png:
            written = write_pngs(args.png, numbers)
            print(f"wrote {len(written)} PNGs to {args.png}")
    except ValueError as error:
        print(f"vividhome markers: {error}", file=sys.stderr)
        return 1
    return 0


def _run_ingest(args: argparse.Namespace) -> int:
    from .ingest import IngestError, ingest

    try:
        result = ingest(
            args.store,
            args.source,
            args.project,
            force=args.force,
            keep_going=args.keep_going,
        )
    except IngestError as error:
        print(f"vividhome ingest: {error}", file=sys.stderr)
        return 1

    print(f"ingested {result.session_id}")
    print(f"  {result.destination}")
    print(f"  {result.bytes_copied / 1e6:.1f} MB, {result.report.keyframes} keyframes")
    if not result.ok:
        print(f"  kept despite {len(result.report.errors)} validation error(s)")
    elif result.report.warnings:
        print(f"  {len(result.report.warnings)} warning(s); run 'vividhome validate' for detail")
    return 0 if result.ok else 1


def _run_inspect(args: argparse.Namespace) -> int:
    from .inspector import build_page, levels_with_alignments
    from .plan import PlanError

    levels = [args.level] if args.level else levels_with_alignments(args.store)
    if not levels:
        print("no aligned sessions yet; run 'vividhome align' first", file=sys.stderr)
        return 1

    written = []
    for level in levels:
        try:
            written.append(
                build_page(
                    args.store,
                    level,
                    thumbnails=not args.no_thumbnails,
                    thumbnail_stride=args.thumbnail_stride,
                )
            )
        except PlanError as error:
            print(f"vividhome inspect: {error}", file=sys.stderr)
            return 1

    for path in written:
        print(f"wrote {path}")

    if args.serve:
        from .serve import serve

        serve(args.store, port=args.port, open_path=f"inspect/{levels[0]}.html")
    return 0


def _run_align(args: argparse.Namespace) -> int:
    from .align import (
        WARN_RMS_M,
        AlignError,
        landmark_pairs,
        marker_pairs,
        project_slug,
        solve,
        update_marker_map,
        write_alignment,
    )
    from .plan import PlanError, load_calibration
    from .session import Session, SessionError

    try:
        session = Session.load(resolve_session(args.store, args.session_id))
        calibration = load_calibration(args.store, args.level)
        if not calibration.is_calibrated:
            raise PlanError(
                f"level {args.level!r} is not calibrated; run 'vividhome plan calibrate' first"
            )

        pairs = []
        if args.web:
            from_browser = _align_in_browser(args, session, calibration)
            if from_browser is None:
                return 1
            pairs += from_browser
        if args.pairs:
            clicks = {}
            for token in args.pairs.split():
                label, _, pixel = token.partition("=")
                if not label or not pixel:
                    raise ValueError(f"expected 'label=x,y', got {token!r}")
                clicks[label] = _points(pixel, 1)[0]
            pairs += landmark_pairs(session, calibration, clicks)
        if args.use_markers:
            pairs += marker_pairs(session, args.store, project_slug(session))
        if not pairs:
            raise AlignError("no correspondences; pass --pairs and/or --use-markers")

        alignment = solve(session, calibration, pairs, force=args.force)
    except (AlignError, PlanError, SessionError, FileNotFoundError, ValueError) as error:
        print(f"vividhome align: {error}", file=sys.stderr)
        return 1

    print(f"{alignment.session_id} -> level {alignment.level}")
    print(f"  method        {alignment.method} ({len(alignment.pairs)} correspondences)")
    print(f"  yaw           {alignment.yaw_deg:+.2f} deg")
    x, y, z = alignment.T_hs[:3, 3]
    print(f"  translation   ({x:+.3f}, {y:+.3f}, {z:+.3f}) m  [floor: {alignment.floor_source}]")
    print(f"  rms           {alignment.rms_m * 100:.1f} cm")
    print(f"  max residual  {alignment.max_residual_m * 100:.1f} cm")
    if alignment.rms_m > WARN_RMS_M:
        print(
            f"\nWARN: {alignment.rms_m * 100:.0f} cm is a poor fit. "
            "Check the pairs before trusting this alignment."
        )

    print(f"\nwrote {write_alignment(args.store, alignment)}")
    added = update_marker_map(args.store, project_slug(session), session, alignment)
    if added:
        print(f"added to the house marker map: {', '.join(added)}")
    return 0


def _run_apriltag(args: argparse.Namespace) -> int:
    from .apriltag import aggregate, check_anchor_frame, solve_session, write_detections
    from .session import Session, SessionError

    try:
        session = Session.load(resolve_session(args.store, args.session))
    except (FileNotFoundError, SessionError) as error:
        print(f"vividhome apriltag: {error}", file=sys.stderr)
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
        print("vividhome synth: --keyframes must be at least 1", file=sys.stderr)
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
    "align": _run_align,
    "inspect": _run_inspect,
    "ingest": _run_ingest,
    "markers": _run_markers,
}


#: Exit code for a pipe closed by the reader, the shell convention for SIGPIPE.
BROKEN_PIPE = 141


def main(argv: Sequence[str] | None = None) -> int:
    """Parse arguments and dispatch. Returns the process exit code."""
    args = build_parser().parse_args(argv)

    try:
        return _dispatch(args)
    except BrokenPipeError:
        # `vividhome apriltag ... | head` closes the pipe partway through. That is
        # the reader's choice, not an error, but Python flushes stdout again at
        # exit and would raise a second time and print a traceback, so stdout is
        # pointed at the null device first.
        with contextlib.suppress(OSError):
            os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
        return BROKEN_PIPE
    except KeyboardInterrupt:
        print("\ninterrupted", file=sys.stderr)
        return 130


def _dispatch(args: argparse.Namespace) -> int:
    handler = _HANDLERS.get(args.command)
    if handler is not None:
        return handler(args)

    name = args.command
    if getattr(args, "plan_command", None):
        name = f"{args.command} {args.plan_command}"
    print(f"vividhome {name}: not implemented", file=sys.stderr)
    return NOT_IMPLEMENTED


if __name__ == "__main__":  # pragma: no cover - exercised via the console script
    raise SystemExit(main())
