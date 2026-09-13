# ADR-0020: The product is named Cadastre, bundle identifier `build.cadastre.app`

## Status

Accepted, 2026-09-13. Supersedes [ADR-0019](0019-name-cadastre.md).

The name decision and the four rounds of research behind it carry forward unchanged; ADR-0019 remains the place to read that reasoning. Only the bundle identifier changes here.

## Context

ADR-0019 set the identifier to `com.davidkelly.cadastre`, reasoning that a bundle ID needs a permanently controlled root, that no domain was secured, and that Apple performs no ownership check — so it fell back to the owner's personal name.

That was written while this was still a personal tool moved to a personal account. The owner intends to market the product, and the identifier is not private: it appears in the App Store Connect record, in crash reports, in entitlements, and in anything derived from it such as an App Group. A personal name sits badly in the one place a product should stand on its own, and it cannot be changed once an app record exists.

Meanwhile the domain question narrowed. [docs/naming-investigation.md](../naming-investigation.md) found `cadastre.build` unregistered, construction-native, and roughly a third the cost of `.ai` with no two-year minimum, and named it the one to pursue.

## Decision

Bundle identifier **`build.cadastre.app`**, prefix `build.cadastre`. Everything else in ADR-0019 stands: product name Cadastre, CLI and Python package `cadastre`, Swift package `CadastreCore`, marker labels `CD-000` to `CD-059`, store `cadastre-data`, repository `DavidKelly94/cadastre`.

The identifier is committed before the domain is registered. ADR-0019 declined that bet on `cadastre.ai`, and the cases differ: `.ai` was probably already held by someone else, whereas `cadastre.build` was free, so it is available to secure rather than merely hoped for. **Register the domain before creating the App ID**, which is the point of no return.

## Consequences

Positive: the identifier names the product only, it is rooted in a domain that can actually be held, and the root extends cleanly to a second app in the family (`build.cadastre.viewer`).

Negative, carried knowingly:

- **A domain purchase joins the critical path**, ahead of the App ID step in [owner-setup.md](../owner-setup.md). If `cadastre.build` has gone since the check, the identifier must be settled again before registration.
- **`.build` as a prefix root is unusual** and will read as a typo to some. It is legal reverse-DNS and Apple does not inspect it.
- ADR-0019's argument against domain-rooted identifiers is overridden here, not refuted. The mitigation is sequencing, not a better argument.

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| Keep `com.davidkelly.cadastre` | Puts the owner's name, permanently, on a product meant to stand on its own. |
| `com.cadastre.app` | Squats the reverse-DNS of `cadastre.com`, a live French product. |
| `com.cadastreapp.cadastre` | No domain dependency, but a coined root and a doubled word in every Xcode and App Store Connect field. |
| Defer until the domain is bought | Leaves a known-wrong identifier in `project.yml` where it can be registered as-is. |
