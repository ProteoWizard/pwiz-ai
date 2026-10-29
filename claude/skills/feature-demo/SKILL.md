---
name: feature-demo
description: Use this skill when asked for a demo deck of a new Skyline feature, a feature walkthrough wiki page for the release notes, or screenshots of new UI captured over the Skyline MCP.
---

# Feature Demos and Walkthrough Pages

**Full documentation**: ai/docs/feature-demo-guide.md - read it before the first capture.

## What this covers

- A short demo deck (a Slides artifact) showing a feature's screens in the order a user meets them
- A feature walkthrough page on skyline.ms, modeled on
  [EncyclopeDiaSearch](https://skyline.ms/home/software/Skyline/wiki-page.view?name=EncyclopeDiaSearch),
  for the release notes to link to
- The screenshots both are built from, captured over the Skyline MCP from the feature's functional test

## The rules that matter most

1. **Screens come from the functional test, at temporary pauses.** `PauseTest()` in the test
   (`PauseAndContinueForm.Show()` inside a static helper), `Run-Tests.ps1 -AiConnector`, then
   `skyline_get_form_image` at each pause and Continue on `PauseAndContinueForm:Pause Test`. The
   pauses live in a CRLF-aware patch script in the session folder, are reverted with
   `git checkout --` before any commit, and `TestFunctional` is rebuilt afterwards
   (ai/TESTING.md, "Demos Are Temporary").
2. **Never pause with an alert open**: a test-mode alert times out after 10 seconds and fails the
   test. Resize a scrolling dialog before capturing it.
3. **A capture is a screen copy only when nothing covers the form**; otherwise an off-screen
   render with a square frame. Both get the border repaint since pwiz PR #4934.
4. **The result screen needs data with real peaks.** A test subset made for speed looks terrible;
   pick the peptide by dot products and area through a report, not by eye.
5. **The deck's history slides come from the developer**: dates, PR numbers, and whether the
   feature is merged or released. Merged to master is not shipped.
6. **The page**: CamelCase name, Markdown, one screenshot per numbered step, attachments hidden
   (`show_attachments=False`), drafted in `/home/software/Skyline-dev-private` and moved to
   `/home/software/Skyline` at release. `create_wiki_page`, `attach_wiki_files` and
   `update_wiki_page` in the LabKey MCP; `ai/mcp/LabKeyMcp/scripts/wiki_publish.py` runs the same
   code when the MCP server predates them.

## Related skills

- **skyline-wiki** - the wiki tools, their gotchas and the update workflow (ai/docs/mcp/wiki.md)
- **skyline-screenshots** - tutorial screenshots and ImageComparer, a different workflow with the same border repaint
- **tutorial-documentation** - full tutorials, where a walkthrough page is not enough
