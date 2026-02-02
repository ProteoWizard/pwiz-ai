# TODO-20260201_mcp_announcement_posting.md

## Branch Information
- **Created**: 2026-02-01
- **Completed**: 2026-02-01
- **Status**: Complete
- **Repository**: pwiz-ai (committed directly to master)

## Objective

Add a `post_announcement` tool to the LabKey MCP server that creates new announcement threads in any LabKey container, primarily for posting Skyline-daily release notes to `/home/software/Skyline/daily`.

## Why Form POST (Not SDK insert_rows)

LabKey's announcement controller handles email notifications — immediate, per-thread, and daily digest subscriptions. Using `labkey.query.insert_rows()` would bypass the controller and silently post without notifying subscribers. We POST through the announcement controller, same as the wiki update pattern.

## What Was Done

### Step 1: Extracted shared session code to common.py
- Moved `LabKeySession` class from wiki.py to common.py
- Moved `_get_labkey_session()` → `get_labkey_session()` (public API)
- Moved `_encode_waf_body()` → `encode_waf_body()` (public API)
- Moved `_decode_waf_body()` → `decode_waf_body()` (public API)
- Added `get_html()` and `post_form()` methods to LabKeySession
- Updated wiki.py and computers.py to import from common

### Step 2: Discovered announcement insert endpoint
- Fetched `announcements-insert.view` HTML from `/home/software/Skyline/daily`
- Form action: `POST announcements-insert.view` with `application/x-www-form-urlencoded`
- Required fields: `title`, `body`, `rendererType`
- Hidden fields: `X-LABKEY-CSRF`, `cancelUrl`, `returnUrl`, `discussionSrcIdentifier`
- Key finding: announcement form does NOT use WAF encoding (unlike wiki save)

### Step 3: Created tools/announcements.py
- `post_announcement(title, body, renderer_type, server, container_path)` tool
- Uses form POST (not WAF-encoded, not JSON) — plain body content
- After posting, queries `announcement.Announcement` table to retrieve RowId
- Returns row ID and direct view URL on success

### Step 4: Registered the tool
- Added to `tools/__init__.py` in DRILL-DOWN section

### Step 5: Updated documentation
- `docs/mcp/announcements.md` — added MCP Tools section with parameters and examples
- `docs/mcp/tool-hierarchy.md` — added Content Authoring section
- `docs/release-guide.md` — updated step 14 with automated posting workflow,
  added `/home/software/Skyline/releases` for major releases, updated "Writing
  and Posting Release Notes" section with 3-step workflow

### Step 6: Tested and used in production
- Test posts to `/home/software/Skyline/events/Announcements` (email off, then on)
- Confirmed Markdown rendering works correctly
- Confirmed email notifications sent through announcement controller
- Confirmed RowId extraction via post-insert query
- Backfilled 3 MailChimp emails to `/home/software/Skyline/releases`:
  * PATCHED: Skyline 24.1 (414 - 5b5ea5889c) — row 73872
  * Skyline 25.1 Release — row 73873
  * Skyline 25.1 (patch 1) — row 73874

## Key Learnings

- Announcement form does NOT use WAF encoding (wiki save does)
- Form POST with `application/x-www-form-urlencoded` works; no need for multipart
- Response HTML from successful POST doesn't contain rowId in a parseable way;
  querying the Announcement table after posting is the reliable approach
- The Claude account needs explicit insert permission per container

## Files Modified

| File | Change |
|------|--------|
| `mcp/LabKeyMcp/tools/common.py` | Added LabKeySession, WAF helpers, get_labkey_session, post_form |
| `mcp/LabKeyMcp/tools/wiki.py` | Removed local defs, imports from common |
| `mcp/LabKeyMcp/tools/computers.py` | Updated import from common instead of wiki |
| `mcp/LabKeyMcp/tools/announcements.py` | **NEW** — post_announcement tool |
| `mcp/LabKeyMcp/tools/__init__.py` | Added import + registration |
| `docs/mcp/announcements.md` | Added MCP Tools section |
| `docs/mcp/tool-hierarchy.md` | Added Content Authoring section |
| `docs/release-guide.md` | Updated release notes posting workflow |
