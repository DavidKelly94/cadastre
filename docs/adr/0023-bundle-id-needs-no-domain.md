# ADR-0023: The bundle identifier is `com.cadastrerecord.app` and depends on no domain

## Status

Accepted, 2026-09-14. Supersedes [ADR-0020](0020-bundle-id-cadastre-build.md).

The name decision carries forward unchanged: the product is **Cadastre**, and ADR-0019 remains the place to read the four rounds of research behind it. Only the identifier changes.

## Context

ADR-0020 set the identifier to `build.cadastre.app`, the reverse-DNS form of `cadastre.build`, and put buying that domain on the critical path ahead of registering the App ID. Two things about that did not survive contact.

The owner disliked `.build`. It is a real generic TLD — delegated to the root zone on 2014-01-18, registry operator Plan Bee LLC — so the objection is not that it is illegitimate. It is that an identifier whose prefix *starts* with the word "build" reads at a glance like a build setting rather than an identifier, in the two places it is seen most: Xcode and App Store Connect. ADR-0020 recorded that as a known cost. Seeing it written out, the owner judged the cost too high, which is a reasonable thing to learn by looking at it.

The purchase was also the only thing standing between the Apple Developer account arriving and the App ID being registered. A domain on the critical path of a permanent decision is a bad trade when the domain buys nothing Apple checks.

That is the part worth stating plainly, because ADR-0020 half-obscured it: **Apple never verifies domain ownership for a bundle identifier.** Reverse-DNS is a collision-avoidance convention. Apple's own wording is that an identifier *"should"* take that form. Nothing about a bundle ID confers or requires control of a domain. Associated Domains, for universal links, genuinely does require serving a file from a domain you control — but that is a separate mechanism, configured separately, and unaffected by this choice.

The reopening also reconsidered the product name itself. That work is recorded in [naming-investigation.md](../naming-investigation.md); the conclusion was to keep Cadastre.

## Decision

Bundle identifier **`com.cadastrerecord.app`**, prefix `com.cadastrerecord`.

It is rooted in a coined string rather than a domain. Nobody else will claim it, no purchase is required, and nothing a registrar does can invalidate it. It echoes the App Store name already chosen, `Cadastre: Building Record`. `cadastrerecord.com` showed no DNS record on 2026-09-14, so the matching domain is available if a website is ever wanted — but the identifier does not wait on it and never will.

Everything else in ADR-0020 and ADR-0019 stands: product name Cadastre, CLI and Python package `cadastre`, Swift package `CadastreCore`, marker labels `CD-000` to `CD-059`, store `cadastre-data`, repository `DavidKelly94/cadastre`.

## Consequences

Positive: the App ID can be registered the moment the Apple account is ready, with nothing to buy first; the identifier cannot be orphaned by a lapsed or lost domain; and it reads as an ordinary iOS bundle identifier in the places it is seen.

Negative, carried knowingly:

- **It breaks the reverse-DNS convention's spirit** — `cadastrerecord.com` is not owned at the time of writing. The convention exists for collision avoidance, which a coined string satisfies, but a purist will notice.
- **It is longer** than the alternatives, and appears in every crash report.
- **Two ADRs in two days** on one identifier. The decision is cheap to change only until the App ID exists, which is exactly why it was worth revisiting rather than defending.

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| Keep `build.cadastre.app` | Puts a domain purchase on the critical path for no verification benefit, and reads as a build setting. |
| `com.cadastre.app` | The natural form, but `cadastre.com` is a live French parcel-viewer product; this takes the reverse-DNS of a namespace someone else holds. |
| `com.usecadastre.app` | Conventional and ownable, but reintroduces the purchase and the "use" prefix is a cliché. |
| Rename the product | Explored at length on 2026-09-13/14 across roughly 150 candidates and six naming angles. Every avenue collided with a funded adjacent company or a generic descriptor. See naming-investigation.md. |
