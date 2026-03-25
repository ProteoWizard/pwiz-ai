# MailChimp MCP Server

Read-only query tools for MailChimp Marketing API.

## Why Read-Only

We investigated full API-driven campaign creation (March 2026) and found that
MailChimp's Marketing API v3 cannot inject content into campaigns created with
the new email editor:

1. **Template sections (`mc:edit`)** - Only works with the deprecated "Classic"
   builder. MailChimp has announced Classic will be discontinued. Templates
   created in the new editor return empty `sections: {}` from the API.

2. **Raw HTML (`PUT /campaigns/{id}/content` with `html` field)** - Overwrites
   the new editor's internal content model. The campaign renders correctly in
   email clients but becomes corrupted and uneditable in the MailChimp UI.

3. **Replicate + modify** - Copying a previous campaign via
   `POST /campaigns/{id}/actions/replicate` works, but modifying the content
   via the API again corrupts the editor view.

**Conclusion**: Until MailChimp adds API support for their new editor's content
model, campaign content must be set manually in the MailChimp UI. Claude generates
paste-ready HTML that the developer copies into the designer's code view.

## What the MCP Server Does

Provides read-only context during the release process:
- **mailchimp_ping** - Verify API key works
- **mailchimp_list_audiences** - Find audience/list IDs
- **mailchimp_list_templates** - Find template IDs
- **mailchimp_list_campaigns** - Review past campaigns (subject, send time, stats)
- **mailchimp_get_campaign** - Inspect campaign details and content

## Release Email Workflow

See `ai/docs/release-guide.md` > "Writing and Posting Release Notes" > Step 4
for the full workflow. Summary:

1. Claude generates HTML from git commits (same content as skyline.ms announcement)
2. Developer creates campaign from "Blank Release" template in MailChimp
3. Developer pastes HTML into the designer's code view
4. Review, test, send to "Skyline Daily Release" segment

## Configuration

Config file: `~/.mailchimp-mcp/config.json`

```json
{
  "api_key": "your-api-key-us21",
  "server_prefix": "us21"
}
```

## Key MailChimp Resources

| Resource | ID | Notes |
|----------|-----|-------|
| Audience | `858d8c94a6` | Skyline (~25,000 members) |
| Segment | `3018561` | Skyline Daily Release (~5,190 members) |
| Template | `10575987` | Blank Release (new editor) |
