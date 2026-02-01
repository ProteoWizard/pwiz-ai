---
description: Archive old completed TODOs into year/month subfolders
---
Archive completed TODO files from ai/todos/completed/ into year/month subfolders (e.g., 2025/12/).

Run the archive script:

```bash
pwsh -Command "& './ai/scripts/Archive-CompletedTodos.ps1'"
```

This keeps the most recent 2 months of TODOs at the root level and moves everything older into ai/todos/completed/YYYY/MM/ subfolders using git mv.

After the script runs, commit and push the moves.

If the user provides arguments (like `-KeepMonths 1`), pass them through to the script. Use `-DryRun` first if unsure what will be moved.
