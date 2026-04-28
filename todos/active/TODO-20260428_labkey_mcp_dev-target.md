# TODO-20260428_labkey_mcp_dev-target.md

## Branch Information
- **Branch**: TBD (suggested: `26.4_fb_labkey-mcp-dev-target`)
- **Base**: `master`
- **Created**: 2026-04-28
- **Status**: Ready to commit (working tree only).
- **Related**:
  - `TODO-LK-20260425_testresults-schema-shadow-test.md` — this feature
    enabled the shadow test by allowing the MCP to point at a local LabKey.
  - `TODO-20260428_labkey_mcp_shadow-fixes.md` — sibling PR (the three
    regressions caught **by** the shadow test). Lands first.

## Objective

Make the LabKey MCP server's target configurable via env vars so it can
point at any LabKey instance (default `https://skyline.ms`, can be
redirected to e.g. `http://localhost:8080`) without code changes.

Default behavior is unchanged: if no env vars are set, the MCP targets
`https://skyline.ms` exactly as before.

This is the feature that enabled the testresults shadow test. Not
required — it doesn't block anything — but it is good to have.

## Out of Scope

- Three regression fixes caused by the testresults Spring-binding refactor
  → sibling PR `TODO-20260428_labkey_mcp_shadow-fixes.md`. 

## Files Changed

```
mcp/LabKeyMcp/README.md
mcp/LabKeyMcp/server.py
mcp/LabKeyMcp/tools/announcements.py
mcp/LabKeyMcp/tools/attachments.py
mcp/LabKeyMcp/tools/common.py
mcp/LabKeyMcp/tools/computers.py        # _scheme propagation only — see "split"
mcp/LabKeyMcp/tools/exceptions.py
mcp/LabKeyMcp/tools/nightly.py          # _scheme propagation only — see "split"
mcp/LabKeyMcp/tools/nightly_history.py
mcp/LabKeyMcp/tools/wiki.py             # _scheme propagation + line-315 link — see "split"
```

> **Split with sibling PR:** three of these files (`nightly.py`,
> `computers.py`, `wiki.py`) also appear in the shadow-fixes PR but at
> non-overlapping line ranges. The shadow-fixes PR contains the
> regression-fix code; this PR contains only the `_scheme()` propagation
> code (and the `wiki.py:315` success-path link fix). If shadow-fixes
> is merged first, this PR rebases trivially.

## Behavior

- Default target unchanged: `https://skyline.ms`.
- Two new env vars:
  - `LABKEY_SERVER` — hostname (and optional `:port`); default `skyline.ms`.
    The port is required when the LabKey instance runs on a non-standard
    port (e.g. dev LabKey on `8080`); production uses default 443 so no
    port is needed there.
  - `LABKEY_USE_SSL` — set to `false` to use `http://`; default `true`.
- New `current_target` MCP tool returns the active URL.
- Server logs the active target at startup (visible in the MCP server log).
- Sample workflow (also documented in `mcp/LabKeyMcp/README.md`):
  ```bash
  # Switch to a local dev instance
  claude mcp remove labkey -s local
  claude mcp add labkey -e LABKEY_SERVER=localhost:8080 -e LABKEY_USE_SSL=false \
    -- python <repo-root>/mcp/LabKeyMcp/server.py

  # Switch back to production
  claude mcp remove labkey -s local
  claude mcp add labkey -- python <repo-root>/mcp/LabKeyMcp/server.py
  ```
  After either, **fully restart Claude Code** — `/mcp` reconnect alone
  re-spawns with the launch parameters cached at session start, so the new
  env vars are ignored.

## Implementation

### Core (`tools/common.py`)

- `DEFAULT_SERVER = os.environ.get("LABKEY_SERVER", "skyline.ms")`
- `USE_SSL = os.environ.get("LABKEY_USE_SSL", "true").lower() != "false"`
- `_scheme()` helper returns `"https"` or `"http"`.
- Threaded `use_ssl=USE_SSL` into `ServerContext`.
- Replaced 6 hardcoded `https://` URL builders with `f"{_scheme()}://..."`.
- `get_netrc_credentials`: strip `:port` before lookup so a `localhost:8080`
  server resolves the `machine localhost` netrc entry. Aligns the MCP's own
  netrc lookup with the `requests` library's behavior used by the LabKey
  SDK — without this fix the two paths can resolve to different accounts.
- Added `current_target` MCP tool returning
  `f"{_scheme()}://{DEFAULT_SERVER}"`.

### `_scheme()` propagation

- `tools/announcements.py`, `tools/attachments.py`, `tools/computers.py`,
  `tools/nightly.py`, `tools/wiki.py`: imported `_scheme`, replaced
  `f"https://{server}..."` with `f"{_scheme()}://{server}..."`.

### Hardcoded URL constants → helper functions

Three places built "View at" links by hardcoding `https://skyline.ms` at
module load time, ignoring `LABKEY_SERVER` / `LABKEY_USE_SSL`. Each now
builds the URL at call time using `_scheme()` and `DEFAULT_SERVER`:

- `tools/wiki.py:315` — `update_wiki_page` success-path return value.
- `tools/exceptions.py` — `EXCEPTION_URL_TEMPLATE` constant removed;
  `_get_exception_url(row_id)` builds the URL inline.
- `tools/nightly_history.py` — `FAILURE_URL_TEMPLATE` constant removed;
  the helper that formatted it now builds the URL inline.

### Server startup banner (`server.py`)

`logger.info(f"Starting LabKey MCP server — target: {target}")` so the
active target is visible from the server log.

### Documentation (`README.md`)

New `## Pointing at a non-production LabKey server` section between
`Usage Examples` and `Data Locations on skyline.ms`. Covers env var table,
switch commands, restart requirement, two-session caveat, and netrc note.


## Notes

- The two-session caveat documented in the README: registration is
  project-local, but each Claude Code session caches its launch
  parameters at start. If you flip the registration between launching
  session A and session B, A keeps its old target until restarted.
- Pre-existing inconsistency: `<repo-root>/ai/mcp/LabKeyMcp/server.py`
  appears in the README at lines 40 and 50 (Setup and `settings.json`),
  but the actual layout is `<repo-root>/mcp/LabKeyMcp/server.py` (no
  `ai/` prefix). Not fixed in this PR — flagged as a follow-up.
