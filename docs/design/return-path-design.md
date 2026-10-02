# The return path: reviewing captures on the phone, and bringing the rendering back

Design for [ADR-0028](../adr/0028-results-return-to-the-app.md). Two things the app cannot do today and the owner asked for on 2026-09-30: show the photos a capture holds, labelled, and save them to the camera roll; and show the rendering the PC produces, with the PC allowed to do the work. The mechanics here are the implementer's and may change; the decision they serve is in the ADR.

## 1. Goals and non-goals

Goals: a capture is reviewable on the phone the moment it stops; a keyframe or still can be handed to anyone as a normal photo that says what it is; the plan with sessions on it — and later meshes and splats — is visible in the app whenever the PC is on and reachable (the home network at first, the owner's tailnet since §7); nothing is written to a raw session by any of this (rule 6 of `AGENTS.md`).

Non-goals for this design: sync when the PC is off (cached pages survive, nothing new arrives); a native 3D renderer in the app; AR relocalisation in a finished room (`system-design.md` §9 still owns that).

## 2. Photos on the phone

**Where.** A **Photos** screen reached from a row in Past captures and from Session review. It reads `frames.jsonl` and `stills.jsonl` directly (`VividHomeCore` has the readers; the ARKit layer never touches this), so it works offline and on any session on the phone, including ones already copied to the PC.

**What it shows.** A grid of keyframes at a stride (every 5th by default, like `inspect`; a stepper to 1) with every still, in time order, stills marked. Tapping opens the image full-screen with swipe to step. Each image carries a label built from the session and nothing else:

```
Our House · Main Floor · Kitchen · electrical, plumbing
2026-11-03 14:17 · keyframe 123 · 12.3 s
corner NE tapped here            (only when landmarks.jsonl has a tap at this i)
```

The last line is what makes "labelled" useful rather than decorative: `landmarks.jsonl` records the keyframe index `i` at which each tap happened, so the frame the owner was looking at when they tapped `corner NE` is findable from the label alone.

**Orientation.** Stored images are landscape sensor orientation regardless of how the phone was held (`session-format.md` §3). The viewer rotates *for display* from the pose: the camera's up axis is the second column of `T_wc`, and its horizontal component says which way the sensor's top was pointing; a phone held upright shows its keyframes upright. The file is never rotated and pixel coordinates in the JSON keep referring to the stored image.

**Save to camera roll.** Select one or many, then *Save to Photos*. Uses `PHPhotoLibrary` with add-only access (`NSPhotoLibraryAddUsageDescription` in `ios/project.yml`; the app never reads the library). No album: finding or creating one means reading the library, which add-only access rightly forbids and the app has no business doing; the label and the creation date are what make the copies findable. Each photo is written with:

- the original JPEG bytes unchanged, so what leaves the app is what the session holds;
- an EXIF orientation tag from the same pose reading, so the camera roll shows it upright;
- the label above in `ImageDescription` (TIFF) and IPTC `Caption/Abstract`, and `session_id`, `i` and the project slug in IPTC keywords, so a photo that comes back weeks later can be traced to its frame;
- the capture's wall-clock time as `DateTimeOriginal`, computed from `capture.started_at` plus `t`, so Photos files it on the day it was taken rather than the day it was saved.

An optional *with label* switch burns the two label lines into a strip along the bottom of a copy, for sending to someone whose app will strip the metadata. Off by default; the plain copy is the honest one.

Nothing here marks the session, deletes anything, or writes under the session folder. A camera-roll copy is a convenience, never the record.

## 3. The rendering, back in the app

**What comes back.** Whatever the PC has rendered for a project: today the `inspect/<level>.html` pages with the plan, the sessions on it and the photo links; later the `web/` viewer with meshes and splats (ADR-0011). All of it is static files under the store, which is what makes a web view the first form: the phone shows exactly what the browser on the PC shows, and the viewer is written once.

**PC side: `vividhome serve --lan`.** `serve.py` today binds `127.0.0.1` and accepts `POST /save` for the calibrate and align pages. With `--lan` it:

- binds every interface and prints the addresses it is reachable on;
- **refuses every POST**, because a writable endpoint on the home network is a way to put files on the owner's PC from any device on it; the calibrate and align pages stay a localhost thing;
- answers `GET /index.json` with what the store holds, so the app never has to guess file names (shape in §4);
- advertises itself over Bonjour as `_vividhome._tcp` with the store name as the instance, so the app finds it without an IP being typed (Python `zeroconf`, one new dependency; the Windows firewall prompt on first run is the owner's to accept);
- writes nothing, ever.

Serving the raw `sessions/` tree as well is what lets the inspect page's photo links work from the phone. It is the same data the phone wrote, so nothing new is exposed, but it is exposed to the LAN, which the ADR carries knowingly.

**App side.** A **PC** entry on the project screen: a discovered list (Bonjour) or a typed address, *Test* which fetches `/index.json` and shows what it found and when it was last generated, and one remembered choice. Info.plist gains `NSLocalNetworkUsageDescription` and `NSBonjourServices: [_vividhome._tcp]`, without which iOS 14+ silently blocks both discovery and the fetch, and `NSAppTransportSecurity` with `NSAllowsLocalNetworking`, without which App Transport Security refuses plain HTTP to the PC even on the LAN. The project screen then offers *Rendering* per level when the index lists a page for it, opening a `WKWebView` on `http://<pc>:8765/inspect/<level>.html`. The page's own JavaScript already does hover, click, step and Escape; on the phone hover does not exist, so the page needs a tap-to-preview path before this ships — a small change to `inspector.py`, not to the app.

**What the PC has.** The same index answers the question Past captures could not: which captures are already on the PC. A session listed with `validated: true` gets an *on the PC* mark, one listed without it is said to be *on the PC, unchecked*, and a button offers to delete exactly the validated ones from the phone, with the PC's store name and the time it answered underneath. This is the PC's own word rather than a mark the phone made when a share sheet closed, which is why it waited for the index to exist. Nothing is ever deleted on the PC.

**Freshness.** The web view keeps its cache, so a page opened once stays openable with the PC off, showing what it showed then. The app shows the index's `generated_at` next to the level so the owner knows how old the picture is. A downloaded per-level bundle for real offline use is a later step and is why the index lists files rather than only pages.

## 4. The contract, drafted

To be added to `docs/session-format.md` as section 14 when the first side lands, additive, `format_version` unchanged (ADR-0021). Draft of `GET /index.json`:

```json
{
  "vividhome": "0.1.0",
  "generated_at": "2026-09-30T18:04:11Z",
  "store": "vividhome-data",
  "projects": [
    {
      "slug": "our-house",
      "levels": [
        { "level": "main", "plan": "plans/main.png", "calibrated": true,
          "inspect": "inspect/main.html", "sessions": ["20261103-141502_main_kitchen_k3x7qa"] }
      ],
      "sessions": [
        { "session_id": "20261103-141502_main_kitchen_k3x7qa", "path": "sessions/our-house/20261103-141502_main_kitchen_k3x7qa",
          "aligned": true, "validated": true }
      ]
    }
  ]
}
```

Paths are relative to the server root, which is the store. Readers ignore unknown fields (§12). The app treats every value as data from a machine it trusts because it is on its network, and never as an instruction.

## 5. Sequencing

1. **PC side first**, because it is the half that can be tested here: `serve --lan`, the POST refusal, `/index.json`, Bonjour. Pipeline tests cover the refusal and the index; Bonjour is checked by hand on the owner's network.
2. **Photos on the phone and the camera roll**, in the app, on the TestFlight branch. Pure reading and one system framework; the core package gets the label builder and the orientation reading, tested on Linux.
3. **PC settings and the web view**, in the app, plus the tap-to-preview change to `inspector.py`.
4. **Sending captures, and the PC away from home** ([ADR-0029](../adr/0029-the-pc-is-reached-over-the-owners-tailnet.md)), §7: the PC side first, then the app.
5. Later: per-level offline bundles; the `web/` viewer served the same way.

## 6. Risks

- **Plaintext on the LAN.** Anyone on the home network can read the store while `--lan` is on. Accepted for a home network and a test path; `serve` prints a reminder and `--lan` is never the default.
- **Discovery.** Windows firewall prompts, guest networks that isolate clients, and phones on cellular all look like "the PC is off". The Test button has to say which.
- **Labels that lie.** A label is only as good as the manifest; a session recorded under the wrong room carries that room into every saved photo. Not a new problem, but the camera roll makes it travel further.
- **Hover-only pages.** The inspect page assumes a mouse. Step 3 does not ship until the tap path exists.
- **The pairing code.** Anyone holding it, with a route to the PC, can put files in the inbox and nothing more: the store is written only by `ingest`, which validates; paths are two plain segments; `derived/` is refused; a session already in the store is refused. Rotating it is deleting `.pairing-code` and running `serve --lan` again.
- **Tailscale down, the PC asleep, the laptop lid closed** all look like "the PC is off" from the phone. The Test text names the address it tried so the owner knows which network it is on.
- **Cellular.** A visit is gigabytes. The app says the size and asks before sending on an expensive path, and a send that stops resumes from what the inbox already holds.

## 7. Sending captures, and the PC away from home

Design for [ADR-0029](../adr/0029-the-pc-is-reached-over-the-owners-tailnet.md), 2026-10-02. The owner captures on site and is not on the home network; the captures have to reach the PC, be processed, and the result come back to the phone, with no stop at the Files app.

**Reach.** Phone and PC are on the owner's tailnet. On the PC, `tailscale serve --bg 8765` publishes `https://<pc>.<tailnet>.ts.net` and proxies it to `http://127.0.0.1:8765`, with a certificate Tailscale issues (<https://tailscale.com/kb/1312/serve>). The app therefore needs no App Transport Security exception beyond the existing `NSAllowsLocalNetworking`: a tailnet address is not local to iOS, and plain HTTP to it would be refused. The owner types that name in PC settings; Bonjour cannot see across a tailnet and does not try. `PCAddress` defaults to port 443 for `https` and 8765 for `http`. Behind the proxy the PC runs `vividhome serve --lan`, never plain `serve`: the localhost mode's `POST /save` has no authentication and must not be the thing the proxy fronts. At home the LAN address works as before; the tailnet address works there too.

**Upload, PC side.** `serve.py` answers `/upload/` (section 14 of the format) in either mode when the store has a pairing code. The code is `<store>/.pairing-code`: 16 hex characters from `secrets`, created by `serve --lan` on first run, printed on every run as four groups of four. Every upload request carries it as a bearer token, compared in constant time; no code on disk means 403 for all of `/upload/`. One file per `PUT`, into `<store>/.inbox/<session-id>/<session-id>/<path>` or `.inbox/<session-id>/plans/<file>`, written to a temporary name and renamed, so the inbox never holds a half-written file under its final name. `done` hands `.inbox/<session-id>` to `ingest` as a project folder: the session **moves** into `sessions/<project>/<id>` (the manifest's project), `validate` runs, plans beside it are imported for the levels the store lacks, and the inbox folder goes. A session that fails validation is kept, with `validated: false`, so the index says *on the PC, unchecked* and the owner decides at the PC, where the report is. The index never lists the inbox.

**Upload, app side.** Captures gains *Send to the PC*: in the list, every capture the PC does not hold; in a capture's detail, that one. The uploader lists the session's files (everything under its folder; the app never has a `derived/`) and the project's `plans/` files, asks `GET /upload/<id>` for what the inbox already holds, skips files whose size matches, `PUT`s the rest three at a time, then `POST`s `done` and refreshes the index. Progress is bytes sent over bytes to send. A failed request is retried twice; then the send stops with the reason, and the next send resumes from the listing. On an expensive path (`NWPathMonitor`, cellular or a hotspot) the sheet says the size and asks first. The screen stays on during a send; backgrounding the app pauses it, and the resume covers that. The core package holds the file listing and the remaining-work calculation (`SessionUpload`), tested on Linux; the app holds `URLSession`. The pairing code lives in the Keychain.

**What stays true.** The app never deletes anything on the PC. Deleting from the phone still follows the index's word, which the `done` answer updates at once. Raw sessions are immutable on both sides: the inbox is staging, and `ingest` is still the only writer of the store.
