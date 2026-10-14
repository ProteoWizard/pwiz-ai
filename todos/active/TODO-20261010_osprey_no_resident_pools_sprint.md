# Sprint: remove every O(files x entries) data structure from Osprey

## Branch Information
- **Branch**: `Skyline/work/20261010_osprey_retire_compacted_buffer` (PR 1; later PRs get their own
  branches off master, listed here as they start)
- **Base**: `master`
- **Created**: 2026-10-10
- **Status**: All five PRs MERGED (PR 4 [#4838] as 4c2eba1af8 on 2026-10-13). No O(files x entries)
  structure is left. Remaining: the three-machine acceptance runs (section "Acceptance runs - three
  machines"); the TODO stays active until their results are recorded.
- **GitHub Issue**: (none - catalogue rows A1-A3, A6-A8 in TODO-osprey_parity_path_retirement.md; #4664)
- **Module**: `osprey`
- **PR**: [#4820](https://github.com/ProteoWizard/pwiz/pull/4820) (PR 1, merged 2026-10-11), [#4821](https://github.com/ProteoWizard/pwiz/pull/4821) (PR 2, merged 2026-10-11), [#4825](https://github.com/ProteoWizard/pwiz/pull/4825) (PR 3a, merged 2026-10-12); PR 3b [#4830](https://github.com/ProteoWizard/pwiz/pull/4830) (merged 2026-10-12); PR 4 [#4838](https://github.com/ProteoWizard/pwiz/pull/4838) (merged 2026-10-13, part of issue #4664)
- **Checkout**: `C:\proj\pwiz`

## Goal

No Osprey code path holds every run's precursor candidates or survivors at once - tokened,
untokened, diagnostic or default. Afterwards there is nothing for `OSPREY_ALLOW_UNFIXED_RESIDENT`
to admit, and `ResidentPaths` goes with it. The sprint may update or close existing issues.

Rows referenced as A1, A2, ... are in `TODO-osprey_parity_path_retirement.md` (the catalogue);
this file is the plan for the memory rows of it. Inventory re-checked 2026-10-10 against
`C:\proj\pwiz` at PR #4816's head (fb0603b9d3); line numbers below are from that checkout.

## Precondition

- PR #4816 merged (closes #4665 = catalogue A4, fixes #4729). It overlaps nearly every file this
  sprint touches and establishes the rule the sprint builds on: PerFileRescoring writes every run's
  2nd-pass answer in every pass-2 mode; SecondPassFDR writes no per-run file.

## Decisions (Brendan, 2026-10-10)

1. **Bank a final A/B before deleting each switch** - one `regression-parallel.ps1 -Dataset All`
   (or `regression.ps1 -Dataset All`) with the switch off, against the golden, recorded here, as
   was done for `OSPREY_STAGE7_STREAM`. **SUPERSEDED 2026-10-10**: both remaining resident arms
   abort in Stage 7, so neither A/B can run; Brendan chose deletion with the golden as oracle.
2. **`OSPREY_DUMP_PERCOLATOR`: drop it.** No bisection is active; a corrected version on the
   streamed first pass can be written when next needed. Remove the "re-run with projection-off"
   messages (FirstPassFdrTask ~1669-1698) with it.
3. **The untokened resident routes: review each one with Brendan before implementing** (stream vs
   refuse). Proposed default: stream where a bounded route already exists; refuse with the remedy
   where the analysis-wide summary is missing.
4. **The co-assignment panel term (#4664 section 1) is IN this sprint.** It is the last
   O(files x entries) structure after the tokens go.
5. **Batch `ModelDiagnosticsData.Build` may stay as a test-only oracle ONLY behind an explicit
   test flag** that keeps it from being reached outside tests.

## PR 1 - retire `compacted-entries-buffer` (`OSPREY_STAGE6_STREAM_SURVIVORS=0`, catalogue A2)

~170 prod + ~70 test lines.
- [x] ~~Bank the A/B~~ - NOT BANKABLE: the resident arm aborts on master (see "A/B finding").
      **Brendan, 2026-10-10: delete anyway, the committed golden is the oracle; same disposition
      for PR 2's projection-off A/B.** Code comments and docs/00 say no A/B was banked, and why.
- [x] Delete `PerFileScoringTask.Stage6ResidentHandoffGuardError` and its calls
- [x] FirstPassFdrTask: guard calls removed, releases unconditional on the switch (still gated on
      `_survivorLoader != null`, which projection-off lacks until PR 2); `ReloadFirstPassSurvivors`
      + 2 resx strings (3 resx + Designer)
- [x] Fold `StreamedSurvivorLoader` into `PublishedSurvivorLoader`
- [x] Remove `Stage6StreamSurvivors` + `Stage6StreamSurvivorsValidityKeySuffix` and the
      PerFileRescoreTask validity-key term (suffix was empty on the default, so no key changes)
- [x] **(#4825)** `MaterializeResumedFile` overlay arm - **NOT switch-only, moved to PR 2**: a null loader also
      happens under projection-off (FirstPassFDR Run's legacy arm never sets `_survivorLoader`, and
      PerFileRescore.Rehydrate passes `PublishedSurvivorLoader`). Comments updated to name projection-off
- [x] Startup refusal: `OspreyEnvironment.Stage6StreamSurvivorsRetiredSet`, Program.cs, and a
      CommandLineErrorTest case beside the OSPREY_STAGE7_STREAM one
- [x] `COMPACTED_ENTRIES_BUFFER` out of `KNOWN_UNFIXED` (now `projection-off` only);
      ResidentPoolGuardTest `AssertStage6HandoffGuard` replaced by `AssertTokenLists` (keeps the
      list-parsing coverage on `ResidentPoolGuardError`); TaskValidityKeyTest; regression.ps1
      `$abSwitchSet` / `$cannotStreamJoin` + comments; docs/00 item 4 marked DONE
- [x] #4544 finding 3: moved into `FirstPassSurvivorLoader.CheckSurvivorCount` - each run's first
      Stage-4 load is recorded (one int per run), a reload must match it, and once every run has
      loaded the sum must equal `ExpectedSurvivorCount` (set by `CompactFromSidecars` from the
      compaction's `afterCount`, only when stems are unique - #4544 finding 1). Reconciled-parquet
      loads are excluded (they add gap-fill rows). Per-run EXPECTED counts were rejected: keeping
      per-file rows-per-base_id is itself O(files x entries). VERIFIED it fires: with the
      comparison temporarily off by one, TestSubsetStraightThroughAndReruns failed with
      "counted 1607 ... produced 1607" (reverted; log `ai/.tmp/sessions/20261010-nores/sabotage.log`)
- [x] Update #4601 and #4577 text that cites `OSPREY_STAGE6_STREAM_SURVIVORS`
- [x] `ai/docs/osprey-development-guide.md` cites the switch - updated 2026-10-11
- Gate: `Build-Osprey.ps1 -Configuration Debug -RunTests -RunInspection` green, 649/649;
  `regression-parallel.ps1 -Dataset All` 48 PASS / 0 FAIL / 0 SKIP in 32:42
  (`ai/.tmp/sessions/20261010-nores/regression-all.log`); Stellar re-run green after review fixes
- Commits: c8bdd230d7 (main change), fbc36e017c (review fixes)
- `/code-review medium` (8 findings), triaged:
  - FIXED #1: count violation was thrown inside parallel loops (message lost) - now returned through
    `Load`'s error, which both callers log + exit 1. Re-verified with the off-by-one: `Error: First-pass
    compaction counted 1607 ...` (`ai/.tmp/sessions/20261010-nores/sabotage2.log`)
  - FIXED #6 stale "loader holds no per-file state" remark; #8 three unreflowed comment lines
  - DROPPED #2 (check fires late / not on resume): with reconciliation on (default) Stage 6 planning
    loads every run at Stage 5, as before; the deleted check never ran on a resume either
  - DROPPED #3 (silently skipped when maps differ in size): only the #4544 stem-collision case
  - DROPPED #4 (`=1` refused too): same as the OSPREY_STAGE7_STREAM precedent and its test
  - DROPPED #5 (regression.ps1 does not pre-detect a stale export): Osprey's startup refusal names it
  - DROPPED #7 (move check out of Load): design preference; Load is where every count is seen

### A/B finding (2026-10-10)

The `OSPREY_STAGE6_STREAM_SURVIVORS=0` arm ABORTS in Stage 7 on every dataset, so there is no
output to compare:

    Experiment-fold scope violation in 'Ste-2024-12-02_HeLa_4mz_sDIA_400-900_20': base_id 0 takes
    its best target observation from entry_id 0, which is not one of this file's survivors
    at StreamingFdr.CompeteOneFile <- ComputeFullPopulationPrecursorFdrStreaming (verify recompute)
    <- Pass2FdrSidecar.ComputePass2TransferCompeteFull <- SecondPassFdrTask.Run

- master 5a1cd82efc (#4816), `regression-parallel -Dataset All`: Stellar and StellarGenDecoyEntrap
  both aborted on the straight-through leg; run stopped. Logs:
  `pwiz_tools/Osprey/TestResults/regression-lane-*-20261010_150639.log`,
  `pwiz_tools/Osprey/TestResults/regression-20261010_150640_35964/Stellar/straight/straight.log`
- pwiz-perfbase af30974a4a (#4809, the commit BEFORE #4816), `-Dataset Stellar`: SAME abort, so
  #4816 did not cause it. Log: `ai/.tmp/sessions/20261010-nores/ab-stage6-off-perfbase.log`,
  `C:\proj\pwiz-perfbase\pwiz_tools\Osprey\TestResults\regression-20261010_151409_54152\Stellar\straight\straight.log`
- Unconfirmed hypothesis: on a non-streamed source `Pass2FdrSidecar.LoadOneFile` returns
  `new List<FdrEntry>()` when `residentByFile` lacks the run (or its list was cleared earlier), so
  `ownSurvivorIds` is empty and every best target fails the scope check. regression.ps1 sets
  `OSPREY_PASS2_VERIFY_WORKER=1`, which is what runs that recompute.
- `OSPREY_FDR_PROJECTION=0` (PR 2's oracle) on master 5a1cd82efc, `-Dataset Stellar`: the SAME
  abort. So both remaining A/B oracles share one broken resident Stage 7 path, and PR 2's banked
  A/B is blocked by the same thing. Log: `ai/.tmp/sessions/20261010-nores/ab-projoff-master.log`,
  `pwiz_tools/Osprey/TestResults/regression-20261010_151810_66852/Stellar/straight/straight.log`
- No gate runs either arm, which is how it broke unnoticed - the argument decision 1 was written for.

## PR 2 - retire `projection-off` (`OSPREY_FDR_PROJECTION=0`, catalogue A1)

~1,050 prod lines. Note projection-off ALSO takes the resident Stage 6 handoff and resident
Stage 7 (its survivor loader is null), so those arms stay live until PR 3.
- [x] ~~Bank the A/B with `OSPREY_FDR_PROJECTION=0 OSPREY_ALLOW_UNFIXED_RESIDENT=projection-off`~~
      - aborts on master like the Stage 6 arm (PR 1's "A/B finding"); golden is the oracle
- [x] **(#4825)** **(DEFERRED to PR 3 shared tail - PR 2 only reworded their comments)** `MaterializeResumedFile` overlay arm + `MaterializeAllResumedFiles` null-loader path (moved
      here from PR 1: projection-off is what still reaches them)
- [x] Coordinate #4511 first: its streaming-vs-resident parity check uses this path - do it now or
      rewrite it against the golden
- [x] PerFileScoringTask: `NeedsResidentPool`, `GuardResidentPool`, `ResidentPoolGuardError`,
      `ResidentPoolTrigger`, the fat loads in Run / RehydrateFromOwnOutputs / LoadJoinOnlyScores
- [x] FirstPassFdrTask: legacy Run branch (~722-820), `RunPercolatorFdr(List)` facade,
      `RunFirstPassProteinFdr`, `WriteFdrScoresSidecars`, resident `WriteFdrBenchPass1IfRequested`,
      `CompactFirstPass` non-bundle branch, the resident refusal and overlay arms
- [x] Osprey.FDR: `PercolatorEngine.RunPercolatorFdr(List)`, `DispatchSvm`, `ApplyPercolatorResults`,
      `RunPercolatorStreaming`; `PercolatorEntryBuilder.cs` (move `BuildBasicFeatures` first - used
      by PercolatorScorer ~1845); `PercolatorScorer.ScorePopulationAndComputeFdr`. CHECK
      `ProteinFdr.RunFirstPassProteinFdr` / `ProteinFdrEngine.RunFirstPass` - also called by
      PerFileRescoreTask ~1046 on the bundle path (PR 3)
- [x] Already dead: resident `PercolatorEngine.ClampExperimentQToBestRun` (only FdrTest calls it),
      the uncalled `RunPercolatorFdr(FdrProjectionSet)` facade
- [x] Drop `OSPREY_DUMP_PERCOLATOR` / `OSPREY_PERCOLATOR_ONLY` and `WriteStage5PercolatorDump`
      (decision 2); update DIAGNOSTICS.md and Test-Snapshot references
- [ ] **(DEFERRED to PR 3 - still live via the R1 batch overlay; also keeps #4542 finding 1 alive)** `ModelDiagnosticsReport.Write` + batch `ModelDiagnosticsData.Build`: delete, or keep test-only
      behind an explicit test flag (decision 5)
- [x] Tests: ResidentPoolGuardTest, PercolatorEntryBuilderTest, FdrTest (779, 833, 1165, 1242, 1298,
      3436), LibraryFragmentReleaseTest 176-232, ModelDiagnosticsDataTest oracle uses
- [x] #4463: one of its two wrong emitters goes; finish the experiment-level count or update it
- [ ] #4542 finding 1 NOT resolved by PR 2 (null accumulator still falls back to the batch Write); commented 2026-10-11 - closes when the batch Write goes in PR 3

## PR 3 - the untokened resident routes, then the shared tail (catalogue A3, A6, A7, A8)

### PR 3 PLAN - decided with Brendan 2026-10-11 (implement in a FRESH session)

**Decisions (Brendan, 2026-10-11):**
- **R3/R4:** reject an older-build reconciled parquet at the currency check, then delete the eager
  all-runs arms. This is the first piece.
- **R1:** stream. When FirstPassFDR will Run and train, treat `.reconciliation.json` as absent, so it
  takes the lean load. Then delete the cleanup tail.
- **R5: DELETE** `OSPREY_DUMP_RESCORED`, `OSPREY_DUMP_MULTICHARGE` and `OSPREY_DUMP_RECONCILIATION`
  (and their `*_ONLY` gates) from C#. Keep `OSPREY_DUMP_CONSENSUS`, which is O(precursors) and has
  no plumbing.
  - Principle (Brendan): diagnostic hooks were kept because they were "free". Once one costs
    maintenance or complexity, remove it and wait for a need to resurface.
- **No per-variable refusal for retired env vars.** Replace the per-name refusals with ONE general
  check: an `OSPREY_*` environment variable Osprey does not recognize is an error, just as an
  unrecognized CLI argument is. This retires `Stage7StreamRetiredSet`,
  `Stage6StreamSurvivorsRetiredSet`, `FdrProjectionRetiredSet` and `PercolatorDumpRetiredSet`.
- **Cross-impl parity must not be broken by accident.** The Rust gate's days are numbered, but
  breaking it has to be an explicit decision, not something we stumble into the way the A/B oracles
  were lost. A cross-impl test must PASS at the end of this PR.

**Facts gathered 2026-10-11 (not yet acted on):**
- **No `OSPREY_*` scan exists today.** There is no `GetEnvironmentVariables()` / prefix check
  anywhere in `pwiz_tools/Osprey`. Recognition is scattered: about 112 distinct `@"OSPREY_..."`
  literals across OspreyEnvironment, OspreyFileDiagnostics, OspreyDiagnostics and the tasks.
- **The cross-impl harness** is `ai/scripts/Osprey/Compare/Compare-EndToEnd-Crossimpl.ps1`
  (README in the same folder; the gate is Stage 7 protein FDR + blib SQL at 1e-9).
  - For the C# run it sets `OSPREY_DUMP_STAGE7_PROTEIN_FDR` and optionally `OSPREY_SVM_C_TOLERANCE`
    (~438-451). Both are recognized by C#.
  - The Rust run sets `OSPREY_DUMP_STAGE7_PROTEIN_FDR` (~406).
  - It builds NEITHER side: run `Compare/Build-OspreyRust.ps1` and
    `Build-Osprey.ps1 -Configuration Release` first. It hard-fails on stale binaries.
- **The unknown-variable check is a risk to cross-impl and harness runs.** A developer shell (or a
  harness) holding a RUST-ONLY variable would now stop the C# run.
  - Rust-only names include `OSPREY_DUMP_PERCOLATOR`, `OSPREY_PERCOLATOR_ONLY`,
    `OSPREY_TRACE_PEPTIDE`, `OSPREY_DUMP_CAL_PREFILTER` and `OSPREY_DIAG_XCORR_SCAN`; see
    `DIAGNOSTICS.md` / the dev guide's "Rust-only" notes.
  - Also check which variables `Test-Snapshot.ps1` passes to the C# tool: its stage6 envVars still
    set the three dumps being deleted.

**Steps, in order:**
1. **Baseline cross-impl FIRST, on current master, before any change.**
   - Build Rust (`Build-OspreyRust.ps1`) and C# Release, then run
     `Compare-EndToEnd-Crossimpl.ps1 -Dataset Stellar -Files Single`, then
     `-Dataset Astral -Files All -Force` (~45 min; detach it).
   - Record PASS/FAIL here with log paths. #4820 and #4821 were gated only against the C# golden,
     so whether parity still holds after them is UNKNOWN.
   - If it FAILS now, stop and bring it to Brendan before PR 3 changes anything. That is the
     explicit decision point.
   - **RESULT (2026-10-11, master a78f88b5a4, Rust maccoss/osprey d19be4c):**
     - Stellar Single first FAILED on two HARNESS defects, neither a parity break:
       1. Rust exe exit `-1073741515` (0xC0000135, `openblas.dll` not on PATH at run time). Fixed in
          pwiz-ai: `Add-VcpkgRuntimeToPath`, called from `Get-OspreyRustExe` (`Dataset-Config.ps1`).
       2. Blib gate FAIL with EVERY result column identical (0 divergent rows in every table): the
          only difference is a C#-only `osprey.validity` row in `OspreyMetadata` - the artifact
          stamp #4809 (2026-10-09) embedded in the blib. The harness excluded `osprey_version` but
          not this key, so the gate has been red on every dataset since #4809. Fixed in
          `Compare-Blib-Crossimpl.ps1` (key excluded, with the reason).
     - After both fixes, Stellar Single **PASS** (Stage 7 protein FDR, blib SQL, FDR sidecars at
       1e-9): `ai/.tmp/sessions/20261011-pr3/xi-stellar-single-baseline.log`, blib re-compare run
       by hand on `pwiz_tools/Osprey/TestResults/crossimpl-stellar/{rust,cs}/output.blib`.
     - Astral All (`-Force`): **PASS** - Stage 7 protein FDR, blib SQL and FDR sidecars at 1e-9,
       117,236 precursors both sides; Rust 23:44, C# 8:27
       (`ai/.tmp/sessions/20261011-pr3/xi-astral-all-baseline.log`,
       `pwiz_tools/Osprey/TestResults/crossimpl-astral/*_compare.log`). Parity holds on master after
       #4820/#4821; this is the baseline step 6 compares against.
2. **R3/R4.** Find the reconciled-parquet currency predicate: `PerFileResumeDriver.IsCurrent` /
   `ScoringTaskShared.AllReconciledParquetsCurrent` / `IsCurrentReconciledSurvivorSubset`, and
   `ParquetScoreCache.IsSubsetWithoutScoreIndex`.
   - Make an older-build parquet NOT current. Then a resume re-scores that run, and
     `--task SecondPassFDR` refuses up front with the existing
     `SecondPassFdrTask_Run__0__of__1__runs_...older_Osprey_build` text instead of a stack trace.
   - Delete `MaterializeAllResumedFiles` + the eager arm (`PerFileRescoreTask` Rehydrate ~914-940),
     and refuse up front in `PerFileScoringTask.Rehydrate` when
     `ExpectReconciledInput && !CanStreamStage7Join`.
   - Delete the dead tail: `ExecuteRescore` / `BuildRescoredPool` null-loader arms;
     `Pass2FdrSidecar` `!Streams` branches (`residentByFile`, `LoadOneFile` resident arm,
     `ReloadPass2Sidecars`, `OverlayPass2OntoResidentPool`); `WarnResidentStage7Join`;
     `WritePass2AndFinalize(rescored.Value)`; the `RescoredEntries` resident fallbacks;
     `MaterializeResumedFile`'s overlay arm.
   - Reproduce the old behavior first, as a SubsetPipelineTest case: an older-build marker parquet
     (the night's `ai/.tmp/sessions/20261010-nores/routes/restamp_parquet.py` shows how) must now
     re-score / refuse up front.
3. **R1.** In `PerFileScoringTask.Rehydrate` (~529/593) treat `hasReconSidecars` as false when
   FirstPassFDR will Run and train. Factor the "Training the first-pass Percolator model" term out
   of `PreCompactionPoolReason`.
   - Then delete: `HydrateReconciliationOverlay` (+ its IOTest oracle tests or port them), the
     overlay arm of `HydrateRescoreBundleIfPresent` / `LoadOwnReconciliationBundle`,
     `ModelDiagnosticsReport.Write` + the null-accumulator fallback in
     `LogFirstPassResultsAndReport` (closes #4542 finding 1), `ProteinFdrEngine.RunFirstPass` at
     PerFileRescoreTask ~1041, and the stubs-only resident loop + `WarnPreCompactionPool` if nothing
     else reaches them.
   - Decision 5: batch `ModelDiagnosticsData.Build` stays only as a test oracle behind an explicit
     test flag, or goes with its oracle tests (ModelDiagnosticsDataTest uses it ~25x).
   - Fix the false "every file in memory" warning + `pre-compaction-pool: resident` route line on
     the shipped HPC SecondPassFDR node (1st-pass sidecars withheld -> `hasReconSidecars` false).
4. **R5.** Delete the three dumps:
   - `IOspreyDiagnostics` / `OspreyFileDiagnostics` members and writers;
   - `Stage6Planner`'s `EntriesForDump` plumbing;
   - the `PerFileRescoreTask` `DumpRescored` pull (~815);
   - the three names in `OspreyDiagnostics.s_forcedDumpBundle` (`-d`).
   - Update `Test-Snapshot.ps1` stage6 (C# envVars + `compareDumps`: keep `consensus`, keep the
     artifact comparison), `DIAGNOSTICS.md` (mark Rust-only), `Measure-Pipeline.ps1` scrub lists
     (harmless) and docs 09/10/11/14/15/18 under `pwiz_tools/Osprey/docs`.
5. **Unknown-`OSPREY_*` check.**
   - Centralize the recognized names: one registry in `Osprey.Core`, e.g. `OspreyEnvironment`
     `KnownVariables`, fed by every reader. Prefer making the readers go through it so the list
     cannot drift.
   - At startup (Program.cs, beside the current refusals), error on any `OSPREY_*` variable not in
     it, naming it. Delete the four `*RetiredSet` refusals.
   - Decide with Brendan how Rust-only names are treated: still an error, since C# does not honor
     them (consistent and simplest)? Or a recognized-but-ignored list for the cross-impl workflow?
     Default to ERROR unless he says otherwise. The cross-impl harness and Test-Snapshot must set
     Rust-only variables ONLY for the Rust process.
   - Test: CommandLineErrorTest (`STARTUP_VARIABLES` / `Variable(...)` helper) - an unknown
     `OSPREY_FOO` fails naming it; a known one passes.
   - A pwiz-ai/CI shell with stale exports will now fail loudly. Check `regression.ps1` /
     `regression-parallel.ps1`, which set e.g. `OSPREY_PASS2_VERIFY_WORKER`, and TeamCity
     `tctest.bat` for anything unrecognized.
6. **Gates at the end:**
   - unit gate;
   - `regression-parallel -Dataset All`;
   - SubsetPipelineTest;
   - `/code-review medium`;
   - TeamCity Perf/Regression;
   - **AND the cross-impl gate re-run** (Stellar Single + Astral All) with the result recorded.
     If it now fails where step 1 passed, that is a parity break: bisect it and bring it to Brendan
     as an explicit decision; do not merge past it silently.
7. Probably two PRs: (a) R3/R4 + R5 + the env-var check, and (b) R1 + its tail. Keep each reviewable.

Each route reviewed with Brendan before implementing (decision 3):

**Route memo for that review (night session 2026-10-10, read-only agent, line numbers approximate).**
Recommendation: **STREAM R1 and R5, REFUSE R3 and R4 early.**
- **R1** (`--task FirstPassFDR` over a dir with `.reconciliation.json`, outputs not current): takes
  the resident stubs-only loop (~1.19 GB/file) + all-runs `HydrateReconciliationOverlay` +
  `BuildFromEntries`, because `hasReconSidecars` forbids the lean load and the "Training the
  first-pass Percolator model" `PreCompactionPoolReason` forbids streaming. The overlay bundle is
  PURE WASTE: `FirstPassFdrTask.Run` never reads `RescoreBundle` and PerFileRescore is excluded.
  Fix: treat `hasReconSidecars` as false when FirstPassFDR will Run and train -> it takes the
  existing lean counts-only load. ~20-40 lines in PerFileScoringTask + resx + test. Then the
  Training reason, `HydrateReconciliationOverlay` (~110 lines; IOTest uses it as an oracle),
  and - once projection-off and DUMP_PERCOLATOR are gone - `ModelDiagnosticsReport.Write` /
  `ModelDiagnosticsData.Build` (prod) and `ProteinFdrEngine.RunFirstPass` @PerFileRescore ~1041
  have NO production caller (inferred; verify after PR 2).
- **R3** (`--task SecondPassFDR`, `CanStreamStage7Join` false for disk reasons): every disk state
  ALREADY ends in an error (missing summary -> `ReadRetainedBaseIds`; no sidecars ->
  `ReadRetainedBaseIdsOrFail` in `ReleaseUnscorableLibraryFragments`; stale/missing reconciled
  parquet -> `SecondPassFdrTask.Run` ~404-421 `UnusableReconciledParquets`) - but only AFTER the
  all-runs load. Fix: refuse up front in `PerFileScoringTask.Rehydrate` when
  `ExpectReconciledInput && !CanStreamStage7Join`, naming the missing piece (reuse existing
  strings). ~40-60 lines; unlocks deleting the stubs-only loop, `PerFileRescoreTask.Rehydrate`'s
  ExpectReconciledInput arm (~962-1057 incl. RunFirstPass + RescoreCompaction.Apply) and the null
  branch of `BuildStage7PerRunSource`.
- **R4** worker: already refused (two different messages). Straight-through resume: a stale summary
  makes FirstPassFDR Run (not resident); the eager `MaterializeAllResumedFiles` is reached only for
  stale/missing reconciled parquets (which then throw at SecondPassFdrTask ~414 after loading
  everything) or an empty join. Fix: turn the null source into the named error up front, delete
  `MaterializeAllResumedFiles` + the eager arm (~914-940). ~30-50 lines.
- **R5**: `OSPREY_DUMP_RESCORED` pulls `rescored.Value` (the ONLY whole-pool pull on a
  PerFileRescoring worker) and `WriteStage6RescoredDump` copies+sorts every row;
  `OSPREY_DUMP_MULTICHARGE/RECONCILIATION` retain every file's list via `EntriesForDump` just to map
  index -> entry_id. Stream: resolve per file in the planner callbacks; write the rescored dump per
  file in ordinal order. ~80-120 lines, 4 files (signature change on IOspreyDiagnostics). Minimum
  alternative: refuse DUMP_RESCORED on a worker.
- Shared tail after R1-R5: `ExecuteRescore` loader-null arm and `BuildRescoredPool` early return are
  dead (empty join only); Pass2FdrSidecar `!Streams` branches, `ReloadPass2Sidecars`,
  `OverlayPass2OntoResidentPool`, `WarnResidentStage7Join`, `WritePass2AndFinalize(rescored.Value)`,
  `RescoredEntries` resident fallbacks are kept alive only by R3/R4.

**Routes EXERCISED on Stellar (2026-10-11, snapshot exe of the PR 2 branch; scratch
`D:\test\osprey-runs\nores-routes-20261011\<exp>\` ~70 GB, scripts + status in
`ai/.tmp/sessions/20261010-nores/routes*`). No route silently wrote a wrong blib.**
- **R1 CONFIRMED, worse than the memo** (`r1-firstpass-rerun\r1.log`): summary deleted ->
  `--task FirstPassFDR` warns "Training the first-pass Percolator model needs ... every file in memory",
  `[PATH] pre-compaction-pool: resident`, loads every run, builds `all-runs-bundle: built runs=3` -
  then "first-pass intermediate files for all 3 files are up to date; skipping first-pass scoring" -
  NO training ran, and planning re-ran from scratch (bundle unused). Outputs byte-identical. Also: a
  deleted `<stem>.1st-pass.model.json` is NOT regenerated (not a declared output).
- **R3 PARTIAL.** Summary missing: on an HPC-staged node (1st-pass sidecars withheld, as
  Invoke-HpcChain stages it) loads all runs (~5 GB warning) THEN errors; on a full dir errors
  immediately. Missing reconciled parquet / Stage-4 parquet in its place: errors UP FRONT. An
  OLDER-BUILD reconciled parquet (marker 'true' or no score_index): loads every run, then
  `InvalidOperationException ... written by an older Osprey build` WITH A STACK TRACE
  (SecondPassFdrTask.cs:417) - a user-data error surfaced as a defect.
- **R4 mostly REFUTED:** a deleted or Stage-4 reconciled parquet -> `rescore-resume: adopted=2
  rescore=1`, only that run re-scored, byte-identical. CONFIRMED only for the older-build parquet:
  the driver judges it VALID (PerFileRescoring skipped), then SecondPassFDR loads all runs and dies
  as above (`r4d-resume-oldmarker`).
- **R5 CONFIRMED:** `OSPREY_DUMP_RESCORED` -> "Rebuilding the kept precursor candidates from 3
  files..." (whole pool) with NO `[PATH]` line, so route-line gates cannot see it.
- **Also found:** the SHIPPED HPC SecondPassFDR node (streams correctly) logs a FALSE "Resuming
  without cross-run reconciliation files needs ... every file in memory" warning and
  `[PATH] pre-compaction-pool: resident`, because the withheld 1st-pass sidecars make
  `hasReconSidecars` false. BuildRescoredPool and MaterializeAllResumedFiles share one resource
  string, so the log cannot tell those routes apart.
- **Sharpened recommendation:** R1 stream (pure waste today). R3/R4 reduce to ONE defect: an
  older-build reconciled parquet is accepted as current, then refused after an all-runs load with a
  stack trace - make the currency check reject it up front (then the eager arms lose their last
  trigger). R5 stream or refuse as before. Fix the false resident warning/route line on the HPC node.

**Reachability PROBED on the PR 2 branch (2026-10-11 00:30, then reverted):** temporary throws at the
start of `RescoreHydration.HydrateReconciliationOverlay`, `ModelDiagnosticsReport.Write` and just
before `PerFileRescoreTask`'s `ProteinFdrEngine.RunFirstPass` call. Unit suite: only the 3 IOTest
tests that call the overlay DIRECTLY as an oracle failed (TestRescoreHydrationRoundTrip,
...RejectsActionEntryIdNotInStubs, ...StreamingMatchesResidentCompaction) - no pipeline test reaches
any of the three. `regression-parallel -Dataset All`: 48 PASS / 0 FAIL with all probes armed
(`ai/.tmp/sessions/20261010-nores/probe-all.log`). So after PR 2 the batch overlay, the batch
model-diagnostics report and the bundle protein-FDR recompute are reached by NO gated route; R1 (an
ungated `--task FirstPassFDR` re-run over a dir with `.reconciliation.json`) is the remaining
candidate trigger. Whichever way R1 is decided, these three go with it - and with them decision 5
(`ModelDiagnosticsData.Build` test-only behind a flag, or deleted with its oracle tests).

**Root cause of the PR 1 A/B abort (inferred from code, consistent with the "base_id 0 / entry_id 0"
signature, not reproduced):** under projection-off / Stage6-switch-off, `FirstPassFdrTask.Run`
never sets `_survivorLoader`, yet `CanHydratePerRun` admits straight-through
(ScoringTaskShared ~582-603), so `BuildPerRunHydrate` is non-null and `RescoreOneFileStreamed`
refills, rescores and CLEARS each run's list; `BuildRunPerRunSource` returns null (no loader) and
`BuildRescoredPool` returns early on `plan.Loader == null` - so Stage 7 folds an EMPTY pool. With
`OSPREY_PASS2_VERIFY_WORKER=1` (regression.ps1) the scope check fires; without it the run would
presumably have written a near-empty blib with exit 0. Dies with projection-off (PR 2); R3/R4 are
not affected (their lists are never drained).
- [x] **(PR 3b)** R1 `--task FirstPassFDR` re-run over a dir with `.reconciliation.json`: resident stubs load +
      all-runs `HydrateReconciliationOverlay` + `BuildFromEntries` (PerFileScoringTask ~1509-1529,
      ~2088; FirstPassFdrTask ~3191)
- [x] R2 `OSPREY_DUMP_PERCOLATOR` - gone with PR 2
- [x] **(#4825)** R3 `--task SecondPassFDR` with `CanStreamStage7Join` false for disk reasons (no current
      summary / stale reconciled parquet): `HydrateCompactedStreaming` all-runs + resident Stage 7
      + `ProteinFdrEngine.RunFirstPass` over the bundle
- [x] **(#4825)** R4 straight-through resume or PerFileRescoring worker with no current summary: all-runs
      bundle (`AllRunsBundleGuardError` returns null by design) + eager `MaterializeAllResumedFiles`
- [x] **(#4825)** R5 `OSPREY_DUMP_RESCORED` reads `rescored.Value`; also `DUMP_MULTICHARGE` / `DUMP_RECONCILIATION`
Then delete the shared tail:
- [x] **(PR 3b)** Stage 6 non-streamed arms (`PlanStage6` `_survivorsStreamed` false, `Stage6Planner.Plan(List)`,
      `ExecuteRescore` loader-null, `BuildRescoredPool` early return)
- [x] **(#4825)** except the `RescoredEntries` resident fallbacks (deferred to PR 3b, needs a `Files()` probe); Stage 7 resident join: `!rescored.Streams` branches in Pass2FdrSidecar (reload, residentByFile,
      LoadOneFile resident arm), `OverlayPass2OntoResidentPool`, `ReloadPass2Sidecars`,
      `WarnResidentStage7Join`, `WritePass2AndFinalize(rescored.Value)` + batch pass-2 builders,
      `RescoredEntries` resident fallbacks (`Files()`, no-op Drop/Materialize)
- [x] **(PR 3b, e682111708)** Guard machinery: `ResidentPaths.cs`, `AllowUnfixedResident` / `NamesResidentPath`, Program.cs
      unknown-token warning (keep a retired-variable refusal), regression.ps1 known-gaps block,
      `$cannotStreamJoin`, the `finally` restore; CommandLineErrorTest, SubsetPipelineTest ~1179
- [x] **(PR 3b)** Docs: 00, 07, 11, 15, Regression/README, osprey-development-guide, osprey-large-datasets, CHS README

## PR 4 - the co-assignment panel's O(accepted x runs) rows (#4664 section 1)

**Night-session finding (2026-10-10, read-only design agent - NOT yet measured):** section 1 likely
describes code #4662 replaced. #4664 was filed 2026-09-13 14:32Z; #4662 ("Added the detection apex
RT to the per-file FDR sidecar at format v7") landed 2026-09-14. Today:
- the panel reads NO parquet (only `<stem>.1st-pass.fdr_scores.bin` v7 via `FdrScoresSidecar.ReadRecords`);
- `_fileRows` / `_fileRowByKey` are ONE file, cleared in `FlushFile` (CoAssignment.cs ~1550, ~1621);
- `_byPrecursor` is per distinct precursor, not x runs;
- "13,954,867 rows" is the CUMULATIVE `COUNT_COASSIGN_DETECTED` counter (PeakCoAssignmentSource.cs ~292, ~336).
The only x-runs structure left is `_admittedRunDecoys` (runs x ~admitted decoys, ~10-30 MB at 1000);
free `[f]` after each phase-2 flush (~5 lines, byte-identical).
- Bigger target: the Parquet.Net per-row-group garbage is in `RescoreHydration.FoldPreCompactionPerRun`
  -> `LoadResumeStubs` ("54 of this task's 63 minutes", FirstPassFdrTask ~370), not the panel;
  `LoadFirstPassExperimentRecords` is read twice back to back (~393, ~403; ~400 MB each at 446).
- Gate gap: `Regression/DiagnosticsGolden.ps1` does NOT pin nShared, betterByTolerance, deltaRt
  histograms or worstOffenders - diff the whole `coAssignment` subtree (`Get-DiagnosticsPayload`).
- **MEASURED on SEA-AD 82 (2026-10-11, snapshot exe of the PR 2 branch, hard-linked copy dir
  `D:\test\osprey-runs\sea-ad\runs\seaad-82files-mdiag-measure-20261011`, original run untouched -
  588/588 files unchanged): the join's floor is FLAT.** Post-GC live (dotMemory `--use-api` forces a
  full GC at the `coassign-join-start/end` snapshots): 5,071 MB -> 5,100 MB across 82 files
  (+0.35 MB/file; `run-coassign-only-dotmemory.log` lines 135-143). The pre-GC climb (+689 MB, or
  5904 -> 6592 MB uninstrumented) is per-file LOH garbage: workstation GC + 64 MB gen0 still +628 MB,
  + 32 MB LOH threshold cut it to +385 MB. `_byPrecursor` holds 81,759 run-scope / 47,495
  experiment-scope entries at 82 files vs 57,169 / 44,469 at 12 - grows with DISTINCT precursors,
  not rows x runs; `coassign-detected rows=3,911,721` is the cumulative counter (identical to the
  original run). Join wall 17 s; whole-run peak WS 11.69 GB. Section 1's premise is stale.
- Remaining for #4664 acceptance: the 500/1000-file regeneration on a 64 GB box (not this machine).
- Was next: MEASURE on the 446-run CHS bed (not on this machine - `D:\test\osprey-runs` has no chs-seer)
  with `OSPREY_MDIAG_COASSIGN_ONLY=1 --timestamp --memstamp OSPREY_LOG_MEMORY=1 OSPREY_LOG_COASSIGN_ALLOC=1`;
  if the join floor is flat, close section 1 with the correction.

- [ ] **(premise MEASURED stale 2026-10-11, see above - close with the correction)** `_fileRows` / `_byPrecursor` retained for the whole apex-RT join: 13.95 M rows at 446 runs,
      ~31 M at 1000. Bound it (fold per precursor, or a disk-backed join) without changing the panel
- [ ] Parquet.Net per-row-group arrays under it (hand the caller one row group at a time, the
      `ReadFdrStubScalars` shape)
- [ ] #4664 acceptance: 500-file and 1000-file `--task ModelDiagnostics` regeneration on a 64 GB box,
      products unchanged, per-phase peaks from perfviz.py; then close #4664 (with #4577's status noted)

## Acceptance runs - three machines

Test design (Brendan, 2026-10-13), replacing issue #4664's 500/1000-file acceptance. The procedure a
session on each machine follows, the shared binary and the results folders are on the share:
**`M:\home\brendanx\data\MacCoss\Osprey\acceptance-20261013\`** (`README.md`). This section is the
contract that README implements.

**Question.** With every O(files x entries) structure gone (PRs 1-4), does the final code run both
large cohorts straight through at default settings on all three test machines - in particular CHS-SEER
446 on a 64 GB box - and do the three machines agree on the answer?

**Matrix.** 3 machines x 2 cohorts = 6 runs, one cohort at a time per machine, SEA-AD then CHS.

| machine | CPU | RAM | SEA-AD before | CHS before |
|---|---|---|---|---|
| BRENDANX-UW8 | i9-14900, 32 logical | 128 GB | 4 h 12 m (10-06 race) | **never** - caches staged 2026-10-13 |
| BRENDANX-UW25 | i9-14900, 32 logical | 64 GB | 4 h 02 m (10-07) | yes |
| MACS2 | PowerEdge, Xeon Gold 6354, 2 sockets, 72 logical | > 500 GB | 4 h 19 m defaults, **2 h 09 m fast1** | 9 h 34 m (tuned, 10-08) |

**Fixed across all six runs.**
- One binary: the Release build of the PR 4 merge commit, published once to the share's `bin\`
  (`READY.txt` names it) and copied locally on each machine. Never rebuilt per machine (a different
  day stamps a different `osprey.version`; the two compiler paths can differ).
- Runner defaults: libdecoy, r1.0, protein-compact, model diagnostics on, FdrLaneResolver chooses
  lanes, tag `sprintfinal`. The i9s run `--threads 30`, files sequential, no tuning switches or
  environment variables.
- **MACS2 runs its optimal settings** (Brendan, 2026-10-13): `-Threads 72 -ParallelFilesScoring 4
  -ParallelFilesRescoring 8`, the "fast1" configuration from `TODO-20261006_osprey_seaad_benchmark_port.md`
  (SEA-AD 2 h 09 m vs 4 h 19 m at defaults). ~2x the i9s is expected and desirable. Not the 16 FDR lanes
  or 36 GC heaps: neither was shown to improve the total, and `Run-Chs.ps1` clears `OSPREY_FDR_FILE_LANES`.
- Library `target+decoy+entrapment-20260817` for both cohorts. `Run-Chs.ps1` has no `-LibraryBuild`
  and otherwise resolves the 07-27 set (different `search_hash`), so CHS passes `-LibraryDir`.
- Cold from the `.spectra.bin` caches; no `-LinkFrom`.

**Varies, by design.** The machine: cores, RAM, disks - and therefore the FirstPassFDR lane count
the resolver picks from free memory (an output, not a setting; record it). On MACS2 also the thread
count and per-stage file parallelism, which makes criterion 3 a check that parallel files give the
same answer as sequential.

**Measured per run.** Wall and per-task `[TIMING]` seconds; `perfviz.py` peak private and managed,
floor drift, reporting gaps >= 30 s; the lane line; exit code; protein groups at 1%; library
spectra written; and the products `out.stats.tsv`, `out.protein_groups.tsv`, `out.blib`, report HTML.

**Pass criteria.**
1. All six runs exit 0.
2. **UW25 CHS 446 completes** within 64 GB: peak private at or under physical RAM, floors flat or
   falling (no O(files) drift), no reporting gap that is a stall rather than known Percolator
   granularity (MACS2's 10-08 run had 30-58 s gaps there).
3. Same answer everywhere: per cohort, `out.stats.tsv` and `out.protein_groups.tsv` identical across
   machines, and `out.blib` equal under `Compare/Compare-Blib-Crossimpl.ps1` (two C# blibs work; the
   parameter names say Rust/C#). Lane counts differ per machine, so this also settles the cross-machine
   identity check left open in `TODO-20261006_osprey_seaad_benchmark_port.md`. A difference is a
   finding to bisect, not noise to tolerate.
4. No regression in wall time against each machine's earlier SEA-AD run in the same configuration
   (i9s: default runs; MACS2: fast1, 2 h 09 m),
   allowing for disk state (wall swings 31 -> 80 min on the regression gate here with disk state alone).

**Comparison.** UW8's session (or Brendan) compares once all `results\<machine>\RESULTS.md` files are
complete, and records the outcome below this section.

## Coordination

- #4710 (maccoss demux, port base) touches OspreyEnvironment, PerFileRescoreTask, ScoringTaskShared
- #4645: its investigation loses the projection-off / compacted-buffer A/Bs
- #4577 (library retained set, O(entries)) is out of scope but its gate text cites the Stage 6 switch
- `ResidentPaths.cs:125` still describes the retired stage7-stream-off oracle oddly - clean up in PR 3

## Progress Log

### 2026-10-13 (evening) - Merged PR 4

PR #4838 merged as 4c2eba1af8 (`osprey: Improved model-diagnostics regeneration to stream per run and
removed the planner's whole-experiment maps`). Shipped: admitted-decoy sets freed per run; experiment
records read once; the diagnostics fold reads four parquet columns per run into a reused `Row[]`
(`FirstPassFoldRows`, changed from parallel arrays to an array of structs on Brendan's review,
`904ddb0adb`); `FdrScoresSidecar.TryJoinRows` is the one join walk for the stub overlay and the fold;
the Stage 6 planner keeps no whole-experiment map (actions, consensus targets, refits, gap-fill).
Gates on the final head: unit 640/640, `regression-parallel -Dataset All` 48/0/0, cross-impl
Stellar Single + Astral All at 1e-9 (on `dc02532231`), TeamCity Perf/Regression #312 SUCCESS.
SEA-AD 82 regeneration 14m45s -> 8m12s (measured on `3295597cfb`). Issue #4664 stays open: its
500/1000-file acceptance is replaced by the three-machine runs (procedure and results on
`M:\home\brendanx\data\MacCoss\Osprey\acceptance-20261013`, `U:\data\...` on MACS2).

**Next session handoff**: UW8 night session for its acceptance leg - read
`ai/.tmp/handoff-20261013_uw8_acceptance_night.md` before starting work.

### 2026-10-13 - PR 4 code complete (4 local commits), all local gates green

Commits on `Skyline/work/20261012_osprey_mdiag_regeneration_bounds` (not pushed, no PR yet):
`2e1b36a6a0` (admitted-decoy sets freed per run; experiment records read once), `e03a84f8b6`
(planner whole-experiment maps removed), `3295597cfb` (diagnostics fold streams four columns),
`dc02532231` (`/code-review medium` fixes: shared `FdrScoresSidecar.TryJoinRows` walk used by
`TryRead` and the fold rows; planner counts refits and keeps them only for the opt-in dumps;
`LibraryStringInterner.Canonicalize`; geometric buffer growth; dead `Stage6Plan.Consensus`;
stale byproduct docs). Review's top finding (fragment release lost its gap-fill term) was not a
behavior change - the in-process path already passed null; docs corrected. Unit gate 640/640,
inspection clean, on each.

Gates on `dc02532231`: `regression-parallel -Dataset All` 48 PASS / 0 FAIL in 29m36s; cross-impl
Stellar Single and Astral All PASS at 1e-9. The SEA-AD numbers below were measured on `3295597cfb`
(before the review fixes changed the join path) and not re-measured.

- **Fold stream**: new `Osprey.Tasks/FirstPassFoldRows.cs` - per-run buffers REUSED across runs
  holding only entry_id/charge/is_decoy/modseq (via `ReadFdrStubScalars`, `SkipCoelutionSum`)
  plus score and run/experiment precursor+peptide q joined from `FdrScoresSidecar.ReadRecords`
  with `TryRead`'s rules (last row per entry_id wins; unmatched rows keep Score 0 / q 1; experiment
  q only on matched rows; unaccounted record fails unless `expectedAbsent`). PEP fed as 1.0, which
  is what every stub carried (sidecar has no PEP). `FoldPreCompactionPerRun` now takes the
  sequence pool and an `Action<int, string, FirstPassFoldRows>`; `LoadResumeStubs` moved into
  `RescoreHydration.LoadFoldRows`. Oracle: SubsetPipelineTest mode 11 (`AssertSameFirstPassProduct`).
- **SEA-AD 82 measurement** (same runner command, `-Tag pr4fold`, snapshot
  `_bin\pr4-foldstream-3295597`) vs `pr4base` (`_bin\pr4-baseline-d2b56e0`):

  | | pr4base (master) | pr4fold |
  |---|---|---|
  | total | 14m45s | **8m12s** |
  | pass-1 fold | 12m13s | **6m07s** |
  | managed peak | 12.7 GB | 11.9 GB |
  | private peak | 20.1 GB | 18.6 GB |

  Products: 2nd-pass JSON byte-identical; 1st-pass JSON and HTML identical except `generatedUtc`.
  Run dirs `D:\test\osprey-runs\sea-ad\runs\seaad-82files-libdecoy-r1.0-transferpr4{base-20261012_180149,fold-20261013_125127}`.
  The floor was already flat per run on master; the win is time (half the fold) and ~1 GB of peak.
- **Brendan's request done**: deleted 49 dirs under `D:\test\osprey-runs` (nores-routes, astral-*
  A/B, sea-ad 12/4-file drills, two older 82-file runs), freeing 616.6 GB. CHS caches copied to
  `D:\test\osprey-runs\chs-seer\raw` (446 `.spectra.bin` + carafe `.libcache`, 1,143 GB, robocopy
  0 failed); `Test-SpectraCaches.ps1` PASSED structurally (sources gone). `OSPREYDEV_CHS_DIR` is NOT
  set yet (README's `setx`).
- **Next**: push the branch and open PR 4 (ask Brendan first), TeamCity when asked, merge with `--admin`.
- **Acceptance deferred (Brendan, 2026-10-13)**: instead of issue #4664's 500/1000-file test, after
  the sprint's final PR merges, run SEA-AD and CHS-SEER on all three test machines (BRENDANX-UW8
  i9-14900/128 GB, BRENDANX-UW25 i9-14900/64 GB, MACS2 PowerEdge Xeon Gold 6354) against the final
  code. One snapshot exe copied to every machine, identical runner args with `-LibraryDir` pinned,
  cold runs from the caches, Dell agent checked first; compare with `perfviz.py`. UW8 has not run
  CHS before (caches staged 2026-10-13); the other two have.

### 2026-10-12 (late) - PR 4 started on `Skyline/work/20261012_osprey_mdiag_regeneration_bounds` (uncommitted)

Naming: issue #4664 is the ISSUE ("bound --task ModelDiagnostics memory for a 500-1000 file
regeneration on 64 GB"); "PR 4" is this sprint's fourth PR, not yet opened.

Survey of issue #4664 against master d2b56e0a51 (read-only agent): the co-assignment `Key` string is
gone (`PrecursorKey` reuses library strings); the panel reads no parquet; `_fileRows` are per file.
Left: `_admittedRunDecoys` never freed (runs x admitted decoys); the diagnostics-only fold loads each
run's WHOLE parquet into a `List<FdrEntry>` via `LoadFdrStubsFromParquet` (11 columns per row group;
the fold needs only entry_id/charge/is_decoy/modseq from the parquet - score and 5 q-values come from
the 1st-pass sidecar); `LoadFirstPassExperimentRecords` read twice back to back; the planner
accumulates the whole-experiment action map / consensus targets / gap-fill (order 13 GB at 446);
Stage 7 `WalkSurvivors` decodes modseq strings per row per run (time/garbage, not a pool - measure
first). `ReclampExperimentQToBestRun` is gone (Stage 7 uses `ExperimentQFloors`).

**Brendan chose scope: diagnostics fold + planner maps.** Done in the working tree (NOT committed):
- `_admittedRunDecoys`: builder `FlushFile(int fileIdx)` removes that run's set (both callers:
  PeakCoAssignmentSource and the batch oracle in CoAssignment.cs).
- `FoldDiagnosticsOnly`: experiment records read ONCE, shared by the fold and the panel (both read-only).
- Planner maps: `Stage6Plan` returns `int? ActionCount` (distinct (file,index) per file, same as the
  old map's Count); `ScanResult.PerFileConsensusTargets` gone (count kept); FirstPassFDR's
  `gapFillByFile` copy and four map fields gone; byproducts `PerFileConsensusTargets`,
  `ReconciliationActions`, `RefinedCalibrations`, `PerFileGapFillForRescore` replaced by
  `PlannedActionCount`; `ExecuteRescore` takes `int totalReconciliation`; library release passes a
  null gap-fill term (it already received null - `_perFileGapFillForRescore` was nulled one line
  before the release; regression mode 6 passes that way).
- Unit gate: compiles; 2 inspection warnings left (a redundant `using pwiz.Osprey.FDR.Reconciliation;`
  at PipelineByproducts.cs:30 and a redundant `(int?)` cast at Stage6Planner.cs:472) - fix interrupted.
  Tests have not yet run on this state.
- pwiz-ai: `SEA-AD/Run-SeaAd.ps1` and `TDP43/Run-Tdp43.ps1` now admit `-Task ModelDiagnostics` (the
  shared module already handled it).
- Baseline measurement LAUNCHED (background, may have finished): `Run-SeaAd.ps1 -Task ModelDiagnostics
  -Pass2Mode transfer -LinkFrom ...seaad-82files-libdecoy-r1.0-transfer-pr4665-20261009_205031 -Exe
  D:\test\osprey-runs\_bin\pr4-baseline-d2b56e0\Osprey.exe -Tag pr4base -Fresh` (snapshot of the master
  Release build); launcher log `ai/.tmp/sessions/20261012-pr4/mdiag-baseline-launch.log`.

Still to do in PR 4: the diagnostics fold stream (avoid the 11-column stub list: read only the needed
scalars with `ReadFdrStubScalars`-style streaming joined to the sidecar records, or at least trim the
loader's columns - preserve `FdrScoresSidecar.TryRead` overlay semantics exactly; the diagnostics
golden is the oracle); re-measure on SEA-AD 82 vs the baseline; regression, code review, cross-impl.
Acceptance for issue #4664 (500/1000 files on a 64 GB box) cannot run on this machine.

**Pending request from Brendan (not started):** clean up `D:\test\osprey-runs` and add a `chs-seer`
subfolder as `ai/docs/osprey-large-datasets.md` describes, copying the `.spectra.bin` files into its
raw folder from `M:\home\brendanx\data\MacCoss\Osprey\chs-seer\raw`.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20261012_osprey_mdiag_regeneration_bounds.md` before starting work.

### 2026-10-12 (evening) - Merged PR 3b

PR #4830 merged as d2b56e0a51 (squash, `--admin`, approved by Brendan; no review approval). Shipped:
the R1 fix, deletion of the all-runs reconciliation bundle, the whole-run survivor builds behind
`RescoredEntries.Value` (now throws), FirstPassFDR's resident projection arm, and the resident-pool
allowance (`ResidentPaths`, `OSPREY_ALLOW_UNFIXED_RESIDENT`, now refused as an unknown variable);
batch diagnostics and projection builders kept as internal test oracles. Gates on the merge candidate
460332883a: TeamCity Perf/Regression #309 SUCCESS; before the master merge, `regression-parallel -Dataset
All` 48/48 and cross-impl PASS (Stellar Single, Astral All). Copilot left a summary review with no
inline comments. **This TODO stays active.** Deferred, not shipped:
- FirstPassFDR's planner still builds the whole-experiment consensus-target / refined-calibration /
  gap-fill maps (order 13 GB at 446 runs), released by PerFileRescore's Consume - candidate for PR 4.
- `RunRescoreInputs.JoinFileStems` is read nowhere (pre-existing; see the afternoon entry).
- `ParquetScoreCache.LoadFullFdrEntries` / `HasPinFeatureColumns` are production-dead, IOTest-only.
- Next: PR 4 (#4664).

### 2026-10-12 (afternoon) - PR 3b on `Skyline/work/20261012_osprey_firstpass_rerun_stream` (4 local commits)

- **R1 fixed** (c45751d143): `PerFileScoringTask.Rehydrate` adopts no bundle when FirstPassFDR is in the
  pipeline, so `--task FirstPassFDR` over a finished dir takes the lean load. Repro added to
  `TestSubsetStraightThroughAndReruns` (summary deleted, re-run, summary byte-identical); it failed on
  master with `pre-compaction-pool: resident` + `all-runs-bundle: built runs=3`
  (`ai/.tmp/sessions/20261012-pr3b/repro-before.log`). Same commit: resident stubs loop,
  `HydrateReconciliationOverlay`, batch `ModelDiagnosticsReport.Write` (closes #4542 finding 1),
  `.gitignore` `/b.bat`, `/b[os].bat`, `/b[os]?.bat`.
- **Decision 5 (Brendan, 2026-10-12):** batch `ModelDiagnosticsData.Build` / `BuildPass2` made `internal`
  test oracles (Osprey.FDR exposes internals only to Osprey.Test). Same treatment for group C.
- **Reachability probes** (temporary throws, `PROBE-3B`): unit suite + `regression-parallel -Dataset All`
  48/48 twice (31:29, 54:52) with no probe hit (`probe-regression.log`, `probe2-regression.log`):
  join-only bundle hydrate, adopted bundle, FirstPassFDR bundle route, resident projection,
  BuildRescoredPool, MaterializeAllFromSource, both non-hydrate rescore arms. Only direct
  `RescoredEntries` unit tests reached the source-less ctor / `Files()`. Deletion map:
  `ai/.tmp/sessions/20261012-pr3b/deletion-map.md`.
- **Brendan approved deleting A and B in 3b; C = delete arm, keep oracle internal.**
  - A (abfe879ce1): all-runs reconciliation bundle route - RescoreBundle, RescoreInputs,
    HydrateCompactedStreaming, RescoreCompaction, AllRunsBundleGuardError, TallyPreCompaction; a run with
    no per-run route is refused before loading, naming the missing summary.
  - B (6c312b9a63): `RescoredEntries` is per-file only (`Value` throws); BuildRescoredPool,
    MaterializeAllFromSource, non-hydrate rescore arms, join-wide rescore dictionaries,
    OverlayReconciledIntoBuffer/File; LogKeys `all-runs-bundle` and `survivor-pool` and their absence checks
    (SubsetPipelineTest, regression.ps1).
  - C (39a9a87e58): FirstPassFDR's resident projection arm and `ReadApexRtsByParquetIndex`;
    `RunPercolatorFdr`, `BuildFromEntries`, `Builder` internal.
- Unit gate 638/638 + inspection clean after each group (`unit-gate-{a,b2,c}.log`).
- **Found, not fixed (pre-existing):** `RunRescoreInputs.JoinFileStems` is set from each run's envelope but
  never read, so a single-run PerFileRescoring worker stamps its reconciled parquet with the single-file
  hash; `ReconciledParquetWriter` docs say SecondPassFDR rejects that, yet the HPC-chain legs pass. Check
  which is stale.
- Docs commit 0280052aad (00, 07, 11, 15). Doc 07 had claimed both passes share `RunPercolatorFdr`;
  the second pass re-scores with the frozen first-pass model and trains nothing.
- **Brendan: fold the guard machinery into 3b** (not a separate 3c). e682111708: `ResidentPaths`,
  `OSPREY_ALLOW_UNFIXED_RESIDENT` (now refused as an unknown variable), the Program.cs warning,
  regression.ps1's allowance clearing and known-gaps table, `ResidentPoolGuardTest` ->
  `PerRunRoutingTest`. pwiz-ai: dev guide section rewritten, datasets doc,
  `SEA-AD/Measure-Stage6Rescore.ps1` passes `hpc-merge` only with the new `-LegacyAllowResident`
  (a current binary refuses the variable). Unit 638/638 + inspection clean (`unit-gate-g.log`).
- `regression-parallel -Dataset All` on A/B/C: **48/48** (`regression-abc.log`), 1:20:50 wall. The slow
  wall was disk, not code: the straight-through mzML parse ran at 7 MB/s. Same-session A/B on Stellar:
  master worktree 308 s, then the branch 152 s with mzML at 175-234 MB/s
  (`regression-stellar-master.log`, `regression-stellar-branch2.log`).
- `/code-review medium` (9 findings), triaged. FIXED in 4813bdd5a3: the dead all-runs gap-fill /
  refined-calibration envelope reader (and `RescoreHydration.ReadGapFillAndCalibrations`; both byproducts
  are plain holders now); the 30.8 M-tuple grouping built only for an action count; a double probe in
  FirstPassFDR's refusal; stale comments (CanHydratePerRun "KNOWN WART", SecondPassFDR ".Value BUILDS the
  pool", probe-the-disk bundle, LoadOwn/StreamOwn). DROPPED: regression.ps1 no longer clearing an inherited
  OSPREY_ALLOW_UNFIXED_RESIDENT (loud failure is the rule since #4825; tctest.bat does not set it); the
  BuildPerRunHydrate "uncaught exception" (DescribeFailure reports an InvalidDataException as its message +
  exit 1); the routing-defect throw (InvalidOperationException is right for a defect); JoinFileStems
  (pre-existing, recorded above). DEFERRED for Brendan: FirstPassFDR's planner still BUILDS the
  whole-experiment consensus-target / refined-calibration / gap-fill maps (order 13 GB at 446 runs, released
  by PerFileRescore's Consume, pinned through Stage 7 on the RefillOnly/DiagnosticsOnly arm) - planner
  surgery, candidate for PR 4 or a 3c. Unit 638/638 + inspection (`unit-gate-r.log`).
- Still open: `ParquetScoreCache.LoadFullFdrEntries` and `HasPinFeatureColumns` are production-dead
  (IOTest-only). Gates on 4813bdd5a3: `regression-parallel -Dataset All` 48/48 (`regression-final.log`, 1:19:19 - slow disk again);
  cross-impl PASS at 1e-9, Stellar Single 26,683 and Astral All 117,236 precursors (`xi-stellar-single.log`,
  `xi-astral-all.log`) - no parity break.
- **PR #4830 opened** (Brendan: push, open, trigger TeamCity). Master had moved 10 commits (incl. #4818 demux,
  #4810 warnings-as-errors); merged as 460332883a: unit 640/640 + inspection, Release build clean,
  `regression.ps1 -Dataset Stellar` PASS. TeamCity Perf/Regression build 4213020 on pull/4830 queued.

### 2026-10-12 - Merged PR 3a

PR #4825 merged as 6ce733caba (squash, `--admin` approved by Brendan; no review approval).
Shipped: R3/R4 (older-build reconciled parquet rejected at the stamp read; `--task SecondPassFDR`
refused up front), deletion of the eager resume arm, the resident SecondPassFDR rehydrate and every
Stage 7 resident branch, R5, and the unknown-`OSPREY_*` startup check (`KnownVariables`), with
tooling variables moved to `OSPREYDEV_*`. TeamCity #307 ran on bd9338cf1c (48/48); the last commit
5267ef9236 was doc-only. **This TODO stays active:** next is PR 3b (R1 + the deferred whole-pool
builders, `ExecuteRescore` null-loader arm, decision 5), then PR 4.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20261012_osprey_no_resident_pools_pr3b.md` before starting work.

### 2026-10-11 (afternoon) - PR 3a on `Skyline/work/20261011_osprey_resident_routes` (uncommitted)

Cross-impl baseline PASS on master (Stellar Single, Astral All) after two harness fixes - see PR 3
PLAN step 1. Then, on the branch (`C:\proj\pwiz`, nothing committed yet):
- **R3/R4 (one defect):** `ParquetScoreCache.ReadStamp` returns null for a `.scores-reconciled.parquet`
  not in the current survivor shape (same open as the stamp), so every currency check rejects an
  older-build parquet: a resume re-scores that run; `--task SecondPassFDR` refuses UP FRONT in
  `PerFileScoringTask.LoadJoinOnlyScores` (`ScoringTaskShared.UnstreamableJoinError`, reusing the
  existing summary / reconciled-parquet messages via `SecondPassFdrTask.UnusableReconciledParquetsError`).
  Repro added to `TestSubsetRescoreResume` (forged pre-#4486 parquet keeping the current stamp); it
  failed on master with `all-runs-bundle: built runs=3` + stack trace, passes now
  (`ai/.tmp/sessions/20261011-pr3/repro-before.log`, `repro-after4.log`).
- `AnalysisPipeline` no longer adds a second "could not reload its results" error after a task's
  own rehydrate refusal (`RehydrateFailedException` -> return its exit code; Program's exit
  reconciliation still catches a silent one).
- **Deleted:** `MaterializeAllResumedFiles` + the eager resume arm (now a named refusal),
  `MaterializeResumedFile`'s overlay arm, the `--task SecondPassFDR` resident Rehydrate arm
  (bundle `ProteinFdrEngine.RunFirstPass` + `RescoreCompaction.Apply`), every Stage 7 `!Streams`
  branch (`WarnResidentStage7Join` -> `RequireStreamedJoin` throws; `OverlayPass2OntoResidentPool`,
  `ReloadPass2Sidecars`, `residentByFile`/`LoadOneFile` resident arm, batch
  `ModelDiagnosticsReport.WritePass2AndFinalize`), 8 resx strings.
- **R5:** deleted OSPREY_DUMP_RESCORED / _MULTICHARGE / _RECONCILIATION + `*_ONLY` (interface,
  writers, `EntriesForDump`, `-d` bundle). Docs 05/09/10/11/14/15/18, `Test-Snapshot.ps1` stage6
  (C# gets only consensus), `DIAGNOSTICS.md` updated.
- **Unknown `OSPREY_*` check:** `OspreyEnvironment.KnownVariables` (98 names) +
  `UnrecognizedVariables()`; Program.cs refuses any other set OSPREY_* name (replaces the four
  `*RetiredSet` refusals). `CodeInspectionTest.TestOspreyVariablesAreRegistered` keeps the list and
  the readers in step both ways; CommandLineErrorTest covers retired, Rust-only and misspelled names.
  - Found on first run: pwiz-ai tooling uses the OSPREY_ prefix for its own config (dataset dirs,
    roots, exe paths), 4 of them in Brendan's User env. **Brendan: rename them** -> `OSPREYDEV_*`.
    User env renamed on this machine (OSPREYDEV_SEAAD_DIR/LIB, OSPREYDEV_TDP43_DIR/LIB); scripts
    + docs renamed (33 files). `OSPREY_SIGN*` (pwiz `package.ps1`, `README.md`) -> `OSPREYDEV_SIGN*`
    too: Brendan confirmed TeamCity code signing is not implemented and nothing sets them.
- Rename fallout fixed in pwiz-ai: `OspreyDatasetRun.psm1` exported OSPREY_PROTEIN_COMPACT_QUALIFY and
  OSPREY_SVM_C_VALUES, which NO build reads (so `-QualifyBy experiment` / `-SvmCValues` silently ran
  the default arm under another directory name) - now refused; same for the Demux scripts'
  OSPREY_DEMUX_ENGINE / OSPREY_DIAG_SEED; `Run-Osprey.ps1 -DiagCalPrefilter*` refuses `-Tool CSharp`;
  OSPREY_TEST_CULTURE and OSPREY_PARQUET_STRESS_ITERS -> OSPREYDEV_*.
- `/code-review medium`: 10 findings. FIXED: pre-compaction warning moved below the per-run arms (also
  removes the false "every file in memory" line on the HPC SecondPassFDR node), platform-correct
  name comparison, stress-test var rename, stale references. DROPPED: env-var breakage (reviewed
  before the rename), loader-null resume (only with zero files), silent rehydrate failure (exit
  reconciliation logs), retained-summary read (reader already format-checks), stamp-vs-validity-key
  altitude (a key bump would re-score every user's parquets), Run-arm non-streamed milestone
  (no gated route reaches it - regression 48/48 with RequireStreamedJoin armed).
- Gates: unit 646/646 + inspection (`unit-gate-6.log`); `regression-parallel -Dataset All` 48 PASS /
  0 FAIL / 0 SKIP in 29:58 (`regression-all.log`, build before the review fixes); `regression.ps1
  -Dataset Stellar` PASS on the final build (`regression-stellar-final.log`). Logs in
  `ai/.tmp/sessions/20261011-pr3/`.
- Cross-impl re-run on the branch: Stellar Single **PASS**, Astral All **PASS** (1e-9; 117,236 precursors;
  Rust 18:50, C# 6:32) - matches the step 1 baseline, no parity break
  (`ai/.tmp/sessions/20261011-pr3/xi-*-branch.log`).
- Committed bd9338cf1c (rebased on master cc074faf83; unit 646/646 re-run), pwiz-ai fe87c719.
  **PR [#4825](https://github.com/ProteoWizard/pwiz/pull/4825)** opened 2026-10-11 ~19:50. TeamCity
  Perf/Regression build 4212056 (`pull/4825`, Agent 1) triggered at Brendan's request (night session).
  **TeamCity PASSED** - build #307 on bd9338cf1c: 48 PASS / 0 FAIL / 0 SKIP in 40:04. Copilot: 5
  comments, 1 fixed (5267ef9236, docs/14 count, doc-only), 4 declined with replies; all resolved.
  All 13 PR checks green, MERGEABLE. **Ready to merge** (needs `--admin`; ask Brendan).
- Demux conflict on push: another session's unmerged demux branches read OSPREY_DEMUX_* in C#, so my
  Demux-script refusals were dropped (upstream versions kept). Those branches must add their names
  to `KnownVariables` - `TestOspreyVariablesAreRegistered` will say so.
- Deferred to PR 3b (R1): the whole-pool builders `BuildRescoredPool` / `MaterializeAllFromSource`
  now have no production `.Value` reader; turning them into a refusal needs a probe of the
  worker's `Files()` paths first. Also `ExecuteRescore`'s null-loader arm.

### 2026-10-11 - Merged PR 1 and PR 2

#4820 merged as 3a5a0a5d00 and #4821 as a78f88b5a4 (squash, `--admin` approved by Brendan; no review
approval on either).
- #4820 retired `OSPREY_STAGE6_STREAM_SURVIVORS` and `compacted-entries-buffer`, moved the compaction
  count check into `SurvivorCountCheck`, and fixed the master flake in `TestSubsetDiagnosticsWithoutReanalysis`.
- #4821 retired `OSPREY_FDR_PROJECTION=0` (~3,700 lines), `projection-off` (`KNOWN_UNFIXED` is now
  empty), `OSPREY_DUMP_PERCOLATOR` and `OSPREY_PERCOLATOR_ONLY`.
- Neither had a banked A/B: both resident oracles already aborted in Stage 7. The golden is the oracle.
- #4821 was stacked on #4820's branch. After #4820's squash it was retargeted to master, and master was
  merged in. Every conflict resolved to the branch side; master's Osprey tree equalled #4820's final
  head, and the merge left #4821's tree byte-identical to the TeamCity-tested head.
- Issue comments: #4664 (co-assignment measurement), #4542 (finding 1 still live until PR 3), #4463
  (one emitter left), #4511 (resident 2nd-pass route gone; sections 2-4 unaffected).

**Deferred to PR 3:**
- `ModelDiagnosticsReport.Write` / batch `ModelDiagnosticsData.Build` (decision 5)
- `MaterializeResumedFile` overlay arm
- `HydrateReconciliationOverlay`
- the allowance plumbing (`OSPREY_ALLOW_UNFIXED_RESIDENT`, `NamesResidentPath`)

**Due now in pwiz-ai** (Osprey refuses these variables at startup):
- `scripts/Osprey/Test-Snapshot.ps1` stage5 mode and `Profile-Stage5.sh` set `OSPREY_PERCOLATOR_ONLY`.
  C# needs `--task FirstPassFDR` as the stop point; Rust still honors the variable, so the harness
  needs a per-tool branch.
- `DIAGNOSTICS.md` and `docs/osprey-development-guide.md` still document the retired variables.

### 2026-10-11 - pwiz-ai brought in line with master

- `docs/osprey-development-guide.md`:
  - "Memory bounding" rewritten as a retired-switch table: all three A/B switches are refused at
    startup, `KNOWN_UNFIXED` is empty, and the section explains why no final A/B was banked.
  - Dump table and bisection step 10 mark `OSPREY_DUMP_PERCOLATOR` / `_PERCOLATOR_ONLY` Rust-only.
  - Stale `PercolatorFdr.cs` citations repointed to `PercolatorEngine` / `PercolatorTrainer` /
    `PercolatorQValues`.
- `scripts/Osprey/DIAGNOSTICS.md`: the two percolator variables are marked Rust-only.
- `scripts/Osprey/Test-Snapshot.ps1` stage5:
  - C# now stops with `--task FirstPassFDR` and keeps its standardizer/subsample/svm_weights dumps.
  - The percolator variables and the percolator-dump comparison are Rust-only.
  - The script parses, but has NOT been run end to end: this machine has no Stellar `_snapshots`.
- `scripts/Osprey/Profile-Stage5.sh`:
  - The C# arm used the long-retired `--join-at-pass=1`; it now uses `--task FirstPassFDR`.
  - `OSPREY_PERCOLATOR_ONLY` is exported for the Rust phase only.
  - `bash -n` passes; not run.
- `Measure-Pipeline.ps1` and the `Test-Snapshot` scrub lists only UNSET the variables, which is
  still correct, so they are unchanged.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20261011_osprey_no_resident_pools_pr3.md` before starting work.
