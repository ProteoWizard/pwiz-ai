# TODO-20260713_osprey_model_diagnostics_memory -- Stream Stage-6 planning + --model-diagnostics so memory does not scale with run count

## Branch Information
- **Branch**: `Skyline/work/20260713_osprey_diagnostics_memory`
- **Base**: `master`
- **Created**: 2026-07-13
- **Status**: In Progress (PR #4419 open; Deliverable A + memory ceilings + fail-fast; B is a follow-up)
- **Raised by**: Brendan (2026-07-13, after the 82-file run OOMed on a 64 GB box)
- **GitHub Issue**: (pending)
- **PR**: #4419 (https://github.com/ProteoWizard/pwiz/pull/4419)

## Problem
Two independent all-runs-resident memory ceilings block 82-file (SEA-AD Astral, ~2x entrapment
library) processing on 64 GB. BOTH are addressed in this branch (scope: A+B, one PR).

1. **Stage-6 reconciliation PLANNING amasses all runs' CWT candidates at once** (the actual 82-file
   death point -- see Findings). `Stage6Planner.PlanReconciliation` -> `CwtCandidateLoader.Load`
   builds `Dictionary<file -> List<List<CwtCandidate>>>` for ALL files, each list indexed to that
   file's FULL pre-compaction parquet row count, held simultaneously on top of the ~12-18 GB
   post-Stage-5 live floor. This is the deferred lever #4378 / #4394 both flagged
   ("perFileCwtCandidates loaded at once during planning, planner indexes one file at a time ->
   streamable, NOT done").
2. **`--model-diagnostics` forces the RESIDENT first-pass pool** at the FirstJoin
   (`FirstJoinTask.cs:274` `needsResidentFirstPassPool`) -- the pool the projection streaming path
   (#4400, default) was built to DROP. So memory scales with run count DIFFERENTLY with the flag.
   20 files WITH --model-diagnostics peaks ~60 GB; 82 files would OOM at the FirstJoin resident pool.

## Goal
Make an 82-run SEA-AD run feasible on 64 GB both WITHOUT and WITH `--model-diagnostics`, with memory
NOT scaling with run count differently than a normal run. Streaming, byte-identical default path.

## Findings (2026-07-13 session) -- empirical root cause of the 82-file OOM
From `D:\test\Pilot-MTG-Tissue-May2026\runs\pass2ab-82file-percolator\run.log`
(START `mdiag=False`, `OSPREY_PASS2_QVALUE=''`, `--fdrbench-pass 2`):
- NONE of the three `needsResidentFirstPassPool` triggers fired. Line 5478 confirms the PROJECTION
  streaming path (`RunStreamingIntoProjection: 344,615,472 rows`) -- ceiling #2 above was never in play.
- Progressed through: first-pass compaction `344,615,472 -> 12,405,655`, multi-charge consensus
  (344,364 to rescore), consensus RTs, and calibration refit `82/82 files` (LAST line logged).
- Died `exit=-1` at 371 min. The next phase after calibration refit is `PlanReconciliation` ->
  `CwtCandidateLoader.Load` (all-82-files CWT load). The run never reached the per-file rescore loop.
- => The true 82-file blocker (no-mdiag) is ceiling #1 above (Stage-6 planning CWT all-files load),
  NOT --model-diagnostics and NOT the rescore reload. Do it first, in this branch.
- `#4406` probe: post-Stage-5 live floor ~12-18 GB at 82 files (12.4M post-compaction stubs +
  library + interned peptides). Fits 64 GB; the all-files CWT load on top is what breaks it.

## Plan (A + B, one PR)
### Deliverable A -- stream reconciliation-planning CWT load (unblocks the no-mdiag 82-file run)
1. `CwtCandidateLoader.ValidateAllInRange(...)`: cheap PARQUET-METADATA-only pre-pass (footer row
   counts, no blob decode, no residency) preserving the current all-or-nothing gate
   (`perFileCwtCandidates.Count == perFileEntries.Count`).
2. `ReconciliationPlanner.Plan`: take a lazy `Func<string, IReadOnlyList<IReadOnlyList<CwtCandidate>>>`
   loader; load each file's candidates inside the per-file loop (line ~149/192, which already touches
   only the current file's candidates), release after -- one file resident at a time, not 82.
   Byte-identical: cross-file inputs (`passingBaseIds`, `consensusMap`) do not use CWT candidates.
   Reuse Mike's #4400 callback pattern + #4406 `Release` where applicable.
### Deliverable B -- stream --model-diagnostics accumulation (ceiling #2; enables diagnostics-on 82-file)
Fold each file's contribution into the report's histograms / FDP-yield curves / feature contributions
on the projection path instead of forcing the 344M resident FdrEntry pool. Keep byte-identity of the
default (no-flag) path. (Design TBD after A; the report needs aggregate-shaped data, not per-entry.)

## Validation
- `--memstamp` per phase; confirm no phase's private MB scales with run count once streamed.
- Byte-identical default path: `regression.ps1 -Dataset Stellar` (mode1/2/3, 1e-9); `Test-PerfGate.ps1`.
- 82-file feasibility: hard-link the Stage-5 caches from `pass2ab-82file-percolator` into a fresh dir
  (skips Stage 1-4; first-pass FDR re-runs ~30-60 min to reach the Stage-6 wall), run the new build
  with `--memstamp`; confirm it clears Stage 6 on 64 GB. Then a WITH-`--model-diagnostics` resume for B.

## References
- `Stage6Planner.cs:267` (`CwtCandidateLoader.Load`), `ReconciliationPlanner.cs:149/192`,
  `CwtCandidateLoader.cs`, `ParquetScoreCache.LoadCwtCandidatesFromParquet`.
- `FirstJoinTask.cs:274` (needsResidentFirstPassPool), #4400 (projection streaming callback pattern),
  #4406 (PipelineContext.Release), #4394 / #4376 (reconciliation transients; deferred reload lever),
  #4378 (memory bounding; names Stage 6 as the remaining ceiling).
- Companion: `TODO-osprey_progress_reporter_heartbeat.md` (the ~1 h silent Stage-6 phase in this run).
- This session's 82-file OOM log + `ai/.tmp/pass2ab-20file-results.md`.

## Progress Log

### 2026-07-13 - Deliverable A implemented + byte-identical; 82-file validation launched
Streamed the Stage-6 reconciliation-planning CWT load (commit `d6116709ef`, branch pushed):
- `ParquetScoreCache.ProbeCwtRowMetadata` (footer-only rows + cwt-field probe, no blob decode).
- `CwtCandidateLoader`: `Load` (eager all-files) -> `ValidateAllInRange` (metadata-only gate,
  same all-or-nothing decision + warnings) + `LoadOneFile` (per-file streaming loader).
- `ReconciliationPlanner.Plan`: new `Func<>` streaming overload (one file resident at a time);
  dict overload kept as a zero-churn adapter (10 ReconciliationTest sites untouched).
- `Stage6Planner.PlanReconciliation`: metadata gate + lazy loader, same gate logic + log strings.
- Drive-by: fixed the now-ambiguous `<see cref="ReconciliationPlanner.Plan"/>` in OspreyFileDiagnostics.
Gates: build net472+net8.0 0 warnings; inspection 0 warnings; 507 tests (504 pass/3 skip);
`regression.ps1 -Dataset Stellar` mode1/2/3 **byte-identical PASS** (golden blib 45,064,192).
Perf gate deferred until after the 82-file validation (Release-DLL lock).
82-file validation: `ai/.tmp/run-82file-memfix.ps1` hard-links the pass2ab-82file-percolator
Stage-5 caches into `runs/pass2ab-82file-memfix` (ValidityKey=search+library, no build hash ->
Stages 1-4 skip), runs the branch Release build with `--memstamp --timestamp` (output in
`run.err.log`), detached PID 16968. Watching for it to clear the Stage-6 planning wall.

### 2026-07-13 - Heartbeat + granularity; 82-file resume OOM root-caused to a THIRD ceiling; resume-lean fix
Heartbeat (commit `e138f7a04d`) + finer granularity (commit `5825c4889e`): the slow-phase heartbeat
now prints `N.NN% (done/total, elapsed)` (Brendan's ask -- a moving count, not just a clock). Caveat:
only fires when the phase calls Report; a silent bulk load needs a reporter wrapped first.
82-file resume (PID 16968) thrashed: silent 53 min, private commit climbed to 102.9 GB / 4.1 GB free,
WS trimmed to 2-3 GB -- killed it. Root cause is NOT the Stage-6 fix and NOT --model-diagnostics: the
pure straight-through RESUME path `PerFileScoringTask.RehydrateFromOwnOutputs` loaded the full fat
FdrEntry stubs + PIN features for all 82 files (~53-58 GB) with NO lean branch -- the exact cost #4400
removed for the Run path, still paid on resume (a THIRD memory ceiling). It's a silent bulk load (no
Report), so it looked hung; my concurrent Debug build tipped it into an unrecoverable page-fault spiral.
Fix (folded in, user-approved): gave `RehydrateFromOwnOutputs` the same `needsResidentPool`-gated
lean/fat branch as `Run` -- extracted `NeedsResidentPool(config)` (shared by both) + `LoadCalibrationAndIsolation`
(cheap cal/iso load reused by both), stream 32 B FdrProjection rows via `ReadFdrStubScalars` unless an
opt-in output needs the resident pool. Wrapped the all-files load in a ProgressReporter (the silent
phase now reports per-file). Byte-identical (regression mode2/resume covers it; running).
Gates: build 0 warnings (my files; the 9 SystemMemory.cs are the known #4379 local flake, CI green);
508 tests (505 pass/3 skip). `regression.ps1 -Dataset Stellar` running (mode2 exercises the lean resume).

Resume-lean committed `a0453d28eb`; `regression.ps1 -Dataset Stellar` mode1/2/3 **byte-identical PASS**
(golden blib 45,064,192; mode2 exercises the lean resume). Branch pushed.

### 2026-07-13 - Resume-lean VALIDATED in real-time; HPC merge/join had the SAME fat-stub bug (Brendan)
Clean 82-file resume relaunch (PID 32564) with the fixes: the `Loading scored entries` phase REPORTED
PROGRESS (...89/91/93/95/98/100%) instead of the silent 58 GB hang, completed `344,615,472 total scored
entries` (totalScored from projections.TotalRows -> lean path ran), and reached `Running First-pass
Percolator ... projection streaming ingest` -- past the exact load that thrashed the fat run. CommitFree
44 GB (vs 4 GB when it thrashed). Resume-lean fix confirmed working end-to-end.
Brendan flagged: the RESUME path I fixed is the single-machine case, but `LoadJoinOnlyScores` (the
`--input-scores` path) is the **HPC merge/join node**, and it had the SAME unconditional fat-stub +
features load -- a large HPC first-pass merge would blow up Stage 5 the same way. Folded in the same
lean fix: `LoadJoinOnlyScores` now returns the `FdrProjectionSet` and streams via `ReadFdrStubScalars`
when `!NeedsResidentPool && !AllHaveReconSidecars` (extracted `AllHaveReconSidecars` from
HydrateRescoreBundleIfPresent; the reconciled 2nd-pass bundle merge stays fat -- it overlays q onto the
stubs and FirstJoin skips Percolator there). Caller captures projections -> FinalizeAndCheck.
**regression mode3 (HPC chain == straight) exercises exactly this path** and gates its byte-identity.
Status: HPC-merge fix coded; Debug build + regression DEFERRED until the 82-file resume frees Release
(hands-off during its heavy phases). Watching it clear the Stage-6 CWT wall.

### 2026-07-13 - 82-file resume CLEARED the Stage-6 CWT wall end-to-end (Deliverable A validated on real data)
The clean resume (PID 32564) reached and passed the exact point the original run OOM'd:
`Reconciliation calibration refit: 82/82` (the original's last line) -> `Reconciliation: 6,472,914
per-(file, entry) actions planned` (NEVER appeared before -- CwtCandidateLoader now streams per-file).
Planning took ~5 min and memory DROPPED after (58 -> 54 GB), vs the original's ~1 h thrash -> commit
OOM. Then reconciliation rescore (6.47M actions) -> 2nd-pass/protein FDR -> blib write (5M+ entries),
memory stable ~60 GB, no OOM. All THREE memory ceilings cleared on the 82-file set: resume fat-stub
load, Stage-6 CWT planning, (HPC-merge same pattern, gated by mode3). The full run is long (~4 h+, the
inherent 82-file cost + a slow large-blib write under memory pressure -- a possible future MergeNode/
blib-write memory lever, separate from these fixes), but the memory validation is done.
Progress-granularity follow-up (Brendan): the two silent first-pass Percolator gaps are countable
344M-row loops -> RunStreamingIntoProjection flat-array build + BuildTrainingSubset (~5 min) and
ScoreProjectionAndComputeFdrInPlace (~15 min, per-file). Wrap both in ProgressReporter (per-file/
per-chunk, NOT per-row -- Report locks) w/ the fractional+count line; byte-identical (console only).

### 2026-07-13 - 82-file run COMPLETED (first ever); PR finalization
`Analysis complete in 3 hours 55 minutes`, clean exit, NO OOM. Outputs: `out.blib` 387,657,728 bytes
(65,762 library spectra from 5,385,957 passing entries), `fdrbench.tsv` 8.27 MB (pass-2, 90,463 rows).
2nd-pass Percolator 3,690,474 T / 36,785 D @1%; 8,648 protein groups @1% protein FDR. Rescore was the
dominant cost (10,643s ~3h); 2nd-pass FDR 1,055s. This is the result Mike's #4400 alone couldn't reach
on the resume path -> the PR narrative.
Progress reporters (Brendan approved "include in this PR"): score pass wrapped in a ProgressReporter
(`ScoreProjectionAndComputeFdrInPlace`, manual create/Report/Dispose, per-file -- covers the 15-min
gap + trips the heartbeat on a slow file); two `logInfo` phase markers for the ~5-min Gap-1 span
(training-subset select + subset feature load) in `RunStreamingIntoProjection`. Console-only, byte-identical.
Compile + 508 tests green (Debug); `regression.ps1 -Dataset Stellar` running (Release build compile-verifies
the HPC-merge fix + reporters; mode2/3 gate byte-identity). PR description drafted: `ai/.tmp/pr-osprey-memory.md`.

### 2026-07-13 - /pw-self-review: four findings, fail-fast hardening; regression re-green
Fresh-context self-review of the branch flagged 4 items; Brendan's directive on the parity call was
**"Fail fast. Partial but wrong is not an improvement"** (old skip-all-reconciliation is ALSO wrong --
must abort and stop; ideal user action = delete the bad parquet + regenerate). All 4 addressed:
- **(1) [high]** Stage-6 CWT gate wasn't equivalent on a *decode-failing* parquet. `CwtCandidateLoader`
  `ValidateAllInRange` + `LoadOneFile` now THROW `InvalidDataException` (naming the file, "delete the
  affected .scores.parquet and re-run") on missing / unreadable / out-of-range / undecodable candidates,
  instead of skipping reconciliation for that file and silently keeping its peaks. `Stage6Planner` gate
  simplified (no more "skipped X/Y" partial branch).
- **(2) [medium]** Lean resume dropped the fat path's `features.Count != stubs.Count` guard (streaming
  scalars never loads features). Restored an equivalent up-front check via a footer-only
  `ParquetScoreCache.HasPinFeatureColumns` probe (no feature memory) on BOTH the lean resume
  (`RehydrateFromOwnOutputs`) and HPC-merge (`LoadJoinOnlyScores`) paths -- a parquet missing the PIN
  feature schema stops the run ("delete it and re-run to regenerate"). Deliberately NOT applied to Run's
  fresh-compute lean path (#4400, parquets the same run just wrote).
- **(3) [low]** `AllHaveReconSidecars` TOCTOU: computed once in the merge path and threaded to both the
  loader (lean/fat choice) and `HydrateRescoreBundleIfPresent`, so a sidecar appearing between two disk
  reads can't make them disagree.
- **(4) [low]** ProgressReporter heartbeat/elapsed formatting -> `CultureInfo.InvariantCulture`.
Tests: `TestHasPinFeatureColumnsRejectsFeaturelessParquet` (Parquet.Net-built features-less parquet is
rejected) + a positive assertion in `TestParquetScoreCacheRoundTrip` (valid parquet passes; pins the
writer/probe column-name agreement so a rename can't silently reject every real run).
Gates: build net472+net8.0 0 warnings (my files; the 9 SystemMemory.cs are the known #4379 local flake);
**509 tests** (506 pass/3 skip); `regression.ps1 -Dataset Stellar` mode1/2/3 **byte-identical PASS**
(golden blib 45,064,192 -- guards inert on valid inputs; mode2=resume, mode3=HPC-merge exercise them).

### Next (PR)
- Commit the self-review fixes -> `Test-PerfGate.ps1` -> `gh pr create` (open to kick TeamCity + Copilot)
  -> address Copilot findings -> trigger the TeamCity Osprey Perf/Regression on the PR ref (Astral).
- Move this TODO active-header Status to In Progress w/ the PR link once opened.
- Deliverable B (stream `--model-diagnostics`, the original headline) is NOT in this PR -- its own follow-up:
  it still forces the resident pool (`needsResidentPool` includes ModelDiagnostics) and builds the report
  from all pre-compaction entries. Would need per-file feature-histogram streaming + its own WITH-mdiag run.
