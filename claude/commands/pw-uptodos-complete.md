---
description: Check active TODOs for merged PRs ready to complete
---
Scan all TODO files in ai/todos/active/ for PR references. For each PR found, query GitHub to check if it's merged. Report:

1. **Ready to complete**: TODOs with merged PRs - offer to add resolution details and move to ai/todos/completed/
2. **Needs review**: TODOs with closed (not merged) PRs - may indicate abandoned or superseded work
3. **In progress**: TODOs with open PRs or no PR yet

For each TODO ready to complete:
- Add a "### YYYY-MM-DD - Merged" entry to the Progress Log with merge commit
- Add a "## Resolution" section with status and fix summary
- Move to ai/todos/completed/
- Commit and push changes
