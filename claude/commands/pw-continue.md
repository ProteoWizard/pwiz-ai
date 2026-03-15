---
argument-hint: [repo-path]
description: Continue work on the current branch's TODO
---

# Continue Work on Current Branch

Resume work on an in-progress feature branch and its associated TODO file.

## Arguments

$ARGUMENTS = optional path to the repository (default: `C:\proj\pwiz`)

## Workflow

### Step 1: Identify Current Branch

Call `mcp__status__get_project_status()` (no arguments needed) to see all repos, their branches, and dirty state. Find the branch for the repo at $ARGUMENTS (or `C:\proj\pwiz` if no argument given).

Do NOT use `git` commands to discover branches — use the status MCP.

### Step 2: Find the Active TODO

Search `ai/todos/active/` for a TODO file whose Branch field matches the current branch name. The branch name typically follows the pattern `Skyline/work/YYYYMMDD_<description>`, and the TODO file follows the pattern `TODO-YYYYMMDD_<description>.md`.

If no matching TODO is found, tell the user and suggest `/pw-startissue` to create one.

### Step 3: Read Essential Context

1. `ai/CRITICAL-RULES.md` - Absolute constraints
2. `ai/MEMORY.md` - Project context and gotchas
3. The matching TODO file in `ai/todos/active/`

### Step 4: Load the Appropriate Skill

Check the TODO file for clues (GitHub Issue labels, file paths mentioned, repository):

| Indicator | Skill |
|-----------|-------|
| Skyline code, `skyline` label, pwiz repo | `/skyline-development` |
| Tutorial work, `tutorial` label | `/tutorial-documentation` |
| AI tooling, pwiz-ai repo | `/ai-context-documentation` |

**Default**: Load `/skyline-development` (most common case for pwiz branches).

### Step 5: Review Recent Progress

Read the **Progress Log** section of the TODO, focusing on the most recent entries to understand:
- What was accomplished in recent sessions
- Current status of each task
- Any blockers or next steps noted
- Decisions made that affect remaining work

### Step 6: Summarize and Begin

Present a brief summary to the user:
- Current branch and TODO file
- What's done vs. what remains (from the task checkboxes)
- The next steps noted in the most recent progress entry

Then ask the user what they'd like to focus on, or proceed with the next logical step from the TODO.
