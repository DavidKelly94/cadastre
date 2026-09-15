# ADR-0012: Monorepo, sessions in the app's Documents folder, no accounts

## Status

Accepted, 2026-09-11.

## Context

VividHome has three codebases in three languages (Swift app plus `VividHomeCore`, Python pipeline, TypeScript viewer) plus documentation, one implementer and one user. The session format (ADR-0004) is shared by all of them, so a `format_version` bump touches the app, the pipeline, the docs and the sample fixtures at once. The MVP has no accounts or cloud; photos of the owner's house are private.

## Decision

One public repository, `homescanner` (renamed only when the owner chooses, ADR-0019), with `docs/`, `ios/`, `pipeline/`, `samples/`, `web/` and `.github/workflows/`. Workflows are path-filtered: `core-test` on every push, `ios-check` on pull requests, `ios-testflight` on pushes touching `ios/**`. `samples/` holds one trimmed real session (at most 10 frames, under 6 MB) used by both Swift and Python tests; real plans and full sessions live in a project store outside the repository.

On the phone, sessions are written to `Documents/sessions/<project>/<session>/`. `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` expose them in the Files app. Transfer is manual: Files to an SMB share on the PC, or USB with the Apple Devices app. No accounts, no cloud storage, no telemetry. The PC copy is the archive; sessions are deleted from the phone after `vividhome validate` passes.

## Consequences

Positive:

- Cross-cutting format changes land in one pull request with docs and fixtures; shared fixtures keep the Swift and Python encoders in agreement.
- The owner can see, copy and delete every byte the app produces; no backend to build or secure.
- A public repository makes macOS runner minutes free (ADR-0002).

Negative:

- Public repository: no house photos, plans or full sessions may be committed; fixtures must be trimmed and unremarkable.
- Path filters and three toolchains in one repository need care.
- Deleting the app deletes untransferred sessions; the review screen must say so.

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| One repository per component | Three CI setups and cross-repository format versioning for one implementer. |
| iCloud Drive container | Slow multi-gigabyte uploads, Apple-only tooling, less deterministic than a copy. |
| Cloud backend with accounts | Out of scope, recurring cost, privacy; a later product phase. |
| Private app container or App Group | Invisible to Files; data could not be moved by hand. |
