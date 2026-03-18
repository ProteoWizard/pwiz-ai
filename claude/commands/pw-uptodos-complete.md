---
description: Check active TODOs for merged PRs ready to complete
args: scope
---
**First**: Pull the latest changes in the ai/ repository before scanning.

**Scope** (argument, default "mine"):
- `mine` — Only check TODOs authored by the current user (use `git log --format="%an" --diff-filter=A` on each file to determine authorship)
- `all` — Check all TODOs in ai/todos/active/

Scan TODO files in ai/todos/active/ (filtered by scope) for PR references. For TODOs without a PR reference, check if they have a GitHub issue reference — if so, check whether the issue was closed by a PR. Also try searching for PRs by the expected branch name (`Skyline/work/YYYYMMDD_feature` derived from the TODO filename).

Report:

1. **Ready to complete**: TODOs with merged PRs - offer to add resolution details and move to ai/todos/completed/
2. **Needs review**: TODOs with closed (not merged) PRs - may indicate abandoned or superseded work
3. **In progress**: TODOs with open PRs or no PR yet

For each TODO ready to complete:
- Add the PR reference if missing
- Add a "### YYYY-MM-DD - Merged" entry to the Progress Log with merge commit
- Add a "## Resolution" section with status and fix summary
- Move to ai/todos/completed/
- Commit and push changes
