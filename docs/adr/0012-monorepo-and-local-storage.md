# ADR-0012: Monorepo, sessions in the app's Documents folder, no accounts

## Status

Accepted, 2026-09-11.

## Context

Igloo has three codebases in three languages (Swift app plus `IglooCore`, Python pipeline, TypeScript viewer) plus documentation, one implementer and one user. The session format (ADR-0004) is shared by all of them, so a `format_version` bump touches the app, the pipeline, the docs and the sample fixtures at once. The MVP has no accounts or cloud; photos of the owner's house are private. A 5-minute room is about 800 MB, and the phone must refuse to start below 2 GB free and stop below 500 MB.

## Decision

One public repository, `homescanner` (kept under that name until the owner renames it, ADR-0015), with `docs/`, `ios/`, `pipeline/`, `samples/`, `web/` and `.github/workflows/`. Workflows are path-filtered: `core-test` on every push, `ios-check` on pull requests, `ios-testflight` on pushes touching `ios/**`. `samples/` holds one trimmed real session (at most 10 frames, under 6 MB) used by both Swift and Python tests; real plans and full sessions live in a project store outside the repository.

On the phone, sessions are written to `Documents/sessions/<project>/<session>/`. `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` expose them in the Files app; Session review opens them with `shareddocuments://`. Transfer is manual: Files to an SMB share on the PC, or USB with the Apple Devices app. No accounts, no cloud storage, no telemetry. The PC copy is the archive; sessions are deleted from the phone after `igloo validate` passes.

## Consequences

Positive:

- Cross-cutting format changes land in one pull request with docs and fixtures.
- Shared fixtures keep the Swift and Python encoders in agreement.
- The owner can see, copy and delete every byte the app produces.
- No backend to build or secure; privacy by construction.
- A public repository makes macOS runner minutes free (ADR-0002).

Negative:

- Public repository: no house photos, plans or full sessions may be committed; fixtures must be trimmed and unremarkable.
- Path filters and three toolchains in one repository need care.
- Deleting the app deletes untransferred sessions; the review screen must say so.
- Manual transfer friction after every visit.

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| One repository per component | Three CI setups and cross-repository format versioning for one implementer. |
| iCloud Drive container | Slow multi-gigabyte uploads, Apple-only tooling, less deterministic than a copy. |
| Cloud backend with accounts | Out of scope, recurring cost, privacy; a later product phase. |
| Private app container or App Group | Invisible to Files; data could not be moved by hand. |
| Photos library | Strips metadata and has no place for depth, confidence or pose sidecars. |
