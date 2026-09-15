# Architecture decision records

This folder holds the architecture decision records (ADRs) for VividHome. Each record captures one decision that is expensive to reverse: the forces behind it, what was decided, what we accept as a consequence, and the alternatives that were on the table. The layout follows MADR (https://adr.github.io/madr/): title, status, context, decision, consequences, alternatives considered. Records 0001 to 0016 were accepted with the owner on 2026-09-11, the day the plan was approved; 0017, 0018 and 0019 followed on 2026-09-12, and 0020 and 0021 on 2026-09-13. They are the reference whenever code, docs and memory disagree. Five of them run longer than the word guidance below, deliberately: 0017 carries a dependency on a decision it cannot yet make, 0018 carries cost arithmetic that loses its value if summarised, 0019 preserves four rounds of naming research so a future rename starts at the finish line rather than the start, 0021 preserves the cross-platform reasoning so the Android and Kotlin question is answered rather than re-argued, and 0025 spells out the boundary between placing a room on a plan and aligning to one, because the two look alike and conflating them silently produces a wrong answer.

Read them in order the first time. Afterwards, use the index.

## Index

| Number | Title | Status |
|---|---|---|
| [ADR-0001](0001-native-swift-arkit.md) | Native Swift, SwiftUI and ARKit for the capture app | Accepted |
| [ADR-0002](0002-ios-builds-on-github-actions-testflight.md) | iOS builds on GitHub Actions with TestFlight distribution | Accepted |
| [ADR-0003](0003-cloud-managed-signing.md) | Cloud-managed signing from an unsigned archive | Accepted |
| [ADR-0004](0004-session-format-posed-rgbd-keyframes.md) | Session format is posed RGB-D keyframes in per-frame files with JSONL sidecars | Accepted |
| [ADR-0005](0005-short-room-sessions-offline-registration.md) | One room per session, registration offline | Superseded by [ADR-0022](0022-session-is-one-pass-carrying-phases.md) |
| [ADR-0006](0006-fiducials-and-plan-as-invariant-frame.md) | AprilTag hybrid markers, with the plan as the invariant frame | Superseded by [ADR-0026](0026-markers-are-optional-the-plan-is-the-frame.md) |
| [ADR-0007](0007-per-level-se2-alignment.md) | Per-level SE(2) alignment from tapped landmarks and plan corners | Accepted |
| [ADR-0008](0008-offline-processing-on-owner-pc.md) | Offline processing on the owner's PC | Accepted |
| [ADR-0009](0009-posed-photos-first-splats-later.md) | Posed photos and the LiDAR mesh are the truth; splats are a visual layer | Accepted |
| [ADR-0010](0010-ai-labeling-assistive.md) | AI labelling is assistive, never automatic | Accepted |
| [ADR-0011](0011-web-viewer-threejs-spark-sog.md) | Web viewer on three.js and Spark with SOG splats | Accepted |
| [ADR-0012](0012-monorepo-and-local-storage.md) | Monorepo, sessions in the app's Documents folder, no accounts | Accepted |
| [ADR-0013](0013-ios17-lidar-required.md) | iOS 17 minimum, LiDAR required | Accepted |
| [ADR-0014](0014-plans-as-calibrated-rasters.md) | Plans as calibrated rasters | Accepted |
| [ADR-0015](0015-name-igloo.md) | The product is named Igloo | Superseded by [ADR-0019](0019-name-cadastre.md) |
| [ADR-0016](0016-core-package-tested-on-linux.md) | Core logic in a pure-Swift package tested on Linux | Accepted |
| [ADR-0017](0017-product-scope-record-and-collaboration.md) | The product is a queryable building record, not only a look behind walls | Accepted |
| [ADR-0018](0018-staged-private-and-runner-budget.md) | Stay public through the build sprint, then go private | Accepted |
| [ADR-0019](0019-name-cadastre.md) | The product is named Cadastre, bundle ID `com.davidkelly.cadastre` | Superseded by [ADR-0020](0020-bundle-id-cadastre-build.md) |
| [ADR-0020](0020-bundle-id-cadastre-build.md) | The product is named Cadastre, bundle ID `build.cadastre.app` | Superseded by [ADR-0023](0023-bundle-id-needs-no-domain.md) |
| [ADR-0021](0021-session-format-is-the-only-cross-language-contract.md) | The session format is the only cross-language contract | Accepted |
| [ADR-0022](0022-session-is-one-pass-carrying-phases.md) | A session is one room in one pass, carrying a set of phases | Accepted |
| [ADR-0023](0023-bundle-id-needs-no-domain.md) | The bundle identifier is `com.cadastrerecord.app` and depends on no domain | Superseded by [ADR-0024](0024-name-vividhome.md) |
| [ADR-0024](0024-name-vividhome.md) | The product is named VividHome, bundle ID `ai.vividhome.app` | Accepted |
| [ADR-0025](0025-plans-are-a-project-level-asset.md) | The floor plan is a project-level asset the app carries | Accepted |
| [ADR-0026](0026-markers-are-optional-the-plan-is-the-frame.md) | Markers are optional; the plan and tapped landmarks carry the frame | Accepted |

## Adding a new ADR

1. Create `NNNN-short-title.md` where `NNNN` is the next unused number in the index. Never reuse or renumber; the index is the source of truth.
2. Use the same sections as the existing records: title line `# ADR-NNNN: <title>`, then Status, Context, Decision, Consequences (positive and negative), Alternatives considered (one line each on why it was rejected). Keep it between 180 and 400 words, in plain language, with a source URL wherever a fact came from outside the project.
3. Start with status `Proposed` and the date, and add the row to the index with that status. Discuss it in the pull request that adds it.
4. When the owner agrees, change the status to `Accepted` with the acceptance date. A proposal that is turned down stays in the folder with status `Rejected` so the reasoning is not lost.
5. Never edit the decision of an accepted record. To change a decision, write a new record whose status line says `Supersedes ADR-NNNN`, and change the old record's status to `Superseded by ADR-MMMM` with a link. Both stay in the index. Fixing a typo or a dead link in an old record is fine.
