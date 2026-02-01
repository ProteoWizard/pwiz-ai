---
description: Start work on a GitHub Issue
---

# Start Work on GitHub Issue

Begin work on a GitHub Issue, following the appropriate workflow based on the repository.

## Arguments

$ARGUMENTS = GitHub Issue number (e.g., "3732") or URL

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

### Step 2: Create Branch (pwiz issues only)

**For pwiz repository issues:**
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

### Step 4: Signal Ownership

**Commit TODO to pwiz-ai:**
```bash
cd ai
git add todos/active/TODO-*.md
git commit -m "Start work on <issue> - <brief description>"
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

**For pwiz issues:**
1. Update TODO Progress Log with completion summary
2. Move TODO: `git mv todos/active/TODO-*.md todos/completed/`
3. Commit to pwiz-ai master
4. Create PR to pwiz master (use `Fixes #$ARGUMENTS` to auto-close issue)

**For pwiz-ai issues:**
1. Update TODO Progress Log with completion summary
2. Move TODO: `git mv todos/active/TODO-*.md todos/completed/`
3. Commit to pwiz-ai master
4. Close issue: `gh issue close $ARGUMENTS --comment "Completed. See ai/todos/completed/TODO-*.md"`

## Related

- ai/WORKFLOW.md - Standard branching and TODO workflow
- ai/docs/ai-repository-strategy.md - Two-repository structure
