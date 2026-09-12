# ADR-0003: Cloud-managed signing from an unsigned archive

## Status

Accepted, 2026-09-11.

## Context

Uploading to TestFlight requires an Apple Distribution certificate and a provisioning profile. The classic route exports a `.p12` from a Mac keychain and stores it as a CI secret; without a Mac the owner cannot create one.

Xcode supports cloud-managed signing: given an App Store Connect API key (`-authenticationKeyPath`, `-authenticationKeyID`, `-authenticationKeyIssuerID`) and `-allowProvisioningUpdates`, `xcodebuild` obtains an Apple-managed distribution certificate and profile at export time, with no keychain or `.p12` (https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases). Verified on 2026-09-11: this works only when the key has the Admin role; lower roles fail with "Cloud signing permission error".

## Decision

`ios-testflight.yml` writes the key to `$RUNNER_TEMP/AuthKey.p8`, then:

1. `xcodebuild archive` unsigned: `CODE_SIGNING_ALLOWED=NO`, `DEVELOPMENT_TEAM` from the secret, `CURRENT_PROJECT_VERSION=${{ github.run_number }}`.
2. `xcodebuild -exportArchive -exportOptionsPlist ios/ExportOptions.plist -allowProvisioningUpdates` with the three key arguments. The plist sets `method app-store-connect`, `destination upload`, `signingStyle automatic`, `teamID`, `testFlightInternalTestingOnly true`, `manageAppVersionAndBuildNumber false`, `uploadSymbols true`.

Secrets: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY_P8` (the full `.p8` text), `APPLE_TEAM_ID`. The app links only system frameworks and the static `CadastreCore` package; embedded frameworks are excluded because they break the unsigned-archive, signed-export flow.

Fallback ladder if upload or signing misbehaves: (1) `destination export` plus `apple-actions/upload-testflight-build`; (2) sign during `archive` with the same API-key cloud signing; (3) fastlane `match` with git storage on a `certs` branch of this repository and `upload_to_testflight(api_key:)`, which adds a `MATCH_PASSWORD` secret (https://docs.fastlane.tools/actions/match/).

## Consequences

Positive:

- No certificate, private key or profile is stored anywhere; Apple manages and renews them.
- Four secrets, all obtainable on the web.
- Compile failures and signing failures are separated, and an archive can be re-exported.

Negative:

- An Admin key is a powerful secret; it lives only in GitHub Actions secrets.
- Cloud signing errors are terse and thinly documented.
- Dependencies are limited to static SwiftPM packages.
- The fallback rungs are untested until needed.

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| `.p12` and profile in secrets | Requires a Mac keychain to create, and yearly manual renewal. |
| fastlane `match` from day one | Adds Ruby tooling, a certs branch and another secret; kept as the last rung. |
| Signing during archive | Mixes compile and signing failures; kept as rung two. |
| Third-party upload action by default | Extra dependency; only needed if the `destination upload` export fails. |
