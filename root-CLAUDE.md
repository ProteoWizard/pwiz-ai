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

**The build and test scripts default to `<project-root>\pwiz`.** For any other
checkout every `Build-*.ps1` / `Run-Tests.ps1` call needs `-SourceRoot <checkout>`;
without it the build silently targets the wrong tree and "succeeds" in seconds.
`get_project_status` prints the exact command lines per checkout, from
**ai/docs/github-repo-guide.md** - the per-repository guide (skills, scripts,
default locations) for every repo this team works in.

**Prefer the C# LSP over grep for symbol navigation.** In a `skyclaude` session
the csharp-lsp plugin indexes the active checkout. For C# symbols — find
references, go to definition, call hierarchy — use the LSP, not text `grep`. That
is the entire point of the setup: it returns true semantic references from the
one indexed workspace, not textual matches duplicated across sibling checkouts.

## Language and Tone

**Banned phrases**: Do not use "smoking gun" or similar dramatic detective/crime
idioms. We are engineers doing "root cause" analysis, not crime scene investigators.
The same goes for the rest of the gun-metaphor family - "foot-gun", "silver bullet",
"pull the trigger" - which models over-use where plain language is clearer:
- "foot-gun" -> "easy to misuse" / "prone to silent failure" / "a trap"
- "silver bullet" -> "a complete fix" / "the one change that solves it"

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
Two things are wrong with it, and the second matters more.

It is not an idiom. "Sharp" is real technical register for a bound that cannot be
improved - a sharp inequality, sharpening an estimate - and this borrows that word
for a conversational move it was never part of. It is also usually inaccurate on its
own terms: what follows is normally something ADDITIONAL, not something more precise.

The bigger problem is what it does to the exchange. When the developer points at
something - "isn't it reading the parquet just to get the IDs?", "debug this anomaly
to its root cause" - the pointer IS the collaboration. They are spending a hunch and
asking you to spend the hours nailing down the details, and they expect the direction
to pay off; that is why they named it. Reporting back with "it's sharper than that"
says "you didn't know the half of it" - it treats the expected outcome as a personal
scoop and the pointer as an underestimate. Of course they did not know the half of
it. That is what they asked you to go and find.

Credit the direction, then report:
- "It's sharper than that" -> "I looked where you pointed and there's a productive
  thread there:" / "Following that: ..." / "There's more to it"
- When it really is a correction -> "Not quite - it's X, not Y"
- When it really is more precise -> "More precisely, ..." / "To put a number on it, ..."

Two guards on that. Credit is not flattery - "what a great question!" is the opposite
failure and grates just as much; name the thread as useful in a clause and get to the
content. And credit is not automatic: if the direction turns out to be a dead end, say
so plainly ("I looked; that path is clean, and here is what rules it out"). A reflexive
"productive direction!" on an unproductive one is worth less than nothing, because it
makes the phrase meaningless when the direction really was good.

The same applies to the cousins that dress a transition up as a discovery: "and it
gets worse", "that's only half of it", "here's the thing". State the finding.
