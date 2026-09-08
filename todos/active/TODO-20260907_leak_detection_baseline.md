# TODO: Memory leak detection baseline for the .NET 10 nightly

## Branch Information

- **Branch**: `Skyline/work/20260907_leak_detection_baseline` (off `Skyline/work/20260612_net8_port`)
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
- **`TestGroupedStudies1Tutorial`** (~1.9 MB/run native).

## Method notes

- **A real leak is near-perfectly linear.** R² ≈ 1.00 with a large t-statistic separates a leak from
  a filling cache from chance alignment. The 24-iteration gate cannot. `ai/.tmp/leak-tools/Shape-Leaks.ps1`
  does this and classifies `UNBOUNDED` / `DECAYING` / `BOUNDED` / `NOISE`.
- **Verify the staged binary before trusting any measurement.** Stale binaries produced four wrong
  conclusions in one session. `TestRunner.exe` run directly out of `bin\staging\Release` does not pick
  up a build — only `Run-Tests.ps1` stages.
- **Never run two test processes at once** — they contend and corrupt each other's memory numbers.
