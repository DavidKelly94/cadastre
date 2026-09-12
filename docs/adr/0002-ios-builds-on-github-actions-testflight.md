# ADR-0002: iOS builds on GitHub Actions with TestFlight distribution

## Status

Accepted, 2026-09-11.

## Context

The owner has no Mac and develops on a Windows PC, so every compile, archive and upload must happen on a hosted macOS machine, and every device test goes through TestFlight.

Verified on 2026-09-11: GitHub-hosted `macos-26` runners are generally available since 2026-02-26, and image 20260907 ships Xcode 26.6 by default (https://github.com/actions/runner-images). Standard hosted runners, macOS included, are free on public repositories; a private one would get roughly 200 real macOS minutes a month on the Free plan. XcodeGen (https://github.com/yonaskolb/XcodeGen) generates the `.xcodeproj` from a readable `project.yml`, so no binary project file is ever edited by hand. TestFlight internal testing needs no Beta App Review and returns crash reports.

## Decision

All iOS builds run on GitHub Actions `macos-26`. The project is generated on the runner from `ios/project.yml` with XcodeGen pinned to the latest 2.46.x release (release asset with a sha256 check, `brew install xcodegen` as fallback, generated project uploaded as a CI artifact for diagnosis). Three workflows:

- `core-test.yml`: `ubuntu-latest`, container `swift:6.1`; `swift test` for IglooCore, `swift-format lint --strict`, `uv run pytest`. Every push; the fast signal.
- `ios-check.yml`: pull requests and manual runs; XcodeGen, then `xcodebuild build` for `generic/platform=iOS Simulator` with `CODE_SIGNING_ALLOWED=NO`.
- `ios-testflight.yml`: pushes to the development branch touching `ios/**`, plus `workflow_dispatch`; `timeout-minutes: 30`, cancel-in-progress; `xcode-select` Xcode 26.6, archive, export, upload (signing in ADR-0003). `CURRENT_PROJECT_VERSION` is `github.run_number`, so build numbers are unique.

Every build bundles `TestPlan.md`, rendered in-app and pasted into TestFlight notes. The implementer reads job logs through the GitHub API and fixes CI without the owner.

## Consequences

Positive:

- Zero local toolchain; the whole build is reproducible from the repository.
- Free minutes while the repository is public.
- Simulator builds give a compile signal on pull requests without signing.

Negative:

- Minutes per iteration instead of seconds, bounded by the 30-minute timeout.
- No debugger; runtime behaviour is visible only on the owner's phone.
- Runner image updates can move Xcode; the workflow pins 26.6 with `xcode-select`.
- XcodeGen is a single point of failure, mitigated by the pinned binary, checksum and brew fallback.

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| Buy or rent a Mac | A second machine to maintain; the owner chose not to. |
| Xcode Cloud | Workflows are configured from Xcode on a Mac; logs are less transparent. |
| Codemagic, Bitrise | Paid macOS tiers and another vendor and secret store; Actions already hosts the repo. |
| Commit an `.xcodeproj` | Unreadable diffs and merge conflicts nobody can resolve in Xcode. |
| Development or ad hoc signing | Needs device UDIDs and profiles; TestFlight avoids that and adds crash reports. |
