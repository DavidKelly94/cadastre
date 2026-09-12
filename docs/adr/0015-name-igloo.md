# ADR-0015: The product is named Igloo

## Status

Superseded by [ADR-0019](0019-name-cadastre.md), 2026-09-12. The decision below is unchanged in substance; it records what was agreed on 2026-09-11, with the brand domain of the time generalised rather than named.

Accepted, 2026-09-11.

## Context

The owner wanted a name that fits the brand in use at the time, which has no strong theme yet. The name is needed early: the App ID is registered on day 2 for the first TestFlight build, and a bundle identifier cannot be changed once an app record exists, so the choice is permanent for this app. The GitHub repository still carries a working name. The CLI, the Swift package and the marker labels also need stable names before code is written.

"Igloo" was chosen because it fits the brand ("sno") and the product: an igloo is a house built course by course from blocks, so each construction phase is a course and the finished house is the dome; ice-white and blue surfaces with one warm accent for record and primary actions read well in bright, dusty outdoor light. The design brief builds the visual theme on this motif.

## Decision

Product name Igloo; bundle identifier on the brand domain in use at the time (explicit App ID); CLI `igloo`; Swift package `IglooCore`; marker labels `IG-000` to `IG-059`; sessions under `sessions/`. The repository stays `homescanner` until the owner renames it (GitHub redirects the old URL). If App Store Connect rejects "Igloo" as already in use, the display name gains a brand qualifier; the bundle identifier is unaffected.

## Consequences

Positive:

- One short, typeable word for app, CLI, package and marker prefix.
- A ready visual theme for the design brief.
- A reverse-DNS identifier under a domain the owner controls.

Negative:

- "Igloo" is a common word with trademarks in other categories (coolers, intranet software); a public product later needs a trademark check, and the App Store name may need a qualifier.
- The repository name will not match until it is renamed.
- The bundle identifier can never change.

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| HomeScanner | Generic, unbranded, and likely taken on the App Store. |
| Snoday Capture | Descriptive, not a product name. |
| X-ray or see-through names | Medical connotations and crowded trademarks. |
| Keep a code name and decide later | The App ID must be fixed by day 2. |
