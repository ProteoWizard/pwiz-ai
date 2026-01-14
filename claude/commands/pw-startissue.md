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

Review the issue scope and determine which repository it belongs to.

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
- **GitHub Issue**: <issue URL>

## Objective

<Copy from issue Summary section>

## Tasks

<Copy scope items as checkboxes>

## Progress Log

### YYYY-MM-DD - Session Start

Starting work on this issue...
```

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

Based on issue type, load appropriate skills:
- Code changes → Load skyline-development skill
- Tutorial work → Load tutorial-documentation skill
- AI tooling → Load ai-context-documentation skill

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
