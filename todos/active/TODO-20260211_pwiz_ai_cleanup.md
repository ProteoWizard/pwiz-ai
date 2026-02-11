# Clean up and reorganize pwiz-ai repository

## Branch Information
- **Branch**: N/A (direct to pwiz-ai master)
- **Created**: 2026-02-11
- **Status**: In Progress

## Objective

Prepare the pwiz-ai repository for a blog post with Anthropic by cleaning up stale references, outdated READMEs, naming inconsistencies, and redundant files.

## Tasks

- [x] Fix skill naming: rename `claude/skills/release-management/skill.md` → `SKILL.md`
- [x] Delete stale `docs/claude-commands.md` (references 6 non-existent commands, superseded by TOC.md)
- [x] Update `ai/README.md` — fix stale `pwiz_tools/Skyline/ai/` references, remove hardcoded line counts
- [x] Update `ai/docs/README.md` — expand from 7 guides to all 26 with categories
- [x] Update `ai/scripts/README.md` — document all 27 scripts (currently only 5)
- [x] Fix stale `pwiz_tools/Skyline/ai/` references in 4 other files
- [x] Regenerate `TOC.md` via `Generate-TOC.ps1`
- [ ] Commit all changes to pwiz-ai master

## Key Files

- `ai/README.md` — stale references to pwiz_tools/Skyline/ai/, hardcoded line counts
- `ai/docs/README.md` — only lists 7 of 27+ guides
- `ai/docs/claude-commands.md` — stale, to be deleted
- `ai/scripts/README.md` — only documents 5 of 27 scripts
- `ai/claude/skills/release-management/skill.md` — wrong casing
- `ai/claude/commands/pw-cover.md` — stale path reference
- `ai/claude/skills/skyline-tester/SKILL.md` — stale path references
- `ai/docs/skylinetester-debugging-guide.md` — stale path references
- `ai/scripts/Skyline/README.md` — stale path reference
- `ai/scripts/Generate-TOC.ps1` — run at end to regenerate TOC.md

## Progress Log

### 2026-02-11 - Planning
Audited full repository structure. Identified 8 cleanup tasks. Created plan.

### 2026-02-11 - Implementation
All cleanup tasks completed:
- Renamed skill.md → SKILL.md (two-step git mv for Windows case sensitivity)
- Deleted stale docs/claude-commands.md
- Updated ai/README.md: removed hardcoded line counts, fixed stale paths, updated See Also
- Rewrote ai/docs/README.md: organized all 26 guides into 7 categories
- Rewrote ai/scripts/README.md: documented all 27 scripts in table format
- Fixed 4 files with stale pwiz_tools/Skyline/ai/ references
- Regenerated TOC.md
