# ADR-0018: Stay public through the build sprint, then go private

## Status

Accepted, 2026-09-12. Amends a stated consequence of ADR-0002 and ADR-0012.

**Update, 2026-09-13.** The repository was found already private — the flip happened at the account transfer rather than after TestFlight, so the staging below had not in fact been followed. The owner is returning it to public for the remainder of the sprint, which restores this decision as written. The one protection deferred to the flip, restricting `ios-check` to `pull_request` and `workflow_dispatch`, has been taken early at the owner's direction: it costs a per-push compile signal but holds in either state, so it need not be revisited when the repository does go private. The decision itself is unchanged.

## Context

ADR-0002 put iOS builds on GitHub Actions because the owner has no Mac, and both it
and ADR-0012 list the same supporting consequence: "A public repository makes macOS
runner minutes free." The owner now intends to transfer this repository and `base`
to a personal account and make both private, which invalidates that premise.

The arithmetic is not marginal for a macOS-heavy project. Standard runners are free
on public repositories; private ones draw from a monthly allowance at 1x for Linux,
2x for Windows and **10x for macOS**.

| | Free | Pro |
|---|---|---|
| Included minutes | 2,000 | 3,000 |
| As macOS wall-clock | **200** | **300** |
| Overage, standard macOS | $0.062/min | $0.062/min |
| Default spending limit | **$0**, so Actions stops | $0 |

`ios-check` runs 5 to 10 minutes and `ios-testflight` 10 to 20, with six TestFlight
builds scheduled across a fortnight of frequent pushes, so a realistic sprint is 300
to 700 macOS minutes. Private from the start means $6 to $31 of overage and, worse,
a silent mid-sprint halt that would look like a broken workflow.

## Decision

Stage it. Transfer both repositories to the personal account and **leave them public
through the sprint**, then make both private once TestFlight works and the app is
capturing.

Two protections land now, since they are free while public: `concurrency` with
`cancel-in-progress: true` on both macOS workflows, and the existing tight path
filters kept as they are. One is deferred to the flip because it costs a per-push
compile signal: restricting `ios-check` to `pull_request` and `workflow_dispatch`.

At the flip, in order: read the Actions usage page for real consumption, raise the
spending limit above $0, apply the deferred trim, flip both repositories, then
**grant same-owner Actions access on `base`**, because the adopted callers reference
its reusable workflows and a private repository does not share them by default.
`docs/transfer-runbook.md` holds the sequence.

## Consequences

Positive: the deadline-bound period is free and cannot halt itself on a budget, the
decision gets made once against a real usage number, and concurrency cancellation
shortens feedback while public.

Negative: the repository is public for a period, which is why
`.github/workflows/claude.yml` carries an author-association guard base's template
lacks; there are two visibility states and a checklist that must actually be run; and
afterwards steady-state macOS usage has to stay near 200 minutes a month.

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| Private immediately, Free plus a spending limit | Pays $6 to $31 for nothing and risks a mid-sprint halt in the only deadline-bound period |
| Private immediately on Pro | $4 a month buys 100 extra macOS minutes, still short of a 300 to 700 minute sprint |
| Private immediately, macOS CI on manual dispatch only | Removes the compile signal the implementer depends on; iOS code cannot be compiled anywhere else here |
| Stay public permanently | Not the owner's intent; the record contains photographs of their house and its structure |
