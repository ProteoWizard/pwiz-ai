---
name: version-control
description: ALWAYS load before git commit, push, or PR - team-specific commit format differs from standard conventions.
---

# Version Control for Skyline/ProteoWizard

Before any Git or GitHub operation, read the relevant documentation:

## Required Reading

- **ai/docs/version-control-guide.md** - Commit message format, PR format, branch naming
- **ai/docs/release-cycle-guide.md** - Current release phase, cherry-pick policy
- **ai/WORKFLOW.md** - Git workflows, TODO system, branch lifecycle

## Pre-Commit Gate: Build and Test

**NEVER commit code that has not been built and tested.** This is a hard gate.

Before staging and committing, verify:
1. The code compiles without errors
2. Relevant tests pass

If the LLM has not built/tested the code itself, ask the developer: "Has this been built and tested since the last change?" Do not skip this step even for small fixes - even a small change can introduce a build error or break a test.

## Module Tagging — every pwiz PR

`ProteoWizard/pwiz` carries three streams of work. Every PR belongs to exactly
one, recorded **twice**:

| Module | Covers |
|--------|--------|
| `skyline` | Skyline app and everything shipped/tested with it (`pwiz_tools/Skyline`, `Test*/`, SkylineTester/Nightly) |
| `pwiz` | ProteoWizard core: msconvert, C++ libraries, vendor readers, BiblioSpec, build system |
| `osprey` | Osprey / OspreySharp (`pwiz_tools/Osprey`) |

Same three strings as the GitHub Issue labels — module, label, and prefix are
one token, no mapping table.

1. **Label the PR** with the module (`gh pr create --label skyline`, or
   `gh pr edit <N> --add-label skyline` after the fact).
2. **Prefix the title AND the squash-merge subject**:

```
<module>: <Title in past tense> (#NNNN)
```

```
skyline: Fixed TestDiaToSrmTutorial failing in Japanese (#4483)
osprey: Made the OspreySharp protein razor rollup deterministic (#4442)
pwiz: Warned on unrecognized rows during --import-peak-boundaries (#4440)
```

**Both, because git history has no labels.** After squash-merge the label lives
only on the PR — `git log --oneline`, `git blame`, and the release-notes pass
see nothing but the subject. Lowercase, exact label token, colon, one space.
The past-tense verb still leads the title; the prefix is not part of the
sentence.

**Where required**: PR title, squash-merge subject, cherry-pick PR title (which
inherits the original's module). **Optional**: intermediate branch commits —
squash-merge discards them. **Never**: `pwiz-ai` (`ai/`) commits — that repo is
one module and has no module labels.

**Choosing it**: from the issue's label when there is an issue; otherwise from
the paths touched. Spanning two modules → the **primary** one (where the intent
lives, not where the most lines moved); exactly one prefix on the title.

**Carry it in the TODO** so it survives compaction — `- **Module**: `skyline``
in Branch Information. Commands that open a PR or write a squash subject read
that field instead of re-deriving from the diff.

**One prefix, not two.** The legacy sub-area prefixes (`OspreySharp:`,
`msconvert:`, `ColorGrid:`, `Volcano plot:`) are retired — put the sub-area in
the prose: `osprey: Made the OspreySharp protein razor rollup deterministic`,
not `osprey: OspreySharp: Made the protein razor rollup deterministic`.

**Branch naming is unaffected** — `Skyline/work/...` is a repo namespace that
TeamCity keys off, not a module marker. Osprey and pwiz work use it too.

## Commit Message Format

```
<Title in past tense>

* bullet point 1
* bullet point 2

Reported by <First>.

See ai/todos/active/TODO-YYYYMMDD_feature.md

Co-Authored-By: Claude <noreply@anthropic.com>
```

**Rules:**
- Past tense title ("Added feature" not "Add feature")
- Bullet points use `* ` prefix (not `-`)
- `Reported by <First>.` (or `Requested by <First>.`) when the change came from a user report/request — see "Crediting reporters" below
- TODO reference required for feature branches
- Co-Authored-By required when LLM contributed
- Maximum 10 lines total
- No emojis, no markdown links

**pwiz-ai repository (ai/)**: Omit TODO reference for documentation-only changes

## Amending Commits

**Nearly all PRs get squash-merged**, so multiple commits on a branch are fine.

**NEVER amend after a PR has been reviewed.** When addressing review feedback (from humans or Copilot), always create a NEW commit. This preserves the review history and makes it easy to see what changed in response to feedback. A commit message like "Addressed Copilot review suggestions" or "Fixed issues from code review" is appropriate.

**When amending is acceptable:**
- Immediately after creating a PR, before any review or interaction
- Local commits not yet pushed

**When amending is NOT acceptable:**
- After a PR has been reviewed (even if just by Copilot)
- After anyone has clicked "Update branch" on GitHub
- After any merge commits from master

The commits will be squashed on merge anyway, so there is no cost to having multiple commits.

## Committing to pwiz-ai (ai/) — Rebase, Never Merge

Changes under `ai/` commit **directly to pwiz-ai master** (no PR, no feature branch).
There is no squash-merge to clean up history later, so the master history must stay
linear — **never create a merge commit on pwiz-ai master.**

When `git push` is rejected because the remote advanced (another machine pushed first),
**rebase your local commits onto the new remote tip — do not `git pull` (merge).**
pwiz-ai changes are almost always small and most machines keep pwiz-ai fairly
up-to-date, so a rejected push is typically only a commit or two out of sync and
rebases cleanly:

```bash
cd /c/proj/ai
git pull --rebase origin master   # replay your commits on top of remote; no merge commit
git push origin master
```

Note this overrides the machine's global `pull.rebase false` setting (which is correct
for pwiz feature branches) by passing `--rebase` explicitly for pwiz-ai work.

If the rebase hits a conflict (rare for `ai/`), resolve it, `git rebase --continue`,
then push. Do not fall back to a merge to avoid the conflict.

## PR Description Format

Title and label carry the module — see "Module Tagging" above:

```bash
gh pr create --title "skyline: Fixed ..." --label skyline --body "..."
```

```
## Summary

* bullet point 1
* bullet point 2

Reported by <First>.

Fixes #XXXX

## Test plan

- [x] TestName - description

Co-Authored-By: Claude <noreply@anthropic.com>
```

**Rules:**
- Title prefixed with the module; matching module label applied
- Use `Co-Authored-By: Claude <noreply@anthropic.com>` at the end (not emoji "Generated with" lines)
- Bullet points use `* ` prefix in Summary
- Test plan uses `- [x]` checkboxes
- No emojis

## Crediting reporters

When a change came from a report or request **from outside the development team**,
credit the originator by **first
name only** in both the commit message and the PR description: `Reported by
<First>.` / `Requested by <First>.` on its own line (it feeds the release notes).

**Do NOT add the line for the PR's own author, or for a developer of the project
being changed** — a developer asking for work on code they develop is ordinary
planning, not an outside request. This is role-scoped: the same person can be an
outside requester on one project and a developer on another (e.g. Mike requests
features for Skyline, but is a primary Osprey developer — no credit line on
Osprey changes). When in doubt, leave it out.

Full rules — placement, looking the name up from a support thread, the Brendan
exception — in ai/docs/version-control-guide.md ("Crediting Reporters and
Requesters").

## Review chain: review BEFORE opening the PR

**`/code-review <level>` is the AI review gate.** It replaced the retired
`pw-self-review` (2026-07-25), which existed only because an early session
claimed it could not give an unbiased review of its own code. `/code-review`
is the native, maintained answer to that, and it gains capability upstream
without us maintaining prose.

**Run it on the branch BEFORE `gh pr create`.** It diffs `master...HEAD`, so
it needs no PR to exist. Reviewing first is cheaper for three reasons:

- **Copilot auto-reviews on PR open.** Observed on #4460: PR created
  14:44:23, Copilot review submitted 14:46:57, unrequested. Opening first
  spends that billed pass on code you are about to rewrite.
- **Every push re-runs CI.** Fixing review findings after opening costs
  extra TeamCity rounds on states obsolete within the hour. #4460 cost three.
- Copilot then reviews already-hardened code and has less left to find.

For **Osprey** there is no counter-argument: the expensive Perf/Regression
config is manual/overnight and does NOT start on PR open, so opening early
overlaps nothing. (For a Skyline PR that does auto-start something long,
weigh that overlap against the wasted Copilot pass.)

1. **`/code-review <level>`** on the branch, before the PR exists. Fold the
   fixes into the commits that will open the PR.
   - **VERIFY every finding before acting.** It can be confidently wrong:
     on #4460, 1 of 9 findings claimed a codec field swap would leave every
     test green, but `TestEncodeMatchesRustByteLayout` pins each field to a
     distinct offset with a distinct literal and does fail. Reproduce or
     refute each finding against the code. Pushing back with the reason is
     a legitimate outcome; auto-applying is not.
   - **Default to `max` for code changes.** The effort levels
     (`low` / `medium` / `high` / `xhigh` / `max`) all run locally on the
     Max subscription with NO extra billing, so use the highest effort the
     change warrants. `max` is the ceiling. Drop to a lower level only for
     genuinely trivial diffs - comment, doc, or rename-only changes - where
     the wall time is the only thing being spent. For reference, `xhigh` on
     #4460 took ~10.5 min and ~138k tokens.
2. **Open the PR** once the branch is green (build + tests + inspection)
   and the findings are settled. Copilot reviews automatically; use
   **`/pw-respond <PR#>`** to address and resolve its threads.

**Do NOT use `/code-review ultra` (aka the deprecated `/ultrareview`) on
this project.** It is a different animal from the effort levels above: a
**billed** multi-agent **cloud** review, and pwiz is too large for it.
Brendan's attempts repeatedly ran ~30 minutes, timed out, and returned
nothing useful while still incurring cost. `max` is both free under the
subscription and actually completes here, so there is no case for ultra on
pwiz.

**The AI reviews do not stack.** Copilot plus `/code-review` is already two
independent passes; do not add a third by rote.

Request human review only after the findings are settled and TeamCity is
green.

## Branch Naming

`Skyline/work/YYYYMMDD_feature_name`

## Cherry-Pick to Release

When in FEATURE COMPLETE or patch mode, bug fix PRs should be cherry-picked to the release branch:

1. Check current release phase in `ai/docs/release-cycle-guide.md`
2. If fixing a bug during FEATURE COMPLETE: add label `Cherry pick to release`
   (this is orthogonal to the module label — the PR carries both)
3. The cherry-pick happens automatically after PR merge

A manual cherry-pick PR (`/pw-cptorelease`) **inherits the original's module** —
label and prefix: `skyline: Cherry-pick: Fixed ...`

**Current release branch**: `Skyline/skyline_26_1` (check release-cycle-guide.md for updates)

## Commands

Use `/pw-pcommit` or `/pw-pcommitfull` for guided commits.

See ai/docs/version-control-guide.md for complete specification.
