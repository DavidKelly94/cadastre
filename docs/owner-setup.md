# Cadastre owner setup

This is the runbook for everything only you can do: the Apple and GitHub accounts, the phone, the markers and the PC. None of it needs a Mac. The implementer handles all code, CI and build failures; you handle this list and report what you see.

You need an iPhone 15 Pro or newer, your Apple Account with a payment method, admin rights on `github.com/DavidKelly94/cadastre`, and the Windows PC.

## 1. Day 0: Apple Developer Program

1. Turn on two-factor authentication on your Apple Account if it is off: iPhone Settings, your name, Sign-In & Security, Two-Factor Authentication. Enrollment refuses accounts without it.
2. Enroll as an **individual** (not an organization) at https://developer.apple.com/programs/enroll/ or in the Apple Developer app on the phone (Account tab, Enroll). Cost is $99 per year.
3. Pay and wait for the welcome email. Apple says about 24 hours; reports in 2026 range up to several days. Steps 2 to 5 are blocked until it arrives, which is why this is day 0.

## 2. Register the domain, then the App ID

**Buy `cadastre.build` first.** The bundle identifier is `build.cadastre.app`, the reverse-DNS form of that domain ([ADR-0020](adr/0020-bundle-id-cadastre-build.md)). Apple never checks who owns it, so registration will succeed either way — but the identifier can never be changed after the next section, and it should not be left pointing at a domain someone else holds. `cadastre.build` had no DNS record when it was checked on 2026-09-12; if it has gone since, stop and settle a new identifier before going further.

Then sign in at https://developer.apple.com/account, open Certificates, Identifiers & Profiles, then Identifiers. Click the plus button, choose App IDs, then App. Description `Cadastre`, Bundle ID **Explicit**, `build.cadastre.app`. Tick no capabilities. Register. This identifier is permanent; do not vary it.

## 3. Create the app in App Store Connect

At https://appstoreconnect.apple.com open My Apps, click the plus button, New App. Platform iOS, Name **`Cadastre: Building Record`**, Bundle ID `build.cadastre.app`, SKU anything (for example `cadastre-ios`).

**Do not type just `Cadastre`.** App Store names must be unique across the whole store, and `Cadastre` is already taken by a French cadastre and parcel viewer (app id 1507993968). Names are capped at 30 characters; `Cadastre: Building Record` is 25 and puts the word *building* beside the wordmark, which is the counterweight to the land reading of the name. The display name can be changed up until first release; the bundle ID cannot be changed at all once this record exists.

## 4. App Store Connect API key (Admin) and Team ID

1. In App Store Connect open Users and Access, the Integrations tab, then App Store Connect API. If it shows a Request Access button, click it and accept the terms.
2. Under Team Keys click Generate API Key. Name `github-actions-cadastre`, Access **Admin**. Admin is required: the build signs in the cloud, and any lower role fails with "Cloud signing permission error".
3. Download the `.p8` file. Apple allows this **once**; keep it somewhere safe. Note the **Key ID** (10 characters) on that row and the **Issuer ID** (a long UUID) at the top of the page.
4. Find your **Team ID** at https://developer.apple.com/account under Membership details (10 characters).

## 5. TestFlight

In App Store Connect open Cadastre, then the TestFlight tab. Under Internal Testing click the plus button, name the group `Owner`, tick **Enable automatic distribution**, and add yourself as a tester. On the phone, install TestFlight from the App Store and sign in with the same Apple Account.

## 6. GitHub secrets and the build workflow

Open https://github.com/DavidKelly94/homescanner/settings/secrets/actions and add four repository secrets:

| Secret | Value |
|---|---|
| `ASC_KEY_ID` | Key ID from step 4 |
| `ASC_ISSUER_ID` | Issuer ID from step 4 |
| `ASC_PRIVATE_KEY_P8` | The entire `.p8` file contents, including the BEGIN and END lines |
| `APPLE_TEAM_ID` | Team ID from step 4 |

The repository is public, so GitHub-hosted runners, including the macOS ones, are free. Builds start automatically when code under `ios/` changes on the branch `claude/construction-3d-mapping-app-nzm3bb`. To start one by hand: Actions tab, `ios-testflight` in the left list, Run workflow, pick that branch, Run workflow. A run takes up to 30 minutes.

Never paste the `.p8` into an issue, a chat or a commit.

## 7. Install a build and follow the test plan

TestFlight notifies you when a build has been processed, usually within 15 minutes of the workflow finishing. Open TestFlight, Cadastre, Install or Update. The build number is the GitHub run number and is shown on the app's first screen.

Every build carries its own test plan: open Settings in the app, then Test plan (the same text is in TestFlight under What to Test). Work through it and report the build number, each item as pass or fail, and your iPhone model and iOS version. If a session misbehaves, include its `log.txt` (step 8). Builds expire 90 days after upload; install the newest one.

## 8. Getting sessions to the PC

Sessions live in the Files app: On My iPhone, Cadastre, `sessions`, a project folder, then one folder per session named like `20260926-101500_L1_kitchen_framing_a1b2c3`. A 5-minute room is about 800 MB.

Over Wi-Fi (SMB): on the PC, right-click a folder such as `D:\cadastre-inbox`, Properties, Sharing, Share, add your Windows user, and note the PC's IP address (`ipconfig`). On the phone, in Files tap the three dots, Connect to Server, enter `smb://<pc-ip>`, sign in as a registered user; the share appears under Shared. Long-press the session folder, Copy, open the share, Paste. Use the 5 GHz network.

Over USB: install Apple Devices from the Microsoft Store, plug the phone in, tap Trust on the phone, select the iPhone, open Files, expand Cadastre and drag session folders to the PC.

Delete a session from the phone only after `cadastre validate` (step 9) has passed on the PC copy: Session review, Delete, or delete the folder in Files. Deleting the app deletes every session still on the phone.

## 9. The PC pipeline

1. Install uv: in PowerShell run `powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"`. Install Git for Windows if `git` is missing.
2. `git clone https://github.com/DavidKelly94/homescanner`, then `cd homescanner\pipeline` and `uv sync` (installs Python 3.12 and every dependency).
3. `uv run cadastre --help` lists the commands.
4. After every capture: `uv run cadastre ingest D:\cadastre-inbox\<session>` copies it into the project store, then `uv run cadastre validate <session>` checks the files. Paste the full output to the implementer, even when it passes.
5. As they land: `uv run cadastre apriltag`, `plan add`, `plan calibrate`, `align` and `inspect` (serves a page at http://localhost:8000). Run `git pull` and `uv sync` first to pick up new commands.

Keep the project store outside the git checkout (for example `D:\cadastre\projects`) and back it up to an external drive after each visit.

## 10. Printing markers

`uv run cadastre markers --out markers.pdf` writes one marker per page, `CD-000` to `CD-059`. Print the first 20 pages on Letter or A4 at 100% (never Fit to page). Laminate with matte pouches; glossy lamination causes glare that breaks detection. Check with a tape that the outer square measures 20.0 cm. Placement and record keeping follow `docs/markers.md`: two per room, on surfaces that survive the next phase, never moved, position written down.

## 11. Troubleshooting

| Symptom | Cause and fix |
|---|---|
| Enrollment pending for days | Normal in 2026. Check the Apple Developer app for an identity request; contact Apple Developer Support after 5 business days. |
| Build log says "Cloud signing permission error" | The API key is not Admin. Generate a new Admin key and replace all three `ASC_` secrets. |
| Workflow succeeded but no build in TestFlight | Apple processing delay. Wait up to an hour, then check App Store Connect, TestFlight, iOS builds for a processing or rejected state. |
| TestFlight asks about export compliance | Should not happen: the app sets `ITSAppUsesNonExemptEncryption` to false. If it does, answer No. |
| Build shows Expired in TestFlight | Builds last 90 days. Install a newer build or run the workflow again. |
| App Store Connect rejects the app name | It is taken; add or change the qualifier, for example `Cadastre: Site Record`. Never change the bundle ID to work around a name clash. |
| Phone cannot see the SMB share | Same Wi-Fi network, Windows file sharing on, use the IP address not the PC name. |
| `cadastre validate` fails | Paste the output to the implementer. Do not delete the session from the phone. |

## 12. Fallback capture if the app is not ready

If framing starts before Cadastre is capture-ready, capture anyway with a free ARKit recorder plus the same markers and protocol; `cadastre ingest` gets a converter for it and nothing downstream changes.

- NeRFCapture: free on the App Store, updated May 2026; saves posed images plus LiDAR depth offline.
- Stray Scanner: RGB, depth, confidence, intrinsics and poses.
- Record3D: `.r3d` export, about $5 in-app unlock.

Place markers as in `docs/markers.md`, record one room per session, and follow `docs/capture-protocol.md`: start at the door, slow sweeps at chest height, each wall square-on with a tape measure in frame, close stills of every box, pipe, gas line, header, blocking and duct, finish where you started.

## 13. Claude automation and local gates (from the `base` harness)

This repository adopted the shared caller workflows from `DavidKelly94/base`,
so four of them now live in `.github/workflows/`: `claude.yml` answers `@claude`
mentions, `claude-review.yml` reviews every pull request, `dependabot-automerge.yml`
auto-merges patch and minor dependency bumps, and `main-triage.yml` opens a
diagnosis issue when CI fails on the default branch. They are thin callers; the
behaviour lives in `base` at the pinned `@v1` ref.

Three things to do once:

1. **Add this repository to the Claude GitHub App** at
   https://github.com/settings/installations so the workflows can act on it.
2. **Set the auth secret.** Add a repository secret named `CLAUDE_CODE_OAUTH_TOKEN`.
   Without it the Claude workflows fail immediately.
3. **Install the plugin locally** so you get the same skills the workflows use:
   `/plugin marketplace add DavidKelly94/base`, then
   `/plugin install base@snoday`. That provides `/base:check` (the deterministic
   gate), `/base:review` (the same rubric CI applies) and `/base:ship` (the
   definition of done).

Two behaviours worth knowing so they do not look like bugs:

- **The first pull request that adds `claude-review.yml` skips its own review.**
  That is deliberate tamper protection, not a failure. Confirm the review works on
  the next pull request.
- **`dependabot-automerge` needs "Allow auto-merge" enabled and at least one
  required status check** on the target branch. Without a required check it merges
  immediately instead of waiting for CI, which is worse than not having it. Enable
  both, or disable that workflow.

Local gates run through `pre-commit` (ruff, gitleaks, shellcheck, actionlint,
whitespace). Once per clone:

```
pip install pre-commit      # or: pipx install pre-commit
pre-commit install
pre-commit run --all-files  # optional, first time
```

`.github/workflows/claude.yml` carries a deliberate change from base's template: a
guard restricting it to repository owners, collaborators and members. base's
reusable checks only that the commenter is not a bot, and this repository is
public, so without the guard any GitHub user could comment `@claude` and drive a
job that holds write permissions and spends your Claude usage. Read the comment in
the file before editing it, and re-check it after any `fleet-sync`.

## 14. Going private later: what changes

The repository stays public through the build sprint on purpose, because standard
GitHub runners are free on public repositories. Private repositories draw from a
monthly allowance with a multiplier per operating system, and **macOS counts 10x**.
GitHub Free includes 2,000 minutes a month, which is only **200 macOS minutes**;
Pro includes 3,000, so 300. Overage on standard macOS runners is **$0.062 a minute**,
and on Free the default spending limit is **$0**, which means Actions simply stops
once the allowance is gone.

So when you do flip to private, in this order:

1. Read the Actions usage page first and see what the sprint actually consumed.
   That number decides Free plus a spending limit versus Pro; do not guess.
2. **Raise the Actions spending limit above $0** before flipping, or the TestFlight
   loop will halt mid-build with no obvious cause.
3. Restrict `ios-check` to `pull_request` and `workflow_dispatch` instead of every
   push touching `ios/**`. You lose a per-push compile signal, which is worth
   paying for only once minutes are billed.
4. Flip both this repository and `base` to private.
5. **Grant same-owner Actions access on `base`**: its Settings, then Actions, then
   General, then Access, set to "Accessible from repositories owned by the user".
   Miss this and every caller fails with "workflow was not found", which reads like
   a broken workflow rather than a missing permission.
6. Re-check whether required status checks are still available on your plan. If not,
   disable `dependabot-automerge` rather than let it merge without gating.

`docs/transfer-runbook.md` has the full two-phase sequence, including the repository
transfer itself.
