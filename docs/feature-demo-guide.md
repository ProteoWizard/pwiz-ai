# Feature Demos and Walkthrough Pages

How to show a new feature once it is in master: a short demo deck for the team and collaborators,
and a feature walkthrough page on skyline.ms for the release notes to link to. Both are built from
the same screenshots, captured over the Skyline MCP from the feature's own functional test, so the
screens are the real UI at the commit being shown and can be retaken in minutes when it changes.

The first deck and page made this way, on 2026-10-28 and 2026-10-29, were the Osprey/Carafe
library-build flow of pwiz PR #4927: the deck for Mike MacCoss and Bo Wen, and the page
`CarafeLibraryBuild` in `/home/software/Skyline-dev-private`. The procedure and the traps below
come from that work; the TODO `TODO-20261028_osprey_integration_demo_deck.md` has the detail.

Two example pages to model a walkthrough on, both in `/home/software/Skyline`:

- [EncyclopeDiaSearch](https://skyline.ms/home/software/Skyline/wiki-page.view?name=EncyclopeDiaSearch)
  (Markdown): one paragraph on what the feature is and which release has it, then numbered steps,
  each a heading, one screenshot and a few bullets on what the page's controls do.
- [Peak Area Dotp Line Plot](https://skyline.ms/home/software/Skyline/wiki-page.view?name=Peak%20Area%20Dotp%20Line%20Plot)
  (HTML): an explanation first, then a two-column table of screenshot beside caption.

## 1. Capture the screens from the functional test

**The mechanism** is the one `ai/TESTING.md` ("Demos Are Temporary") describes: temporary
`PauseTest()` calls dropped into the feature's functional test, the test run on screen with the
AI connector, and the Skyline MCP driven at each pause.

```powershell
pwsh -File ./ai/scripts/Skyline/Build-Skyline.ps1 -SourceRoot C:/proj/pwiz -Target TestFunctional
pwsh -File ./ai/scripts/Skyline/Run-Tests.ps1 -SourceRoot C:/proj/pwiz -TestName BuildLibraryCarafeWizardTest -AiConnector
```

Launch the run in the background and wait for `~/.skyline-mcp/connection-*.json` to appear. At
each pause: `skyline_get_open_forms` (the pause is `PauseAndContinueForm:Pause Test`, the form to
capture is listed with it), `skyline_get_form_image(formId, returnFormat="file", filePath=...)`,
look at the file, then `skyline_click_form_button("PauseAndContinueForm:Pause Test", "Continue")`.
The pause form itself is never in a capture, since a capture is of one form.

**Where to pause.** Write the list of screens first: every wizard page in order, each dialog a
button opens, the run or progress page while it works and when it is done, the hand-off to the
next wizard, and the result. Then put one pause after the test has filled each page and before it
clicks Next. `PauseTest` is an instance method; inside a static helper (the shared `RunSearch`,
`AdvanceToSearchSettings`) call `PauseAndContinueForm.Show("...")` instead, which is what
`PauseTest` does. Give every pause a description naming the screen; the test log lists them in
order, which is how you tell where a run is after a long wait.

**Keep the pauses as a patch script**, not as hand edits: a small Python script in the session
folder (`ai/.tmp/sessions/<date>-<topic>/`) that inserts each pause after a unique anchor line,
spelled with `\r\n` (the test files are CRLF) and refusing an anchor that matches zero or two
places. The pauses are re-applied for every recapture round, and reverted with
`git checkout -- <test files>` before anything is committed; then rebuild `TestFunctional` so the
binaries match the source again. `CodeInspection` flags a leftover `PauseTest()`.

**Never pause with an alert open.** In test mode a `MessageDlg` or `MultiButtonMsgDlg` times out
after 10 seconds and fails the test with `DialogTimeoutException`, and the MCP does not list it
among the open forms anyway. Pause on wizard pages and property dialogs; let the test dismiss its
own alerts. A screen that only exists as an alert (the Osprey download prompt) is not capturable
this way.

**Resize before capturing a scrolling dialog.** `skyline_resize_window` on the dialog (the screen
height caps it; the Additional Settings grid needed 560x1100) so one capture shows every row;
crop into columns afterwards if the slide needs it.

**Screen copy or off-screen render.** The form image is copied from the screen only when the whole
form is on the monitors and no other application's window covers it; otherwise Skyline renders it
off-screen, with a plain square frame. While a developer is using the desktop (a browser over the
test's windows) expect renders. Since pwiz PR #4934 both paths get the tutorial screenshots'
border repaint (`ScreenshotBorder.CleanupBorder` in CommonBaseUI), so corners are clean either way;
a capture from an older Skyline carries whatever lay behind the rounded corners, and
`clean_borders.py` in the session folder of the first deck repaints it the same way in Pillow.

**Capturing the main window.** Size it to the slot it will fill (`skyline_resize_window` on
`SkylineWindow:...`; 1660x710 fills a 1664x714 box at native scale), choose the peptide with a
report rather than by eye (`skyline_get_report_from_definition_rows` with
`LibraryDotProduct > 0.95`, `IsotopeDotProduct > 0.95`, sorted by `TotalArea` descending, filtered
to one replicate), `skyline_set_selection` with its `PrecursorLocator`, then
`View > Auto-Zoom > Best Peak` and, when precursor traces swamp the fragments,
`View > Transitions > Products` through `skyline_click_main_menu_item`.

**Use data with real peaks for the result screen.** A test subset made for speed (Osprey's Stellar
subset: three or four points across a peak, most transitions red) looks terrible on a slide, and
no choice of peptide fixes it. A completed perf-test document on the machine may be no better.
When the feature has a real dataset on disk (the Astral HeLa runs in `D:\test\osprey-runs\astral`,
with spectra caches and a predicted library beside them), a temporary block in the test can drive
the wizard over it and pause on the result; the Osprey Search on three Astral runs took 12 minutes
and the chromatogram import 10. A tutorial dataset is the other source of good-looking peaks.

**Ending a run.** Letting the test finish is best: it passes and tears down. To stop early, cancel
the wizard the test is on and then click Continue: the test fails at its next step and exits. On
screen the framework pauses once more on the failure; Continue again. The build script refuses to
build while a TestRunner is alive, so a run must be over before the next build.

**Processing.** For a 1920x1080 deck, upscale captures 2x with nearest-neighbour sampling (crisp UI
pixels; a 581x405 dialog becomes 1162x810 and fills a 1080-wide slot at 1.8x native). Keep the
main-window capture at native size. For a wiki page use the native-size files. Name the files for
what they show, in capture order (`bl-01-page1-quick.png`), and keep the raw captures separate
from the processed output; a 2x nearest-neighbour upscale is reversible by taking every other
pixel, which saved a capture that was overwritten.

## 2. The demo deck

The deck is a Slides artifact (the Artifact tool, `quickstart` with intent `slides`; one call per
new deck), published privately and shared by the developer from its Share menu. The runtime takes
the slides as `project/slides/<id>.html` files and an index; when the Artifact tool has no asset
upload, the screenshots go in as the deck's own files under `project/ds/shots/` and are referenced
by that path.

A shape that worked, 23 slides:

1. Cover: the feature in a line and who it is for.
2. The arc: how long it took and what blocked it, as a row of dated cards. Dates, PR numbers and
   what happened come from the developer; the first draft got the years wrong and said "shipped" of
   a branch that was merged, not released. Merged to master is not shipped.
3. What changed: the pieces that made the feature possible, three cards and one sentence.
4. One slide per screen, in the order a user meets them: an eyebrow naming the section and the
   count ("Build Library · 3 of 7"), a heading of a few words, one line of caption, the menu path
   or a note in the footer, and the capture at the right in a card. The page's own help text is
   the best source for the caption.
5. A comparison slide when the point is a difference (the settings grid with 10, 8 and 6 sections
   on the three routes): panels side by side, each labelled with the count.
6. The run and the result: the progress page during the work and when it is done, the hand-off,
   and the document with a peptide selected. Numbers from the run's log go on the slide with the
   caveats in the speaker notes (a toy dataset, a setting a test changed).
7. Where it stands: what is in master, what is still to do, and how to try it.

Speaker notes on every slide carry what the caption leaves out. Keep the deck's title and ids
stable across republishing; a changed slide is one file.

## 3. The feature walkthrough page

**Where.** Draft in `/home/software/Skyline-dev-private`, which only the team can read. When the
feature is released, the page moves to `/home/software/Skyline` and the release notes link to it
by name: `https://skyline.ms/home/software/Skyline/wiki-page.view?name=<PageName>`.

**Name and title.** The page name is CamelCase with no spaces (`CarafeLibraryBuild`,
`EncyclopeDiaSearch`); it is the `name=` in the URL and never changes. The title is the feature in
words, with the release once it is known ("EncyclopeDIA Search from Skyline 23.1").

**Format.** Markdown, which the wiki renders and which matches these docs. The body of the
EncyclopeDiaSearch page is the template: an opening paragraph (what the feature does, what it
replaces, which release has it), then `# 1. <Verb phrase>` headings, each followed by one
screenshot `![alt text](file-name.png)` and two to four bullets on what the controls do, and a
closing pointer to the related feature. Spaces in an attachment name become `%20` in the
reference; plain names avoid the question.

**Screenshots are attachments** with "Show attachments" off, so the list of files does not repeat
under the page. Use the native-size captures with the repainted border, named for what they show.

**Publishing with the LabKey MCP:**

```
create_wiki_page(page_name="CarafeLibraryBuild", body_file="...md",
    title="Building a Spectral Library with Carafe", renderer_type="MARKDOWN",
    show_attachments=False, container_path="/home/software/Skyline-dev-private")
attach_wiki_files(page_name="CarafeLibraryBuild", file_paths=[...png], container_path=...)
update_wiki_page(page_name=..., body_file=..., container_path=...)   # keeps show_attachments
```

A session whose MCP server started before these tools existed can run the same code as a script
(from Git Bash, `MSYS_NO_PATHCONV=1` stops the container path being rewritten):

```bash
MSYS_NO_PATHCONV=1 python C:/proj/ai/mcp/LabKeyMcp/scripts/wiki_publish.py create --page CarafeLibraryBuild \
    --title "Building a Spectral Library with Carafe" --body CarafeLibraryBuild.md \
    --container /home/software/Skyline-dev-private --hide-attachments
MSYS_NO_PATHCONV=1 python C:/proj/ai/mcp/LabKeyMcp/scripts/wiki_publish.py attach --page CarafeLibraryBuild \
    --container /home/software/Skyline-dev-private build-library-carafe.png fasta.png ...
```

**Verify** with `get_wiki_page` (renderer, version), `list_wiki_attachments`, and
`fetch_labkey_page("wiki-page.view", container_path=..., params={"name": ...})`: every
`<img>` in the saved HTML should point at `wiki-download.view?entityId=...&name=<file>`.
`ai/docs/mcp/wiki.md` has the tools, the gotchas and the update workflow.

## 4. Checklist

- [ ] Screens listed before any pause is written; pauses as a CRLF-aware patch script in the session folder
- [ ] No pause with an alert open; scrolling dialogs resized first
- [ ] Test files reverted and `TestFunctional` rebuilt; nothing demo-shaped committed
- [ ] Result screen from data with real peaks, the peptide chosen by dot products and area
- [ ] Deck: dates, PR numbers and "merged" versus "released" confirmed with the developer
- [ ] Page: CamelCase name, Markdown, one screenshot per step, attachments hidden, in Skyline-dev-private until release
- [ ] Rendered page fetched and its images checked
- [ ] The TODO records the capture mechanics, the deck and page links, and any test output kept for recaptures
