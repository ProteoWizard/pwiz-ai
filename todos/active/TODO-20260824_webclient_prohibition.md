# TODO-20260824_webclient_prohibition.md

## Branch Information
- **Branch**: `Skyline/work/20260824_webclient_prohibition`
- **Base**: `master`
- **Created**: 2026-08-24
- **Status**: In Progress
- **GitHub Issue**: (none)
- **Module**: `skyline`
- **PR**: (pending)

## Objective

Finish the WebClient to HttpClient migration in the batch tools (SkylineBatch,
AutoQC, SharedBatch) and add the `CodeInspectionTest` rule that stops new
`WebClient` uses from appearing.

This is **Phase 2** of the migration, the phase this TODO was written for as
`TODO-tools_webclient_replacement.md` in the backlog. Phase 1 (core Skyline.exe,
`.skyp`, PanoramaClient) is on master already as PRs
[#3636](https://github.com/ProteoWizard/pwiz/pull/3636),
[#3656](https://github.com/ProteoWizard/pwiz/pull/3656) and
[#3658](https://github.com/ProteoWizard/pwiz/pull/3658), with TODOs in
`completed/2025/10/`.

## Why This Targets master, Not the .NET Port

The work was originally done inside `Skyline/work/20260823_resharper_cleanup`,
which is based on the .NET port branch, because `WebClient` is obsolete on modern
.NET (SYSLIB0014) and had to go before the port could build clean.

It belongs on master instead. The migration is something the project wanted
anyway on net472 - the 2025 migration set `HttpClientWithProgress` as the project
standard and simply never finished the batch tools - and landing it on master
means the port inherits it rather than carrying it. Keeping it on the port branch
would also mean the prohibition rule does not protect master, which is exactly
where the July 2026 regression (a new `WebClient` in the DIA-NN test download)
appeared.

The branch was extracted onto a master base on 2026-08-24. See "Extraction
Cleanup" below for what that extraction got wrong and how it was fixed.

## What Is Done

### WebClient migration (commit `Completed the WebClient migration in SkylineBatch and enforced it`)
- [x] `WebDownloadClient.DownloadAsync` migrated to `HttpClientWithProgress`
- [x] `SkylineBatch/DownloadDlg.cs` migrated, sharing a new
      `DownloadProgressMonitor` that adapts `HttpClientWithProgress` to the
      percent callback the dialog wants and carries the cancellation token
- [x] `SkylineBatch/Server.cs` migrated
- [x] DIA-NN test download in `TestPerf/DiannSearchLFQbenchTest.cs` migrated -
      this one had added a *new* `WebClient` in July 2026, nine months after the
      migration meant to remove them
- [x] `CodeInspectionTest` prohibition added (details below)

### Test reliability (commit `Fixed the batch-tool functional tests hanging without a Skyline installation`)
- [x] Modal `FindSkyline` prompt returns early under `FunctionalTest`, so the
      suites no longer hang waiting on a dialog nobody can answer
- [x] `TestAdminSkylineCmdPath` seam plus assembly setup for both suites
      (`SkylineBatchTestSetup.cs`, `AutoQCTestSetup.cs`)
- [x] `RInstallations.TestRVersions` made a fallback; `RDirs` NRE fixed
- [x] Null combo-box selections guarded in AutoQC, null paths in CommonUtil

## The Prohibition Rule

Added to `pwiz_tools/Skyline/Test/CodeInspectionTest.cs`:

- Pattern is `new\s+WebClient\s*\(` - **construction**, not the identifier. A
  good deal of code holds other download clients in a variable named
  `webClient`, and those are not what this is about.
- `ignoredDirectories` is `null`, so it applies everywhere the inspection scans.
  `NonSkylineDirectories()` would have exempted `Executables`, which is precisely
  where the migration was missed.
- **No inline opt-out.** Several inspections in this file can be waived with a
  magic comment, which suits rules that have occasional legitimate exceptions.
  This one does not: an inline opt-out is a silent route back to `WebClient`, and
  a silent route back is how the original migration lost track of the uses it
  left behind. An exception requires editing the test, which puts it in front of
  a reviewer.
- **Tolerance is 3**, the count of known remaining uses inside the scan root
  (`pwiz_tools/Skyline`, per `GetCodeBaseRoot`). The tolerance mechanism warns
  when *fewer* than the tolerated number are found, so the number cannot silently
  drift upward, and it is the only thing tracking the remaining three.

Note that `pwiz_tools/Bumbershoot/idpicker/Deploy/SetupDeployProject.cs` also
constructs a `WebClient`, but it is outside the scan root and so is not counted.

## What Remains (Phases 3 and 4 - Not In This Branch)

These are the three uses the tolerance of 3 is tracking. Each one lowers the
number when migrated.

- [ ] **`SkylineNightly/Nightly.cs`** and **`SkylineNightlyShim/Program.cs`** -
      may not have `HttpClientWithProgress` available. The Shim especially is a
      deliberately tiny program that runs on developer machines during nightly
      testing, only to check that SkylineNightly itself is current; plain
      `HttpClient` with much simpler handling is likely the right answer there
      rather than the full wrapper.
- [ ] **`Executables/Installer/SetupDeployProject.cs`** - the installer strategy
      is expected to change wholesale with the .NET port, so migrating it now
      would likely be wasted work.

Out of scope entirely: `pwiz_tools/Bumbershoot/` (not Skyline, outside the
inspection's scan root).

## Extraction Cleanup

The 2026-08-24 extraction moved the WebClient work onto a master base but carried
along four `CodeInspectionTest.cs` changes that only make sense on the .NET port
branch, where `CommonUtil` has been split into `CommonUtil` + `CommonBaseUI` (PR
[#4587](https://github.com/ProteoWizard/pwiz/pull/4587), merged to
`Skyline/work/20260612_net8_port`, **not** to master). On master these would have
failed outright:

| Carried-over change | Why it breaks on master |
|---|---|
| `Directory.GetFiles(...Shared\CommonBaseUI...)` in the file scan | That directory does not exist on master - `DirectoryNotFoundException` |
| "CommonUtil must not depend on WinForms" inspection, tolerance 0 | Master's `CommonUtil` still has 17 files matching, since the split has not landed |
| `RequiredPathMasks` plumbing on `PatternDetails` / `AddTextInspection` | Only consumer was the rule above; dead code without it |
| `zh-CHS` changed to `zh-Hans` | Culture-name change that belongs with the port |
| `Kernel32` added to the PInvoke assembly scan | The namespace spans two assemblies only after the split |

All five were reverted to master's form on 2026-09-09, leaving
`CodeInspectionTest.cs` differing from master **only** by the WebClient rule.
They should be re-applied on the port branch, where they are correct and needed.

## Verification

- [x] Rule logic checked against the tree by hand: `new\s+WebClient\s*\(` matches
      exactly 3 files inside `pwiz_tools/Skyline` (Installer, SkylineNightly,
      SkylineNightlyShim), matching the tolerance
- [x] `CodeInspectionTest.cs` diff against master reviewed - WebClient rule only
- [ ] `CodeInspection` test run locally (blocked: the `pwiz` checkout has no
      native C++/CLI bindings built; a `quickbuild.bat` run is required first)
- [ ] TeamCity green
- [ ] `/code-review max` findings triaged

## References

- Phase 1 TODOs: `completed/2025/10/TODO-20251010_webclient_replacement.md`,
  `TODO-20251019_skyp_webclient_replacement.md`,
  `TODO-20251023_panorama_webclient_replacement.md`
- Sibling branch holding the same work on the port base:
  `Skyline/work/20260823_resharper_cleanup` (see
  `TODO-20260823_resharper_cleanup.md`)
- Related backlog: `TODO-httpclient_to_progress_continued.md` (core Skyline
  Ardia + `HttpWebRequest`), `TODO-batch_tools_ci_integration.md` (TeamCity
  coverage for the batch tools)
- `HttpClientWithProgress.cs` - the project standard wrapper
- `HttpClientTestHelper.cs` - test infrastructure from Phase 1
