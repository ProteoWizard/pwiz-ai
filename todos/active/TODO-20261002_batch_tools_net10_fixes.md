# TODO-20261002_batch_tools_net10_fixes.md

Bring forward what is still worth having from `Skyline/work/20260823_resharper_cleanup`, which
never got a PR, onto the .NET 10 port branch.

## Branch Information
- **Branch**: `Skyline/work/20261002_batch_tools_net10_fixes`
- **Base**: `Skyline/work/20260612_net8_port` @ `2aa6888005` (PR #4619)
- **Checkout**: `C:\proj\review` (BRENDANX-UW6)
- **Module**: `skyline`
- **Created**: 2026-10-02
- **Status**: In Progress - 2 commits (`5cd3c43a1e`, `4822e9fd60`), local; both batch-tool solutions inspection-clean and green; /code-review max running
- **PR**: (pending)
- **Salvaged from**: `completed/TODO-20260823_resharper_cleanup.md` (superseded by Matt's #4685,
  `TODO-20260917_resharper_warning_reduction.md`)

## How the remaining changes were found (2026-10-02)

Cherry-picked the 8 commits on `origin/Skyline/work/20260823_resharper_cleanup` that had not
landed through #4648, in order, onto the port branch head (`2aa6888005`, which includes #4685),
then diffed against the head:

* Most of it was already there. The AutoQC hang fix (`47513caf32`, the `AssemblyInitialize` in
  `AutoQCTestSetup.cs`) came through #4648. Over 20 files of warning cleanup were already
  present, and `38eb21a434` was present in full.
* Everything that conflicted was net472-only (`d75c9b1b8a`'s net472 build fixes, `.Cast<>()`
  and `#if NET472` workarounds). The batch tools and `CommonUtil` now build net10 only, so the
  head's version was kept every time.
* Left over: 8 files, +65/-13. Patch at
  `ai/.tmp/resharper_cleanup-remaining-vs-port-2aa6888005.patch` (BRENDANX-UW6).

## Changes

1. **DNS failures reported as connection failures** (from `1a99335fa3`) - the one user-visible bug.
   `HttpClientWithProgress.MapHttpException` detected DNS failure only through .NET Framework's
   inner `WebException` (`NameResolutionFailure`). SocketsHttpHandler never produces one, so on
   net10 a host that does not resolve was reported as "Failed to connect... check your network"
   instead of "Failed to resolve host... check your DNS". Now keyed on
   `HttpRequestError.NameResolutionError` or an inner `SocketException` of `HostNotFound`.
   The real shape was confirmed on .NET 10.0.12 against `asdfdsafads-skyline-test.invalid`:
   `NameResolutionError`, inner `SocketException`, `HostNotFound`.
2. **Why no test caught it**: `HttpClientTestHelper.SimulateDnsFailure` built the .NET Framework
   shape, so the simulated DNS tests passed on net10 while every real DNS failure was
   misreported. The simulation now builds the SocketsHttpHandler shape, and the expected-message
   logic keys on `HttpRequestError`. The `WebException` check in production code was removed, so
   the existing tests (`TestHttpClientWithProgressIntegration`, `PanoramaClientDownloadTest`)
   now exercise the real path.
3. `AutoQCStarter.GetLogLocation`: `Assembly.CodeBase` (obsolete, SYSLIB0012, throws for a
   single-file publish) replaced by `AppContext.BaseDirectory`.
4. `CommonException.Message`: `ExceptionDetail.ToString() ?? base.Message`, since `ToString()` is
   annotated `string?`.
5. Mechanical cleanup outside `Skyline.sln`, which #4685's inspection does not see: redundant
   casts in `FilePathControl`, `FileUtil`, `Helpers`; `new Action(...)` wrappers in
   `LongWaitDlg` and `DataServerForm`.

All net472 branches and two-target comments from the original commits were dropped.

## Tasks
- [x] Branch off the port head, apply the remaining diff, strip net472 code
- [x] Build Skyline (`-SourceRoot C:/proj/review`)
- [x] Build AutoQC and SkylineBatch
- [x] Run `TestHttpClientWithProgressIntegration` and `CodeInspection`
- [x] Run the AutoQC and SkylineBatch suites
- [ ] `/code-review max`, triage
- [ ] Open the PR into `Skyline/work/20260612_net8_port`, label `skyline`

## Progress Log

### 2026-10-02 - Branch created

Built and tested on BRENDANX-UW6. Logs are in `ai/.tmp/sessions/20261002-batchfix/`.

* Skyline Debug build passed. `TestHttpClientWithProgressIntegration`, `TestPanoramaDownloadFile`
  and `CodeInspection` all pass (`tests3.log`).
* **The new simulation catches the bug.** With the old WebException-only check temporarily put
  back, `TestHttpClientWithProgressIntegration` failed with the user-visible symptom: expected
  "Failed to resolve host nonexistent.example.com...", got "Failed to connect to
  nonexistent.example.com..." (`tests-revertcheck.log`).
* AutoQC: 18/18 passed.
* SkylineBatch: 27/38 passed. The same 11 tests fail on the unchanged base
  (`skylinebatch-base.log`), so the failures are environmental and not caused by this branch.
  They look for SkylineCmd under `bin\Release\net10.0-windows` (only Debug was built here) and
  for a missing `Test\emptyTemplate.sky`. The run also writes `*_replaced.bcfg` files into
  `SkylineBatchTest/Test/BcfgTestFiles`, which had to be cleaned up afterwards.
* Quick inspection reported 46 issues, none in a changed file. All are unresolved-reference
  errors in `CommonUtil` (JetBrains annotations, Newtonsoft, ProtectedData), the artifact
  described in #4685.

### 2026-10-02 - Batch-tool tests fixed for a Debug build; both solutions inspection-clean (`4822e9fd60`)

Brendan asked whether the 11 SkylineBatch failures could be fixed so the suite passes on the
Debug build. All 11 came from one cause, including the missing `emptyTemplate.sky`, which was
a downstream effect.

* `SkylineBatchTest.TestUtils.GetSkylineDir` only searched Release output folders (its doc
  comment claimed Debug was searched too). The Debug build is at `bin\x64\Debug\net10.0-windows`
  and `bin\staging\Debug`.
* `AutoQCTest.TestUtils.GetSkylineBinDirectory` searched both and picked the newest, but still
  listed the net472 `bin\x64\Release` and `bin\x64\Debug`. This checkout has a stale net472
  `SkylineCmd.exe` there from 2026-08-17. It went unused only because the new build was newer.
* Fixed by adding `ExtensionTestContext.GetSkylineBinDirectory()` in SharedBatchTest: the
  newest SkylineCmd.exe across `bin\<Config>\net10.0-windows`, `bin\x64\<Config>\net10.0-windows`
  and `bin\staging\<Config>` for Release and Debug, with no net472 paths. Both test projects now
  call it. AutoQC still throws when nothing is found; SkylineBatch falls back to the Release path.
* Result: **SkylineBatch 38/38** (was 27/38) and AutoQC 18/18, both on a Debug-only tree.

Also cleared the last ReSharper warnings in both batch-tool solutions, so `-RunInspection` passes
with zero warnings on both:

* `ServicePointManager.SecurityProtocol` (SYSLIB0014) in AutoQC and SkylineBatch `Program.cs`:
  removed, as #4697 did for Skyline and SkylineTester. On .NET it has no effect on HttpClient.
* `ProgramLog.GetProgramLogFilePath`: dropped an always-true `repository != null`. AutoQC's own
  copy of that method was never called, so it was deleted, along with the usings it alone needed.
* `TestContext.TestDir` (obsolete) changed to `TestRunDirectory`, its documented replacement
  (MSTest sets both to the same directory).
* Redundant `(long?)` casts in `DownloadDlg` and `Server`; unused usings in `FilePathControl`
  and `Server`.

Logs: `ai/.tmp/sessions/20261002-batchfix/autoqc4.log`, `skylinebatch3.log`.
