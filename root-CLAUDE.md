# Claude Code Configuration

**Run Claude Code from this directory** (the project root).

This directory is not a git repository. It contains sibling checkouts
(`ai/`, `pwiz/`, etc.) that are each their own git repo.

**At session start**, call `mcp__status__get_project_status()` to see all
repos, their branches, and dirty state — one call, no arguments needed.
Use `mcp__status__get_status` for targeted checks on specific directories.
Do NOT use `git` commands or `gh` to discover branches when status MCP can do it.

All Claude Code documentation lives in the **ai/** folder. See:
- **ai/CLAUDE.md** - Critical configuration (PowerShell, paths, commands)
- **ai/CRITICAL-RULES.md** - Absolute constraints
- **ai/MEMORY.md** - Project context and gotchas

The `.claude/` folder is a junction to `ai/claude/`, providing access to
commands, skills, and settings.

**CRITICAL**: Never use `cd /path && command` — `cd` once, then run simple
commands. See **ai/CRITICAL-RULES.md** for details.
