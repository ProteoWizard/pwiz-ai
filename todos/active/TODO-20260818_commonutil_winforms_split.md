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
fire. Working tree in `C:\proj\pwiz-work1` is dirty and uncommitted.

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

### Follow-ups

- [ ] Commit. Nothing is committed yet; `pwiz-work1` and `ai` are both dirty.
- [ ] Report the net472 breakage to Matt.
- [ ] `ai/scripts/Skyline/Deploy-SkylineMcp.ps1:26` hardcodes `..\..\..\pwiz\...`, so it
      always deploys from the `pwiz` checkout regardless of which one is active.
- [ ] Decide the #4497 sequencing now that the wrapper is plain net8.0 - Osprey can go back
      through it and stop reproducing the six `MsDataFileImpl` semantics by hand.
- [ ] Drop the `BrukerFormat.cs` fix from the Osprey branch on its next rebase.

