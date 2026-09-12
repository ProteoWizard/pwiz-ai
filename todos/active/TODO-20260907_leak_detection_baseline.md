# TODO: Memory leak detection baseline for the .NET 10 nightly

## Branch Information

- **Branch (PR)**: `Skyline/work/20260911_net10_leak_fixes` - the leak fixes
- **PR**: https://github.com/ProteoWizard/pwiz/pull/4659
- **Branch (parked)**: `Skyline/work/20260911_leak_estimator` - estimator and diagnostics tooling
- **Branch (original)**: `Skyline/work/20260907_leak_detection_baseline` (off `Skyline/work/20260612_net8_port`)
- **Checkout**: `C:\proj\pwiz-work1`
- **PR target**: `Skyline/work/20260612_net8_port` (the port branch), not master
- **Module**: `skyline`

## Why this exists

The .NET 10 port cannot become master until its memory behaviour under test is trustworthy. Two
nights of full leak-checking runs (2026-09-04 and 2026-09-05, archived in `D:\test\nightly-logs\`)
say the failure behaviour is in good shape — **zero test failures across 644 leak-checked tests, both
runs** — but the memory reporting is not. It reports leaks that are not there, misses leaks that are,
and the Private Bytes axis carries so much variance that it cannot support a threshold at all.

This branch is where that gets fixed. It will take several commits; it exists so that iterating does
not land half-finished threshold changes on the port branch.

## What the two nightlies established

### The native heap axis reports a different random set every night

Six of seven heap leakers **changed identity** between two runs of the same suite on the same
machine:

| | 09-04 | 09-05 |
|---|---|---|
| AgilentMseChromatogramTest x2 | 39.9 / 20.6 | gone |
| TestInternationalFilenames | 50.8 | gone |
| TestLogScaleAxis | 33.8 | gone |
| TestSrmSmallMoleculeChromatograms | 91.5 | gone |
| TestSmallMoleculesQuantificationTutorial | 178.2 | gone |
| ConsoleAddDecoysTest | - | new, 55.9 |
| TestTreeRestoration | - | new, 40.8 |
| TestMSstatsTutorialLegacy | - | new, 39.1 |
| **TestGroupedStudies1Tutorial** | 2056.6 | 1925.3 |

Reproducing them in isolation agreed: five of six did not merely fail to reproduce, they went
strongly **negative** — `TestSrmSmallMoleculeChromatograms` reported +89.4 KB/run in the nightly and
−522.8 KB/run alone. `HeapMemory = 20 * KB` in `TestRunner/Program.cs` is roughly an order of
magnitude below that axis's measured noise floor.

`TestGroupedStudies1Tutorial` is the one real one, confirmed four ways (two nightlies, an isolation
run, and an independent measurement from a parallel session).

### The managed axis is reliable, and its gate is set too high

On the *same runs*, managed gave R² = 1.00 where heap gave 0.00–0.63. Managed deltas for
non-leaking tests sat in a tight 3.1–7.6 KB band; the one real leak reproduced to within 0.7 KB.

But `ManagedMemory = 8 * KB` hides real leaks. Two of the three leaks fixed this week —
`TestAddIrtStandards` at 5.89 KB/run and `IrtRedundantDbFunctionalTest` at 4.40 KB/run, both
perfectly linear at R² = 1.00 over 100 iterations — were **never reported**, because they sit under
the threshold. They surfaced only because they were pulled in by hand as near-misses.

### A magnitude gate is the wrong instrument for small leaks

The `SortableBindingList` leak (PR #4644) was 3.83 KB/run. No magnitude threshold can catch it
without drowning in false positives from the same band. What did catch it, in under 7 seconds, was a
GC assertion: register the object that should die, and let the per-test check fail with the retention
chain printed. That is the direction this work should go.

## Root cause of the detection problem: the estimator, not the thresholds

Found 2026-09-08 by reading `TestRunner/Program.cs` and reproducing its output arithmetically from
the nightly log. **Every threshold in this file is being compared against a statistic that is not
what the code's comment says it is.**

The leak check keeps a sliding window of the last 8 samples and calls `LeakTracking.MeanDeltas`,
described in the loop as "Run linear regression on memory size samples". There is no regression
anywhere in TestRunner. `MeanDelta` averages the 7 consecutive differences, and that sum
**telescopes**:

```
mean(v[i] - v[i-1], i = 1..7)  ==  (v[7] - v[0]) / 7
```

So it is a **two-point** estimate that throws away the six interior samples. It is then reduced
further: `minDeltas = minDeltas.Min(lastDeltas)` keeps the element-wise **minimum** across every
window, and the test exits as soon as one window is under threshold.

Two consequences, both measured against `SkylineTester-20260907-...-9leaks.log`:

**It biases every leak downward, which is why real leaks go unreported.** On
`TestGroupedStudies1Tutorial` — the cleanest signal in the suite, heap rising 148 -> 196 MB over 24
iterations at R² = 0.997:

| estimator | result |
|---|---|
| least-squares slope over all 24 | **2.153** MB/run |
| mean of the 17 window estimates | 2.155 MB/run |
| min of the 17 window estimates (what TestRunner uses) | **1.859** MB/run |
| what the nightly reported | 1.857 MB/run |

The last two lines match, which is what confirms the reading. Taking the minimum of 17 noisy
estimates costs 14% *on a near-perfect signal*; the noisier the axis, the deeper the bias. This is
the mechanism behind "the 8 KB managed gate hides real leaks" recorded above — a 3.83 KB/run leak is
not merely under the gate, it is measured as smaller than it is before the gate is consulted.

**On Private Bytes it inverts the sign.** Same test, same 24 iterations, `TotalMemory` axis:

| estimator | result |
|---|---|
| least-squares slope (private bytes rise 466 -> 511 MB) | **+2.60** MB/run |
| mean of windows | +2.66 MB/run |
| min of windows (TestRunner) | **-4.30** MB/run |
| what the nightly logged | -4.40 MB/run |

A genuine 45 MB rise is reported as a 4.4 MB/run *reduction*. The `TotalMemory = 150 * KB` threshold
is not "too tight" or "too loose" — on this estimator it is unreachable, which is why three nightlies
in a row report zero private-bytes leaks. The axis is already effectively off.

**This reframes the Private Bytes spikes** (up to 2.4 GB on `TestFindNodeCancel`, 1.1 GB on
`TestDocumentSizeError`, and generally new on .NET 10). They are not currently causing false leak
reports and smoothing them would not change any reported number, because `Min`-over-windows already
discards isolated spikes far more aggressively than any smoother would. Smoothing is worth doing for
the *plot* and for run stability, not for detection. Fix the estimator first, then decide what the
axis can support.

## Work items

### 1. Replace the two-point delta with a fitted slope

Change `MeanDeltas` to a least-squares slope over the window, and reconsider `Min`-over-windows —
probably median-over-windows, or simply the slope over all iterations run. Both are a few lines in
`TestRunner/Program.cs` and both are directly testable against the three archived nightly logs, since
the current estimator can be reproduced from the logged series exactly (done above). Report R²
alongside the slope so a leak can be told from a filling cache without a separate script.

Only after that does re-tuning `HeapMemory` / `ManagedMemory` / `TotalMemory` mean anything: today
those thresholds are being compared against a different quantity than anyone assumes.

### 2. Characterise Private Bytes variance

`TotalMemory = 150 * KB` already carries the comment "Too much variance to track leaks in just 12
runs". Quantify it: run the shape analysis across a representative set and report the distribution,
then decide whether the axis can support any threshold. Note the spikes above are per-test and
reproducible (`TestFindNodeCancel` peaked at 2,365 MB against a 348 MB run median), so this is not
purely noise — some of it is tests that genuinely allocate, and .NET 10 releasing committed memory
later than .NET Framework did. Worth measuring `GC.GetGCMemoryInfo().TotalCommittedBytes` alongside
private bytes to separate "GC holding committed segments" from "native growth"; the archived
comparison cannot settle it, because **every** net472/net8 log in `D:\test\nightly-logs` is a
parallel run whose Total column barely moves (median 339 MB, max 374 MB across 45,171 rows), while
only the three net10 leak-sweep logs are serial. A serial net472 run of the spiking tests is the
missing control.

### 3. Extend GC-tracker registration

`Program.GcTracker` currently covers `SkylineWindow`, `SrmDocument`, and (in PR #4644)
`SimpleGridViewDriver`'s BindingSource. Each registration converts a class of leak from an
unreportable slope into an immediate per-test failure. Candidates worth evaluating — each needs its
own measured pass, since turning one on may surface existing retention:
- Other long-lived UI objects with a clear "should be dead after the test" contract.
- **Not** `CommonFormEx` — prototyped and abandoned. `CheckAllFormsDisposed` already covers
  undisposed forms per test, and form-level GC tracking would have **passed** the BindingSource leak,
  because the form was disposed *and* collected while the BindingSource it owned was not.

### 4. Finish or drop `GcHeapHistogram`

Committed here as a starting point, but **it has not yet closed a case unaided** and has produced two
false positives, both `String`, both its own retained state on the heap it was measuring. The second
over-reported by ~250× against a dotMemory capture showing a 22-object delta.

The unfinished fix: persist the baseline snapshot to disk and drop the in-memory copy, so nothing
belonging to the tool is live during the second capture. Filtering more type names only moves the
blind spot and would hide real string leaks. If it cannot be made to agree with dotMemory on a known
scenario, drop it and keep only the `GcRootReporter` field-name work, which did earn its place.

### 5. Re-baseline

Once the above settles, run a full nightly and record the new expected leak set. That becomes the
baseline the port is promoted against.

## Known leaks, deliberately out of scope here

These are leaks to fix, not detection problems. Listed so they are not confused with the above:

- **The four wiff2 tests** (26–36 KB/run): one `SampleDataProviderServer` per `.wiff2` open, rooted by
  its own periodic Timer. Root-caused; a shared-api fix was written and **reverted** after a test
  proved it caused `ObjectDisposedException: SQLiteConnection` under concurrent readers. Deferred by
  decision. Two regression tests exist (uncommitted in `pwiz-work1`).
- **`TestKoinaConnection`** (16.5 KB/run managed): reported 16900.6 bytes in *both* nightlies,
  identical to the decimal, so deterministic given the test sequence — yet only 3.5 KB in isolation.
- **`TestGroupedStudies1Tutorial`** (~1.9 MB/run native) — root-caused 2026-09-08, see below.

### Folded in 2026-09-12: the per-cycle managed growth measured 2026-08-27

From `TODO-20260827_net8_managed_memory_leak.md` (now completed), the one leak observation on
the port line that no per-test check can see. Two full-suite overnight runs, 657 tests x 5
languages, 8 workers, a cycle being one pass through the list (3,285 results):

| | cycle 4 | last cycle | rate |
|---|---|---|---|
| net472 managed | 62.9 MB | 64.0 MB (cycle 13) | **+0.12 MB/cycle** — plateaus |
| net8 managed | 101.7 MB | 136.4 MB (cycle 10) | **+5.8 MB/cycle** — straight line |

~48x the managed growth rate, ~6 KB per test execution, so invisible at per-test granularity;
it exists only as a slope across cycles. That is exactly the estimator problem work item 1
addresses — a fitted slope with R² over the cycle series would report it directly. Not
blocking (9-hour throughput +5%, far from the container limit), but unexplained linear growth
in managed memory is a retained object graph, and master does not have it.

Candidates to eliminate first, all new on the net8 line: the `Wiff2LoadContext` side-by-side
`AssemblyLoadContext` (never unloaded), the staged portable runtime loaded per worker, and the
WinForms/SystemEvents hook changes made during the port. The shape (flat per-cycle, tiny
per-test) says something retained once per test class or per language switch rather than per
test, so do not expect pass-1 attribution to name a single test.

## `TestGroupedStudies1Tutorial`: a .NET 10 GDI+ regression in layout loading

Not a detection problem and not an old Skyline bug — a **port blocker**. Every claim below is a
measurement; the reasoning that produced them is in the session, the numbers are here.

### Per-heap attribution turns a 20-minute cycle into 3 minutes

`-ReportHeaps` already logs committed bytes for **every** Win32 heap, and the leak check only ever
reports their sum. Split out, **one heap carries the entire leak** — index 7, 2.12 MB/run at
R² = 1.00, deltas of 2.12 MB on *every single iteration*, deterministic to 0.01 MB, while every
other heap is flat. Summing them buries that in the process heap's churn, which swings hundreds of
KB within a single operation.

That is worth building into the tooling: it makes 4 iterations a better oracle than 25 were.
`ai/.tmp/leak-tools/Heap-Deltas.ps1` parses the `# Heaps` lines into per-heap slopes.

It also retired a false lead: English-only looked like it "plateaued" while 5 languages looked
linear. Heap 7 is identical in both. The language difference was noise in the summed heap.

### It is `SkylineWindow.LoadLayout`, at ~43 KB per call

Bisecting `DoTest` (heap 7, MB/run): import only 0.24 -> +`ExploreTopPeptides` 0.92 ->
+`ExploreGlobalStandards`+`ExploreBottomPeptides` 1.89 -> full test 2.12. Spread proportionally, so
not one hotspot. Against per-phase call counts only `RestoreViewOnScreen` fits all four groups
(0.047 / 0.043 / 0.048 / 0.058 MB per call); `SelectNode` and `ActivateReplicate` do not, since the
import phase has zero of the latter and still leaks.

Amplification settled it: import-only baseline plus 100 extra `RestoreViewOnScreen(6)` calls
predicted ~4.9 MB/run and measured **4.50** — **42.6 KB per call**, a 19x inflation. 45 calls x
42.6 KB = 1.92 MB of the measured 2.12.

### The runtime is the difference, not the code

Identical amplification, byte-identical test file, 400 layout loads each:

| | .NET 10 | .NET Framework 4.7.2 |
|---|---|---|
| heap 7, first -> last | 4.69 -> **18.18 MB** | 0.01 -> **0.01 MB** |
| slope | **4.50 MB/run** | 0.00 |
| all 12 heaps summed | rising | 30.23 -> 30.51, flat |

Both runtimes report 12 heaps and every one is flat on net472.

### Heap 7 is the GDI+ heap

Allocating known types and watching which one moves it:

| allocation | heap 7 | after `Dispose` |
|---|---|---|
| `SolidBrush` x500 | 376 bytes each | 0 |
| `Pen` x500 | 559 bytes each | 0 |
| `Bitmap(1,1)` x500 | 1,956 bytes each | 0 |
| `Font` x200 | 48 bytes each | 0 |
| WinForms `Control` x500 | 0 | - |
| managed `byte[4096]` x500 | 0 | - |

**GDI+ finalizers work fine on .NET 10** — abandoning 500 of each without `Dispose`, then
`GC.Collect` + `WaitForPendingFinalizers`, returned heap 7 to zero for all three types. So the
leaked objects are either still rooted or have no managed wrapper. Managed memory is flat
(~0.36 KB per load), which rules out ~100 retained small wrappers and is consistent with a small
number of **large** GDI+ objects — a single 100x100 32bpp bitmap is ~40 KB, close to the 43 KB.

### Rebuilding DigitalRune for .NET 10 does not fix it

Skyline references `DigitalRune.Windows.Docking.dll` as a prebuilt **net472** binary
(`pwiz_tools/Shared/Lib`, HintPath, no NuGet equivalent), loaded on .NET 10 through WinForms compat.
Source is in `uw-maccosslab/developers` under `skylinedev/DigitalRune-Docking-Windows/Source`; it is
now cloned at `C:\proj\developers` and buildable via
`ai/scripts/Skyline/DigitalRune/Build-DigitalRune.ps1`.

Rebuilt for `net10.0-windows` and swapped in (same assembly identity, 1.3.5.0, unsigned), the
measurement is **unchanged**: 4.68 / 9.20 / 13.69 / 18.18, the same 4.50 MB/run. The original binary
has been restored. This is expected in hindsight — the same IL runs either way — but the rebuild is
what makes the docking code instrumentable, and the script keeps it repeatable.

### Where the GDI+ churn happens

Probing committed heap-7 bytes at ten points across `LoadLayout`, over 100 loads (segments sum to
44.5 KB/load, reconciling with the 42.6 KB measured independently):

| segment | bytes/load |
|---|---|
| `destroys` -> `LoadFromXml` (DigitalRune `dockPanel.LoadFromXml`) | **+66,706** |
| `LoadFromXml` -> `InsertFilesView` (Skyline `InsertFilesViewIntoLegacyLayout`) | **+53,126** |
| `lockedStart` -> `destroys` (the ~15 `Destroy*` calls) | -36,416 |
| `beforeUnlock` -> `unlocked` (`DockPanelLayoutLock` disposal) | -24,014 |
| `unlocked` -> `enter` (between loads) | -11,143 |
| everything else | < 2,400 each |

Heavy churn with a net +44 KB. No single call is "the leak", so segment attribution cannot separate
allocated-and-freed from allocated-and-leaked. Object-level tracking is the next instrument.

**The most actionable lead looked like `InsertFilesViewIntoLegacyLayout`** at +53 KB/load — Skyline's
own recent FilesTree code rather than the third-party library, and it does build a `FilesTreeForm`
on *every* layout load rather than once, because the tutorial `.view` files predate
`FILES_TREE_SHOWN_ONCE_TOKEN` and the destroy block has just nulled `_filesTreeForm`. **Refuted by
measurement**: suppressing it entirely moved the leak from 4.50 to 4.40 MB/run, about 2%. The
+53 KB it allocates is freed elsewhere. (Building that form on every load is still odd and may
deserve its own look, but it is not this leak.)

### Minimal reproduction: docking a form, nothing else

Eliminating by construction — 100 create/show/close/dispose cycles each, GC and finalizers settled
before and after, measuring the GDI+ heap, which the probe **locates at run time** by allocating
500 `SolidBrush` and taking the heap that grows. That matters: GDI+ is heap index 7 on .NET 10 but
index **10** on net472, so a hard-coded index would have silently compared the wrong heaps.

| cycle x100 | .NET 10 | .NET Framework 4.7.2 |
|---|---|---|
| plain `Form`, empty | 0 | 0 |
| plain `Form` + `ZedGraphControl` | 0 | 150 B/form |
| plain `Form` + `TreeView` / `DataGridView` / `ToolStrip` / `SplitContainer` | 0 | — |
| **`DockableForm.Show(DockPanel, DockLeft)` + `Close` + `Dispose`, empty** | **978 B/form** | **0** |
| **same, holding a `ZedGraphControl`** | **978 B/form** | **0** |

It is the **docking operation itself** — byte-identical (97,776 for 100 forms, twice) whether the
form is empty or holds a graph, so neither the content nor the control types matter. No document,
no import, no layout file. The probe is kept at
`ai/.tmp/leak-tools/GdiPlusDockingRepro-probe.cs.txt`.

978 bytes/form against 43 KB per layout load implies roughly 44 dock operations per load, plausible
for ~10 forms that each dock, tab and activate.

### Root cause: Control.Region on a created handle, set once per docked form

Instrumenting DigitalRune (a `DockProbe` hook plus marks, diff kept at
`ai/.tmp/leak-tools/digitalrune-gdiplus-instrumentation.diff`) and bisecting the Show path by
GDI+ heap bytes. Every segment reconciles to the 976 B/Show total:

| segment | bytes/Show |
|---|---|
| `DockingHandler.Show` -> `Pane` setter -> `SetDockState` -> **`SetPaneAndVisible`** | **+1,152** |
| `resumeLayout` -> `activate` | -176 |
| all fifteen other segments | 0 |

`SetPaneAndVisible` -> `SetPane`, which sets `FlagClipWindow = true`, and that setter
(`DockingHandler.cs:1415`) is the whole story:

```csharp
_flagClipWindow = value;
if (_flagClipWindow)
  Form.Region = new Region(Rectangle.Empty);   // suppresses flicker while docking
else
  Form.Region = null;
```

`DockPane.cs:831` clears it again only once the form becomes **visible**, so in a tabbed pane every
form behind the active tab is disposed with that `Region` still assigned.

**The leak is in applying a `Region` to a created window handle, not in the managed object.**
Measured on .NET 10, 100 forms each:

| | leaked |
|---|---|
| `Region` set, cleared **before** the form is shown | **0** |
| `Region` set before `Show`, form shown | 978 B/form |
| `Region` set **after** `Show` | 978 B/form |
| `Region` set after `Show`, then set to `null` | 976 B/form |
| `Region` set after `Show`, then nulled **and** `Dispose`d | 976 B/form |

A `Region` object is only 176 bytes, so the ~976 is the native window-region state. On
.NET Framework 4.7.2 every one of these is **0**.

Two fixes were tried and **failed**, for the same reason - once the handle has it, giving the
managed object back is too late:

- `FlagClipWindow = false` in `DockingHandler.Dispose` - never runs; `DockableForm.Dispose` does
  not dispose its `DockingHandler`.
- `DockingHandler.FlagClipWindow = false` in `DockableForm.Dispose` - runs, and still leaks 978.

### There is no disposal point - the cost is charged at assignment

Bisecting the lifespan of the property, 100 forms each, on .NET 10:

| variant | leaked |
|---|---|
| never assigned | **0** |
| assigned **once** | 978 B/form |
| assigned **5x** | 4,882 B/form |
| assigned **10x** | 9,762 B/form |
| null right after | 976 B/form |
| null + `Application.DoEvents()` | 976 B/form |
| null in `OnFormClosing` | 976 B/form |
| null in `OnFormClosed` | 976 B/form |
| null before `Close` | 976 B/form |
| null in `OnHandleDestroyed` | 976 B/form |
| `RecreateHandle()` first | 976 B/form |

~976 bytes per **non-null** `Control.Region` assignment, charged when it is assigned and never
recoverable. Assigning `null` costs nothing, so setting the flag back to false does nothing for the
memory already gone. Every clearing point is identical to doing nothing.

### The fix: keep the clipping, bypass GDI+

`Control.Region` routes through GDI+ - its `Region` lives on the GDI+ heap. `SetWindowRgn` is what
that setter ends up calling anyway, and it takes a plain **GDI** region, so no GDI+ object exists to
leak. The system takes ownership of a region it accepts and frees it with the window.

In `DockingHandler.FlagClipWindow`, replacing the two `Form.Region` lines with:

```csharp
if (Form.IsHandleCreated)
{
  IntPtr region = _flagClipWindow ? NativeMethods.CreateRectRgn(0, 0, 0, 0) : IntPtr.Zero;
  if (NativeMethods.SetWindowRgn(Form.Handle, region, false) == 0 && region != IntPtr.Zero)
    NativeMethods.DeleteObject(region);   // the window refused it, so we still own it
}
```

plus three P/Invokes in `Win32/NativeMethods.cs`. 36 lines total, saved at
`ai/.tmp/leak-tools/digitalrune-native-clip-fix.diff`, uncommitted in `C:\proj\developers`.

Measured clean on **both** axes - 0 GDI+ bytes and 0 GDI handles - so it is not trading one leak for
another:

| | before | after |
|---|---|---|
| one docked form cycle | 978 B/form | **0** |
| 100 layout loads per iteration | 4.50 MB/run | **0.01 MB/run** |
| **`TestGroupedStudies1Tutorial`, unmodified** | **2.12 MB/run** | **0.017 MB/run** |

A control variant in the same run - a raw `Control.Region` assignment, which the fix does not touch -
still reads 978 B/form, so the probe stayed sensitive and the runtime bug is untouched. Only
DigitalRune's use of it is fixed.

Nothing reads `Form.Region` in the docking path; the only other readers are `DockOutline` and
`SplitterOutline`, on their own transient drag forms. **Those two also assign Regions and so leak the
same way**, but only per user drag rather than per docked form - worth the same treatment, not
urgent.

### All five sites, one helper

`DrawHelper.SetWindowRegion` / `SetEmptyWindowRegion` / `ClearWindowRegion` now serve every
`Control.Region` assignment in the library — `DockingHandler.FlagClipWindow`, both
`DockOutline.SetDragForm` overloads, `SplitterOutline.SetDragForm`, and `DockIndicator`. None
remain. It lives in the existing `Helpers/DrawHelper.cs` so the legacy non-SDK project stays valid
without adding a file to it.

The leak is content-independent, so one helper genuinely covers both shapes the library uses
(empty clips and path-derived regions):

| assignment, x100 forms, .NET 10 | through `Control.Region` | through the helper |
|---|---|---|
| empty region | 978 B/form | **0** |
| rectangle region | 978 B/form | **0** |
| path-derived region | 999 B/form | **0** |

GDI object count is 0 in every helper case, so it is not trading a GDI+ leak for a handle leak.

**The drag sites do leak, measured.** One real dock drag (`BeginDragDisplay`/`EndDragDisplay`, which
drives the actual `DockDragHandler`): **14,352 bytes before, 13,376 after — exactly 976**, one region
assignment. Small next to docking (976 per drag vs ~44 assignments per layout load) but real, and now
covered by the same helper. The residual ~13 KB is not region-related and does not accumulate.

### The .NET Framework guard is necessary, and that is measured too

The native path is **not** behaviour-neutral on .NET Framework. Forcing it there (legacy build with
`NETCOREAPP` defined) fails 4 of 6 tests with `NullReferenceException` in
`FilesTree.OnDocumentChanged`. Mechanism not investigated - there is nothing to gain on net472, which
has no leak, so the helper is guarded:

```csharp
#if NETCOREAPP      // not !NETFRAMEWORK: the legacy non-SDK project defines neither symbol,
                    // so the safe path has to be the default
```

### Validation

| | result |
|---|---|
| .NET 10, `TestGroupedStudies1Tutorial` unmodified, 4 iterations | **2.12 -> 0.017 MB/run** |
| .NET 10, five docking/layout tests | all pass |
| **net472, six tests, fixed DLL** | **all pass, 111.8 s** |
| net472, same six, original DLL (control) | all pass, 113.9 s |

So updating the net472 binary would be harmless, even though it is not needed there.

### A false alarm worth recording

An earlier round concluded "the fix hangs `TestFilesTreeForm` on net472". That was wrong, and the
mistake is instructive: the hang came from **how the DLL was built**, not from the change. Building
this assembly for net472 through an SDK-style project requires
`GenerateResourceUsePreserializedResources`, which writes the embedded images in a format needing
`System.Resources.Extensions` at run time - which Skyline's net472 app does not reference. The proof
was building **pristine source** through the same SDK project: it hung identically. Three hypotheses
(`redraw`, handle creation, the `IsHandleCreated` guard) were chased before that control was run;
running it first would have saved all three.

**So: build net472 with the legacy `DigitalRune.Windows.Docking.csproj` via MSBuild**, which is how
the shipped binary was made and which produces a byte-identical 270,336-byte DLL. The
`-TargetFramework net472` path in `Build-DigitalRune.ps1` produces a binary that loads but hangs, and
should be removed or switched to MSBuild.

### Shipping notes

`pwiz_tools/Shared/Lib/DigitalRune.Windows.Docking.dll` is a **tracked binary**, so the fix ships as
a rebuilt DLL + PDB, the way the Jan 2026 `DockPaneStrip` fix did (see
`ai/todos/completed/2026/01/TODO-20260128_DockPaneStrip_race_condition.md`). The source change must
land in `uw-maccosslab/developers` alongside it or the next rebuild loses it. `pwiz-work1` currently
carries the rebuilt net10 binary; `daily` is untouched.

Still unverified: on-screen flicker. Every measurement ran offscreen. The risk is lower than for
"do not clip at all" - the clipping still happens, through the call `Control.Region` itself makes -
but it has not been watched with a real window.

Worth reporting upstream regardless: `Control.Region` leaks ~976 bytes of GDI+ heap per non-null
assignment on .NET 10 and nothing reclaims it, where .NET Framework released it on
`Control.Dispose`. The probe in `ai/.tmp/leak-tools/` is a self-contained reproduction.

## 2026-09-09: two more leaks fixed, and the estimator design settled by measurement

### The 2026-09-08 nightly

8h51m, both passes, zero failures. Log: `SkylineTester-20260908-net10-9hr-COMPLETE-0failures-8leaks-gdiplusfix.log`.
**The GDI+ fix held** - `TestGroupedStudies1Tutorial`, 1.9-2.1 MB/run for three consecutive nights, is
gone from the leak list entirely and sits flat at 93-95 MB in pass 2.

Four nights make the axis split unambiguous. The **same five managed tests report every night**, to
within a few percent. Of the twelve heap entries across four nights, **eleven appeared in only one or
two nights** and the twelfth was `TestGroupedStudies1Tutorial`, the one real one, now fixed.

### Four of the five were one root cause, now excluded from leak checking

`Wiff2ResultsTest`, `FileTypeTest` (`TestData/Results/SmallWiffTest.cs`), `TestInstrumentInfo`,
`TestInstrumentSerialNumbers` (`TestData/PwizFileInfoTest.cs`) - all four read `.wiff2`, all four leak
the known `SampleDataProviderServer` at ~17 KB per file open.

`AbstractUnitTest.IsAbWiff2Safe` (and `ExtAbWiff2Safe`, which must move with it or the filename
becomes `swath.api-sample-centroid.wiff2`, which does not exist) returns
`CanImportAbWiff2 && TestPass != LEAK_CHECK_PASS`. In the leak pass the four tests read the
equivalent mzML instead - they still run and still assert - and full `.wiff2` coverage stays in
pass 2. Verified: all four report **0 leaked bytes** in pass 1 and still pass in pass 2 reading real
`.wiff2`.

One case loses coverage rather than substituting: `TestInstrumentSerialNumbers` checks `CI231606PT`,
an empty-serial-number case that exists only in the `.wiff2` file. Commented at the site.

`TestInstrumentInfo` has **no residual leak** behind the wiff2 one - 40 iterations with wiff2 off is
flat (11.25 -> 11.27, one step at iteration 8), against 34.6 KB/run at R2 = 0.9999 with it on.

### TestKoinaConnection: an undisposed GrpcChannel, fixed

The fifth. `KoinaConfig.CallWithClient` created a channel per call and only awaited
`ShutdownAsync()`. `GrpcChannel` owns an `HttpClient` and its connection pool and **is**
`IDisposable`, where the legacy `Grpc.Core` `ChannelBase` it replaced was not - so this is a
port-introduced regression from the Grpc.Core -> Grpc.Net.Client migration. Adding
`(channel as IDisposable)?.Dispose()` is a no-op on any non-disposable channel.

| 30 iterations, drop 10 warm-up | slope | R2 |
|---|---|---|
| before | 17.64 KB/run | 0.998 |
| after | 0.93 KB/run | 0.425 |

It also corrects the record: the old note that this was "only 3.5 KB in isolation" was measuring
through the warm-up. In isolation it is 16.4-17.6 KB/run, matching the nightly's 16.9 exactly.

### The estimator: what the data says to build

Brendan's point on why the sliding window exists is right - it is doing **warm-up rejection**, and
the downward bias is a side effect of the mechanism, not its purpose. His proposal (drop a fixed
warm-up, then fit) tested against last night's leak pass, 41 tests with >= 14 iterations:

- **Warm-up choice barely moves a real leak.** The four wiff2 leakers read 35.5 / 35.4 / 30.7 / 30.7
  KB/run at R2 = 1.00 whether 0, 5, 8 or 10 iterations are dropped.
- **But dropping hurts short series.** `FullScanFilterTestCentroided` (N=14) goes -21.9 -> -51.9 ->
  -111.2 -> -233.5 KB/run as more are dropped, R2 = 0.43. Six points left is not a fit. Warm-up
  exclusion and long fixed-length runs are a package; under today's early exit, a test that looks
  clean stops at 12-16 iterations.
- **Shape is what makes a low threshold safe.** A gate of `R2 > 0.9 AND slope > 1 KB/run` produces
  **zero false positives** across every leak-checked test in the run, at either warm-up setting.
  Noise tests sit at R2 0.27-0.75; every real leak is >= 0.99. The two hand-found leaks that the
  8 KB gate hid (4.40 and 5.89 KB/run) are both far above 1 KB and both at R2 = 1.00.
- The Koina series is the cleanest illustration: raw fit over 30 iterations gives 28.45 KB/run at
  R2 = 0.836; dropping 10 gives 17.64 at R2 = 0.998.

**Cost math for a leak-only night**: pass 1 was ~5h of the 8h51m at ~25 iterations, so 50 iterations
is roughly 10h for the sweep alone and 100 is roughly 20h. Dropping pass 2 buys back ~3.9h. So 50
without pass 2 is about a 10h night; 100 is not, without shrinking or parallelising the set. A middle
option: keep early exit but require a **minimum** of ~20 iterations before a test may exit, which
removes the short-series instability while letting most clean tests still exit early.

Note if pass 2 is dropped: it is now the only place `.wiff2` is read, and the only run that exercises
each test in all four languages.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260907_leak_detection_baseline.md` before starting work.

## 2026-09-10: the estimator switch, scored offline, and the first slopes run

No nightly ran on 09-09 - that night went to getting SkylineNightly running on the port branch as
the Integration branch, and it held `pwiz-work1`.

### Work item 1 is in, as a switch rather than a replacement

`1dc987b855`. Both estimators live behind one `ILeakEstimate` interface, so the pass-1 loop exists
once and choosing an estimator cannot change anything else about how the pass runs - which is what
makes the two comparable on the same night. `deltas` remains the default and is unchanged, verified
by running the same test both ways.

| arg | default | |
|---|---|---|
| `leakestimator` | `deltas` | `slopes` fits a least-squares line and reports R2 with the slope |
| `leakiterations` | 24 | maximum iterations |
| `leakwarmup` | 5 | dropped before fitting |
| `leakminiterations` | 20 | floor before a clean reading may end a test |
| `leakrsquared` | 0.9 | linearity a rising axis must show |

Slope-mode thresholds are their own set (`SlopeLeakThresholds`): managed and heap at **1 KB**,
private bytes left at 150 KB, handles unchanged. Same knobs on `Run-Tests.ps1` as `-LeakEstimator`,
`-LeakIterations`, `-LeakWarmup`, `-LeakMinIterations`, `-LeakRSquared`.

Two details that were not obvious:

- **The per-test iteration overrides had to become multipliers.** `LeakCheckIterationsOverrideByTestName`
  baked `LeakCheckIterations * 4` at static-init time, so raising the base on the command line would
  have left them at the old absolute count.
- **`ArgAsDouble` was culture-sensitive.** `leakrsquared=0.9` would parse as 9 on a machine with a
  comma decimal separator, and this runner exists to run French and Turkish. Now invariant.

Reporting keeps the delta estimator's line shape with the R2 appended *after* the word `bytes`, so
`SkylineNightly`'s three regexes and SkylineTester's `parts[2]` split both still match.

### Scored against all four archived nights before spending a night

`ai/.tmp/leak-tools/Score-Estimators.ps1`. The delta simulation reproduces 09-08 exactly - same
7 tests, 8 lines, values within the log's print precision - which is what makes the rest credible.

**The managed axis separates cleanly.** Across four nights, tests slope mode reports sit at
R2 0.999-1.00; tests it does not report top out at 0.70-0.75. Nothing lands between, so the 0.9 gate
is in a wide gap rather than on a boundary.

**It catches the two leaks the 8 KB gate hid**, on the 09-04 night, before either was found by hand:
`TestAddIrtStandards` 6.27 KB/run at R2 = 0.97 and `IrtRedundantDbFunctionalTest` 4.41 at R2 = 0.93.

**It drops the heap set that changed identity every night.** 09-08's two heap reports
(`AgilentMseChromatogramTestAsSmallMolecules` 20.5, `ConsoleAddAnnotationsFromArgumentsTest` 24.9)
fail the shape gate at R2 = 0.86 and 0.79.

**Positive control**: `TestGroupedStudies1Tutorial` heap on the three nights before the GDI+ fix
reads 2166-2194 KB/run at R2 = 0.99-1.00 under slopes, against 1880-2007 under deltas. The slope
recovers the true 2.153 MB/run least-squares value; the old estimator's ~14% under-report is exactly
as predicted.

The heap threshold barely matters once shape is gating - moving it 1 -> 50 KB changes the
long-series count by at most one test per night. The extra reports at 1 KB are all 8-sample series,
which the 20-iteration floor removes by construction.

### The cost is the floor, not the maximum

Pass 1 on 09-08 was 4.4h over 6,251 iterations, because **41% of tests exit at 8 iterations and 86%
at 11 or fewer**. Projected from that log's per-test timings:

| floor | pass 1 |
|---|---|
| today (none) | 4.4 h |
| 20 | 9.4 h |
| 24 | 11.3 h |
| 50 | 23.5 h |

`leakiterations` is nearly free by comparison - only tests that stay above threshold ever reach it,
so raising the maximum to 50 adds ~1h even if 50 tests run the full count. **Raise the maximum for
resolution, not the floor.**

### The first slopes run

Started 2026-09-10 18:37 on `pwiz-work1`, pass 1 only, full 1133-test list:

```
pwsh -File ./ai/scripts/Skyline/Run-Tests.ps1 -UseTestList -Pass 1 -Quality `
  -Configuration Release -SourceRoot 'C:\proj\pwiz-work1' `
  -LeakEstimator slopes -LeakIterations 50 -LeakMinIterations 20 -ReportHeaps
```

Log lands at `bin\staging\Release\SkylineTester test list.log`; archive it to
`D:\test\nightly-logs\` when it finishes. Expect ~9.4-10.5h. This is deliberately an exhaustive
sweep rather than a cheap one - the point is to catch what the biased estimator has been missing,
so the managed threshold is at 1 KB and every test gets at least 20 iterations.

**What to check when it lands**: the managed axis should be near-empty, since the five tests that
reported every night are all now fixed or excluded. Anything it does report at R2 >= 0.99 is new and
real. The heap axis is the open question - the archived logs cannot predict it, because every test
that would now run 20+ iterations stopped at 8 under the old early exit.

### Also fixed

`9b9a93499c` - `PwizFileInfoTest.cs` and `SmallWiffTest.cs` picked up UTF-8 BOMs in `d82108870e`
(the wiff2 commit). `CodeInspection` strips them on every run and then fails, so this was a standing
nightly failure.

### Worth a look later, not urgent

- `TestTargetResolver` shows user+GDI handles rising **0.9/run at R2 = 0.99** over 20 iterations.
  Under the 1-handle threshold, so neither estimator reports it, but that shape is not settling.
- `TestFilesTreeForm` fit 3.33 KB/run managed at R2 = 0.93 on the 09-04 night. Never investigated.
- `TestInternationalFilenames` (86-89 KB/run heap, R2 = 0.97-0.98) and `TestLogScaleAxis` (49-54,
  R2 = 0.99) appear on two of the four nights with nearly identical slope and R2 both times. Under
  the delta estimator they looked like part of the random heap set; under shape they do not.

## 2026-09-11: the first slopes run found nothing, and the branch split

### The run

10.8h, 1101 tests, pass 1 only, zero failures, **zero leaks reported**. Log archived as
`SkylineTester-20260910-net10-slopes-1101tests-0failures-0leaks.log`.

Nothing was near the gate either. Every heap axis with R2 >= 0.9 is 0-0.3 KB/run or negative; the
largest managed slope is `TestMSstatsTutorialLegacy` at 5.0 KB/run, but at R2 = 0.59 it is not
linear and would not be reported at any threshold worth trusting.

### Three findings from this branch were wrong, all the same way

Each was inferred from the archived nightly logs and each dissolved when measured directly:

| claimed | measured directly |
|---|---|
| `TestFilesTreeForm` leaks 3.33 KB/run managed (R2 = 0.93, 09-04) | 0.1 KB/run at R2 = 0.87 - the sample-buffer artifact below, not a leak |
| `TestInternationalFilenames` heap 86-89 KB/run at R2 = 0.97-0.98, two nights | **-79.8 KB/run at R2 = 0.08** |
| `TestLogScaleAxis` heap 49-54 KB/run at R2 = 0.99, two nights | **-0.7 KB/run at R2 = 0.02** |

**The archived logs are not a fit instrument for small-signal questions.** They print managed and
heap memory at 0.01 MB, i.e. 10.24 KB granularity, and the old early exit leaves series of 8-12
samples. A 4.4 KB/run leak rises ~31 KB across an 8-sample window - three quantisation steps, whose
R2 computes to 0.89 and reads as "borderline" when the true value is 1.00. Reconstruction
systematically understates small real leaks and overstates short noisy ones. **Reproduce in
isolation before adjudicating any report**; it takes minutes and it is the only thing that settled
any of these.

### Precision by axis, four nights - the waste is all on one axis

| axis | reports | real | precision |
|---|---|---|---|
| managed | 21 | 21 | **100%** |
| heap | 17 | 3 (all `TestGroupedStudies1Tutorial`) | **18%** |

The managed axis is why the existing check has earned trust: every one of its 21 reports was a real
leak. The 14 non-actionable heap reports - ~3.5 a night - are the measured waste, and the TODO
already records that five of six reproduced in isolation went strongly negative. Any future change
should be judged on whether it removes those 14, not on whether it catches more.

### Two false positives this branch created, and what they taught

`AgilentGCEIChromatogramTest` and `TestTargetResolver` were flagged as handle leaks. Both are
**bounded ramps**: over 50 iterations in isolation they climb exactly one handle per run for 18 runs
and then sit flat forever (91 -> 109, then 109 for 32 more; 50 -> 68, then 68 for 32 more).

They were false positives only because the estimator had been changed to fit the whole run. The
existing design does not have this failure mode, and that is not an accident:

- the window is **trailing**, so a ramp stops being visible once it flattens;
- `Min` across windows rejects the warm-up, since the early windows are the steep ones;
- eight samples is one whole window, which is why a clearly-clean test can stop after eight runs.

Fitting the entire run discards all three and costs 2.1x the runtime. The estimator now fits the
trailing window instead - the change originally specified, and the one the loop comment has claimed
all along - leaving everything around it alone.

### Coverage gap: 35 tests are never leak-checked

`TestGroupedStudiesTutorialDraft` carries `NoLeakTesting(EXCESSIVE_TIME)`, so it only ever runs in
pass 2. It exercises the same `LoadLayout` path that made `TestGroupedStudies1Tutorial` leak 2 MB/run,
and would never have shown it. Its entries in `LeakCheckIterationsOverrideByTestName` (4x iterations)
and `MutedTotalMemoryLeakTestNames` are **dead code** - both can only take effect in pass 1.

It is not alone. **35 tests carry `NoLeakTesting`, every one of them `EXCESSIVE_TIME`** - none because
leak-checking them is meaningless, all because they do not fit the window. Mean duration 23s, so one
pass over all 35 is 10.6 minutes and **leak-checking the whole excluded set at the 8-iteration
minimum costs ~1.4 hours**.

### A third nightly flavour, and the numbers that justify it

Brendan's proposal: split nightly into (1) normal, (2) perf, (3) leak detection, letting 1 and 2 run
pass 0 and then cycle pass 2 immediately, while some machines run pass 1 only.

| | |
|---|---|
| last night, 1101 tests, 20-iteration floor | 10.8 h |
| same set at the 8-minimum, trailing-window estimator | ~5.3 h (est., +-20%) |
| plus the 35 currently-excluded tests | **~6.7 h** |

So a leak-only flavour covers **more than the suite covers today**, including everything now excluded
for time, and still fits a 9-hour window. Flavour 1 gets back the ~4.4h pass 1 was consuming.

The under-appreciated benefit is comparability. Today pass 1 runs after pass 0 on a machine that then
runs pass 2, and memory measurement is load-sensitive - measured 2026-09-10, the same test read
13.9 KB/run heap under contention and 8.5 on a quiet machine. A machine doing only pass 1 has the
same load profile every night, which is the precondition for both stable thresholds and "consistent
detection".

Watch two things: one leak machine means one failure leaves no leak coverage that night, where today
it degrades gracefully; and `IsAbWiff2Safe` keys off `TestPass != LEAK_CHECK_PASS`, so on a leak-only
machine `.wiff2` is never read at all - fine while flavour 1 still runs pass 2, but it becomes a
cross-flavour dependency rather than a within-run one.

### The branch split

`Skyline/work/20260907_leak_detection_baseline` mixed proven fixes with unproven tooling. Split:

- **`Skyline/work/20260911_net10_leak_fixes`** (PR) - the DigitalRune GDI+ binary, the Koina
  `GrpcChannel` dispose, the wiff2 leak-pass exclusion, and the BOM removals. These fix leaks that
  show up in nightly testing.
- **`Skyline/work/20260911_leak_estimator`** - the estimator work, plus `27bccc4009` (heap growth
  reporting, `GcRootReporter` field names and `GcHeapHistogram`). Parked, not abandoned:
  `GcRootReporter` and per-heap attribution earned their place - per-heap attribution is what cut the
  GDI+ oracle from 25 iterations to 4 - and can be PR'd separately on their own evidence.
  `GcHeapHistogram` still has not closed a case unaided.

The original branch still holds the full history until the split is confirmed.

### The review caught a build break in the binary, and the layout that fixed it

`/code-review max` on the fixes branch found that the rebuilt `DigitalRune.Windows.Docking.dll` had
been retargeted from `.NETFramework,Version=v4.7.2` to `NETCoreApp,Version=v10.0` - verified from the
binaries' `TargetFrameworkAttribute` strings - while three net472 projects (`SeeMS`, `IDPicker`,
`IDPicker\Test`) still referenced that exact file by HintPath, and SeeMS is in the standard Windows
install target. The fix is `#if NETCOREAPP`, so it only exists in a net10 build, and a net10 build
cannot be referenced from net472: one binary cannot serve both.

So `pwiz_tools/Shared/Lib/DigitalRune/` now holds `net472/` (the untouched original, verified
byte-identical to the port branch by blob hash, with its `ja` and `zh-CHS` satellites and XML doc)
and `net10/` (the rebuilt one, with the same satellites and a copy of the XML). Every consumer
chooses: the seven Skyline projects and the pwiz-sharp SeeMS port take net10; SeeMS and IDPicker
stay on net472. A reference that has not been updated fails to resolve, on purpose, so the build
reports what has not been ported. The installer templates reference build output, not `Shared\Lib`,
and needed nothing.

Two things the move nearly cost, both caught by measuring rather than assuming:

- **The satellites.** The build resolves a HintPath reference's satellites relative to the HintPath
  directory. With the DLL moved and `ja/` left behind, `DigitalRune.Windows.Docking.resources.dll`
  silently stopped being deployed - missing satellites fall back to neutral English. Populating
  `net10/ja/` and rebuilding brought it back. (`zh-CHS` is not copied under either layout: .NET Core
  treats it as a deprecated alias for `zh-Hans`, so DigitalRune's Chinese strings are not deployed
  on net10 at all. Pre-existing; not addressed here.)
- **The XML doc.** The SDK-style project that built net10 has `GenerateDocumentationFile = false`,
  so the net10 build never produced one, and Skyline would have lost docking IntelliSense. The
  net472 XML is copied beside net10 for now; the proper fix is flipping that property in the
  developers repo so the next rebuild generates its own.

Also confirmed from the decompiled binary: the `Control.Region` conversion covers 8 of 14 sites.
The 6 that remain include `AutoHideStripBase.SetRegion`, on the layout path. This TODO's earlier
"none remain" was wrong. The measured test does not reach those paths; a full 1101-test pass 1
reported nothing.

Review findings deliberately not acted on, for follow-up:

- `KoinaTestUtil.FakeKoina.Dispose` still does `ShutdownAsync().Wait()` with no `Dispose`, and it IS
  exercised by three pass-1 tests; `CallWithClient`, where the fix went, has one caller that
  early-returns without a Koina server. An additional site, not a contradiction - needs measuring.
- `PwizFileInfoTest`'s comment says the empty-serial-number case "only exists in the .wiff2 file";
  the fallback mzML carries `CI231606PT`, so the assertion could have kept running. And the CI build
  check runs `pass1=on pass2=off`, so "coverage stays in pass 2" does not hold for that job.
- Six findings on the uncommitted `ReaderSciexTests.cs`, including that it will not compile without
  vendor licenses (a Linux CI break) - relevant when those tests find a home.

## Method notes

- **A real leak is near-perfectly linear.** R² ≈ 1.00 with a large t-statistic separates a leak from
  a filling cache from chance alignment. The 24-iteration gate cannot. `ai/.tmp/leak-tools/Shape-Leaks.ps1`
  does this and classifies `UNBOUNDED` / `DECAYING` / `BOUNDED` / `NOISE`.
- **Verify the staged binary before trusting any measurement.** Stale binaries produced four wrong
  conclusions in one session. `TestRunner.exe` run directly out of `bin\staging\Release` does not pick
  up a build — only `Run-Tests.ps1` stages.
- **Never run two test processes at once** — they contend and corrupt each other's memory numbers.
  Now enforced: `Run-Tests.ps1` refuses to start a memory-measuring run (`-Quality`, `-Pass 1`,
  `-Loop > 1`, `-MemoryProfile`) while any `TestRunner` or `SkylineTester` is alive **anywhere on the
  machine**, exiting 2 before it stages anything. `-AllowConcurrent` overrides; a single functional
  run only warns, since there contention costs wall-clock rather than correctness.

  **The check is deliberately machine-wide, unlike the one in `Build-Skyline.ps1`**, and the
  difference is the lesson. A build protects its own output files from being locked, so scoping to
  its checkout is right and a run out of `D:\Nightly` is correctly ignored. A test run protects its
  *measurements*, and memory, heap and handle counts belong to the machine, not a directory.

  Learned by doing it: on 2026-09-10 a slope sweep was launched against a running SkylineNightly
  (`D:\Nightly\SkylineTesterForNightly_integration`) and ran 28 minutes alongside it. No binaries
  were harmed — separate checkouts — but the numbers were. `AaantivirusTestExclusion` read
  **13.9 KB/run heap at R² = 0.78** under contention and **8.5 at R² = 0.52** on the quiet relaunch
  minutes later: a false rising signal manufactured entirely by the other run, on the very axis this
  branch exists to make trustworthy. The build guard had looked at the checkout, found it idle, and
  its silence was read as "the machine is idle".
