# TODO-20261013_testddasearch_skyline_dev6.md

## Branch Information
- **Branch**: `Skyline/work/20261013_msamanda_lost_hits` (MSAmanda priority mitigation)
- **Module**: `skyline`
- **Created**: 2026-10-13 (SKYLINE-DEV6, checkout `C:\proj\pwiz`)
- **Machine**: SKYLINE-DEV6 (Dell Precision 3680, 88DXT64), i9-14900 CPU #3 (replaced 2026-10-07),
  BIOS 1.29.0 / microcode 0x133, Turbo + SpeedStep on (~5.5 GHz, 24C/32T). Case history:
  `M:\home\brendanx\docs\Machines\SKYLINE-DEV6\cpu-health-analysis.md`
- **Status**: root cause found (MSAmanda lazy-init race); mitigation soaking

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

### 2026-10-13 (afternoon) - Reproduced locally; MSAmanda drops hits under some scheduling

Nightly stopped for the session. Release build of master `daeed6d5f9`, plus uncommitted diagnostic code in
`DdaSearchTest.cs` (`SoakCaptureSearchOutput` / `SoakCaptureFinalDocument`, marked "not for commit") that
copies each execution's `.mzid.gz`, `_pin.tsv`, search log and final peptide list to
`D:\test\TestDdaSearchSoak\<time>_<lang>\`.

**Test soak** (Run-Tests, Release, en): failed on execution 1 (79,190,236,708,92) and again on execution
8 (78,191,238,714,93) - 2/8.
- The difference is already in MSAmanda's own output: MSAmanda's own log line "Scored N peptide hits"
  is 158/46 for `_02` and 121/34 for `_03` when good; failures logged 154/46 (`_02`) and 120/33 (`_03`).
  The `_pin.tsv` (Percolator input) loses whole PSMs - including strong ones (VSPDVQ... score 266,
  IVDDLSSL... 407) - and every row that remains is identical to the good run. Not changed scores: missing hits.

**Standalone MSAmanda loop** (`ai/.tmp/sessions/20261013-ddasearch/amanda-loop.ps1`, same settings,
file `_02`, results `D:\test\TestDdaSearchSoak\_standalone\*.log`; good = 205 pin rows / 158 hits):

| Condition | Lossy / runs |
|---|---|
| Normal priority, all CPUs | 0 / 190 |
| BelowNormal (what Skyline's ProcessRunner uses), all CPUs | 6 / 190 (~3%); worst 9 hits of 158 |
| BelowNormal, 1 CPU | 0 / 40 |
| BelowNormal, P-cores only (0xFFFF) | 1 / 190 |
| BelowNormal, E-cores only (0xFFFF0000) | 0 / 190 |

Every lossy pin file is a strict subset of the good one. Scheduling priority changes the results:
a thread-safety bug in MSAmanda 3.0.22.864 (lost results). Preemption at BelowNormal is the main
trigger; core pinning reduces it but P-cores-only still lost hits once, so it is NOT specific to the
P/E mix. A CPU computing wrong values would not
depend on priority and would not produce a strict subset. The 79->46 nightly failure fits the
worst-case standalone run (9 hits survive). No WHEA 19 since 2026-10-07 15:00.

### 2026-10-13 (evening) - Root cause found in decompiled MSAmanda; confirmed by experiment

No editable MSAmanda source exists: upstream `github.com/hgb-bin-proteomics/MSAmanda` is release
binaries only; `pwiz_tools/Shared/Lib/MSAmanda/*.dll` are binaries (#1044, viikiid, 2020). Extracted the
single-file bundle with `sfextract` and decompiled with `ilspycmd` 11.1 to
`D:\test\TestDdaSearchSoak\_decompile\src\` (tools under `C:\c\proj\ai\.tmp\...\tools` - wrong path,
user to delete `C:\c`).

**Root cause** - `FHOOE_IMP.MSAmanda.Utils`, `MSAmanda.Utils.Peptide` constructor (decompiled
`Peptide.cs:190-197`): unsynchronized lazy init of `private static AminoAcid[] _aminoAcids`, and the
EMPTY array is published before it is filled:
```
if (_aminoAcids == null) { _aminoAcids = new AminoAcid[255]; foreach (...) _aminoAcids[code] = value; }
```
Another thread constructing a Peptide in that window sees non-null, skips init, and `CalculateIons`
hits `if (_aminoAcids[b] == null) return false;` (`Peptide.cs:471`) -> empty ion list -> score never
< 1.0 -> candidate silently dropped in `SpectrumProcessor2.CalculateScoreForPeptide`. No exception,
every other result exact - the strict-subset signature. The window is process startup; preempting the
filling thread (BelowNormal) widens it while ~31 others score. Upstream fix: fill a local array and
assign it last (or a static readonly initializer).

**Proof** - harness `ai/.tmp/sessions/20261013-ddasearch/harness` runs MSAmanda's own entry point
in-process from the extracted DLLs (output byte-identical to MSAmanda.exe), optionally pre-filling
`_aminoAcids` by reflection. BelowNormal, unpinned, 200 runs each
(`D:\test\TestDdaSearchSoak\_standalone\h_control.log`, `h_preinit.log`):
control 8/200 lossy (worst 3 of 158 hits), preinit 0/200 (p ~ 3e-4).

**Conclusion**: software race exposed by this machine, not CPU #3.

**Priority mitigation tried and dropped**: launching MSAmanda at Normal priority (verified in effect) still
failed TestDdaSearch 1 of 13 - inside the test, Skyline's own threads keep the CPU busy, so the idle-machine
0/190 does not carry over. Reverted.

**Reported upstream**: https://github.com/hgb-bin-proteomics/MSAmanda/issues/9 (2026-10-13).

**Test relaxed** (branch `Skyline/work/20261013_msamanda_lost_hits`): `DdaTestSettings.FinalCountTolerance`
(default 0 = exact); TestDdaSearch sets 0.1 with a TODO to remove once MSAmanda ships a fix for issue #9.
(Superseded below by the search retry.) 5% was too tight: relaxed soak (`ai/.tmp/sessions/20261013-ddasearch/relaxed-soak.log`) had 7 of 44
executions off, one by 8.3% (precursors 241->221), which failed. 10% covers every ordinary loss seen; the
catastrophic 79->46 kind (~1 in 84 nightly executions) still fails. A tolerated
mismatch prints "Final count N differs from expected M" so its rate stays visible.

**10% soak found a Skyline hang**: 1 of 58 executions timed out in `MSAmandaSearchWrapper.DiagnosePercolator`
(runs only when the mzid has no Percolator q-values - here a catastrophic MSAmanda loss). It read stdout to
the end, then stderr; `percolator.exe --help` writes 0 bytes to stdout and ~25 KB to stderr, so it
deadlocks EVERY time it runs (user-facing: the search page never finishes). Fixed with
`ProcessStreamReader` (drains both streams). TestDdaSearch now calls `DiagnosePercolator` after the first
search (MSAmanda only); verified red on the old code (percolator alive 47 s, deadlocked), green on the fix.

**Tolerance replaced by search retry** (user preference): `DdaTestSettings.ExpectedScoredHits` =
{158+46, 121+34} (MSAmanda's "Scored N peptide hits and M decoy" per file). After the final search,
`RetrySearchWhileScoredHitsDiffer` repeats it (Back to settings, Next) up to 3 attempts while it failed or
the scored counts differ, printing "repeating search" each time. Exact final-count assertions restored.

**Verified** (Release, SKYLINE-DEV6): TestDdaSearch 40 loops x en/fr/ja/zh = 160 executions, 0 failures
with exact counts, 6 repeats (`ai/.tmp/sessions/20261013-ddasearch/retry-soak.log`) - one recovered a
catastrophic search (30 of 204 hits scored). Other DDA tests (Comet, CometAutoTolerance, MsgfPlus, Tide,
MsFragger, SettingsPreset, DependencyErrors) pass; CodeInspection passes. (A first soak attempt hung: the
restored fix had an older mtime than the build output, so the incremental build ran the old code - a stack
dump showed `ReadToEnd`. Touching the file fixed it.)

**Follow-up**: when a fixed MSAmanda release appears, update the download pin, remove the workaround
(now `ExpectedScoredHits` and the retry) from TestDdaSearch, and soak to confirm exact counts.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20261013_testddasearch_skyline_dev6.md` before starting work.
