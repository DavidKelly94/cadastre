# ADR-0029: The PC is reached over the owner's tailnet, and the app sends captures to it

## Status

Accepted, 2026-10-02. Amends [ADR-0028](0028-results-return-to-the-app.md): replaces its decision 3 (LAN only, nothing written over the network). Its other decisions stand. Mechanics in `docs/design/return-path-design.md` §7, endpoints in `docs/session-format.md` §14.

## Context

ADR-0028 reached the PC on the home Wi-Fi only. The house being recorded is not where the PC is: the owner captures on site and wants captures to reach the PC, be processed, and the result to show on the phone, without a stop at the Files app and without being home. Framing, the first real test, starts in weeks.

A five-minute room is 300 to 800 MB (`session-format.md` §10), so the carrier must survive a dropped connection. The repository is public, so nothing may depend on the code being unread.

## Decision

1. **The PC is reached through the owner's own tailnet.** Phone and PC run Tailscale; the PC gets a stable name reachable from anywhere, visible only to the owner's enrolled devices, with no port forwarding and nothing on the public internet (<https://tailscale.com/kb/1151/what-is-tailscale>). `tailscale serve` gives it an HTTPS name and proxies to `vividhome serve` on localhost (<https://tailscale.com/kb/1312/serve>); that satisfies App Transport Security, since a tailnet address is not "local" to iOS. Tailscale Funnel, the public variant, is never used.
2. **The app sends captures.** `vividhome serve --lan` accepts uploads under `/upload/`, one file per request so an interrupted send resumes, into an inbox that `ingest` moves into the store and validates. Raw sessions stay immutable (rule 6): only `ingest` writes the store.
3. **A pairing code is the second lock.** The PC generates a random code, prints it, and every upload request carries it. The code is never in the repository.
4. **Reads stay as they were.** A reader on the tailnet or the home network changes nothing except through `/upload/`.

## Consequences

Positive: no Files step, at home either; a capture reaches the PC from the site over cellular, in pieces, and resumes; the rendering opens from anywhere while the PC is on.

Negative, carried knowingly: the PC must be on; gigabytes over cellular are slow and cost data, which the app says first; a Tailscale account, the owner's own; the home server gains a writable path, gated by the code; a Tailscale outage looks like a PC that is off.

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| A synced cloud folder (iCloud Drive, OneDrive) | ADR-0012's objections stand: slow, nondeterministic multi-gigabyte sync; iCloud for Windows is unreliable; the house's photos pass through a third party. |
| The owner's own bucket with the PC pulling | Works with the PC off, but the most code on both sides and a monthly cost; revisit if the PC cannot be kept reachable. |
| Port forwarding with dynamic DNS | Exposes the PC to the internet. |
| One zip per session | A dropped 800 MB upload starts over; iOS cannot resume an upload. |
