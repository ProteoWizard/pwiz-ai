# TODO-20261013_testddasearch_skyline_dev6.md

## Branch Information
- **Branch**: none yet (investigation; branch from master if a test/code fix results)
- **Module**: `skyline`
- **Created**: 2026-10-13 (SKYLINE-DEV6, checkout `C:\proj\pwiz`)
- **Machine**: SKYLINE-DEV6 (Dell Precision 3680, 88DXT64), i9-14900 CPU #3 (replaced 2026-10-07),
  BIOS 1.29.0 / microcode 0x133, Turbo + SpeedStep on (~5.5 GHz, 24C/32T). Case history:
  `M:\home\brendanx\docs\Machines\SKYLINE-DEV6\cpu-health-analysis.md`
- **Status**: not started - handed off 2026-10-13

## Question

Is TestDdaSearch's intermittent failure on SKYLINE-DEV6 a speed/race issue in the test or MSAmanda search
that this (now fastest-in-fleet) machine exposes - like the MCP connector race fixed in PR #4824 - or a
sign that CPU #3 computes wrong, as CPU #2 did in its last week?

## What the failure is

- TestDdaSearch = `DdaSearchTest.TestDdaSearch`, search engine **MSAmanda** (3.0.22.864, unchanged),
  `ExpectedResultsFinal = (79 proteins, 192 peptides, 241 precursors, 723 transitions, 93 unmapped)`.
- Every failure: `emptyProteinsDlg.NewTargetsFinalSync` count off by 1-2 at DdaSearchTest.cs:1471-1473
  (79 vs 77/78; 192 vs 190/193; 241 vs 239). Languages vary (en, fr, ja, zh) - not language-specific.
- The commented-out block just above (`NewTargetsAll`) says "reenable these checks for 32 bit once
  intermittent failures are debugged" - these counts have a history of flakiness.

## Evidence so far (per execution, local logs D:\Nightly\Logs, one line per language execution)

| Period | TestDdaSearch failures |
|---|---|
| 2026-01-09 to 06-29, CPU #2 healthy | 0 / ~2,790 |
| 2026-07-06 to 09-24, CPU #2 logging WHEA 19 | 0 / ~588 |
| 2026-09-25 to 10-02, CPU #2 crashing, turbo on | 3 / ~53 (79->77, 192->190) |
| 2026-10-02 to 10-07, CPU #2, turbo OFF | 0 / ~46 |
| 2026-10-07 to 10-13, CPU #3, turbo on | 7 / ~84 (~8%) |

- skyline.ms: no other machine failed TestDdaSearch in October (Nightly x64, Integration). Jun 30-Jul 5
  failures on 6 machines were a different, fleet-wide ThreadExceptionDialog bug - ignore.
- Twin 89DXT64 (BRENDANX-UW25, same i9-14900) has no October runs to compare. BRENDANX-UW8 (i9-14900K,
  32 threads) passes it.
- No code or MSAmanda change explains the Oct 10-11 clean stretch (29 straight passes) or the return.
- CPU #3 otherwise clean: no WHEA 19, no crash, no reboot since 2026-10-07 15:36, ~143k tests.

## Plan
- [ ] Measure the rate in a soak on this machine (Release, like nightly), time-to-failure not per-hour
- [ ] On a failure, keep the MSAmanda output and Skyline's import result; diff a failing vs a passing
  execution: is MSAmanda's own output different run to run (search nondeterminism or bad arithmetic), or
  is it identical and the difference arises later in Skyline (protein association / threading)?
- [ ] If MSAmanda output varies: does it vary with thread count / CPU affinity, or with Turbo off?
  Deterministic variation tied to threading = software; random variation only at turbo = hardware suspect
- [ ] Compare on another machine (UW25 twin ideally) with the same soak
- [ ] Conclude; record in this TODO and in cpu-health-analysis.md (and the Dell thread only if hardware)

## Progress Log

### 2026-10-13 - Handed off
Evidence gathered from local run logs and skyline.ms (table above); no soak run yet.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20261013_testddasearch_skyline_dev6.md` before starting work.
