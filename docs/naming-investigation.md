# Naming investigation: closed

**This question is settled.** The product is **VividHome**, the bundle identifier is
`ai.vividhome.app`, and the accepted decision is [ADR-0024](adr/0024-name-vividhome.md).
Nothing below reopens it; this file survives only to record what was and was not
verified, and to hold the two items that are still genuinely open.

## Why this file was rewritten

It was written on 2026-09-12, while the product was named *Cadastre*, to work through
one question: whether the wordmark should carry an "AI" suffix. When the product was
renamed, a mechanical sweep replaced every occurrence of the old name — including the
ones inside sentences that were *about* the old name rather than about the product.
The result asserted, among other things, that `vividhome.com` resolves to a live French
product, that the name is unfamiliar to most Americans, and that "VividHome AI" is a
near-homograph of "Cadastral AI". Every one of those claims was true of *Cadastre* and
false of *VividHome*.

Rather than leave a document whose every fact was wrong, it is replaced by the record
below. The original reasoning is preserved where it belongs, in the decision records:
[ADR-0019](adr/0019-name-cadastre.md) (the old name and its full elimination list),
[ADR-0023](adr/0023-bundle-id-needs-no-domain.md) and
[ADR-0024](adr/0024-name-vividhome.md). Accepted ADRs are never edited, so they still
read in the old name's terms, which is correct.

The lesson generalises past naming: **a rename sweep is safe on identifiers and unsafe
on prose.** A name inside a sentence may be the subject of the sentence rather than a
label for the product. Sweep by symbol, not by word.

## What carried forward, and what did not

| Claim | Status |
|---|---|
| The wordmark is one word: **VividHome** | Decided, ADR-0024 |
| "VividHome AI" is allowed as a *descriptor*, not as the wordmark | Carried forward from ADR-0019; the reasoning below still holds |
| Bundle identifier `ai.vividhome.app` | Decided, ADR-0024; permanent once the App Store Connect record exists |
| App Store display name | Open; try bare `VividHome` first, qualifier ready. See `owner-setup.md` §3 |
| "Bare name taken by app id 1507993968" | **Void.** That app is a French *cadastre* viewer; it says nothing about this name |
| "`.com` and `.io` resolve to live French products" | **Void.** Was true of the old name; unverified for this one |
| The "Cadastral AI" homograph collision | **Void as stated.** It was a collision with the *old* root word |

The suffix argument that does survive the rename is the general one, and it is why
"VividHome AI" stays a descriptor rather than the wordmark: the USPTO refused OpenAI's
"GPT" application because an industry-generic descriptor is not a source identifier, so
an "AI" suffix would likely be disclaimed and add no trademark scope; and the suffix is
being dropped across the industry rather than added — Acer removed it from its Swift
line, Pepper Content became Pepper, Runpod's rebrand excluded it, ClearCOGS dropped it.
An analysis of 200 Y Combinator companies found no fundraising advantage: of 79 matched
pairs, AI-named won 25, non-AI won 31, 23 tied.

## Still open

1. **No trademark clearance has been done.** The research environment could not reach
   USPTO or WIPO, so everything ever recorded here was search-index and DNS evidence.
   A real clearance search is required before spending on the mark, and none of the
   old name's clearance work transfers.
2. **`vividhome.ai` is unverified.** The bundle identifier is the reverse-DNS form of
   that domain, so it should be held; a registrar is the only authority on whether it
   is available, and a missing DNS record is not proof. `.ai` carries a two-year
   minimum. A subdomain such as `app.vividhome.ai` is not a separate purchase; it
   belongs to whoever owns the apex.
