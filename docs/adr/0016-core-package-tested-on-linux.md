# ADR-0016: Core logic in a pure-Swift package tested on Linux

## Status

Accepted, 2026-09-11.

## Context

The implementer cannot run the app, ARKit does not run in the simulator, and a macOS runner build takes minutes. Most defects in a recorder are ordinary logic: gating, conventions, encoding, thresholds. Those need a fast, deterministic signal on every push. The plan's `core-test.yml` runs on `ubuntu-latest` in a `swift:6.1` container (https://hub.docker.com/_/swift): `swift test`, `swift-format lint --strict` and `uv run pytest`. `simd`, ARKit, UIKit and RealityKit exist only on Apple platforms.

## Decision

`ios/IglooCore` is a SwiftPM package with no ARKit, simd, UIKit or other Apple-only imports, restricted to the Foundation subset that behaves identically on Linux. It contains `Transform` (4x4 matrices as plain arrays), `KeyframePolicy` (100 ms, 0.10 m, 5 degrees, tracking normal; thresholds doubled under serious thermal state), `FrameRecord` and `SessionManifest` (the JSON shapes in `docs/session-format.md`), `JSONLWriter` (append, fsync every 50 lines) and `HealthPolicy` (refuse below 2 GB free, warn at 5 minutes, stop at 10 minutes, below 500 MB or on critical thermal). Tests run on every push in the `swift:6.1` container. The app links IglooCore as a static package (ADR-0003) and converts ARKit values to plain floats at the boundary; ARKit types never cross into the package. The same `samples/` fixtures are decoded by the Python tests, so both encoders are checked against one truth.

## Consequences

Positive:

- Feedback in a minute or two on Linux, before any macOS build.
- Deterministic coverage of the parts that would otherwise fail silently on device; format drift is caught by shared fixtures.
- Forces the ARKit layer, the untestable part, to stay thin.

Negative:

- Hand-written 4x4 math without `simd`, and a conversion at the boundary; acceptable at about ten keyframes per second.
- Linux Foundation quirks (dates, `FileHandle`) can surprise.

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| XCTest in the app target on the macOS runner | Ten times slower per push and needs the full Xcode toolchain. |
| `#if canImport(simd)` dual paths | The tested path would not be the shipped path. |
| Logic inside the app, no tests | Exactly the risk the plan mitigates. |
| Rust or Kotlin Multiplatform core | Another toolchain and a bridging layer for no gain. |
