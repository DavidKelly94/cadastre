# ADR-0033: Projects are made, named and removed in the app

## Status

Proposed, 2026-11-13. Extends [ADR-0012](0012-monorepo-and-local-storage.md) and [ADR-0025](0025-plans-are-a-project-level-asset.md).

## Context

The app has one project, written into the code as "Our house". The owner rehearsed a capture at home on 2026-11-13, and that level now sits beside the real main floor on the phone and on the PC, with no way to remove it short of deleting folders by hand. The owner asked to start a project, name it, and delete one with its media.

The PC is not ready for a second project either. `docs/session-format.md` section 13 already records that the store keeps one `plans/` folder for every project, so two projects with a level of the same name would share a plan, and says the fix needs an ADR.

## Decision

1. **The app opens on a list of projects.** A project is created by naming it. The name can be changed later; the slug, which is the folder name, cannot.
2. **A project carries its name in a file.** `project.json` beside `plans/` holds the name and the creation time. It is optional: a folder without one reads as before.
3. **Deleting a project deletes its captures and plans from the phone.** The app first says how many captures the PC has not confirmed, and asks for the project's name to be typed.
4. **The PC keeps each project apart.** Plans, alignments, marker maps and rendered pages live under the project they belong to. A one-time migration moves today's files under `our-house`.
5. **The phone never deletes on the PC.** Removing a project from the store is a command typed there.

## Consequences

Positive: rehearsals and tests stay out of the real house; a second building needs no code change; the latent plan collision is closed.

Negative: the store layout changes, so every pipeline path and the pages the phone opens move; the migration must be safe to run twice.

## Alternatives considered

| Alternative | Why not |
|---|---|
| One project with a "test" flag on levels | Leaves the collision in place and does not give a clean delete. |
| A separate `--store` per project on the PC | Works today, but the owner would restart the server to change project. |
