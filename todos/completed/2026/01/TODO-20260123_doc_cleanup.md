# TODO-20260123_doc_cleanup.md

## Branch Information
- **Created**: 2026-01-23
- **Status**: Complete
- **Merged**: Pushed directly to pwiz-ai master (no PR needed)

## Objective

Implement high-priority recommendations from the 8-agent documentation review swarm, focusing on quick wins and missing MCP documentation.

## Background

An 8-agent swarm reviewed all documentation in ai/. Full report at `ai/.tmp/ai-documentation-report.md`.

Key findings being addressed:
- 5 zero-value pw-r* commands should be deleted
- 3 commands listed in TOC.md don't exist
- MCP tool docstrings reference missing documentation files
- `issues-strategy.md` was intentionally deleted (decision complete) but references remain

## Phase 1: Quick Wins

### Delete Zero-Value Commands
- [x] Delete `pw-rbuildtest.md` (90 chars - just reads one file)
- [x] Delete `pw-rcrw.md` (105 chars - reads files already in CLAUDE.md)
- [x] Delete `pw-rmemory.md` (77 chars - single file read)
- [x] Delete `pw-rstyle.md` (66 chars - single file read)
- [x] Delete `pw-rtesting.md` (154 chars - just reads two files)

### Fix TOC.md
- [x] Remove non-existent commands: pw-aicontext, pw-aicontextsync, pw-aicontextupdate
- [x] Regenerate TOC with updated counts

### Fix Stale References
- [x] Update `ai/docs/mcp/README.md` - change issues-strategy.md to issues.md
- [x] Update `ai/mcp/LabKeyMcp/tools/issues.py` - change 3 docstring references from issues-strategy.md to issues.md

## Phase 2: Create Missing MCP Documentation

### Create ai/docs/mcp/issues.md
- [x] Document LabKey issues MCP tools (skyline.ms issue tracker):
  - `query_issues` - Browse issues by status/type
  - `get_issue_details` - Full issue with comments
  - `save_issues_report` - Issue tracker summary

### Create ai/docs/mcp/files.md
- [x] Document WebDAV file tools:
  - `list_files` - List files in container
  - `download_file` - Download file from container
  - `upload_file` - Upload file to container

### Create ai/docs/mcp/status.md
- [x] Already exists with comprehensive documentation (169 lines)

### Update ai/docs/mcp/README.md
- [x] Add entries for new files (issues.md, files.md, status.md)
- [x] Remove broken issues-strategy.md reference

## Success Criteria

- [x] All 5 pw-r* command files deleted
- [x] TOC.md regenerated with correct counts (Commands: 31 → 24)
- [x] No references to issues-strategy.md remain (was 4 stale references)
- [x] issues.md created with LabKey issues tool documentation (131 lines)
- [x] files.md updated with comprehensive WebDAV tool documentation (113 lines)
- [x] status.md already exists with complete documentation (123 lines)
- [x] All changes pushed to master

## Not In Scope (Future Work)

- Command consolidation (pw-pcommit + pw-pcommitfull, etc.)
- Skills trimming
- New architecture docs (threading, error-handling)
- Core doc accuracy fixes (enum naming, async exceptions)

## Progress Log

### 2026-01-23 - Session 1
- Created branch doc-cleanup-20260123
- Created TODO with 2-phase plan
- Spawned 4-agent implementation swarm (phase1-cleanup, issues-doc-writer, files-doc-writer, status-doc-writer)

### 2026-01-23 - Session 1 (continued)
- Completed Phase 1: Deleted 5 zero-value commands (pw-rbuildtest, pw-rcrw, pw-rmemory, pw-rstyle, pw-rtesting)
- Fixed 3 stale references in `ai/mcp/LabKeyMcp/tools/issues.py` (lines 35, 126, 276)
- Fixed stale reference in `ai/docs/mcp/README.md` (line 27)
- Created `ai/docs/mcp/issues.md` (131 lines) - comprehensive documentation for LabKey issue tracker tools
- Updated `ai/docs/mcp/files.md` (113 lines) - comprehensive documentation for WebDAV file tools
- Confirmed `ai/docs/mcp/status.md` already exists (123 lines) - StatusMcp tools
- Updated `ai/docs/mcp/README.md` with entries for issues.md, files.md, status.md
- Regenerated TOC.md:
  - Commands: 31 → 24 (removed 5 deleted + 3 non-existent)
  - MCP Data Sources: 9 → 12 (added issues.md, files.md descriptions; status.md already existed)
- Added descriptions to TOC.md for new MCP documentation files
- Fixed stale `/pw-aicontextsync` reference in Generate-TOC.ps1
- All Phase 1 and Phase 2 tasks complete
- All changes pushed to master
