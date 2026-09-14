# Implementation guide

Step-by-step instructions for implementing Cadastre from the docs in this repository. Written for a coding agent working in a Linux container with no Xcode and possibly no Swift toolchain; all iOS compilation happens on GitHub Actions. The owner tests on the phone via TestFlight.

Read first: `docs/plan.md` (approved plan), `docs/session-format.md` (the contract), `docs/design/system-design.md`, `docs/design/ios-app-design.md`, `docs/design/pipeline-design.md`, `docs/schedule.md`, `docs/adr/README.md`.

## 0. Ground rules

- Branch: `claude/construction-3d-mapping-app-nzm3bb`. Commit small, push often (`git push -u origin <branch>`). Never force-push.
- The working loop for iOS: edit → push → wait for `ios-check` → read the job log through the GitHub API tools → fix → push. Do not guess at compiler errors; read the log.
- No third-party Swift dependencies. No Swift 6 strict concurrency (`SWIFT_VERSION = 5.0`). No embedded frameworks (the signing flow depends on it).
- Never commit secrets. The App Store Connect key exists only as GitHub secrets.
- Use the harness skills rather than a private definition of done: `/base:check`
  runs the deterministic gate (it picks up this repo's commands from
  `.harness.yml`), `/base:review` applies the same rubric CI's review uses, and
  `/base:ship` is the bar — no push until the gate and the self-review both pass,
  and a red check on your own PR is yours to fix. Read
  `plugins/base/ship/POLICY.md` in the `base` checkout once, then follow it.
- Dependencies are not installed for you: the plugin's SessionStart hook only
  looks at the repository root, and this repo's Python manifest is
  `pipeline/pyproject.toml`. Run `uv sync --project pipeline` yourself.
- Keep the session format stable; any change goes through `docs/session-format.md` first.
- Update the docs when behaviour changes; keep `docs/adr/` current (new decision → new ADR).
- No AI model identifiers in commits, code or docs.
- Every push that changes `ios/**` triggers a TestFlight build once secrets exist; write the in-app `TestPlan.md` for each build the owner should test.

## 1. Environment check (5 minutes)

```
python3 --version           # need 3.12; install uv: curl -LsSf https://astral.sh/uv/install.sh | sh
uv --version
swift --version || echo "no swift locally: rely on core-test.yml"
git status && git branch --show-current
```

## 2. Scaffold

Create:

```
.gitignore                  (macOS, Xcode, Python, uv, node, cadastre-data/, *.xcodeproj, DerivedData, .build)
pipeline/pyproject.toml     see §6
pipeline/cadastre/__init__.py  __version__ = "0.1.0"
pipeline/cadastre/cli.py       argparse with all subcommands stubbed (print "not implemented", exit 2)
pipeline/tests/test_cli.py  `cadastre --help` works
ios/CadastreCore/Package.swift see §4
.github/workflows/core-test.yml, ios-check.yml, ios-testflight.yml   see §7
```

Run `cd pipeline && uv sync && uv run pytest` locally. Commit and push. `core-test` must be green before continuing.

## 3. CadastreCore (pure Swift)

Implement, with tests, in this order: `Transform` (column-major `[Double]` 4x4: identity, multiply, invert, translation, rotationAngle between two matrices), `SessionID` (slug + id6), `Records` (Codable structs matching `session-format.md` exactly; golden-string tests), `KeyframePolicy`, `HealthPolicy`, `JSONLWriter` (Foundation `FileHandle`; test on Linux with a temp file).

`Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription
let package = Package(
  name: "CadastreCore",
  platforms: [.iOS(.v17), .macOS(.v13)],
  products: [.library(name: "CadastreCore", targets: ["CadastreCore"])],
  targets: [
    .target(name: "CadastreCore"),
    .testTarget(name: "CadastreCoreTests", dependencies: ["CadastreCore"]),
  ]
)
```

Use only `Foundation`. No `simd`, no `ARKit`, no `UIKit`. Linux Foundation differences to remember: `JSONEncoder.OutputFormatting.sortedKeys` exists; `FileHandle.synchronize()` exists; avoid `NSString` bridging.

## 4. iOS project (`ios/project.yml`)

```yaml
name: Cadastre
options:
  bundleIdPrefix: com.cadastrerecord
  deploymentTarget:
    iOS: "17.0"
  createIntermediateGroups: true
  generateEmptyDirectories: true
packages:
  CadastreCore:
    path: CadastreCore
targets:
  Cadastre:
    type: application
    platform: iOS
    sources: [Cadastre]
    dependencies:
      - package: CadastreCore
        product: CadastreCore
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.cadastrerecord.app
        PRODUCT_NAME: Cadastre
        MARKETING_VERSION: "0.1.0"
        CURRENT_PROJECT_VERSION: "1"
        SWIFT_VERSION: "5.0"
        TARGETED_DEVICE_FAMILY: "1"
        CODE_SIGN_STYLE: Automatic
        ENABLE_USER_SCRIPT_SANDBOXING: "NO"
        ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS: "NO"
    info:
      path: Cadastre/Info.plist
      properties:
        CFBundleDisplayName: Cadastre
        UILaunchScreen: {}
        UISupportedInterfaceOrientations: [UIInterfaceOrientationPortrait]
        UIRequiredDeviceCapabilities: [arkit, arm64]
        NSCameraUsageDescription: "Cadastre records the camera and LiDAR to document your house during construction."
        UIFileSharingEnabled: true
        LSSupportsOpeningDocumentsInPlace: true
        ITSAppUsesNonExemptEncryption: false
        UIApplicationSupportsIndirectInputEvents: true
```

Start with a minimal app: `CadastreApp.swift` (`@main`), one `ContentView` showing "Cadastre build <CFBundleVersion>", whether `ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification)` is true, and a button that opens a full-screen `ARView`. Get `ios-check` green, then `ios-testflight` (once the owner adds secrets). This is **TestFlight build #1** (schedule day 2–3).

Then implement the screens and capture pipeline in the order of `docs/design/ios-app-design.md`, pushing a TestFlight build at each milestone in `docs/schedule.md`, each with an updated `Resources/TestPlan.md`.

`ios/ExportOptions.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>TEAM_ID_PLACEHOLDER</string>
  <key>testFlightInternalTestingOnly</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
  <key>uploadSymbols</key><true/>
</dict>
</plist>
```

The workflow substitutes `TEAM_ID_PLACEHOLDER` with the `APPLE_TEAM_ID` secret at run time (`sed`), so the real team ID is never committed.

## 5. Marker images

Before the marker detection feature: `cd pipeline && uv run cadastre markers --png ../ios/Cadastre/Resources/Markers --ids 0-59`. Commit the PNGs: they are about 38 KB each, 2.4 MB for the set, and the app bundles them as ARKit reference images, so they have to exist at build time on the runner.

The PDF is **not** committed. It is 3.3 MB, one command and four seconds to regenerate, and a single binary that would diff in full every time it was rebuilt — and it exceeds the 1 MB ceiling this repository's own `check-added-large-files` hook enforces outside `samples/`. `docs/owner-setup.md` already tells the owner to run `cadastre markers --out markers.pdf` when it is time to print, which is the only moment it is needed.

## 6. Pipeline (`pipeline/pyproject.toml`)

```toml
[project]
name = "cadastre"
version = "0.1.0"
requires-python = ">=3.12"
dependencies = ["numpy>=2.0", "opencv-python-headless>=4.10", "pypdfium2>=4.30", "reportlab>=4.2", "pillow>=10.4"]

[project.scripts]
cadastre = "cadastre.cli:main"

[dependency-groups]
dev = ["pytest>=8", "ruff>=0.6"]

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[tool.ruff]
line-length = 100
```

Implement in the order of `docs/design/pipeline-design.md`: `transforms` → `session` → `validate` → `synth` (so every later feature has a fixture) → `markers` → `apriltag` → `plan` → `align` → `inspector` → `ingest`. Each with tests; `uv run pytest` must stay green.

## 7. Workflows

`.github/workflows/core-test.yml` (the workflow's display name is `CI` because
base's adopted `main-triage.yml` triggers on `workflow_run` for
`workflows: ["CI"]`; the filename stays `core-test.yml`):

```yaml
name: CI
on: [push, pull_request]
jobs:
  swift:
    runs-on: ubuntu-latest
    container: swift:6.1
    steps:
      - uses: actions/checkout@v4
      - run: swift test --package-path ios/CadastreCore
  python:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/setup-uv@v6
      - run: uv sync --project pipeline
      - run: uv run --project pipeline ruff check pipeline
      - run: uv run --project pipeline pytest pipeline -q
```

`.github/workflows/ios-check.yml`:

```yaml
name: ios-check
on:
  push:
    paths: ["ios/**", ".github/workflows/ios-check.yml"]
  pull_request:
    paths: ["ios/**"]
  workflow_dispatch:
# macOS runners bill at a 10x multiplier once this repo goes private, so never
# let a superseded push keep a runner. See docs/adr/0018.
concurrency:
  group: ios-check-${{ github.ref }}
  cancel-in-progress: true
jobs:
  build:
    runs-on: macos-26
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v4
      - run: sudo xcode-select -s /Applications/Xcode_26.6.app
      - run: brew install xcodegen
      - run: xcodegen generate --spec ios/project.yml --project ios
      - run: >
          xcodebuild build -project ios/Cadastre.xcodeproj -scheme Cadastre
          -destination 'generic/platform=iOS Simulator'
          CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" | tee build.log | grep -E "error:|warning: unre|BUILD"
      - uses: actions/upload-artifact@v4
        if: failure()
        with: { name: ios-check-log, path: build.log }
```

If `brew install xcodegen` is slow or breaks, download the pinned release asset (`https://github.com/yonaskolb/XcodeGen/releases`) and verify its sha256 instead. If the Xcode path differs on the current image, read the runner image README (`actions/runner-images`, `macos-26-arm64-Readme.md`) and adjust.

`.github/workflows/ios-testflight.yml`:

```yaml
name: ios-testflight
on:
  push:
    branches: ["claude/construction-3d-mapping-app-nzm3bb"]
    paths: ["ios/**"]
  workflow_dispatch:
concurrency:
  group: testflight
  cancel-in-progress: true
jobs:
  preflight:
    runs-on: ubuntu-latest
    outputs: { ready: ${{ steps.check.outputs.ready }} }
    steps:
      - id: check
        env: { KEY: ${{ secrets.ASC_KEY_ID }} }
        run: echo "ready=$([ -n "$KEY" ] && echo true || echo false)" >> "$GITHUB_OUTPUT"
  build:
    needs: preflight
    if: needs.preflight.outputs.ready == 'true'
    runs-on: macos-26
    timeout-minutes: 40
    steps:
      - uses: actions/checkout@v4
      - run: sudo xcode-select -s /Applications/Xcode_26.6.app
      - run: brew install xcodegen
      - run: xcodegen generate --spec ios/project.yml --project ios
      - name: Write API key and export options
        env:
          P8: ${{ secrets.ASC_PRIVATE_KEY_P8 }}
          TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
        run: |
          mkdir -p "$RUNNER_TEMP/keys"
          printf '%s\n' "$P8" > "$RUNNER_TEMP/keys/AuthKey.p8"
          sed "s/TEAM_ID_PLACEHOLDER/$TEAM_ID/" ios/ExportOptions.plist > "$RUNNER_TEMP/ExportOptions.plist"
      - name: Archive (unsigned)
        run: >
          xcodebuild archive -project ios/Cadastre.xcodeproj -scheme Cadastre
          -destination 'generic/platform=iOS' -archivePath "$RUNNER_TEMP/Cadastre.xcarchive"
          CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=""
          DEVELOPMENT_TEAM=${{ secrets.APPLE_TEAM_ID }}
          CURRENT_PROJECT_VERSION=${{ github.run_number }}
      - name: Export and upload (cloud signing)
        run: >
          xcodebuild -exportArchive -archivePath "$RUNNER_TEMP/Cadastre.xcarchive"
          -exportOptionsPlist "$RUNNER_TEMP/ExportOptions.plist" -exportPath "$RUNNER_TEMP/export"
          -allowProvisioningUpdates
          -authenticationKeyPath "$RUNNER_TEMP/keys/AuthKey.p8"
          -authenticationKeyID "${{ secrets.ASC_KEY_ID }}"
          -authenticationKeyIssuerID "${{ secrets.ASC_ISSUER_ID }}"
      - uses: actions/upload-artifact@v4
        if: always()
        with: { name: export-logs, path: "${{ runner.temp }}/export/*.plist" }
```

Fallback ladder if the export step fails (in order; each is a small change): (1) `destination: export` in the plist and upload the IPA with `apple-actions/upload-testflight-build@v5` using the same key; (2) archive with cloud signing (drop `CODE_SIGNING_ALLOWED=NO` from the archive step and pass the three `-authentication*` flags there too); (3) fastlane `match` (git storage on a `certs` branch of this repo) + `upload_to_testflight(api_key:)`. Common causes: key not Admin ("Cloud signing permission error"); bundle ID not registered; app record missing in App Store Connect.

## 8. Samples

After the owner's first valid capture, copy a trimmed session (≤ 10 keyframes, 1 still, all JSONL, `mesh.obj` truncated to ≤ 2,000 faces) into `samples/session-v1/` and point `tests/test_real_sample.py` at it. Keep it under 6 MB.

## 9. Definition of done for the MVP

- `core-test` and `ios-check` green on the branch; the latest `ios-testflight` run uploaded and the build processed.
- The owner completed the Test plan of the latest build, including a 5-minute room with 3 markers, 3 stills and 4 landmarks.
- `cadastre validate` passes on that session; `apriltag` finds all 3 markers with < 3 cm spread; `plan add` + `calibrate` done for one level; `align` residual < 10 cm; `inspect` shows the trajectory on the plan.
- Docs updated to match; ADRs current; `docs/schedule.md` checked off through day 12.
