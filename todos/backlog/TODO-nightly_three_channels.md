# TODO-nightly_three_channels.md - Standard, Leak Checking and Perf as separate nightly channels

## Branch Information
- **Branch**: (not started - `Skyline/work/YYYYMMDD_nightly_three_channels` when picked up)
- **Module**: `skyline`
- **Base**: `master` for SkylineNightly (the shim auto-updates every machine from master);
  TestRunner and SkylineTester changes on master, cherry-picked to `Skyline/skyline_26_1`,
  merged into `Skyline/work/20260612_net8_port` (each branch's nightly runs that branch's
  SkylineTester)
- **Created**: 2026-09-17 (design), by Brendan and Claude
- **Status**: Backlog - design settled except the open points at the bottom
- **GitHub Issue**: (none yet)
- **PR**: (pending)

## Objective

Split the nightly into three run types, each chosen per machine, so that no machine has to do
everything in one night:

| Type | What it runs | Duration |
|---|---|---|
| **Standard** | pass 0, then pass 2 cycling; no pass 1 | 9 h |
| **Leak Checking** | pass 1 only, every test including the `NoLeakTesting` set, sweeps repeated until the cutoff | 12 h (or 9) |
| **Perf** | TestPerf first, then the suite once in four languages, then TestPerf again in further languages until the cutoff; no pass 0, no pass 1 | 12 h |

Every machine may schedule **at most one 9-hour run plus one 12-hour (or 9-hour) run per day**
- never two 12-hour runs. The ~3 h left over is deliberate: configuration changes, updates,
a human at the keyboard. Brendan enforces this by hand today; the new UI enforces it.

## Why

1. **Most machines never finish pass 1.** Only the 4-5 newest get through leak checking, and
   leak checking was already split across standard and perf runs (perf machines leak-check only
   the 30 `NoLeakTesting` tests, by inverting the attribute) to get the slower machines through.
   Even on the fastest machine (BRENDANX-UW8, 9/16) pass 1 took 5 h 18 m of the 9 h and pass 2
   then covered only 911 of 1,111 tests in four languages.
2. **Leak-only runs enable the leak-detection improvements** recorded in
   `TODO-20260907_leak_detection_baseline.md`: a higher iteration floor, the trailing-window
   estimator on the parked branch, the 35 (now 33) `NoLeakTesting` tests that are never
   leak-checked (~1.4 h at the 8-iteration minimum), and a machine whose load profile is the
   same every night - the precondition for stable thresholds.
3. **Leak-only can be 12 h and run on more machines** - part of what limits perf machines is
   disk, memory and speed for the perf tests that follow pass 1; a leak-only machine needs none
   of that.
4. **Perf machines stop repeating the standard run.** Today a perf night is standard plus perf
   tests once in one language; the 12 h should concentrate on the perf tests.

## How it works today (measured)

- **SkylineNightly** (`pwiz_tools/Skyline/SkylineNightly`): the form has two combos
  (`mode1`, then `mode2`) over one enum `RunMode { trunk, perf, release, stress, integration,
  release_perf, integration_perf }` that conflates branch and type; the scheduled task's
  argument is `run <mode1> [<mode2>]`; `PerformTests` skips a run that would overrun the next
  scheduled start. Durations: 9 h, perf 12 h, stress 168 h. Posting folder by mode; the log
  phrase `# Perf tests` is what makes the parser choose the perf folder.
- **SkylineTester Nightly tab** (`TabNightly.cs:388-403`): `quality=on loop=-1 pass0=on
  pass1=on [perftests=on] runsmallmoleculeversions=on retrydatadownloads=on`. Stress:
  `pass0=off pass1=off repeat=100 random=on`. Perf: `pass0=off`.
- **TestRunner** (`Program.cs`): on a nightly with `perftests=on` it *inverts* `NoLeakTesting`
  (`:2298-2310`) so perf machines leak-check only the excluded tests; pass 2 front-loads the
  `NoLeakTesting` tests (`:2675-2681`); perf tests run once, in one language chosen by
  `DayOfYear % languages` (`:2699-2701`); `IsPerfTest` is namespace `TestPerf` (`RunTests.cs:65`);
  pass 1 repeats forever when `pass2=off` and `loop<=0` (`:2531-2533`).
- **A 12 h perf night on BRENDANX-UW7** (master, run #85511, 2026-09-17, 8,850 runs):
  pass 1 (30 inverted tests) 2 h 15 m; **TestPerf once in one language, 74 tests, 2 h 50 m**
  (`AllVsMz5OptimzeCeImportPerformanceTests` 30 min, `TestDiaQeDiaUmpireTutorialExtra` 20 min,
  `TestPeakPerf` 16 min); the other 1,110 tests x 4 languages ~4 h 10 m (~1 h per language:
  TestFunctional 0.46 h, TestTutorial 0.15 h, TestData 0.04 h, Test/CommonTest/TestConnected
  0.02 h of test time); a third pass of 986 tests until the cutoff. BSPRATT-UW2 gets through
  about half as many runs in 12 h - figure 2x for a mid-range machine.
- **A 9 h standard night on BRENDANX-UW8** (port branch, 2026-09-16, 14,530 runs): pass 0
  47 min (1,111 tests), pass 1 5 h 18 m (9,788 runs), pass 2 2 h 50 m (911 tests x 4).

## Design

### SkylineNightly (master)

- **Model**: `RunSpec(Branch, RunType)` replaces `RunMode` for scheduling.
  `Branch { master, release, integration }`, `RunType { standard, leak, perf, stress }`
  (stress kept as a type only if Brendan wants it in the UI - open point 1). `parse` and
  `post` stay commands.
- **Form**: two rows
  ```
  Tests:  Branch [ Master | Release | Integration v ]   Type [ Standard | Leak Checking | Perf v ]
  Then:   Branch [ Master | Release | Integration v ]   Type [ (none) | Standard | Leak Checking | Perf v ]
  ```
  The end-time display uses the type's duration (standard 9, leak 12, perf 12). **The form
  refuses two 12-hour types** (leak + perf, perf + perf, leak + leak): 24 h leaves no margin
  and the existing overrun check would skip the second run every night anyway. Allowed:
  9 + 12, 9 + 9, or one run. This is the rule Brendan enforces by hand today.
- **Task argument**: `run master/standard release/leak`. Legacy names keep parsing so the
  auto-updated exe changes nothing until a machine is reconfigured: `trunk` -> master/standard,
  `perf` -> master/perf, `release` -> release/standard, `release_perf` -> release/perf,
  `integration` -> integration/standard, `integration_perf` -> integration/perf, `stress` ->
  master/stress. `Settings.Default.mode1/mode2` migrate the same way.
- **Per run**: SkylineTester zip by branch (unchanged); `.skytr` gains `nightlyRunType`
  (`standard | leak | perf | stress`) and keeps writing `nightlyRunPerfTests` and
  `nightlyRepeat` for an older SkylineTester; `TargetDuration` by type.
- **Posting**: folder by (branch, type). Three new folders on skyline.ms for leak runs
  (`Nightly x64 Leak Detection`, `Release Branch Leak Detection`, `Integration Leak Detection` -
  open point 4); the parser recognises `# Leak checking only` the way it recognises
  `# Perf tests`.

### SkylineTester Nightly tab (each branch)

- Reads `nightlyRunType`; falls back to `nightlyRunPerfTests` / `nightlyRepeat > 1` for an old
  `.skytr`. UI: a Run type combo replacing the perf checkbox.
- TestRunner line per type (common tail unchanged: `offscreen=on quality=on
  runsmallmoleculeversions=on retrydatadownloads=on dmpdir=...`):
  - **standard**: `pass0=on pass1=off pass2=on loop=-1`
  - **leak**: `pass0=off pass1=on pass2=off loop=-1 leakall=on` - pass 1 sweeps repeat until
    the cutoff (already TestRunner's behaviour for `pass2=off loop<=0`), so a 12 h night is
    two or three independent measurements of every test
  - **perf**: `pass0=off pass1=off pass2=on loop=-1 perftests=on perffirst=on`
  - **stress**: `pass0=off pass1=off repeat=100 random=on` (unchanged)

### TestRunner (each branch)

- `leakall=on`: pass 1 ignores `NoLeakTesting`. Remove the perf-run inversion of
  `NoLeakTesting` and the pass-2 front-loading - both existed only because one run did all
  three jobs.
- `perffirst=on` (nightly perf order): TestPerf once in the rotating language, then the suite
  once in every language (TestTutorial, then TestFunctional, then the cheap unit projects),
  then TestPerf again in the next language, and again, until the cutoff. The remaining time
  goes to perf languages, not a second suite cycle, because standard machines already deliver
  suite cycles. A slow machine degrades by losing the extra perf languages, not the suite.
- **Per-machine language rotation** for perf tests: `(DayOfYear + machine offset) %
  languages`, offset from a stable hash of the machine name, so three perf machines cover
  three languages the same night instead of all picking the same one.
- Log `# Leak checking only` in nightly mode when pass 1 is on and pass 2 off.
- The iteration floor and the trailing-window estimator stay as shipped for phase 1; the
  parked `Skyline/work/20260911_leak_estimator` branch is phase 2 and can now be scored
  against a leak-only machine's clean signal.

### Budget check

| Machine class | Standard (9 h) | Leak (12 h) | Perf (12 h) |
|---|---|---|---|
| fast (UW7/UW8) | pass 0 0.8 h + ~2 full pass-2 cycles | ~2 sweeps at today's floor, or 1 at a 20-iteration floor | perf x1 lang 2.8 h + suite x4 4.2 h + perf x1-2 more languages |
| 2x slower | pass 0 1.6 h + ~1 cycle | ~1 sweep | perf x1 lang ~5.6 h + most of the suite x4 |

Perf tests in all four languages on one machine is 11.2 h on the fastest machine and is not a
nightly definition; language coverage comes from machine count and the per-machine rotation.

## Rollout (the shim auto-update makes the order matter)

1. TestRunner + SkylineTester on master; cherry-pick to `Skyline/skyline_26_1`; merge into the
   port branch. An old `.skytr` still means today's run, so nothing changes yet.
2. SkylineNightly on master with the new form and the legacy argument mapping. Every machine
   picks it up the next night and still runs exactly what it ran.
3. Create the three folders; teach the report side (`ai/docs/nightly-tests.md`, the labkey MCP
   `current_target` / `get_daily_test_summary` / folder lists, `/pw-nightly`,
   `/pw-daily-research`); write the machine table in the wiki (`skyline-wiki` skill).
4. Reconfigure the leak machines first (open the form, save `<branch> / Leak Checking`);
   verify a night of posts in the new folders. Then the perf machines, then the standard
   ones. No night is without leak coverage.

## Tasks

- [ ] TestRunner: `leakall=on`, `perffirst=on` with the perf-first / suite / perf-languages
      order and the per-machine rotation, `# Leak checking only`, remove the inversion and the
      pass-2 front-loading
- [ ] SkylineTester: `nightlyRunType` in `.skytr` and the Nightly tab, the four arg sets, old
      `.skytr` fallback
- [ ] SkylineNightly: `RunSpec`, the two-row form with the 9+12 rule, legacy argument and
      settings migration, durations, posting folders, parser key phrase
- [ ] skyline.ms: three leak folders (needs project admin)
- [ ] Reporting: docs, labkey MCP, `/pw-nightly`, `/pw-daily-research`; the machine table on the wiki
- [ ] Rollout steps 1-4 above, one branch and one machine class at a time

## Open points

1. **Stress** in the Type combo, or legacy-argument only?
2. **Leak machines per branch**: one, or two for resilience?
3. **Leak duration**: 12 h everywhere, or 9 h on machines that also run a 12 h perf?
   (9 + 12 is allowed; 12 + 12 is not.)
4. **Folder names** for the leak channel.
5. **"Perf tests only"** as a per-machine option (perf type minus the suite pass) for the
   slowest perf machines - a checkbox on the same design, if wanted.

## Related

- `TODO-20260907_leak_detection_baseline.md` - the leak-detection work this enables (2026-09-11
  "A third nightly flavour", 2026-09-16/17 the quiet sample point and the first clean nightlies)
- `TODO-20260913_net8_nightly_reporting.md` - Integration nightly reporting
- PR #4677 (`GCCollectionMode.Aggressive` before each sample), which is what makes the
  private-bytes axis worth a dedicated leak machine
