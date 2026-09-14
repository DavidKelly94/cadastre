# ADR-0024: The product is named VividHome, bundle identifier `ai.vividhome.app`

## Status

Accepted, 2026-09-14. Supersedes [ADR-0023](0023-bundle-id-needs-no-domain.md), and with it the name decision that ran ADR-0015 → 0019 → 0020 → 0023.

## Context

Cadastre was chosen for what the word means: the authoritative register of what exists on a parcel. The owner's objection, after living with it, was that the word is **land-based** while the product is about a building — a document, inspector, renderer and recorder for a home, used during development and, more importantly, for **serviceability afterwards**. When an electrician needs to run a new circuit in four years, the record exists so someone knows what is behind that wall before cutting into it. ADR-0019 had already half-conceded the problem by adding "Building Record" to the store name as "the counterweight to the land reading".

A wide search followed: roughly 250 candidates across nine angles — descriptive, vision, building fabric, builder-roots, what-remains-underneath, the strata/fabric/foundation/ground-truth families, forward-vision concepts, and serviceability language. The consistent finding, which reconfirmed ADR-0019's original four rounds, is that every obvious name in this category is held by a real and usually funded business: `Lintel` is a construction-AI plan-review startup, `HomeVision` is a funded appraisal-AI company alongside a trademarked "HomeVision AI" for 3D home visualisation, `Groundwork` sells video walkthroughs to home-improvement contractors, `as-built` is a generic industry descriptor and unownable, and `Scaffold` is taken across `.com`, `.ai`, `.app` and `.io`. Of ~250 candidates, roughly a dozen had a free-looking exact `.com`.

The owner chose **VividHome**, with `vividhome.ai` as the domain.

## Decision

Product name **VividHome**. Bundle identifier **`ai.vividhome.app`**, the reverse-DNS form of `vividhome.ai`.

Renamed with it: CLI and Python package `vividhome`, Swift package `VividHomeCore`, the fixture binary `vividhome-fixture`, the Xcode target and scheme `VividHome`, local store `vividhome-data`, and marker labels **`VH-000` to `VH-059`**.

The marker prefix is part of the session contract — `docs/session-format.md` validation rule 8 matches `VH-\d{3}` — so `format_version` goes to **3**. As with the version 2 change, there is nothing to migrate: no session has ever been captured on a device, `samples/` is empty, and no markers have been printed. Readers need not accept versions 1 or 2.

## Consequences

Positive: the name is about a home rather than a parcel of land; it is immediately pronounceable and spellable, which Cadastre never was; and the `.ai` domain matches the product's stated direction.

Negative, carried knowingly:

- **"Vivid Home" is an existing business, and this is the most serious cost.** [Vivid Home LLC](https://www.vividhomempls.com/) is a Minneapolis interiors firm founded by designer Danielle Loven, formerly Vivid Interiors, with two retail locations and roughly twenty years of trading, offering home furnishings and **interior and architectural design**. A separate Vivid Home Company in Arizona does real-estate investment built on interior design. Both use the exact name, both in the home space, which puts them in the same trademark territory rather than an unrelated one. Search engines will conflate the three. This is the collision ADR-0019 refused to accept for "Cadastre AI" against Cadastral; the owner weighed it and accepted it here. It is recorded so a future reader knows it was seen rather than missed.
- **"Vivid" and "lucid" are heavily defended words.** Lucid Group litigates over its mark; Vivid Seats is a public company. Neither is in this product's category, but the words are crowded.
- **The name sells image quality**, which is the product's least durable attribute. What the record is actually worth is that it is still findable and answerable in four years; "vivid" points at how the pictures look.
- **A domain purchase returns to the critical path.** `vividhome.ai` must be registered before the App ID, and `.ai` costs several times a normal TLD with a two-year minimum. ADR-0023 had removed that dependency; this reinstates it.
- **`vividhome.com` is owned by someone else**, so the conventional `com.vividhome.app` was unavailable without squatting.
- **The design work is orphaned.** The cadastral parcel motif in `docs/ui/design-brief.md` §2 — rooms as parcels filling by phase, the ruled-grid icon, the survey benchmark mark — was derived from the meaning of "cadastre" and no longer has any justification. The brief's §2 and §7 need replacing, and a design canvas already in progress needs re-seeding.
- **Fourth name in the project's history**, and the third in two days.

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| Keep Cadastre | Land-based for a building product; the owner judged the store-name qualifier insufficient. |
| Plumbline, Spandrel, Plinth | Free-looking and collision-free, but two of the three carry Cadastre's exact fault of needing permanent explanation. |
| HouseLogbook, SafeToCut, RunMap | The serviceability angle produced these late; adjacent property-logbook products exist, and they were not pursued. |
| `com.vividhome.app` | Squats the reverse-DNS of a domain owned by someone else — the objection that ruled out `com.cadastre.app`. |
