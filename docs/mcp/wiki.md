# Wiki Documentation Access

Access and update wiki pages on skyline.ms, panoramaweb.org, or any other LabKey
server via the LabKey MCP server.

## Data Location

| Property | Value |
|----------|-------|
| Server | `skyline.ms` by default; any LabKey server via `server` (see [Other LabKey Servers](#other-labkey-servers)) |
| Schema | `wiki` |
| Tables | `CurrentWikiVersions`, `AllWikiVersions` |

### Wiki Containers

Any LabKey folder can contain wiki pages. The two main repositories:

| Container | Access | Content |
|-----------|--------|---------|
| `/home/software/Skyline` | Public | Install pages, tutorials, release announcements |
| `/home/development` | Authenticated | `release-prep`, `DeployToDockerHub`, `NewMachineBootstrap`, dev tools |

Other wiki content locations:

| Container | Access | Content |
|-----------|--------|---------|
| `/home` | Public | Landing page for skyline.ms |
| `/home/software/Skyline/daily` | Semi-public (signup required) | Skyline-daily release announcements |
| `/home/software/Skyline/events/<event>` | Public | Event registration, course info |
| `/home/software/Skyline/events/<event>/participants` | Restricted (participants/instructors) | Photos, posters, contacts, surveys |

**Default container**: Most MCP tools default to `/home/software/Skyline`. Use `container_path` parameter for others:
```
get_wiki_page("DeployToDockerHub", container_path="/home/development")
```

**Key columns:**

| Column | Description |
|--------|-------------|
| `Name` | Page identifier (e.g., `tutorial_method_edit`) |
| `Title` | Display title |
| `Body` | Page content (HTML or wiki markup) |
| `RendererType` | HTML, MARKDOWN, RADEOX, TEXT_WITH_LINKS |
| `Version` | Version number (integer) |
| `Modified` | Last modification timestamp |

**Tutorial naming convention:**
- English: `tutorial_<name>` (e.g., `tutorial_method_edit`)
- Japanese: `tutorial_<name>_ja`
- Chinese: `tutorial_<name>_zh`

## MCP Tools

| Tool | Description |
|------|-------------|
| `list_wiki_pages(container_path)` | List all pages with metadata (no body) |
| `get_wiki_page(page_name)` | Get full page content, save to `ai/.tmp/wiki-{host}--{container}--{page}.md` |
| `update_wiki_page(page_name, body_file, title)` | Update page content from local file (optional title change) |
| `list_wiki_attachments(page_name)` | List attachments for a wiki page |
| `get_wiki_attachment(page_name, filename)` | Download attachment from wiki page |

## Usage Examples

**List all wiki pages:**
```
list_wiki_pages()
```

**Get a specific tutorial page:**
```
get_wiki_page("tutorial_method_edit")
```
Returns metadata and saves full content to
`ai/.tmp/wiki-skyline.ms--home-software-Skyline--tutorial_method_edit.md`. The file
name includes the server and container, so same-named pages (`default` exists in
most folders) never overwrite each other. The tool prints the path it wrote.

**Update a wiki page:**
```
# 1. Download current page
get_wiki_page("AIDevSetup")  # saves to ai/.tmp/wiki-skyline.ms--home-software-Skyline--AIDevSetup.md

# 2. Copy to working file (strip markdown header), apply edits with Edit tool
# 3. Upload from file
update_wiki_page("AIDevSetup", body_file="C:/proj/ai/.tmp/wiki-AIDevSetup-updated.html")
```

> **Note:** Pages with `<iframe>` or `<script>` elements (tutorial wrappers) require "Allow Iframes and Scripts" permission, which the Agents group now has.

**List wiki page attachments:**
```
list_wiki_attachments("NewMachineBootstrap")
```

**Download a wiki attachment:**
```
get_wiki_attachment("NewMachineBootstrap", "new-machine-setup.md")
```
Text files are returned directly; binary files (PDF, images) are saved to `ai/.tmp/attachments/`.

## Other LabKey Servers

Every wiki tool takes `server` and `container_path`, so the same tools work on
panoramaweb.org, a local dev server, or any other LabKey instance. Credentials come
from a `machine <host>` entry in your netrc. To default a whole MCP instance to
another server, register it with `LABKEY_SERVER` (see
[ai/mcp/LabKeyMcp/README.md](../../mcp/LabKeyMcp/README.md)).

```
list_wiki_pages(server="https://panoramaweb.org", container_path="/MacCoss")
get_wiki_page("default", server="https://panoramaweb.org", container_path="/MacCoss")
```

What differs from skyline.ms:

- **No server-side setup needed.** The tools read the built-in
  `wiki.CurrentWikiVersions` table, which every LabKey server has.
- **Attachment listings may lack sizes.** `list_wiki_attachments` uses
  `corex.documents_metadata` for sizes and types where that external schema is
  configured (some skyline.ms folders). Elsewhere it lists the attachment names
  from the page's edit view, without sizes or types. Downloads work either way.
- **Allowed HTML depends on the account's permissions.** On panoramaweb.org, an
  account without the script and style permission gets
  `400 Illegal element <style>` from `update_wiki_page`. Inline `style="..."`
  attributes are allowed, so write styles inline.
- **There is no create tool.** `update_wiki_page` only changes existing pages.
  Create a page in the LabKey UI, or POST to `wiki-saveWiki.view` with the editor's
  new-page defaults (`entityId`, `rowId` and `parent` null, `pageVersionId` -1).

## Permissions

- ✅ Read all wiki content
- ✅ Add new wiki pages
- ✅ Update existing simple HTML/Markdown pages
- ❌ Delete pages or folders
- ❌ Update pages with `<iframe>` or `<script>` (security restriction)

## LabKey UI Operations

Some wiki operations require the LabKey web UI and cannot be done via MCP:

### Change Page Format (HTML ↔ Markdown)

1. Navigate to the wiki page on skyline.ms
2. Click **Edit** to enter edit mode
3. Look in the **top-right corner** for the **Convert To...** button (next to "Delete Page")
4. Select the desired format (HTML, Markdown, etc.)
5. Save the page

> **UX Note:** The format selector is not obvious. There's no visible "Format:" label or dropdown—the current format isn't displayed anywhere in the edit UI. The "Convert To..." button is the only way to see or change the format, and it applies to both new and existing pages. New pages in `/home/software/Skyline` default to HTML.
>
> **Tip:** Prefer Markdown for new pages—it's easier to maintain and matches our ai/docs files.

### Rename a Page

1. Navigate to the wiki page on skyline.ms
2. Click **Manage** (opens the page management view)
3. Click the **Rename** button
4. Enter the new page name
5. Confirm the rename

> **Note:** Renaming preserves page history. Use this instead of delete+recreate when you need to archive an old page (e.g., rename to `PageName-archived`).

## Wiki-to-File Mappings

Some wiki pages are kept in sync with files committed to the repository. The ai/docs files are the **source of truth**:

| Wiki Page | Source File | Sync Pattern |
|-----------|-------------|--------------|
| AIDevSetup | ai/docs/developer-setup-guide.md | **Body** - wiki body content = file content |
| NewMachineBootstrap | ai/docs/new-machine-setup.md | **Attachment** - file attached to wiki page |

**Update workflow:**
1. Edit the ai/docs source file
2. Commit to repository
3. Run `/pw-upconfig` to sync wiki pages

## Update Workflow

For pages that can be edited (simple HTML without iframes/scripts):

1. **Download current content**: `get_wiki_page("PageName")` → saved to
   `ai/.tmp/wiki-skyline.ms--home-software-Skyline--PageName.md` (the tool prints the path)
2. **Copy to working file**: Strip the markdown header (first 9 lines) to get raw HTML:
   ```bash
   tail -n +10 ai/.tmp/wiki-skyline.ms--home-software-Skyline--PageName.md > ai/.tmp/wiki-PageName-updated.html
   ```
3. **Apply edits**: Use the Edit tool to make changes — diffs are visible and reviewable
4. **Upload from file**: `update_wiki_page("PageName", body_file="ai/.tmp/wiki-PageName-updated.html")`
5. **Verify**: Check the live page at `https://skyline.ms/home/software/Skyline/wiki-page.view?name=PageName`

The wiki maintains full version history, so changes can be reverted if needed.

## Server-Side Queries

The wiki tools no longer use saved queries. `wiki_page_list` and `wiki_page_content`
still exist on skyline.ms (definitions in `ai/mcp/LabKeyMcp/queries/wiki/`), but they
only wrap `CurrentWikiVersions`. The tools query that table directly so they also
work on servers that don't have the saved queries.

## Searching All Wiki Pages Site-Wide

The MCP tools list pages one container at a time and fetch one body per call, so
neither can answer "which pages link to X?" Use LabKey's query API through
`fetch_labkey_page` with `containerFilter=AllFolders` to search every wiki body
on the server in a single call:

```python
fetch_labkey_page(
    view_name="query-selectRows.api",
    container_path="/home/software/Skyline",
    params={
        "schemaName": "wiki",
        "query.queryName": "CurrentWikiVersions",
        "query.containerFilterName": "AllFolders",
        "query.Body~contains": "2026-ugm.url",
        "query.columns": "Name,Title,Container",
        "query.maxRows": "200",
    },
)
```

Returns JSON with `rowCount` and one row per matching page.

> **Use `query-selectRows.api`, not `query-executeQuery.view`.** The `.view`
> action returns a JS-rendered grid whose rows are not present in the saved
> HTML, so grepping the file finds nothing and looks like a zero-result search.
> The `.api` action returns plain JSON.

**Always validate the filter with a control string first** — something you know
exists in a page body. A typo, a mis-named column, or a non-filterable field
returns `rowCount: 0`, which is indistinguishable from a true "nothing links
here" result. Confirming a known string matches first is what makes a zero
result trustworthy.

Typical uses:

- Find every page linking to one you plan to delete or rename
- Confirm a page is orphaned before removing it
- Audit where a short URL (`*.url`) is referenced

**Scope limit**: this searches wiki page bodies only. Links can also live in
webparts, message board posts, or entirely off-site.

**Short URLs** are not in the `wiki` schema. Resolve a `*.url` redirect directly:

```bash
curl -s -o /dev/null -D - "https://skyline.ms/ugms.url" | grep -i "^location:"
```

Repointing a short URL requires the LabKey admin UI — `admin-shortURLAdmin.view`
is not reachable through the MCP, and `core.ShortURL` is not exposed as a query.

## Gotchas

**`fetch_labkey_page` needs the `.view` or `.api` suffix.** The tool builds
`{server}/{container}/{view_name}` verbatim and appends nothing. `view_name="wiki-page"`
returns HTTP 404; `view_name="wiki-page.view"` works.

**Git Bash rewrites container paths passed to scripts.** When a script run from
Git Bash takes a container argument, `/MacCoss` arrives as
`C:/Program Files/Git/MacCoss` and LabKey answers `404: No such folder or workbook`.
Prefix the command with `MSYS_NO_PATHCONV=1`, and give the script's own path in
Windows form (`D:/...`), because the prefix also stops `/d/...` from being converted.
MCP tool calls are not affected.

**Saved wiki bodies use CRLF line endings.** Splitting on `'\n---\n'` to strip
the markdown header fails — use `re.search(r'\r?\n---\r?\n', text)`. Plain `diff`
also reports *every* line as changed when comparing an edited LF file against the
CRLF original; use `diff --strip-trailing-cr` to see the real changes.

**`<style>` blocks are permitted on skyline.ms, and LabKey rewrites the markup.**
For the skyline.ms Agents group, wiki bodies may contain `<style>` (unlike
`<script>` and `<iframe>`). panoramaweb.org rejects `<style>` from accounts without
the script and style permission; see [Other LabKey Servers](#other-labkey-servers). The HTML cleaner
normalizes self-closing tags — `<hr class="x" />` becomes `<hr class="x">` — and
may emit the style block twice in the rendered page. Both are harmless, but
account for them when grepping a fetched page to confirm an update landed.

> A `<style>` block in a wiki body applies to the **whole document**, not just
> the wiki content. Scope rules to a class you define; styling bare element
> selectors like `hr` or `p` will restyle LabKey's own page chrome.

**Verify content preservation on scripted bulk edits.** Before publishing, diff
the set of `href` values and visible text blocks against the original rather than
comparing line counts — counts shift misleadingly when line endings or separator
elements change.

## Future Enhancements

- Tutorial sync workflow (`pw-tutorial-sync`, proposed) for coordinating Git and wiki updates
- Attachment upload capability
