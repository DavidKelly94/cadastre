# VividHome

Capture your house while it is being built. See behind the walls forever.

VividHome is a toolchain for a homeowner (first) and, later, a product:

- an **iPhone app** (LiDAR iPhone Pro) that records, for each room at each construction phase, posed photos, LiDAR depth, high-resolution stills, tapped room corners and printed marker sightings, plus a mesh;
- a **Python pipeline** on the owner's PC that validates sessions, finds the markers, aligns every session to the floor plans, and (later) builds meshes, Gaussian splats and AI labels;
- a **web viewer** (later) to find studs, pipes, gas lines, ducts and wires behind finished walls, years after they were covered.

Product name: **VividHome** ([ADR-0024](docs/adr/0024-name-vividhome.md)). Bundle ID `ai.vividhome.app`.

## Status

Planning is complete (2026-09-11); the product was named and the repositories moved on 2026-09-12. Implementation follows [docs/implementation-guide.md](docs/implementation-guide.md) and the 14-day [schedule](docs/schedule.md). Nothing ships to the App Store; builds go to TestFlight for the owner.

## Where to start

| If you are… | Read |
|---|---|
| The owner | [Owner setup](docs/owner-setup.md), [Capture protocol](docs/capture-protocol.md), [Markers](docs/markers.md), [Schedule](docs/schedule.md), [Transfer runbook](docs/transfer-runbook.md) |
| Implementing the code | [AGENTS.md](AGENTS.md), [Implementation guide](docs/implementation-guide.md), [System design](docs/design/system-design.md), [iOS app design](docs/design/ios-app-design.md), [Pipeline design](docs/design/pipeline-design.md), [Session format](docs/session-format.md), [ADRs](docs/adr/README.md) |
| Designing the UI | [UI design brief](docs/ui/design-brief.md) (self-contained handoff) |
| Asking "why" | [Feasibility](docs/feasibility.md), [Naming investigation](docs/naming-investigation.md), [Approved plan](docs/plan.md), [AI roadmap](docs/ai-roadmap.md), [Viewer design](docs/design/viewer-design.md) |

## Repository layout (target)

```
vividhome/
  docs/                 plan, feasibility, design docs, ADRs, UI brief, schedule, protocols, format spec
  ios/
    project.yml         XcodeGen spec; the Xcode project is generated on the CI runner
    ExportOptions.plist App Store Connect export (TestFlight upload)
    VividHome/              SwiftUI app with a thin ARKit capture layer
    VividHomeCore/          pure-Swift package (no ARKit/simd); tests run on Linux CI
  pipeline/             Python 3.12 package `vividhome` (uv): validate, apriltag, plan, align, inspect, markers
  samples/              one trimmed real session for pipeline tests
  web/                  browser viewer (weeks 3+)
  .github/workflows/    core-test.yml, ios-check.yml, ios-testflight.yml
```

## How it fits together

```
iPhone (VividHome app)  --sessions (files)-->  PC (vividhome pipeline)  --JSON/GLB/SOG-->  browser viewer
ARKit poses + LiDAR depth              validate, markers, align to plan           plan overlay, phases,
+ stills + landmarks + markers         (later: mesh, splats, AI labels)            click-to-photo, measure
```

The floor plan is the permanent reference frame. Each session is aligned to it with a 2D rigid transform per level. Printed markers tie sessions and construction phases together; the app's own relocalization is never relied on across phases. Posed photos are the source of truth for anything thin (wires, half-inch pipe); meshes and splats are the skeleton you navigate.

## Development

- iOS builds run on GitHub Actions `macos-26` runners and upload to TestFlight (no Mac required). See [owner setup](docs/owner-setup.md) for the four secrets.
- Core Swift logic and the Python pipeline are tested on Linux on every push.
- Development branch: `claude/construction-3d-mapping-app-nzm3bb`.
- Agent instructions live in [AGENTS.md](AGENTS.md) (cross-tool) and [CLAUDE.md](CLAUDE.md) (Claude-specific). The repository carries the shared harness from `DavidKelly94/base`: `.harness.yml` configures it, and `/base:check`, `/base:review` and `/base:ship` are the gates.
- Enable local gates once per clone: `pip install pre-commit && pre-commit install`.
- The product is being renamed, and both this repository and `base` move to a personal account and later go private. See [ADR-0017](docs/adr/0017-product-scope-record-and-collaboration.md), [ADR-0018](docs/adr/0018-staged-private-and-runner-budget.md) and the [transfer runbook](docs/transfer-runbook.md).
