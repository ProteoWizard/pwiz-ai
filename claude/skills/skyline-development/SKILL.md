---
name: skyline-development
description: ALWAYS load when working in pwiz_tools/Skyline, on GitHub issues labeled 'skyline', or TODOs referencing Skyline code.
---

# Skyline Development Context

When working on any Skyline/ProteoWizard task, consult these documentation files for essential context.

## Starting Work on a TODO

When starting a new TODO or sprint, read **ai/todos/STARTUP.md** first. It provides:
- Essential context files to read (CRITICAL-RULES.md, MEMORY.md, WORKFLOW.md)
- Git branch workflow (create from master, copy TODO to active/)
- TODO lifecycle (backlog → active → completed)

## Continuing Work on Current Branch

When asked to continue work on the current branch or its TODO:
1. Call `mcp__status__get_project_status()` to get branch name (e.g., `Skyline/work/20251126_files_view`)
2. Extract date and feature name from branch (e.g., `20251126_files_view`)
3. Read the TODO file at `ai/todos/active/TODO-{date}_{feature}.md`
4. The TODO contains: objective, PR link, completed tasks, remaining work, and context

## Core Files (Read for Every Code Task)

Read these files to understand project constraints and patterns:

1. **ai/CRITICAL-RULES.md** - Absolute constraints (NO async/await, resource strings only, CRLF line endings, naming conventions)
2. **ai/MEMORY.md** - Project context (900K LOC, 17 years, 8 devs, critical gotchas)
3. **ai/WORKFLOW.md** - Git workflows, TODO system, commit message format
4. **ai/STYLEGUIDE.md** - **MUST READ before writing or editing ANY C#.** C# coding conventions for Skyline
5. **ai/TESTING.md** - Testing rules (translation-proof, test structure)

## When to Read What

- **Before writing code**: Read CRITICAL-RULES.md and **STYLEGUIDE.md - open the
  actual files.** The one-line summaries above are a table of contents, not a
  substitute. Re-read the relevant section any time you are about to deviate from
  what it shows, or catch yourself thinking "this rule probably doesn't cover my
  case" or "the surrounding code does it this way."
- **Before writing tests**: Read TESTING.md, ai/docs/testing-patterns.md
- **Before committing**: Read WORKFLOW.md (commit message rules, Co-Authored-By attribution)
- **Before building/testing**: Read ai/docs/build-and-test-guide.md
- **Investigating memory or slow/silent CLI runs**: Read ai/docs/memory-band-guide.md.
  `SkylineCmd --timestamp --memstamp` teed to a log, read with `ai/scripts/perfviz.py`
  (peak, memory-floor drift per unit of work, and every reporting gap over 30s) or
  `ai/scripts/perfviz.html` (plot). This is how memory that scales with workload size gets
  found without a profiler; it is a different problem from a leak (see leak-debugging).
- **For detailed patterns**: Read files in ai/docs/

## Key Constraints (Quick Reference)

- **NO `async`/`await`** - Use `ActionUtil.RunAsync()` instead
- **ALL user-facing text in .resx files** - No string literals
- **NEVER English text in test assertions** - Use resource strings
- **Line endings: CRLF** - Windows standard
- **Private fields: `_camelCase`** - Not `m_` prefix
- **Always include `Co-Authored-By: Claude <noreply@anthropic.com>`** in commits
- **CLI args must work via MCP `RunCommand()`** - Every SkylineCmd argument is also driven by an LLM through the in-process Skyline MCP, which saves via the GUI path (`SkylineFiles.SaveDocument`), not `CommandLine`'s. Don't thread per-invocation state through the `SaveDocument`/`Serialize*` signatures (the MCP path drops it); use a scoped ambient override set in `CommandLine.RunInner` and read at the convergence point all save paths share (`DocumentWriter` → `CompactFormatOption.Effective`). See PR #4288.

## Slash Commands Available

Type `/pw-` to see all project-specific commands. Key ones:
- `/pw-context` - Full context reload
- `/pw-rules` - Re-read the critical rules to correct drift
- `/pw-pcommitfull` - Pre-commit with TODO update
- `/pw-help` - Full command reference
