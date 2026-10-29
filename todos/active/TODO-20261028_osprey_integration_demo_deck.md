# TODO-osprey_integration_demo_deck.md

## Branch Information
- **Branch**: none needed (an HTML artifact, not pwiz code; a pwiz branch only if a demo pause has to be committed, which it does not)
- **Created**: 2026-10-28
- **Status**: Active (started 2026-10-28)
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
- [ ] Capture the screens (both wizards, the two grids, page 1 of Build Library)
- [ ] Build the deck; a slide for the 2-year arc and one for what changed (C#, TorchSharp, no runtimes)
- [ ] Publish and hand Brendan the link; he sends it to Mike and Bo Wen

## Progress Log

### 2026-10-28 - Briefed

Written at the end of the #4927 session (context nearly exhausted) so a fresh session can start it.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20261028_osprey_integration_demo_deck.md` before starting work.
