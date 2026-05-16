# Add --start-page=true|false Skyline launch flag for scripted launches

## Branch Information
- **Branch**: `Skyline/work/20260515_start_page_launch_flag`
- **Base**: `master`
- **Created**: 2026-05-15
- **Status**: In Progress
- **GitHub Issue**: [#4216](https://github.com/ProteoWizard/pwiz/issues/4216)
- **PR**: [#4217](https://github.com/ProteoWizard/pwiz/pull/4217)

## Objective

Add a `--start-page=true|false` command-line argument to `Skyline.exe` / `Skyline-daily.exe` that controls whether the StartPage shows on launch, independent of `Settings.Default.ShowStartupForm` and independent of `--opendoc`.

Today's behavior is fragile: scripted launches without a document get the StartPage they never asked for, and `--opendoc` (no path) happens to skip the StartPage as a semantic accident. The new flag makes the intent explicit and orthogonal to `--opendoc`.

## Tasks

- [x] Parse `--start-page=true|false` into `Program.StartPageOverride`; reject bare `--start-page` and unparseable values via `ParseStartPageArg`.
- [x] Broaden GUI-launch detection so `--start-page=...` keeps us out of the CLI branch (`isGuiLaunch = openDoc || StartPageOverride.HasValue`).
- [x] Fold `StartPageOverride` into the StartPage decision; activation data and `--opendoc` still force MainWindow at startup.
- [x] In `Skyline.OnShown`, after `LoadFile`, call `OpenStartPage()` when an `--opendoc` launch sets `Program.StartPageOverride == true`.
- [x] Extend Skyline.cs arg filter so `--start-page=...` doesn't end up as `_fileToOpen`.
- [x] Unit test `Program.ParseStartPageArg` for absent/valid/invalid/multi-arg cases (`Test/StartPageArgTest.cs`).
- [x] Functional tests for override semantics, routed through `Program.Main` via `AbstractFunctionalTest.LaunchArgs`:
      override=true beats `ShowStartupForm=false`; override=false beats `ShowStartupForm=true`;
      `--opendoc --start-page=true` opens MainWindow (empty doc, null path) with StartPage modal on top.
- [x] PR with `Fixes #4216` (PR #4217).

## Manual smoke checks before merge

The functional tests cover most of the issue's test matrix end-to-end via
`AbstractFunctionalTest.LaunchArgs` (routed into `Program.Main`). The
following two cases are still worth a hand sanity-check from a developer's
`Bin\` folder, since the test framework does not exercise actual file I/O
through `--opendoc PATH` and does not run the parse-error stderr exit path:

- `Skyline.exe --opendoc <path> --start-page=false` -- the document loads, no StartPage modal (parity with `--opendoc <path>` alone).
- `Skyline.exe --start-page` and `Skyline.exe --start-page=foo` -- clean stderr error, exit code 1, no UI launch.

## Progress Log

### 2026-05-15 - Session Start

Starting work on this issue. Branch created from master (post-merge of `Skyline/work/20260514_osprey_library_decoy_catchup` / PR #4214).

### 2026-05-15 - Implementation complete

Implemented the flag end-to-end:
- `Program.START_PAGE_ARG = "--start-page"`, `Program.StartPageOverride` static, and `Program.ParseStartPageArg` helper.
- `Program.Main` parses the flag (writing a stderr message and returning `EXIT_CODE_FAILURE_TO_START` on parse error), broadens GUI detection, and folds the override into the startup StartPage decision.
- `SkylineWindow.OnShown` calls `OpenStartPage()` after `LoadFile` when an `--opendoc` launch had `StartPageOverride == true`, using `_fileToOpen != null` (captured before clear) to discriminate the opendoc path from the StartPage-initiated SkylineWindow construction.
- Resource strings added in `SkylineResources.resx` (+ `.ja` / `.zh-CHS`).
- Three new tests pass: `TestParseStartPageArg`, `TestStartPageOverrideTrue`, `TestStartPageOverrideFalse`. Existing StartPage tests still pass.
