# Operating VividHome: from a capture to the rendering

The owner's runbook. Everything here was done once on real hardware on
2026-10-02 (iPhone, Windows PC, home Wi-Fi), and every place the owner
stumbled that day is written down here so it does not happen twice. Setup that
happens once (Apple account, TestFlight, installing uv) is in
[owner-setup.md](owner-setup.md); this is what you do every visit.

**PowerShell rules.** One command per line. PowerShell 5 does not accept `&&`.
Paths with spaces go in quotes. Anything in angle brackets is a placeholder you
replace; nothing below is meant to be typed with the brackets.

## 0. Before the first visit, once

1. Install uv and Git (owner-setup §9), clone the repository, and in
   `cadastre\pipeline` run `uv sync`.
2. Pick a folder for the project store, outside the git checkout, for example
   `C:\Users\<you>\vividhome-data`. Every command takes it as `--store`. It is
   created on first use and holds everything the PC produces; back it up.
3. To pick up new pipeline code later: in `cadastre\pipeline`, `git pull` then
   `uv sync`.

## 1. Two PowerShell windows

The PC runs **a server the phone talks to**, which stays running, and **commands
you type**, which come and go. Use two windows so the server is never in the
way. In both, start the same way:

```
cd "C:\Users\<you>\claude projects\cadastre\pipeline"
$store = "C:\Users\<you>\vividhome-data"
```

`$store` is a PowerShell variable; the commands below say `--store $store` and
PowerShell fills it in. Set it again in every new window.

### Window A: the server

```
uv run vividhome --store $store serve --lan
```

It prints:

- the address the phone uses, `http://192.168.x.x:8765/`;
- the **pairing code**, four groups of four characters. The phone needs it
  once. It is kept in `<store>\.pairing-code`; delete that file and restart the
  server to issue a new one. Do not paste it into chats or commits;
- `advertised as <store> (_vividhome._tcp.local)`, which is how the app finds
  the PC by itself.

It also does the PC's share of the work as captures arrive: each one is
ingested and validated when the phone finishes sending it, and a capture that
arrives placed (the HUD said *placed* when you stopped) redraws its level's
page, so **Rendering on the PC** on the phone is current without a command
being typed here. The window prints a line per arrival saying what happened.

Leave this window alone. The first time, Windows asks whether to allow Python
through the firewall: allow it on **private** networks. Ctrl+C stops the server;
start it again the same way whenever the phone needs the PC.

### Window B: the commands

Everything from section 4 on runs here. The click pages (calibrate, align)
open a browser from this window; if the server's port is taken they pick
another and print the address, so there is nothing to configure.

## 2. Pair the phone, once

1. Phone on the home Wi-Fi.
2. iPhone Settings, Privacy & Security, Local Network: **VividHome on**. iOS
   reports a denied local connection as "offline" even with Wi-Fi connected,
   and the app finds no PC until this is on.
3. In the app, on the project screen, tap the monitor icon (PC). Under *Found on
   this network* tap the PC, or type the `192.168.x.x` address Window A
   printed. Type the pairing code. Tap **Test**.
4. Expect two green lines: the store's contents, and *Pairing code accepted;
   captures can be sent*. Anything red says what to fix.

## 3. After a visit: send the captures

1. Window A running, phone on the home Wi-Fi.
2. In the app: Captures, then **Send N captures to the PC**, then **Send**. One
   capture at a time is the same button inside the capture. On cellular the
   sheet says the size first and asks.
3. Each row ends *On the PC and validated.* The plan you imported in the app
   goes across with the first capture, and the row says so. Window A prints one
   line per capture: `received <session-id>: validated -> sessions/...`.
4. A send that drops resumes where it stopped: tap Send again.
5. Tap Done. Captures now show the green **on the PC** chip, and the top of the
   list offers to delete exactly those from the phone. Delete only what is
   marked.

## 4. Calibrate the plan, once per level

The drawing needs a scale and an origin before captures can be placed on it. Do it **on the phone**, in the room, with nothing else running:

1. Project screen, tap the plan card, then **Scale** at the top left.
2. Tap one end of a printed dimension line, then drag the ring under the loupe until the crosshair sits on the tick. Pinch to zoom first if the ticks are small.
3. The other end of the same dimension line, the same way.
4. The house origin: a point you can identify precisely that exists in the built house, such as the outside corner of the foundation at the bottom-left. Use the same point for every level.
5. Type the printed length as written, `25' 0"` or `11'-6 1/2"` or `7.62m`. The line under the fields turns into the scale and the drawing's width in metres; a house is tens of metres across. Save.

The scale travels to the PC with the next capture you send, and the PC adopts it. Or do it on the PC instead:

```
uv run vividhome --store $store plan calibrate --level level-1 --web
```

`--level` is the level's slug: the app's level name in lowercase with dashes,
so *Level 1* is `level-1`. The receipt on the phone said it: "plan for level-1
imported".

A browser opens on the plan (if not, open the address printed). Three clicks:

1. **One end of a printed dimension.** Pick the longest dimension line you can
   read with confidence, such as the house's overall width. Click the tick or
   arrowhead at one end.
2. **The other end** of the same dimension line.
3. **The house origin.** Any point you can identify precisely that exists in
   the built house, such as the outside corner of the foundation at the
   bottom-left. Use the same point for every level.

Type the printed length exactly as written, for example `25' 0"` or `3.81m`.
Leave rotation at 0 and floor height at 0 for the first level. Zoom the browser
with Ctrl and the scroll wheel before clicking; the clicks stay accurate at any
zoom. *Start the clicks again* resets. Then **Save calibration**.

The terminal prints the scale, for example `20.2 mm per pixel`. Sanity check:
a house about 30 m across in an image about 1,500 pixels wide is around 20 mm
per pixel. If the number is wildly different, the two dimension clicks were not
on the same line.

## 4b. Outline the rooms, once per room, at home

The capture will ask you to tap each corner of the room by name, and place the capture on the plan before you leave. For that it needs to know where the corners are on the drawing. On the phone: project screen, the plan card, then the row of rooms under *Outline the corners*. Tap a room, tap its inside corners in order around the room, drag any under the loupe, Save. The footer names them: NW, NE, SE, SW. Three corners minimum; an L-shaped room has six.

Do this at home with the plan in front of you. A room without an outline still captures, unguided, and is placed on the PC afterwards.

## 4c. In the room: corners, stills, and the check before you leave

With the room outlined, the capture guides itself (ADR-0031). On the HUD:

- **Corners.** The chips above the buttons name the next corner to tap, in
  order around the room. Stand at it and tap the floor where the walls meet.
  The mark slides to where the mesh says the walls meet and the banner says by
  how many centimetres; if it slid somewhere wrong, tap the mark and *Unsnap*.
  *Skip* parks a corner you cannot reach; tap a chip out of order if that is
  where you stand. After two corners the FIT readout shows the residual and
  the line under the strip says *Placed on the plan, 6 cm*, *Check the
  corners* or *Not placed*; a third corner tightens it.
- **The inset.** The small plan under the marker strip shows the room, the
  corners ticked, your walk once the capture is placed, and each wall shading
  grey, amber, green as you photograph it. The chevron folds it away.
- **Stills.** The STILLS chips are the trades' required stills from
  `capture-protocol.md` §4. Tap a chip to take the still for that item; it
  ticks once the file is written. The camera button takes a still with no
  label, which ticks nothing.
- **Stop** opens the review screen with three lines at the top: the placement,
  the walls photographed with the worst gap in metres from a named corner, and
  the stills taken against the list. Green is done; orange says what to
  re-shoot while the wall is still open. *Capture more* starts a short second
  capture of the same room and trades, which starts with the first capture's
  walls already shaded and its stills already ticked, so you only fill the
  gaps. Both captures are sent and kept.

## 5. Align each capture to the plan

If the room was outlined (§4b), the capture placed itself: during capture the HUD asked for each corner by name, showed the fit in centimetres, and wrote the placement beside the plans when you stopped. The review screen says *Placed on the plan, 6 cm*. The next send carries it, the PC adopts it, and this step is done; `vividhome align` on the PC only redoes one deliberately.

A capture made without an outline can be placed on the phone afterwards: Captures → the capture → *Place on the plan*. Its landmarks appear as chips; tap a chip, then where that landmark is on the drawing, two pairs minimum, and *Place* when the fit line is green or amber. The same screen adjusts a placement later.

Or align it on the PC. Find the capture's id. It is the folder name under the project:

```
Get-ChildItem $store\sessions -Recurse -Depth 1 -Directory | Select-Object -ExpandProperty Name
```

The id starts with the date and time, like `20260915-152407_level-1_bedroom_2hhv3k`.
Copy it whole into the command:

```
uv run vividhome --store $store align <session-id> --level level-1 --web
```

The page shows the plan on the left and the capture on the right: the grey
line is where you walked, the blue dots are the corners you tapped, labelled.
Click a dot, then click where that corner is on the plan, at the inside corner
of the room's walls. Two pairs is the minimum; three or four lets the solver
say how well they agree. *Undo last* takes back a mistake. Then **Solve and
save**.

The terminal prints the residual, the average disagreement between the tapped
corners and the clicked ones, in metres. Under about 0.1 m is good. If it is
above 0.3 m the command refuses to write the alignment: the usual cause is a
pair matched to the wrong corner, so run it again and check each pair against
the walk. `--force` writes it anyway; use that only when you know the capture
is not of this plan, such as a test room in a different house.

## 6. Render, and look on the phone

A capture that arrived placed has already been drawn: Window A prints
`rendered inspect/level-1.html` a minute or so after `received`. `align` on
the PC (§5) redraws the page itself when it writes. So this command is only
for a page that is missing or stale, which is the case for captures copied in
by hand:

```
uv run vividhome --store $store inspect --level level-1
```

The first run generates thumbnails and takes a minute.

On the phone: project screen, **Rendering on the PC**. If the row is not there,
open PC, tap Test, and go back. The page shows the plan with the walk, the
corners and a dot per photo; tap a dot to open the photo, swipe to step. A
page opened once stays openable with the PC off; the footer says when the PC
made it.

## 7. The whole visit, in order

| Where | What |
|---|---|
| Window A | `serve --lan` running |
| Phone | Captures, Send N captures to the PC |
| Phone, once per level | Plan card, Scale: three points and the printed distance (or `plan calibrate --level <level> --web` in Window B) |
| Phone, once per room | Plan card, the room under *Outline the corners*: tap its corners in order |
| Phone, during capture | Tap each corner the HUD names; take the stills the chips ask for; stop when it says *placed* and the lines are green, or *Capture more* to fill the gaps |
| Phone, for a capture made without an outline | Captures, the capture, *Place on the plan* |
| Window A, by itself | `received <capture>` as each send lands, then `rendered inspect/<level>.html` for a placed one |
| Window B, only for a capture that was not placed | `align <session-id> --level <level> --web` (draws the page too) |
| Phone | Rendering on the PC |
| Phone, when done | Delete the captures the PC has validated |

## 8. Away from home

Phone and PC on your own tailnet make the PC reachable from anywhere, with
nothing opened to the internet ([ADR-0029](adr/0029-the-pc-is-reached-over-the-owners-tailnet.md)).

1. Install Tailscale on the PC and the phone and sign in with the same account
   (<https://tailscale.com/kb/1017/install>).
2. In the Tailscale admin console, enable HTTPS certificates for the tailnet
   (<https://tailscale.com/kb/1153/enabling-https>).
3. On the PC, once: `tailscale serve --bg 8765`. It prints the PC's name,
   `https://<pc>.<tailnet>.ts.net`, and forwards it to Window A's server. Never
   use `tailscale funnel`, which is the public version.
4. In the app, PC: type that `https://` name as the address. Test, then send as
   usual. The PC must be on and Window A running; Tailscale down looks the same
   as the PC off.

A visit is gigabytes, so send over Wi-Fi where you can; a send that stops
resumes.

## 9. When something goes wrong

| What you see | What it is and what to do |
|---|---|
| `The token '&&' is not a valid statement separator` | PowerShell 5. Run the two commands on two lines. |
| The app: *iOS is not letting this app reach the local network* | iPhone Settings, Privacy & Security, Local Network, VividHome on. |
| The app: *Nothing answered at that address* | Window A not running, phone not on the home Wi-Fi, or Windows Firewall blocked Python: Windows Security, Firewall & network protection, Allow an app through firewall, tick Private for the Python under `pipeline\.venv`. |
| The app: *The PC refused this pairing code* | Retype it from Window A. Dashes and capitals do not matter; a wrong character does. |
| `is not a session directory or an id` | The id was typed with a placeholder or a typo. List the folders (section 5) and copy the name whole. |
| `residual ... is above 0.3 m` | A corner paired with the wrong corner, or the capture is not of this plan. Section 5. |
| Calibrate or align page takes no clicks | The page is from before 2026-10-02. `git pull`, `uv sync`, run the command again. |
| `received <id>: kept, validation failed` | The capture landed but has a problem the terminal lists. The phone shows it as *on the PC, unchecked* and keeps it. Send the lines to the implementer. |
| Window A prints `169.254.x.x` addresses | Virtual adapters; ignore them, use the `192.168.x.x` one. Pipelines from 2026-10-02 on leave them out. |
