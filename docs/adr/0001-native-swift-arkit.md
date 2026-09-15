# ADR-0001: Native Swift, SwiftUI and ARKit for the capture app

## Status

Accepted, 2026-09-11.

## Context

The capture phone is an iPhone 15 Pro or newer, decided on 2026-09-11. Through ARKit it gives, per frame, a metric 6-DoF pose, intrinsics, a 1920x1440 colour image and a 256x192 depth map with per-pixel confidence; `captureHighResolutionFrame` adds posed full-resolution stills and scene reconstruction a classified mesh (https://developer.apple.com/documentation/arkit). ARKit on iOS gained no headline APIs in iOS 26 or in the iOS 27 announcement of 2026-06-09, so it is a mature, stable surface.

No other stack exposes the same data. Android has no LiDAR equivalent in 2026. Among cross-platform options only Unity AR Foundation 6.x reaches raw depth, intrinsics and pose; ViroReact is rendering only, `ar_flutter_plugin` has been dead since November 2022, and Safari implements no WebXR on iOS.

The owner has no Mac, so builds run on CI (ADR-0002) and the implementer can never run the app. That favours the thinnest layer around Apple's documented patterns, with all logic in a package tested elsewhere (ADR-0016).

## Decision

Build VividHome as a native iOS app: SwiftUI screens in a `NavigationStack`, `ARView` wrapped in `UIViewRepresentable`, a thin ARKit layer (`ARSessionController`, `SessionRecorder`, `FrameWriter`, `JPEGEncoder`, `MarkerLogger`, `LandmarkLogger`, `MeshExporter`), Swift 5 language mode to avoid strict-concurrency compile failures we cannot iterate on locally, and system frameworks only. Decision logic and serialisation live in the pure-Swift `VividHomeCore` package.

## Consequences

Positive:

- Full access to `sceneDepth`, confidence, mesh classification, `detectionImages` and posed stills with no bridging layer.
- Smallest build surface for a CI-only toolchain: one `xcodebuild`, nothing else to pin.
- Native components give Human Interface Guidelines behaviour, Dynamic Type and haptics for free.

Negative:

- iPhone only (ADR-0013).
- ARKit behaviour is observable only on the owner's device; mitigated by the per-build test plan, `vividhome validate` and per-session `log.txt`.
- Swift 5 mode gives up strict concurrency checking.

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| React Native (ViroReact) | No raw depth or mesh API. |
| Flutter (`ar_flutter_plugin`) | Unmaintained since November 2022; no depth, intrinsics or pose. |
| Unity AR Foundation 6.x | Viable data access, but an engine licence, a heavy CI toolchain and non-native UI. |
| WebXR | No WebXR in Safari on iOS. |
| Apple RoomPlan | Idealised planar walls (6.45 m reported as 6.82 m), USD only; not a raw recorder. |
