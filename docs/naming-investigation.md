# Naming investigation: picking this up

Written 2026-09-12, at the point where the name was decided and then immediately
reconsidered. Read [ADR-0019](adr/0019-name-cadastre.md) first; it is the accepted decision and
carries the full elimination list. This document exists for one open question: **should the
wordmark be "VividHome" or "VividHome AI"?**

## Where things stand

- **Decided and shipped:** the product is **VividHome**. The repository is `DavidKelly94/vividhome`,
  every identifier carries the name (CLI `vividhome`, Swift package `VividHomeCore`, markers `VH-000`
  to `VH-059`, store `vividhome-data`), and the bundle identifier is `ai.vividhome.app` ([ADR-0024](adr/0024-name-vividhome.md)).
- **ADR-0019 explicitly rejects "VividHome AI" as the wordmark**, while permitting it as a
  descriptor. That distinction is the whole of the open question.
- **Reopened by the owner**, who now thinks "VividHome AI" makes more sense. That instinct deserves
  a real hearing, because one of its arguments is strong and was under-weighted.

## The case for "VividHome AI"

1. **It solves a live problem.** Bare "VividHome" is already an iOS app, a French vividhome and
   parcel viewer (app id 1507993968). App Store names must be unique within 30 characters, so the
   app cannot ship as "VividHome" regardless. Something has to be appended, and "AI" is a candidate
   that costs no extra words.
2. **It fixes the opacity.** "VividHome" is unfamiliar to most Americans and is not
   self-explanatory, which was the owner's original complaint about the previous name. Attaching a
   category word does some of the work a tagline would otherwise carry alone.
3. **It pairs with a `.ai` domain**, if one is ever obtained, and reads consistently across a
   domain, a wordmark and a store listing.

## The case against, which is what ADR-0019 records

1. **The suffix creates the product's worst collision.** [Cadastral](https://cadastral.ai/) is an
   AI platform for commercial real estate that raised $9.5M and was
   [acquired by Legora](https://legora.com/newsroom/legora-acquires-cadastral-to-bring-ai-native-legal-intelligence-to-commercial-real-estate)
   in June 2026. "VividHome AI" is a near-homograph of "Cadastral AI", and during research every
   search for "VividHome AI" returned Cadastral instead. Plain "VividHome" is the form that separates
   the two. This is the objection that matters, and note its shape: **the suffix is what causes the
   collision, not the root word.**
2. **It adds no trademark scope.** The USPTO refused OpenAI's "GPT" application because an
   industry-generic descriptor is not a source identifier. "AI" is the same category of word and
   would likely be disclaimed, leaving the mark to stand or fall on "VividHome" anyway.
3. **The suffix is being dropped, not added.** Acer removed "AI" from its Swift laptop line, Pepper
   Content became Pepper, Runpod's rebrand excluded it, ClearCOGS dropped it. An analysis of 200 Y
   Combinator companies found no fundraising advantage: of 79 matched pairs, AI-named won 25,
   non-AI won 31, 23 tied.

## The middle path, which may already be what the owner wants

ADR-0019 permits "VividHome AI" as a **descriptor** and forbids it only as the **wordmark**. Under
that decision the following is already allowed today, with no new ADR:

| Context | Use |
|---|---|
| Wordmark, app UI, docs, repo | VividHome |
| App Store name | VividHome plus a qualifier, currently "VividHome: Building Record" |
| Directory listings, title tags, a LinkedIn company field | VividHome AI, where the category has to be spelled out |
| First-touch marketing | VividHome, with the line: the permanent register of your building |

If the instinct behind "VividHome AI" is *"people need to know it is an AI product"*, that is
satisfied here. If the instinct is *"the wordmark itself should say AI"*, then it is a real change
and needs the work below.

## What changes if "VividHome AI" becomes the wordmark

- **A new ADR superseding 0020.** The repository rule is that an accepted decision is never edited;
  write the next unused record with `Supersedes ADR-0020` and set 0020's status accordingly. (0020
  is the live name record: it superseded 0019 to change the bundle identifier.) Record the Cadastral
  collision as a known, accepted risk rather than dropping it, so a future reader knows it was
  weighed and not missed.
- **Display-name occurrences only.** `README.md`, `docs/ui/design-brief.md` sections 1 and 2, and
  `docs/owner-setup.md`. The identifiers do **not** change: `vividhome`, `VividHomeCore`, `VH-NNN`
  and `vividhome-data` stay, because a hyphenated or suffixed slug is worse in every one of those
  positions.
- **The bundle identifier does not change.** `ai.vividhome.app` is decoupled from the marketing
  name — a wordmark can gain a suffix without the identifier following — and it is permanent once an
  App Store Connect record exists. Leave it.
- **The design brief's wordmark lockup and icon.** A two-word wordmark sets differently from a
  one-word one, and the parcel-grid icon concept is unaffected.
- **Search defence gets more expensive**, because the whole point of the objection is that
  "VividHome AI" and "Cadastral AI" compete for the same queries.

## Open items, independent of the wordmark question

1. **The domain is unresolved.** `vividhome.ai` showed unavailable at Squarespace, which does carry
   `.ai`, so it is probably taken; it has no DNS record, which is consistent with a parked or
   defensive registration. `vividhome.com` and `vividhome.io` resolve to live French products.
   **`vividhome.build` had no DNS record**, is construction-native, costs roughly a third of `.ai`
   with no two-year minimum, and the sector already uses the TLD (`clearstory.build`). It is no
   longer merely the one to chase: ADR-0020 roots the bundle identifier in it, so it must be
   registered before the App ID is created. A subdomain such as `app.vividhome.ai` is not a separate purchase; it belongs to
   whoever owns the apex.
2. **No trademark clearance has been done.** The research environment could not reach USPTO or
   WIPO. Everything above is search-index and DNS evidence. A real clearance search is required
   before spending on the mark, and it should cover both forms.
3. **The App Store name is still nominally open.** "VividHome: Building Record" is written into
   `docs/owner-setup.md` as the working choice. It is changeable up until first release.
4. **Domain evidence is weak by construction.** A missing DNS record is not proof a domain is
   available. Confirm at a registrar before buying.

## How to pick this up

Read ADR-0019, then the middle-path table above. Decide whether the instinct is about the wordmark
or about the positioning. If it is positioning, nothing needs to change. If it is the wordmark,
write ADR-0020 and touch the display-name occurrences only, leaving every identifier and the bundle
identifier alone.
