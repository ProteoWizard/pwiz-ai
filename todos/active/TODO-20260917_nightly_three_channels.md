# TODO-20260917_nightly_three_channels.md - Standard, Leak Checking and Perf as separate nightly channels

## Branch Information
- **Branch**: `Skyline/work/20260918_skylinenightly_run_types` (SkylineNightly, off master) and
  `Skyline/work/20260918_run_types_net8_port` (SkylineTester, TestRunner, tests, off the port
  branch; work in the `C:\proj\pwiz-work1` checkout). The combined
  `Skyline/work/20260917_nightly_three_channels` (#4687) was split on 2026-09-18 and deleted;
  GitHub keeps it restorable from the closed PR.
- **Module**: `skyline`
- **Base**: `master` for SkylineNightly (the shim auto-updates every machine from master, and
  SkylineNightly drives every branch's SkylineTester, old or new); `Skyline/work/20260612_net8_port`
  for everything else - the run types are proven there, on machines Brendan controls, and reach
  master when the port merges. The release branch never changes.
- **Created**: 2026-09-17 (design), by Brendan and Claude
- **Status**: In Progress - design settled except the open points at the bottom
- **GitHub Issue**: (none yet)
- **PR**: [#4688](https://github.com/ProteoWizard/pwiz/pull/4688) SkylineNightly -> master,
  merged 2026-09-19 as `7037da93c6`; [#4689](https://github.com/ProteoWizard/pwiz/pull/4689)
  SkylineTester + TestRunner + tests -> port branch, merged 2026-09-19 as `1a95f04634`; the
  gate [#4684](https://github.com/ProteoWizard/pwiz/pull/4684) merged 2026-09-18 as
  `f6e34de4fa`; [#4687](https://github.com/ProteoWizard/pwiz/pull/4687) closed, superseded by
  the split. Both work branches deleted.

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

## Gradual adoption: `SKYLINE_NIGHTLY_BRANCH` (2026-09-18)

Merging this to master would put the new SkylineNightly on every machine the next night through
the shim's auto-update - too abrupt. PR #4684 (`Skyline/work/20260918_nightly_branch_env_var`, off
master, tiny, a no-op when unset) adds the gate:

- `SKYLINE_NIGHTLY_BRANCH`, read in the shared `TeamCityNightlyAuth`: a bt209 branch locator
  (`pull/NNNN`) that stands in for master when the shim downloads `SkylineNightly.zip` and when
  SkylineNightly downloads its master-run `SkylineTester.zip`. Verified: bt209 serves a PR
  build's artifacts for `?branch=pull%2F4683`; bt209 is "master and PRs" only, so a `Skyline/work`
  branch needs a PR to be reachable. Release and Integration runs use their own configs (unaffected;
  #4619 has no bt209 builds, so the port branch is reached only by merging this work into it).
- The shim ignores its arguments: update SkylineNightly and itself, then `SkylineNightly run`.
  `run` with no modes runs what the saved settings say; the form schedules the task as `run`.
  Caveat for the night #4684 lands: every machine then runs its *settings*, not its task
  argument; they agree wherever the form wrote both - the daily report shows any machine that
  changed folder.

This branch, on top: the form stores its runs in new settings `Run1`/`Run2` and never writes the
pre-split `mode1`/`mode2` (read only as a fallback), so a machine put back on master's
SkylineNightly (which would crash on `master/leak` in `mode1`) still opens its form and runs
what it ran. Flag a machine: set the variable to this PR's `pull/NNNN`, let the next scheduled run
update it, open the new form, save the run. Unflag: unset the variable; next night it is back on
master's build and its old runs.

**What the gate reaches** (traced 2026-09-18 after Brendan asked): the `.zip`s carry only
SkylineNightly and SkylineTester; TestRunner and the tests are always built on the machine from
the branch SkylineTester clones. So for a **master run** on a flagged machine everything comes
from the PR - shim and SkylineNightly from the PR's `SkylineNightly.zip`, SkylineTester from its
`SkylineTester.zip`, and the clone of the PR's head branch (`6cba70df06`: SkylineNightly resolves
`pull/NNNN` to the head branch through the GitHub API, because a TeamCity PR build is a detached
checkout whose stamp reads `(HEAD detached at ...)` and would have broken the clone). For an
**Integration or Release run** the variable reaches only SkylineNightly: SkylineTester comes from
that branch's own config and the clone is that branch, so the run types need this work merged
into the branch first (the port branch for #4619). The first full-stack trial is therefore a
master machine.

Order: merge #4684; merge master into this branch; open this PR; flag one master machine;
create the leak folders; then the machine-by-machine rollout below.

**2026-09-18, the #4684 live test on BRENDANX-UW8**: staged the PR's shim in `D:\Nightly`, set
the variable to `pull/4684`, Brendan scheduled "Now". Shim log: `...SkylineNightly.zip?branch=pull%2F4684`;
`SkylineNightly.exe` and the shim replaced by the PR build (6:55 AM stamps, shim now the Release
copy); the old task argument `run integration trunk` ignored, `run` read `mode1`/`mode2` and the
integration run started. Merged, branch deleted, variable cleared. Every other machine picks up
the merged shim on its next run and from then on runs its settings.

## Rollout (revised 2026-09-18: prove it on the port branch, master and release untouched)

Brendan's target: a SkylineNightly on master that can run both the old way (master, release:
their SkylineTester ignores `nightlyRunType` and runs its combined passes with its own
TestRunner, attributes and all) and the new way (the port branch, whose SkylineTester and
TestRunner carry #4689). `SKYLINE_NIGHTLY_BRANCH` means only "which SkylineNightly" -
SkylineTester always comes from the branch's own build - so trying #4688 on a machine changes
nothing about what that machine tests.

1. Merge #4689 into the port branch (Brendan's; the Integration config then builds the new
   SkylineTester and the clone builds the new TestRunner). Flag an Integration machine with
   `SKYLINE_NIGHTLY_BRANCH=pull/4688`, save its form as Integration / Standard: the first full
   new-stack night. Create `Integration Leak Detection`, switch it to Leak Checking: the first
   leak-only night, with `LeakCheckingIncomplete` as the loud check.
2. Merge #4688 to master. Every machine picks it up the next night and still runs what it
   ran (legacy arguments map to the combined or perf run; master's and release's SkylineTester
   ignore the new element). Clear the variable on the flagged machine.
3. Create the three folders; teach the report side (`ai/docs/nightly-tests.md`, the labkey MCP
   `current_target` / `get_daily_test_summary` / folder lists, `/pw-nightly`,
   `/pw-daily-research`); write the machine table in the wiki (`skyline-wiki` skill).
   Files with the six-folder list, found 2026-09-17: `ai/mcp/LabKeyMcp/tools/nightly.py`
   (two lists, with the 540/720 minute expectations - a leak folder is 720),
   `ai/mcp/LabKeyMcp/tools/nightly_history.py`, `ai/mcp/LabKeyMcp/README.md`,
   `ai/mcp/LabKeyMcp/queries/nightly/hangs-schema.md`, `ai/docs/mcp/nightly-tests.md`,
   `ai/docs/daily-report-guide.md`, `ai/docs/testing-patterns.md`,
   `ai/claude/skills/skyline-nightlytests/SKILL.md` (folder table). Not before the folders
   exist: the daily report queries every listed folder.
4. Master gets the run types when the port branch merges (#4619). Then reconfigure the leak
   machines first (open the form, save `<branch> / Leak Checking`); verify a night of posts in
   the new folders. Then the perf machines, then the standard ones. No night is without leak
   coverage. The release branch keeps its combined run for good.

## Tasks

- [x] `NoLeakTesting` removed as an annotation (2026-09-17, Brendan: it only ever meant "leak
      test this in a perf run", a stopgap this replaces) - the attribute class, `DoNotLeakTest`
      and all 33 usages; so no `leakall` argument, pass 1 simply checks every test
- [x] TestRunner: `perffirst=on` with the perf-first / suite / perf-languages order and the
      per-machine rotation, `# Leak checking only`, the inversion and the pass-2 front-loading
      removed
- [x] SkylineTester: `nightlyRunType` in `.skytr` and the Nightly tab, the arg sets, old
      `.skytr` fallback
- [x] SkylineNightly: `RunSpec`, the two-row form with the 9+12 rule, legacy argument and
      settings migration, durations, posting folders, parser key phrase
- [x] Build, CodeInspection, ReSharper quick inspection; dry runs of the perf-first order
      (`Run-Tests.ps1 -PerfFirst -Loop 3`), the leak-only pass (`-Quality -Pass 1`) and the
      repeated sweeps (loop=-1, stopped after 12 s); `RunSpec.Parse` over every legacy
      argument and `Nightly.Parse` over last night's integration log (-> integration/standard)
- [ ] skyline.ms: three leak folders (needs project admin)
- [ ] Reporting: docs, labkey MCP, `/pw-nightly`, `/pw-daily-research`; the machine table on the wiki
- [x] `/code-review max` findings triaged and applied (2026-09-17, see Progress)
- [x] PR #4684 for the `SKYLINE_NIGHTLY_BRANCH` gate (off master; merge first)
- [x] `Run1`/`Run2` settings and the `run`-only task on this branch (`98772c12da`)
- [x] #4684 merged (`f6e34de4fa`, 2026-09-18); #4687 split into #4688 (SkylineNightly -> master)
      and #4689 (the rest -> port branch), both open; the variable narrowed to SkylineNightly only
- [x] #4688 tried on BRENDANX-UW8 (2026-09-18 6:25 PM: shim pulled `pull/4688`, the new
      SkylineNightly ran `integration/standard_leak` from `mode1`, the port branch's SkylineTester
      ran its usual passes; the new form showed Runs 1, Integration / Standard) and merged to
      master; #4689 merged into the port branch (its Perf/Tutorial TeamCity check was already
      failing on #4619-based branches); the variable cleared again
- [x] `Integration Leak Detection` folder created by Brendan (2026-09-18; testresults module
      answers there)
- [ ] Quiet-period check (8:00-10:00 AM): a master or release machine's next run unchanged
      under master's new SkylineNightly; then this machine's first Leak Checking night once the
      Integration config has built the port branch with #4689
- [ ] Rollout steps 1-4 above, one branch and one machine class at a time

## Progress

### 2026-09-17 - the code for steps 1 and 2

Branch `Skyline/work/20260917_nightly_three_channels` off master.

**Decisions made while implementing** (each is reversible before the PR merges):

- **`NoLeakTesting` is gone**, per Brendan's mid-session note. That removes the `leakall`
  argument from the design: pass 1 checks every test, always. Consequence for the rollout: a
  machine still on a pre-split standard argument now leak-checks the 33 formerly excluded tests
  too (about 1.4 h more pass 1 on a fast machine), and a machine on a pre-split perf argument
  gets the new perf run (no pass 1 at all), because "today's perf run" depended on inverting
  an attribute that no longer exists.
- **A fifth run type, `standard_leak`**, is the pre-split combined run (pass 0, pass 1, pass 2).
  It exists so that step 2 changes nothing on a standard machine: the legacy `trunk`,
  `release` and `integration` arguments map to it, and it stays until the machine is saved
  through the new form, which shows it as Standard. It is not in SkylineNightly's Type combo.
  SkylineTester's Run type combo does list it ("Standard with leak checking"), because an old
  `.skytr` with no `nightlyRunType` has to land on a visible item. Remove both once every
  machine has been reconfigured.
- **Working directory and log names keep the pre-split short names** (`RunSpec.ShortName`:
  `trunk`, `perf`, `release_perf`, ... plus `leak`, `release_leak`, `integration_leak`), so
  nothing on disk moves when a machine is reconfigured and the log parser keeps finding the
  branch in the clone command's directory name.
- **Open point 1, settled**: stress is gone entirely (Brendan, 2026-09-17: never noticed the 7th
  option, not interested in preserving it; its `NightlyStress` folder does not exist on
  skyline.ms, so it could not have posted in years). No `RunType.stress`, no legacy `stress`
  argument, and the Nightly tab's repeat / randomize controls are removed with it - the run
  type alone decides the run.
- **Open point 4**, provisionally: `Nightly x64 Leak Detection`, `Release Branch Leak
  Detection`, `Integration Leak Detection` (the names in the design). Only `Nightly.cs`
  knows them; change there and on skyline.ms together.
- **`.skytr` protocol**: `nightlyRunType` holds the combo text (`Standard`, `Leak checking`,
  `Perf`, `Stress`, `Standard with leak checking`), the way every other combo in a `.skytr`
  is stored. SkylineNightly still writes `nightlyRunPerfTests`, `nightlyRepeat` and
  `nightlyRandomize` for an older SkylineTester, which ignores the unknown element.
- **Perf run after every language has had its perf pass**: the remaining passes cycle the
  suite (loop=-1 keeps its meaning) rather than ending the run.

**Files**: `TestRunner/Program.cs` (pass 1 and pass 2, `GetPerfTestLanguageIndex`,
`OrderForPerfNight`), `TestRunnerLib/RunTests.cs`, `TestUtil/TestFunctional.cs`, 23 test
files, `SkylineTester/{TabNightly,SkylineTesterWindow,SkylineTesterWindow.Designer}.cs`,
`SkylineNightly/{RunSpec (new),Nightly,LogFileMonitor,Program,SkylineNightly,
SkylineNightly.Designer}.cs`, `SkylineNightly.skytr`, `SkylineNightly.csproj`.

### 2026-09-17, later - the form, and the review

**SkylineNightly form** (three iterations with Brendan's UI rules: no disabled control without
an obvious reason, no order dependence between controls): a `Runs (o) 1 ( ) 2` row between
Folder and Tests; the Then row (Branch + Type) is hidden with one run. The 9+12 rule fires as
the type is chosen (message box, combo switches back), with an OK-time check only for a pair
loaded from saved settings. Brendan laid the form out in the designer (standard button margins,
tab order); do not re-generate it.

**`/code-review max`** returned 15 findings (commit `734dfdbbb5`). Applied: #8 (`LoadNightlyRunType`
ignores non-nightly documents), #9 (perf language index read once per run - a pass starting
after midnight walked past a language), #15 (`ShortName` distinct per run: `master`,
`release_standard`, `master_leak`; legacy specs keep `trunk`, `perf`, `release`, ...), #10 (the
antivirus check is the first test of a perf night, before the perf tests), #6 (pass 1 drops a
failed test for the following sweeps and runs the run-once tests once, not as leak checks),
#2 (`RunAndPost` posts to the folder the log proves - `# Perf tests` / `# Leak checking only` -
so a branch whose SkylineTester predates the run type never posts a combined run to a leak
folder), #3 as a loud failure rather than rotation: TestRunner logs `# Pass 1 sweep N
complete.` and a leak run whose log lacks sweep 1's completion gets a synthetic
`LeakCheckingIncomplete` failure in the posted XML (Brendan: a machine that cannot get through
the suite in 12 h should not be a leak machine, and today nobody but him notices). #5 became
moot with stress removed. Declined: #1 and #7 (legacy machines keep the combined run, now with
the 33 extra tests in pass 1, and saving the form is the deliberate switch - Brendan is the one
reconfiguring machines), #4 (the leak hanger is pre-existing), #11 (manual `parse` command
matches master), #12 (folders are rollout step 3), #13 (perf-only list with loop=0 - not worth
the code), #14 (moot).

Dry runs after the fixes: perf night order is AV check, perf (ja), suite (en, fr), perf (zh);
leak run logs the sweep marker; quick inspection clean.

## Open points

1. ~~**Stress** in the Type combo, or legacy-argument only?~~ Removed entirely (2026-09-17).
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
