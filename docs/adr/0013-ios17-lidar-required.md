# ADR-0013: iOS 17 minimum, LiDAR required

## Status

Accepted, 2026-09-11.

## Context

Everything in VividHome depends on metric depth: `sceneDepth` with confidence, `ARMeshAnchor` with classification, raycast landmarks on real surfaces and the depth-scaled intrinsics in the session format. Only LiDAR iPhones provide it: every Pro and Pro Max since the iPhone 12 Pro (2020) through the 17 Pro; no non-Pro model, including the iPhone 17, 17e and Air, has LiDAR. The iPhone 18 Pro announced on 2026-09-09 almost certainly continues the line, but its specification was not verified. The owner's phone is an iPhone 15 Pro or newer.

The APIs needed are all available by iOS 16 or 17: `sceneDepth` (iOS 14), mesh classification (iOS 13.4 with LiDAR), `captureHighResolutionFrame` (iOS 16), `NavigationStack` (iOS 16). ARKit on iOS has received no headline additions since, so nothing in iOS 18 to 27 is required. Every LiDAR iPhone can run iOS 17 or newer. Xcode 26.6 on the runner builds for a 17.0 deployment target. ARKit does not run in the simulator, so `ios-check` only compiles.

## Decision

Deployment target iOS 17.0, Swift 5 language mode, portrait only, `UIRequiredDeviceCapabilities [arkit]`. At launch the app checks `ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification)` and `supportsFrameSemantics(.sceneDepth)` and refuses capture with a clear message on any device without LiDAR; onboarding shows the check. There is no degraded non-LiDAR mode. iPad is neither excluded nor tested.

## Consequences

Positive:

- One code path and one session format; every file a session promises is always present.
- All LiDAR devices still receiving updates are covered; iOS 17 leaves headroom if a phone is not updated.
- New OS releases need no immediate work.

Negative:

- Excludes non-Pro iPhones and all Android; a future product must accept this or add a photo-only mode.
- Runtime capability checks must stay in sync with the ARKit configuration.
- Simulator builds prove compilation only.

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| iOS 26 minimum | No API needed; removes headroom for no gain. |
| Photo-only mode without LiDAR | No metric depth; doubles the code paths and breaks the format guarantees. |
| iPad Pro as a capture device | Two-handed on a dusty site; untested. |
| Android | No LiDAR equivalent in 2026. |
