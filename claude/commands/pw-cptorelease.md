---
argument-hint: <PR#>
description: Cherry-pick a merged PR to the release branch
---
Cherry-pick PR #$ARGUMENTS to the release branch:

## Prerequisites
- Read ai/docs/release-cycle-guide.md for current release branch name and phase
- Verify the PR has been merged to master (not just approved)

## Steps

1. **Fetch and identify the merge commit**
   ```bash
   git fetch origin master
   git log --oneline origin/master | grep "#$ARGUMENTS"
   ```

2. **Create a release branch for the cherry-pick**
   - Branch name format: `Skyline/work/YYYYMMDD_<feature>_release`
   - Base it on the current release branch (check release-cycle-guide.md for branch name)
   ```bash
   git checkout -b Skyline/work/YYYYMMDD_<feature>_release origin/<release-branch>
   ```

3. **Cherry-pick the merge commit**
   ```bash
   git cherry-pick <merge-commit-hash>
   ```

4. **Push and create PR**

   **The cherry-pick inherits the original PR's module** — both the label and
   the title prefix. Read it from the original: `gh pr view $ARGUMENTS --json
   labels,title`. The `<module>: ` prefix leads, before `Cherry-pick:`, so the
   release branch's log greps and sorts the same way `master` does:

   ```
   skyline: Cherry-pick: Fixed a NullReferenceException in the chromatogram totals graph
   ```

   ```bash
   git push -u origin <branch-name>
   gh pr create --base <release-branch> \
     --title "<module>: Cherry-pick: <original-title>" \
     --label <module> \
     --body "..."
   ```

   If the original PR predates module tagging and carries neither a label nor a
   prefix, infer the module from the diff and state the inference to the user.

5. **PR body format**
   ```markdown
   ## Summary

   Cherry-pick of #<PR#> to release branch `<release-branch>`.

   <Reason for cherry-pick if not obvious, e.g., "The automatic cherry-pick failed because...">

   **Original changes:**
   <Brief summary of what the PR did>
   ```

## Why Manual Cherry-Pick?

Common reasons the automatic cherry-pick fails (see release-cycle-guide.md):
1. PR branch deleted before cherry-pick bot ran
2. Merge commits in PR history interfered with squash-and-merge

## Benefits of Manual Cherry-Pick PRs

- More informative PR descriptions than auto-generated ones
- Clear link back to original PR
- Explicit summary of changes for reviewers
