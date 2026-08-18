# CommonUtil: break the WinForms dependency so ProteowizardWrapper can be plain net8.0

## Branch Information
- **Checkout**: `C:\proj\pwiz-work1` (the team's **Integration** checkout, agreed at the
  2026-08-17 dev meeting; SkylineNightly runs against Matt's PR will start here)
- **Branch**: work directly toward a PR **into `chambem2/pwiz-sharp`** (Matt's #4178), NOT
  master. Currently checked out at `5ef89bd228`.
- **Created**: 2026-08-18
- **Status**: Not started - analysis done, execution pending
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
- [ ] `Collections/LinqExtensions.cs:26` - `using System.Windows.Forms;` with **no WinForms
      type used anywhere in the file**. Delete the line. This alone makes `Collections` clean.

### Tier 2 - genuinely GUI, move to Common as-is
- [ ] `GUI/CommonAlertDlg.cs` + `.Designer.cs`, `GUI/MessageIcons.cs`
- [ ] `CommonResources/Images.Designer.cs`
- [ ] `SystemUtil/CenterWinDialog.cs`, `CommonFormEx.cs`, `FormUtil.cs`,
      `TreeViewStateRestorer.cs`, `ConcurrencyVisualizer.cs`
- [ ] `SystemUtil/PInvoke/User32.cs`, `User32Extensions.cs`, `PInvokeCommon.cs`
      (CRITICAL-RULES wants PInvoke isolated in one place - keep them together)

### Tier 3 - do NOT move wholesale; these need thought
- [ ] `SystemUtil/CommonActionUtil.cs` - **split, do not move.** `RunAsync` is the async
      helper CRITICAL-RULES mandates for all `pwiz_tools/Shared` code, so it must stay
      portable. Only `SafeBeginInvoke(Control control, Action action)` is WinForms. Moving
      the class would force WinForms onto every Shared consumer.
- [ ] `SystemUtil/Caching/Producer.cs` + `Receiver.cs` - thread `Control ownerControl`
      through the API (`RegisterCustomer(Control, ...)`, `HandleDestroyed`,
      `InvokeRequired`). Genuinely UI-lifetime-bound, so moving wholesale is honest.
      Abstracting behind `ISynchronizeInvoke` is possible but more work for less clarity.

### Tier 4 - the payoff
- [ ] Drop `UseWindowsForms` from `CommonUtil.csproj`; retarget it off `net8.0-windows`
- [ ] Make `ProteowizardWrapper` plain `net8.0` (it has **zero** WinForms usage of its own -
      verified 2026-08-17)
- [ ] **Retire `PortableUtil`** if it is now redundant. It is only 10 files (CLI argument
      parsing + `CommandStatusWriter`), created for master because CommonUtil was too tied to
      net472. A WinForms-free CommonUtil is the right home for exactly that content.

## Rejected alternative

Moving what `ProteowizardWrapper` needs INTO `PortableUtil` and breaking its CommonUtil
dependency. PortableUtil is a 10-file sharing layer, not a utility library; putting
`SignedMz` / `ImmutableList` / `SpectrumMetadata` there makes it CommonUtil #2 and entrenches
the split we want to remove - and it leaves CommonUtil WinForms-bound, so the next portable
consumer hits the same wall.

## Also for this PR into Matt's branch

- [ ] **`BrukerFormat.cs` XML doc fix** (currently carried in the #4497 branch, belongs
      here): `<see cref="CompassXtractData"/>` is CS1574 when that file is compiled out
      without vendor licenses, so **Bruker does not build in the no-licenses configuration**.
      Change the two references to `<c>`. Once this lands in Matt's branch, DROP it from the
      Osprey branch on the next rebase.
- [ ] **Investigate: does a Release Skyline link the DEBUG pwiz-sharp assemblies?**
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

- [ ] Move `SafeBeginInvoke(Control, Action)` to a new `ControlUtil` in
      **`pwiz.Common.Controls`** - that namespace **already exists in `Common`**
      (`Common/Controls/AutoScrollTextBox.cs`, `Controls/Clustering/*`), so this needs no new
      structure.
- [ ] Add a CodeInspection rule forbidding WinForms in CommonUtil, modelled on the existing
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
