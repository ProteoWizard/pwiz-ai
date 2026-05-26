---
description: Start work on a GitHub Issue
---

# Start Work on GitHub Issue

Begin work on a GitHub Issue, following the appropriate workflow based on the repository.

## Arguments

$ARGUMENTS = GitHub Issue number (e.g., "3732") or URL

## Before You Begin — REQUIRED

**Load the `/version-control` skill BEFORE running any of the workflow steps below.**
This command's very first action (Step 4) is a commit to `pwiz-ai` master, so the
commit-message format, Co-Authored-By rule, and PR-description rules must already
be in working memory when you commit. They are easy to violate from defaults
(imperative tense, `-` bullets, emoji "Generated with" lines, fully-versioned
Co-Authored-By strings) — and once committed/pushed/opened, several are
either un-amendable or only amendable in a narrow window.

```
/version-control
```

Re-load `/version-control` if the conversation context has compacted before
the final PR is opened.

## Repository Structure

| Repository | Issues For | Local Path |
|------------|------------|------------|
| `ProteoWizard/pwiz` | Skyline/ProteoWizard code changes | `pwiz/` |
| `ProteoWizard/pwiz-ai` | AI tooling, documentation, MCP servers | `ai/` |

**Key point**: Issues for AI tooling/documentation belong in the **pwiz-ai** repository's Issues, not pwiz.

## Workflow

### Step 1: Fetch Issue Details

```bash
gh issue view $ARGUMENTS
```

Review the issue and note:
- **Labels**: Check for `skyline`, `pwiz`, `tutorial`, etc. (determines which skill to load in Step 5)
- **Scope**: What work is described
- **Repository**: pwiz (code changes) or pwiz-ai (AI tooling/docs)

### Step 2: Prepare Repositories

**Pull pwiz-ai first** to avoid conflicts with TODOs already moved by other sessions:
```bash
cd ai
git pull origin master
```

**For pwiz repository issues — check if the worktree is free:**

If pwiz is on a feature branch (not master), check whether that branch's PR has already been merged:
```bash
gh pr list --repo ProteoWizard/pwiz --head <current-branch-name> --state merged
```

If the PR is merged, the worktree is free — discard any leftover staged/modified files and switch to master. If the PR is NOT merged, the worktree has active work; use a different worktree or ask the user.

```bash
cd pwiz
git checkout master
git pull origin master
git checkout -b Skyline/work/YYYYMMDD_<description>
```

**For pwiz-ai repository issues:**
No branch needed - work directly on pwiz-ai master.

### Step 3: Create TODO File

Create `ai/todos/active/TODO-YYYYMMDD_<issue_title_slug>.md`:

```markdown
# <Issue Title>

## Branch Information
- **Branch**: `Skyline/work/YYYYMMDD_<description>` | `master` (pwiz-ai)
- **Base**: `master`
- **Created**: YYYY-MM-DD
- **Status**: In Progress
- **GitHub Issue**: [#NNNN](https://github.com/ProteoWizard/pwiz/issues/NNNN)
- **PR**: (pending)

## Objective

<Copy from issue Summary section>

## Tasks

<Copy scope items as checkboxes>

## Progress Log

### YYYY-MM-DD - Session Start

Starting work on this issue...
```

**For exception/nightly-test issues**: Copy tracking fields from the GitHub issue into the Branch Information section so fixes can be recorded when the PR merges:

```markdown
## Branch Information
...
- **Exception Fingerprint**: `abc123def456...`
- **Exception ID**: 73754
```

or for nightly test failures/leaks:

```markdown
## Branch Information
...
- **Test Name**: TestSomething
- **Fix Type**: failure | leak | hang
- **Failure Fingerprint**: `abc123def456...`
```

These fields are used by `record_exception_fix()` and `record_test_fix()` when the PR is merged. Without them, the fix cannot be tracked back to the original report.

**Also add a Regression Test section** so the fix leaves behind a permanent verifier. The fix is the diff between "test red" and "test green" -- a bug fix without a regression test is a fix that cannot be trusted to stay fixed. See [ai/docs/validation-cycle-principles.md](../../docs/validation-cycle-principles.md).

```markdown
## Regression Test

- **Test name**: (filled in once written)
- **Test project**: Test | TestFunctional | TestData | TestPerf | other
- **Fails on master**: (yes/no, with run log path or SHA when verified)
- **Passes on fix**: (yes/no, with run log path or SHA when verified)

If no regression test was added, explain why here. Acceptable answers exist (infrastructure-level fix no unit test could cover, infrastructure not yet in place) but must be acknowledged explicitly, not silently omitted.
```

The test should usually be the **first** deliverable on the branch, not the last. Write it, watch it fail on master, then make it pass.

### Step 4: Signal Ownership

> **Checkpoint**: `/version-control` must already be loaded (see "Before You Begin"
> at the top of this file). The commit below is the first place format rules apply.

**Commit TODO to pwiz-ai** — past-tense title, `* ` bullets, Co-Authored-By line,
max 10 lines, no TODO-file reference (the TODO file *is* the change):

```bash
cd ai
git add todos/active/TODO-*.md
git commit -m "$(cat <<'EOF'
Started work on #<issue> - <brief past-tense description>

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
git push origin master
```

**Comment on the issue:**
```bash
gh issue comment $ARGUMENTS --body "Starting work.
- Branch: \`<branch-name>\` (or pwiz-ai master)
- TODO: \`ai/todos/active/TODO-YYYYMMDD_<slug>.md\`"
```

### Step 5: Load Context

**Check the issue labels** and load the appropriate skill:

| Label | Skill to Load | Command |
|-------|---------------|---------|
| `skyline` | skyline-development | `/skyline-development` |
| `tutorial` | tutorial-documentation | `/tutorial-documentation` |
| `pwiz` | *(no skill yet)* | Read ai/CRITICAL-RULES.md, ai/MEMORY.md manually |

**For `skyline`-labeled issues**: Always load the skyline-development skill:
```
/skyline-development
```

**For `pwiz`-labeled issues**: No dedicated skill exists yet. Manually read:
- ai/CRITICAL-RULES.md - Absolute constraints
- ai/MEMORY.md - Project context
- ai/STYLEGUIDE.md - Coding conventions

**For AI tooling (pwiz-ai repo issues)**:
```
/ai-context-documentation
```

### Step 6: Begin Work

With TODO created and ownership signaled, begin implementing the issue scope.

Reference the issue in commits: `See #$ARGUMENTS` or `Fixes #$ARGUMENTS`

## Completion

> **Checkpoint**: Re-confirm `/version-control` is loaded before the code commit
> and `gh pr create`. Both have format rules (past-tense titles, `* ` bullets,
> `Co-Authored-By: Claude <noreply@anthropic.com>`, no emoji "Generated with"
> lines, no "Claude Opus 4.X (1M context)" variants in Co-Authored-By).
> After `gh pr create` returns the URL, the post-open review chain in the
> version-control skill (Copilot wait → `/pw-respond` → `/pw-self-review`)
> is mandatory, not optional.

**For pwiz issues:**
1. Update TODO Progress Log with completion summary
2. **For exception/nightly-fix issues**: confirm the Regression Test section is filled with a test name, project, and red->green verification (or an explicit rationale if no test was added). See [ai/docs/validation-cycle-principles.md](../../docs/validation-cycle-principles.md).
3. Move TODO: `git mv todos/active/TODO-*.md todos/completed/`
4. Commit to pwiz-ai master (format per `/version-control`)
5. Create PR to pwiz master (use `Fixes #$ARGUMENTS` to auto-close issue; description per `/version-control`)

**For pwiz-ai issues:**
1. Update TODO Progress Log with completion summary
2. Move TODO: `git mv todos/active/TODO-*.md todos/completed/`
3. Commit to pwiz-ai master (format per `/version-control`)
4. Close issue: `gh issue close $ARGUMENTS --comment "Completed. See ai/todos/completed/TODO-*.md"`

## Related

- ai/WORKFLOW.md - Standard branching and TODO workflow
- ai/docs/ai-repository-strategy.md - Two-repository structure
