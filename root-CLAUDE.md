# Claude Code Configuration

**Run Claude Code from this directory** (the project root).

This directory is not a git repository. It contains sibling checkouts
(`ai/`, `pwiz/`, etc.) that are each their own git repo.

**At session start**, call `mcp__status__get_project_status()` to see all
repos, their branches, and dirty state — one call, no arguments needed.
Use `mcp__status__get_status` for targeted checks on specific directories.
Do NOT use `git` commands or `gh` to discover branches when status MCP can do it.

**NEVER state a context-remaining number that did not come from
`mcp__status__get_context_usage`.** No estimates, no "~8%". Call it, then quote
it; if you haven't called it, say nothing about context. This covers every
mention, not just handoff — especially a number used to justify scoping down or
skipping a step, since a guess reads identically to a measurement and the user
may be on a phone.

Call it **before** suggesting handoff, end-of-session, or `/compact`. NEVER
mention a next session above 20%; many users push into single digits.

All Claude Code documentation lives in the **ai/** folder. See:
- **ai/CLAUDE.md** - Critical configuration (PowerShell, paths, commands)
- **ai/CRITICAL-RULES.md** - Absolute constraints
- **ai/MEMORY.md** - Project context and gotchas

The `.claude/` folder is a junction to `ai/claude/`, providing access to
commands, skills, and settings.

**CRITICAL**: Never use `cd /path && command` — `cd` once, then run simple
commands. See **ai/CRITICAL-RULES.md** for details.

**Sibling checkouts — scope every search to the ACTIVE checkout.** `C:\Dev`
holds many near-identical pwiz checkouts (one per branch), so searching across
the whole root returns meaningless duplicated hits (the same symbol in 20 copies).
Each session works in ONE active checkout: the directory in `$env:PWIZ_LSP_DIR`
(drop the trailing `\pwiz_tools` for the checkout root), or the one the user
names. At the start, `cd` into that checkout root **once** and use
checkout-relative paths (e.g. `pwiz_tools/Skyline/Foo.cs`). Never `grep`/`Glob`
across all of `C:\Dev`, and never silently pick a different checkout than the
active one. Do not re-`cd` per command. Your shell cwd is independent of
`CLAUDE_PROJECT_DIR` (which stays at the root so the `ai/` tooling works); invoke
shared `ai/` scripts by absolute path (`<project-root>/ai/scripts/...`).

**Prefer the C# LSP over grep for symbol navigation.** In a `skyclaude` session
the csharp-lsp plugin indexes the active checkout. For C# symbols — find
references, go to definition, call hierarchy — use the LSP, not text `grep`. That
is the entire point of the setup: it returns true semantic references from the
one indexed workspace, not textual matches duplicated across sibling checkouts.

## Language and Tone

**Banned phrases**: Do not use "smoking gun" or similar dramatic detective/crime
idioms. We are engineers doing "root cause" analysis, not crime scene investigators.

When you find decisive evidence, use analytical language, with these explicit preferences:
- "I found the smoking gun." -> "I found the root cause." or "Root cause identified!"
- "The smoking gun:" -> "The root cause:"
Or more specific to the context of the finding:
- "Found the mismatch" / "Found the discrepancy"
- "This accounts for the behavior we saw"

**Avoid "load-bearing"**: another metaphor borrowed from structural engineering to
sound weighty -- a wall is load-bearing; a decision, test, or assumption is just
important. Prefer plain words:
- "the load-bearing decision" -> "the critical decision" / "the key decision"
- "the load-bearing gate / oracle / test" -> "the critical gate" / "the key test"
- "X was load-bearing" (cannot be removed without breaking things) -> "X was essential"
Default to "critical" or "key"; use "essential" when the point is that something
cannot be removed.

**Avoid "it's sharper than that"** (and "sharper still", "the sharper point is").
"Sharp" is real technical register for a bound that cannot be improved - a sharp
inequality, sharpening an estimate - but "it's sharper than that" as a reply is not
an English idiom. It is that technical sense pressed into a conversational move:
agree with the reader, then claim the truth is more pointed than what they said. It
reads as swagger, and it is usually inaccurate on its own terms, because what
follows is normally something ADDITIONAL rather than something more precise.

Say what actually happened:
- "It's sharper than that" -> "There's more to it" (I looked where you pointed and
  found more that matters)
- When it really is a correction -> "Not quite - it's X, not Y"
- When it really is more precise -> "More precisely, ..." / "To put a number on it, ..."

The same applies to its cousins that dress a transition up as a discovery: "and it
gets worse", "that's only half of it", "here's the thing". State the finding.
