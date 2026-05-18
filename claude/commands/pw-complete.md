---
description: Finalize a merged PR — write final TODO, move to completed, sync local master, delete the work branch
args: pr-number (optional)
---

# Complete a (Merged or Mergeable) PR

End-of-branch ritual for a PR that is either already merged or ready
to be merged. The user is telling you the work is done — your job is
to merge it (only if asked), leave a clean record in
`ai/todos/completed/`, and sync the local checkout so the work
branch is gone and `master` is the merged state.

The default behavior is **non-destructive**: if the PR isn't merged,
you stop and offer to squash-merge it. The user explicitly approves
the squash subject + body before any merge happens, and the local
branch is never deleted until the merge commit is confirmed to be an
ancestor of the freshly-pulled local master.

## Arguments

`$ARGUMENTS` (optional) = PR number. Omit to resolve from the current
pwiz branch via `gh pr view --json number`.

## Step 1 — Identify PR and TODO

Run these together:

```bash
git -C C:/proj/pwiz branch --show-current
gh pr view $ARGUMENTS --json number,url,headRefName,baseRefName,title,state,mergeCommit,mergedAt
ls C:/proj/ai/todos/active/ | grep -i "$(date +%Y)"   # narrow the list
```

From the gh output capture:
- **PR number** and **URL** (for the TODO note)
- **headRefName** (must match the local branch) — proves you're completing the right branch
- **state** — must be `MERGED`; if `OPEN` or `CLOSED`-not-merged, STOP and tell the user
- **mergeCommit.oid** — the SHA on `master` that carries the squashed work (this is what we'll verify after `git pull`)

Resolve the TODO file by reading branch name → date + slug. The TODO
filename pattern is `TODO-YYYYMMDD_<slug>.md` where the slug matches
the branch's `Skyline/work/YYYYMMDD_<slug>`. If multiple candidates
exist, ask the user which one. If none, check
`ai/todos/completed/` — the TODO may already be moved (someone ran
this workflow partially) — and skip Step 3's move.

State-driven branching for the rest of this command:

| `state`              | Next step                                       |
| -------------------- | ----------------------------------------------- |
| `MERGED`             | Skip Step 1b; go to Step 2 (Final TODO write)   |
| `OPEN`               | Step 1b (offer to squash-merge), then continue  |
| `CLOSED` (not merged)| **STOP** — surface the closure to the user      |

## Step 1b — Merge if still open

Skip this step entirely when the PR is already `MERGED`.

When the PR is `OPEN`, the command's job is to *propose* a squash
merge that follows the team's commit-message format, not to merge
silently. The user approves the exact subject + body before the merge
happens.

### 1b.1 — Check the gate

```bash
gh pr view <N> --json statusCheckRollup,mergeable,reviewDecision \
  --jq '{checks: [.statusCheckRollup[] | {name, status, conclusion}],
         mergeable, reviewDecision}'
```

If `mergeable != "MERGEABLE"`, or any required check is `FAILURE`,
**STOP** and report — manual intervention is needed (fix the conflict
or the failing check). Pending checks are fine to merge over only if
the user explicitly says so; otherwise either wait or pass `--auto` in
Step 1b.3 so GitHub merges when the gate clears.

### 1b.2 — Draft the squash message

The squash commit replaces the per-commit history on the branch with
a single commit on `master`. That commit must follow the team
standard from `ai/docs/version-control-guide.md`:

```
<Title line in past tense> (#NNNN)

* <bullet point 1>
* <bullet point 2>
* <bullet point 3>

See ai/todos/active/TODO-YYYYMMDD_feature_name.md

Co-Authored-By: Claude <noreply@anthropic.com>
```

Format rules (also in `version-control-guide.md`):

- Title: past tense ("Added", "Fixed", "Refactored" — NOT "Add", "Fix")
- Title MUST end with ` (#NNNN)` — see the subject rule below
- Bullets: 1-5, each `* `-prefixed; what shipped, not how
- TODO reference: a `See ai/todos/active/TODO-...md` line, even
  though Step 3 moves the file to `completed/` — the commit lands
  before the move, so the path in the message is the pre-move path
- Co-authorship: exactly `Co-Authored-By: Claude <noreply@anthropic.com>`
- No emojis, no markdown links
- Total body ≤ 10 lines including blank lines

Generate a draft using this priority order:

1. **Subject**: `<PR title> (#NNNN)`. **You MUST include the
   ` (#NNNN)` suffix yourself** — when `gh pr merge --squash` is
   invoked with an explicit `--subject`, GitHub does NOT auto-append
   the PR number, so an explicit subject without `(#NNNN)` lands a
   commit message with no PR reference in the title, breaking
   `git log --oneline` discoverability and diverging from every other
   squash commit on `master`. If the PR title is not in past tense,
   rewrite it before adding the suffix.
2. **Body bullets**: prefer the bullets under `## Summary` in the PR
   description; if absent, derive them from the first ("foundation")
   commit on the branch. Trim sub-bullets and redundant "addressed
   review feedback" rounds — the squash is the *what shipped* view,
   not the *how we got there* view.
3. **TODO ref**: derive from the TODO path identified in Step 1.
4. **Co-Author line**: literal, always present.

### 1b.3 — Present and execute

Show the drafted subject and body to the user verbatim, then ask:

> Merge PR #N with this squash message? (yes / edit / abandon)

- **yes**: proceed
- **edit**: incorporate the user's revisions and re-confirm
- **abandon**: stop the command; do not touch local state

On approval (note the literal ` (#<N>)` at the end of `--subject` —
GitHub will NOT add it for you when an explicit subject is passed):

```bash
gh pr merge <N> --squash \
  --subject "<approved subject> (#<N>)" \
  --body "$(cat <<'EOF'
<approved body, verbatim, including blank lines and the TODO + Co-Author footers>
EOF
)"
```

After the merge, sanity-check the subject landed correctly:

```bash
git -C C:/proj/pwiz fetch origin master
git -C C:/proj/pwiz log origin/master --oneline -1
```

The first line must end with ` (#<N>)`. If it doesn't, the subject
was passed without the PR-number suffix and the commit is now on
`master` without it — flag this to the user immediately. Do not
attempt to rewrite the merge commit; surface it so they can decide
whether to leave it or hand-amend on the next push window.

If the user wants the merge to wait for pending checks instead of
firing immediately, append `--auto`.

Do **NOT** add `--delete-branch`. Step 6 deletes the *local* branch
with the safe `-d` after the merge-commit ancestry check; whether the
*remote* branch gets cleaned up is a repo-policy decision.

After `gh pr merge` returns, re-fetch the PR to capture the actual
`mergeCommit.oid`:

```bash
gh pr view <N> --json state,mergeCommit --jq '{state, oid: .mergeCommit.oid}'
```

`state` must now be `MERGED` and `oid` must be non-empty before Step
2 starts. If `gh pr merge` succeeded but `state` is still `OPEN`
(e.g. `--auto` was passed), STOP and tell the user — the rest of the
command will only be safe to run after the merge actually lands.

## Step 2 — Final TODO write

Edit the TODO at `ai/todos/active/TODO-YYYYMMDD_<slug>.md` (or
`completed/` if already moved):

1. **Status** → `Completed`
2. **PR** field → confirmed merged link, e.g.
   `[#NNNN](https://github.com/ProteoWizard/pwiz/pull/NNNN) (merged YYYY-MM-DD)`
3. Mark remaining checkboxes that are actually done as `[x]`. Leave
   unchecked any scope items the merged PR explicitly deferred —
   acknowledge them as deferred in the merge entry instead of
   pretending they shipped.
4. Append a Progress Log entry:

```markdown
### YYYY-MM-DD - Merged

PR #NNNN merged as commit <short SHA>. <One-paragraph summary of what
actually shipped, what was deferred, and any follow-up issues that
were filed.>
```

5. If the original TODO header included exception-fix or
   nightly-fix tracking fields (Exception Fingerprint / Test Name /
   Fix Type), record the fix at this point using the appropriate MCP
   tool (`record_exception_fix`, `record_test_fix`) — without those
   the report-side dashboards stay open against a fix that has
   actually shipped. If the TODO had no such fields, skip.

## Step 3 — Move and push (if not already moved)

Only if the TODO is still in `todos/active/`:

```bash
cd C:/proj/ai
git pull origin master                  # avoid colliding with another session
git mv todos/active/TODO-YYYYMMDD_<slug>.md todos/completed/
git add todos/completed/TODO-YYYYMMDD_<slug>.md
git commit -m "Completed TODO for #NNNN - <feature>"
git push origin master
```

If it was already in `todos/completed/`, commit only the final-write
edits and push:

```bash
cd C:/proj/ai
git pull origin master
git add todos/completed/TODO-YYYYMMDD_<slug>.md
git commit -m "Final TODO update for #NNNN - merged"
git push origin master
```

## Step 4 — Verify the PR is actually merged

Re-read `gh pr view <N> --json state,mergeCommit`. Treat anything
other than `state == "MERGED"` and a non-empty `mergeCommit.oid` as a
hard stop — back out of the local-branch cleanup and tell the user.
This is the gate before any destructive local operation.

## Step 5 — Switch to master, pull, verify

```bash
cd C:/proj/pwiz
git status --short                      # MUST be empty - never blow away local work
git checkout master
git pull origin master
```

If `git status` showed uncommitted changes on the work branch, STOP.
Stash, commit, or surface them to the user — never silently lose work
just because a PR is "merged" upstream.

After pull, verify the merge commit landed locally:

```bash
git merge-base --is-ancestor <mergeCommit.oid> HEAD && echo OK || echo MISSING
git log --oneline -5
```

If the merge commit isn't an ancestor of local `master`, STOP. Either
the upstream `master` you pulled doesn't yet contain the merge (rare:
mirror lag) or the SHA from `gh` doesn't match what got pushed.
Surface both SHAs to the user and let them decide.

Optionally diff one or two key files against the PR's head to
spot-check that the squash actually carries the expected change:

```bash
git show <mergeCommit.oid> --stat | head -20
```

## Step 6 — Delete the local work branch

Only after Step 5 passes:

```bash
git branch -d Skyline/work/YYYYMMDD_<slug>
```

Use `-d` (safe delete), never `-D` (force). For a GitHub squash-merge,
expect `-d` to print a warning like:

> warning: deleting branch 'Skyline/work/...' that has been merged to
> 'refs/remotes/origin/Skyline/work/...', but not yet merged to HEAD.

That warning is **normal and not a failure** — squash-merge creates a
new commit on `master` whose SHA differs from anything on the work
branch, so the work-branch tips are not direct ancestors of HEAD. The
proper safety check is the `git merge-base --is-ancestor` in Step 5;
having passed that, the warning is just git pointing at the squash
relationship. `git branch -d` still allows the delete because the
work-branch tip matches its remote-tracking ref ("you've pushed
everything"). For a merge-commit merge there is no warning.

If `-d` *refuses* (different from warning), stop and report what's
unreachable; do NOT escalate to `-D` without the user's explicit
go-ahead.

## Step 7 — Close the GitHub Issue (optional)

If the PR description used `Fixes #NNNN`, the issue auto-closed at
merge — skip this step. Otherwise:

```bash
gh issue close <issue-N> --comment "## Completion Summary

**PR**: #<pr-N> | **Merged**: YYYY-MM-DD as <short SHA>

### What Was Done
- <bullet 1>
- <bullet 2>

See ai/todos/completed/TODO-YYYYMMDD_<slug>.md for full engineering context."
```

## Final report

End with a short status to the user:

- PR #NNNN: merged as `<short SHA>` on YYYY-MM-DD
- TODO moved to `ai/todos/completed/TODO-YYYYMMDD_<slug>.md`
- Local master at `<short SHA>` (matches upstream)
- Work branch `Skyline/work/YYYYMMDD_<slug>` deleted

If any step had a deviation (deferred scope items, follow-up issues
filed, unresolved review threads carried forward), name them here so
they don't get lost.

## Hard rules

- **Never squash-merge without explicit user approval** of the exact
  subject and body in Step 1b.3. Auto-merging "because the PR looks
  ready" replaces author intent with model guesswork.
- **Always include ` (#NNNN)` in the squash subject.** GitHub auto-
  appends the PR number only when no explicit `--subject` is passed.
  This command always passes one, so the model must include the
  suffix verbatim. Past sessions have shipped commits to `master`
  without it and the title fails to surface the PR in `git log`,
  `git blame -L`, or release notes built from the log. The Step 1b.3
  draft AND the `gh pr merge` invocation MUST both end with `(#N)`.
- **Do not delete the local branch** unless Step 4 confirmed `state == MERGED`
  AND Step 5 confirmed the merge commit is an ancestor of local master.
- **Never amend or rewrite history** on the TODO move. The TODO is the
  durable engineering record; a clean, ordinary commit on `pwiz-ai`
  master is what we want.
- **Never use `-D`** on the work branch. If `-d` refuses (different
  from the squash-merge warning in Step 6), that's a signal to
  investigate, not to escalate.
- **Pull `pwiz-ai` master before the TODO commit** — TODOs from other
  sessions land on master too and rebasing the move is messier than
  just pulling first.

## Related

- `ai/WORKFLOW.md` — Workflow 3: Complete Work and Merge
- `ai/claude/commands/pw-uptodos-complete.md` — batch variant: scan
  all active TODOs for merged PRs and offer to complete each. Use
  that one when you don't know which TODO is ready; use this one
  when you know a specific PR just merged.
