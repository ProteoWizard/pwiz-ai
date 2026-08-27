# net8 workers leak managed memory across cycles; net472 plateaus

## Branch Information
- **Checkout**: `C:\proj\pwiz-work1` (net8 line), logs in `D:\test\nightly-logs`
- **Branch**: not created yet
- **Base**: `Skyline/work/20260818_commonutil_winforms_split` (PR #4587)
- **Created**: 2026-08-27
- **Status**: Measured, not diagnosed
- **Module**: `skyline`
- **Related**: `TODO-20260826_nightly_flake_cleanup.md`, PR #4587, PR #4619

## What was measured

Two full-suite overnight runs, same machine, same 657 tests x 5 languages, 8 parallel
workers. Memory columns are `Managed / Committed / Total` MB per test, averaged per cycle
(a cycle = 3,285 results = one pass through the list).

Total MB growth per cycle:

    net472:  +82  +27  +17  +8  +5  +5  +4  +2  +3  +5  +3  +8     <- decays to noise
    net8:    +76  +26  +26 +21 +20 +20 +18 +19 +17                 <- flat, does not decay

net472 plateaus after the caches fill. net8 holds a near-constant ~19 MB/cycle from
cycle 4 onward - a straight line, not a curve flattening out.

The managed column is the sharper signal:

| | cycle 4 | last cycle | rate |
|---|---|---|---|
| net472 managed | 62.9 MB | 64.0 MB (cycle 13) | **+0.12 MB/cycle** |
| net8 managed | 101.7 MB | 136.4 MB (cycle 10) | **+5.8 MB/cycle** |

About 48x the managed growth rate, still climbing at cycle 10 with no sign of levelling.
net8 passed net472's end-of-night total (398.8 MB at cycle 10 vs 386.9 at cycle 13) with
three cycles still to run.

## Why the leak check did not catch it

19 MB per cycle spread over 3,285 test executions is **~6 KB per test** - far below any
per-test threshold. It is invisible at the granularity the check runs at and only appears
as a slope across cycles. No single test looks guilty, which is exactly why it survived.

## Why it matters

Unbounded linear growth in MANAGED memory is a retained object graph, not a cache reaching
capacity. Over a 9-hour run it is tolerable (~456 MB projected by cycle 13, against a
13 GB container limit). Over the longer runs a nightly does, and on the Integration branch
where the port is headed, it is not something to leave unexplained.

It is a genuine .NET 8 regression: master does not have it.

## Next step

Point pass-1 leak detection at it deliberately - that pass repeats each test and attributes
retained memory, which is the tool for turning "+5.8 MB/cycle somewhere" into a named
holder:

    pwsh -File ./ai/scripts/Skyline/Run-Tests.ps1 -Quality -Configuration Release

Do NOT expect a single test to own it. The shape (flat per-cycle, tiny per-test) suggests
something retained once per test class or per language switch rather than per test.
Candidates worth eliminating first, since all three are new on the net8 line:
- the `Wiff2LoadContext` side-by-side AssemblyLoadContext (never unloaded)
- the staged portable runtime being loaded per worker
- WinForms/SystemEvents hook changes made during the port

## Not blocking

The 9-hour throughput result is good (~46,000 results vs net472's 43,794, about +5%) and
memory stays far from the container limit. This belongs in the port's follow-up work, not
in the merge gate for #4587.
