# ADR-0019: The product is named Cadastre, bundle identifier `com.davidkelly.cadastre`

## Status

Accepted, 2026-09-12. Supersedes [ADR-0015](0015-name-igloo.md).

The wordmark question was reopened the same day; see [docs/naming-investigation.md](../naming-investigation.md). This record stands until a superseding ADR replaces it.

## Context

ADR-0015 chose "Igloo" on the brand in use at the time, when this was a personal tool. The owner now
intends to market the product and has moved it to a personal account, and "Igloo" says nothing
about what it does. A bundle identifier is permanent once an App Store Connect record exists and
none had been created, so the rename was free at this moment and would not be later.

Four vetting rounds ran. The first assumed the product was about seeing through walls and was
rejected as too narrow, since the product also inspects, answers questions, and will carry markup
and coordination. The decisive finding across all four: **self-explanatory names in this category
are taken, usually by a direct competitor**, while the category leaders carry opaque names.

## Decision

Product name **Cadastre**: the authoritative register of what exists on a parcel, borrowed and
applied to a building. Bundle identifier `com.davidkelly.cadastre`. CLI and Python package
`cadastre`; Swift package `CadastreCore`; marker labels `CD-000` to `CD-059`; local store
`cadastre-data`; repository `DavidKelly94/cadastre`.

**Not "Cadastre AI", and not `cadastre-ai`.** The suffix is what creates the product's worst
collision: [Cadastral](https://cadastral.ai/) is an AI platform for commercial real estate that
raised $9.5M and was [acquired by Legora](https://legora.com/newsroom/legora-acquires-cadastral-to-bring-ai-native-legal-intelligence-to-commercial-real-estate)
in June 2026, and "Cadastre AI" is a near-homograph of "Cadastral AI" that search engines already
conflate. The suffix also adds nothing legally: the USPTO refused OpenAI's "GPT" application
because an industry-generic descriptor is not a source identifier, and "AI" is the same category of
word. Use "Cadastre AI" only as a descriptor in a directory or title tag, never as the wordmark.

**The bundle identifier is deliberately decoupled from the domain.** Apple's own wording is that a
bundle ID *"should* also be in reverse-DNS format", for collision avoidance rather than as proof of
ownership, and no ownership check exists. The domain was unsettled when the identifier had to be
fixed, so it is rooted in something permanently controlled instead. Note that Associated Domains,
for universal links, *does* require serving a file from a domain you control; that is a separate
mechanism and unaffected.

## Consequences

Positive: the mark is distinctive in the field it competes in, the identifier cannot be orphaned by
a domain that falls through, and the name survives the product growing into inspection, question
answering, markup and coordination in a way the wall-and-see-through names would not.

Negative, carried knowingly:

- **The App Store name needs a qualifier.** Bare "Cadastre" is taken by a French parcel viewer
  (app id 1507993968), and store names must be unique within 30 characters. The working choice is
  "Cadastre: Building Record".
- **The word is unfamiliar to most Americans.** It is "kuh-DASS-ter"; some will try "CAD-astre",
  and CAD is a live word in this industry. It also sits near "cadaver" on a fast first read. Both
  are mitigated by pairing the wordmark with its line on first touch and never abbreviating to "CAD".
- **`cadastral` is both the adjective and a competitor**, so search traffic will leak both ways and
  a brand-defence term is the normal remedy.
- **The obvious domains are gone.** `cadastre.com` and `cadastre.io` resolve to live French
  products; `cadastre.ai` showed unavailable at a registrar that does carry `.ai`.

## Why the land reading is a strength here

Distinctiveness under the Abercrombie spectrum is judged relative to the goods. For land-registry or
GIS software "Cadastre" is generic and essentially unregistrable, which is exactly why Cadastre.com,
cadastre.io and the French App Store app coexist without excluding one another. For AI-assisted
construction documentation the word is arbitrary: it borrows a register's connotation and applies it
to an unrelated product. The owner's concern that the name felt "too land focused" and the source of
the mark's strength are the same fact. Positioning carries the difference: the tagline says
*building*, not land.

## Names eliminated, so a future round starts here

Taken by an established user, with the field that disqualified them: Lintel (Procore-integrated
construction AI plan review), HomeLedger (AI-first home management, same audience), Buildledger
(six users), Sitemind, Homedex, Tenon, Stratum, Almanac, Cairn (AI *and* housebuilding), Revisit
(phonetic near-miss to Revizto, construction BIM collaboration), Buildatlas, ClearFrame, Framewise,
Gridline, Plumbline, Glasshouse, Hindsight, Retrace, Fenestra (AI architectural rendering, 20k
architects), Glazier (software for glazing contractors), Clerestory and its Clearstory spelling
(construction change orders), Tomo, Roentgen, Scintilla, Corbel, Plinth, Ashlar, Joist, Purlin,
Datum, Trestle, Trowel, Spandrel, Gazetteer, Wainscot, Mortise, Astragal.

Rejected for other reasons: Sheer (homophone of *shear*, and "shear wall" is live framing
vocabulary, so it cannot be dictated on site); Muntin, Casement and Newel (clean, but declined);
Lightshelf, Fanlight, Glasswright (clean, but the register metaphor was preferred).

## Two caveats that must not be lost

1. **This is not legal clearance.** No trademark register was actually searched; the research
   environment could not reach USPTO or WIPO. A real clearance search is required before spending
   on the mark.
2. **Domain findings are DNS-resolution and search-index evidence only.** A missing record is not
   proof a domain is available. Confirm at a registrar before purchase.

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| Keep Igloo | Says nothing about the product, and the rename is free only before the app record exists |
| "Cadastre AI" as the wordmark | Creates the Cadastral collision it is meant to avoid, and adds no trademark scope |
| A self-explanatory name | Every one vetted was taken, most by direct competitors in this exact category |
| Bundle ID `ai.cadastre.app` | Depends on a domain that is not secured, and the identifier is permanent |
