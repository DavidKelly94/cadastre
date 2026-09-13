# CLAUDE.md

Guidance for Claude Code when working in this repository.

The shared, tool-agnostic project instructions live in **@AGENTS.md** (project
overview, layout, build/test commands, commit and branching conventions, the
project-specific rules, security). Read that first; the notes below are
Claude-specific additions.

## Claude-specific notes

- **Dependencies do not install themselves here.** The `base` plugin's SessionStart
  hook detects manifests at the repository root only, and this repo has none: the
  Python project is `pipeline/pyproject.toml`. Run `uv sync --project pipeline`
  yourself when you need it.
- **Use the harness skills.** `/base:check` runs the deterministic gate,
  `/base:review` applies the same rubric CI's review uses, and `/base:ship` is the
  definition of done — no push until the gate and the self-review both pass. The
  gate picks up this repo's real commands from `.harness.yml`.
- **iOS work is a CI loop, not a local loop.** There is no Xcode here. Edit, push,
  read the failing job log via the GitHub tools, fix, push again. The Xcode project
  is generated on the runner from `ios/project.yml`; do not commit an `.xcodeproj`.
- **Local quality gates:** `pre-commit` runs ruff, gitleaks, shellcheck, actionlint
  and whitespace checks. Run `pre-commit run --all-files` before pushing if you
  changed many files.
- **Commit at milestones, open a PR per coherent change.** A module landing, a bug
  fixed, a doc corrected — each is a commit on the feature branch, verified locally,
  with a real message. The PR comes when the change is reviewable as one thing. Use
  judgement about the size: eleven PRs for one pipeline is as wrong as one PR for the
  whole app.
- **The rename is done.** The product is Cadastre; the old brand survives only in
  ADR-0015, the ADR index, and `docs/plan.md`'s historical decision table, where it
  is correct. `IG-NNN` strings in tests are deliberate negative fixtures — a marker
  ID that must *not* validate. Do not "fix" those.

## Where things live

- `AGENTS.md` — shared, cross-tool project instructions (source of truth).
- `docs/plan.md` — the approved plan, including scope and the 14-day schedule.
- `docs/implementation-guide.md` — build order, CI workflows, project and export
  configuration. Start here to write code.
- `docs/session-format.md` — the on-disk contract between the app and the pipeline.
- `docs/adr/` — architecture decision records, with the index in `README.md`.
- `docs/design/` — system, iOS app, pipeline and viewer design.
- `.harness.yml` — deviations from the shared harness defaults (CI stacks, extra
  gate commands, review instructions).
- `.claude/settings.json` — the Bash permission allowlist plus the marketplace and
  plugin enablement that installs the `base` plugin.
- `.github/workflows/` — the Claude callers and this repo's own CI. `claude.yml`
  carries a deliberate divergence from base's template; read its comment before
  touching it.
