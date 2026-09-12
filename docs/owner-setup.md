# Igloo owner setup

This is the runbook for everything only you can do: the Apple and GitHub accounts, the phone, the markers and the PC. None of it needs a Mac. Budget about an hour of clicking on day 0 plus Apple's enrollment wait, then about an hour on day 2 or 3 once enrollment clears. The implementer handles all code, CI and build failures; you handle this list and report what you see.

You need: an iPhone 15 Pro or newer, your Apple Account with a payment method, admin rights on `github.com/davidkelly-snoday/homescanner`, and the Windows PC.

## 1. Day 0: Apple Developer Program

1. Turn on two-factor authentication on your Apple Account if it is not on already: iPhone Settings, your name, Sign-In & Security, Two-Factor Authentication. Enrollment refuses accounts without it.
2. Enroll as an **individual** (not an organization) at https://developer.apple.com/programs/enroll/ or in the Apple Developer app on the phone (Account tab, Enroll). Cost is $99 per year. The app may ask for a government ID scan and a selfie.
3. Pay and wait for the welcome email. Apple says about 24 hours; reports in 2026 range up to several days. Steps 2 to 5 are blocked until it arrives, which is why this is day 0.

## 2. Register the App ID

Sign in at https://developer.apple.com/account, open Certificates, Identifiers & Profiles, then Identifiers. Click the plus button, choose App IDs, then App. Description `Igloo`, Bundle ID **Explicit**, `ai.snoday.igloo`. Tick no capabilities. Register. This identifier is permanent; do not vary it.

## 3. Create the app in App Store Connect

At https://appstoreconnect.apple.com open My Apps, click the plus button, New App. Platform iOS, Name `Igloo`, primary language English, Bundle ID `ai.snoday.igloo` from the list, SKU `igloo-ios`, User Access Full. Create. If the name is rejected as already in use, use `Igloo by snoday`; the bundle ID stays the same. Nothing else on the app page needs filling in for TestFlight.

## 4. App Store Connect API key (Admin) and Team ID

1. In App Store Connect open Users and Access, the Integrations tab, then App Store Connect API. If it shows a Request Access button, click it and accept the terms.
2. Under Team Keys click Generate API Key. Name `github-actions-igloo`, Access **Admin**. The Admin role is required: the build signs in the cloud, and any lower role fails with "Cloud signing permission error".
3. Download the `.p8` file. Apple allows this **once**; keep the file somewhere safe. Note the **Key ID** (10 characters) on that row and the **Issuer ID** (a long UUID) at the top of the page.
4. Find your **Team ID** at https://developer.apple.com/account under Membership details (10 characters).

## 5. TestFlight

In App Store Connect open Igloo, then the TestFlight tab. Under Internal Testing click the plus button, name the group `Owner`, tick **Enable automatic distribution**, then add yourself as a tester. On the phone, install TestFlight from the App Store and sign in with the same Apple Account. Internal testers receive every build without Beta App Review.

## 6. GitHub secrets and the build workflow

Open https://github.com/davidkelly-snoday/homescanner/settings/secrets/actions and add four repository secrets:

| Secret | Value |
|---|---|
| `ASC_KEY_ID` | Key ID from step 4 |
| `ASC_ISSUER_ID` | Issuer ID from step 4 |
| `ASC_PRIVATE_KEY_P8` | The entire `.p8` file contents, including the BEGIN and END lines (open it in Notepad, select all, copy) |
| `APPLE_TEAM_ID` | Team ID from step 4 |

The repository is public, so GitHub-hosted runners, including the macOS ones, are free. Builds start automatically when code under `ios/` changes on the branch `claude/construction-3d-mapping-app-nzm3bb`. To start one by hand: Actions tab, `ios-testflight` in the left list, Run workflow, pick that branch, Run workflow. A run takes up to 30 minutes. If it fails, the implementer reads the logs; you do not need to.

Never paste the `.p8` into an issue, a chat or a commit.

## 7. Install a build and follow the test plan

TestFlight notifies you when a build has been processed, usually within 15 minutes of the workflow finishing, sometimes longer. Open TestFlight, Igloo, Install or Update. The build number is the GitHub run number and is shown on the app's first screen.

Every build carries its own test plan: open Settings in the app, then Test plan (the same text is in TestFlight under What to Test). Work through it and report the build number, each item as pass or fail, your iPhone model and iOS version, and what you saw. If a session misbehaves, include its `log.txt` (step 8). TestFlight builds expire 90 days after upload; install the newest one.

## 8. Getting sessions to the PC

Sessions live on the phone in the Files app: On My iPhone, Igloo, `sessions`, then a project folder, then one folder per session named like `20260926-101500_L1_kitchen_framing_a1b2c3`. A 5-minute room is about 800 MB.

Over Wi-Fi (SMB): on the PC, right-click a folder such as `D:\igloo-inbox`, Properties, Sharing, Share, add your Windows user, and note the PC's IP address (`ipconfig`). On the phone, in Files tap the three dots, Connect to Server, enter `smb://<pc-ip>`, sign in as a registered user, and the share appears under Shared. Long-press the session folder, Copy, open the share, Paste. Use the 5 GHz network; the copy is thousands of small files.

Over USB: install Apple Devices from the Microsoft Store, plug the phone in, tap Trust on the phone, select the iPhone in Apple Devices, open Files, expand Igloo and drag session folders to the PC.

Delete a session from the phone only after `igloo validate` (step 9) has passed on the PC copy: in the app's Session review tap Delete, or delete the folder in Files. Deleting the app deletes every session still on the phone.

## 9. The PC pipeline

1. Install uv: open PowerShell and run `powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"`. Install Git for Windows if `git` is not available.
2. `git clone https://github.com/davidkelly-snoday/homescanner`, then `cd homescanner\pipeline` and `uv sync` (this installs Python 3.12 and every dependency).
3. `uv run igloo --help` lists the commands.
4. After every capture: `uv run igloo ingest D:\igloo-inbox\<session>` copies it into the project store, then `uv run igloo validate <session>` checks the files. Paste the full output to the implementer, even when it passes.
5. As they land: `uv run igloo apriltag`, `plan add`, `plan calibrate`, `align` and `inspect` (which serves a page at http://localhost:8000). Run `git pull` and `uv sync` before each session to pick up new commands.

Keep the project store outside the git checkout (for example `D:\igloo\projects`) and back it up to an external drive after each visit.

## 10. Printing markers

`uv run igloo markers --out markers.pdf` writes one marker per page, `IG-000` to `IG-059`. Print the first 20 pages first, on Letter or A4, at 100% or Actual size (never Fit to page). Laminate with matte pouches; glossy lamination causes glare that breaks detection. Check with a tape that the outer square measures 20.0 cm. Placement and record keeping follow `docs/markers.md`; the short version is two per room, on surfaces that survive the next phase, never moved, position written down.

## 11. Troubleshooting

| Symptom | Cause and fix |
|---|---|
| Enrollment pending for days | Normal in 2026. Check the Apple Developer app for an identity request; contact Apple Developer Support after 5 business days. Code work continues meanwhile. |
| Build log says "Cloud signing permission error" | The API key is not Admin. Generate a new key with the Admin role and replace all three `ASC_` secrets. |
| Workflow succeeded but no build in TestFlight | Apple processing delay. Wait up to an hour, then check App Store Connect, TestFlight, iOS builds for a processing or rejected state. |
| TestFlight asks about export compliance | Should not happen: the app sets `ITSAppUsesNonExemptEncryption` to false. If it does, answer No. |
| Build shows Expired in TestFlight | Builds last 90 days. Install a newer build or run the workflow again. |
| App Store Connect rejects the app name | Use `Igloo by snoday`; keep the bundle ID. |
| Phone cannot see the SMB share | Same Wi-Fi network, Windows file sharing on, password-protected sharing on, use the IP address not the PC name. |
| `igloo validate` fails | Paste the output to the implementer. Do not delete the session from the phone. |

## 12. Fallback capture if the app is not ready

If framing starts before Igloo is capture-ready, capture anyway with a free ARKit recorder plus the same markers and protocol; `igloo ingest` gets a converter for it later and nothing downstream changes.

- NeRFCapture: free on the App Store, updated May 2026; saves posed images plus LiDAR depth offline.
- Stray Scanner: RGB, depth, confidence, intrinsics and poses.
- Record3D: `.r3d` export, about $5 in-app unlock.

Place markers exactly as in `docs/markers.md`, record one room per session, and follow `docs/capture-protocol.md`: start at the door, slow sweeps at chest height, each wall square-on with a tape measure in frame, close stills of every box, pipe, gas line, header, blocking and duct, finish where you started. Copy the recordings to the PC after every visit.
