# Skyline Git Workflow - Quick Reference

Essential workflows for LLM-assisted development. See [ai/docs/workflow-guide.md](docs/workflow-guide.md) for comprehensive details.

## Repository Structure

Development involves two repositories:

| Repository | Local Path | Purpose |
|------------|------------|---------|
| `ProteoWizard/pwiz` | `pwiz/` | Skyline source code |
| `ProteoWizard/pwiz-ai` | `ai/` | AI tooling, documentation, TODOs |

**Key point**: The `ai/` directory is a separate git repository (`pwiz-ai`). Changes to anything under `ai/` are committed and pushed directly to `pwiz-ai` master - no feature branches needed.

See [ai/docs/ai-repository-strategy.md](docs/ai-repository-strategy.md) for setup details.

## Branch Strategy

**For pwiz repository:**
- **master** - Stable releases, requires review
- **Skyline/skyline_YY_N** - Release branches
- **Skyline/work/YYYYMMDD_description** - Feature/fix branches (all development)

**For pwiz-ai repository (ai/):**
- **master** - All work happens here directly
- No feature branches needed - commit and push to master

## Backlog and TODO System

### Where Work Lives

| Stage | Location | Repository |
|-------|----------|------------|
| **Backlog** | GitHub Issues | pwiz |
| **Active TODOs** | `ai/todos/active/` | pwiz-ai |
| **Completed TODOs** | `ai/todos/completed/` | pwiz-ai |

### Key Labels (GitHub Issues in pwiz)

| Label | Description |
|-------|-------------|
| `skyline` | Application changes |
| `pwiz` | ProteoWizard/msconvert |
| `todo` | Tracked via ai/todos system |

### TODO File Naming
- `TODO-20251227_feature_name.md` - Active (dated, in ai/todos/active/)
- `TODO-20251227_feature_name-auxiliary.txt` - Auxiliary files (logs, data, coverage)

### Header Standard (All TODO Files)

```markdown
# TODO-YYYYMMDD_feature_name.md

## Branch Information
- **Branch**: `Skyline/work/YYYYMMDD_feature_name`
- **Base**: `master` | `Skyline/skyline_YY_N`
- **Created**: YYYY-MM-DD
- **Status**: In Progress | Completed
- **GitHub Issue**: [#NNNN](https://github.com/ProteoWizard/pwiz/issues/NNNN)
- **PR**: [#NNNN](https://github.com/ProteoWizard/pwiz/pull/NNNN) | (pending)
```

**Note**: GitHub Issue and PR references must be Markdown links in the format `[#NNNN](URL)`, not raw URLs.

## Key Workflows

### Workflow 1: Start Work from GitHub Issue (/pw-startissue)

Use `/pw-startissue <number>` for zero-prompt startup.

**In pwiz repository** - create feature branch:
```bash
cd pwiz
git checkout master
git pull origin master
git checkout -b Skyline/work/YYYYMMDD_feature_name
```

**In pwiz-ai repository** - create TODO and push directly to master:
```bash
cd ai
# Create TODO file in ai/todos/active/
git add todos/active/TODO-YYYYMMDD_feature_name.md
git commit -m "Start work on #NNNN - feature name"
git push origin master
```

**Signal ownership** - Comment on the GitHub issue:
```
Starting work.
- Branch: `Skyline/work/YYYYMMDD_feature_name`
- TODO: `ai/todos/active/TODO-YYYYMMDD_feature_name.md`
```

### Workflow 2: Daily Development

**Code changes** go to pwiz feature branch:
```bash
cd pwiz
git add .
git commit -m "Descriptive message"
git push
```

**TODO updates** go directly to pwiz-ai master:
```bash
cd ai
git add todos/active/TODO-*.md
git commit -m "Update TODO progress"
git push origin master
```

**Update TODO with every significant milestone** - track completed tasks, decisions, files changed.

### Workflow 3: Complete Work and Merge

**Before PR approval:**
1. Add completion summary to TODO
2. Add PR reference: `**PR**: [#1234](https://github.com/ProteoWizard/pwiz/pull/1234)`
3. Mark all completed tasks as `[x]`
4. Update Status to `Completed`
5. Move TODO to completed and push to pwiz-ai:
```bash
cd ai
git mv todos/active/TODO-YYYYMMDD_feature.md todos/completed/
git commit -m "Move TODO to completed - ready for merge"
git push origin master
```

**After PR merge:**
```bash
cd pwiz
git checkout master
git pull origin master
git branch -d Skyline/work/YYYYMMDD_feature  # Delete local branch
```

**Close the GitHub Issue with completion summary:**
```bash
gh issue comment NNNN --body "## Completion Summary

**PR**: #XXXX | **Merged**: YYYY-MM-DD

### What Was Done
- Key accomplishment 1
- Key accomplishment 2

### Key Files Modified
- path/to/file.cs

See ai/todos/completed/TODO-YYYYMMDD_feature.md for full engineering context."

gh issue close NNNN
```

### Workflow 3a: Bug Fix for Completed Work

When fixing bugs in recently completed features:

```bash
cd pwiz
git checkout master
git pull origin master
git checkout -b Skyline/work/YYYYMMDD_original-feature-name-fix
```

**Update the original TODO** (don't create new one) - add "Bug Fixes" section.

### Workflow 4: Create GitHub Issue for Future Work

When inspiration strikes during development:

```bash
gh issue create \
  --title "Brief description" \
  --label "skyline,todo,enhancement" \
  --body "## Summary
Brief description...

## Scope
- [ ] Task 1
- [ ] Task 2

## Getting Started
Use /pw-startissue <number> to begin work."
```

## LLM Tool Guidelines

### Starting a Session
1. Read `ai/todos/active/TODO-YYYYMMDD_feature.md` - understand current state
2. Review recent commits - see what's been done
3. Check `ai/MEMORY.md` and `ai/CRITICAL-RULES.md` - essential constraints
4. Confirm remaining tasks

### During Development
1. Update TODO with every significant milestone
2. Follow `ai/STYLEGUIDE.md` and `ai/CRITICAL-RULES.md`
3. Use DRY principles - avoid duplication
4. Handle exceptions per established patterns

### Build and Test Automation

> Always build before running tests.

```powershell
# Build entire solution (default)
pwsh -Command "& './ai/scripts/Skyline/Build-Skyline.ps1'"

# Pre-commit validation
pwsh -Command "& './ai/scripts/Skyline/Build-Skyline.ps1' -RunTests -TestName CodeInspection"

# Run specific test
pwsh -Command "& './ai/scripts/Skyline/Run-Tests.ps1' -TestName TestPanoramaDownloadFile"
```

See [docs/build-and-test-guide.md](docs/build-and-test-guide.md) for complete reference.

### Context Switching
When switching LLM tools/sessions:
1. Update TODO with exact progress
2. Note key decisions and modified files
3. Provide handoff prompt in TODO

## Commit Messages

**Keep commit messages concise (10 lines max)**

**Required Format:**
```
<Title in past tense>

* bullet point 1
* bullet point 2

See ai/todos/active/TODO-YYYYMMDD_feature.md

Co-Authored-By: Claude <noreply@anthropic.com>
```

**Rules:**
- Past tense title - "Added feature" not "Add feature"
- 1-5 bullet points, each starting with `* `
- TODO reference - always include `See ai/todos/active/TODO-...`
- Co-Authored-By - always include when LLM contributed
- No emojis or markdown links

See [ai/docs/version-control-guide.md](docs/version-control-guide.md) for complete details.

## Critical Rules

See [ai/CRITICAL-RULES.md](CRITICAL-RULES.md) for full list. Key workflow rules:

- **Use git mv** - Always use `git mv` for moving TODO files (preserves history)
- **Update TODO regularly** - Track progress, decisions, files modified
- **Never modify completed TODOs** - They document merged PRs (historical record)
- **All TODOs must have PR reference** - Before moving to completed/
- **Signal ownership** - Comment on GitHub Issue when starting work
- **Commit messages 10 lines max** - Reference TODO for details
- **ai/ changes go to pwiz-ai master** - No feature branches needed

## See Also

- [ai/docs/workflow-guide.md](docs/workflow-guide.md) - Comprehensive workflow guide
- [ai/docs/ai-repository-strategy.md](docs/ai-repository-strategy.md) - AI repository setup (sibling/child modes)
- [ai/CRITICAL-RULES.md](CRITICAL-RULES.md) - All critical constraints
- [ai/MEMORY.md](MEMORY.md) - Project context and patterns
- [ai/STYLEGUIDE.md](STYLEGUIDE.md) - Coding conventions
