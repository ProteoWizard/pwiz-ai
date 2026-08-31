# CommonUtil: break the WinForms dependency so ProteowizardWrapper can be plain net8.0

## Branch Information
- **Checkout**: `C:\proj\pwiz-work1` (the team's **Integration** checkout, agreed at the
  2026-08-17 dev meeting; SkylineNightly runs against Matt's PR will start here)
- **Branch**: `Skyline/work/20260818_commonutil_winforms_split` - branched off **`chambem2/pwiz-sharp`**
  @ `5ef89bd228`, NOT master. The PR targets that branch too, so Matt reviews it against his own work.
- **Created**: 2026-08-18
- **Status**: Implemented, verified and committed (4 commits) on 2026-08-18. Not pushed; no PR open yet.
- **Module**: `skyline`
- **Related**: #4497 (our Osprey PR, `C:\proj\pwiz`, stacked on the same base)

## Why

`ProteowizardWrapper`'s net8 target is `net8.0-windows` because it depends on
`pwiz.CommonUtil`, which sets `UseWindowsForms=true`. That is believed to be wrong by
design: **CommonUtil is not supposed to depend on WinForms; `Common` is allowed to.**

It has a concrete downstream cost. Osprey must be plain `net8.0` to run on Linux, so it
cannot reference the wrapper at all, and #4497 therefore reads pwiz-sharp DIRECTLY and
reproduces six `MsDataFileImpl` semantics by hand. Fix CommonUtil and the wrapper can be
plain `net8.0`, Osprey can go back through it, and those six semantics are inherited from one
place again.

## Measured state (2026-08-18, before any edits)

CommonUtil: **16 of 113 .cs files** reference `System.Windows.Forms` or `System.Drawing`.
Per namespace, for the four the wrapper actually uses:

| Namespace | WinForms-tainted |
|---|---|
| `Chemistry` | 0 of 9 |
| `Spectra` | 0 of 3 |
| `Collections` | 1 of 28 |
| `SystemUtil` | 11 of 59 |

## Plan: move to Common, keep namespaces

**The move is cheaper than it looks.** If types keep their namespaces
(`pwiz.Common.SystemUtil` etc.) and only change ASSEMBLY, **no call site changes** - only
project references. Projects referencing both (Skyline) see nothing; the only ones that break
are those referencing CommonUtil but not Common, which are exactly the ones we want to keep
WinForms-free.

### Tier 1 - free win
- [x] `Collections/LinqExtensions.cs:26` - `using System.Windows.Forms;` with **no WinForms
      type used anywhere in the file**. Delete the line. This alone makes `Collections` clean.

### Tier 2 - genuinely GUI, move to Common as-is
- [x] `GUI/CommonAlertDlg.cs` + `.Designer.cs`, `GUI/MessageIcons.cs`
- [x] `CommonResources/Images.Designer.cs`
- [x] `SystemUtil/CenterWinDialog.cs`, `CommonFormEx.cs`, `FormUtil.cs`,
      `TreeViewStateRestorer.cs`, `ConcurrencyVisualizer.cs`
- [x] `SystemUtil/PInvoke/User32.cs`, `User32Extensions.cs`, `PInvokeCommon.cs`
      (CRITICAL-RULES wants PInvoke isolated in one place - keep them together)

### Tier 3 - do NOT move wholesale; these need thought
- [x] `SystemUtil/CommonActionUtil.cs` - **split, do not move.** `RunAsync` is the async
      helper CRITICAL-RULES mandates for all `pwiz_tools/Shared` code, so it must stay
      portable. Only `SafeBeginInvoke(Control control, Action action)` is WinForms. Moving
      the class would force WinForms onto every Shared consumer.
- [x] `SystemUtil/Caching/Producer.cs` + `Receiver.cs` - thread `Control ownerControl`
      through the API (`RegisterCustomer(Control, ...)`, `HandleDestroyed`,
      `InvokeRequired`). Genuinely UI-lifetime-bound, so moving wholesale is honest.
      Abstracting behind `ISynchronizeInvoke` is possible but more work for less clarity.

### Tier 4 - the payoff
- [x] Drop `UseWindowsForms` from `CommonUtil.csproj`; retarget it off `net8.0-windows`
- [x] Make `ProteowizardWrapper` plain `net8.0` (it has **zero** WinForms usage of its own -
      verified 2026-08-17)
- [x] **Retire `PortableUtil`** if it is now redundant. It is only 10 files (CLI argument
      parsing + `CommandStatusWriter`), created for master because CommonUtil was too tied to
      net472. A WinForms-free CommonUtil is the right home for exactly that content.

## Rejected alternative

Moving what `ProteowizardWrapper` needs INTO `PortableUtil` and breaking its CommonUtil
dependency. PortableUtil is a 10-file sharing layer, not a utility library; putting
`SignedMz` / `ImmutableList` / `SpectrumMetadata` there makes it CommonUtil #2 and entrenches
the split we want to remove - and it leaves CommonUtil WinForms-bound, so the next portable
consumer hits the same wall.

## Also for this PR into Matt's branch

- [x] **`BrukerFormat.cs` XML doc fix** (currently carried in the #4497 branch, belongs
      here): `<see cref="CompassXtractData"/>` is CS1574 when that file is compiled out
      without vendor licenses, so **Bruker does not build in the no-licenses configuration**.
      Change the two references to `<c>`. Once this lands in Matt's branch, DROP it from the
      Osprey branch on the next rebase.
- [x] **Investigate: does a Release Skyline link the DEBUG pwiz-sharp assemblies?**
      `Skyline.sln` includes `ProteowizardWrapper` / `CommonUtil` / `PortableUtil` as
      solution members, but does NOT include the pwiz-sharp projects - the wrapper reaches
      them by `ProjectReference` from outside the solution. That is the same shape that makes
      Osprey deploy Debug pwiz-sharp into a Release build (MSBuild's
      `ShouldUnsetParentConfigurationAndPlatform`). **Not verified by building Skyline** -
      the mechanism is identical but the symptom was only observed on Osprey. If it
      reproduces, the fix is to put the pwiz-sharp projects in the solution, which is also
      what makes Osprey consistent with Skyline.

## Caveats on the analysis

Measured: file counts, per-namespace WinForms usage, and what the two risky files use it for.
NOT done: checking what depends on the 13 Tier-2 files (a move changes which assemblies need
a `Common` reference), and nothing has been built. This is a scoped recommendation, not a
validated plan. Expect a full Skyline build + test cycle to be the bulk of the work.

## Enforce it, do not just fix it (Brendan, 2026-08-18)

`SafeBeginInvoke` is a mistake of naming convenience, not a design choice - someone reached
for CommonUtil and forgot it is meant to be WinForms-free. A rule with no verifier drifts,
which is exactly what CRITICAL-RULES says: *"Trust comes from verifiers, not from the LLM...
When a rule's verifier is weak, the rule will drift; strengthen the verifier rather than the
wording."* So the fix must come with a CodeInspection rule.

- [x] Move `SafeBeginInvoke(Control, Action)` to a new `ControlUtil` in
      **`pwiz.Common.Controls`** - that namespace **already exists in `Common`**
      (`Common/Controls/AutoScrollTextBox.cs`, `Controls/Clustering/*`), so this needs no new
      structure.
- [x] Add a CodeInspection rule forbidding WinForms in CommonUtil, modelled on the existing
      one in `pwiz_tools/Skyline/Test/CodeInspectionTest.cs:221`:

      AddForbiddenUIInspection(@"*.cs", @"namespace pwiz.Skyline.Model",
          @"Skyline model code must not depend on UI code");

      whose regex forbids
      `(pwiz\.Skyline\.(Alerts|Controls|.*UI)|System\.Windows\.Forms|pwiz\.Common\.GUI)\.`

### Two gotchas found while checking the pattern

1. **The new rule must key on DIRECTORY, not namespace.** `Common` and `CommonUtil` SHARE the
   `pwiz.Common.*` root - Common owns `pwiz.Common.Colors` / `Controls` / `DataAnalysis`,
   CommonUtil owns `pwiz.Common.GUI` / `SystemUtil`. A `namespace pwiz.Common` cue would also
   flag `Common`, where WinForms is legitimate. Scope it to
   `pwiz_tools/Shared/CommonUtil/**` instead. `AddTextInspection` already takes a directory
   filter (see the `NonSkylineDirectories()` argument at CodeInspectionTest.cs:226), so the
   mechanism exists.
2. **`pwiz.Common.GUI` is ALREADY on the forbidden list** in that same regex - the codebase
   already classifies it as UI. It is simply in the wrong ASSEMBLY. That is independent
   corroboration for moving `CommonUtil/GUI/*` into `Common`: everything else already treats
   that namespace as UI code.

Sequencing note: land the inspection rule LAST, after the moves, or the test goes red on the
very changes that fix it.

## This is not a new idea - it advances an existing backlog item

`ai/todos/backlog/TODO-ui_free_model_phase2.md` ("Phase 2: UI-free Model and report export",
partially complete via PR #3700) already lists the remaining work, and two of its three items
are what this TODO does:

| Backlog item | Relationship |
|---|---|
| **T1** - "Add folder-based Model scan (path-based, not just namespace-based) in CodeInspectionTest" | **Exactly gotcha 1 above.** I derived the need for a directory-scoped rule independently, from the fact that `Common` and `CommonUtil` share the `pwiz.Common.*` root; T1 had already recorded that namespace-based scanning is the loophole. Build the CommonUtil rule as part of T1's path-based mechanism, not as a one-off. |
| **T6** - "Audit Common for WinForms usage that could be transitively pulled by Model" | **This audit, arrived at from the other end.** T6 framed it as a Model risk; we hit it as `ProteowizardWrapper -> CommonUtil -> WinForms` blocking a plain-net8.0 wrapper for Osprey on Linux. Same dependency, different consumer - which makes the case stronger, not weaker. |
| **T2** - "Util split guardrails (Model/Util vs Skyline/UtilUI separation)" | The larger vision Brendan described: move `Skyline\Model` to its own DLL, rename `Skyline\Util` to `UtilUI`, and move Model-required classes into `Skyline\Model\Util`, because `Skyline\Util` is still where the separation is unenforced. NOT in scope here, but this work should not make it harder. |

**Historical context (Brendan, 2026-08-18)**, worth recording because it explains the shape:
`pwiz.Common` was loosely defined by Nick before the UI-vs-Model separation was clarified.
His fix was to split the classes into TWO DLLs while KEEPING the shared namespace - initially
even in the same folder structure, before `Common` and `CommonUtil` became separate folders.
So the namespace overlap that defeats a namespace-based inspection rule is a deliberate
compatibility artifact, not an oversight. That is also why moving types between the two
assemblies costs no call-site changes - the namespace was always the constant.

## Session end 2026-08-18

Analysis complete, execution not started. `C:\proj\pwiz-work1` is checked out on
`chambem2/pwiz-sharp` @ `5ef89bd228` and clean, ready to work in. Nothing has been built
there yet - budget for a first full Skyline build.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260818_commonutil_winforms.md` before starting work.

## Session 2026-08-18 (second): implemented, built, and verified

All four tiers are done, `CodeInspection` passes, and the inspection rule is proven to
fire. Committed as 4 commits on `Skyline/work/20260818_commonutil_winforms_split` (base `5ef89bd228`); working tree clean, nothing pushed.

### The assembly is called CommonBaseUI, and it is new

The plan said "move the 13 GUI files into `Common`". Measuring what actually depends on
them changed that decision. **Five projects reference `CommonUtil` but not `Common`, and
every one of them uses the types being moved:**

| Project | In `Skyline.sln`? | Types used |
|---|---|---|
| `Shared/PanoramaClient` | yes | `CommonAlertDlg`, `CommonFormEx`, `FormUtil`, `TreeViewStateRestorer` |
| `Shared/CommonFileDialogs` | yes | `CommonFormEx` |
| `Executables/AutoQC` | no | `CommonAlertDlg`, `FormUtil` |
| `Executables/SharedBatch` | no | `CommonAlertDlg`, `CommonFormEx`, `FormUtil` |
| `Executables/SkylineBatch` | no | `CommonAlertDlg` (10 files), `FormUtil` |

The plan predicted this set but read it as harmless - "exactly the ones we want to keep
WinForms-free". That is backwards: they are all WinForms GUI projects. Moving the types
into `Common` would have put NHibernate, System.Data.SQLite, WebView2, MathNet.Numerics,
ZedGraph, MSGraph, Sprache and log4net onto three standalone shipped tools whose only real
need is `CommonAlertDlg`. The last three are not in `Skyline.sln`, so our build would have
gone green while they broke for their maintainers.

So the WinForms types went into a NEW small assembly, `pwiz.CommonBaseUI`
(`pwiz_tools/Shared/CommonBaseUI/`), which references only `CommonUtil`. Named for the
convention that `Common` should eventually become `CommonUI` for the bulk of the UI; this
one holds the base types everything builds on. Namespaces are unchanged, so no call site
moved.

### What is in each assembly now

`CommonBaseUI` (18 files): `GUI/CommonAlertDlg` + `GuiMessages` + `MessageIcons`,
`CommonResources/Images` + `GeneralTerms` (+ `Copy.bmp`, `SuccessMessageIcon.png`),
`SystemUtil/{CenterWinDialog, CommonFormEx, FormUtil, TreeViewStateRestorer,
ConcurrencyVisualizer}`, `SystemUtil/PInvoke/{User32, User32Extensions, PInvokeCommon}`,
`SystemUtil/Caching/Receiver` + new `ProducerControlExtensions`, and new
`Controls/ControlUtil`.

`CommonUtil` is now WinForms-free and **plain net8.0** (`net472;net8.0`, no
`UseWindowsForms`). `ProteowizardWrapper` is plain `net8.0` too - confirmed via its
`deps.json` reading `.NETCoreApp,Version=v8.0`. That was the whole point.

### Corrections to the original analysis

- **Tier 1 was not a free win.** `SortOrder` at `LinqExtensions.cs:32` IS a WinForms type
  (`System.Windows.Forms.SortOrder`), so deleting the `using` alone breaks the build. The
  overload that uses it has ZERO call sites anywhere in `pwiz_tools`, so the fix was to
  delete the dead overload along with the `using`.
- **`GeneralTerms` had to move too.** It is `internal`, and `CommonAlertDlg` is its only
  consumer - it is dialog button text (Abort/Cancel/Ignore/No/OK/Retry/Yes).
- **`Producer` could NOT move** with `Receiver`. `Production.cs` and `ProductionFacility.cs`
  both depend on `Producer`, and they stay in CommonUtil, so moving it would have made
  CommonUtil depend on CommonBaseUI - a cycle. Only `Receiver` moved; `Producer`'s one
  `Control`-typed factory method became `ProducerControlExtensions.RegisterCustomer`, an
  extension method in the SAME namespace. Note that extension methods need the namespace
  imported, which an instance method did not: `AreaAbundanceComparisonGraphPane.cs` needed
  a new `using pwiz.Common.SystemUtil.Caching;`.
- **Plain net8.0 loses DPAPI.** `CommonTextUtil.EncryptString`/`DecryptString` need the
  `System.Security.Cryptography.ProtectedData` package once the project is not
  `net8.0-windows`. Added. **It throws `PlatformNotSupportedException` off Windows**, so a
  Linux consumer of CommonUtil must not call those two methods.

### PortableUtil is retired (Brendan, this session)

Its stated reason - "net8.0-capable staging ground for portable pieces of CommonUtil
(which is net472-only, non-SDK, and GUI/web-laden)" - is now false in all three clauses.
Its ten files (`CommandLine/*`, `SystemUtil/CommandStatusWriter.cs`) moved into CommonUtil
with namespaces unchanged, and the project is deleted from disk and from `Skyline.sln`,
`Osprey.sln` and `AutoQC.sln`. Skyline and Osprey share through CommonUtil directly now.

### Verification

- `Build-Skyline.ps1 -VendorLicenses` (net8 path): green, ~105s.
- `CodeInspection`: **passes**.
- **The new rule was proven to fire**, not just to pass: injecting
  `using System.Windows.Forms;` into `CommonActionUtil.cs` made the test fail citing the
  exact file and line, and reverting made it pass again. The path scoping is proven by the
  same run - CommonBaseUI is in the scan roots and is full of WinForms code, and does not
  flag.
- `CommonBaseUI` net472 leg builds green in isolation (this is the leg AutoQC,
  SharedBatch and SkylineBatch consume).

The rule needed a new mechanism: `PatternDetails` gained `RequiredPathMasks`, an INCLUSION
filter, because `ignoredDirectories` only excludes. That is backlog item **T1**
("path-based, not just namespace-based"), built as a general capability rather than a
one-off.

### Two bugs in Matt's branch, fixed here because they blocked verification

1. `BrukerFormat.cs` CS1574 - the fix already carried on the #4497 branch (was on this list).
2. `Skyline.csproj` copied `msparser.dll` unconditionally while `BiblioSpec.csproj` only
   emits `msparserD.dll` in Debug. **Every Debug build after the first one failed MSB3030**;
   the first passes only because the native directory does not exist yet when the guarding
   `Exists(...)` condition is evaluated. Now tracks `$(Configuration)`.

### Why nobody has noticed (established 2026-08-18 with Brendan)

Two different build paths, and they do not overlap:

- **Matt uses `quickbuild.bat`.** `make Skyline.exe` is marked **`explicit`** in
  `pwiz_tools/Skyline/Jamfile.jam:467`, so plain `quickbuild.bat` never builds the Skyline
  C# at all. He gets pwiz core from `quickbuild.bat` and Skyline from his own
  `pwiz_tools/Skyline/build.bat`, which is net8-only. His path never touches net472 Skyline.
- **The Skyline team uses `bs.bat`**, which `ai/docs/new-machine-setup.md` Phase 4 documents
  as the standard developer build: `bs.bat` -> `b.bat` -> `pwiz_tools/build-apps.bat` ->
  bjam target `pwiz_tools\Skyline//Skyline.exe`, whose actions are literally
  `msbuild Skyline.sln` (Jamfile.jam:184/187/191) - **the net472 leg**.

The Skyline Jamfile does NOT pass `PwizCliAssembly`/`PwizCliHintPath` (MSConvertGUI's
Jamfile at :64 does; Skyline's does not), so ProteowizardWrapper takes the
`Condition="'$(PwizCliAssembly)' == ''"` branch. On master that branch reads
`obj\$(Platform)\pwiz_data_cli.dll` - exactly where the Jamfile's
`install-native-dependencies` rule (:458) has just staged it. On this branch it reads
`..\Lib\pwiz_data_cli.dll`, which does not exist.

That matches both observations exactly: `C:\proj\daily` (master, bs.bat-built) builds
`Skyline.sln` green, while `pwiz-work1` does not despite having the same staged DLLs in
`obj/x64`.

**Consequence: the first Skyline developer to run `bs.bat` on the Integration checkout hits
all 89 errors** - and `pwiz-work1` IS the Integration checkout as of the 2026-08-17 dev
meeting, with SkylineNightly runs meant to start there.

It also explains why `SkylineTester`/`SkylineNightly`/`SkylineNightlyShim` are absent from
`build.bat`'s `BUILD_TARGET` (:108): Matt never needed them there, because the team's
harness has always come from Jamfile:191. All three DO build clean on net8 today with zero
code changes (verified 2026-08-18), producing `SkylineTester.exe`, `SkylineNightly.exe` and
`SkylineNightlyShim.exe` - they are simply not wired into the net8 entry point.

So there are two non-exclusive routes, and the choice belongs to Matt and the team:
1. Fix the net472 leg (the HintPath cause is a revert to master's `obj\$(Platform)\`) so
   `bs.bat` works again and nothing else changes.
2. Move the pipeline to net8 - add the three harness projects to `build.bat`, and teach the
   Jamfile's Skyline target to call `build.bat` instead of `msbuild Skyline.sln`.

### The net472 leg of chambem2/pwiz-sharp does NOT build - NOT fixed here

`Skyline.sln` Debug|x64 fails with 91 errors at `5ef89bd228`, 89 of them in the net472 leg:

| Count | Project | Cause |
|---|---|---|
| 80 | ProteowizardWrapper | `HintPath`s point at `..\Lib\{pwiz_data_cli,MassSpec\MassSpecDataReader,Thermo\ThermoFisher.CommonCore.Data,SCIEX.Apis.Data.v1}.dll`, which do not exist and are not tracked. master resolves all four from `obj\$(Platform)\`, where the bjam build stages them (`pwiz_tools/Skyline/Jamfile.jam:458`) and where they sit right now. Introduced by `9c2a45ab15`, whose message says only "Net8 build is green". |
| 5 | TestRunnerLib | `Microsoft.VisualStudio.QualityTools.UnitTestFramework` unresolved (it IS on disk in VS PublicAssemblies) |
| 2 | Skyline | unconditional `ProjectReference` to pwiz-sharp `BlibBuild`/`BlibFilter`, which are net8.0-only |
| 2 | BiblioSpec | `OperatingSystem.IsWindows()` does not exist on net472 |

This is out of scope for our PR but Matt should know. It is NOT a stale-artifact problem -
`clean.bat` would delete `build-nt-x86` and the staged `obj/x64` deps and fix none of it.

### Deferred findings from /code-review max on the ai/ wrappers (2026-08-18)

The review found 15 issues, ALL in `ai/scripts/Skyline/*.ps1` and NONE in the pwiz
branch. Eight were fixed (staging every run, dotnet/vswhere guards, Clean/Rebuild verbs,
inspection refusal, detection banner, build-first hint, TODO contradictions). These six
are real but deferred - they are gaps in the wrapper, not blockers for the PR:

- [ ] **Hardklor is never built on the net8 path.** `build.bat:129` builds
      `Executables\Hardklor\Hardklor.vcxproj` with VS MSBuild first, because `dotnet build`
      cannot build a vcxproj. `Skyline.csproj:323` includes the exe under an `Exists(...)`
      condition, so a missing one is silently dropped and every Hardklor/Bullseye
      feature-detection test fails at run time after a green build.
- [ ] **`-Target Skyline -RunTests` runs a stale `Test.dll`.** The single-project mapping
      excludes Test.csproj and TestRunner.csproj, but the `$testDll` switch has no
      `Skyline` arm and falls through to `Test.dll`, so it tests the PREVIOUS build
      against the new Skyline-daily.dll. `-Target Test` has the same shape.
- [ ] **`TestTutorial` and `TestPerf` are never staged.** Stage-Net8Tests.ps1 is called
      with no `-Projects`, so its seven defaults are staged; both targets are still
      accepted by `-Target` and `-TestName`. The runner then reports "No tests found",
      which trips the heuristic in Run-Tests.ps1 and prints actively wrong advice.
- [ ] **A partial stage passes as success.** Stage-Net8Tests.ps1 warns and `continue`s
      per missing project output and still exits 0, so `$LASTEXITCODE -ne 0` never fires
      on an incomplete staging directory.
- [ ] **`-Target Solution` means two different things.** net472 builds all of
      `Skyline.sln`; net8 builds only build.bat's seven projects, silently dropping
      SkylineTester, SkylineNightly, SkylineCmd, SkylineTool, TestUtil and TestRunnerLib.
      This is the DEFAULT target, so a developer can change SkylineCmd, see a green
      build, and commit code that never compiled.
- [ ] **Docs still assert `bin\x64\Debug`** as the test output, log and runner location
      (`debugging/SKILL.md:101`, `skyline-tester/SKILL.md:26`, `docs/skylinetester-guide.md:20`,
      `docs/build-and-test-guide.md:173`). That directory still EXISTS on a net8 checkout
      with stale content, so following the docs opens an old log rather than failing.
- [ ] **DRY**: `$isNet8` detection (11 lines) and the staging invocation are copy-pasted
      between the two scripts, plus the `bin\staging-net8\$Configuration` literal in three
      places. If one regex is updated and the other is not, the build stages one place
      and the test runs another. Both scripts already dot-source `session/SessionState.ps1`.

### Follow-ups

- [x] Commit. 4 commits on `Skyline/work/20260818_commonutil_winforms_split`, 2 in `ai`. Neither pushed.
- [ ] Report the net472 breakage to Matt.
- [ ] `ai/scripts/Skyline/Deploy-SkylineMcp.ps1:26` hardcodes `..\..\..\pwiz\...`, so it
      always deploys from the `pwiz` checkout regardless of which one is active.
- [ ] Decide the #4497 sequencing now that the wrapper is plain net8.0 - Osprey can go back
      through it and stop reproducing the six `MsDataFileImpl` semantics by hand.
- [ ] Drop the `BrukerFormat.cs` fix from the Osprey branch on its next rebase.

## PR #4587 open, reviewed, threads resolved (2026-08-18 evening)

https://github.com/ProteoWizard/pwiz/pull/4587 - base `chambem2/pwiz-sharp`, label
`skyline`, head `Skyline/work/20260818_commonutil_winforms_split` @ `3b6755c392`. Pushed.
`ai` master pushed too (rebased onto 8 commits another machine had landed - no merge commit).

### `/code-review max` on the PR found real defects; 4 fixed in 3b6755c392

The earlier review had run with `C:\proj\ai` as cwd, so it only saw the wrapper scripts.
Re-run against the PR number, it found defects in the product change:

* **Installer manifests** - the only release-breaking one. `Product-template.wxs` and
  `FileList64-template.txt` still listed the deleted `pwiz.PortableUtil.dll/.pdb` (fails
  `light.exe`) and never gained `pwiz.CommonBaseUI.dll/.pdb`. Since `CommonFormEx` is the
  base class of nearly every Skyline dialog, a patched-but-unfixed installer throws
  `FileNotFoundException` at first form creation. Added the `ja`/`zh-CHS` satellites too.
  **Nothing in dev builds, TeamCity or SkylineTester catches this** - they copy whole output
  directories. Copilot found it independently.
* **P/Invoke allowlist silently narrowed** - `typeof(User32).Assembly` saw only CommonBaseUI
  after the move, dropping Advapi32/Gdi32/Kernel32/Shell32/Shlwapi. 20 `DllImport`s stopped
  being checked and the test stayed green. Now scans both assemblies AND asserts every
  expected type was reached.
* **Resource test sentinels** - `typeof(CommonFormEx).Assembly` was the stand-in for
  CommonUtil in `LocalizedResourcesTest` and `ResourcesTest`; it moved, so CommonUtil lost
  all localized-resource validation, and the self-check used the same broken expression.
  Restored via `typeof(Assume).Assembly`.
* **CRLF regression** - `core.autocrlf=true` flattened 5 files whose blobs were CRLF here.
  Restored the original blobs for the 3 moved `.cs` (back to `R100` renames, so
  `git blame --follow` survives) and re-stored both `.sln` unfiltered.
  **`fix-crlf.ps1` cannot catch this**: it is a working-tree tool filtering on `^( M|AM|A )`,
  the worktree was already correct, and the moved files were staged renames. Blob-level
  corruption is only visible by comparing blobs across commits.

### Deferred - see the "Deferred findings" section above for the full list

Not fixed, recorded rather than half-done at low context: `Osprey.sln` missing `CommonUtil`
(Debug DLL into a Release build via `ShouldUnsetParentConfigurationAndPlatform`), six
projects relying on transitive `CommonBaseUI` flow, the inspection rule banning
`System.Drawing` wholesale when it is portable on net8, `build.bat`'s `!` corruption under
delayed expansion, stale Osprey docs, and stale `.resx` designer anchors.

### Copilot review - both threads resolved

1. Installer manifests - already fixed in `3b6755c392` before the review landed.
2. Osprey net472 removal breaking the bjam vendor build - **deliberate** (Brendan: "we don't
   need any net472 support in pwiz-sharp"). Resolved with that rationale; #4497 deletes the
   `OspreyVendorReaderEnabled` machinery entirely and is already rebased on this branch.

### Still open for Matt

The PR body carries an **Open question**: is the net472 leg of `Skyline.sln` still meant to
build? It does not, for four reasons unrelated to this PR. Invisible from `quickbuild.bat`
(`make Skyline.exe` is `explicit`) but hit by `bs.bat` -> the bjam Skyline target ->
`msbuild Skyline.sln`, which is what `new-machine-setup.md` teaches. **Do not update
`new-machine-setup.md` until that is answered** - and note the Osprey TODO says that file
must not be edited until #4497 lands either, since `ai/` master serves every branch.

## Session 2026-08-18 (evening) - three shared defects fixed here, found from #4497

Brendan decided Osprey should read through `ProteowizardWrapper` rather than pwiz-sharp
directly, which this PR is what made possible. Building that reader surfaced three
pre-existing defects in shared code. They are fixed HERE rather than in #4497 because they
are Skyline-shared code and #4497 stacks on this branch. Two commits:

**`ba16d3c884` - Fixed vendor centroiding and the no-vendor build of the net8 wrapper**

1. **Vendor centroiding was a no-op.** `MsDataFileImpl` asks for centroiding by passing
   `"1-"` to `SpectrumList_PeakPicker`'s STRING overload, and that overload's private
   `ParseIntegerSet` splits on `,`/space and `int.TryParse`s each token - it has no range
   syntax at all. `"1-"` parsed to NOTHING, leaving an EMPTY level set, and an empty set
   means `GetSpectrum`'s level check matches no spectrum and returns every one of them
   unpicked. `IntegerSet.Parse` in the same assembly parses `"1-"` correctly (regex group
   `b3`, `e = int.MaxValue`) - the picker just never called it. Fixed by delegating.
   * **net472 is unaffected**: C++ `IntegerSet.cpp:96` handles the trailing dash, which is
     why `msconvert --filter "peakPicking vendor msLevel=1-"` has always worked. This is a
     defect in the managed re-implementation, not a long-standing Skyline bug.
   * `SpectrumListFactory` is unaffected: it builds a real `IntegerSet` via `.Parse()` and
     calls the `IntegerSet` overload. The blast radius was the string overload's callers -
     this wrapper and `TestHarness/ReaderTestConfig.cs`.
   * **Why it went unnoticed**: `_vendorCentroidPath` is assigned from
     `preferVendor && inner is IVendorCentroidingSpectrumList` ALONE, independent of
     `_msLevels`, so Thermo/Waters/Sciex still received vendor centroids. What was dead is
     the profile-to-centroid CV relabeling and the `VendorOnlyPeakDetector` fail-fast. The
     real exposure is **Agilent**, which does not implement that interface: Skyline asked
     for vendor centroids on net8 and silently got PROFILE peaks.
   * `"1"` parses fine either way, so MS1-only centroiding worked; `"1-"` and `"2-"` did
     not, and `"1-"` is what Skyline asks for whenever it wants both levels.
   * Regression test added at the seam that had no coverage - `SpectrumListFactoryTests`
     already covered spec-string parsing, but only through the factory, i.e. the correct
     path. `PeakPickingTests.SpectrumList_PeakPicker_StringOverloadParsesPwizIntervalSyntax`
     now pins the ctor overload for `1-`, `2-`, `1`, `1,2`, `2-3` and asserts it agrees
     with `IntegerSet.Parse`. **Committed UNRUN** - see the tooling gap below.

2. **The net8 wrapper did not compile without vendor licenses.** `MsDataFileImpl.cs:798`
   used `SpectrumList_LockmassRefiner` unguarded, and `Analysis.csproj` `Compile-Remove`s it
   (and `ChromatogramListLockmassRefiner`, and defines `NO_VENDOR_SUPPORT`) when
   `IAgreeToVendorLicenses` is not true. That is the configuration CI and the shipped zips
   build, and it is Osprey's default - so Skyline net8 was red for every no-vendor build.
   Same family as the `BrukerFormat.cs` CS1574 break #4497 hit: Osprey is the first consumer
   to build these projects no-vendor, which is why neither had surfaced. Guarded with
   `#if NO_VENDOR_SUPPORT`, throwing rather than silently dropping a correction the caller
   explicitly asked for.

3. **The two ways of agreeing to the licenses do not have the same reach**, which the guard
   in (2) made critical:

   | Route | Reaches pwiz-sharp | Reaches pwiz_tools |
   |---|---|---|
   | `-p:IAgreeToVendorLicenses=true` (`b.bat`, `build.ps1`, `Build-Skyline -VendorLicenses`) | yes | yes |
   | `i-agree-to-the-vendor-licenses.bat` -> `Directory.Build.user.props` | yes | **no** |

   `pwiz-sharp/Directory.Build.props` imports that `.user.props`, and MSBuild only walks it
   up from projects under `pwiz-sharp/`. So a guard keyed on the raw property would have
   been WRONG for anyone using the `.bat` route: pwiz-sharp would compile the refiners while
   the wrapper believed them absent, silently dropping Waters lockmass correction from a
   build that fully supports it. `ProteowizardWrapper.csproj` now imports the same file, so
   both routes agree. No change to anyone's workflow - Brendan's `b.bat` passes the flag on
   the command line, which is arguably the better route for the licence anyway, since the
   agreement is an explicit act per build rather than a file on disk asserting it.

**`b3a3072491` - Recorded vendor reader registration failures instead of dropping them**

`MsDataFileImpl.Vendors.cs` swallowed a failed vendor registration into `Debug.WriteLine`,
which is `[Conditional("DEBUG")]` - so every shipping build had an empty catch. The failure
then surfaces much later as ProteoWizard's "No registered reader recognized the file", a
message about the FORMAT when the cause was the BUILD. Now collected into
`VendorReaderRegistration.Failures` (the class went `internal` -> `public`) and left for the
host to surface, because this assembly has no opinion about where a host writes diagnostics.
Osprey prints them through `OspreyOutput`; Skyline has no consumer yet. This is #4497's
review finding #9, which Osprey had already fixed in its own copy - fixing it here is what
stops the two from diverging again.

### Gates

* `Build-Skyline.ps1 -Target Skyline -Configuration Debug -VendorLicenses` - **succeeds**,
  before and after all three changes.
* No-vendor build gets past the CS0246 that defect 2 caused; verified end to end by the
  Osprey build in `C:\proj\pwiz`, which is no-vendor by default and now builds
  `ProteowizardWrapper` on the way through.

### Found here, NOT fixed - for Matt

**Skyline net8 still cannot build no-vendor**, for a reason unrelated to the above. With
defect 2 fixed the build reaches Skyline's copy stage and fails on vendor native runtime
files a no-vendor build never produces: `MBI_SDK.dll`, `MIDAC.dll`, `MobilionShim.dll`,
`msvcp120.dll`, `msvcr120.dll`, `OFX.Logging.dll` and more, copied unconditionally by
`Skyline.csproj`. It does NOT block Osprey, which never builds `Skyline.csproj`, so it is
left alone rather than folded into this PR. Worth raising with Matt alongside the net472
`Skyline.sln` question already in the PR body.

### Tooling gap - no way to run pwiz-sharp's tests

`Build-Osprey.ps1` runs only `Osprey.Test`, `Build-Skyline.ps1`'s targets are all Skyline
projects, and the `Deny-DirectBuildTest` hook blocks `dotnet test`. So the `PeakPickingTests`
case above is committed without ever having been run. `IntegerSet.Parse` itself is covered
(`IntegerSetTests.Parse_AllFormatVariants` pins `"10-"`), and the licensed and no-vendor
builds both compile, so confidence is high - but that is not the same as a green test. Now
that Matt's branch is a build dependency of both Skyline and Osprey, a wrapper target for
pwiz-sharp's suite is worth adding.

## Session 2026-08-19 - rebased onto Matt's moving branch; Skyline tests still unrun

Branch is `9b88fecfb2`, clean, pushed. Rebased THREE times today as
`chambem2/pwiz-sharp` advanced: `e381040486` -> `b6fcff8754` (a master merge, 30 commits)
-> `c42140e7df` (adds `fb541bf0c3 Make SkylineCmd able to load Skyline at all on net8` and
`979660e18c Stop build.bat leaving cross-version MSBuild nodes behind`). Every rebase was
conflict-free, and `Build-Skyline.ps1 ... -VendorLicenses` is green on the current head.

The stack above it was rebased to match each time: #4588 onto this branch's new head, #4590
onto `chambem2/pwiz-sharp` directly.

### The vendor-licence import in this PR is what makes a Visual Studio build possible

Worth stating plainly because it is easy to lose in the diff. There are two ways to agree to
the vendor licences and they do NOT have the same reach:

| Route | Reaches pwiz-sharp | Reaches pwiz_tools |
|---|---|---|
| `-p:IAgreeToVendorLicenses=true` (`b.bat`, `build.ps1`, `Build-Skyline -VendorLicenses`) | yes | yes |
| `i-agree-to-the-vendor-licenses.bat` -> `Directory.Build.user.props` | yes | **no**, before this PR |

Visual Studio cannot pass `-p:`, so the `.bat` route is the ONLY one available to it. Before
this PR that route left `ProteowizardWrapper` compiling in NO_VENDOR_SUPPORT mode while
pwiz-sharp compiled with vendors - a split that produces the lockmass guard firing on a build
that fully supports Waters. `ProteowizardWrapper.csproj` now imports the same user.props.

Consequence for anyone building in VS: run
`pwiz-sharp\i-agree-to-the-vendor-licenses.bat` ONCE first. Without it the build fails at a
copy step naming `MBI_SDK.dll` / `MIDAC.dll` / `msvcp120.dll`, which reads as a missing-file
problem rather than a licence one. (Skyline net8 cannot build no-vendor at all - separate,
pre-existing, flagged for Matt.)

### smartBuildTrigger: fixed for #4588, still broken for this PR

Matt merged the fix (#4591) and it is now in this branch's ancestry. Confirmed on live PRs:

* **#4588 auto-triggers and passes** - its base is `Skyline/work/...`, which matches
  `base_branch.startswith("Skyline/work/")`.
* **#4587 and #4590 still report "no builds triggered"** - their base is
  `chambem2/pwiz-sharp`, a developer branch, which the condition does not match.

Also confirmed empirically: the script runs from the PR's OWN checkout, not from master.
Merging to master was necessary but not sufficient - the fix only took effect once Matt
updated his branch and we rebased onto it.

Suggested broadening for Matt: map any base that is not `master`/`release` to `master`. Every
PR here is ultimately headed for master, and the change list is still computed against the
real base, so the stacked-diff behaviour is unaffected.

### Still unrun: Skyline's own tests

Builds, Osprey tests and pwiz-sharp tests are green, but **no Skyline test has been run
against this branch**. That is the next session's job - SkylineTester with the default
release set, from `pwiz-work1`. A green build proves references resolve; it does not prove
runtime type loading, resource lookup, or installer layout survived moving the WinForms half
of CommonUtil into a new assembly.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260818_commonutil_winforms_split.md` before starting work.

## 2026-08-20/21 night session: parallel Docker run

Skyline's own suite HAS now been run against this branch, in parallel (Docker) mode - the
mode TeamCity uses. Two commits, not pushed:

* `c92b1c1540` checkpoints the branch work that was sitting uncommitted (net472 removal,
  font pin, app-local VC140 CRT, STA marshalling, staging defaults).
* `b763d46701` fixes the container-only graph failures.

### Root cause of the container-only graph failures

`InitializeComponent` adds `dockPanel` to `panel1` - laying it out at the 200x100
`UserControl` default - BEFORE `ApplyResources` applies the 736x444 from `Skyline.resx`.
`panel1`'s layout is suspended across that and its `ResumeLayout(false)` performs no
layout, so the anchor deltas cached from the 200x100 default are never refreshed. The next
layout pass on `panel1` - raised by `CoverControl`'s construction in
`DockPanelLayoutLock.EnsureLocked`, which passes `cover.Parent` to the
`Control(Control parent, string text)` base ctor - runs `DefaultLayout.ApplyCachedBounds`
and snaps `dockPanel` back to 200x100 permanently. Every docked graph pane collapses with
it: `GraphChromatogram` ends up 98x77 with a **negative-width chart rect**, so every
data-to-pixel conversion off it is garbage.

Ruled out by measurement, not argument: screen size (client area is 734x514 in BOTH), the
font pin, DPI value (96 both), resource resolution (`ApplyResources` replayed on a fresh
`Panel` inside the container returns 736x444 correctly), and launch mode (host via
`dotnet.exe TestRunner.dll` also passes). The host never fires `dockPanel.SizeChanged` at
all; the container fires it once, from `ApplyCachedBounds`.

Fix: re-assert `dockPanel.Anchor` after `InitializeComponent`, with layout live, so the
deltas are recaptured from the real bounds. Exact geometry preserved - `Dock = Fill` was
rejected because the resx deliberately overhangs `panel1` by 1px to hide the DockPanel
border.

Second, separate bug found once the layout was correct: `ComparePeakPickingDlg`'s
designer-wired `zedGraphFiles_Resize` runs before the constructor creates
`_axisLabelScaler`, so a resize message in between null-derefs. That was
`TestPeakBoundaryCompare`'s `ThreadExceptionDialog` and its 384-second stall.

Result: the 13 target tests went from 10 failures in 416s to **13 green in 53s**.

### Tooling gap worth a decision (NOT changed)

`build.bat` intentionally excludes `TestPerf` and `TestTutorial` from the standard build,
and `Build-Skyline.ps1 -Target Solution` faithfully mirrors that. But
`Stage-Net8Tests.ps1`'s default `-Projects` now DOES include both, so build-then-stage
silently stages whatever stale `TestTutorial.dll`/`TestPerf.dll` happen to be on disk.
Three of the 13 target tests live in `TestTutorial`. Suggest either staging only what was
built, or warning when a staged project's output is older than its sources.

## Progress Log

### 2026-08-28/29 - Merged the net10 base; found Release linking Debug pwiz-sharp

Branch at `d529c36129`, clean and pushed. Solution builds Release, CodeInspection passes,
`TestThreadDumpNamesRunningFrames` passes pass-1 leak detection at 0 KB.

**Landed on this branch:**

- **Thread-dump runtime leak fixed.** ClrMD 3.x makes `ClrRuntime` disposable and it owns the
  loaded DAC; building one per dump and dropping it leaked 3.3 MB / 37 KB managed per run.
  Now `using var runtime`. Same defect #4618 fixed against ClrMD 0.8.31, where there was no
  `Dispose` to call and the answer had to be attach-once-and-reuse - which is why that fix did
  not carry across. Also removed the test's unconditional console dump, which landed mid
  result-line and broke the log format `Report()` parses.
- **SkylineTester usable after a clean build.** The test tree now lists from the per-project
  build output (what the stager copies FROM) instead of the staged directory, so a test just
  added and built appears immediately. Running no longer demands a staged directory in order to
  create one. One resolver for the run directory - three callers read the UI selection, which
  keeps its "nothing found" sentinel for the session because `FindBuilds` runs at startup and
  staging happens later; one of them crashed on `Path.Combine(null)`.
- **Merged #4619 (now .NET 10), 44 conflicts.** 31 were target-framework only and took net10
  (a net8 consumer cannot reference a net10 assembly, CS1705). Project files kept THIS branch's
  structure with `net8.0` rewritten to `net10.0` - `ProteowizardWrapper` and `CommonUtil` stay
  PLAIN (no `-windows`), which is the whole point of the split. `HangDetection` kept the ClrMD
  3.x implementation; auto-merge had blended #4618's 0.8.31 code into it and it could not
  compile. `CommonBaseUI` and `TestStager.TFM` still said net8 and were never in conflict,
  because only this branch has them.
- **Restored the staging script the merge deleted.** #4619 renamed `Stage-Net8Tests.ps1` to
  `Stage-Tests.ps1`; git raised the conflict at the new path, it read as "their file", and it
  was deleted as superseded. It was not - it is a thin wrapper over `TestStager`, and
  `build.bat` calls it twice, so `bs.bat` could not stage at all. Also `TestStager` bundled the
  portable runtime for Docker workers by hardcoded `"8.0"`; workers would have got a .NET 8
  runtime for net10 apps. Now 10.0.

**In `pwiz-ai`:** `Run-Tests.ps1` now stages by invoking the runner when the old script is
absent, and takes the staged directory from the line the stager prints, so `TestStager` stays
the single authority. It previously hardcoded `bin\staging\<Config>` and could not run this
branch at all.

**BLOCKING for a net10 nightly:** Release builds link **Debug** pwiz-sharp assemblies. Proven by
hash - the staged `Pwiz.Analysis.dll` matched `bin/Debug/net10.0` exactly. pwiz-sharp declares no
`<Platforms>`, so an x64 build triggers dynamic platform resolution, which falls back and takes
`Configuration` with it. Predates the retarget; it was hidden because `obj\Debug\net8.0` existed
on disk and silently satisfied the fallback. Fix belongs in pwiz-sharp
(`<Platforms>AnyCPU;x64</Platforms>`, ideally in its `Directory.Build.props`) and is worth telling
Matt about regardless of who lands it. Until then the nightly runs net472.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260818_commonutil_winforms_split.md` before starting work.

### 2026-08-29 - net472 baseline set; next goal is a net10 comparison run

The net472 nightly on master ran **23:46 -> 09:11 with 43,471 tests at the 9-hour mark, 0
failures and 0 worker losses, all 8 workers alive** (log rolled to
`D:\test\nightly-logs\SkylineTester-20260829-net472-9hr-COMPLETE.log`). It went on to 45,171
tests by 09:25, ~4,830 tests/hour. That is the number a .NET 10 run gets compared against.

Every test that dominated earlier runs came through clean: `ConsoleMethodTest` 0/70 (was 7/70),
`PeakAreaDotpGraphTest` 0/70 (was 6/67), `TestInstrumentSerialNumbers` 0/70 with no worker loss,
`ConsoleImportNonSRMFile` 0/70, `TestAuditLogTutorial` 0/70. At their measured rates the first
two are ~0.06% and ~0.14% events, so those are the fixes showing, not a quiet night. The zero
worker losses is a real measurement rather than an absence of reporting - which is the
difference from the runs that shed workers and still said "No failures".

**Next goal**: fix the pwiz-sharp Debug/Release defect (still blocking), resync to Matt's latest
(he HAS committed since our merge), rebuild and stage, then start a net10 run for comparison.
When comparing, note that a difference will not isolate to the framework - it also carries the
retarget and this branch's split - and confirm whether the net472 baseline was Debug or Release
before treating tests/hour as comparable.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260818_commonutil_winforms_split.md` before starting work.

### 2026-08-29 (second session) - Merged Matt's latest; the Debug/Release blocker does not reproduce

**Branch is up to date with its base and mergeable.** `15de5ce126`, 43 commits, **0 behind**
`origin/Skyline/work/20260612_net8_port`, pushed. PR #4587 reports **MERGEABLE / CLEAN**.

**The BLOCKING "Release links Debug pwiz-sharp assemblies" defect does not reproduce.**
Measured, not assumed. A fresh Release build followed by a re-stage puts **zero** Debug
assemblies in the staged tree:

| Staged `Pwiz.*.dll` | Config it came from |
|---|---|
| 16 of 18 | `bin/x64/Release/net10.0` - correct |
| `Pwiz.Tools.BiblioSpec`, `Pwiz.Vendor.Sciex.Wiff2` | `bin/Release/net10.0` - AnyCPU, still **Release** |
| none | any Debug output |

The `76a3f78e` Debug DLL the previous session found was **stale staging**, not a live fallback:
the staged copy is timestamped 22:28:48 and the correct `x64/Release` output is 22:31:57 - the
tree was staged three minutes before the compile that corrected it. Deleting the 18 `Pwiz.*.dll`
from `pwiz_tools/Skyline/bin/x64/Release/net10.0-windows` and rebuilding reproduces the 16/2/0
split above from scratch, so it is not leftover state either.

Brendan independently confirmed the practical symptom is gone: a Clean Solution followed by a
full Solution compile now completes in Visual Studio, which was the original motivating failure.
Clearing the stale x64/Release outputs is the likely reason - a Debug-configuration
`Pwiz.Analysis.dll` was sitting in an x64/Release output path and was being treated as current.

Still true and still worth telling Matt: **no pwiz-sharp csproj declares `<Platforms>`** (checked
all 59), while every `pwiz_tools/Shared` project does. That is what lets the two stragglers fall
back to AnyCPU. `Pwiz.Vendor.Sciex.Wiff2` is referenced `ReferenceOutputAssembly=false` +
`OutputItemType=Content` as a deliberate side-by-side ALC plugin, so it may need more than the
`<Platforms>` line. **Not fixed here** - both are Release, both are managed-only, and an AnyCPU
managed DLL loads fine in an x64 process, so neither blocks a comparison run.

**Merged `df188772e9..cc94d3b45b`** - two commits: `cc94d3b45b` (small molecule accessions on
.NET 10.0.3, `NistLibSpec.cs`) and `40fd787ff5` (GDI+ splitter repaint failures,
`AvailableFieldsTree.cs` + `Program.cs`). Two files auto-merged; **one conflict, in
`Program.Init()`, and it was not a pick-a-side**:

- The incoming commit moves `ThreadException += handler` out of the run-once block to the top of
  `Init()` as a `-=`/`+=` pair, so it re-attaches after every message loop.
- This branch had replaced that same line with `InitUiThreadExceptionHandling()`, which also sets
  the exception mode and is guarded by a `[ThreadStatic]` flag.
- Taking THIS branch's side unchanged would have left the handler **subscribed twice** on the
  first thread - the incoming block subscribes, then the helper subscribes again - so every
  UI-thread exception would report twice and `AddTestException` would fire twice per failure.
- Taking the INCOMING side would have dropped the per-thread setup that a message loop started
  on a NEW thread depends on.
- Resolution keeps both: the call site stays `InitUiThreadExceptionHandling()`, and the helper
  now removes before adding. Steady state is one subscription on the first thread; a new
  message-loop thread still gets its own mode and subscription.

**Verified**: Release solution compiles (100 s). `TestThreadDumpNamesRunningFrames` passes.
`PeakAreaDotpGraphTest`, `TestAutoZoom` and `TestMultiInjectRescore` pass in one process - three
`Application.Run` cycles, which is the path the resolution governs.

**Next**: re-stage and start the net10 nightly for comparison against the net472 baseline above.
The Debug/Release concern that was holding it back is measured away.

### 2026-08-30 (night session) - The eight net10 nightly failures are one WinForms .NET 9 regression

**Eight failures in the 42-minute net10 nightly were a single defect, and it is in WinForms,
not in Skyline.** Every one carried the same `ObjectDisposedException` on a
`SafeWaitHandle` from `Control.InvokeMarshaledCallbacks`.

**Root cause.** `Control.MarshaledInvoke` disposes the marshaled call's completion event as
soon as it stops waiting:

```csharp
if (!tme.IsCompleted)
{
    using WaitHandle waitHandle = tme.AsyncWaitHandle;   // added by dotnet/winforms#10460
    WaitForWaitHandle(waitHandle);
}
```

`WaitForWaitHandle` has paths that return while the entry is still queued, and
`ThreadMethodEntry.Complete()` then calls `_resetEvent?.Set()` on the disposed handle from the
UI thread's message pump. Comparison across release branches:

| Runtime | `MarshaledInvoke` | `ThreadMethodEntry` |
|---|---|---|
| net472 / .NET 6 / .NET 8 | `WaitForWaitHandle(tme.AsyncWaitHandle);` | `~ThreadMethodEntry() { _resetEvent?.Close(); }` |
| .NET 9 / .NET 10 | `using WaitHandle waitHandle = ...` | finalizer removed |

.NET 8 closed the handle only from a finalizer, i.e. only once nothing could signal it. That is
why the net472 baseline was clean and one runtime change broke eight tests.

Already reported upstream as **dotnet/winforms#14996** (milestone 11.0-rc2, assigned, **no
backport**), which names #10460 as the cause. Not the same defect as `40fd787ff5`.

**The exception is noise, not a symptom.** A deterministic standalone repro on 10.0.11
reproduces the nightly's stack exactly and reports `callbackRan=True`, `IsCompleted=True`: the
marshaled work runs and the entry completes; only the completion signal throws, and by then no
thread is waiting on it.

**Eliminated by measurement, not argument**: `Application.ThreadContext.FromId` is never null
on a live thread (probed at nine points across a message-loop lifecycle), so
`WaitForWaitHandle`'s silent `ctx is null` early return cannot be the abandonment path here.

**Fix**: `IsBenignInvokeCompletionFailure` in `Program.ThreadExceptionEventHandler`, following
the `IsBenignSplitterRepaintFailure` precedent - matched narrowly on the WinForms method name
and `typeof(SafeWaitHandle).FullName`, with a comment saying what to remove it for. Ignoring it
restores .NET 8 behavior exactly rather than hiding a new failure.

**Verified**:
- New `TestUiThreadExceptionFilter` FAILS without the fix (1.3 s, deterministic, the exact
  nightly exception) and PASSES with it in all five languages.
- BEFORE: 4 failures / 336 test instances (1.2%) in 6.3 min - the eight failing tests, five
  languages, `parallelmode=server workercount=8`.
- AFTER: same configuration, running.

**Follow-up, not done here**: `ai/scripts/Skyline/Run-Tests.ps1 -Loop 0` documents "run forever"
but maps to `loop=1`; use an explicit count until that is fixed.

**Hardened after a measurement, same night.** The first filter matched on
`ObjectName == SafeWaitHandle` plus `StackTrace.Contains("InvokeMarshaledCallbacks")`, and a
side-by-side experiment showed that an `ObjectDisposedException` thrown by OUR OWN code inside a
marshaled callback matches all of that too - same ObjectName, same method on the stack. The
filter now requires every frame's declaring assembly to be WinForms or CoreLib, which is what
actually separates the framework's completion signal from a callback failure.
`TestUiThreadExceptionFilter` asserts both directions. Commits `f2fba23503`, `a64f2f4b2a`.

**Draft comment for dotnet/winforms#14996** (the repro of the framework-owned path they say they
could not reproduce) is in `ai/.tmp/draft-comment-winforms-14996.md`. **Not posted - needs
Brendan's okay**, it is outward-facing.

**AFTER results (2026-08-30, ~23:40).** Targeted soak: 0 failures / 367 instances. Full nightly
list, the same 657 tests / 5 languages / 8 workers that produced the eight failures:
**0 failures / 7,501 instances in 69 minutes**, still running. That is 3.7x the exposure at
which the original run had accumulated all eight, so open question 4 from the predecessor
handoff ("how many more would there have been?") is answered: there is no second failure mode
behind the first.

**Two pass-0/1 findings, neither blocking (2026-08-30, 02:00-03:40).** Passes 0 and 1 had never
been run on this branch under .NET 10. Three full pass-0/1 runs, ~7,100 instances each:

* `TestLayoutExportImport` - failed 3 of 3, always as a 360 s `WaitForCondition` timeout at
  USER+GDI of 18,157 / 18,154 / 18,153. Measured with `GetGuiResources` inside the container:
  `user=9852` against the Windows default `USERProcessHandleQuota` of 10,000. A process at that
  quota cannot create windows, so the floating Document Grid never appears. **The container, not
  Skyline**: the host worker never exceeded USER=581 in the same run, and the test holds
  USER+GDI flat at ~170 in a single host process. Infrastructure issue, would hit any branch.
* `ThermoCancelImportTest` - failed 2 of 3, at line 144's mute `Assert.IsTrue` (the cancel
  compare-and-swap, which the test's own 2022 retry does not cover). Pre-existing since
  `5100494e2f`, 2022-10-26.

No ObjectDisposedException in any of the three runs. Details in
`ai/.tmp/handoff-20260830_net10_invoke_disposed_fixed.md`.

**Pass 1 reports 11 reproducible leaks on net10 that do NOT fail the run - needs a master
baseline, not a fix.** The failure count stayed at 2 (the two FAILED tests) in all three runs
with 11-14 LEAKED lines present, matching the precedent in TODO-20260612_net8_port.md where a
LEAKED line "did not fail the leg". The leak
detector prints `!!! <Test> LEAKED <n> <kind>`, not `FAILED`, so failure greps miss it. Across
three pass-0/1 runs the same eleven tests leaked with byte counts reproducible to a fraction of a
percent - `TestFilesTreeForm` 2.12 MB managed all three times, `TestCrosslinkIms` ~1.2 MB,
`TestMeasuredDriftValues` ~0.59 MB. Deterministic, not noise.

**Whether these are port regressions is UNKNOWN** - there is no pass-1 baseline for master/net472.
The next step is to run the same `-Pass "0,1"` configuration on master and diff the leak lists;
only tests leaking on net10 and not master are regressions. `TestFilesTreeForm` and
`TestTreeRestoration` are tree/docking UI, the same family as the net8 WinForms holds this branch
already works around, so check for a shared cause first. Full table in
`ai/.tmp/handoff-20260830_net10_invoke_disposed_fixed.md`.

**Correction: a pass-1 run does not currently complete.** Of the three pass-0/1 runs, two exited
-1 because they were killed manually; the one left alone (run C) self-terminated with exit code 1
after `TestGroupedStudies1Tutorial LEAKED 886391.6 Heap bytes` at `deltas (25)`, the max retry
count, with heap climbing 75 -> 117 MB across those iterations. Leaks that converge in a few
retries do not fail; that one does not converge and ends the run. This is a stronger item than
the eleven-leak table and still needs the master/net472 baseline to classify. Separately, the
"it is the container, not Skyline" wording for the USER-quota finding overstates the evidence -
what was measured is an asymmetry (containers reach the 10,000 USER quota, host worker never
passed 581), not an identified cause.

### Code review of the filter found a real hole - reworked and re-verified

`/code-review max` was run on the two-file diff alone (soft-reset onto the working tree rather
than branching, since branching at `59e78e9181` leaves the same 43-commit merge-base and
branching from master fails outright: `IsBenignSplitterRepaintFailure` does not exist there and
master is net472, where this bug cannot occur). Findings worked, then re-verified.

**The critical one, reproduced independently before acting.** The first filter walked the ENTIRE
stack, including the WndProc dispatch chain BELOW `Control.InvokeMarshaledCallbacks`. Adding a
`WndProc` override to the target - the only change between two otherwise identical probe runs on
.NET 10.0.11 - flipped the verdict from True to False. Skyline has seven such controls
(`SequenceTree`, `AllChromatogramsGraph`, `CustomTip`, `WizardPages`, `UndoRedoList`,
`ClickThroughToolStrip`, `CustomTextProgressBar`), so the nightly failures would have returned
for any of them. The filter now stops at `InvokeMarshaledCallbacks`; frames below it are the
message pump and are legitimately ours.

Also fixed: a callback whose delegate target is a framework method group produced an
all-framework stack and was swallowed (now rejected via the `InvokeMarshaledCallback*` /
`ExecutionContext` dispatch frames), and an empty frame array made the walk vacuous and return
true (now fails closed).

**The review's own suggested fix was wrong and was not taken**: requiring
`ThreadMethodEntry.Complete` directly under `InvokeMarshaledCallbacks` breaks on the real
nightly stack, where the JIT inlines `Complete`, `EventWaitHandle.Set` and `DangerousAddRef`
away. Bounding the window works on both the inlined and non-inlined stacks.

The test now asserts positively (hooks `Messages.WriteDebugMessage` rather than asserting an
absence), strands on `SequenceTree` as well as `SkylineWindow`, provokes the reporting half from
a framework method group, removes only its own exception under the lock the writer takes, and
uses `WAIT_TIME` instead of a raw 10s. **Verified as a gate**: it fails against the old
whole-stack predicate (394 s, the exact ObjectDisposedException) and passes against the new one
in all five languages over three loops. CodeInspection green. Commit `412dff25b6`; the
pre-review commits are kept on local branch `review-backup/20260830_invoke_filter`.

**Left for Brendan, not done**: `BackgroundEventThreads.cs:64` wires `Application.ThreadException`
straight to `Program.ReportException`, which applies neither benign filter, so a `LongWaitDlg` on
its own STA thread can still fail tests this way. Real and pre-existing (the splitter filter has
the same gap); the one-line fix is to call `Program.InitUiThreadExceptionHandling()` there.

### The pass-1 managed leak: IrtDb builds a SessionFactory per operation

Measured, not inferred. A temporary counter at `SessionFactoryFactory.CreateSessionFactory` (the
single choke point every Skyline NHibernate factory goes through; diagnostic since reverted) over
**3 iterations** of `TestFilesTreeForm`:

| Type | Factories built | Per iteration | File |
|---|---|---|---|
| `IrtDb` | **99** | **33** | always the same `Rat_Prosit.blib` |
| `IonMobilityDb` | 18 | 6 | `Rat_settings.imsdb` |
| `OptimizationDb` | 12 | 4 | `Rat_settings.optdb` |
| `ProteomeDb` | **1** | - | `Rat_mini.protdb` |

**ProteomeDb builds one factory for the entire run; IrtDb builds 33 per iteration for the same
file.** The difference is `DatabaseResource` (`Shared/ProteomeDb/Util/DatabaseResource.cs`), a
static refcounted cache added for exactly this reason - its comment reads "these are large,
expensive-to-construct objects that leak a great deal of string space, so we'll hang onto them".
`IrtDb` has no equivalent: ten methods each do `using var sessionFactory = GetSessionFactory(_path)`,
building the full mappings, persisters, dialect, HQL registry and proxy bytecode every time.

The factories ARE disposed, so this is not "never released". What is not released is the
bytecode: the dotMemory diff shows `DynamicILGenerator`, `DynamicMethod`, `ScopeTree` (2,960 new
each) and `SignatureHelper` (6,960 new) with **0 dead**. Disposing a SessionFactory does not
reclaim the dynamic methods NHibernate emitted for it.

This is a throughput problem as much as a memory one - 33 full NHibernate configurations per test.

**RETRACTED: "almost certainly pre-existing, not a net10 regression" was wrong.** It was written
with no baseline, immediately after noting no baseline existed. Brendan confirms these tests pass
without leaking on master, so the leak IS a regression and the branch cannot merge until it is
gone.

**And caching IrtDb does NOT fix the leak - measured.** With a per-path SessionFactory cache in
IrtDb (experiment, reverted), pass 1 still reported
`TestFilesTreeForm LEAKED 2352934.9 Managed bytes` / `managed = 2297.8 KB`, slightly WORSE than
the ~2,072 KB baseline. Factory count is constant across iterations under the cache, yet
per-iteration growth is unchanged, so **the growth is not proportional to factory construction**.
IrtDb consistency remains worth doing for throughput (33 configurations per test), but it is not
the leak fix.

Two variables changed together in the port, which is the live lead:

| | master | branch |
|---|---|---|
| Runtime | net472 | net10.0-windows |
| NHibernate | 5.1.3 (vendored `Shared/Lib/NHibernate/NHibernate.dll`) | 5.5.2 (PackageReference) |

NHibernate changed its default proxy factory to a built-in Reflection.Emit one across that
range, which fits the snapshot's `DynamicMethod` / `DynamicILGenerator` / `SignatureHelper` /
`ScopeTree` all showing **0 dead**. Not yet confirmed - and note the two variables can be
separated, since the NHibernate version is a package reference that can be moved independently
of the runtime.

### NHibernate bisect: 5.1.3 cannot run on .NET 10, so the two variables are not separable

Swapped all six `PackageReference NHibernate 5.5.2` back to master's exact declaration -
`<Reference>` with `HintPath` into the still-vendored `Shared/Lib/NHibernate/`, which holds
precisely master's versions (NHibernate **5.1.3.0**, Antlr3.Runtime 3.5.1, Iesi.Collections
4.0.4, Remotion.Linq 2.1.2). It **compiles** on net10 and the output binds 5.1.3.0. It does not
run:

```
NHibernate.InvalidProxyTypeException: The following types may not be used as proxies:
  pwiz.ProteomeDatabase.DataModel.DbVersionInfo: method MemberwiseClone should be
    'public/protected virtual' or 'protected internal virtual'
  ... DbProtein, DbProteinName, DbProteinAnnotation, DbSubsequence
   at NHibernate.Cfg.Configuration.ValidateEntities()
   at NHibernate.Cfg.Configuration.BuildSessionFactory()
```

5.1.3's proxy validator walks inherited methods, now sees `Object.MemberwiseClone` (not
virtual), and rejects **every** mapped entity, so no SessionFactory can be built at all. This is
almost certainly why the port moved to 5.5.2.

**Consequence: the runtime and the ORM version cannot be separated.** .NET 10 forces a newer
NHibernate, so the leak has to be fixed within 5.5.x or in how Skyline uses it - a version
revert is not on the table. csproj changes reverted.

### Correction to the IrtDb cache experiment

Stated earlier that the cache held "factory count constant across iterations". That is wrong:
only IrtDb was cached, while `IonMobilityDb` (6 per iteration) and `OptimizationDb` (4 per
iteration) kept churning. The experiment cut construction from ~43 to ~10 per iteration - a 4.3x
reduction - and the leak did not shrink (2,072 KB baseline vs 2,298 KB cached). That is still
strong evidence the leak is not proportional to factory construction, but it is not the clean
control the earlier wording implied.

### Abandoned the cache-based control, and a blind spot it exposed

The plan to cache `IrtDb`/`IonMobilityDb`/`OptimizationDb` factories and clear them at test
teardown was **dropped on Brendan's objection, which is right**: a static path-keyed cache grows
with every distinct file a user opens and is freed only at window close, so clearing it per test
does not remove the growth - it removes our ability to SEE the growth. Bounding a leak to a test
iteration is not fixing it.

Measured before dropping it, and worth keeping:

* With caches in place, factory construction fell from **130 to 11 across 3 iterations**.
* The named database paths repeat every iteration, but the **temp files do not** -
  `~SK333A.tmp`, `~SK352F.tmp`, `~SK3A12.tmp`, a fresh name per iteration. So a path-keyed cache
  retains roughly one extra factory per iteration forever. That is very likely why the earlier
  IrtDb-only cache measured slightly WORSE (2,298 KB) than the uncached baseline (2,072 KB): it
  manufactured a leak of the same order as the one being measured.

**Pre-existing blind spot, not introduced here.** `ProteomeDb`'s `DatabaseResource` is exactly
this shape - a static path-keyed cache that deliberately retains ("we'll hang onto them"),
released only at `Skyline.OnClosed()`. And `AbstractUnitTest.cs:494` calls
`DatabaseResources.ReleaseAll()` at **every test teardown**, so pass-1 leak detection
structurally cannot observe unbounded growth in that cache. Worth deciding separately whether
that teardown call should stay.

**Where the leak hunt stands**: factory construction is not the driver (a 4.3x cut in
construction produced no reduction), the ORM version cannot be reverted, and the next step is the
retention path for the surviving NHibernate objects - which does not require changing product
behavior. All experimental changes reverted; tree clean at `4f14b7cee6`.

### The leak is NOT from the .NET 10 retarget - it is already there on .NET 8

Built commit `14e8820ac5` (the parent of `b882847f21` "Retargeted the Skyline and pwiz-sharp
trees from .NET 8 to .NET 10") in a throwaway worktree and ran the same pass-1 check:

| Configuration | Managed leak, TestFilesTreeForm |
|---|---|
| net10.0-windows + NHibernate 5.5.2 (current branch) | 2,072.8 KB |
| **net8.0-windows + NHibernate 5.5.2 (`14e8820ac5`)** | **2,133.9 KB** |

Within 3%. **The net10 retarget did not introduce this leak; it inherited it.** The working
premise that "something changed with the move to .NET 10" is wrong, which is also why bisecting
NHibernate versions on net10 was leading nowhere - wrong axis.

So the fault is somewhere in the net8 port, which is also where NHibernate went 5.1.3 -> 5.5.2.

**Next cut, and it is nearly free**: `14e8820ac5` multi-targets `net472;net8.0-windows`, and its
net472 leg binds the VENDORED NHibernate 5.1.3 while the net8 leg binds package 5.5.2. Running
the net472 leg at that same commit compares the two ORM versions with the source tree held
constant, isolating the upgrade from every other port change.

Worktree: `C:\proj\pwiz-net8` (detached at `14e8820ac5`; remove with `git worktree remove`).
Needs the era-matched wrappers - `ai` commit `2d92f01`, extracted to
`ai/.tmp/Build-Skyline-net8era.ps1` and `ai/.tmp/Run-Tests-net8era.ps1` - because the current
wrapper calls `TestRunner.exe stage=1`, which that commit's runner does not support. Its
`Stage-Net8Tests.ps1` also had to be pointed at `bin\x64\...` since the build lands there.

**Tooling bug found on the way**: `Build-Skyline.ps1 -Framework Net8` sets `$isNet8` but never
sets `$script:SdkTfm`, so it builds with an empty `-f` and swallows the next argument
(`TargetFramework=-nologo`). Only `-Framework Auto` works. Worth fixing in ai/scripts.

### ROOT CAUSE of the pass-1 managed leak: an undisposed NHibernate SessionFactory

Bisected from a MEASURED known-good point (`C:\proj\daily`, master `99609d5bc0`, net472) by moving
one variable at a time. `TestFilesTreeForm`, pass 1, managed leak:

| Runtime | NHibernate | Factory lifecycle | Managed leak |
|---|---|---|---|
| net472 | 5.1.3 | `using` (disposed after Load) | **2.8 KB**, converged at 15 iterations |
| net472 | 5.1.3 | ownership transferred, never disposed | **1,720.7 KB** |
| net472 | 5.5.2 | ownership transferred | 2,127.4 KB |
| net8 | 5.5.2 | ownership transferred | 2,133.9 KB |
| net10 | 5.5.2 | ownership transferred | 2,072.8 KB |

**The change-point is the lifecycle change alone.** It leaks on the ORIGINAL NHibernate 5.1.3,
on net472, on master. The runtime accounts for nothing; the ORM upgrade accounts for ~400 KB of
~2 MB (larger factories), not for the leak's existence.

**Mechanism, verified by reflection on both assemblies.** `NHibernate.Impl.SessionFactoryObjectFactory`
holds `static IDictionary<string, ISessionFactory> Instances` / `NamedInstances` - STRONG
references - and only `Dispose()` calls `RemoveInstance`. An undisposed factory is therefore
rooted for the life of the process together with its persisters, dialect, HQL registry and
emitted proxy bytecode. That is why every NHibernate type in the dotMemory diff showed **0 dead**.
The registry is identical in 5.1.3, which is why the defect is transferrable.

**Why the port opened the gap.** NHibernate 5.5 throws `ObjectDisposedException` when
`OpenSession` is called on a disposed factory, where 5.1.3 tolerated it - confirmed by swapping
5.5.2 into master, which hangs at `EditIonMobilityLibraryDlg`. The port therefore had to drop the
`using` and transfer ownership to `IonMobilityDb`/`OptimizationDb`. But `OptimizationDb` is not
even `IDisposable`, and `IonMobilityLibrary.cs:148` never disposes the `IonMobilityDb` it retains,
so nothing ever released a factory again. `IrtDb` kept `using` at all ten sites and does NOT leak -
the existence proof that the pattern is fine under 5.5.2.

**Fix being measured**: neither class retains a factory. Each session owns the factory it was
opened from (`SessionWithLock` gained an optional owned factory it disposes with itself), so no
factory can outlive a `using`. Closed by construction rather than by a disposal call someone must
remember. Note the trade Brendan flagged: this exposes any read that is not fully materialised by
a BackgroundLoader, since such a read now builds a factory per call.

### Candidate fix (UNCOMMITTED, NOT yet validated)

Working tree of `pwiz-work1` carries an unvalidated candidate:

* `Shared/Common/Database/NHibernate/SessionWithLock.cs` - optional `ownedSessionFactory` that
  the session disposes with itself.
* `Model/IonMobility/IonMobilityDb.cs`, `Model/Optimization/OptimizationDb.cs` - neither retains
  a factory. Each session creates and owns one; `GetXxxDb` no longer builds or locks a factory.
  Both classes already stored `_path`, and there was only ONE construction site each.

Closed by construction rather than by a disposal call someone must remember - which matters
because these are `Immutable` objects with no lifetime to hang `Dispose` on. (There is a
mechanism for closing references held by `SrmDocument` via the `ConnectionPool`, but
open-read-close is far simpler and is what `IrtDb` already does.)

**Status: builds, but NOT validated.**
* `TestFilesTreeForm` failed 1 of 3 pass-2 iterations at `FilesTreeFormTest.cs:1666`
  `Assert.IsTrue(simulator.IsDragging)` - a bare, message-less assertion in a drag simulation.
* Intermittent, not deterministic. But the pre-fix baseline ran **25 iterations clean**, and
  post-fix it is ~2 failures in 4, so the rate looks raised rather than incidental.
* **The leak number was never obtained** - both pass-1 attempts aborted on this failure before
  completing the 25-iteration measurement. So there is no evidence yet that the fix removes the
  2,072.8 KB. Do not treat it as fixed.

**Plausible mechanism, unproven**: with no `BackgroundLoader`, this database is materialized on
the FOREGROUND thread during file open, without progress UI or the usual protections (Brendan's
observation; a pre-existing short-cut, out of scope here). Rebuilding a SessionFactory per read
makes that foreground load slower, which would stall the UI thread during the simulated mouse
move so the drag never initiates. If that is right, the fix is sound but exposes the missing
background loader as a functional failure rather than only a cost.

### FIXED and verified on both ends - commit `b867cf2664`

Neither `IonMobilityDb` nor `OptimizationDb` retains a SessionFactory now. Each session owns the
factory it was opened from (`SessionWithLock` gained an optional owned factory it disposes with
itself), so no factory can outlive the `using` that opened its session. Closed by construction,
which matters because these are `Immutable` types with no lifetime to hang a `Dispose` on.

`TestFilesTreeForm`, pass 1, managed leak:

| Configuration | Before | After |
|---|---|---|
| branch, net10 + 5.5.2 | 2,072.8 KB (exhausted 25 iterations) | **0 KB** (`managed = -1.1 KB`, 24 iterations, passed) |
| master, net472 + 5.5.2 | hung at `EditIonMobilityLibraryDlg` | **2.8 KB**, converged at 15 - identical to pristine master |
| master, net472 + 5.1.3 | 2.8 KB | NOT MEASURED - only pass 2 was run on this combination (3/3 functional). Do not cite an after-fix leak number for 5.1.3. |

Functionally clean: 3/3 pass-2 iterations on master with BOTH 5.1.3 and 5.5.2, 24 pass-1
iterations on the branch, CodeInspection green. The one `TestDragSimulation` failure seen earlier
was an intermittent flake - it did not recur across those runs.

**The old code was never coherent**, which is the real story: master passes a SessionFactory into
the class *inside* a `using` that disposes it before the function returns, and the class keeps it
as a member. On 5.1.3 that was a tolerated use-after-dispose; 5.5 made it fatal. The port then
traded the latent use-after-dispose for a definite leak by removing the `using`. Removing the
member is the fix that was always correct - which is why it is neutral on 5.1.3 and required on
5.5.2. **This is a correctness fix for master in its own right, not only an upgrade enabler.**

### What it takes to adopt NHibernate 5.5.2 on master

Surveyed every session-factory site. The recipe is small:

1. Swap three vendored DLLs in `Shared/Lib/NHibernate/` - NHibernate 5.5.2 (`lib/net461`),
   Remotion.Linq 2.2.0, Remotion.Linq.EagerFetching 2.2.0 (5.5.2 needs >= 2.2.0; master vendors
   2.1.2). Antlr3.Runtime 3.5.1 and Iesi.Collections 4.0.4 already match. **No csproj changes** -
   master references by `HintPath`. Verified: builds and binds 5.5.2.
2. Apply this same fix to `IonMobilityDb` and `OptimizationDb`.

Already compatible, no change needed: `IrtDb` (`using var` per operation), `MidasLibrary`
(factory and session disposed in one scope), `BlibDb` (`IDisposable`, disposes its factory),
`ProteomeDb`/`DatabaseResource` (refcounted, released via `ReleaseAll`).

Not adopted here - `daily` still carries the swap and fix as UNCOMMITTED working changes for
inspection; revert with `git checkout` if not wanted.

### Controlled check that the fix introduces no functional regression

The two `TestDragSimulation` failures seen while developing the fix were called a flake on one
passing retry, which was too quick. Re-run properly, isolating functional behaviour from leak
checking, one thing at a time on an otherwise idle machine:

| Step | Configuration | Functional | Leak |
|---|---|---|---|
| 1 | pre-fix, pass 2, 20 iterations | **20/20 pass** | - |
| 2 | pre-fix, pass 1, 25 iterations | 25/25 pass | **2,069.8 KB LEAKED** |
| 3 | post-fix, pass 2, 20 iterations | **20/20 pass** | - |
| - | post-fix, pass 1, 24 iterations (earlier build, same commit) | passed | **0 KB** (`managed = -1.1 KB`) |

Pre-fix the test is reliable across 45 iterations; post-fix across 44. **No measurable functional
regression from the fix**, and the leak is gone.

The two original failures remain UNEXPLAINED. An earlier draft of this entry attributed them to
UI timing under concurrent machine load; that was a guess about a test whose mechanism had not
been read, and it is withdrawn. What is measured: 2 failures at `FilesTreeFormTest.cs:1666`
during development, then 44 clean iterations across pre- and post-fix runs. No mechanism
established.

Also fixed: the `daily` working copy had a UTF-8 BOM added to all three files by the script that
applied the fix there. Removed. Verified the branch and master fixes are otherwise identical
ignoring comments and whitespace.

### After the fix: 9 of 11 leakers clear; the 2 survivors are SCIEX/WIFF2

Pass-1 managed leak on the branch with `b867cf2664`:

| Test | Before | After |
|---|---|---|
| `TestFilesTreeForm` | 2,072.8 KB | 0 |
| `TestCrosslinkIms` | ~1,180 KB | -0.1 KB |
| `TestMeasuredDriftValues` | 589.2 KB | 5.8 KB |
| `TestMeasuredDriftValuesAsSmallMolecules` | ~596 KB | 6.6 KB |
| `TestNewDocumentLoadLibraries` | ~303 KB | 7.1 KB |
| `TestSelectSpectrum` | ~273 KB | -0.3 KB |
| `Wiff2ResultsTest` | ~30 KB | -97.4 KB |
| `IrtDocumentFunctionalTest` | ~11 KB | -130.4 KB |
| `TestTreeRestoration` | ~40 KB heap | 0.9 KB |
| **`TestInstrumentSerialNumbers`** | 36.0 KB | **35 KB - unchanged** |
| **`FileTypeTest`** | 31.1 KB | **30.9 KB - unchanged** |

All nine fixed tests now CONVERGE (8-14 iterations) instead of exhausting the 25-iteration retry.

**The two survivors are port regressions, and they are SCIEX.** On pristine master they are clean:
`TestInstrumentSerialNumbers` 6.4 KB converging at 9, `FileTypeTest` 0 KB converging at 8. Both
carry `[TestMethod, NoParallelTesting(TestExclusionReason.VENDOR_FILE_LOCKING)]` -
`TestData/PwizFileInfoTest.cs:40` (which also calls `SkipWiff2TestInTestExplorer` and reads ABI
`.wiff` and Sciex `.wiff2`) and `TestData/Results/SmallWiffTest.cs:46`. The net8 port TODO's
earlier sighting, `TestInstrumentInfo LEAKED 36192 Managed bytes`, is from the SAME file at the
same magnitude - three independent points on the SCIEX reader.

Brendan's reading: this likely fingers .NET 8+ support for WIFF2/SCIEX, where there is no true
.NET 8+ vendor binary and the net472 one has been adapted. Not investigated further here.

**Still untested**: `TestGroupedStudies1Tutorial` (886 KB HEAP, the one that aborted a pass-1 run
outright). Nothing in this fix targets heap.

**Correction on what that threatens.** An earlier note called it the likely blocker for the
overnight 9-hour run. Wrong: those runs are **pass 2 only, parallel, no leak checking**, so leak
detection never executes and cannot abort them - which is also why there was no net8 leak data
before this session. The relevant evidence for that configuration is the pass-2 nightly run from
the night session: **12,056 instances, 0 failures** at `workercount=8` across the full 657-test
list (measured PRE-fix). The tutorial heap leak still matters for a long parallel run because
memory accumulates whether or not anything is checking, but it will not fail the leg.

`C:\proj\daily` changes are on the stash (`nh552-swap-and-fix`), tree pristine; `git stash pop`
to restore. Throwaway worktree `C:\proj\pwiz-net8` still on disk.

### `TestGroupedStudies1Tutorial`: heap leak confirmed on the branch, UNCLASSIFIED

Branch, pass 1, with the fix applied:

```
!!! TestGroupedStudies1Tutorial LEAKED 1129718.6 Heap bytes
# deltas (25): managed = -3.9 KB, heap = 1103.2 KB
```

The session-factory fix DID help it - managed is now clean at -3.9 KB. What remains is purely
the **heap** (unmanaged) metric, growing ~1.1 MB over 25 iterations and never converging.
Nothing in this fix targets heap.

**No master baseline obtained.** The comparison run on `C:\proj\daily` failed before reaching
the measurement: `Timeout 1200 seconds exceeded in WaitForConditionUI (Expecting loaded document
but still not loaded after 600 seconds)` at `GroupedStudies1TutorialTest.OpenImportArrange()`
line 289, after 1463 s. Possibly the tutorial's data is not staged in that rarely-used checkout -
NOT verified. So whether this heap leak is a port regression or pre-existing is still unknown.

**It also did NOT abort the run this time** - reported `All tests PASSED`. Last night run C
exited with code 1 immediately after this same leak report. So `deltas (25)` alone is not the
abort trigger and the actual rule remains unidentified.

Bearing on the overnight cycle: those runs are pass 2, so this cannot fail the leg. It only
matters as accumulating memory over 9 hours, and ~1.1 MB per 25 iterations is a slow drip.

### Session end 2026-08-30 - state at handoff

**Committed on the branch, unpushed** (3 ahead of origin):
* `412dff25b6` - the WinForms marshaled-call exception filter and its test
* `4f14b7cee6` - narrowed that filter so doubtful cases stay reported
* `b867cf2664` - the NHibernate SessionFactory disposal fix

Working tree clean. CodeInspection green. Nothing pushed anywhere.

**In flight at handoff**: Brendan restarted the long parallel pass-2 cycle. At 1h45m it had
**2 failures**, one of them **`TestAuditLogTutorial`** - which this effort had already fixed once
via an audit-log ordering fix, so this is a RECURRENCE and the first thing to look at. Details
will be in `pwiz_tools/Skyline/SkylineTester/SkylineTester.log` in `C:\proj\pwiz-work1`.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260818_commonutil_winforms_split_leak.md` before starting work.

### 2026-08-30 (evening) - Both failures from the parallel run diagnosed and addressed

Brendan's long parallel pass-2 cycle (13:44-16:19, Release/net10, 8 workers, all five languages)
reached **14,660 instances with 2 failures**, then he stopped it. Log rolled to
`D:\tests\nightly-logs\SkylineTester-20260830_134418-parallel-pass2.log`.

Both are rare intermittents at roughly **one occurrence per 25 executions** of the affected test
(`TestAuditLogTutorial` ran 22 times, `WatersImsMseLibraryDriftTimesChromatogramTestAsSmallMolecules`
27). Neither has any nightly failure history on master.

#### 1. `TestAuditLogTutorial` - NOT a recurrence; a different defect

The handoff called this a recurrence of the audit-log ordering fix. It is not. That fix
(`3af899a9a6`, peak-bounds ordering) is already in this branch's copy of the file, at a different
place in the test. This failure is a `NullReferenceException` at `AuditLogTutorialTest.cs:269`,
in French, on parallel client 1.

Root cause: `FindOpenForm<DocumentGridForm>()` on line 266 returned null and line 269
dereferenced it. `FindOpenForms` only yields a form once `form.Created` is true, so a dockable
form shown by `SkylineWindow.ShowDocumentGrid(true)` in the `RunUI` immediately above is not
guaranteed to be visible to it by the time that call returns. The stack pins the null to the
test's own lambda frame - `DataboundGridControl.ChooseView` is far too large for the JIT to
inline, so an NRE raised inside it would have left a frame of its own.

Fixed by waiting instead of demanding: `WaitForOpenForm<DocumentGridForm>()`. The same file
already uses `WaitForOpenForm` for `CalibrationForm` (line 479) and `AuditLogForm` (line 608),
and four other tests already use `WaitForOpenForm<DocumentGridForm>`. Line 385's
`FindOpenForm<CalibrationForm>()` had the identical exposure and got the same treatment.

The change is also self-diagnosing: if the null were ever something other than the form,
`WaitForOpenForm` times out naming every open form instead of raising a bare NRE.

#### 2. `WatersImsMseLibraryDriftTimesChromatogramTestAsSmallMolecules` - a PORT regression

`ResultsTestDocumentContainer.AssertComplete()` failed with the bare string `Loader cancelled`
at `WatersImsMseTest.cs:200`, in Japanese, on parallel client 3.

**Not reproducible serially**: 40 consecutive runs in Japanese on an idle machine, zero
failures. It needs the parallel load, matching the "reproduce nightlies in parallel mode"
lesson. In an 8-worker two-test run it reproduced **twice in the first 11 executions**.

`Loader cancelled` names neither the loader, the document, nor what was left unloaded. Per the
rule that a mute assertion is the first bug to fix, `AssertComplete` now reports the progress
state, message and warning and whether the document is loaded. That paid off on the first
reproduction, and **refuted the leading hypothesis**:

```
Loader cancelled
Progress: begin at 0%
Message: Performing replicate retention time alignments
Document is NOT loaded:
  ResultFileAlignments
```

Not a stale status at all - a load genuinely had not finished.

**Root cause.** `RetentionTimeManager.IsCanceled` (`RetentionTimeManager.cs:62`) is nothing but
a reference comparison against the container's current document, so "cancelled" there means
SUPERSEDED, never that anyone stopped anything. Under parallel load the chromatogram loader's
`FinishLoad` commits its new document exactly as a replicate retention time alignment begins;
the alignment sees a different document, cancels at 0%, and posts a cancelled status.
`MemoryDocumentContainer.IsFinal` counts any cancellation as terminal, so `WaitForComplete`
returns on a document still missing `ResultFileAlignments` - even though
`BackgroundLoader.OnLoadBackground` re-notifies on the way out precisely so the loader restarts
on the new document. The wait quit on a hand-off that was about to complete itself.

**This is a port regression, NOT a master defect** (an earlier note in this session said
otherwise; it was wrong). Master's `IsFinal` is:

```csharp
return doc.IsLoaded || (LastProgress != null && LastProgress.IsFinal && LastProgress.IsError);
```

A cancellation is never terminal there. The cancel-terminal behaviour came from the net8 port
loosening `IsFinal` "to return true on any final loader progress state (previously it also
required IsError)" so a Waters load that finished chromatograms but left `doc.IsLoaded == false`
would fail fast instead of hanging - preserved explicitly in Matt's `3d526a3470` (2026-07-22,
"Don't treat a multi-file load checkpoint as final in MemoryDocumentContainer"), which is on the
port branches and not on master.

**Fix**: wait the restart out, bounded at 30 one-second loops, and only for containers that opt
in. `CommandLine.cs:2017` waits on this same container, and test stability is not worth up to 30
seconds added to a shipping import's failure path, so `WaitForCancelRestart` is false in
`MemoryDocumentContainer` and true in `ResultsTestDocumentContainer`. Committed as `94c2121e39`.

**For Matt, and not fixed here.** This works AROUND the port's `IsFinal` rather than reconciling
it. Simply dropping `IsCanceled` from the terminal test would NOT have fixed it: the fall-through
below it declares the document final when every data file is already cached, which was true here
- the chromatograms were all cached and what was missing was a NON-chromatogram loader. That
fall-through was written for the Waters chromatogram case and does not account for the other
loaders a document waits on.

**Sibling left alone**: `TestUtil/TestDocumentContainer.cs:32` has a second copy of the same bare
"Loader cancelled" assert and no opt-in. It registers no loaders of its own, so it was not
touched rather than change behaviour never reproduced.

#### What goes to master, and what does not

Brendan's call, 2026-08-30: PR the master-applicable parts against master and pull them through.

| Change | Master? | Why |
|---|---|---|
| `AuditLogTutorialTest.cs` lines 266 and 385 | **Yes** | `origin/master` has both `FindOpenForm` calls verbatim, at the same line numbers |
| `AssertComplete` load-state message | **Yes** | master's copy is the same bare string at `ResultsUtil.cs:287`; worth having regardless |
| `MemoryDocumentContainer` cancel-restart wait + `WaitForCancelRestart` | **No** | master's `IsFinal` never treats a cancel as terminal, so master cannot exhibit this |

The branch is based on `chambem2/pwiz-sharp`, not master, so the master PR wants authoring fresh
from master rather than a cherry-pick.

#### Verification

| Test | Before | After |
|---|---|---|
| `TestAuditLogTutorial` | 1 failure in 22 (nightly-shaped run) | **0 in 609** at 8 workers, five languages |
| `WatersImsMse...AsSmallMolecules` | 2 in 291 (0.69%); 2 in the FIRST 11 under worker-startup load | **0 in ~1400** |

**The absence of failures was not accepted as proof.** A first attempt to observe the fix path
counted zero wait-outs, which looked like the race simply never recurring - and a fix that cannot
be told apart from luck is not a fix. The zero turned out to be a MEASUREMENT ARTIFACT: a
parallel run discards a test's console output unless the test fails, so no worker log carries a
single `# ` line. A temporary probe appending to the staged directory - the volume every Docker
worker shares with the host - settled it:

```
17:10:00.131 pid=2332 Performing replicate retention time alignments
17:10:00.679 pid=2276 正在执行重复测定的保留时间校准
```

Two wait-outs in the first 15 executions, from two processes in two languages, carrying the same
loader message as the original failure. Pre-fix the identical condition produced two FAILURES in
the first 11. So the race still happens at the same rate and is now ridden out - the mechanism is
demonstrated, not inferred from silence. The probe was removed before commit; the `# Waiting out
a cancelled loader` line stays, useful in a serial run where console output survives.

**Follow-up worth having**: a deterministic unit test over `WaitForComplete` - post a cancelled
status for a superseded document, then a restart, and assert the wait rides it out. It was not
built here because it needs a document whose `IsLoaded` is false plus a `BackgroundLoader` double
and a way to shorten `CANCEL_RESTART_LOOPS`, and the night run's window was better spent
verifying. A soak proves this build; only a test keeps it proved.

Commits: `a43bb777d6` (audit log test), `94c2121e39` (loader wait). Solution builds clean in
Release/net10 and CodeInspection reports 0 failures, confirmed in its own log rather than the
script summary.

#### A note on "zero failures in 9 hours"

The 2.5-hour sample produced two DISTINCT rare flakes at ~1 in 25 executions of their own tests.
Extrapolating the instance rate (14,660 in 2.5 h) a 9-hour run is roughly 50,000 instances, so
tests that never came up twice tonight can still fail once. Fixing these two does not by itself
make zero failures likely - it removes the two that are known.

### 2026-08-30 (night run) - `TestRInstaller` x5: a live network call no stub intercepts

Tonight's 9-hour run reported its first failures at **22:26**: `TestRInstaller` in all five
languages within the same minute, at 5,942 instances. **Unrelated to anything fixed today.**

```
Attendu : <The operation was canceled by the user.>
Réel : <Error: Failed to connect to the website www.r-project.org ...>
```

**It is a transient outage, not a defect in the run.** The same five languages PASSED at 21:50,
35 minutes earlier; the site answered `HTTP 200` when checked at 22:28; and the test was clean in
both of today's earlier runs - 20 executions in the morning pass-2 cycle and 35 in the 23,250
instance post-fix run, zero failures in either. No nightly failure history on master either.

**But the test should never have been able to fail this way.** `RInstaller.InstallPackages()`
opens with a LIVE connectivity check:

```csharp
if (!RUtil.CheckForInternetConnection(out var errorMessage))   // RInstaller.cs:242
```

which issues a real HEAD to `www.r-project.org` through `HttpClientWithProgress`. Nothing in
`FormatPackageInstaller` stubs it. Its `connectionSuccess` parameter is a red herring - it feeds
`TestSkylineProcessRunner.ConnectSuccess`, the elevated-process stub, not this check. So every
`RInstallerTest` path reaching `InstallPackages` - `TestNoAdminPrivledges`,
`TestPackageInstallFailure`, `TestExitBoxBeforeCompletion`, `TestPackageInstallSuccess` - passes
only while the machine can reach r-project.org, and reports a connectivity string where the test
expected its mocked outcome.

**The seam already exists and this file already uses it.** `TestInternetConnectionFailure` forces
the failure path with `HttpClientTestHelper.SimulateNoNetworkInterface()`, and `TestStartToFinish`
wraps itself in `HttpClientTestHelper.SimulateSuccessfulDownload(...)`. The helper intercepts
`HttpClientWithProgress`, so a success-mode stub makes `CheckForInternetConnection` deterministic
without touching the network. The other tests were simply missed.

**Fix**: wrap the remaining `InstallPackages` paths in a success-mode `HttpClientTestHelper`, the
way `TestStartToFinish` already does. NOT done tonight - it needs a build and a re-stage, and the
9-hour run owns the machine. Left for the morning.

**Master-applicable: YES, and checked, not assumed.** `git diff origin/master HEAD` over both
`TestFunctional/RInstallerTest.cs` and `ToolsUI/RInstaller.cs` is EMPTY - the branch's copies are
identical to master, so the defect and its fix belong in the master PR alongside the audit-log and
`AssertComplete` changes.

### 2026-08-30 (night run) - `TestExplicitRT`: an import that finished and was never finished with

Second failure of the night, 22:51, at 8,501 instances. A DIFFERENT failure from the
`TestRInstaller` one, and again **not in the path of anything changed today**.

```
Timeout 360 seconds exceeded in WaitForConditionUI (Expecting loaded document ...
No ChromFileInfo.FileWriteTime for ...120315_125.mzML;...120315_126.mzML
[unloaded=2, finalCache=none, joiningDisabled=False, 125 cached=False 126 cached=False])
AllChromatogramsGraph (-> all four files: 100%   Total complete: 100%)
```

**The import COMPLETED and the document never noticed.** All four files report 100% in the
progress graph, yet two are `cached=False` and `finalCache=none`, so the document never reached
loaded and the test timed out after six minutes.

**Nothing was working on it.** The failure carries a thread dump, and the only `Thread.Join` in it
is `HangDetection.TryGetThreadDump` on the test's own thread - no loader thread anywhere. So this
is not a hang inside cache building; the work finished and the step that would commit it never
ran. Dump preserved at
`D:\tests\nightly-logs\20260830_2251-TestExplicitRT-failure-with-threaddump.txt`.

**A lead, NOT a conclusion.** `BackgroundLoader.OnLoadBackground` forces a document-changed
notification on its way out, specifically because "loading blocks them from triggering new
processing, but new processing may have accumulated" - and it does that **only when
`!IsMultiThreadAware`** (`BackgroundLoader.cs:132`). `ChromatogramManager` sets
`IsMultiThreadAware = true` (`Chromatogram.cs:54`), so it does not get that safety net and depends
on a real document-changed event to re-trigger. Idle loaders plus an uncommitted final join is
consistent with such an event being missed. **Unverified** - it fits the evidence and has not been
reproduced or instrumented.

**Not caused by today's work.** `ExplicitRTTest` is a functional test driving `SkylineWindow`; it
references neither `MemoryDocumentContainer`, `ResultsTestDocumentContainer` nor `AssertComplete`,
so none of tonight's three commits execute in it.

**Frequency**: first sighting. 16 executions tonight, and clean in both of the day's earlier runs
- 25 executions this morning and 35 in the 23,250-instance run - so 1 in 76 across the day. No
nightly failure history on master. Worth watching rather than acting on: one occurrence is not
enough to bisect against, and the next one will land in the same log with the same thread dump.

### 2026-08-31 (night run) - `TestWatersConnectExportMethodDlg`: a PORT REGRESSION in real product code

Third failure of the night, 02:52, at 29,331 instances. Unlike the other two this one is a
**genuine defect in shipping code**, introduced by the port, and worth fixing on this branch.

```
System.ArgumentException: Parameter is required (Parameter 'refresh_token')
   at IdentityModel.Client.Parameters.AddRequired(...)
   at IdentityModel.Client.HttpClientTokenRequestExtensions.RequestRefreshTokenAsync(...)
```

**Not a network failure** - the test is fully mocked with `MockHttpMessageHandler`. Its mock token
response is the whole story:

```json
{"access_token":"qqq","expires_in":3,"token_type":"Bearer","scope":"webapi"}
```

**Three seconds, and no refresh token.** So in `WatersConnectAccount.Authenticate()`:

1. the token is cached with `ExpirationDateTime = UtcNow + 3s`;
2. any authentication more than three seconds later finds it expired;
3. that enters the refresh branch with `RefreshToken` null, since the mock never supplied one;
4. IdentityModel 7's `RefreshTokenRequest` validates required parameters CLIENT-SIDE and THROWS;
5. so `if (!refreshedToken.IsError)` - the fallback to `RequestPasswordTokenAsync` - is never
   reached, and the exception escapes `Task.Run(...).Result` and fails the test.

**Why master is immune.** Master calls the old API, `tokenClient.RequestRefreshTokenAsync(refreshToken)`
(`WatersConnectAccount.cs:237` on master), which returns an error RESULT rather than throwing, so
`IsError` is true and the password grant runs - which the mock answers happily. The migration to
IdentityModel 7 (`RefreshTokenRequest` + `Parameters.AddRequired`) arrived with Matt's
`58ee602f7e` "Skyline net8 port - Shared wrappers on pwiz-sharp + net8 fixes" (2026-07-02),
**not on master**. The error handling around it was written for an API that reported failure by
return value and was never adapted to one that reports it by exception.

**This is not only a test problem.** Against a real waters_connect server that returns no refresh
token, an expired session would throw instead of quietly re-authenticating with username and
password. The fallback exists; the port made it unreachable.

**Fix**: only attempt the refresh when the cached response actually carries a refresh token, and
treat a throwing refresh the same as a failing one - fall through to the password grant. Not done
tonight; the 9-hour run owns the machine.

**Why it took 5.5 hours to appear**: the three-second lifetime makes it a race against how long
the test takes between authentications. It needs a machine slow enough to cross that boundary, so
it is load-dependent - 45 executions tonight over 9 passes, all clean until two of five languages
(en, zh) crossed it in the same minute at 02:52, with fr/ja/tr passing alongside. Clean in both of
the day's earlier, shorter runs (20 and 35 executions). No nightly history on master, as expected
for a port-only defect.

**Master-applicable: NO.** Port-only, like the loader-wait fix. Belongs on this branch.

**Confirmed quantitatively (03:33).** A third failure (pass 11, `fr`) allowed checking the theory
against the clock. Duration of this test, per pass, in seconds:

| Pass | 2-4 | 5-9 | 10 | 11 |
|---|---|---|---|---|
| Durations | mostly 2s | 3s | **5s, 6s**, 3s, 3s, 3s | 3s, 3s, 3s, **11s**, 3s |

**Every failure is exactly a run that took longer than three seconds**, and the baseline crept
from 2s to 3s as the workers aged - sitting right on the mock's `expires_in: 3`. Nothing else
distinguishes the failing runs from the passing ones. Expect the rate to RISE as a run lengthens,
which is why a 2.5-hour or 4-hour run never sees it and a 9-hour one does.

**The test is not at fault.** The three-second expiry is deliberate: it exists to force the token
to expire so the "expired session re-authenticates" path gets exercised, and it supplies no
refresh token precisely so the password grant is the path taken. That is the behaviour the port
broke. This is a good test catching a real regression, not a flaky test needing a longer timeout -
so raising `expires_in` would HIDE the defect rather than fix it.

#### Brendan's two questions, answered (2026-08-31 morning)

**Is the fix already in flight? YES - do NOT write a competing one.** PR **#4613** (rita-gwen,
open, base master, `Skyline/work/20260825_watersConnectHttpClientWithProgress`) is exactly the
HttpClientWithProgress conversion Brendan remembered, and it **removes this failure mode as a side
effect**. It replaces

```csharp
tokenClient.RequestRefreshTokenAsync(expiredTokenCacheEntry.TokenResponse.RefreshToken).Result
```

with a direct form POST (`grant_type=refresh_token`, `refresh_token=...`) through
`HttpClientWithProgress`, keeping `if (!refreshedToken.IsError)`. A form POST does no client-side
required-parameter validation, so an empty refresh token can no longer THROW - it posts, gets a
response, and the fallback to the password grant runs as designed. **Action: land #4613 and merge
it through, rather than patching `Authenticate()` here.**

*Merge hazard worth flagging*: #4613 is written against master's OLD `TokenClient` code, while this
branch carries the IdentityModel 7 rewrite from Matt's `58ee602f7e`. When master merges in, both
sides will have edited `Authenticate()`. **Take #4613's form-POST version** - it is both the newer
design and the one without the defect.

**Was master's recent fix the answer? No, and the branch already has it.** `ecf53f8859` (#4603,
Rita, 2026-08-24, "Fixed TestWatersConnectExportMethodDlg failing on the second in-process run")
IS an ancestor of this branch. It fixed a different thing - the pooled `IHttpClientFactory`
pipeline serving a previous run's mock handler - and does not touch the token refresh path.

**Are these tests misplaced, and do they belong in TestConnected?** Both live in `TestFunctional`.
Split verdict:

* **`TestRInstaller` - yes, it really does connect.** `RInstaller.InstallPackages()` calls
  `RUtil.CheckForInternetConnection()`, a live HEAD to `www.r-project.org`, with no stub. So the
  dependency is real. **But moving it to `TestConnected` is the weaker fix**: the stub seam already
  exists and this very file already uses it twice (`SimulateNoNetworkInterface` in
  `TestInternetConnectionFailure`, `SimulateSuccessfulDownload` in `TestStartToFinish`). Stubbing
  the remaining paths makes the test deterministic AND keeps its coverage in ordinary runs, which
  a move to `TestConnected` would forfeit. Recommend stubbing; move only if that proves awkward.
* **`TestWatersConnectExportMethodDlg` - no, Brendan's own suspicion was right.** It is fully
  mocked with `MockHttpMessageHandler` and recorded JSON under `MockHttpData\`, and makes no real
  connection at all. It is correctly placed, and its failure was never a connectivity problem.

### 2026-08-31 - PR #4587 merged; work moved to a new branch

**PR #4587 merged** into `Skyline/work/20260612_net8_port` (the net8/net10 port branch, NOT
`chambem2/pwiz-sharp` which the TODO's Branch Information still names as the target - the merge
went to the port branch, and `origin/Skyline/work/20260818_commonutil_winforms_split` has been
deleted). Verified by `59e78e9181`, our last PUSHED commit, being an ancestor of
`origin/Skyline/work/20260612_net8_port` and not of `origin/chambem2/pwiz-sharp`.

**None of the seven commits from the 2026-08-30/31 session were ever pushed**, so none are in that
merge. They have been moved to a new branch:

* **New branch**: `Skyline/work/20260831_net10_nightly_fixes`, from
  `origin/Skyline/work/20260612_net8_port` @ `fc02f6d68e`
* **Old tip preserved** as `backup/20260818_commonutil_pre_rebase` @ `ec87d6f705` until the new
  PR is up
* Cherry-picked cleanly - the twelve commits that landed on the port branch since our last push
  touch **no file** our seven touch, so there was nothing to conflict
* **Verified equivalent**: the diff against the new base is identical to the diff against the old
  one, 11 files / 608 insertions / 32 deletions either way
* Rebuilt on the new base: solution clean, CodeInspection 0 failures, and `TestExplicitRT`,
  `TestAuditLogTutorial`, `WatersImsMse...AsSmallMolecules` and `TestUiThreadExceptionFilter` all
  pass over two passes

**Contents of the new branch** (7 commits):

| Commit | What |
|---|---|
| `4b4b175693` | WinForms marshaled-call exception filter (eight net10 nightly failures) |
| `aad6605077` | Narrowed that filter so doubtful cases stay reported |
| `f709fe01aa` | NHibernate SessionFactory disposal - the pass-1 managed leak |
| `139b7f8f60` | `TestAuditLogTutorial` waits for the document grid |
| `cedd916516` | Superseded loader's cancellation no longer ends a results test's wait |
| `49c8c86d2e` | That fix announces when it rides out the race |
| `1fce78184e` | Loader lifecycle trace for the `TestExplicitRT` failure |

**Still to do**: this TODO covers the merged PR and should be completed/archived (`/pw-complete`),
with a new TODO opened for the new branch. Not done here - it is Brendan's call whether to split
the history or carry this file forward.
