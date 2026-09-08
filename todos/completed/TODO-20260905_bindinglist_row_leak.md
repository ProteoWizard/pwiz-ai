# TODO: Rows bound by Skyline's settings grids were never released

**Status**: Completed
**PR**: [#4644](https://github.com/ProteoWizard/pwiz/pull/4644)

## Branch Information

- **Branch**: `Skyline/work/20260905_bindinglist_row_leak` (off `master`)
- **Checkout**: `C:\proj\daily`
- **Module**: `skyline`

## Summary

Every settings grid built on `SimpleGridViewDriver` retained the rows it displayed for the life of
the process. Found while leak-checking the .NET 10 port, but the defect is on `master` and has been
shipping — it is not a port bug, which is why it went to master on its own branch rather than into
the port PR.

## Root cause

`SortableBindingList<T>` did not implement `IRaiseItemChangedEvents`. `BindingList<T>` answers
**false** there whenever `T` lacks `INotifyPropertyChanged` — which every row type bound by these
grids does (`DbIrtPeptide`, `DbOptimization`, `EditIsolationWindow`, `PeakCalculatorWeight`, ...) —
and a `BindingSource` that gets false subscribes to its **current** row through
`PropertyDescriptor.AddValueChanged`.

That subscription lives in `ReflectPropertyDescriptor._valueChangedHandlers`, reached from
TypeDescriptor's static provider cache. Crucially the handler's **target is the BindingSource**, so
the static cache roots the BindingSource, which holds `DataSource` -> the list -> **every row**. One
subscription, the whole list.

Both of these are required for the leak, and the fix makes both moot by never creating the hook:

- the row type has no `INotifyPropertyChanged`, and
- the BindingSource is not disposed.

`BindingListView` already answered true here, with a comment describing exactly this behaviour.
`SortableBindingList` simply never got the same treatment.

### Three explanations were wrong before this one

Each was disproved by measurement, not argument, and the record matters because the wrong ones are
plausible:

- *"the BindingSource subscribes to every row"* — no, only the current row.
- *"current row only, so the leak is one row"* — no; a 100-row list retained all 100. A per-row hook
  cannot do that; the hook's target dragging the list can.
- *"the dialog is not disposed"* — no; instrumenting `EditIrtCalcDlg` showed construction and
  `Dispose(disposing=True)` pairing 1:1.

The amplification settled it: 200 iterations, rows/list varied, `BindingList` against the fixed
`SortableBindingList`. With disposal, 0 survivors everywhere. Without, **200 / 2000 / 20000 vs 0**.

## What shipped

| File | Change |
|------|--------|
| `pwiz_tools/Shared/Common/DataBinding/SortableBindingList.cs` | Implements `IRaiseItemChangedEvents` returning true |
| `pwiz_tools/Skyline/SettingsUI/SimpleGridViewDriver.cs` | Registers the BindingSource with `Program.GcTracker` |

## Evidence

`IrtRedundantDbFunctionalTest`, 100 iterations, net472 (the runtime the PR targets):

| | managed slope | R² |
|---|---|---|
| before | 3.83 KB/run | 0.985 |
| after | 0.00 KB/run | 0.000 |

Across two full nightly runs of the .NET 10 branch, **thirteen** tests with a positive managed slope
went to zero and nothing regressed: the six iRT tests plus `ConsoleImportNonSRMFile`,
`TestLabelLayoutDeterminism`, `TestExportSpectralLibrary`, `TestFilesTreeForm`,
`IrtBlibFunctionalTest`, `UpgradeCancelFunctionalTest`, `TestSpectrumFilterTransitionList` and
`TestUniquePeptidesSettings`.

A dotMemory capture of the same scenario after the fix showed a 22-object delta, 11 of them
`RuntimeType` with no reference graph, against 14,773 survived — as clean as the tests get.

## Why the GC registration matters more than the fix

**The nightly never reported this leak.** 3.83 KB/run is below the 8 KB managed threshold, and two of
the other leaks it cleared (4.40 and 5.89 KB/run, both perfectly linear at R² = 1.00) were likewise
invisible. A magnitude gate cannot see a leak smaller than itself.

`CheckAllFormsDisposed` could not have caught it either — that asks only whether `Dispose` ran, and
here the form was disposed *and* collected while the BindingSource it owned was not. Form-level GC
tracking was prototyped and abandoned for the same reason: it would have passed.

Registering the BindingSource converts the whole class of defect into an immediate per-test failure.
Verified both directions on both runtimes: with the leak restored, `IrtRedundantDbFunctionalTest`
fails in **under 7 seconds** with `GC-LEAK Objects not garbage collected after test: BindingSource x3`
and the retention chain printed; with the fix, the grid-dialog suite passes clean and no other one of
the 14 drivers reports retention.

## Follow-ups filed

- [#4643](https://github.com/ProteoWizard/pwiz/issues/4643) — `EditOptimizationLibraryDlg` in
  small-molecule mode: five pre-existing defects found while testing this, none related to the leak.
  Note recorded there that a `DataError` handler on `SimpleGridViewDriver` is **not** the fix — it
  pre-empts the per-dialog handlers six dialogs already have, and breaks `TestIsolationScheme`.

## Progress Log

### 2026-09-07 - Merged

PR #4644 merged as commit `4cb159f`, all 19 TeamCity checks green. Shipped the
`IRaiseItemChangedEvents` implementation and the GC-tracker registration together — the fix and the
check that would have caught it. Nothing was deferred from the PR's own scope.

Deliberately left out along the way: a `DataError` handler for the settings grids (written, tested,
**reverted** — it pre-empted the per-dialog handlers six dialogs already have and broke
`TestIsolationScheme`), and a unit test asserting the leak (written, **deleted** — it passed with and
without the fix, because WinForms unsubscribes correctly in isolation on both .NET Framework and
.NET 10, so it looked like protection while providing none). The real guard is the GC registration,
which was verified red/green on both runtimes.

Follow-up [#4643](https://github.com/ProteoWizard/pwiz/issues/4643) carries the five
`EditOptimizationLibraryDlg` small-molecule defects found while testing this.

Open question for a later decision: whether this wants a cherry-pick to the release branch. The leak
is on master and affects shipping Skyline, not only the .NET 10 port.
