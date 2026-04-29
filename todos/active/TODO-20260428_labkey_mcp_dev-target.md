# TODO-20260428_labkey_mcp_dev-target.md

## Branch Information
- **Branch**: `feature/labkey-mcp-dev-target`
- **Base**: `master`
- **Created**: 2026-04-28
- **Status**: Tested on both http (dev box) and https (production) targets; ready to commit.
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
mcp/LabKeyMcp/tools/nightly_history.py  # delete dead `_get_failure_url` helper + constant
mcp/LabKeyMcp/tools/wiki.py             # _scheme propagation + line-315 link + non-200 extractor
```

> **Overlap with sibling PR:** `nightly.py` and `computers.py` are
> touched by both PRs at different lines, so a rebase is clean.
> `wiki.py` is exclusive to this PR.

## Behavior

- Default target unchanged: `https://skyline.ms`.
- Two new env vars:
  - `LABKEY_SERVER` — hostname (and optional `:port`); default `skyline.ms`.
    The port is required when the LabKey instance runs on a non-standard
    port (e.g. dev LabKey on `8080`); production uses default 443 so no
    port is needed there.
  - `LABKEY_USE_SSL` — set to `false` to use `http://`; default `true`.
- New `current_target` MCP tool returns the active target server URL.
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
- `get_netrc_credentials`: strip `:port` before the netrc lookup. Without
  this, the MCP's own lookup and the LabKey SDK's internal lookup behaved
  differently — the MCP needed `machine localhost:8080` while the SDK
  needed `machine localhost`, so a single dev entry in `~/.netrc`
  couldn't satisfy both code paths.
- Added `current_target` MCP tool returning
  `f"{_scheme()}://{DEFAULT_SERVER}"`.

### `_scheme()` propagation

- `tools/announcements.py`, `tools/attachments.py`, `tools/computers.py`,
  `tools/nightly.py`, `tools/wiki.py`: imported `_scheme`, replaced
  `f"https://{server}..."` with `f"{_scheme()}://{server}..."`.

### Hardcoded URL constants → helper functions

Two places built "View at" links by hardcoding `https://skyline.ms` at
module load time, ignoring `LABKEY_SERVER` / `LABKEY_USE_SSL`. Each now
builds the URL at call time using `_scheme()` and `DEFAULT_SERVER`:

- `tools/wiki.py:315` — `update_wiki_page` success-path return value.
- `tools/exceptions.py` — `EXCEPTION_URL_TEMPLATE` constant removed;
  `_get_exception_url(row_id)` builds the URL inline.

### Dead-code removal (`tools/nightly_history.py`)

`tools/nightly_history.py` had a `FAILURE_URL_TEMPLATE` constant and a
`_get_failure_url` helper that hardcoded `https://skyline.ms`. Verified
no callers anywhere in the MCP — both deleted rather than refactored
to use the active target. If a future tool needs this URL, it can build
it inline at the call site like the other tools do.

### Wiki update: clearer error messages on failure (`tools/wiki.py`)

When a wiki update request fails, `update_wiki_page` returns the error
message from LabKey's response. LabKey's standard error response uses
an `exception` field, but the MCP was only looking at `error` — so
most failure responses (permission denials, CSRF failures, etc.) came
back as a generic dump instead of the real reason. Now it checks
`exception` first, falls back to `error`, then to a truncated raw
response. Same fix as the shadow-fixes PR applied to `computers.py`.
Wiki tools weren't exercised by the testresults shadow test; this is a
defensive cleanup included since we're already touching the file.

### Server startup banner (`server.py`)

`logger.info(f"Starting LabKey MCP server — target: {target}")` so the
active target is visible from the server log.

### Documentation (`README.md`)

New `## Pointing at a non-production LabKey server` section between
`Usage Examples` and `Data Locations on skyline.ms`. Covers env var table,
switch commands, restart requirement, two-session caveat, and netrc note.

## Test plan

Changes in this PR that do not target testresults-specific tools, touch code paths whose
server-side behavior is identical on the dev box and production —
same module versions, and the dev box was restored from a production
DB dump. Both branches of `_scheme()` (http for dev, https for prod)
can therefore be exercised against either server by toggling the env
vars.

### Already verified via the testresults shadow test

During the shadow test, the MCP was pointed at a local LabKey
(`LABKEY_SERVER=localhost:8080 LABKEY_USE_SSL=false`) and 13 read-only
nightly tools plus 2 write tools ran end-to-end against it. That run
covers:

- **`common.py`** — env vars are read at startup and applied to every
  URL the MCP builds; `current_target` returned the configured URL;
  the netrc port-strip works (a single `machine localhost` entry in
  `~/.netrc` served both the MCP's own lookup and the LabKey SDK's
  lookup).
- **`nightly.py` and `computers.py`** — `_scheme()` propagation works
  for the testresults action URLs (`viewLog`, `viewXml`,
  `setUserActive`).
- **`server.py`** — startup banner printed the active target on launch.

The default `https://skyline.ms` branch of `_scheme()` (env vars unset)
is logically identical to the pre-feature hardcoded URL — but it has
not been empirically verified against production yet. That's the
`https` column in the table below.

### To run before merging

Run each row twice: first with
`LABKEY_SERVER=localhost:8080 LABKEY_USE_SSL=false` (exercises the
`http` branch), then with env vars unset (exercises the `https` branch
against production). Read-only tools are safe both ways.

| http | https | Test / verification | Prompt |
|:----:|:-----:|---------------------|--------|
| [x]  | [x]   | **Wiki (read)** — `get_wiki_page("<known page>")` and `list_wiki_pages` | `List wiki pages in /home/software/Skyline, then get the content of one of them.` |
| [x]  | [x]   | **Attachments** — `list_files` then `download_file` on one of them; verify the WebDAV URL uses the active scheme + port | `List files in /home/software/Skyline. Then download one of them.` |
| [x]  | [x]   | **Announcements** — `query_support_threads` | `Query support threads from the last 7 days.` |
| [x]  | [x]   | **Exceptions** — `save_exceptions_report(<date>)`; verify URLs in `ai/.tmp/exceptions-report-YYYYMMDD.md` use the active target | `Run save_exceptions_report for yesterday's date.` |
| [x]  | [x]   | **Wiki failure path** — `update_wiki_page` on a page that doesn't exist (or as a non-admin user); error message should come from LabKey's `exception` field, not a generic dump | `Try to update a wiki page named "this-page-does-not-exist-12345" with content "test".` |

### Side findings during testing

- **Row 2 (attachments):** real LabKey 403s triggered on both targets
  (dev box: removed user from Site:Agents; production: tried upload to
  a folder without permission). The MCP correctly surfaced the
  response as `"Upload failed with HTTP 403 Forbidden"` rather than
  masking it as a generic error — confirms the non-200 / error-
  extraction path on the upload tool works against real permission
  denials from LabKey on both http and https targets. After granting
  permission, upload succeeded — confirming the success path too.

### Out of scope here

Testresults-specific tools (`save_run_log`, `save_run_xml`,
`deactivate_computer`, `reactivate_computer`) need post-deploy
verification on production after the testresults Spring-binding
refactor is deployed on skyline.ms.

## Notes

- The two-session caveat documented in the README: registration is
  project-local, but each Claude Code session caches its launch
  parameters at start. If you flip the registration between launching
  session A and session B, A keeps its old target until restarted.
