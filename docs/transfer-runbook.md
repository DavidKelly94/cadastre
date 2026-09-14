# Transfer runbook

Moving this repository and `base` to the owner's personal GitHub account, then
making both private. Two phases on purpose: the transfer is cheap and can happen
immediately, while going private ends free macOS runner minutes and so waits until
the build sprint is done. The reasoning is in [ADR-0018](adr/0018-staged-private-and-runner-budget.md).

Do not interleave the phases. Each one ends in a working state.

## Before you start

- Know the destination account name. Several files hard-code the current owner and
  have to change in step 4.
- `base` moves too. The workflow callers in `.github/workflows/` reference its
  reusable workflows, so the two repositories have to end up under the same owner.
- A Claude session's GitHub access is scoped to the repository path it was started
  with. Transferring mid-session cuts it off until the new path is attached, so
  finish or pause any running work first.

## Phase 1 (DONE 2026-09-12): rename and transfer, both repositories stay public

Steps 1 to 4 are complete: both repositories were renamed and transferred to `DavidKelly94`, and the
owner references were repointed in the same change that added this note. Steps 5 to 7 remain for the
owner. The steps are kept below as the record of what was done.

1. **Rename this repository** to the product name (Settings, then the name field).
   GitHub redirects the old web and git URLs, so existing clones keep working. Still
   update any local clone: `git remote set-url origin <new-url>`.

2. **Transfer this repository** to the personal account (Settings, Danger Zone,
   Transfer ownership). Issues, pull requests, the wiki, stars and watchers move, and
   old URLs redirect.

3. **Transfer `base`** the same way. Its `v1` tag moves with it, which matters
   because every caller pins `@v1`.

4. **Repoint every reference to the old owner, in one commit.** Leaving the workflow
   ones stale breaks CI in a way that reads like a broken workflow rather than a
   wrong path. Run `git grep -n 'DavidKelly94'` and work the list; it is longer
   than just the workflows:

   | File | What to change |
   |---|---|
   | `.github/workflows/claude.yml` | the `uses:` line, and the owner named in the header comment |
   | `.github/workflows/claude-review.yml` | the `uses:` line |
   | `.github/workflows/dependabot-automerge.yml` | the `uses:` line |
   | `.github/workflows/main-triage.yml` | the `uses:` line |
   | `.claude/settings.json` | `extraKnownMarketplaces.snoday.source.repo` |
   | `.github/CODEOWNERS` | `* @DavidKelly94` |
   | `README.md` | the `base` slug in the Development section |
   | `docs/owner-setup.md` | three repository URLs, the `base` slug, and the `/plugin marketplace add` line |
   | `docs/transfer-runbook.md` | the example strings in this very table |

   **Leave two files alone.** `docs/plan.md` records the plan as approved on a date,
   and `docs/adr/0015-name-vividhome.md` is a superseded decision. Both are historical
   record, and rewriting them destroys the audit trail the ADRs exist to keep.

   Then confirm: `git grep -n 'DavidKelly94'` returns hits **only** in
   `docs/plan.md` and `docs/adr/`.

5. **Verify what the transfer kept.** Sources disagree about what survives, so check
   rather than assume:

   - [ ] The four App Store Connect secrets and `CLAUDE_CODE_OAUTH_TOKEN`
   - [ ] Actions enabled
   - [ ] The Claude GitHub App installed on the **new** account, with this repository
         added to the installation
   - [ ] Branch protection rules, which may need re-creating
   - [ ] Workflow run history is **not** transferred; that is expected

6. **Re-attach the new repository path** to a Claude session, then carry on with the
   sprint. macOS minutes are still free at this point.

7. **Create the Apple App ID and App Store Connect app record only once the name is
   final**, using `ai.<name>.app`. A bundle identifier is permanent once the app
   record exists, so this is the one step with no undo.

## Phase 2: go private. Only after TestFlight works and the app is capturing.

Order matters here. Steps 8 and 9 must both happen before step 10, or Actions can
stop without an obvious cause.

8. **Read the Actions usage page** and note what the sprint actually consumed in
   macOS minutes. That number decides Free plus a spending limit versus Pro. Do not
   guess: Free gives 200 macOS wall-clock minutes a month, Pro 300.

9. **Raise the Actions spending limit above $0.** The Free default is $0, which means
   Actions halts the moment the included minutes are gone rather than billing.

10. **Apply the deferred trim**: restrict `ios-check` to `pull_request` and
    `workflow_dispatch` instead of every push touching `ios/**`. This costs a
    per-push compile signal, which is worth paying for only now that minutes are
    billed.

11. **Make both repositories private.**

12. **Grant same-owner Actions access on `base`**: its Settings, then Actions, then
    General, then Access, set to "Accessible from repositories owned by the user".
    Equivalently `PUT /repos/<owner>/base/actions/permissions/access` with
    `access_level=user`. **Skip this and every caller fails with "workflow was not
    found"**, which looks like a broken workflow rather than a missing permission.

13. **Re-check required status checks.** Moving a private repository to a Free plan
    can remove access to protected branches. `dependabot-automerge` needs "Allow
    auto-merge" plus at least one required status check; without a required check it
    merges immediately instead of waiting for CI, which is worse than not having it.
    If checks are unavailable, disable that workflow.

14. **Prove it on a throwaway pull request** before trusting the private setup:

    - [ ] The reusable workflows resolve (no "workflow was not found")
    - [ ] `claude-review` posts a review
    - [ ] `@claude` answers a comment from a collaborator account
    - [ ] The author-association guard in `claude.yml` is still present

## If something breaks

| Symptom | Cause |
|---|---|
| "workflow was not found" on every caller | `base` is private without the same-owner Actions access grant (step 12), or a caller still points at the old owner (step 4) |
| Actions stopped running entirely | Included minutes exhausted with a $0 spending limit (step 9) |
| Claude workflows fail instantly | `CLAUDE_CODE_OAUTH_TOKEN` did not survive the transfer (step 5) |
| Dependabot PRs merge without CI | No required status check on the target branch (step 13) |
| `@claude` does nothing for a collaborator | The guard's `if:` expression is malformed; a bad expression evaluates false and silently disables the workflow |
