---
argument-hint: <PR>
description: Review a PR and discuss issues with the developer
---

# PR Review

Review PR #$ARGUMENTS from the ProteoWizard/pwiz repository and discuss findings with the developer.

## Step 1: Load Skyline Development Context

Load the skyline-development skill for codebase context:
```
/skyline-development
```

## Step 2: Fetch PR Details

```bash
gh pr view $ARGUMENTS --repo ProteoWizard/pwiz --json title,body,headRefName,baseRefName,files,author,state,labels
```

Save the branch name (`headRefName`) and base branch (`baseRefName`) for later steps.

If the PR is not open, inform the developer and stop.

## Step 3: Find an Available pwiz Checkout

Call `mcp__status__get_project_status()` to see the state of all repositories.

There are three pwiz checkouts:
- `pwiz/` (primary)
- `pwiz-work1/`
- `pwiz-work2/`

**Selection criteria** - pick the first checkout that meets ALL of these:
1. Currently on `master` (no active feature branch)
2. No dirty state (no modified or staged files)

If a checkout is on a feature branch, check whether its PR has been merged:
```bash
gh pr list --repo ProteoWizard/pwiz --head <branch-name> --state merged
```
If merged, the checkout is available - it just needs to be reset to master first.

If no checkout is available, inform the developer which checkouts are busy and on what branches, and ask them to free one up. Do not proceed until a checkout is available.

## Step 4: Switch to the PR Branch

Using the selected checkout directory:

```bash
cd <selected-checkout>
git fetch origin
git checkout <headRefName>
git pull origin <headRefName>
```

## Step 5: Check Whether a Full Rebuild Is Needed

Compare the PR branch to its base to identify what files changed:
```bash
git diff --name-only <baseRefName>...<headRefName>
```

Categorize the changes:

| Changed files location | Build action |
|------------------------|-------------|
| Only within `pwiz_tools/Skyline/` (`.cs`, `.csproj`, `.resx`, `.Designer.cs`) | Solution build: `Build-Skyline.ps1` |
| `pwiz_tools/` but outside `Skyline/` (e.g., `Shared/`, `BiblioSpec/`) | Full native rebuild: `bs.bat` |
| Outside `pwiz_tools/` entirely (e.g., `pwiz/`, `libraries/`) | Full native rebuild: `bs.bat` |
| Only non-code files (`.md`, `.txt`, docs) | No build needed |

**If a full native rebuild (`bs.bat`) is required:**
Tell the developer:
> This PR includes changes outside `pwiz_tools/Skyline/` which require a full native rebuild (`bs.bat`).
> Please run `bs.bat` in the `<selected-checkout>` directory before testing.
> This takes approximately 20-30 minutes and cannot be run from Claude Code.

**If only a solution build is needed**, run it:
```bash
pwsh -File './ai/scripts/Skyline/Build-Skyline.ps1' -SourceRoot '<selected-checkout>'
```

**If no build is needed**, note this and continue to review.

## Step 6: Review the PR

### 6a. Read the full diff
```bash
gh pr diff $ARGUMENTS --repo ProteoWizard/pwiz
```

### 6b. For each changed file, read the surrounding context

Don't review the diff in isolation. For each substantially changed file, read the full file (or relevant sections) to understand:
- How the changed code fits into the class/module
- Whether callers or dependents are affected
- Whether the change is consistent with existing patterns

### 6c. Evaluate against quality criteria

Review for:

**Correctness**
- Does the logic do what the PR description claims?
- Are edge cases handled?
- Are there off-by-one errors, null reference risks, or race conditions?

**Architecture & Design**
- Does the change follow existing patterns in the codebase?
- Is there unnecessary duplication that should use existing helpers?
- Are new abstractions justified or premature?

**Skyline-Specific Rules** (from CRITICAL-RULES.md)
- No `async`/`await` — must use `ActionUtil.RunAsync()`
- No hardcoded UI strings — must use `.resx` resources
- No `MessageBox.Show()` — must use `MessageDlg`
- No new `using System.Windows.Forms` in Model layer
- Solution must build with zero warnings

**Style & Consistency**
- Follows existing naming conventions
- No unrelated formatting changes
- Comments only where logic isn't self-evident

**Test Coverage**
- Are new features/fixes covered by tests?
- Do existing tests need updating for the changes?

## Step 7: Present Findings

Present a structured review to the developer:

### Summary
One paragraph describing what the PR does and the overall assessment (looks good / needs changes / has concerns).

### Issues Found
List each issue with:
- **File and line reference** (file_path:line_number)
- **Severity**: Blocker / Concern / Suggestion / Nit
- **Description**: What the issue is and why it matters
- **Suggested fix** (if applicable): Concrete code suggestion

### Questions
List any areas where intent is unclear and you'd like the developer's input.

### What Looks Good
Brief acknowledgment of well-done aspects (keeps the review constructive).

---

After presenting findings, engage in discussion. The developer may:
- Explain design decisions that resolve concerns
- Ask you to suggest specific code changes
- Ask you to look deeper into a particular area
- Ask you to help draft review comments for the PR

Be ready to iterate on the review based on the discussion.
