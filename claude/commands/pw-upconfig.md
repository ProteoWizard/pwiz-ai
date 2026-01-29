---
description: Sync developer config wiki pages with ai/docs
---

# Update Developer Configuration Wiki Pages

Compare the wiki pages on skyline.ms with their source files in ai/docs and update if needed.

## Pages to Sync

| Wiki Page | Source File | Sync Pattern |
|-----------|-------------|--------------|
| AIDevSetup | ai/docs/developer-setup-guide.md | Body content (wiki body = file content) |
| NewMachineBootstrap | ai/docs/new-machine-bootstrap.md | Body content (wiki body = file content) |

Note: NewMachineBootstrap previously carried `new-machine-setup.md` as an attachment.
That attachment was removed — the prompt now points directly to the GitHub raw URL,
which is always current and avoids the extra manual sync step.

## Workflow

### Step 1: Fetch Current Wiki Content

```
mcp__labkey__get_wiki_page("AIDevSetup")
mcp__labkey__get_wiki_page("NewMachineBootstrap")
```

### Step 2: Read Source Files

```
Read ai/docs/developer-setup-guide.md
Read ai/docs/new-machine-bootstrap.md
```

### Step 3: Compare and Report

For each page:
1. Compare content (ignore the wiki metadata header that get_wiki_page adds)
2. Report: "In sync" or "Needs update" with summary of differences
3. For significant differences, show a brief diff summary

### Step 4: Update (with confirmation)

For each page that needs updating:
- Strip HTML comment headers from source file before uploading
- Use: `mcp__labkey__update_wiki_page("<PageName>", new_body=<file_content>)`

## Important Notes

- The ai/docs files are the **source of truth**
- **Strip HTML comment headers** from source files before uploading to wiki
  - Known issue: LabKey's MARKDOWN renderer displays `<!-- -->` comments as visible text
  - Tested 2025-12-26 - reported to LabKey contact
- The wiki page metadata (title, version, etc.) is added by the MCP tool and shouldn't be compared
- After updating wiki, fetch again to verify the update took

## Related Documentation

- [Wiki MCP Documentation](ai/docs/mcp/wiki.md) - Full MCP wiki tool reference
- [Developer Setup Guide](ai/docs/developer-setup-guide.md) - Source for AIDevSetup
- [New Machine Bootstrap](ai/docs/new-machine-bootstrap.md) - Source for NewMachineBootstrap
