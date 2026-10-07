---
description: Archive old completed TODOs into year/month subfolders
---
Archive completed TODO files from ai/todos/completed/ into year/month subfolders (e.g., 2025/12/).

Since 2026-10-07 `/pw-complete` and `/pw-uptodos-complete` move a TODO straight to its
`completed/YYYY/MM/` folder when the PR merges, so that the link in the PR description
(rewritten to that path) never breaks. This command remains for the files that were left
loose under `completed/` before then, and as a safety net. A file loose at the root is
not wrong, only not yet filed; moving it does break any PR link that still names the
root path, which is why the link is written to the final folder in the first place.

Run the archive script:

```bash
pwsh -File './ai/scripts/Archive-CompletedTodos.ps1'
```

This keeps the most recent 2 months of TODOs at the root level and moves everything older into ai/todos/completed/YYYY/MM/ subfolders using git mv.

After the script runs, commit and push the moves.

If the user provides arguments (like `-KeepMonths 1`), pass them through to the script. Use `-DryRun` first if unsure what will be moved.
