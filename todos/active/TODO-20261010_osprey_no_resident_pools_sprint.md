# Sprint: remove every O(files x entries) data structure from Osprey

## Branch Information
- **Branch**: `Skyline/work/20261010_osprey_retire_compacted_buffer` (PR 1; later PRs get their own
  branches off master, listed here as they start)
- **Base**: `master`
- **Created**: 2026-10-10
- **Status**: In Progress - PR 1 started. Precondition met: #4816 merged 2026-10-10 as 5a1cd82efc
- **GitHub Issue**: (none - catalogue rows A1-A3, A6-A8 in TODO-osprey_parity_path_retirement.md; #4664)
- **Module**: `osprey`
- **PR**: (pending)
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
- [ ] Update #4601 and #4577 text that cites `OSPREY_STAGE6_STREAM_SURVIVORS`
- [ ] `ai/docs/osprey-development-guide.md` cites the switch - update with the PR
- Gate so far: `Build-Osprey.ps1 -Configuration Debug -RunTests -RunInspection` green, 649/649

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
- [ ] `MaterializeResumedFile` overlay arm + `MaterializeAllResumedFiles` null-loader path (moved
      here from PR 1: projection-off is what still reaches them)
- [ ] Coordinate #4511 first: its streaming-vs-resident parity check uses this path - do it now or
      rewrite it against the golden
- [ ] PerFileScoringTask: `NeedsResidentPool`, `GuardResidentPool`, `ResidentPoolGuardError`,
      `ResidentPoolTrigger`, the fat loads in Run / RehydrateFromOwnOutputs / LoadJoinOnlyScores
- [ ] FirstPassFdrTask: legacy Run branch (~722-820), `RunPercolatorFdr(List)` facade,
      `RunFirstPassProteinFdr`, `WriteFdrScoresSidecars`, resident `WriteFdrBenchPass1IfRequested`,
      `CompactFirstPass` non-bundle branch, the resident refusal and overlay arms
- [ ] Osprey.FDR: `PercolatorEngine.RunPercolatorFdr(List)`, `DispatchSvm`, `ApplyPercolatorResults`,
      `RunPercolatorStreaming`; `PercolatorEntryBuilder.cs` (move `BuildBasicFeatures` first - used
      by PercolatorScorer ~1845); `PercolatorScorer.ScorePopulationAndComputeFdr`. CHECK
      `ProteinFdr.RunFirstPassProteinFdr` / `ProteinFdrEngine.RunFirstPass` - also called by
      PerFileRescoreTask ~1046 on the bundle path (PR 3)
- [ ] Already dead: resident `PercolatorEngine.ClampExperimentQToBestRun` (only FdrTest calls it),
      the uncalled `RunPercolatorFdr(FdrProjectionSet)` facade
- [ ] Drop `OSPREY_DUMP_PERCOLATOR` / `OSPREY_PERCOLATOR_ONLY` and `WriteStage5PercolatorDump`
      (decision 2); update DIAGNOSTICS.md and Test-Snapshot references
- [ ] `ModelDiagnosticsReport.Write` + batch `ModelDiagnosticsData.Build`: delete, or keep test-only
      behind an explicit test flag (decision 5)
- [ ] Tests: ResidentPoolGuardTest, PercolatorEntryBuilderTest, FdrTest (779, 833, 1165, 1242, 1298,
      3436), LibraryFragmentReleaseTest 176-232, ModelDiagnosticsDataTest oracle uses
- [ ] #4463: one of its two wrong emitters goes; finish the experiment-level count or update it
- [ ] #4542 finding 1 resolved by deletion; update the issue

## PR 3 - the untokened resident routes, then the shared tail (catalogue A3, A6, A7, A8)

Each route reviewed with Brendan before implementing (decision 3):
- [ ] R1 `--task FirstPassFDR` re-run over a dir with `.reconciliation.json`: resident stubs load +
      all-runs `HydrateReconciliationOverlay` + `BuildFromEntries` (PerFileScoringTask ~1509-1529,
      ~2088; FirstPassFdrTask ~3191)
- [ ] R2 `OSPREY_DUMP_PERCOLATOR` - gone with PR 2
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
