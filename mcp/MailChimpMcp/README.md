# MailChimp MCP Server

Read-only MCP server for querying MailChimp Marketing API. Used to inspect
audiences, templates, and past campaigns during the Skyline release process.

## Why Read-Only

MailChimp's new email editor does not support API-driven content injection.
The `mc:edit` template section API only works with the deprecated "Classic"
builder, and writing raw HTML via the API corrupts campaigns created with
the new editor (they become uneditable in the MailChimp UI).

Instead, Claude generates paste-ready HTML that the developer copies into
MailChimp's designer code view. See the "Writing and Posting Release Notes"
section in `ai/docs/release-guide.md` for the full workflow.

## Setup

### 1. Create MailChimp API Key

Account > Extras > API Keys in MailChimp. Note the datacenter suffix
(e.g., `us21` from key ending in `-us21`).

### 2. Create Config File

Create `~/.mailchimp-mcp/config.json`:

```json
{
  "api_key": "your-api-key-us21",
  "server_prefix": "us21"
}
```

### 3. Install Dependencies

```bash
pip install mcp
```

### 4. Register with Claude Code

```bash
claude mcp add mailchimp -- python C:/proj/ai/mcp/MailChimpMcp/server.py
```

## Tools

- **mailchimp_ping** - Verify API connectivity
- **mailchimp_list_audiences** - List subscriber lists with member counts
- **mailchimp_list_templates** - List email templates
- **mailchimp_list_campaigns** - List campaigns with status/date filters
- **mailchimp_get_campaign** - Get campaign details and content

## MailChimp Resources

| Resource | ID | Description |
|----------|-----|-------------|
| Audience | `858d8c94a6` | Skyline (25,194 members) |
| Segment | `3018561` | Skyline Daily Release (~5,190 members) |
| Template | `10575987` | Blank Release (new editor, for daily releases) |
| Template | `10565578` | 2024 SL Simpletext (classic, for reference only) |
