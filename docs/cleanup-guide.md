# Cleanup Guide

How to clean up the machine's clones and worktrees, `ai/.tmp/`, and the test data area.
Driven by `/pw-cleanup`.

## Why this is a command and not a script

The measuring is deterministic and already scripted: `ai/scripts/Clean-TmpFiles.ps1`
lists candidates by age, category and size and can delete them. What it cannot do is
decide whether a given file is disposable, misplaced, or something that should have
been a durable document. That decision needs judgement and a conversation with the
developer, which is what makes this a command.

The script has existed for a long while and was not the gap. On 2026-08-22 `ai/.tmp`
had reached **79 GB across 706 entries**, and the largest item - a 75 GB directory of
Osprey run output - was 18 days old, well inside what the script would have swept. It
survived because nothing prompts anyone to run the script, and running it blind is
unsafe. The command is the thing that gets invoked.

## Phase 0 - clones and worktrees

Sessions create git worktrees and sibling clones for parallel work: agent waves put one
worktree per agent under `C:\proj\wt-*` (or `D:\Dev\pwiz-*`), a review session checks a PR
out beside the primary clone, a perf baseline gets its own detached checkout. They are the
largest items on the machine (a full Skyline checkout with build output is 35-170 GB) and
nothing removes them when the work merges. Added 2026-11-05 after the round-2 backlog wave
left five `C:\proj\wt-*` worktrees and two `D:\Dev` worktrees behind, all detached at
master with their PRs merged.

1. **Measure first.** From the primary clone:

   ```bash
   git -C C:/proj/pwiz worktree list
   mcp__status__get_project_status()          # every sibling clone: branch, dirty state
   du -sh C:/proj/wt-* C:/proj/pwiz-* D:/Dev/pwiz-*   # sizes; a few seconds each
   ```

   For each entry record: path, branch or `detached`, dirty count, last commit date, size.

2. **Classify.** Each is one of:

   - **Finished agent or review worktree** - detached or on a branch whose PR is merged
     (`gh pr list --state merged --head <branch>`), no uncommitted changes. Remove:
     `git -C C:/proj/pwiz worktree remove <path>` then `git worktree prune`. A local
     branch left in it (`review/<N>`) goes with `git branch -D` once its PR is merged or
     abandoned, and that is the one place `-D` is expected.
   - **Dirty or unpushed** - uncommitted changes, untracked files, or commits not on any
     remote (`git -C <path> log --branches --not --remotes --oneline`). List the files and
     commits for the developer; never remove without an explicit yes. Untracked files in
     another session's checkout are usually that developer's own work in progress.
   - **Deliberate long-lived checkout** - a release branch (`skyline_26_1_1`), a perf
     baseline pinned at a commit, a port branch kept for comparison. Keep; ask only if the
     branch is gone upstream or the last commit is months old.

3. **Name the big ones.** Anything over 20 GB gets its own line with size, branch and last
   commit date, whatever its classification.

4. **Remove with an explicit yes per item.** A sibling clone (not a worktree) is deleted as
   a directory after the unpushed-commit check; its entry in
   `mcp__status__get_project_status` disappears with it.

The git stash is shared across worktrees of one clone; a stash entry another session made
is not a reason to keep a worktree, but mention it before removing.

## Phase 1 - `ai/.tmp`

1. **Measure first**, so the result can be stated as a before and after:

   ```bash
   du -sh ai/.tmp; ls -A ai/.tmp | wc -l
   ```

2. **Report** with the existing script - it already gives categories, per-item sizes,
   ages and a "would free" total, so do not write new reporting code:

   ```bash
   pwsh -File './ai/scripts/Clean-TmpFiles.ps1' -IncludeSubdirs -WhatIf
   ```

3. **Apply judgement** to what it lists. Every candidate is one of three things, and
   only the first is a simple delete:

   - **Disposable** - one-off logs, patch scripts, commit message drafts, MCP page
     downloads. Delete.
   - **Misplaced** - test or run output that should never have been written here.
     Delete it, and say so plainly: the fix is where the next one gets written, not
     the cleanup. Run output belongs under the machine's test data area; a session's
     own working files belong in `ai/.tmp/sessions/<YYYYMMDD>-<short-session-id>/`.
   - **Durable** - a design note, a measured result, an inventory someone will want in
     three months. Promote it to `ai/docs/` or into the relevant TODO first, then
     delete the copy. A durable document sitting in a temp folder is a document nobody
     will find.

4. **Name anything large or ancient explicitly** - over 100 MB or older than 90 days -
   with its size and date, and ask. Do not let a big or strange item go past in a
   summary line. Itemise the script's catch-all "Other" bucket rather than trusting it.

5. **Execute** the same command without `-WhatIf`, then report the before and after.

### Night-session budget logs

`/night-session` writes one dated log per night, `night-session-budget-<YYYYMMDD>.md`
(the script reports them as "Night-session logs"). Each is a minute-by-minute timeline
whose findings should already be in a TODO. Before deleting one, check that the TODO it
served carries its results (search the TODOs for the log's file name or the night's
date); if it does not, promote the missing findings first, as for any durable file. An
undated `night-session-budget.md` predates the dated scheme: rename it by its start date
(the "Start:" line) rather than deleting it.

## Phase 2 - the test data area

The test data root is machine-specific (on BRENDANX-UW8 it is `D:\test`). Treat it as
**report-only** unless the developer approves specific items.

- **Do not run a recursive `du`.** Measured on a 2.4 TB tree, it exceeded two minutes
  and timed out. Use shallow listings, `ls -lt`, and modification times.
- **Read the tree's own `README.md` first.** It carries retention policy the developer
  already wrote - for example "raw can be deleted after the mzML are verified" and
  "do not delete it casually" next to a directory that costs 47 minutes to rebuild.
  Surface those lines; do not invent a policy beside them.
- **Report what is expensive versus what is regenerable.** Staged instrument data and
  libraries took days to download and convert. Run output usually did not.
- **Propose reorganisation, not just deletion.** Sessions create run directories ad hoc
  and inconsistently; grouping them the way the tree's README prescribes is often worth
  more than the space.
- **Delete per item, with an explicit yes.** Never a blanket sweep here.

## Never deleted

- The script's protected list: `screenshots`, `state`, `daily`, `pr-report`, `history`,
  `attachments`, `icons`, `plots`, `plots-outliers`, and the live
  `active-project*.json` - these are owned by other tooling and regenerate on a schedule
- Anything tracked by git
- Anything the developer says is in use - when in doubt, ask, and list the paths so the
  answer is easy

## Prevention

- Session working files go in `ai/.tmp/sessions/<YYYYMMDD>-<short-session-id>/`, not at
  the root. The root is for files exchanged with the developer: handoffs, pasted
  context, downloads. A session writing dozens of `.py` and `.txt` files there buries
  the thing the folder exists for - on 2026-08-22 a single day's session accounted for
  123 of 706 entries.
- Test and run output goes to the test data area, never to `ai/.tmp`.
