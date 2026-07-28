---
description: Audit Claude Code documentation and configuration
---

# Audit Documentation

Run `ai/scripts/audit-docs.ps1` to check documentation sizes.

## Usage

```powershell
# Full audit (all sections)
pwsh -File ai/scripts/audit-docs.ps1

# Specific sections
pwsh -File ai/scripts/audit-docs.ps1 -Section skills
pwsh -File ai/scripts/audit-docs.ps1 -Section commands
pwsh -File ai/scripts/audit-docs.ps1 -Section ai
pwsh -File ai/scripts/audit-docs.ps1 -Section docs
pwsh -File ai/scripts/audit-docs.ps1 -Section mcp

# Content checks only (rules, not sizes)
pwsh -File ai/scripts/audit-docs.ps1 -Section checks
```

## Sections

| Section | Path | Metric |
|---------|------|--------|
| skills | .claude/skills/*/SKILL.md | Characters, both tiers |
| commands | .claude/commands/*.md | Characters, both tiers |
| ai | ai/*.md | Lines, against per-file limits |
| docs | ai/docs/*.md | Lines (no limit - unlimited by design) |
| mcp | ai/docs/mcp/*.md | Lines (no limit) |
| checks | ai/**/*.md, ai/**/*.ps1 | Content rules, not sizes |

## Content checks

`-Section checks` verifies rules that nothing previously measured. Per
CRITICAL-RULES.md, *a rule without a verifier drifts* - each of these was
written down, followed for a while, then quietly stopped being followed:

| Check | Rule |
|---|---|
| call-operator | `pwsh -Command "& ..."` breaks Claude Code permission matching; use `-File` |
| broken-link | Relative markdown links must resolve |
| dangling-command | Every `/pw-*` reference names a real `claude/commands/<name>.md` |
| | *Convention: the leading `/` means **invocable**. Name a retired or not-yet-built command WITHOUT the slash (`` `pw-self-review` ``, `` `pw-review-leaks` ``) so a reader does not try to run it - and so this check stays meaningful.* |
| docs-to-skill | `ai/docs` must not link into `ai/claude/skills` - pointers run skills → docs |
| banned-phrase | "load-bearing", "smoking gun" per `C:\proj\CLAUDE.md` |

Link resolution tries three views before reporting a failure: the file's own
directory, repo-root-relative (the project's documented path convention), and -
for files under `ai/claude/` - the `.claude/` junction view, since command
authors reasonably write links relative to the path Claude Code loads them from.

**Excluded**: `todos/` and `docs/archive/`. Both are frozen records; "fixing"
their links would falsify history, and a check that fails forever gets muted.

**Whitelisted**: files that DEFINE a prohibition necessarily contain it as their
WRONG example (`ai/CLAUDE.md`, `root-CLAUDE.md`, `documentation-maintenance.md`,
`audit-docs.ps1` itself, and generated `TOC.md`).

## Two tiers of limits - read both

The script reports **platform** and **project** limits separately. They are far
apart, and reporting only the looser one is what let 16 files drift into
refactor territory unnoticed for ~9 months.

**Platform** (Claude Code hard constraints, skills/commands):

| Status | Chars |
|---|---|
| WARN | >=20,000 |
| ERROR | >=30,000 |

**Project** (`ai/docs/documentation-maintenance.md`, the tighter and more
important set):

| Status | Chars | Meaning |
|---|---|---|
| OK | <2,000 | Concise reference |
| REVIEW | 2,000-5,000 | Consider extracting to `ai/docs/` |
| REFACTOR | >=5,000 | Move content out; keep a pointer |

Core `ai/*.md` files additionally carry hard **line** limits (100-200 each,
<1000 combined for the core five; CLAUDE.md 250). `TOC.md`, `root-CLAUDE.md`
and `README.md` are exempt.

**A file can be `OK` on the platform tier and still need refactoring.** That is
the normal case here, not an edge case.

## Exit code

`0` unless a **hard** failure occurs - a platform ERROR, a core file (or the
core total) over its line limit, or any content-check violation. REFACTOR/REVIEW
are real debt and are reported prominently, but do not fail the run: 16 files sit
in that state today, and a script that always exits 1 gets ignored.

## Fixing size issues

See `ai/docs/documentation-maintenance.md`, section **"Commands and Skills:
Reference, Don't Embed"**, for the rule, the rationale, and the command
structure pattern to refactor toward.
