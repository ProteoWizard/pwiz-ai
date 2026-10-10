# Sprint: remove every O(files x entries) data structure from Osprey

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
   was done for `OSPREY_STAGE7_STREAM`.
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

~170 prod + ~70 test lines, no blockers.
- [ ] Bank the A/B with `OSPREY_STAGE6_STREAM_SURVIVORS=0 OSPREY_ALLOW_UNFIXED_RESIDENT=compacted-entries-buffer`
- [ ] Delete `PerFileScoringTask.Stage6ResidentHandoffGuardError` (~2420-2468) and its calls
- [ ] FirstPassFdrTask: guard calls + conditional releases (~852-874, ~1080-1104) -> unconditional;
      `ReloadFirstPassSurvivors` (~3980-4044) + 2 resx strings
- [ ] Fold `StreamedSurvivorLoader` into `PublishedSurvivorLoader` (PerFileRescoreTask ~2884-2896)
- [ ] Remove `Stage6StreamSurvivors` + `Stage6StreamSurvivorsValidityKeySuffix` (OspreyEnvironment
      ~342, ~404-419) and its PerFileRescoreTask validity-key term (~293)
- [ ] `MaterializeResumedFile` overlay arm (PerFileRescoreTask ~3293) - reached only under the switch
- [ ] Startup refusal for the retired variable (precedent `Stage7StreamRetiredSet`, Program.cs ~590)
- [ ] Remove `COMPACTED_ENTRIES_BUFFER` from `ResidentPaths.KNOWN_UNFIXED`; ResidentPoolGuardTest
      `AssertStage6HandoffGuard` (~384-449); TaskValidityKeyTest:671; regression.ps1 416/2203
- [ ] #4544 finding 3: assert the streamed rebuild's survivor count matches what compaction retained
- [ ] Update #4601 and #4577 text that cites `OSPREY_STAGE6_STREAM_SURVIVORS`

## PR 2 - retire `projection-off` (`OSPREY_FDR_PROJECTION=0`, catalogue A1)

~1,050 prod lines. Note projection-off ALSO takes the resident Stage 6 handoff and resident
Stage 7 (its survivor loader is null), so those arms stay live until PR 3.
- [ ] Bank the A/B with `OSPREY_FDR_PROJECTION=0 OSPREY_ALLOW_UNFIXED_RESIDENT=projection-off`
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
