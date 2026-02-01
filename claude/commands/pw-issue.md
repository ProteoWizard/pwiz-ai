---
description: Create GitHub Issue from TODO file, skyline.ms issue, or conversation context
---

# Create GitHub Issue

Create a GitHub Issue from various sources - TODO files, skyline.ms issues, or current conversation context.

**Goal**: Complete information transfer so the GitHub Issue is self-contained with ALL technical details preserved.

## Arguments

$ARGUMENTS = One of:
- TODO file path: `ai/todos/backlog/TODO-old_work.md`
- skyline.ms issue: `skyline:NNN`
- Context description: `for the exception we discussed` or similar phrase
- *(empty)*: Create from current conversation context

## From TODO File

```
/pw-issue ai/todos/backlog/TODO-old_work.md
```

### Workflow

1. **Read the TODO file completely**:
   - If file exists on current branch: `Read ai/todos/backlog/TODO-old_work.md`
   - If not found: `git show backlog-archive-YYYYMMDD:ai/todos/backlog/TODO-old_work.md`

2. **Transfer ALL content** (the issue must be self-contained):
   - Objective/Summary
   - Scope items (as checklist)
   - **All technical details** - proposed solutions, code samples, root cause analysis
   - **All context** - affected files/screenshots, status notes, related work
   - Preserve code blocks with proper formatting

3. **Determine labels** (apply ALL that fit):
   - **Repository**: `skyline` (Skyline app) or `pwiz` (ProteoWizard/msconvert)
   - **Type**: `bug`, `enhancement`, `todo`, `tutorial`, `performance`
   - Most issues need at least: repository label + type label

4. **Ask about assignee** (default: assign):
   - "Should I assign this to someone? Team members: brendanx67, nickshulman, bspratt, rita-gwen, etc."
   - Default to assigning unless user declines
   - Common assignees: `brendanx67` (lead), `nickshulman`, `bspratt`, `rita-gwen`

5. **Create GitHub Issue**:
   ```bash
   gh issue create \
     --title "<objective>" \
     --label "skyline,bug" \
     --assignee "brendanx67" \
     --body "## Summary
   <from TODO - include category, priority, origin>

   ## Scope
   <checklist from TODO>

   ## Technical Details
   <ALL technical content - code samples, proposed solutions, root cause analysis>
   <Use markdown headers to organize by task/topic>

   ## Getting Started
   Use /pw-startissue <number> to begin work.

   ---
   Migrated from: $ARGUMENTS"
   ```

6. **Report**: Show issue URL

7. **Verify completeness**: Ask user to confirm the issue contains all information needed to delete the TODO file

## From skyline.ms Issue

```
/pw-issue skyline:1234
```

### Workflow

1. **Fetch issue**: `mcp__labkey__get_issue_details(issue_id=1234)`

2. **Extract content**:
   - Title
   - Description
   - Priority, Area, Milestone (as labels if applicable)

3. **Determine labels** (apply ALL that fit):
   - **Repository**: `skyline` (Skyline app) or `pwiz` (ProteoWizard/msconvert)
   - **Type**: `bug`, `enhancement`, `todo`, `tutorial`, `performance`
   - Map skyline.ms Priority/Area to labels where applicable

4. **Ask about assignee** (default: assign):
   - "Should I assign this to someone? Team members: brendanx67, nickshulman, bspratt, rita-gwen, etc."
   - Default to assigning unless user declines

5. **Create GitHub Issue**:
   ```bash
   gh issue create \
     --title "<title>" \
     --label "skyline,bug" \
     --assignee "brendanx67" \
     --body "## Summary
   <from skyline.ms>

   ## Getting Started
   Use /pw-startissue <number> to begin work.

   ---
   Transferred from: skyline.ms Issue #1234"
   ```

6. **Report**: Show issue URL

## From Conversation Context

When no file/issue is specified, or a descriptive phrase is given:

```
/pw-issue
/pw-issue for the exception we discussed
/pw-issue for the NullReferenceException in BackgroundActionService
```

### Workflow

1. **Gather context from conversation**:
   - Look for exceptions, bugs, or features discussed in the current session
   - Extract: problem description, stack traces, root cause analysis, proposed fixes
   - Include any file paths, code snippets, or reproduction steps mentioned
   - Note any exception fingerprints, test names, or issue references

2. **Draft issue content** and present to user:
   - Proposed title
   - Summary of the problem
   - Technical details (stack trace, affected code, root cause)
   - Proposed fix (if discussed)
   - Ask user to confirm or modify before creating

3. **Determine labels** (apply ALL that fit):
   - **Repository**: `skyline` (Skyline app) or `pwiz` (ProteoWizard/msconvert)
   - **Type**: `bug` (for exceptions/defects), `enhancement`, `performance`
   - For exceptions: typically `skyline,bug`

4. **Ask about assignee** (default: assign):
   - "Should I assign this to someone? Team members: brendanx67, nickshulman, bspratt, rita-gwen, etc."
   - Default to assigning unless user declines

5. **Create GitHub Issue**:
   ```bash
   gh issue create \
     --title "<problem summary>" \
     --label "skyline,bug" \
     --assignee "brendanx67" \
     --body "## Problem

   <description of the bug/exception>

   ## Exception Report

   **Fingerprint**: \`<fingerprint hash>\`
   **Exception ID**: <skyline.ms exception ID>
   **Reports**: <N> from <M> users
   **Version**: <version string>

   ## Stack Trace

   \`\`\`
   <stack trace if applicable>
   \`\`\`

   ## Root Cause

   <analysis from conversation>

   ## Proposed Fix

   <solution discussed, if any>

   ## Files to Modify

   - <list of affected files>

   ## Getting Started
   Use /pw-startissue <number> to begin work.

   ---
   Created from conversation context"
   ```

6. **Report**: Show issue URL

### Exception-Specific Guidance

When creating issues for unhandled exceptions:
- **REQUIRED**: Include the **fingerprint** hash in the issue body under `## Exception Report`. This is critical for tracking fixes back to exception reports. Without the fingerprint, `record_exception_fix()` cannot be called later when the fix is merged.
- Include the **exception ID** (skyline.ms row ID) for linking to the original report
- Note the **user impact** (how many users affected, frequency of reports)
- Include version information
- Link to exception report thread if one exists

## Rules

- **Complete transfer**: The GitHub Issue must contain ALL information from the source. No summarizing or omitting technical details.
- **Self-contained**: After migration, the issue should be usable without referencing the original TODO file.
- **Deletable source**: The goal is that `ai/todos/backlog/` ceases to exist - all backlog items live in GitHub Issues.
- **Labels required**: Always add repository label (`skyline` or `pwiz`) + type label (`bug`, `enhancement`, etc.)
- **Assignee by default**: Ask about assignment and default to assigning unless user declines
- The created issue becomes the backlog item - TODO files are only created when work actively starts via `/pw-startissue`

## Available Labels

| Label | Use For |
|-------|---------|
| `skyline` | Skyline application changes |
| `pwiz` | ProteoWizard/msconvert changes |
| `bug` | Something isn't working |
| `enhancement` | New feature or request |
| `todo` | Tracked via ai/todos system |
| `tutorial` | Tutorial refresh work |
| `performance` | Performance issues |
| `Cherry pick to release` | Needs backport to release branch |

## Team Members (Assignees)

Common assignees: `brendanx67` (lead), `nickshulman`, `bspratt`, `rita-gwen`, `bconn-proteinms`
