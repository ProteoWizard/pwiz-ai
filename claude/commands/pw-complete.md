---
description: Finalize a merged PR — write final TODO, move to completed, sync local master, delete the work branch
args: pr-number (optional)
---

# Complete a Merged PR

End-of-branch ritual after a PR has been merged on GitHub. The user is
telling you the merge happened — your job is to verify that, leave a
clean record in `ai/todos/completed/`, and sync the local checkout so
the work branch is gone and `master` is the merged state.

**Do not run this command speculatively.** If the PR is not actually
merged when you check, stop and report. Deleting a local branch whose
work hasn't reached master is unrecoverable from the local repo alone.

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

Use `-d` (safe delete), never `-D` (force). The safe delete refuses
if the branch has commits not reachable from another ref — that's
the last line of defense against losing un-pushed local work. If `-d`
refuses, stop and report what's unreachable; do NOT escalate to `-D`
without the user's explicit go-ahead.

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

- **Do not delete the local branch** unless Step 4 confirmed `state == MERGED`
  AND Step 5 confirmed the merge commit is an ancestor of local master.
- **Never amend or rewrite history** on the TODO move. The TODO is the
  durable engineering record; a clean, ordinary commit on `pwiz-ai`
  master is what we want.
- **Never use `-D`** on the work branch. If `-d` refuses, that's a
  signal to investigate, not to escalate.
- **Pull `pwiz-ai` master before the TODO commit** — TODOs from other
  sessions land on master too and rebasing the move is messier than
  just pulling first.

## Related

- `ai/WORKFLOW.md` — Workflow 3: Complete Work and Merge
- `ai/claude/commands/pw-uptodos-complete.md` — batch variant: scan
  all active TODOs for merged PRs and offer to complete each. Use
  that one when you don't know which TODO is ready; use this one
  when you know a specific PR just merged.
