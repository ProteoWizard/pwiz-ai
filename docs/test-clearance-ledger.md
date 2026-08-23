# Test clearance ledger

What has actually been measured, and what the measurement was worth. Method and the
meaning of the columns: `ai/docs/test-flakiness-method.md`.

A row here is a claim someone can check. It is not "this test passed" - it is "this test
ran N times in a configuration capable of detecting classes X, and did not fail", which is
a much narrower and much more useful statement.

## Columns

| column | meaning |
|---|---|
| test | test method name |
| date | when measured |
| sha | git sha of what was tested; the claim expires when this code changes |
| execs | executions, NOT runs |
| langs | languages covered |
| width | parallel workers (1 = serial) |
| mode | harness mode - decides what contention is even possible |
| passes/proc | executions per process; 1 cannot detect a class-1 state leak |
| classes | which flake classes this configuration could have caught |
| verdict | what the number supports, by rule of three (0 failures in N clears 3/N) |

## Entries

| test | date | sha | execs | langs | width | mode | passes/proc | classes | verdict |
|---|---|---|---|---|---|---|---|---|---|
| TestWatersConnectExportMethodDlg | 2026-08-23 | 2e5f957 | 100 | en,fr,ja,tr,zh | 8 | server | many | 1, 3 | **cleared < 3%**; was 45%. Also 5/5 consecutive in one process, the exact failing condition |
| PeakAreaDotpGraphTest | 2026-08-23 | 2e5f957 | see note | en,fr,ja,tr,zh | 8 | server | many | 1, 3 | soak in progress; before-rate 1/460 |
| TestDdaSearchDependencyErrors | 2026-08-22 | 5aa3ae4 | 100 | en,fr,ja,tr,zh | 4 | server | many | 1, 3 | **NOT CLEARED** - see below |

## Why TestDdaSearchDependencyErrors is not cleared despite 0/100

This row is the reason the ledger records configuration at all.

The test failed 27 times in 45 overnight executions (60%). A 100-execution soak of it alone
returned zero failures. That number does not clear it, because its failure is class 2 -
contention over the crux tools directory - and TestRunner's parallel queue reserves those
directories (`QueuedTestInfo.RequiredToolsDirectories`). In `parallelmode=server` the
contention being hunted **cannot occur**. The soak measured a configuration in which the
failure is impossible.

Recorded as not cleared until it is measured by an instrument that can reproduce the
neighbour holding the file.

## Rule of three

Zero failures in N executions gives 95% confidence the true rate is below `3/N`.

| execs, 0 failures | clears a rate above |
|---|---|
| 100 | 3% |
| 300 | 1% |
| 1,000 | 0.3% |
| 3,000 | 0.1% |

For scale: the 2026-08-21 overnight suite aggregate was 46 failures in 48,272 executions,
about 0.095%.

## Re-clear when

* the test changes
* code under the test changes
* the harness changes in a way that alters what contention is possible - a clearance is
  against a configuration, not against the universe
