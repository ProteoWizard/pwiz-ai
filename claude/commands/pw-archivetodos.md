---
description: Archive old completed TODOs into year/month subfolders
---
File any completed TODO left loose in ai/todos/completed/ into its year/month subfolder (e.g., 2025/12/).

**A completed TODO's home is `completed/YYYY/MM/`** (year and month of its file name date),
from the moment its PR merges. `/pw-complete`, `/pw-uptodos-complete` and `/pw-startissue`
move it there directly, so the PR-description link (rewritten to that path) never breaks
and nothing needs filing later. There is no holding period at the root. This command is
the safety net for files that still land loose under `completed/`: older ones from before
the policy, or a hand move that skipped the year/month folder. Filing one breaks any link
that still names the root path, so search `ai/` for its name and fix those references in
the same commit.

Run the archive script:

```bash
pwsh -File './ai/scripts/Archive-CompletedTodos.ps1'
```

By default this moves every dated TODO at the root into ai/todos/completed/YYYY/MM/ using git mv.

After the script runs, commit and push the moves.

If the user provides arguments (like `-KeepMonths 1` to leave the current month at the root), pass them through to the script. Use `-DryRun` first if unsure what will be moved.
