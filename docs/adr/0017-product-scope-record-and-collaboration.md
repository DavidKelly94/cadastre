# ADR-0017: The product is a queryable building record, not only a look behind walls

## Status

Accepted, 2026-09-12.

## Context

`docs/plan.md` was written around one question: photograph a house during framing
and rough-in, then find the studs, pipes, gas lines, ducts and wires afterwards.
Every document inherited that framing.

The owner's intent is broader in three ways. The product is used **during and
after** construction, so inspecting work and comparing phases matter as much as the
later search. The captured imagery is an **answer surface**, not just texture: the
owner expects to reference real photos and panoramas alongside the rendering and ask
questions of them. And the long-term direction is **coordination with builders and
clients, with markup as a major feature**.

None of that changes what gets built in two weeks. It changes what the documents
claim, which extension points are reserved while they are cheap, and which accepted
decision will have to give way.

## Decision

The product is an AI-assisted spatial record of a building, spanning construction
and ownership. Capture, plan alignment and the session format are unchanged, and the
MVP scope in `docs/plan.md` stands.

Three extension points are reserved now:

- **Panoramas**: an optional `panos/` plus `panos.jsonl` slot in
  `docs/session-format.md` §7, additive and keeping `format_version` at 1.
- **Spatial markup**: specified to live in the house frame rather than against a
  photo, so a mark renders in 3D, on the plan and over any phase
  (`docs/design/viewer-design.md` §7).
- **Question answering over panoramas** as well as stills, in `docs/ai-roadmap.md`,
  since a panorama is a better retrieval unit for a room-level question.

## Consequences

Positive: the documents describe the product being built, so an implementer will not
optimise for the narrow case; panoramas and markup can arrive without a format bump;
and naming is no longer constrained to see-through metaphors.

Negative: a broader claim invites scope creep, guarded only by the MVP definition and
the schedule; and a reserved slot may read as a commitment, so both are marked
optional and unused by the MVP.

## The collision this creates

ADR-0012 decided "No accounts, no cloud storage, no telemetry." Sharing with a
builder or client cannot be done under that constraint: it needs identity for
attribution, a scope per recipient, and a view that does not leak the rest of the
house. This ADR does not resolve it. It records that multi-user collaboration will
require a future ADR **superseding ADR-0012's no-accounts clause**, and that until
then the architecture stays local-only. That work should not start before capture and
alignment are trusted, because sharing an unreliable record is worse than not
sharing.

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| Leave the docs narrow, widen them when the features arrive | The narrow framing was already steering decisions, including naming; retrofitting panoramas would cost a `format_version` bump |
| Widen the MVP to include markup now | Markup without a trusted coordinate frame marks the wrong place, and capture is the perishable part |
| Supersede ADR-0012's no-accounts clause here | Premature: that decision needs a concrete sharing design to argue against |
