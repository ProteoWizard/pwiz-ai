# TODO-osprey_integration_demo_deck.md

## Branch Information
- **Branch**: none needed (an HTML artifact, not pwiz code; a pwiz branch only if a demo pause has to be committed, which it does not)
- **Created**: 2026-10-28
- **Status**: Deck published 2026-10-28, awaiting Brendan's review
- **Deck**: https://claude.ai/artifact/3dTj3s8uLAmM7p2qrKY44i (private until shared from its Share menu)
- **Module**: (none: ai/ deliverable)
- **Objective**: A short DHTML demo deck for Mike MacCoss and Bo Wen showing the Skyline library-build
  flow with Osprey and Carafe as it shipped in PR #4927 (merged 2026-10-28, 15c39798df), and how
  close it is to the integration Brendan spec'd two years ago.
- **Requested by**: Brendan, 2026-10-28, on completing #4927.

## The story Brendan wants told
- The integration was spec'd ~2 years ago and got hung up in the details: installing Python and
  Java, and a fine-tune that relied on DIA-NN.
- The complete Osprey pipeline in C# and Carafe on TorchSharp (CarafeSharp) changed everything:
  Skyline now achieves the level of integration its users expect - download once, no runtimes to
  install, one wizard.
- Show, don't tell: the Build Library flow (Carafe source on page 1 as the quick path; the
  Fine-tune box leading to the tuning runs, FASTA, modifications and Search Settings pages; the
  Additional Settings property grid, sections from Osprey's own help), and the Osprey Search wizard
  (data files, FASTA or existing library, Library Model, modifications, Search Settings, run page,
  hand-off to Import Peptide Search; the grid showing fewer settings for an existing library).

## How to make it
- Screenshots over the Skyline MCP: drop temporary `PauseTest()` calls into
  `BuildLibraryCarafeWizardTest` and `OspreySearchTest` (the pages are listed in the completed TODO
  `todos/completed/2026/10/TODO-20261027_osprey_search_settings_grid.md`, "Demos" entry), run
  `Run-Tests.ps1 -SourceRoot C:/proj/pwiz -TestName <Test> -AiConnector`, capture with
  `skyline_get_form_image` (file return), then `git checkout --` the test files. Never commit pauses
  or a demo env var (`ai/TESTING.md`, "Demos Are Temporary").
- The deck: an HTML artifact (load the `artifact-design` skill first; a slides type if the
  quickstart offers one), a dozen screens with one line each, published privately for sharing.
- The grid screenshot to feature: the fine-tune route's dialog (every section) beside the
  existing-library search's (search section alone) - the point being that the settings follow what
  the run can use.

## Tasks
- [x] Capture the screens (both wizards, the two grids, page 1 of Build Library)
- [x] Build the deck; a slide for the 2-year arc and one for what changed (C#, TorchSharp, no runtimes)
- [x] Publish and hand Brendan the link; he sends it to Mike and Bo Wen
- [ ] Brendan reviews; fix what he asks for, then share from the deck's Share menu

## Progress Log

### 2026-10-28 - Briefed

Written at the end of the #4927 session (context nearly exhausted) so a fresh session can start it.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20261028_osprey_integration_demo_deck.md` before starting work.

### 2026-10-28 evening - Captured and published

- 21 slides as a Slides artifact: cover, the two-year arc, what changed, Build Library (page 1 both
  ways, tuning runs, FASTA, modifications, Search Settings, the fine-tune grid in two columns), Osprey
  Search (data files, FASTA to predict from, existing library, Library Model, modifications, Search
  Settings, the three grids side by side, run page, the Import Peptide Search hand-off, the imported
  document), and where it stands. Fonts Domine and IBM Plex Sans; navy, warm off-white, burnt orange.
- Captures over the Skyline MCP with temporary `PauseTest()` calls in `BuildLibraryCarafeWizardTest`
  and `OspreySearchTest` (patch script and shots in `ai/.tmp/sessions/20261028-demo-deck/`), the
  test files reverted and `TestFunctional` rebuilt afterwards. Each shot upscaled 2x nearest-neighbour
  for the 1920-wide canvas; the Additional Settings grid resized to 560x1100 so every section is in
  one capture, then cropped to columns.
- Two things that did not work, now in `ai/TESTING.md` ("Demos Are Temporary"): a pause on the Osprey
  download prompt fails the test (test-mode alerts time out after 10 s), and the MCP does not list an
  alert among the open forms, so that screen is not in the deck.
- The Artifact tool in this session has no asset upload, so the screenshots are published as the
  deck's own files under `project/ds/shots/` and referenced by that path. If they do not render in
  the page, that is the first thing to revisit.
- The Build Library demo run was ended deliberately after its last screen (the grid cancelled under
  the test), so its failure is not a test result. The Osprey Search demo run was stepped through to
  the end and passed (0 failures, 826 s with the pauses; log in the session folder).

### 2026-10-28 night - Brendan's corrections, and the fine-tune route in the search wizard

- Timeline corrected on Brendan's review: all Osprey/CarafeSharp work is 2026 (OspreySharp begun
  April 2026); 2025 got AlphaPeptDeep in with the Python and Java installation solved (PR #3527, in
  Skyline 26.1) but Carafe's fine-tune, dependent on DIA-NN, stalled (PR #3549 closed unmerged); and
  #4927 is merged to master, not shipped. Every "shipped" on the cover, arc and closing slides is
  now "merged to master" / "not yet released".
- The point of the deck is the Carafe fine-tune, so the Osprey Search wizard's own fine-tune route
  is now shown: `OspreySearchTuningTest` scenario 1 with temporary pauses (`add_tuning_pauses.py` in
  the session folder) gave the Library Model page with "Fine-tune a new model on these runs" and the
  three searched runs checked, the grid on that route (every section), and the run page during the
  tuning (RT tuned, MS2 epochs) and after it. Two new slides (the fine-tune choice; the tuned
  model's result) and the three-grid comparison re-based on the search wizard alone. Now 23 slides.
- The tuned search kept 158 of 205 target peptides at 1% FDR on the subset against 11 for the
  pretrained run earlier in the day; the slide says so, with the caveat in its notes that the subset
  is tiny and the pretrained run carried the test's NCE 30.
- Test files reverted and TestFunctional rebuilt again; the tuning run was cut short after its last
  screen (not a test result).

### 2026-10-28 late - Screen dirt, and a real dataset for the result slide

- Brendan: the captures carry Windows 11 "screen dirt" (what lay behind the rounded corners and the
  blended frame); the ScreenshotManager's border repaint should apply. Done both ways:
  - Deck: `clean_borders.py` (session folder) repaints the on-screen captures the way
    `CleanupBorder11` does (white outside an 8 px rounded boundary, #707070 border, the capture
    pasted back clipped at radius 12); republished as version 7.
  - pwiz branch `Skyline/work/20261028_mcp_screenshot_border` (commit a6e149ef6e):
    `ScreenshotBorder` in `pwiz.Common.GUI` (CommonBaseUI; there is no project named CommonUtilUI,
    CommonBaseUI is CommonUtil's WinForms counterpart) holds the cleanup moved out of TestUtil;
    `ScreenCapture.GetFormImage` repaints every capture, screen copy or off-screen render; a
    `ScreenshotBorderTest` on a synthetic capture; ten callers take the class from its new home.
    Verified over the MCP: a dialog rendered off-screen now comes back with white corners and the
    standard border. `/code-review medium`: 7 findings, 4 fixed in the working tree (the unit
    test's Windows 10 branch, no repaint on a docked pane, the doc comment, a try/catch so a repaint
    failure keeps the capture), 2 dropped (TakeShot keeps its own docked-pane rule by design; the
    TestRunner Windows 11 check has no CommonBaseUI to call), 1 was the uncommitted pauses. The
    fixes built green with ScreenshotBorderTest and CodeInspection passing, and the branch is
    PR [#4934](https://github.com/ProteoWizard/pwiz/pull/4934) (two commits, label skyline),
    awaiting TeamCity and Brendan's review.
- Mike: slide 22's data is terrible. Root cause: the Stellar sDIA subset has three or four points
  across a peak and most transitions carry the red "no peak" overlay, whatever peptide is chosen.
  The completed OspreySearchPerfTest documents on this machine (Stellar, full HeLa FASTA) look the
  same. So the result slide is being recaptured from an Osprey Search wizard run on the three
  Astral HeLa runs in `D:\test\osprey-runs\astral` against the predicted library beside them
  (`add_astral_pause.py`: a temporary block in `OspreySearchTuningTest` after scenario 1; the
  search plus the chromatogram import take about an hour).
- Done (deck version 9): the search took 12 min 10 s on 32 threads (104,543 of 571,917 target
  peptides at 1% FDR, 8,936 protein groups, 118,314 library spectra), the import about 10 minutes.
  The result slide shows histone H4's VFLENVIR in replicate 49, product ions only, idotp and dotp
  0.99, every transition green. The document is kept for re-captures:
  `pwiz_tools/Skyline/TestResults/TestRunner results/OspreySearchTest-tuning/AstralDemo.sky`
  (with its 4.9 GB .skyd and, under `AstralDemo.osprey`, the three 6 GB spectra caches Osprey
  wrote there and the 0.7 GB .blib it converted the .tsv library to - about 25 GB in all, to delete
  once the deck is final).
- The fine-tune slides (Library Model, the run page during and after tuning) were recaptured with
  the branch build, so their off-screen renders now carry the repainted boundary too.
