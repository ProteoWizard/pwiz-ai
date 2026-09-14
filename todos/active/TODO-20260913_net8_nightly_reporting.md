# TODO-20260913_net8_nightly_reporting.md

## Branch Information
- **Branch**: `Skyline/work/20260913_net8_nightly_reporting`
- **Base**: `Skyline/work/20260612_net8_port`
- **Module**: `skyline`
- **Created**: 2026-09-13
- **Status**: In Progress
- **GitHub Issue**: (pending - not yet created)
- **PR**: [#4666](https://github.com/ProteoWizard/pwiz/pull/4666) (merged 2026-09-13 as `ea391bde4e` into `Skyline/work/20260612_net8_port`, not `master`)

## Objective

Make SkylineNightly runs of the .NET 10 port branch report correctly to
skyline.ms, run their full duration, and cover the same test set as Trunk -
so that the weeks of Integration-vs-Trunk data needed to clear the
squash-merge into `master` actually accumulate.

Today none of that is true. Integration has not successfully posted a run
since **2025-12-15**; every run since is sitting in the Integration folder's
*Posting Errors* tab. The nightly dies about 5 hours into a 9-hour window,
and 26 tutorial tests plus the entire perf suite never run at all.

Related: `TODO-20260612_net8_port.md` (the port itself).

## Why this blocks the merge

Two of the three defects are **silent**. Nothing fails, no alarm fires -
data just stops arriving. If the branch merges to `master` in this state,
every Trunk nightly on every machine inherits the same behavior:

| | Effect after merge |
|---|---|
| Blocker 1 | All nightly posting breaks fleet-wide. LabKey rejects every run. |
| Blocker 2 | Every machine loses ~45% of its nightly test window. |
| Blocker 3 | Tutorial suite and both Performance Tests folders silently stop running. |

## Evidence baseline (2026-09-12, BRENDANX-UW6, same machine, same night)

| | Integration | Trunk |
|---|---|---|
| posted to skyline.ms | **no** (`NumberFormatException`) | yes |
| duration | 290-304 min | 540 min |
| tests run | 6,933-6,972 | 9,775-10,266 |
| distinct tests (pass 0) | 1,107 | 1,128 |
| failures | 1 | 0 |
| leaks | 4-5 | 0 |
| `TestTutorial.dll` / `TestPerf.dll` | absent | present |

Raw logs: `E:\Nightly\Logs\BRENDANX-UW6_2026-09-{10,11,12}_*.log` / `.xml`.
All three defects reproduce identically on 9/10, 9/11 and 9/12, and the
Posting Errors tab shows BRENDANX-UW8 and AEROWORK failing the same way -
so none of this is machine-specific.

---

## Blocker 1 - Results never reach skyline.ms

### Symptom

```
java.lang.NumberFormatException: For input string: "unknownDate.3114ac104"
  at org.labkey.testresults.TestResultsController$NIGHTLY_POSTER.ParseAndStoreXML(:1957)
```

Run XML root attributes:

| attribute | Trunk | Integration |
|---|---|---|
| `revision` | `26254` | `unknownDate.3114ac104` |
| `git_hash` | `7af9eb0ea` | *(empty)* |

### Root cause

`SkylineNightly\Nightly.cs:792` scrapes the revision and hash out of the
build banner in the run log:

```csharp
reRevision = new Regex(@"\nProteoWizard \d+\.\d+\.([^ ]*)\.([^ ]*).*\r\n", ...);
```

Trunk's log carries it at line 2126:
`ProteoWizard 3.0.26254.7af9eb0ea master x64 AMD64 NT` - emitted by the
**bjam/boost-build native step**, right before it generates the `Version.cpp`
files.

The port replaced that step. `build.bat` drives a `dotnet`/CMake build and
never runs bjam, so the banner is never printed - the Integration log contains
no `Building pwiz`, no `Version.cpp`, no `ProteoWizard 3.0.x` line at all.
`revisionInfo` stays null, `Nightly.cs:804` falls back to `GetRevision()`
(`Nightly.cs:1270`), which returns `"unknownDate." + hash`. That is never an
integer, so LabKey's `Integer.parseInt` throws and the whole post is discarded.
`git_hash` is empty because it is group 2 of the same unmatched regex.

### Fix

Emit an equivalent banner from the port's build. The pieces already exist,
Jam-free, in `pwiz-sharp\build\PwizVersion.targets` (consumed by
`pwiz_tools\Skyline\SkylineVersion.targets`):

- `$(PwizVersionYear2)` -> `26`
- `$(PwizVersionDayOfYear)` -> `254`
- `$(PwizVersionGitHash)` -> `3114ac104`

pwiz's revision is exactly `{YY}{DDD}`, so the target line is:

```
ProteoWizard 3.0.26254.3114ac104 Skyline/work/20260612_net8_port x64 AMD64 NT
```

Preferred because it needs no change to SkylineNightly (which is deployed
separately to every nightly machine and would otherwise all need updating),
and it keeps one contract for both branches.

- [ ] Add a target/echo in the port's build that prints the banner in the exact
      regex-matching format, before the managed build
- [ ] Confirm group 1 parses as an int (`26254`) and group 2 is the short hash
- [ ] Verify the regex's `\r\n` requirement survives into the captured log
      (batch `echo` gives CRLF - check, do not assume)
- [ ] Re-run a nightly and confirm `revision=` / `git_hash=` in the emitted XML
- [ ] Re-post the queued XMLs via the Posting Errors tab's **Re-Post All**
      and confirm they land (recovers 9/10-9/12 and the UW8/AEROWORK runs)

### Follow-up worth considering separately

`GetRevision()` returning a guaranteed-unparseable string is a trap for any
future build path that misses the banner. A numeric fallback, or a LabKey-side
tolerance for a non-numeric revision, would turn a total data loss into a
cosmetic one. Not required for the merge; file separately.

---

## Blocker 2 - TestRunner crashes ~5 h into every run

### Symptom

```
Caught exception in TestRunnner.Program.Main:
Value cannot be null. (Parameter 'source')
   at System.Linq.Enumerable.Take[TSource](IEnumerable`1 source, Int32 count)
   at TestRunnerLib.RunTests.Run(...) RunTests.cs:line 496
# Process TestRunner had nonzero exit code 1
```

Identical on 9/10, 9/11, 9/12. Costs 236-250 minutes of every 540-minute window.

### Root cause

`RunTests.cs:495-498` reads the per-block heap detail:

```csharp
allSizes.AddRange(heapCount.CommittedSizes.Take(sizeOutputs)...);
allStrings.AddRange(heapCount.StringCounts.Take(stringOutputs)...);
```

`HeapAllocationSizes` is a **struct**; `CommittedSizes` and `StringCounts` are
`List<T>` properties that default to null. On the port,
`MemoryManagement.GetProcessHeapSizes()` deliberately never walks the heap -
its own comment explains HeapWalk/HeapLock fault with a non-catchable
AccessViolation on a Windows Segment Heap - and fills only `Committed` and
`Reserved` from `HeapSummary`. It never assigns either list, and the consumer
was not disabled to match. The comment even says so: *"The per-block
HeapDiagnostics detail is net472-only."*

**This is consistent with the Heaps series looking healthy in SkylineTester.**
`Committed`/`Reserved` *are* populated - that is the blue Heaps band, present on
all 6,899 logged lines. Only the per-block histogram lists are null, and they
are reached solely through `if (heapOutput && ReportSystemHeaps)`.

`heapOutput` is true only at `Program.cs:2569`:

```csharp
runTests.Run(test, 1, testNumber, dmpDir, hangIteration >= 0 && (i - hangIteration) % 100 == 0)
```

- i.e. inside the leak-check loop, after `hangIteration` is set, every 100th
iteration. So the chain is:

**a leaking test -> leak-check `runTestForever` -> `hangIteration` set ->
100th iteration requests heap detail -> null `.Take()` -> process dies.**

A run that has not yet entered leak checking cannot hit it. That is why the
9/13 run sat at 0:20 / 341 tests / 0 leaks looking perfectly healthy.

### Fix

- [ ] Null-guard (or skip) the two `AddRange` calls at `RunTests.cs:495-498`
      when the per-block lists are unavailable
- [ ] Emit a one-line note instead, so the absence is visible rather than silent
- [ ] Decide whether `ReportSystemHeaps`/`heapOutput` should be suppressed
      outright on the port rather than guarded at the use site
- [ ] Verify with a forced-leak run that the loop completes and the run reaches
      its full 540 minutes

Note this only fires *because* of Blocker 4's leaks - fixing it does not make
the leaks go away, it stops them from costing half the night.

---

## Blocker 3 - 26 tutorial tests and the whole perf suite never run

### Symptom

Absent from Integration pass 0, present in Trunk - and it is every tutorial test
without exception:

`TestAbsoluteQuantificationTutorial`, `TestAuditLogTutorial`,
`TestCEOptimizationTutorial`, `TestCEOptimizationTutorialAsSmallMolecules`,
`TestCustomReportsTutorial`, `TestDiaTutorial`, `TestExistingExperimentsTutorial`,
`TestGroupedStudies1Tutorial`, `TestGroupedStudiesTutorialDraft`, `TestIrtTutorial`,
`TestLibraryExplorerTutorial`, `TestLiveReportsTutorial`, `TestMSstatsTutorialLegacy`,
`TestMethodEditTutorial`, `TestMethodRefinementTutorial`, `TestMs1Tutorial`,
`TestPeakPickingTutorial`, `TestQuasarTutorialLegacy`,
`TestSmallMolMethodDevCEOptTutorial`, `TestSmallMoleculesQuantificationTutorial`,
`TestSmallMoleculesTutorial`, `TestSmallMoleculesTutorialInferredLabels`,
`TestSrmTutorialLegacy`, `TestTargetedMSMSTutorial`,
`TestTargetedMSMSTutorialAsSmallMoleculeMasses`,
`TestTargetedMSMSTutorialAsSmallMolecules`

### Root cause

`build.bat:171` fixes the project list:

```
set BUILD_TARGET=Skyline.csproj CommonTest\CommonTest.csproj Test\Test.csproj
                 TestData\TestData.csproj TestFunctional\TestFunctional.csproj
                 TestConnected\TestConnected.csproj TestRunner\TestRunner.csproj
```

`build.bat:76` states the intent: *"TestPerf and TestTutorial are intentionally
EXCLUDED from the standard build -- run those separately when needed."*

That split mirrors the **TeamCity configuration structure**, not a
developer-convenience call: `bt209` ("Skyline master and PRs (Windows x86_64)")
and `ProteoWizard_SkylinePrPerfAndTutorialTestsWindowsX8664` ("Skyline PR Perf
and Tutorial tests (Windows x86_64)") are separate configurations. Developers
building in Visual Studio get both anyway, since the `.sln` includes them - it
is only the command-line/CI path that drops them.

The nightly is the case that split does not serve. On Trunk the bjam build
produces everything and the *run* selects; SkylineNightly runs tutorials as part
of an ordinary nightly, with perf gated by "Include perf tests in nightly run".
On the port there is nothing to select from.

TestRunner's stager then reports it without failing:

```
Skipping TestTutorial - no output at ...\TestTutorial\bin\x64\Release\net10.0-windows (build it first).
Skipping TestPerf   - no output at ...\TestPerf\bin\x64\Release\net10.0-windows (build it first).
```

The build reports `0 Error(s)`, staging "succeeded", and the run posts as
healthy. Both `.csproj` are already ported to `net10.0-windows` and are in
`Skyline.sln`; neither has a `bin` directory, so they are simply never compiled.

(Cosmetic aside: the skip message's path carries an `x64` segment the projects
that do build stage without - `Test\bin\Release\net10.0-windows`. Worth tidying
while in there so the message points where the output would actually be.)

### Fix

Keep the TeamCity split intact; give the nightly a way to opt in.

- [ ] Add a `build.bat` flag (e.g. `--with-tutorial-perf`) that appends
      `TestTutorial\TestTutorial.csproj TestPerf\TestPerf.csproj` to
      `BUILD_TARGET`; parser is at `build.bat:116-132`
- [ ] Pass it from `SkylineTester\TabBuild.cs:242-244`, which today builds the
      command line as
      `build.bat <config> --i-agree-to-the-vendor-licenses [--no-tests]`.
      Build both unconditionally so the *run* selects, matching Trunk -
      building TestPerf is cheap, running it is what is gated
- [ ] Have the perf/tutorial TeamCity configuration pass the same flag
- [ ] Make the stager's "Skipping ..." loud when the caller expected the
      project, so this can never be silent again
- [ ] Verify a nightly on the branch runs all 26 tutorial tests
- [ ] Verify a perf-configured nightly finds TestPerf

---

## After reporting works: the data that starts arriving

Fixing 1-3 is what makes 4+ observable. These are recorded from the logs we
already have; treat them as leads, and re-derive from posted data once it flows.

### 4. Leaks unique to the port (4-5 nightly, Trunk has 0)

| test | bytes/run |
|---|---|
| `TestArrangeGraphs` | 142,493 - 151,140 |
| `TestFilesTreeForm` | 57,130 - 64,493 |
| `TestExplicitAnalyteConcentration` | 60,209 *(9/11 only)* |
| `TestInstrumentInfo` | 34,721 - 35,425 |
| `FileTypeTest` | 30,999 - 31,025 |

These are what trigger Blocker 2. Before chasing them as product leaks, settle
a measurement question: the port changed how the committed number is derived
(`HeapSummary.cbAllocated` instead of HeapWalk busy bytes), so thresholds
calibrated on net472 may not transfer. Some or all of these may be artifacts.
`#4659` ("Fixed two .NET 10 leaks and excluded the wiff2 SDK leak from leak
checking", 2026-09-12) is prior art on this branch.

### 5. Test failures unique to the port (1 per night, varying)

- `ThermoCancelImportTest` - 9/11, 9/12, French locale, `ThermoQuantTest.cs:146`
- `TestCustomIon` - 9/10
- 2026-09-09 posted `tests=0` - a complete washout, cause not yet established

### 6. Memory and handle profile (9/12, per-test, from the run XMLs)

| metric (pass 1) | Integration | Trunk | delta |
|---|---|---|---|
| managed med | 88.6 | 83.2 | +5.4 |
| committed med | 88.5 | 76.5 | +12.1 |
| **total med** | **283.2** | **461.1** | **-177.9** |
| **total max** | **898.7** | **502.1** | **+396.6** |
| user-gdi med | 193 | 166 | **+27** |
| handles med | 3,334 | 3,353 | -19 |

The port is much lighter at steady state and much heavier at the ceiling.
Worst single-sample spikes vs Trunk: `TestDocumentSizeError` +527 MB,
`TestDocumentViewTransformerMappings` +482 MB, `TestFindNodeCancel` +296 MB,
`TestRetentionTimeManager` +259 MB. Single samples - pointers, not measurements.

The sustained **+27 user-GDI** is a real regression and is consistent with the
GDI-heavy leakers in section 4.

`TestDiagnostics.dll` (the net472-only C++/CLI handle enumerator) is gone on the
port, so per-type handle-leak diagnosis is unavailable - relevant to how
section 4 gets investigated. `RunTests.cs:481-483` notes a pure-C# P/Invoke
reimplementation would be needed.

### 7. Non-blocking

- 784 `WFO1000` designer-serialization warnings in the port build
- `bsdtar.exe: Error exit delayed from previous errors` - benign, "Already
  exists" on test-data extraction
- Throughput is *better* on the port: 22.9 tests/min vs Trunk's 18.1

---

## Task list

- [x] Blocker 1 - emit the ProteoWizard version banner from the port build
- [ ] Blocker 1 - Re-Post All the queued XMLs, confirm they land
- [x] Blocker 2 - guard the null per-block heap lists in `RunTests.cs`
- [x] Blocker 3 - `--with-tutorial-perf` flag + `TabBuild.cs`
- [ ] Blocker 3 - pass the flag from the perf/tutorial TeamCity configuration
- [ ] Blocker 3 - make the stager's skip loud
- [ ] Confirm one full Integration nightly: posts, runs 540 min, ~1,128 tests
- [ ] Then re-baseline Integration vs Trunk from posted data and revisit 4-6

## Progress

### 2026-09-13 - first pass, commit `ee2581d8be`

All three code fixes are in and pushed. What is verified, and what is not:

**Blocker 1 - verified mechanically, not yet in a nightly.**
`SkylineVersion.targets` gains a `PrintPwizVersionBanner` target that reuses the
existing `ComputePwizBuildVersion` pieces, so the banner cannot drift from the
version the assembly is stamped with. `build.bat` runs it standalone (no restore,
no ProjectReference graph - about a second) and emits the line.

Two traps found while building it, both now handled:
- MSBuild indents `Message` output by two spaces, and the scrape regex anchors on
  a newline immediately followed by `ProteoWizard`. The target writes the line to
  `obj\pwiz-version-banner.txt` (gitignored) and `build.bat` emits it with `type`,
  which lands at column 0.
- The revision must parse as an int on the LabKey side.

Checked against the real `Nightly.cs` regex:

```
ProteoWizard 3.0.26255.6ef677076e Skyline/work/20260913_net8_nightly_reporting x64 AMD64 NT
  match -> revision '26255' (parses int), git_hash '6ef677076e'
```

**Blocker 2 - fixed, not yet exercised.** The two `AddRange` calls are guarded and
the absence now logs `# HEAP DETAIL unavailable - per-block heap walking is
net472-only` instead of throwing. Still needs a run that actually reaches leak
checking to confirm the run survives it.

**Blocker 3 - flag works, TeamCity side outstanding.** `--with-tutorial-perf`
appends both projects; `TabBuild.cs` passes it unconditionally so every
SkylineTester-driven run stages both and selects at run time, as Trunk does.
Verified the chained `if ... else ^` parser still rejects unknown arguments after
the insertion, and that both projects build clean on the port branch.

**Gates run:** `Build-Skyline.ps1 -Summary` (solution, 186 s) and
`-RunTests -TestName CodeInspection` - both green. Once `TestTutorial`/`TestPerf`
output existed, the stager picked them up on its own, which confirms the stager's
default set already includes them and only the build was missing.

**Not yet done:** no nightly has run with these changes. The real gate is still a
clean Integration nightly - posts, 540 minutes, tutorial tests in pass 0.

### 2026-09-13 - review pass, commit `4a4d4fb8b8`, PR [#4666](https://github.com/ProteoWizard/pwiz/pull/4666)

`/code-review max` returned 15 findings against commit `ee2581d8be`. Acted on 8, skipped 7.

**Acted on:**

1. **Stale banner emitted as this run's** (critical, same failure class this work removes).
   `build.bat` never deleted `obj\pwiz-version-banner.txt` before generating it and never
   checked the msbuild exit code. A run killed between write and delete leaves the file; a
   later run whose msbuild failed would `type` the previous commit's banner and post that
   revision and hash as its own. Now deletes first, checks `!ERRORLEVEL!`, and warns on
   both failure paths. Verified: with a stale file present and the target failing, the
   stale banner is not emitted.
2. **`--with-tutorial-perf` applied to the developer Build tab too.** `CreateBuildCommands`
   has two callers - `TabNightly.cs:376` and `TabBuild.Run` - so "run build verification
   tests" would have started running the 26 tutorial tests. Now a defaulted parameter,
   passed `true` only from the nightly.
3. **Branch field could hold git stderr / `HEAD` / a `';'`.** `Exec`'s `ConsoleToMSBuild`
   captures stderr, and MSBuild still gathers `ConsoleOutput` when the command fails under
   `ContinueOnError`, so `'' -> unknown` never fired; multi-line output joins with `';'`,
   and `WriteLinesToFile` takes `ITaskItem[]`, so a `';'` splits the banner across lines.
   Detached HEAD (every CI agent) gave the literal `HEAD`. Now resolves detached HEAD with
   `git name-rev` as `SkylineTester.csproj` does, then shape-guards to `^[A-Za-z0-9._/+-]+$`.
   Verified against all six cases including the real "dubious ownership" stderr text.
4. Banner step skipped for `--build-only` - a developer compile is never scraped.
5. Corrected two comments that were wrong: the day-of-year must stay **zero-padded** (the
   comment said "unpadded", which would have produced `3.0.265` in early January), and the
   `Message` is invisible at the `-v:q` build.bat passes.
6. Usage synopsis and the contradicting scope note in `tcbuild.bat`.

**Skipped deliberately**, with reasons, so they are not re-litigated:

- *The heap guard's else branch is unreachable* - `CommittedSizes`/`StringCounts` are
  assigned nowhere in this net10-only assembly. True, but it is defensive code that costs
  nothing; deleting the branch would remove the path a restored net472 leg needs.
- *Read revision/hash from SkylineTester.dll instead of scraping the log* - genuinely the
  better design: `Nightly.cs:582` already reads the branch back out of the assembly's
  `AssemblyInformationalVersion`, which carries all three. But it changes SkylineNightly,
  which is deployed separately to every nightly machine, and the goal was to land before
  the next cycle. Filed as follow-up.
- Hardcoded `3.0.` / `x64 AMD64 NT` in the banner tail (the scrape ignores it); redundant
  `mkdir obj`; `--with-tutorial-perf` growing distro zips if someone adds it to a
  zip-producing TeamCity command line (the `tcbuild.bat` note now warns against exactly
  that).

### 2026-09-13 - Merged (TODO stays active)

PR #4666 merged as `ea391bde4e` into `Skyline/work/20260612_net8_port`. All three
reporting blockers shipped: the version banner, the heap-detail null guard, and
`--with-tutorial-perf` scoped to the nightly.

**Left in `active/` deliberately.** The central gate - one Integration nightly that
posts, runs 540 minutes and shows tutorial tests in pass 0 - has not happened yet, and
the TeamCity flag, the loud stager skip, the queued XML re-post and sections 4-6 are all
still open. This TODO is the evidence baseline for the rest of that work.

**Dependency worth remembering for the first verification run.** The three fixes do not
all take effect at the same time. SkylineNightly downloads `SkylineTester.zip` from
TeamCity and runs *that* SkylineTester, which then clones the branch and builds locally.
So:

* banner (`build.bat`, `SkylineVersion.targets`) and heap guard (`RunTests.cs`) come from
  the fresh clone - they work on the next run, whatever zip is in use
* `--with-tutorial-perf` is passed by `TabBuild.cs`/`TabNightly.cs`, which live in
  SkylineTester itself - it only takes effect once TeamCity has produced a **new
  SkylineTester.zip** from the port branch

A run started against an older zip would therefore post correctly and still have no
tutorials. Check `Staging TestTutorial` in the log before concluding anything.

### 2026-09-13 - #4659 cleared the leaks, and the run got past 5 hours

The first Integration run built at or after `6ef677076e` (#4659) reached **7:53 elapsed
with 1 failure and 0 leaks**, versus 4-5 leaks and a hard stop at ~5h04 on 9/10-9/12.

This settles the question the earlier analysis could not: all of the leak data in section
4 came from builds one commit *before* #4659, and the wiff2 leak-pass substitution
(`IsAbWiff2Safe`, mzML instead of `.wiff2` during pass 1) removed them. Confirmed
individually - `TestArrangeGraphs` (was 146,192 B), `FileTypeTest` (was 31,025 B) and
`TestExplicitAnalyteConcentration` (was 60,209 B) all ran clean.

Consequences:

* The `runTestForever` park never triggered, so the ~4 hours previously lost were a
  *symptom of the leaks*, not of the crash. The heap guard from #4666 is now insurance
  against the next `reportLeakEarly` leak rather than the thing that restores the window.
* An earlier proposal to drop `reportLeakEarly` from `TestInstrumentInfo` is **withdrawn** -
  it was based on pre-#4659 data and would have removed leak reporting from a test that no
  longer leaks.
* Section 4's leak table is historical. Re-baseline from posted data once reporting works.

### Incidental finding - stale `AssemblyInfo.cs` blocks a SkylineTester build

`SkylineTester.csproj` sets `GenerateAssemblyInfo=true` and comments that the
project "has no hand-written AssemblyInfo.cs, so there is nothing for the
generated attributes to collide with". That holds on a clean clone (which is why
the nightly is unaffected), but `SkylineTester\Properties\AssemblyInfo.cs` is
gitignored, so a checkout where the old net472/Jam build ever ran still has one -
and the build then dies with six `CS0579: Duplicate ... attribute` errors. Hit on
BRENDANX-UW6 with a file dated 2026-04-02.

`Skyline.csproj` already solves exactly this with
`<Compile Remove="Properties\AssemblyInfo.cs" />` on the net10 pass. Not a merge
blocker and out of scope here, but it will bite any developer with a pre-port
checkout. Worth a separate one-line fix.

## Verification

Build and test with the wrapper scripts before any commit:

```
pwsh -File './ai/scripts/Skyline/Build-Skyline.ps1' -Summary
```

The real gate for this work is a clean Integration nightly on BRENDANX-UW6:
posted to skyline.ms, 540-minute duration, tutorial tests present in pass 0.

## Files expected to change

| file | blocker |
|---|---|
| `pwiz_tools/Skyline/build.bat` | 1, 3 |
| `pwiz_tools/Skyline/TestRunnerLib/RunTests.cs` | 2 |
| `pwiz_tools/Skyline/SkylineTester/TabBuild.cs` | 3 |
| TestRunner stager (skip message / hard failure) | 3 |
| TeamCity perf+tutorial configuration | 3 |
