---
description: Apply the git settings the pwiz repositories need (line endings, merges, blame)
---
Run, from the project root:

```
pwsh -File ./ai/scripts/Configure-Git.ps1
```

The script does all the work and is safe to rerun: it reports each setting as OK, SET (changed
now) or LEFT (differs and kept on purpose). Show the developer its table, then explain in a
sentence or two only the rows that are SET or LEFT. Do not read other docs or re-derive the
settings; the reasons are in the script's header if the developer asks.

If the developer asks to see what would change first, run it with `-Check`, which changes
nothing and exits 1 when something is needed.

If the "blame ignore list" row says SKIPPED, no pwiz checkout under the project root has
`.git-blame-ignore-revs` on origin yet; that is expected before the .NET 10 promotion and
needs nothing from the developer.
