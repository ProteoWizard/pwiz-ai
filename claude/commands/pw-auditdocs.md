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
```

## Sections

| Section | Path | Metric |
|---------|------|--------|
| skills | .claude/skills/*/SKILL.md | Characters, both tiers |
| commands | .claude/commands/*.md | Characters, both tiers |
| ai | ai/*.md | Lines, against per-file limits |
| docs | ai/docs/*.md | Lines (no limit - unlimited by design) |
| mcp | ai/docs/mcp/*.md | Lines (no limit) |

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

`0` unless a **hard** limit is breached - a platform ERROR, or a core file (or
the core total) over its line limit. REFACTOR/REVIEW are real debt and are
reported prominently, but do not fail the run.

## Fixing size issues

See `ai/docs/documentation-maintenance.md`, section **"Commands and Skills:
Reference, Don't Embed"**, for the rule, the rationale, and the command
structure pattern to refactor toward.
