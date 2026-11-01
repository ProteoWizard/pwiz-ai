# TODO-20261006_autoqc_import_failure_limit.md

## Branch Information
- **Branch**: `Skyline/work/20261006_autoqc_import_failure_limit`
- **Base**: `Skyline/skyline_26_1_1`
- **Created**: 2026-10-06, branch created 2026-10-08
- **Status**: In Progress. VM tests done, all commits pushed
- **Module**: `skyline`
- **PR**: [#4939](https://github.com/ProteoWizard/pwiz/pull/4939)

## Objective

Stop an AutoQC configuration with an error, and tell the user to restart AutoQC, when the Skyline it runs is gone.
Before this change it retried every import forever while it showed `Running`. The case that matters now is the
ClickOnce-to-Inno Setup handoff for Skyline (PR #4773), which removes the ClickOnce Skyline under a running AutoQC.
AutoQC finds Skyline only at startup (`Program.InitSkylineSettings`), so a restart picks up the Inno Setup install.

## Decisions

- **Skyline is gone** when any of these holds after a Skyline run
  - SkylineRunner prints `Error: Unable to find Skyline program` (the ClickOnce `.appref-ms` is gone)
  - the run fails and its `SkylineCmd.exe` or runner no longer exists (an Inno Setup or administrative Skyline
    uninstalled, or a custom folder deleted or moved)
  - the run exits with 0x80008083, the .NET launcher's code for missing runtime files. An uninstall during an import
    cannot delete the running `SkylineCmd.exe` but removes the runtime files next to it (VM test 6)

  "Could not connect to Skyline" is not counted. SkylineRunner prints it when Skyline is installed but does not start
  within 15 seconds, and the next import usually works
- **Stop at the first sign, with no retry count.** AutoQC looks for Skyline only at startup, so once Skyline is gone
  every later import fails the same way until AutoQC is restarted. The configuration turns red with a message in the
  log, and no dialog is shown
- **AutoQC does not look for Skyline again while running.** A version that searched again and retried was built and
  removed as too much change for the release. The ClickOnce-to-Inno Setup handoff happens once per computer, and a
  restart handles it
- **The message depends on the Skyline option** (`ConfigRunner.GetSkylineNotFoundMessage`)
  - Skyline and Skyline-daily say to restart AutoQC, which finds the new install
  - A custom folder, or the Skyline next to AutoQC, names the folder and says to edit the configuration. A restart
    would look in the same folder again
- **Accepted limits**
  - A Skyline installed on a network drive stops the configuration if the drive is briefly unavailable. Before this
    change the imports failed until the drive came back and then recovered. Only the Skyline program location is
    affected, not documents or raw files on a network drive. Skyline is on a network drive only if the user chose a
    folder there, as a custom Skyline folder or as the install folder of an all-users Inno Setup install
  - A .NET Framework 4.7.2 Skyline from the administrative installer, uninstalled during an import, is not detected.
    Its leftover `SkylineCmd.exe` does not return 0x80008083, so AutoQC retries the imports forever as before. A
    restart may also find that leftover `SkylineCmd.exe`
  - A .NET 10 Skyline from the installer without its own .NET runtime (`NoNetRuntime`) exits with 0x80008083 when the
    shared .NET runtime on the computer is missing or damaged. The configuration stops with the "Skyline could not be
    found" message, although the problem is the runtime. The .NET error text is not in the log
  - After Skyline is found missing, `ProcessOneFile` finishes its other steps before the configuration stops. After
    the last existing file at startup, the annotations import, the Panorama upload and the archive can each run and
    fail, and after a failed month-boundary archive the import can. Each failure adds an error line to the log
    before the stop message. Raised by Copilot on PR #4939 and left as it is for this release
  - When a configuration is stopped and started again quickly, the Log tab can go blank and then show only the new
    run. `Logger.Init` clears the Log tab's lines. This happened before this branch too, and `AutoQC.log` has every
    line (VM test 5)

## Changes

- **Detection.** `ProcessRunner.SkylineNotFound` is set when SkylineRunner prints "Unable to find Skyline program" or
  the process exits with 0x80008083. `ConfigRunner.RunProcess` sets `_skylineNotFound` after every Skyline run when
  `SkylineNotFound` is set, or when the run failed and its exe does not exist
- **Stop.** `ProcessNewFiles` checks the flag before waiting for a new file and after each import.
  `ProcessExistingFiles` checks it before each existing file and `TryReimportOldFiles` before each re-import.
  `Stop()` maps it to `RunnerStatus.Error`. `RunConfiguration` logs the message when the startup report fails
- **Messages.** Two resource strings, the restart message and the edit-the-configuration message. They are `public`
  so the test can compare the exact text
- **Log tab.** `SetConfigEnabled` passes the existing `Logger` to the new runner, so a stopped run's last lines,
  often the error, appear in the Log tab
- **`Logger.Init` (SharedBatch).** Now that a `Logger` is reused, `Init` can run while `AutoQC.log` is still open. It
  closes the file before opening it again. The open handle blocked the move of `AutoQC.log` to a backup at 10 MB.
  `Init` also locks `_uiBufferLock`, like every other use of the Log tab's lines
- **Tests.** `ProcessRunnerTest.TestSkylineNotFound` (each signal, a success that clears the flag, an unrelated
  failure, the message for each option). `ConfigManagerTest.TestEnableDisableKeepsLogger`. Each check failed with its
  code removed

## Commits

| Commit | What it did |
|---|---|
| `fae8bd230c` | The stop when Skyline is not found, the messages, the Log tab and `Logger.Init` fixes |
| `7a70f77ef8` | Copilot review. Stops in `ProcessExistingFiles` and `TryReimportOldFiles` |
| `666488994d` | `ProcessRunnerTest.cs` stored with CRLF line endings |
| `0e34cb14dc` | Exit code 0x80008083 counted as Skyline not found |

## VM results

ClickOnce test publishes to `software/AutoQC-test24` on the `AutoQC-Test` VM. Publish settings and test plan are
kept outside this repository.

**2026-10-09, 26.1.1.281 and .282, ClickOnce Skyline-daily.** The handoff, an Inno Setup uninstall, and a start
after the handoff each stopped the configuration with the message. A restart found the Inno Setup `SkylineCmd.exe`
and imported the failed file. The custom-folder message named the folder.

**2026-10-30 and 31, 26.1.1.283 and .284, configuration `Daily-Upgrade`.**

| Test | Result |
|---|---|
| 1. Inno Setup Skyline-daily upgraded in place while importing | Pass. Eight files imported and uploaded. The installer waited to replace a DLL until the imports ended |
| 2. ClickOnce Skyline-daily updated while running | On the VM, not reachable. Check for Updates on Nick's test build offers the Inno Setup handoff. The handoff during imports stopped once with the restart message, and a restart imported the rest |
| 2, again on a developer computer, 284 | Pass. ClickOnce Skyline-daily 26.1.1.159 from the real feed updated to 26.1.1.279 while importing. Four runs failed with "Could not connect to Skyline" during the update, and their three files were re-imported. Every file imported, still running, no stop message. Skyline-daily offered the update and downloaded it several times before it was installed. That is Skyline and ClickOnce, not AutoQC |
| 3. A long normal run, on 284 | Pass. 65 minutes, eight files imported and uploaded, still running |
| 4. A bad `.raw` file, then a real one | Pass. The bad file was retried and skipped, the real one imported |
| 5. Stopped and started four times | Pass. The Log tab went blank on one start (see Accepted limits) |
| 6. Skyline-daily uninstalled while existing files imported | Fail on 283. The leftover `SkylineCmd.exe` exited with 0x80008083 on every retry. Pass on 284. Stopped once, no other file attempted |

## Task Checklist

- [x] Stop with an error when Skyline is not found, with a message per Skyline option
- [x] `/code-review max` (2026-10-08) and `/code-review high` (2026-10-09, 2026-10-31), findings fixed or recorded
- [x] PR #4939 against `Skyline/skyline_26_1_1` (2026-10-29)
- [x] VM tests (above)
- [x] Push `0e34cb14dc`
- [ ] Update the PR description with the VM tests
- [x] Test 2, a ClickOnce Skyline-daily update while a configuration runs (developer computer, 2026-10-31). The VM
      checkpoint `AutoQC 284 + ClickOnce daily 279 real feed` can repeat it on the next ClickOnce Skyline-daily
- [ ] Check the PR's CI before merge

## Key Files

- `pwiz_tools/Skyline/Executables/AutoQC/AutoQC/ConfigRunner.cs` - `RunProcess`, `ProcessNewFiles`,
  `ProcessExistingFiles`, `TryReimportOldFiles`, `Stop`
- `pwiz_tools/Skyline/Executables/AutoQC/AutoQC/ProcessInfo.cs` - `ProcessRunner.SkylineNotFound`
- `pwiz_tools/Skyline/Executables/AutoQC/AutoQC/AutoQcConfigManager.cs` - `SetConfigEnabled`
- `pwiz_tools/Skyline/Executables/SharedBatch/SharedBatch/Logger.cs` - `Init`
- `pwiz_tools/Skyline/Executables/AutoQC/AutoQCTest/ProcessRunnerTest.cs`
