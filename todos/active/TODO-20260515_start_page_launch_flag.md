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
- [x] Functional tests for override semantics: override=true forces StartPage even with `ShowStartupForm=false`; override=false forces MainWindow even with `ShowStartupForm=true` (`TestFunctional/StartPageOverrideFlagTest.cs`).
- [ ] PR with `Fixes #4216`.

## Manual smoke checks before PR

The functional tests cover the override-vs-Setting interaction. The arg-driven launch
flow (Program.Main parsing real command-line args) is not exercised by the test
framework, so the following combinations should be sanity-checked by hand once the
build is in a developer's Bin folder:

- `Skyline.exe --start-page=false` — empty MainWindow, no StartPage, no file.
- `Skyline.exe --start-page=true` (with `ShowStartupForm=false`) — StartPage shown.
- `Skyline.exe --opendoc <path> --start-page=true` — document loads, then StartPage as modal.
- `Skyline.exe --opendoc <path> --start-page=false` — document loads, no StartPage.
- `Skyline.exe --start-page` and `Skyline.exe --start-page=foo` — clean stderr error, exit 1, no UI.

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
