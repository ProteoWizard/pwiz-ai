# TODO-20261002_batch_tools_net10_fixes.md

Bring forward what is still worth having from `Skyline/work/20260823_resharper_cleanup`, which
never got a PR, onto the .NET 10 port branch.

## Branch Information
- **Branch**: `Skyline/work/20261002_batch_tools_net10_fixes`
- **Base**: `Skyline/work/20260612_net8_port` @ `2aa6888005` (PR #4619)
- **Checkout**: `C:\proj\review` (BRENDANX-UW6)
- **Module**: `skyline`
- **Created**: 2026-10-02
- **Status**: Completed
- **PR**: [#4763](https://github.com/ProteoWizard/pwiz/pull/4763) (merged 2026-10-03 into `Skyline/work/20260612_net8_port`)
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
- [x] `/code-review max`, triage
- [x] Open the PR into `Skyline/work/20260612_net8_port`, label `skyline` - #4763
- [x] CI green (no Copilot review); Brendan's 3 review comments addressed (`/pw-respond 4763`)
- [ ] Follow-up for review findings #5 and #6: `backlog/TODO-http_failure_simulator_fidelity.md` (deferred, not started)

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

### 2026-10-02 - /code-review max: 15 findings, triaged; squashed to `94ad5f6fb8`

Reviewed commit `5cd3c43a1e` (the review started before `4822e9fd60`). Its 15 findings were
checked and sorted into fix-now or drop.

**Fixed:**
* **#4 - The DNS fix was incomplete.** A name that exists but has no address record arrives as
  `ConnectionError` with an inner `SocketException` of `NoData`. Confirmed on .NET 10.0.12:
  `nonexistent.example.com`, which is `SimulateDnsFailure`'s own default host, does exactly
  that. `IsDnsResolutionFailure` now also accepts an inner `HostNotFound`, `NoData`,
  `NoRecovery` or `TryAgain`. `ConnectionRefused` stays a connection failure.
  `SimulateDnsNoDataFailure` was added, and `TestHttpClientWithProgressIntegration` covers it for
  both download and upload.
* **#9** - `SimulateConnectionFailure` was a bare `HttpRequestException`, so the non-DNS path was
  never tested with a realistic exception. It now uses the real refused shape (`ConnectionError`
  + `ConnectionRefused`).
* **#8** - `GetExpectedMessage` checked message text for status codes before checking the DNS
  shape, so a host name containing "500" would have been mistaken for HTTP 500. It now checks
  the exception shape first, using its own list of DNS shapes rather than calling the product's.
  The hard-coded `:443` was dropped.
* **#1 - LongWaitDlg hang, reproduced.** `LongWaitOperation` starts its work before `ShowDialog`
  creates the window. A fast operation (for example an unresolvable FTP host failing in ~1.5 ms)
  calls `Finish()` with no window handle, `Invoke` throws `InvalidOperationException`, and the
  task swallows it. The completion callback never runs, the dialog never closes, and SkylineBatch's
  Run buttons stay disabled. `Finish` now catches it, and the `Shown` handler closes the dialog
  when the work already completed. New `LongWaitDlgTest.TestFinishBeforeDialogShown` fails in
  12 ms against the old code (`skylinebatch-revertcheck.log`) and passes with the fix.
* **#11, #14** - Inaccurate comments (the `IsDnsResolutionFailure` doc; the `HttpClientSingleton`
  comment claiming .NET 4.7.2 limits and automatic DNS refresh).
* **#12** - The commit message was 11 lines. The branch was squashed to one commit, never pushed.

**Dropped:**
* #2 (invalid naming-pattern regex in `DataServerForm`), #3 (`GetServerFromUi` swallowing
  validation errors), #10 (`DialogResult` set off the UI thread): bugs already present in functions
  this branch only edited mechanically (lambda wrapper removal). Not this branch's subject.
* #7 - An unresolvable proxy is reported as a DNS failure of the target host. Low severity, and
  it matches what .NET Framework did for https targets.
* #13 - `FilePathControl` duplicates `UiFileUtil.OpenFile`. Calling `OpenFile` would silently
  ignore the declared `ExistingOptional` option, which nothing passes today. That is a separate
  decision.
* #15 - `IsNetworkReallyAvailable` walks the adapters twice. A performance issue outside this
  change.

**Raised with Brendan (same simulator-versus-production pattern, outside the diff):**
* #6 - Every real non-2xx response reaches users as raw "Response status code does not indicate
  success: 404 (Not Found)". The friendly 404/401/403/500/429 messages only run for the
  simulator's message-only exceptions.
* #5 - The `ConnectionLost` classification keys on IOException HResults that .NET 10 never
  produces. A real mid-download drop is rethrown raw, and WebEnabledFastaImporter's
  batch-splitting branch can never fire.

Final verification (all on `94ad5f6fb8`'s content): Skyline build;
`TestHttpClientWithProgressIntegration`, `TestPanoramaDownloadFile`, `CodeInspection`,
`TestRInstaller` pass; AutoQC 18/18 and SkylineBatch 39/39, both with `-RunInspection` at zero
warnings. Logs: `build4.log`, `tests4.log`, `tests5.log`, `autoqc5.log`, `skylinebatch5.log`.

### 2026-10-02 - PR #4763 opened

Pushed `94ad5f6fb8` and opened #4763 into `Skyline/work/20260612_net8_port` with label `skyline`.
Brendan chose to keep review findings #5 and #6 out of this PR and fix them in a follow-up:
`backlog/TODO-http_failure_simulator_fidelity.md`.

### 2026-10-02 - Review round 1 (Brendan, 3 comments) - `db27b076b5`

* `CommonException.Message` simplified to `return ExceptionDetail?.ToString() ?? base.Message;`
* Restored two `HttpClientWithProgress` lines whose only change was a dropped trailing space
* Gate: Skyline build; HTTP, Panorama, RInstaller and CodeInspection tests; AutoQC 18/18 and
  SkylineBatch 39/39 with zero inspection warnings. All 3 threads replied to and resolved.

### 2026-10-03 - CI failures untied; re-verified on a correctly primed checkout; merged port head (`df20c5bdef`)

**TeamCity on `db27b076b5`:**
* "Skyline code inspection" error: since #4685 this is a step inside the Skyline Windows .NET
  build (4199254), not a separate config. inspectcode's internal build hit
  `MSB3021 ... Google.Protobuf.dll ... Access to the path is denied` on agent
  `pwiz-windows-i-097d4f6119150d8d6` and exited with code 4 before inspecting anything.
* Perf/Tutorial: `TestDiaTtofDiaUmpireTutorial` (`Expected:<14107>. Actual:<14094>`) also fails
  on the port head build (4200795) and on every PR into it that was checked.
  `TestAlphaPeptDeepBuildLibrary` (SQLite `CantOpen` on the existing `rat_consensus_final_true_lib.blib`)
  also failed on #4758, which does not contain this PR.

**Mistake recorded:** all verification up to this point ran in `C:\proj\review` while it was still
primed for master (Boost.Build `b.bat`, net472 leftovers). That gave 4648 bogus inspection issues
and a stale net472 SkylineCmd.exe, and it should have stopped the work rather than been explained
away. Brendan re-primed it (`clean.bat -cpp`, port-style `b.bat`/`bs.bat`/`bo.bat`, `.\bs.bat`).
The guidance is now in `ai/docs/build-and-test-guide.md` ("Pick a Checkout Primed for the Branch")
and `ai/CRITICAL-RULES.md`. Next mistake: running `Build-Skyline.ps1` without `-VendorLicenses`
rebuilt pwiz-sharp tools without vendor support over the `bs.bat` vendor build, and Skyline then
failed with MSB3030 copy errors. That is also in the guide now.

**Re-verified on the primed checkout** (Release, `-VendorLicenses`), after merging
`origin/Skyline/work/20260612_net8_port` (`e60a58be42`, adds #4751 and #4758) into the branch:
* Build passes. `TestHttpClientWithProgressIntegration`, `TestPanoramaDownloadFile`,
  `TestRInstaller`, `CodeInspection` pass.
* `tcinspect.ps1` (the CI script): "success - No inspections at WARNING or above".
  (`Build-Skyline.ps1 -RunInspection` still reports 547 unresolved-symbol artifacts, none in PR
  files. The guide now says to use `tcinspect.ps1`.)
* AutoQC 18/18 and SkylineBatch 39/39, both inspection-clean.
* `TestAlphaPeptDeepBuildLibrary` fails, and **fails on the port head control too**: on `e60a58be42`
  with no PR code in the same checkout, 1 pass and 1 fail. It is intermittent on the port branch,
  not caused by this PR. A first hypothesis (missing #4751 stale-BlibBuild fix) was disproven by
  the merged branch still failing.

Logs: `ai/.tmp/sessions/20261002-batchfix/reverify/`, `control-porthead/`, `loop-porthead/`,
`tcinspect-pr-merged/`.

### 2026-10-03 - Merged

PR #4763 merged into `Skyline/work/20260612_net8_port` as `077ebe41e8`. It reaches master with #4619.
TeamCity on the final head `df20c5bdef`: Skyline Windows .NET 1806 tests passed, Skyline code
inspection "No inspections at WARNING or above", Core Windows .NET and Docker/Wine green.
Perf/Tutorial was not re-run on the final head; its last run failed only on
`TestDiaTtofDiaUmpireTutorial` and `TestAlphaPeptDeepBuildLibrary`, both shown to fail on the port
branch without this PR.

Shipped: DNS failures classified correctly on .NET 10 (`NameResolutionError`, or inner
`HostNotFound`/`NoData`/`NoRecovery`/`TryAgain`) with realistic DNS and connection-failure
simulations; the `LongWaitDlg` hang fix with `TestFinishBeforeDialogShown`; the shared Debug/Release
SkylineCmd lookup for the AutoQC and SkylineBatch tests; zero ReSharper warnings in both batch-tool
solutions; and the remaining salvage from `Skyline/work/20260823_resharper_cleanup`.

Deferred:
* Review findings #5 (ConnectionLost never classified on .NET 10) and #6 (raw status-code text
  instead of the friendly messages): `backlog/TODO-http_failure_simulator_fidelity.md`.
* `TestAlphaPeptDeepBuildLibrary` intermittent SQLite `CantOpen` on the port branch: reproduced
  locally in about 4 minutes, not yet investigated.
