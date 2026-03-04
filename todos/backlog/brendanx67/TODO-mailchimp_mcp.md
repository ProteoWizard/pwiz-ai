# TODO: MailChimp MCP Server

## Overview
Build a Python MCP server for MailChimp Marketing API integration, focused on automating Skyline daily release email campaigns. The server should follow the same patterns established in the existing LabKey Server and TeamCity MCP servers.

## Context
- Currently, Claude Code generates release notes as a `.md` file during the release process
- The `.md` file is posted directly to LabKey Server's announcement module (already automated)
- For MailChimp, the text content is manually copied from the `.md` file into the MailChimp web UI template editor
- Goal: eliminate the manual copy step by using the MailChimp API to create campaigns, inject content into our existing HTML template, and send

## Prerequisites
- [ ] Generate a MailChimp API key (Account > Extras > API Keys) and note the datacenter suffix (e.g. `us6`)
- [ ] Identify the MailChimp audience/list ID for the Skyline release email recipients
- [ ] Identify the MailChimp template ID for the release email template
- [ ] Discover the template section name(s) where content is injected
  - Option A: Call `GET /campaigns/{id}/content` on an existing sent campaign and inspect the `template.sections` in the response
  - Option B: Look at the template source in MailChimp's template editor for `mc:edit="section_name"` attributes
- [ ] Decide on secrets management approach (`.env` file, environment variables, etc.) consistent with other MCP servers

## Sprint 1: Project Setup and Discovery

### 1.1 Project scaffolding
- [ ] Create project directory structure following existing MCP server conventions
- [ ] Initialize Python project with `pyproject.toml` or `setup.py`
- [ ] Add dependencies: `mcp` SDK, `httpx` or `mailchimp-marketing`, `markdown`, `python-dotenv`
- [ ] Create `.env.example` with required config keys:
  - `MAILCHIMP_API_KEY`
  - `MAILCHIMP_SERVER_PREFIX` (datacenter, e.g. `us6`)
  - `MAILCHIMP_LIST_ID` (audience ID)
  - `MAILCHIMP_TEMPLATE_ID`
  - `MAILCHIMP_TEMPLATE_SECTION` (content section name in template)
  - `MAILCHIMP_FROM_NAME`
  - `MAILCHIMP_REPLY_TO`

### 1.2 API client wrapper
- [ ] Implement a thin MailChimp API client class
  - Consider using `httpx` directly against `https://{dc}.api.mailchimp.com/3.0/` with basic auth rather than the official SDK (last updated Nov 2022)
  - Basic auth: any string as username, API key as password
  - All responses are JSON
- [ ] Implement `ping` call to verify authentication: `GET /ping`
- [ ] Test connectivity and confirm credentials work

### 1.3 Template discovery
- [ ] Implement `GET /templates` to list available templates
- [ ] Implement `GET /templates/{template_id}` to inspect a specific template
- [ ] Implement `GET /campaigns/{campaign_id}/content` to inspect an existing sent campaign
- [ ] Document the exact section name(s) needed for content injection
- [ ] Save a sample of the existing template's section content for reference during development

## Sprint 2: Core MCP Tools

### 2.1 `list_audiences` tool
- [ ] Implement `GET /lists` — returns audience/list IDs, names, member counts
- [ ] Useful for initial setup and debugging
- [ ] Return simplified results: id, name, member count, date created

### 2.2 `list_templates` tool
- [ ] Implement `GET /templates` — returns available templates
- [ ] Filter to show user-created templates (not built-in Mailchimp ones)
- [ ] Return: id, name, date_created, active status

### 2.3 `list_campaigns` tool
- [ ] Implement `GET /campaigns` with optional filters:
  - `status` filter (sent, draft, etc.)
  - `count` / `offset` for pagination
  - `since_send_time` for recent campaigns
- [ ] Return: id, title, subject, status, send_time, open/click stats summary

### 2.4 `get_campaign` tool
- [ ] Implement `GET /campaigns/{campaign_id}` — full campaign details
- [ ] Include content retrieval: `GET /campaigns/{campaign_id}/content`
- [ ] Useful for inspecting existing campaigns and debugging

## Sprint 3: Campaign Creation Workflow

### 3.1 `create_release_campaign` tool — the main tool
- [ ] Input parameters:
  - `markdown_file_path` (path to the .md file) OR `markdown_content` (raw markdown string)
  - `subject_line` (e.g. "Skyline Daily 24.2.1.234")
  - `preview_text` (optional — the preview text shown in email clients)
- [ ] Implementation steps:
  1. Read the .md file if path provided
  2. Convert markdown to HTML using Python `markdown` library
     - Verify that `<p>`, `<ul>/<li>`, `<b>`/`<strong>` all render correctly
     - Consider whether any post-processing of the HTML is needed
  3. Create campaign: `POST /campaigns` with:
     - `type`: `"regular"`
     - `recipients.list_id`: from config
     - `settings.subject_line`: from input
     - `settings.preview_text`: from input (if provided)
     - `settings.from_name`: from config
     - `settings.reply_to`: from config
     - `settings.title`: auto-generate from subject (for MailChimp internal tracking)
  4. Set content: `PUT /campaigns/{campaign_id}/content` with:
     - `template.id`: from config
     - `template.sections.{section_name}`: the converted HTML
  5. Return campaign ID, web URL for preview, and status
- [ ] Error handling: if campaign creation succeeds but content setting fails, clean up the empty campaign

### 3.2 `send_test_email` tool
- [ ] Implement `POST /campaigns/{campaign_id}/actions/test`
  - Input: `campaign_id`, `test_emails` (list of email addresses), `send_type` ("html" or "plaintext")
- [ ] Important safety step before sending to full audience
- [ ] Default test email address(es) could come from config

### 3.3 `check_send_readiness` tool
- [ ] Implement `GET /campaigns/{campaign_id}/send-checklist`
- [ ] Returns list of items with `is_ready` boolean and any error messages
- [ ] Should be called before send to catch issues

### 3.4 `send_campaign` tool
- [ ] Implement `POST /campaigns/{campaign_id}/actions/send`
- [ ] Require explicit campaign_id (no accidental sends)
- [ ] Call send-checklist first automatically and warn if issues found
- [ ] Return confirmation with send time

## Sprint 4: Safety, Polish, and Integration

### 4.1 Safety features
- [ ] Add a `dry_run` option to `create_release_campaign` that creates the campaign and sets content but does NOT send — just returns the preview URL
- [ ] Consider whether `send_campaign` should require a confirmation step or always be explicit
- [ ] Add `delete_campaign` tool for cleaning up draft campaigns from testing: `DELETE /campaigns/{campaign_id}` (only works on non-sent campaigns)

### 4.2 Campaign reporting
- [ ] Implement `get_campaign_report` tool: `GET /reports/{campaign_id}`
  - Opens, clicks, bounces, unsubscribes
  - Useful for checking that the email was delivered properly after send

### 4.3 MCP server configuration
- [ ] Add server to Claude Code MCP config (`.mcp.json` or equivalent)
- [ ] Configure appropriate tool permissions for non-interactive use if this will run in the automated daily release pipeline
- [ ] Test with Claude Code interactively first

### 4.4 Integration with release workflow
- [ ] Document how this MCP server fits into the existing release process alongside LabKey and TeamCity MCP servers
- [ ] Determine if `create_release_campaign` + `send_campaign` should be called automatically by the release process or remain a manual Claude Code step
- [ ] Consider a combined `create_and_send_release_email` tool that does everything in one shot for fully automated use, with a config flag to control whether it auto-sends or stops at draft

### 4.5 Documentation
- [ ] Write MEMORY.md or README.md for the MCP server project
- [ ] Document environment variables and setup steps
- [ ] Document typical usage patterns / slash commands for Claude Code

## API Reference Quick Notes

Base URL: `https://{dc}.api.mailchimp.com/3.0/`
Auth: HTTP Basic — username: any string, password: API key

| Endpoint | Method | Purpose |
|---|---|---|
| `/ping` | GET | Verify API key works |
| `/lists` | GET | List audiences |
| `/templates` | GET | List templates |
| `/campaigns` | GET | List campaigns |
| `/campaigns` | POST | Create campaign |
| `/campaigns/{id}` | GET | Get campaign details |
| `/campaigns/{id}` | DELETE | Delete draft campaign |
| `/campaigns/{id}/content` | GET | Get campaign content |
| `/campaigns/{id}/content` | PUT | Set campaign content (HTML or template+sections) |
| `/campaigns/{id}/send-checklist` | GET | Pre-send validation |
| `/campaigns/{id}/actions/test` | POST | Send test email |
| `/campaigns/{id}/actions/send` | POST | Send campaign |

## Key Design Decisions to Make
- [ ] Official SDK (`mailchimp-marketing`) vs. direct HTTP (`httpx`) — SDK is stale (2022) but functional; direct HTTP is cleaner and more maintainable
- [ ] Whether the markdown-to-HTML conversion needs any custom processing beyond the standard `markdown` library output
- [ ] Whether to support both `template.sections` content injection AND raw `html` body modes
- [ ] How to name/title campaigns for easy identification in the MailChimp UI
