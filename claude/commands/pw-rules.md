---
description: Re-read CLAUDE.md and CRITICAL-RULES.md to correct rule violations
---
You are drifting from the project's critical rules. Stop what you are doing and carefully re-read these files:

1. Read `ai/CLAUDE.md` — pay close attention to:
   - **Prefer `pwsh` for commands** (use `pwsh -Command` or `pwsh -File`, not raw bash for .NET/Windows tools)
   - **Script path syntax** (forward slashes with `pwsh -File`, never backslash paths in Bash tool)
   - **Never use `&` call operator** in pwsh commands
   - **File editing paths** (backslashes for Edit/Read/Write tools)
   - **Null device** (`/dev/null` not `nul` in Git Bash)

2. Read `ai/CRITICAL-RULES.md` — pay close attention to:
   - **Bash: avoid `cd /path && command`** — `cd` once, then run simple commands separately
   - **No async/await**, no English literals in tests, CRLF line endings
   - **File and member ordering** rules

3. Read the root `CLAUDE.md` for any additional project-root rules.

After reading, briefly acknowledge which specific rule(s) you were violating and confirm you will follow them going forward. Then resume the task at hand.
