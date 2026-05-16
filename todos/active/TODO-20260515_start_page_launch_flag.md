# Add --start-page=true|false Skyline launch flag for scripted launches

## Branch Information
- **Branch**: `Skyline/work/20260515_start_page_launch_flag`
- **Base**: `master`
- **Created**: 2026-05-15
- **Status**: In Progress
- **GitHub Issue**: [#4216](https://github.com/ProteoWizard/pwiz/issues/4216)
- **PR**: (pending)

## Objective

Add a `--start-page=true|false` command-line argument to `Skyline.exe` / `Skyline-daily.exe` that controls whether the StartPage shows on launch, independent of `Settings.Default.ShowStartupForm` and independent of `--opendoc`.

Today's behavior is fragile: scripted launches without a document get the StartPage they never asked for, and `--opendoc` (no path) happens to skip the StartPage as a semantic accident. The new flag makes the intent explicit and orthogonal to `--opendoc`.

## Tasks

- [ ] Parse `--start-page=true|false` in `Program.cs:182` into `bool? startPageOverride`; reject `--start-page` with no value and unparseable values.
- [ ] Broaden GUI-launch detection at `Program.cs:184` so `--start-page=...` keeps us out of the CLI branch: `isGuiLaunch = openDoc || startPageOverride.HasValue`.
- [ ] Fold `startPageOverride` into the StartPage decision at `Program.cs:322` so it overrides every other condition.
- [ ] In `Skyline.cs:OnShown`, after the existing `LoadFile` block, call `OpenStartPage()` when `startPageOverride == true` and a file was just loaded.
- [ ] Extend `Skyline.cs:270` arg filter so `--start-page=...` doesn't end up as `_fileToOpen`.
- [ ] Add `TestFunctional` coverage for: `--start-page=false` alone, `--start-page=true` alone with `ShowStartupForm=false`, `--opendoc PATH --start-page=true`, `--opendoc PATH --start-page=false`, invalid values.

## Progress Log

### 2026-05-15 - Session Start

Starting work on this issue. Branch created from master (post-merge of `Skyline/work/20260514_osprey_library_decoy_catchup` / PR #4214).
