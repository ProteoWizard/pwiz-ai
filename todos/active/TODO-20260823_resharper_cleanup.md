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

- [ ] **0.1 Fix net472 MSTest resolution in the SDK-style test projects.**
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

### Phase 1 - baseline

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

### Phase 2 - fix

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
