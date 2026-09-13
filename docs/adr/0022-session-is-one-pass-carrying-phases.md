# ADR-0022: A session is one room in one pass, carrying a set of phases

## Status

Accepted, 2026-09-13. Supersedes [ADR-0005](0005-short-room-sessions-offline-registration.md).

Only the phase clause changes. Every other decision in ADR-0005 — room-scale sessions of 2–5 minutes, the hard stop, a per-session world frame, no cross-session relocalisation, the doorway-to-doorway protocol, offline registration and the week-3 pose graph — is carried forward unchanged, and ADR-0005 remains the place to read the drift measurements behind them.

## Context

ADR-0005 says "a session is one room in one phase", and `docs/session-format.md` encoded that literally: the phase is a segment of the session id, which is also the directory name, and a single-valued `phase` in the manifest.

That is a claim about how building work is sequenced, and it is wrong. Electrical, plumbing and HVAC rough-in routinely happen in the same week and are often exposed in the same wall cavity at the same time — the trade is called MEP for that reason. Under the old model the owner had to either file one capture under a single phase and lose the others, or walk the same room twice recording near-identical imagery.

The owner also intends AI to infer what a photo contains rather than requiring it to be declared up front (`docs/ai-roadmap.md`, ADR-0010). That is out of the MVP window and nothing here implements it. What matters now is not foreclosing it, and a single value inside a directory name forecloses it: a set stored in a file can be corrected, extended, or suggested later, while a path segment cannot change without moving the session.

The timing is the cheapest it will ever be. No session has been captured, `samples/` is empty, the app has not yet run on a device, and no reader outside this repository exists.

## Decision

A session is **one room in one pass**. The pass carries a set of construction phases: whatever trades were exposed while it was recorded.

- The session id drops its phase segment: `<YYYYMMDD-HHMMSS>_<level>_<room>_<id6>`.
- `manifest.json` replaces `phase` with `phases`, a non-empty array of the same eight values.
- `format_version` becomes **2**. There is no migration path and readers need not accept version 1, because no version 1 session exists.
- Phases stay editable after capture. The app asks for them before recording so the coverage checklist knows what to prompt for, but they are metadata, not identity, and Session review can correct them.

## Consequences

Positive: the record can describe concurrent trades, which is what a site produces; one pass documents them all instead of two passes duplicating imagery; a later AI suggestion amends a list rather than contradicting a folder name; and coverage becomes the union of the checklists for the phases present.

Negative, carried knowingly:

- **A folder name no longer says which trade it covers.** The owner copying sessions to the PC loses a real convenience, and `cadastre inspect` has to supply it instead.
- **Sessions of one room are distinguished only by timestamp and id6.** They already were in practice — nothing stopped two electrical passes — but the phase segment used to hide that.
- **A breaking format change, taken deliberately.** Rule 2 would have allowed an additive optional `phases` alongside the existing `phase` at version 1. That was rejected: it leaves the wrong model in the id permanently and makes every reader decide which field wins.

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| Optional `phases` beside `phase`, staying at version 1 | Cheaper today, but the broken single value stays in the directory name forever and two fields can disagree. |
| A list inside the id (`elec+plmb`) | Keeps phase in the identity, so it still cannot be corrected, and it invents new parsing rules for a path segment. |
| Ask for phases only at Session review | Removes the up-front step, but the coverage checklist needs to know what to prompt for during the capture, which is the moment it matters. |
| Leave it and re-capture per phase | Doubles capture time for concurrent trades and produces duplicate imagery of the same wall. |
