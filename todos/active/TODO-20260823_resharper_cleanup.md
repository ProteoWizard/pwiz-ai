# TODO-20260823_resharper_cleanup.md

Get ReSharper green again for Skyline, SkylineBatch and AutoQC on the net8 line.

## Branch Information
- **Checkout**: `C:\proj\pwiz`
- **Branch**: `Skyline/work/20260823_resharper_cleanup` - branched off
  `Skyline/work/20260818_commonutil_winforms_split` @ `2cb66ee39d`, NOT master.
- **Base**: `Skyline/work/20260818_commonutil_winforms_split`
- **Created**: 2026-08-23
- **Status**: In Progress (Phase 0 not started)
- **Module**: `skyline`
- **PR**: (pending)
- **Related**: [#4587](https://github.com/ProteoWizard/pwiz/pull/4587) (CommonUtil WinForms split,
  the immediate base), `TODO-20260818_commonutil_winforms_split.md`,
  `TODO-20260612_net8_port.md`

### Base chain (measured 2026-08-23)

```
master
  +- chambem2/pwiz-sharp                              (6 behind master, 516 ahead)
       +- Skyline/work/20260612_net8_port             (1 behind pwiz-sharp, 0 ahead)
            +- Skyline/work/20260818_commonutil_winforms_split   <- this work branches here
                 (0 behind net8_port; local == origin)
```

`net8_port` is a strict subset of `pwiz-sharp`: the one commit separating them is
`1d26ed967b pwiz: Added opt-in parallel decoding to the pwiz-sharp mzML reader (#4590)`.
PR #4587 targets `net8_port`, so the branch is fully up to date with the base its PR is
measured against. Merging `pwiz-sharp` directly would pull #4590 into the #4587 diff;
if that commit is wanted down here, fast-forward `net8_port` to `pwiz-sharp` first so
the PR base moves with it.

## Goal

Stated 2026-08-23 by Brendan, as a **prerequisite for merging the .NET 8.0 repo port**:

1. Fully working **net8.0 builds for AutoQC and SkylineBatch**, with **passing tests**.
2. **Skyline, SkylineBatch and AutoQC all clean of ReSharper warnings and errors** on
   this branch.

net472 must keep building too - the port multi-targets `net472;net8.0-windows` on
purpose, and master still ships net472 - so "fix net8" here never means "drop net472".
That closes open question 2 below.

## Why

`ai/CRITICAL-RULES.md`, "Tools and Quality": *"Solution must build with zero warnings.
ReSharper must show green (no inspections)."* That rule has a verifier on master and no
verifier at all on this line of work:

| Target | Gate | State on this branch |
|---|---|---|
| `Skyline.sln` | TeamCity **Skyline Code Inspection** + local `Build-Skyline.ps1 -RunInspection` | TeamCity does not run for a PR based off `net8_port` (no build exists for `pull/4587`); the local switch **refuses to run** |
| `SkylineBatch.sln` | local `Build-SkylineBatch.ps1 -RunInspection` only (no TeamCity config) | **solution does not build**, so inspection never starts |
| `AutoQC.sln` | local `Build-AutoQC.ps1 -RunInspection` only (no TeamCity config) | **solution does not build**, so inspection never starts |

For reference, the master gate is genuinely clean: TeamCity build **#19161**
(`176539ec`, config `ProteoWizard_WindowsX8664msvcProfessionalSkylineResharperChecks`)
reports zero issues at WARNING+ for `Skyline.sln`. So this is not a backlog that master
is carrying - it is a gate that stopped running when the net8 port changed the build
shape underneath it.

**Nothing can be "addressed" until the gate runs.** Phase 0 below is therefore not
setup work, it is the work.

## Measured state (2026-08-23, on `2cb66ee39d`, clean tree)

### 1. Skyline: the local inspection gate refuses on the net8 path

`ai/scripts/Skyline/Build-Skyline.ps1` auto-detects net8 (line ~226: `Skyline.csproj`
declares `<TargetFrameworks>net472;net8.0-windows</TargetFrameworks>`), builds fine, and
then hits an explicit refusal (line ~576):

```
ReSharper inspection is not wired up for the net8 build path.
  It writes to bin\x64\<Config>, which the net8 build never creates, and runs
  jb --no-build against Skyline.sln, which the net8 path never builds.
  Refusing rather than reporting a green gate that inspected nothing.
exit 2
```

The refusal is correct - it is refusing to lie - but it means the switch is unusable
here. Two distinct problems behind it:

- **Output path.** The block writes `bin\$Platform\$Configuration\InspectCodeOutput.xml`;
  the net8 path stages to `bin\staging-net8\$Configuration`. Cosmetic, easy.
- **What actually gets inspected.** The net8 path builds only the explicit project list
  (`Skyline.csproj` for `net8.0-windows`), not the solution. Inspecting `Skyline.sln`
  with `--no-build` would then evaluate projects whose net472 outputs do not exist. This
  is the real design question, not a path fix. See Phase 0.2.

`jb` itself is present and current (`C:\Users\brendanx\.dotnet\tools\jb.exe`,
JetBrains.ReSharper.GlobalTools; the script's own note measures ~5 min for a full
`Skyline.sln` pass at 2026.1.3).

### 2. SkylineBatch and AutoQC: the solutions do not build

`Build-SkylineBatch.ps1 -RunInspection` and `Build-AutoQC.ps1 -RunInspection` both fail
at the MSBuild step and exit before inspection. Identical cause in both, in the shared
project: **13 errors in `SharedBatchTest`, net472 target only** (the `net8.0-windows`
target of the same project compiles clean):

```
SharedBatchTest\AbstractBaseFunctionalTest.cs(8,17):  error CS0234: The type or namespace
  name 'VisualStudio' does not exist in the namespace 'Microsoft'
  ... same at AbstractUnitTest.cs(22,17), AssertEx.cs(24,17),
      ExtensionTestContext.cs(24,17), TestFilesDir.cs(22,17)
SharedBatchTest\AbstractUnitTest.cs(44,16):           error CS0246: The type or namespace
  name 'TestContext' could not be found
  ... plus 7 more TestContext sites in ExtensionTestContext.cs and TestFilesDir.cs
```

**Root cause.** `6f06a355d9 "Port SkylineBatch/SharedBatch to net8; SkylineBatchTest
38/38"` converted these projects from legacy csproj to SDK-style multi-target, but the
net472 condition kept a bare, path-less reference:

```xml
<ItemGroup Condition="'$(TargetFramework)' == 'net472'">
  <Reference Include="Microsoft.VisualStudio.QualityTools.UnitTestFramework" />
```

In the legacy project (still what `master` has - `ToolsVersion="12.0"`, old xmlns, test
`ProjectTypeGuids`) the Visual Studio test-project flavor targets add
`$(VsInstallRoot)\Common7\IDE\PublicAssemblies` to `AssemblySearchPaths`, so a bare
reference resolves. An SDK-style project gets no such search path. The commit message's
"38/38" refers to the net8 target; the net472 target was never rebuilt after conversion.

Three things this is **not**, all checked:

- **Not a machine/GAC problem.** `Microsoft.VisualStudio.QualityTools.UnitTestFramework`
  is absent from both `%WINDIR%\Microsoft.NET\assembly\GAC_MSIL` and the legacy
  `%WINDIR%\assembly\GAC_MSIL`. It exists on disk only under the VS installs
  (`...\Common7\IDE\PublicAssemblies\` and `...\ReferenceAssemblies\v4.0\`), which is
  exactly the directory SDK-style resolution does not look in.
- **Not a VS-version problem.** Reproduced identically with VS 2022 Community MSBuild and
  with VS 18 (2026) Community MSBuild. Both are installed on this machine; the build
  scripts pick VS 18 via `vswhere -latest`, but pinning to 2022 does not change the
  result.
- **Not a script problem.** `Build-SkylineBatch.ps1` and `Build-AutoQC.ps1` invoke
  MSBuild correctly (with `-restore`), detect the failure, and report it accurately.
  They are working; the source they build is broken. An out-of-band inspection run
  against both solutions reproduced the same unresolved reference
  (`[MSB3245] Could not resolve this reference`), confirming the inspector sees the same
  broken graph the compiler does. **That out-of-band path was abandoned - all work in
  this TODO goes through the standard scripts, and if a script is in the way it gets
  fixed, not bypassed.**

### 3. The same bare reference is spread across the Skyline test projects

Every one of these still carries the path-less
`Microsoft.VisualStudio.QualityTools.UnitTestFramework` reference in an SDK-style
project on this branch:

```
pwiz_tools/Skyline/CommonTest/CommonTest.csproj
pwiz_tools/Skyline/Test/Test.csproj
pwiz_tools/Skyline/TestConnected/TestConnected.csproj
pwiz_tools/Skyline/TestData/TestData.csproj
pwiz_tools/Skyline/TestFunctional/TestFunctional.csproj
pwiz_tools/Skyline/TestPerf/TestPerf.csproj
pwiz_tools/Skyline/TestTutorial/TestTutorial.csproj
pwiz_tools/Skyline/TestRunner/TestRunner.csproj
pwiz_tools/Skyline/TestRunnerLib/TestRunnerLib.csproj
pwiz_tools/Skyline/Executables/SharedBatch/SharedBatchTest/SharedBatchTest.csproj
pwiz_tools/Skyline/Executables/SkylineBatch/SkylineBatchTest/SkylineBatchTest.csproj
pwiz_tools/Skyline/Executables/AutoQC/AutoQCTest/AutoQCTest.csproj
```

(Also `pwiz_tools/MSConvertGUI/Test`, `.../TestConnected`, `pwiz_tools/Bumbershoot/*`,
and `Executables/BuildMethod/*`, which are outside this TODO's scope.)

**Not yet verified**: whether the Skyline test projects actually fail to build for
net472 the way `SharedBatchTest` does. Only the two batch-tool solutions were built.
The pattern is identical, so assume they do until measured - Phase 0.1 must confirm.

### 4. The inspection profile is already unified

`ai/scripts/Skyline/scripts/Sync-DotSettings.ps1` (called first by all three build
scripts) copies `Skyline.sln.DotSettings` as the canonical baseline over
`SkylineBatch.sln.DotSettings`, `AutoQC.sln.DotSettings` and
`SkylineMcp.sln.DotSettings`, applying exactly one intentional override:
`LocalizableElement` WARNING -> HINT for the batch tools. It is idempotent and skips the
write when content already matches, so it does not dirty the tree. **No profile
divergence to chase** - the three solutions are measured against one ruleset, and any
severity retuning belongs in the Skyline baseline plus the `$overrides` map, never in a
hand-edited downstream `.DotSettings`.

## Plan

### Phase 0 - make the gate runnable

This is the prerequisite for every later phase. Nothing here is optional.

- [x] **0.1 Fix net472 MSTest resolution in the batch-tool test projects.** DONE
      2026-08-23. Option (a) as planned: `MSTest.TestFramework` (and, for the two runnable
      suites, `MSTest.TestAdapter`) moved out of the net8-only `ItemGroup` into an
      unconditional one in `SharedBatchTest`, `SkylineBatchTest` and `AutoQCTest`, and the
      path-less `Microsoft.VisualStudio.QualityTools.UnitTestFramework` reference deleted.
      Both solutions now build both TFMs.

      Two things the plan did not anticipate, both now handled and commented in the csprojs:

      - **`Microsoft.NET.Test.Sdk` had to stay net8-only.** On net472 it pulls
        `Microsoft.TestPlatform.ObjectModel 17.5.0` -> `System.Reflection.Metadata 1.6.0` ->
        `System.Collections.Immutable 1.5.0` (assembly `1.2.3.0`). net472 only needs the
        framework and adapter to compile and be discovered.
      - **`MSTest.TestAdapter` drags the same `Immutable 1.5.0` in**, and a package asset
        beats a `HintPath`, so `SkylineBatchTest`'s existing
        `Shared\Lib\System.Collections.Immutable.dll` (assembly `5.0.0.0`) silently lost and
        the result was `CS1705` against `SharedBatch`/`SkylineBatch`/`AutoQC`. Fixed by
        asking NuGet for `System.Collections.Immutable 5.0.0` on net472 in the two test
        projects - the same version `Shared\Lib` ships - so the whole graph agrees. This is
        a compile error, not a warning; `NoWarn` on `NU1605` had been hiding the downgrade
        signal that would have pointed at it.

- [ ] **0.1b Fix net472 MSTest resolution in the Skyline test projects.**
      Confirm first whether Skyline's own test projects share the failure (build
      `Test.csproj` and `TestFunctional.csproj` for the net472 target), then pick one
      strategy and apply it to every project in the list above:
      - **(a) `MSTest.TestFramework` NuGet on net472 too** (preferred). net8 already
        does this; MSTest 3.2.0 supports net462+, the namespace
        (`Microsoft.VisualStudio.TestTools.UnitTesting`) is unchanged, and it removes the
        Visual Studio install from the reference graph entirely. **Must be applied to
        `SharedBatchTest`, `SkylineBatchTest` and `AutoQCTest` together** - they
        reference each other, and mixing the VS assembly with the NuGet one across a
        project boundary is a type-identity mismatch, not a version warning.
      - **(b) `<HintPath>` into `$(VsInstallRoot)\Common7\IDE\PublicAssemblies\`.**
        Smaller diff, but `VsInstallRoot` is undefined outside VS MSBuild, so it
        reintroduces the exact "green on CI, red on a dev box" split this TODO exists to
        close. Prefer (a) unless (a) turns up a concrete blocker.
      Decide with Matt / whoever owns the net8 port before doing the wide edit - this
      touches his conversion work, and option (a) changes what CI restores.

- [ ] **0.2 Wire `-RunInspection` for the net8 path in `Build-Skyline.ps1`.**
      Replace the `exit 2` refusal with something that actually inspects. The refusal
      names two problems; solve the second one first, because it decides the first:
      - Pass the net8 target framework through as an inspection property so ReSharper
        evaluates the same TFM the net8 build produced, and make the net8 path build the
        whole solution (not just the explicit project list) before inspecting -
        otherwise the `--no-build` pass inspects a graph with missing outputs and
        reports resolution noise instead of real findings.
      - Then move `$inspectionOutput` to a directory that exists on the net8 path
        (`bin\staging-net8\$Configuration`).
      - Keep the refusal as a fallback for any combination still not wired. The comment
        that motivates it - *"Refusing rather than reporting a green gate that inspected
        nothing"* - is the right instinct and should survive the change.
      This is an `ai/` change: commit to **pwiz-ai master**, not the pwiz branch.

- [ ] **0.3 Confirm all three scripts reach the inspection stage and produce XML.**
      Success criterion is an `InspectCodeOutput.xml` per solution with a parsed issue
      count - green or red, but real.

### Phase 0 findings - the batch-tool tests hang, and it is not a net8 regression

`Build-SkylineBatch.ps1 -RunTests` (which runs the **net8** assembly - the script takes
the last declared TFM) does not fail, it **hangs**. Measured: 14 minutes wall clock for
1.7 seconds of CPU, flat, with a `Skyline Batch` window open. Enumerating that window's
controls named it exactly:

```
'Skyline Batch requires Skyline to run, but did not find an administrative or
 web-based installation.'
'&Please specify Skyline installation folder:'  [ C:\Program Files\Skyline ]  [OK] [...]
```

`Program.Main` calls `InitSkylineSettings()`, which calls
`SkylineInstallations.FindSkyline()` and, when that fails, runs the modal
`FindSkylineForm`. Under a functional test nothing can answer it, so the run never ends.
This machine has no Skyline installation at all - no `C:\Program Files\Skyline`, no
`Skyline-daily`, no ClickOnce `.appref-ms`, no `SkylineCmd.exe` beside the test binaries -
so `FindSkyline()` correctly returns false.

**`master` has the identical code** (same two lines, same `InitSkylineSettings`), so this
is not something the net8 port broke. It is a latent test-robustness defect that only
shows on a machine without Skyline installed, which is presumably why the port's
"SkylineBatchTest 38/38" was recorded on a machine that had one. It is in scope here
because the goal is passing tests, and a suite that hangs cannot pass.

Behind that first hang were three more, each hidden by the one in front of it. The full
chain, in the order it had to be peeled:

1. **Modal `FindSkylineForm` at startup** (above) - hung the run outright.
2. **`No R installation found`** - `TestUtils` builds nearly every fixture through
   `RInstallations.GetMostRecentInstalledRVersion()`, which throws when no R is
   installed. 26 of 38 tests failed in fixture construction, before testing anything.
   `TestUtils.SetupMockRInstallations()` exists for exactly this ("Use this to run tests
   on TeamCity clients or machines without R installed") and **nothing had ever called
   it** - on `master` either. These tests validate that a version is recorded; they never
   execute R.
3. **Modal `Could not find a Skyline installation at this location`** - saving a
   configuration validates its Skyline settings and pops an error box. Same root cause as
   (1): no Skyline on the machine.
4. **`GetSkylineDir()` only probed Release output directories** - `bin\Release\net8.0-windows`,
   `bin\x64\Release\net8.0-windows`, `bin\staging-net8\Release`, and it fell back to the
   first of those even when it did not exist. The batch-tool build scripts default to
   **Debug**, so every test that needed a real `SkylineCmd.exe` failed against a directory
   that had never been built. `master`'s net472 branch has the same Release-only
   assumption (`bin\x64\Release`).

5. **`SkylineSettings`'s two XML readers disagree about where Skyline is.** `ReadXml`
   (current format) opens with *"always use local Skyline if it exists"* and retypes the
   configuration to `SkylineType.Local`. `ReadXmlVersion_20_2` (old format) does not. So
   the same configuration, saved in the two formats and read on the same machine, can end
   up with different Skyline settings - and on a machine whose only Skyline is a local
   build, every old-format configuration keeps its saved type (`Skyline`), resolves
   `CmdPath` to null, and fails validation with *"Could not find a Skyline installation on
   this computer"*. That is what was invalidating the imported configurations, which in
   turn is what left `ImportTest` waiting four minutes for an `InvalidConfigSetupForm`
   that `HandleEditEvent` had already skipped past, with the config editor sitting open.

   **Left alone deliberately.** Making the two readers agree is a one-line change, and it
   makes the failing tests pass - but `Test\BcfgTestFiles\*` baselines encode the current
   behaviour (an old-format import/export round trip is expected to write back
   `type="Skyline"`), so eight `BcfgFileTest` cases fail the moment the readers agree.
   Fixing it properly means regenerating those baselines and deciding what an old-format
   round trip should preserve. That is a call for whoever owns SkylineBatch, not a
   drive-by inside a ReSharper cleanup. A comment at the asymmetry now says so.

**Fixes applied** (all in the batch-tool tree, none of them net8-specific):

- `SkylineBatchTest/SkylineBatchTestSetup.cs` (new): an `[AssemblyInitialize]` that falls
  back to mock R *only when real detection finds none*, and points
  `SkylineInstallations.TestLocalSkylineCmdPath` at a Skyline built in this checkout *only
  when no installation is found*. A machine that has R and Skyline behaves exactly as
  before.
- `SharedBatch/SkylineInstallations.cs`: `TestLocalSkylineCmdPath` test seam, mirroring
  the existing `RInstallations.TestRVersions`. It has to be consulted inside
  `FindLocalSkyline()` rather than assigned once by the test, because the app's own
  startup calls `FindSkyline()` again and would overwrite it.
- `SkylineBatchTest/TestUtils.cs`: `GetSkylineDir()` now probes Debug as well as Release,
  on both TFM branches, and returns the first that actually holds `SkylineCmd.exe`.

**Result**: 38 tests, **35 passed / 3 failed**, from a starting point where the suite
never finished at all.

The three that remain all **execute** a configuration rather than just validating one,
and this machine has no R installation:

| Test | What it needs |
|---|---|
| `TestRunFromRScripts` | runs the R scripts; mock versions point at paths that do not exist |
| `TestMultipleLogs` | starts a batch run with `RunBatchOptions.R_SCRIPTS` |
| `DataDownloadTest` | downloads data, then runs the configuration |

Mock R versions cannot help these - the seam exists to let configurations *validate*
without R, not to execute it. They need R installed on the machine, and that is a
prerequisite on `master` too, not something the net8 port introduced. **Decide whether
to install R on the test machines or mark these three as requiring it**; do not "fix"
them by weakening what they assert.

### AutoQC's suite hangs in `RunUI` - the harness's one un-timeout-able wait

`Build-AutoQC.ps1 -RunTests` got through 8 tests (7 passed, `TestConfigEquals` failed)
and then stopped dead for 18 minutes at 0.02 CPU-seconds per 15s. Managed stacks
(`dotnet-stack report`) name it exactly:

```
test thread : AbstractBaseFunctionalTest.RunUI -> AppInvoke -> [blocked]
UI thread   : AutoQcConfigForm.Save() <- ClickSave() <- AutoQcFunctionalTest.BasicTest
```

`AppInvoke` is `MainWindow?.Invoke(act)` - a **synchronous** `Control.Invoke` with no
timeout, and it is the only wait in the whole harness that has none. Every other one
(`WaitForOpenForm`, `WaitForClosedForm`, `WaitForCondition`) fails after
`GetWaitCycles()`. So when a `RunUI` action blocks - `Save()` here, presumably on a modal
or a synchronous server check - the run does not fail, it stops forever, and on a
developer's machine it parks a window on the screen.

Two separate things to fix, both in `SharedBatchTest`:

- `RunUI` must not be used for an action that can open a modal dialog; `ShowDialog<T>`
  exists for that and correctly uses `AppBeginInvoke`. `AutoQcFunctionalTest.BasicTest`
  calls `RunUI(() => configForm.ClickSave())`.
- `AppInvoke` should not be able to hang a run indefinitely. Bounding it turns "hangs
  forever" into a test failure with a stack, which is the difference between a suite that
  can run unattended and one that cannot.

Note this is the same shape as the two modal hangs already fixed in SkylineBatch: the
harness has no defence against a blocking UI action, so every such bug presents as a hang
rather than a failure. Worth fixing once, in the base class.

### Test byproducts are written into the source tree

Two places write into the checkout rather than `TestResults`, and leave the files behind
when the test fails:

- `ConfigManagerTest.TestImportExport` exports to `TestUtils.GetTestFilePath("configs.xml")`,
  i.e. `SkylineBatchTest\Test\configs.xml`.
- `BcfgFileTest` writes `*_replaced.bcfg` beside the baselines in
  `SkylineBatchTest\Test\BcfgTestFiles\` and only deletes them on the success path.

A failing run therefore leaves ~20 untracked files in the source tree. `96a86b7507
"Fix test infrastructure to use TestResults instead of source tree"` did this work for
other cases; these two were missed. Cleaned up by hand for now.

**Fix applied**: an early `if (FunctionalTest) return true;` in `InitSkylineSettings()`
in **both** `SkylineBatch/Program.cs` and `AutoQC/Program.cs`, immediately after the
`FindSkyline()` attempt and before the modal form. This mirrors the `FunctionalTest`
guards already sitting around `SendAnalyticsHit()` and `AddFileTypesToRegistry()` in the
same files. `FindSkyline()` still runs, so `Settings.Default` is still populated when an
installation does exist; only the interactive fallback is skipped. A test that genuinely
needs a Skyline path now fails with a message instead of hanging forever -
`AutoQCTest.TestUtils.GetTestSkylineSettings()` already returns `null` in that case, so
the null-installation path is one the tests were written to tolerate.

### Phase 0 findings - ReSharper analyses EVERY target framework, not one

This is the single most important thing learned so far, and it reframes the rest of the
plan.

`jb inspectcode` on a multi-target project reports the **union** of the issues from all
declared TFMs. Proof, from the two AutoQC runs on the same tree:

- Before 0.1: 324 errors, all `Cannot resolve symbol` for MSTest types. Those can only
  come from the **net472** leg - net8 already had the MSTest NuGet packages.
- Both runs: 4 x `CA1416` in `CommonUtil`. `CA1416` is a net5+ platform-compatibility
  analyzer that cannot fire on net472, and `Directory.Build.targets` suppresses it only
  when `TargetPlatformIdentifier == 'Windows'`, which `CommonUtil`'s plain `net8.0` leg
  is not. So those can only come from the **net8** leg.

Both in one report means both legs are analysed. **A solution is only ReSharper-clean
when every TFM it declares compiles cleanly** - there is no "inspect just the net8 leg"
without changing what the projects declare. This is why 0.1 was a prerequisite rather
than a detour, and it is the crux of the open question about Skyline below.

### Skyline baseline - and why the first number was worthless

Two measured runs, same tree, same commit:

| Run | Total | Errors | Warnings |
|---|---|---|---|
| Unpinned (all declared TFMs) | **161,478** | 149,436 | 12,042 |
| Pinned `TargetFramework=net8.0-windows` | **4,252** | 3,014 | 1,238 |

The first run is 97% artefact. `inspectcode` analyses every TFM a project declares, and
on this branch the **net472 leg of `Skyline.sln` does not resolve** - the pwiz-sharp
vendor projects (Thermo, Waters, Sciex, Agilent, Bruker, Shimadzu, UIMF, UNIFI) are built
for net8 only, and the build log warns about each one before the inspection starts.
Sampling the 149,436 `CSharpErrors` confirms it: *"Cannot resolve symbol"* and *"The type
is defined in an assembly that is not referenced"*. The 4,585 `RedundantUsingDirective`
hits were the same cascade in disguise - a `using` looks unused once the types behind it
stop resolving - which is how you can tell the non-error counts were contaminated too.
`master`'s gate is clean at zero, so none of that could have been real.

**Correction to Phase 0.2 as originally written.** It claimed the "jb --no-build against
Skyline.sln" half of the old refusal "does not survive contact with how inspectcode
actually works". That was wrong, and the measurement says so. The refusal was pointing at
something real. `Build-Skyline.ps1` now pins the TFM on the net8 path and carries these
numbers as the reason.

#### The pin is not the whole answer either - 3,014 errors survive it

| Project | Errors | Why |
|---|---|---|
| `TestTutorial` | 1,367 | **not in the net8 build list** - `build.bat` builds Skyline + CommonTest + Test + TestData + TestFunctional + TestConnected + TestRunner, and nothing else |
| `TestPerf` | 1,213 | same |
| `SkylineTester` | 20 | same |
| `ProteowizardWrapper` | 321 | targets **`net472;net8.0`**, not `net8.0-windows` - the pin gives it a TFM it does not declare |
| `CommonUtil` | 24 | same |
| `SkylineNightlyShim` | 4 | same |
| `Skyline` | 65 | knock-on from the above |

2,584 of the 3,014 are the single message *"The type is defined in an assembly that is
not referenced"*. So the residue is two clean, separable causes, neither of which is a
code defect:

1. **Projects the net8 path never builds.** Either add them to the net8 project list or
   exclude them from the report with `--project=`; do not leave them half-analysed.
2. **Projects on plain `net8.0`.** `inspectcode` has no per-project TFM switch, so one
   pinned pass cannot cover both `net8.0-windows` and `net8.0`. The fix is **two passes** -
   one pinned to each - with the second `--project=`-limited to
   `ProteowizardWrapper`, `CommonUtil`, `SkylineNightlyShim`. Recommended shape for 0.2b.

#### The real signal underneath: ~1,238 warnings on the net8 leg

| Project | Count | | Inspection | Count |
|---|---|---|---|---|
| `Skyline` | 595 | | `PossibleNullReferenceException` | 614 |
| `TestFunctional` | 159 | | `RedundantCast` | 168 |
| `TestUtil` | 68 | | `AssignNullToNotNullAttribute` | 155 |
| `TestTutorial` | 66 | | `RedundantDelegateCreation` | 80 |
| `Test` | 53 | | `RedundantUsingDirective` | 61 |
| `TestPerf` | 44 | | `RedundantNameQualifier` | 26 |
| `SkylineTester` | 43 | | `LocalizableElement` | 25 |
| `CommonUtil` | 38 | | `ConditionIsAlwaysTrueOrFalse` | 23 |
| `TestData` | 33 | | `CSharpWarnings::CS0618` | 17 |
| `Common` | 31 | | everything else | 69 |

Treat this as **approximate until the two-pass fix lands** - warnings from a project whose
references did not resolve are not trustworthy, so `TestTutorial`/`TestPerf`/
`ProteowizardWrapper` counts in particular will move.

**This is the headline for the port.** `master`'s TeamCity gate reports zero for the
net472 leg. The net8 leg has never been inspected by anything, and carries on the order of
**1,200 warnings that no gate has ever seen**. That is the actual size of "clean of
warnings and errors for Skyline", and it is a different order of magnitude from the batch
tools (70 unique each). Half of it is nullability
(`PossibleNullReferenceException` + `AssignNullToNotNullAttribute` = 769), which is
expected: net8's annotated BCL tells ReSharper about nulls that net472's did not.

### Phase 1 - baseline

**AutoQC baseline captured 2026-08-23** via `Build-AutoQC.ps1 -RunInspection`:
**0 errors, 83 warnings** (was 0 errors reachable at all - the solution did not build).

| Project | Count |
|---|---|
| `CommonUtil` | 37 |
| `SharedBatch` | 12 |
| `CommonBaseUI` | 10 |
| `AutoQC` | 9 |
| `SharedBatchTest` | 8 |
| `PanoramaClient` | 5 |
| `AutoQCStarter` | 2 |

| Inspection | Count |
|---|---|
| `AssignNullToNotNullAttribute` | 22 |
| `RedundantCast` | 21 |
| `PossibleNullReferenceException` | 19 |
| `CA1416` | 4 |
| `CSharpWarnings::CS0618` | 3 |
| `RedundantUsingDirective` | 3 |
| everything else (7 kinds) | 11 |

Two thirds of it is in shared assemblies (`CommonUtil` 37, `CommonBaseUI` 10,
`PanoramaClient` 5 = 52 of 83), which Skyline also consumes - so fixing those pays for
both solutions and should be done first. `SpectrumMetadata.cs` alone carries 12 and
`CommonTextUtil.cs` 6 (all 4 `CA1416` plus 2 more).

- [ ] **1.1 Capture the WARNING+ baseline for all three solutions** and record the
      counts in this file (total, and grouped by inspection `TypeId`). Save the raw XML
      under `ai/.tmp/sessions/<date>-<session>/` - it is diagnostic output, not a
      durable record.
- [ ] **1.2 Diff Skyline's net8 result against the master TeamCity baseline** (#19161,
      zero issues). Anything Skyline reports here is net8-port-introduced by definition,
      which makes it both higher priority and easier to attribute.
- [ ] **1.3 Sort the findings**: (i) real defects, (ii) mechanical and safe to autofix,
      (iii) noise that should be a profile severity change rather than a code change.
      Bucket (iii) goes in the Skyline baseline `.DotSettings` plus the
      `Sync-DotSettings.ps1` `$overrides` map, per section 4.

### Two things that change how this backlog must be worked

Both were learned by measurement, and both mean "apply ReSharper's suggested fix" is the
wrong default here.

**1. A finding can be valid on one target framework and breaking on the other.**
`inspectcode` reports the union of every declared TFM, so a warning that is correct for
net8 may be describing code that net472 cannot compile without. Confirmed cases:

| Site | Why it cannot be "fixed" |
|---|---|
| `NaturalComparer.cs` `REGEX.Matches(s).Cast<Match>()` | `MatchCollection` is `IEnumerable<Match>` on net8, non-generic on net472, where `.Reverse()` then will not compile |
| `HttpClientWithProgress.cs` `cookies.Cast<Cookie>()` | `CookieCollection` became `ICollection<Cookie>` on net8 only |
| `ConcurrencyVisualizer.cs` redundant `return` | everything after it is `#if NET472`; the `return` only looks redundant on net8 |

These take a documented `// ReSharper disable once <Inspection>`, which is already the
codebase's idiom (`MappedList.cs`, `PrimitiveArrays.cs`, `Assume.cs` all use it). **Check
both legs before deleting anything a redundancy inspection points at.**

**2. `LangVersion` is not uniform, so the same warning has opposite correct answers.**
`pwiz_tools/Directory.Build.props` sets `8.0`; `CommonUtil`, `CommonBaseUI`,
`PanoramaClient`, `SharedBatch` and the batch test projects override to `latest`. The
`(double?)null` casts in a ternary are genuinely redundant under C# 9+ target-typed
conditionals - and **required** under 8.0. `Skyline.csproj` inherits 8.0, which is where
most of the 1,200-warning backlog lives, so the `RedundantCast` hits there will mostly
NOT be removable the way they were in `SpectrumMetadata` and `ImmutableList`. Check the
project's effective `LangVersion` first.

### Phase 2 - fix

**Progress 2026-08-23** (all through the standard scripts, both TFMs building, tests
re-verified at 36/38 after each batch):

| Solution | Baseline | Now |
|---|---|---|
| AutoQC | 83 | **51** |
| SkylineBatch | 106 | **86** |
| Skyline | 1,238 warnings + 3,014 artefact errors | untouched |

52 raw warnings cleared, concentrated in the shared assemblies so each fix counts against
both batch solutions and against Skyline. What is left in the batch tools is mostly
`PossibleNullReferenceException` and `AssignNullToNotNullAttribute`, which need
caller-level reasoning rather than a mechanical edit - resist `?? string.Empty` unless the
invariant that makes it safe is real and gets written down.



- [ ] **2.1 Skyline** - clear WARNING+ to zero.
- [ ] **2.2 SkylineBatch** - clear WARNING+ to zero.
- [ ] **2.3 AutoQC** - clear WARNING+ to zero.
- [ ] Commit per solution, not one giant sweep, so a regression bisects cleanly.
- [ ] Every commit: build plus `Build-Skyline.ps1 -RunTests -TestName CodeInspection`
      (the custom `CodeInspectionTest` is a different gate from ReSharper - line
      endings, BOM, resource strings - and both must pass).
- [ ] Watch `ai/CRITICAL-RULES.md` while fixing: no `async`/`await`, no English literals
      in test assertions, `Assert.IsNotNull` not `AssertEx.IsNotNull` (ReSharper only
      recognises the former as a null-guard, which is itself a source of NRE warnings),
      CRLF line endings in pwiz.

### Phase 3 - keep it green

- [ ] **3.1** Get `SkylineBatch.sln` and `AutoQC.sln` inspected by something other than a
      developer remembering to pass a switch. Either a TeamCity config alongside
      `ProteoWizard_WindowsX8664msvcProfessionalSkylineResharperChecks`, or fold them
      into it. Without this, Phase 2 decays.
- [ ] **3.2** Decide whether the Skyline Code Inspection build should run for PRs whose
      base is a work branch rather than master. The whole net8 line has been developing
      without it.
- [ ] **3.3** Record the outcome in `ai/docs/build-and-test-guide.md`.

## Open questions

1. **Who owns the net472 MSTest fix?** It is a defect in the net8 port
   (`6f06a355d9`), not in this work. Fixing it here is the pragmatic path since it
   blocks everything, but it should be agreed with Matt rather than landed silently
   under a "ReSharper cleanup" title.
2. ~~**Does net472 still need to build at all on this line?**~~ **Answered 2026-08-23:
   yes.** The port multi-targets on purpose and master still ships net472, so dropping
   the `net472` TFM is not an option. Option 0.1(a) it is.
3. **Scope of "errors"**: ReSharper ERROR severity, or compiler errors too? The two
   build breaks above are compiler errors and are treated as in scope here because they
   block the ReSharper gate.

## Working notes

Standard scripts only - do not hand-roll the inspector:

```
pwsh -File ./ai/scripts/Skyline/Build-Skyline.ps1 -RunInspection
pwsh -File ./ai/scripts/SkylineBatch/Build-SkylineBatch.ps1 -RunInspection
pwsh -File ./ai/scripts/AutoQC/Build-AutoQC.ps1 -RunInspection
```

TeamCity reference for the master baseline:

```
search_builds(build_type_id="ProteoWizard_WindowsX8664msvcProfessionalSkylineResharperChecks", branch="master")
get_code_inspections(build_id=4148893)
```

## Appendix - provisional SkylineBatch numbers (NOT the baseline)

One out-of-band inspection pass over `SkylineBatch.sln` completed before that approach
was abandoned. It ran against the broken reference graph described in section 2, so it
is **not** a baseline and Phase 1.1 must re-measure through `Build-SkylineBatch.ps1`.
It is recorded here because it sizes the job and corroborates the root cause. Raw XML:
`ai/.tmp/sessions/20260823-d576ed81/skylinebatch-inspect-provisional.xml` (gitignored).

470 issues at WARNING+: **324 ERROR, 146 WARNING**.

**The errors are the build break, not a code backlog.** 322 of the 324 are
`CSharpErrors` / "Cannot resolve symbol", concentrated in `SkylineBatchTest` (334
WARNING+ total) and `SharedBatchTest` (47) - i.e. the unresolved MSTest reference
cascading through every test file. Expect that count to collapse to ~2 once Phase 0.1
lands. The two survivors are worth a look on their own: one "Interface member is not
implemented" and one "type arguments cannot be inferred from the query".

**The warnings are the real backlog.** Excluding test projects, 89 WARNINGs:

| Project | Count | Dominant types |
|---|---|---|
| `CommonUtil` | 37 | RedundantCast 14, AssignNullToNotNullAttribute 9, PossibleNullReferenceException 5, CA1416 4 |
| `SkylineBatch` | 25 | AssignNullToNotNullAttribute 9, PossibleNullReferenceException 8, CS0618 3, RedundantDelegateCreation 3 |
| `SharedBatch` | 12 | AssignNullToNotNullAttribute 7, RedundantCast 4 |
| `CommonBaseUI` | 10 | PossibleNullReferenceException 5, plus singles |
| `PanoramaClient` | 5 | ConstantNullCoalescingCondition 2, ConditionIsAlwaysTrueOrFalse 2 |

Two observations that shape Phase 1:

- **`CommonUtil` (37) and `CommonBaseUI` (10) are shared with Skyline**, and
  `CommonBaseUI` is the assembly PR #4587 just created by splitting CommonUtil. These
  will show up in the Skyline baseline too - do not fix them twice, and check whether
  they are split fallout that belongs in #4587 rather than here.
- The mix is roughly half nullability (`AssignNullToNotNullAttribute` 33 +
  `PossibleNullReferenceException` 39 across all projects) and half redundancy
  (`RedundantCast` 21, `RedundantUsingDirective` 29). The redundancy half is largely
  mechanical; the nullability half needs judgement and is where real defects hide.

## Files expected to change

- `pwiz_tools/Skyline/Executables/SharedBatch/SharedBatchTest/SharedBatchTest.csproj`
- `pwiz_tools/Skyline/Executables/SkylineBatch/SkylineBatchTest/SkylineBatchTest.csproj`
- `pwiz_tools/Skyline/Executables/AutoQC/AutoQCTest/AutoQCTest.csproj`
- Skyline test `.csproj` files (pending the 0.1 confirmation)
- `ai/scripts/Skyline/Build-Skyline.ps1` (net8 inspection wiring - pwiz-ai master)
- Source files across `Skyline`, `SkylineBatch`, `AutoQC` per the Phase 1 baseline
- Possibly `pwiz_tools/Skyline/Skyline.sln.DotSettings` plus
  `ai/scripts/Skyline/scripts/Sync-DotSettings.ps1` (severity retuning only)
