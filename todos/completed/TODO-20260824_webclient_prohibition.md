# TODO-20260824_webclient_prohibition.md

## Branch Information
- **Branch**: `Skyline/work/20260824_webclient_prohibition`
- **Base**: `master`
- **Created**: 2026-08-24
- **Status**: Completed
- **GitHub Issue**: (none)
- **Module**: `skyline`
- **PR**: [#4648](https://github.com/ProteoWizard/pwiz/pull/4648) (merged 2026-09-10)

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

- Pattern is `new\s+(System\.Net\.)?WebClient\s*[({]` - **construction**, not the
  identifier. A good deal of code holds other download clients in a variable named
  `webClient`, and those are not what this is about. It covers the fully-qualified
  name and the object-initializer form because this migration removed
  `using System.Net;` from the files it touched (see Code Review Triage).
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
  (`pwiz_tools/Skyline` per `GetCodeBaseRoot`, plus `Shared/Common` and
  `Shared/CommonUtil`). The tolerance mechanism warns
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
along five `CodeInspectionTest.cs` changes that only make sense on the .NET port
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

- [x] `CodeInspectionTest.cs` diff against master reviewed - WebClient rule only
- [x] Native build completed in this checkout (`quickbuild.bat address-model=64
      --i-agree-to-the-vendor-licenses --no-tests`; `bs.bat` is the .NET-port entry
      point and does not apply on master)
- [x] `CodeInspection` passes; tolerated count of 3 matches the tree
- [x] `Skyline.sln`, `SkylineBatch.sln`, `AutoQC.sln` all build clean
- [x] `/code-review max` run and findings triaged (below)
- [ ] SkylineBatch / AutoQC functional suites - never run, locally or in CI (see below)
- [x] TeamCity green - all 19 checks SUCCESS on 90ec03cf, ready_to_merge

### CI notes (2026-09-09)

Two red checks along the way, both traced before touching anything:

1. **Skyline code inspection ERROR on 5f2c1afa** - ours, and fixed. Adding
   `using pwiz.Common.SystemUtil;` to DiannSearchLFQbenchTest.cs for
   HttpClientWithProgress made the pre-existing fully-qualified
   `pwiz.Common.SystemUtil.SilentProgressMonitor` on the next line redundant
   (RedundantNameQualifier, line 271). Fixed in 90ec03cf. Worth remembering: a
   migration that consolidates onto a shared type will do this anywhere the old
   code hand-qualified that namespace, in lines the diff never touches.
2. **TestNativeMessageBox, then the Wine container** - both agent flakes, both
   passed on re-run. The Wine one looked alarming (a Unicode filename mangled to
   `e -mix`, next to this branch changing ProcessEx.CanConvertUnicodePathsInDirectory)
   but was disproved: the Wine build PASSED on 5f2c1afa which already contains
   that ProcessEx change, the whole diff between the two commits is one C# name
   qualifier in a TestPerf file, and both builds reported the same ProteoWizard
   revision dbb642a8, so the native code under test was identical.
- [x] Copilot review addressed (one comment, pushed back with rationale, left unresolved)

## Code Review Triage (2026-09-09)

`/code-review max` returned 15 findings. Four were fixed; the rest were judged not
worth changing in this PR, with reasons.

### Fixed

1. **Prohibition regex was evadable.** `new\s+WebClient\s*\(` missed
   `new System.Net.WebClient()` and `new WebClient { ... }`. This went to the heart
   of the PR - the rule advertises no opt-out, and left two silent ones open - and it
   is sharpest here because this migration *removed* `using System.Net;` from the
   files it touched, making the qualified form the natural next reach. Now
   `new\s+(System\.Net\.)?WebClient\s*[({]`. Verified the tolerated count stays 3.
2. **`DownloadDlg` passed the -1 sentinel to `ProgressBar.Value`.**
   `HttpClientWithProgress` reports -1 when it cannot know the total size
   (`ChangePercentComplete(-1)`, line 445); `Math.Min(percent, 99)` let it through to a
   control that rejects negatives, once per 10 ms timer tick. Now
   `Math.Max(0, Math.Min(percent, 99))`.
3. **File-header spacing.** All three new files omitted the blank ` *` line between
   `AI assistance:` and `Copyright`. Measured: 356 of the 359 files carrying that line
   have it; these three were the only deviations.
4. **Overstated comment.** "Applies everywhere" reworded - the inspection walks only
   `pwiz_tools/Skyline` plus `Shared/Common` and `Shared/CommonUtil`.

### Deferred - worth doing, not here

These are all real, but they change download or test-seam semantics that this PR only
touches incidentally. Each would be better as its own change with the batch-tool suites
actually run.

- **`Server.cs` writes straight to the final path** with no `FileSaver`, and the new
  `catch` suppresses every exception once the token is cancelled, so a cancelled or
  failed download can leave a truncated file at the real destination while the log
  says 100%. Verified behaviour-preserving against master, but every other
  `HttpClientWithProgress` download in the tree targets a temp/`FileSaver` path.
  Testing `e is OperationCanceledException` rather than the token state is the
  narrower fix.
- **Test seam only fills `SkylineAdminCmdPath`**, but `SkylineSettings` consults
  `SkylineRunnerPath` first, so on any machine with a Skyline ClickOnce shortcut the
  seam is inert - i.e. on exactly the developer machines its doc comment describes.
- **Mock R versions are installed assembly-wide and never cleared**, so the three
  tests that genuinely execute R now launch a non-existent relative `Rscript.exe`
  instead of failing with "No R installation found".
  `TestUtils.ClearMockRInstallations` still has no caller.
- **`GetSkylineDir` prefers Release unconditionally** while the AutoQC sibling added in
  the same commit prefers the newer build - two policies for one decision.
- **`ConfigValidationReport` is built eagerly** as an `Assert` message, so all 53
  `CheckConfigs` call sites pay for two full re-validations on the UI thread even when
  passing; it also re-validates at assert time while `InvalidConfigCount` reads flags
  recorded at import, so the diagnostic can contradict the assertion.
- **`HttpClientWithProgress` `RequestUri` guard is asymmetric** - added on the
  `GetCookies` path, but the two `SetCookies` paths pass the same possibly-null URI.
  Guard all three or assert the invariant once.
- **`DiannSearchLFQbenchTest`** now inherits a 15 s per-chunk read timeout on a large
  unattended download that has no retry.
- **`SkylineTypeControl` `?? string.Empty`** turns a null `CmdPath` from a loud
  `ArgumentNullException` into an empty box that resolves to the CWD-relative
  `SkylineCmd.exe`, which `Validate()` then accepts.
- **AutoQC `instrumentType`** saves as `""` rather than throwing when the stored value
  matches no combo item; `GetFileFilter("")` then yields `*.*`. No in-app path produces
  it - needs a hand-edited or foreign config.

### Rejected

- **"The Skyline fallback makes `PanoramaWebFunctionalTest`'s guard unreachable, so it
  runs against panoramaweb.org."** The guard asserts a usable Skyline exists; the seam
  makes one exist, which is its purpose. The test additionally requires
  `AllowInternetAccess` and a password environment variable (`Assert.Fail` otherwise),
  so it cannot run unattended by accident.

## Copilot Review (2026-09-09) - Pushed Back, Not Fixed

Copilot left one inline comment: the prohibition regex can be bypassed with
`new global::System.Net.WebClient()`. It is correct, and the gap is wider than
reported - `new Net.WebClient()` (partial qualification under `using System;`)
slips through too.

**Decision: leave the regex alone.** Not because the gap is imaginary, but
because the rule has a short life and the threat model does not include
deliberate evasion.

- On the .NET port branch every project that can construct a `WebClient` is on
  `net10.0-windows` - Skyline, and **SkylineBatch/AutoQC too** - so the compiler
  raises SYSLIB0014 on every build. That is a stronger backstop than a regex.
- Caveat worth knowing: SYSLIB0014 is a **warning, not an error**. It is not in
  `NoWarn` (only SYSLIB0011 is) and there is no `TreatWarningsAsErrors`, so what
  makes it bite is the team's zero-warnings convention, not the toolchain.
- This inspection therefore covers the net472 window between now and the port.
  In that window the realistic failure is someone typing `new WebClient()`
  without thinking, which the current pattern catches.

Counter-evidence recorded honestly on the thread: `CodeInspectionTest.cs:216`
*does* match the `global::` form in the ResourceManager inspection. That one has
to - it matches generated Designer code, which is where `global::` actually
lives (381 occurrences in generated code under the scan root; exactly **1** in
hand-written code, and that one is the line 216 regex itself).

Thread left **unresolved** so a human reviewer can overrule.

### When this rule can be deleted

The tolerated count of 3 is the part worth keeping - it is the only record of the
three remaining uses, and the mechanism warns when the count *drops*. That makes
it a progress tracker: when the count reaches 0, or when every remaining project
has moved to net10.0-windows and the compiler covers it, the inspection can be
removed outright. Removing it before then would delete the only tracking of the
three survivors.

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

## Progress Log

### 2026-09-10 - Merged

PR #4648 merged as commit 085c0c99, squash-merged with --admin. What shipped:
the batch tools (SkylineBatch, AutoQC, SharedBatch) migrated off WebClient onto
HttpClientWithProgress via a shared DownloadProgressMonitor; the DIA-NN test
download that had regressed in July 2026; the CodeInspectionTest prohibition
with no inline opt-out and a tolerated count of 3; and the fix for both batch
functional suites hanging on a machine with no Skyline installation.

Deferred, NOT shipped: Phases 3 and 4 of the original backlog TODO
(SkylineNightly, SkylineNightlyShim, Executables/Installer). Those are the three
uses the tolerance of 3 tracks, and the reasons for deferring each are in the
comment above the rule.

Also deferred: the nine code-review findings listed under Code Review Triage.
The two worth doing first are Server.cs writing downloads straight to the final
path with no FileSaver, and the test seam being inert on machines that have a
Skyline ClickOnce shortcut (it fills SkylineAdminCmdPath, but SkylineSettings
consults SkylineRunnerPath first).

Carried forward unresolved: the Copilot thread on the global:: regex bypass,
left open deliberately - the decision was that the rule covers only the net472
window, since on the port branch every project that can construct a WebClient
is net10.0-windows and gets SYSLIB0014.

Verification gap worth naming: the SkylineBatch and AutoQC functional suites
were never run, locally or in CI. Skyline TeamCity does not build them (see
TODO-batch_tools_ci_integration.md in the backlog), and the second commit of
this PR exists specifically to fix those suites. That is the least-verified part
of what merged.

