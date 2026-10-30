# TODO-20261006_autoqc_import_failure_limit.md

## Branch Information
- **Branch**: `Skyline/work/20261006_autoqc_import_failure_limit`
- **Base**: `Skyline/skyline_26_1_1`, rebased on 2026-10-29 onto `02c0b72390` (#4932). Commit `fae8bd230c`, pushed
- **Created**: 2026-10-06, branch created 2026-10-08
- **Status**: In Progress
- **Module**: `skyline`
- **PR**: (pending)

## Objective

Stop an AutoQC configuration with an error, and tell the user to restart AutoQC, when the Skyline it runs is gone.
Before this change it retried every import forever while it showed `Running`. The case that matters now is the
ClickOnce-to-Inno Setup handoff for Skyline (PR #4773), which removes the ClickOnce Skyline under a running AutoQC.
AutoQC finds Skyline only at startup, so a restart is what picks up the Inno Setup install.

PR #4771 (`TODO-20261004_autoqc_find_inno_skyline.md`) lets AutoQC find an Inno Setup Skyline at startup. This branch
started on it and was rebased onto `skyline_26_1_1` after #4771 was squash-merged.

## Problem

AutoQC finds Skyline only at startup (`Program.InitSkylineSettings`). After the handoff removed the ClickOnce
Skyline-daily, every import failed with `Error: Unable to find Skyline program` from `SkylineDailyRunner.exe` and was
retried with no limit, while the configuration showed `Running`. A restart found the Inno Setup install and imported
the file. Seen on the `AutoQC-Test` VM on 2026-10-06.

## Decisions

- **Skyline is gone** when SkylineRunner prints `Error: Unable to find Skyline program` (the ClickOnce `.appref-ms` is
  gone), or a run fails and its `SkylineCmd.exe` or runner no longer exists (an Inno Setup or administrative Skyline
  uninstalled, or a custom folder deleted or moved). "Could not connect to Skyline" is not counted. The runner prints
  it when Skyline is installed but does not connect to its pipe in time
- **Stop at the first sign, with no retry count.** AutoQC finds Skyline only at startup, so both signals last until a
  restart or a configuration edit and retrying cannot succeed. The stop is `RunnerStatus.Error` and a log line, no
  dialog, and unchecks the configuration. The VM tests of Skyline updates while AutoQC runs check that an update
  does not briefly look the same
- **No search for Skyline again.** Searching again and retrying, per configuration, was built and removed as too much
  for the release. The handoff happens once. Worth revisiting only if installs move again
- **The message depends on the Skyline option** (`ConfigRunner.GetSkylineNotFoundMessage`). Skyline and
  Skyline-daily say to restart AutoQC, which finds the new install. Editing the configuration does not help, because
  the form uses the paths `FindSkyline` saved at startup. A custom folder or the Skyline next to AutoQC names the
  folder and says to edit the configuration, because a restart builds the same path
- **Local disk assumed (2026-10-29).** A Skyline on a network share that drops stops the configuration, where it used
  to recover when the share came back. Skipping UNC paths and `DriveType.Network` drives was left out. Only the
  Skyline program path is checked, so data files and documents on a network drive are not affected. Skyline is on a
  share only in a custom folder put there (the portable zip, a copied administrative install, a WiX MSI installed
  there) or an all-users Inno Setup install into a folder chosen on the installer's folder page. ClickOnce and
  per-user Inno Setup installs are always under `%LOCALAPPDATA%`
- **Left as they were (2026-10-29).** Two limits of `Logger.Init` that the shared logger does not change
  - `Init` clears the Log tab buffer, so a configuration restarted within one 500 ms Log tab update of stopping does
    not show the stopped run's last lines there. They are in `AutoQC.log`. Before, they were lost on every stop
  - `Init` replaces `_logBuffer`, the lines not yet written because `AutoQC.log` was unavailable. A restart loses
    them, as it did when each enable made a new `Logger`

## Changes

- **Detection.** `ProcessRunner.SkylineNotFound` is set from the runner's "Unable to find Skyline program" line.
  `ConfigRunner.RunProcess` sets `_skylineNotFound` after every Skyline run (imports, the startup report, Panorama
  uploads, annotations, archives), from that line or a failed run whose exe does not exist. It is checked once per
  `ProcessNewFiles` pass and stops the configuration, so it is never cleared in practice
- **Stop.** `ProcessNewFiles` stops after its import section when the flag is set, and `Stop()` maps it to
  `RunnerStatus.Error`. `RunConfiguration` logs the same message when the startup report fails for this reason
- **Messages.** Resource strings `ConfigRunner_GetSkylineNotFoundMessage_..._Restart_AutoQC_` and
  `..._Edit_the_configuration_`, made `public` so the test compares the exact text, as `cce89ac809` (#3165) did
- `Program.LogCustomSkylineCmd` logs the folder, not the `SkylineCmd.exe` path
- **Log tab fix (existing bug).** A configuration that stops disables itself, which replaces its runner. The new
  runner used to get a new `Logger`, so the last lines of the stopped run, often the error, stayed in the old
  `Logger` and never appeared in the Log tab (they were in `AutoQC.log`). `SetConfigEnabled` now passes the existing
  `Logger` to the new runner, and the Log tab shows those lines as soon as the configuration stops
- **`Logger.Init` (SharedBatch).** With a shared `Logger`, `Init()` can run while its `_fileStream` is still open.
  It replaced the stream without closing it, leaving a read handle on `AutoQC.log` until GC that blocked the 10 MB
  rotation. It now closes the stream first. It also locks `_uiBufferLock`, as every other `_uiBuffer` use does,
  instead of `_uiBuffer`, an existing race with `DisplayLogFromFile`. Nothing reads `_fileStream`, so a stream closed
  early does not affect logging or the Log tab
- **Tests.** `ProcessRunnerTest.TestSkylineNotFound` (the runner line, a real `ConfigRunner` with a missing exe, the
  runner line through `cmd.exe`, a success that clears the flag, an unrelated failure, the message for each Skyline
  option). `ConfigManagerTest.TestEnableDisableKeepsLogger` (the same `Logger` after enabling and disabling, no open
  handle after `Init` twice and `Close`). Each check failed with its code removed

## VM results (2026-10-09)

ClickOnce test publishes to `software/AutoQC-test24`, signed with the self-signed test key: 26.1.1.281, then
26.1.1.282 with the per-option message. Starting checkpoint `AutoQC 279 + ClickOnce daily`.

| Test | Result |
|---|---|
| Handoff with the configuration running, then a raw file | Stopped on the first failure ("Unable to find Skyline program"), red, message in the Log tab |
| Restart, then start the configuration | Found the Inno Setup `SkylineCmd.exe`. The failed file imported |
| Start after the handoff without a restart | The startup report failed, then the stop message |
| Inno Setup Skyline-daily uninstalled while running | Stopped on the first failure ("cannot find the file"), then the message |
| Start with no Skyline installed | The existing validation dialog. No new code involved |
| Log tab | Showed the stop message and "Finished running configuration." after it in every stop |
| 282, Skyline-daily option | Restart message |
| 282, custom folder uninstalled | Message naming `...\AppData\Local\Programs\Skyline-daily` |

## Task Checklist

- [x] Create the branch
- [x] Stop with an error when Skyline is not found, and test it
- [x] `/code-review max` (2026-10-08), and fix findings 3, 5, 8, 9, 12, 15 and the Log tab (4)
- [x] Per-option message (restart, or edit the custom folder)
- [x] VM tests on 281 and 282 (see VM results)
- [x] `/code-review high` (2026-10-09). No defects. An independent review of the shared `Logger` led to the `Logger.Init`
      fix
- [x] Commit
- [x] Rebase onto `Skyline/skyline_26_1_1` after #4771 is squash-merged
- [ ] PR against `Skyline/skyline_26_1_1`

## Key Files

- `pwiz_tools/Skyline/Executables/AutoQC/AutoQC/ConfigRunner.cs` - `RunProcess`, `ProcessNewFiles`, `RunConfiguration`,
  `Stop`
- `pwiz_tools/Skyline/Executables/AutoQC/AutoQC/ProcessInfo.cs` - `ProcessRunner.DetectError`
- `pwiz_tools/Skyline/Executables/AutoQC/AutoQC/AutoQcConfigManager.cs` - `SetConfigEnabled`, `AddConfig`
- `pwiz_tools/Skyline/Executables/AutoQC/AutoQC/MainForm.cs` - `OutputLog`, the 500 ms Log tab timer
- `pwiz_tools/Skyline/Executables/SharedBatch/SharedBatch/Logger.cs` - `Init`, `Close`, `_uiBuffer`
- `pwiz_tools/Skyline/Executables/SkylineRunner/Program.cs` - the runner messages
- `pwiz_tools/Skyline/Executables/AutoQC/AutoQCTest/ProcessRunnerTest.cs`
