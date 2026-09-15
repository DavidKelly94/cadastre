# ADR-0021: The session format is the only cross-language contract

## Status

Accepted, 2026-09-13. Does not supersede anything: [ADR-0016](0016-core-package-tested-on-linux.md) stands. It records the reasoning behind one line of that record's alternatives table, and the rule that reasoning implies.

## Context

The owner is a Kotlin and Java engineer, and this repository is expected to grow an
Android client and a browser viewer alongside the iPhone app. That invites a fair
question: why is the app in a language the owner does not use, and does it constrain
the clients that come later? ADR-0016 rejected a Kotlin Multiplatform core in six
words — "another toolchain and a bridging layer for no gain" — too thin to survive
being asked twice. The real question is where the seam between clients sits.

Today the repository is 3,993 lines of Python, 1,943 of pure-Foundation Swift in
`VividHomeCore`, and **363 lines of ARKit and SwiftUI**. Only that last number is
Apple-locked, and nothing links against it: `docs/session-format.md` is what the
pipeline reads, and the `contract` CI job proves the two agree.

Two facts constrain what the other clients can be. `sceneDepth` with per-pixel
confidence, `captureHighResolutionFrame`, `sceneReconstruction` and `detectionImages`
have no cross-platform equivalent (ADR-0001), so a capture client is native or it is
Unity. And per `docs/feasibility.md`, ARCore depth is depth-from-motion and hardware
ToF exists on about ten Android models, none newer than the Galaxy S20 generation —
so **an Android capture client cannot produce the metric depth this product rests
on**. The Android client is a viewer and markup client, which needs a format reader,
not the writer, keyframe policy, health policy, row packer or manifest lifecycle.

## Decision

Clients are independent implementations of one file contract, not consumers of one
shared library. `docs/session-format.md` is the only thing they share, and a new
client joins by adding an arm to the `contract` CI job — writing or reading a fixture
session that the other implementations check — never by linking a common core.

The iPhone app stays native Swift. Kotlin Multiplatform is not adopted, for reasons
worth stating properly:

- It would work technically. KMP static-links (`isStatic = true`), so it would not
  trip the ban on embedded frameworks — `VividHomeCore` is static-linked for that same
  reason (ADR-0003, ADR-0016).
- It costs the thing this project cannot spare: iteration. With no Mac (ADR-0002),
  iOS changes are already a CI round trip; adding Kotlin/Native's Xcode integration
  means debugging the framework embed through push-and-wait.
- The prize is small. An Android client would share a format reader; the rest of
  `VividHomeCore` is write-side logic a viewer never runs.

## Consequences

Positive: the seam is a documented file format rather than an ABI, so clients can be
written in whatever suits them, drift is caught by a test rather than a type system,
and no client is blocked on another's toolchain.

Negative, carried knowingly:

- **A second writer duplicates logic.** If an Android capture client is ever
  justified, roughly 1,900 lines are rewritten rather than shared, and two
  implementations must agree byte for byte. The `contract` job is the whole defence,
  so it must grow with every writer.
- **The owner cannot fluently review the app's language.** Mitigated by the thin
  ARKit layer and one package holding the decision-bearing logic, not eliminated.
- **Reversing this later costs more than adopting KMP now would have.**

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| Kotlin Multiplatform core shared by both apps | Mac-less CI-only iteration makes the Xcode framework embed expensive to debug, for a shared surface that is mostly write-side logic Android would not run. |
| Flutter for the screens over a Swift capture layer | The ARKit code still has to be written in Swift; this adds a second language and a toolchain rather than removing one. |
| Unity AR Foundation for one codebase | Rejected in ADR-0001: engine licence, heavy CI toolchain, non-native UI. |
| Share a core via a C ABI or WASM | A third artifact to build and version, to share a reader that is a few hundred lines in any language. |
