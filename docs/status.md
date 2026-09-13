# Status

What is built, what is not, and what is blocked. Keyed to `docs/schedule.md`'s
day plan, but this file is the honest one: the schedule says what was planned,
this says what is true.

**Update this in the same commit as the work.** A status file that lags is worse
than none, because it is believed.

Last updated: 2026-09-13, after PR #28.

## The short version

The pipeline is feature-complete and tested. The Swift core is complete and
tested. The iOS capture layer is written and compiles, but **has never run** —
there is no device build yet, so nothing below marked "compiles" should be read
as "works". The screens do not exist.

## Pipeline (`pipeline/`) — complete

| Command | State | Notes |
|---|---|---|
| `validate` | done | All 8 rules, `--skip-images`, `--skip-depth` |
| `synth` | done | Writes a format_version 2 session |
| `markers` | done | Generates `CD-000`–`CD-059`, PDF and PNG |
| `apriltag` | done | 36h11 via `cv2.aruco`, subpixel refinement, IPPE_SQUARE |
| `plan` | done | `add`, `calibrate`; parses `12' 6"` |
| `align` | done | Umeyama 2D, rotation and translation only |
| `inspect` | done | Level page, groups multi-phase sessions by earliest trade |
| `ingest` | done | Zip-slip and path-traversal guarded |
| `serve` | done | Local server for the browser pages |

14 modules, **232 tests passing**, ruff clean.

## Swift core (`ios/CadastreCore/`) — complete

13 modules, 11 test files, all Linux-tested. `Transform`, `SessionID`,
`Records`, `Coding`, `KeyframePolicy`, `HealthPolicy`, `JSONLWriter`,
`RowPacker`, `SessionLayout`, `SessionLifecycle`, `BoundedWriteQueue`,
`SessionStore`, plus the `cadastre-fixture` binary the contract job runs.

## iOS capture layer (`ios/Cadastre/`) — written, never run

| File | State |
|---|---|
| `ARKitBridge` | compiles |
| `ARSessionController` | compiles |
| `SessionRecorder` | compiles |
| `FrameWriter`, `JPEGEncoder`, `PixelBufferPacker` | compiles |
| `StillCapture` | compiles |
| `MarkerLogger`, `LandmarkLogger` | compiles |
| `MeshExporter` | compiles |
| `ProjectStore` | **not written** |

**Not one line of this has executed.** ARKit does not run in the simulator, and
there is no device build. Everything here is unverified behaviour behind a
successful compile.

## Screens — none built

Onboarding, ProjectPicker, Project overview, Level view, RoomPicker, Capture
HUD, Session review, Markers, Settings, Test plan. The app currently shows one
build-check screen and a bare AR view, both scaffolding from day 1.

Design decisions for these are settled in `docs/ui/design-brief.md` §10; the
canvas has not been made.

## CI

| Check | Runs on | State |
|---|---|---|
| `swift` | every push, Linux | green |
| `python` | every push, Linux | green |
| `contract` | every push, Linux | green — the only check that puts both implementations in contact |
| `ios-check` | **pull requests only** | green |
| `ios-testflight` | push to the work branch | no-ops; Linux preflight gates the macOS build on secrets |
| `Claude Review` | pull requests | green — first ran 2026-09-13, having never run before |

## Blocked on the owner

1. **Four App Store Connect secrets** — `ASC_KEY_ID`, `ASC_ISSUER_ID`,
   `ASC_PRIVATE_KEY_P8`, `APPLE_TEAM_ID`. Until these exist `ios-testflight`
   no-ops and there is no build on a phone. This is the single biggest blocker:
   everything in the capture layer stays unverified without it.
2. **Register `cadastre.build`** before creating the App ID (ADR-0020) — the
   bundle identifier is rooted in it and the App ID is the point of no return.
3. **The first real capture** — needed to confirm `R_am`, ARKit buffer strides
   and `ARReferenceImage` validation, and to fill `samples/`, which is empty.
4. **Print and laminate the markers** (`docs/markers.md`), verifying 20.0 cm
   with a tape.
5. **Remove `davidkelly-snoday` as a collaborator** — it still has write access.

## Known gaps

- `samples/` is empty. The schedule wanted a trimmed real session there by day 5.
- No device has ever run the app, so the test plan has never been executed.
- The design canvas does not exist; §11 of the brief holds three questions that
  need a phone in sun and in an unlit basement.
