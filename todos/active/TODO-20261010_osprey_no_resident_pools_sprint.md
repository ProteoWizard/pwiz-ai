# Sprint: remove every O(files x entries) data structure from Osprey

## Branch Information
- **Branch**: `Skyline/work/20261010_osprey_retire_compacted_buffer` (PR 1; later PRs get their own
  branches off master, listed here as they start)
- **Base**: `master`
- **Created**: 2026-10-10
- **Status**: In Progress. PR 1 and PR 2 MERGED 2026-10-11 (#4820 as 3a5a0a5d00, #4821 as
  a78f88b5a4). PR 3 waits on Brendan's route decisions (memo + experiments below); PR 4's premise
  measured stale (see PR 4). The pwiz-ai follow-up from #4821 is DONE (2026-10-11).
- **GitHub Issue**: (none - catalogue rows A1-A3, A6-A8 in TODO-osprey_parity_path_retirement.md; #4664)
- **Module**: `osprey`
- **PR**: [#4820](https://github.com/ProteoWizard/pwiz/pull/4820) (PR 1, merged 2026-10-11), [#4821](https://github.com/ProteoWizard/pwiz/pull/4821) (PR 2, merged 2026-10-11); PR 3 / PR 4 not started
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
- [ ] `MaterializeResumedFile` overlay arm - **NOT switch-only, moved to PR 2**: a null loader also
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
- [ ] **(DEFERRED to PR 3 shared tail - PR 2 only reworded their comments)** `MaterializeResumedFile` overlay arm + `MaterializeAllResumedFiles` null-loader path (moved
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
- [ ] R1 `--task FirstPassFDR` re-run over a dir with `.reconciliation.json`: resident stubs load +
      all-runs `HydrateReconciliationOverlay` + `BuildFromEntries` (PerFileScoringTask ~1509-1529,
      ~2088; FirstPassFdrTask ~3191)
- [x] R2 `OSPREY_DUMP_PERCOLATOR` - gone with PR 2
- [ ] R3 `--task SecondPassFDR` with `CanStreamStage7Join` false for disk reasons (no current
      summary / stale reconciled parquet): `HydrateCompactedStreaming` all-runs + resident Stage 7
      + `ProteinFdrEngine.RunFirstPass` over the bundle
- [ ] R4 straight-through resume or PerFileRescoring worker with no current summary: all-runs
      bundle (`AllRunsBundleGuardError` returns null by design) + eager `MaterializeAllResumedFiles`
- [ ] R5 `OSPREY_DUMP_RESCORED` reads `rescored.Value`; also `DUMP_MULTICHARGE` / `DUMP_RECONCILIATION`
Then delete the shared tail:
- [ ] Stage 6 non-streamed arms (`PlanStage6` `_survivorsStreamed` false, `Stage6Planner.Plan(List)`,
      `ExecuteRescore` loader-null, `BuildRescoredPool` early return)
- [ ] Stage 7 resident join: `!rescored.Streams` branches in Pass2FdrSidecar (reload, residentByFile,
      LoadOneFile resident arm), `OverlayPass2OntoResidentPool`, `ReloadPass2Sidecars`,
      `WarnResidentStage7Join`, `WritePass2AndFinalize(rescored.Value)` + batch pass-2 builders,
      `RescoredEntries` resident fallbacks (`Files()`, no-op Drop/Materialize)
- [ ] Guard machinery: `ResidentPaths.cs`, `AllowUnfixedResident` / `NamesResidentPath`, Program.cs
      unknown-token warning (keep a retired-variable refusal), regression.ps1 known-gaps block,
      `$cannotStreamJoin`, the `finally` restore; CommandLineErrorTest, SubsetPipelineTest ~1179
- [ ] Docs: 00 (~1325), 07 (177, 183), 12 (198), osprey-development-guide 1038-1126

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

- [ ] `_fileRows` / `_byPrecursor` retained for the whole apex-RT join: 13.95 M rows at 446 runs,
      ~31 M at 1000. Bound it (fold per precursor, or a disk-backed join) without changing the panel
- [ ] Parquet.Net per-row-group arrays under it (hand the caller one row group at a time, the
      `ReadFdrStubScalars` shape)
- [ ] #4664 acceptance: 500-file and 1000-file `--task ModelDiagnostics` regeneration on a 64 GB box,
      products unchanged, per-phase peaks from perfviz.py; then close #4664 (with #4577's status noted)

## Coordination

- #4710 (maccoss demux, port base) touches OspreyEnvironment, PerFileRescoreTask, ScoringTaskShared
- #4645: its investigation loses the projection-off / compacted-buffer A/Bs
- #4577 (library retained set, O(entries)) is out of scope but its gate text cites the Stage 6 switch
- `ResidentPaths.cs:125` still describes the retired stage7-stream-off oracle oddly - clean up in PR 3

## Progress Log

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
