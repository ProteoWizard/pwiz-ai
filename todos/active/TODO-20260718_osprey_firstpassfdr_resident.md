# TODO: Osprey FirstPassFDR resident memory bounding (Increment 2)

## Branch Information
- **Branch**: `Skyline/work/20260718_osprey_firstpassfdr_resident`
- **Base**: `master`
- **Created**: 2026-07-18
- **Status**: Stage B COMPLETE -- primary goal achieved (first-pass resident memory FLAT in files); PR ready for review + gates green. Awaiting human review + Brendan's manual TeamCity Perf/Regression trigger.
- **PR**: [#4435](https://github.com/ProteoWizard/pwiz/pull/4435) (ready for review; Stage A + Stage B landed)

**Priority**: High -- the ONE goal: make `--task FirstPassFDR` memory FLAT in file count.
PR #4434 (merged) bounded the TRANSIENT + trimmed constants (-15 GB LIVE @82f, byte-identical)
but did NOT touch the O(files) RESIDENT core. At 500 files the resident set is still ~140 GB
and grows linearly -- the blocker to a 500-file run.
**Predecessor**: `TODO-20260717_osprey_firstpassfdr_memory_peak.md` (completed, PR #4434).

## Execution plan (2026-07-18 session) -- staged, each byte-identical-gated

Code re-traced on master@#4434 and CONFIRMED the design. Splitting Increment 2 into two
byte-gate-able stages (lowest-risk first). The full O(rows) resident set to eliminate is
THREE buffers, all O(pre-compaction rows n ~= 344M @82f), not two:
`FdrProjectionSet.PerFile` (32 B/row) + `FdrProjectionOutputs` (16 B/row) + the flat
`labels/entryIds/peptides/bestScores[n]` arrays in `RunStreamingIntoProjection` (~7 GB @82f;
the design's "1c", DEFERRED by #4434, NOT shipped).

Key facts verified this session:
- The phase-1 sidecar record ALREADY carries `run_peptide_qvalue` (FdrStoringSink.AcceptOutput
  writes `q.RunPeptideQvalue` to slot [20..28]); phase-2 patches `run_protein_qvalue` [52..60].
  So the finalized `.1st-pass.fdr_scores.bin` holds Score + ALL 5 q-values keyed by entry_id.
  => `FdrProjectionOutputs` (RunPeptideQ+RunProteinQ) is 100% redundant with the sidecar.
- `FdrProjectionOutputs` has exactly 4 readers: ProteinFdr.CollectBestPeptideScores +
  RunFirstPassProteinFdr (RunPeptideQ), ComputeFirstPassBaseIds (both), and
  PatchFirstPassSidecarProteinQvalues (RunProteinQ). Rewrite those 4 -> the array is gone.
- Modseq source = `ParquetScoreCache.ReadFdrStubScalars(path, onRow(entryId,charge,isDecoy,
  coelutionSum,modseq))` -- light per-row callback, no full FdrEntry. Same parquet column
  peptideById was interned from (value-identical => byte-identical string keys).
- `IsDecoy == (EntryId & DECOY_ID_BIT 0x80000000) != 0` holds by construction (decoys minted
  `target.Id | 0x80000000`; base_id = `& 0x7FFFFFFF`; target/decoy pairs share base_id). So
  compaction can run purely from the sidecar's entry_id (verify via the byte gate).
- CAVEAT: `ScoreProjectionAndComputeFdrInPlace` + `RunStreamingIntoProjection` + the flat
  arrays + `FdrProjectionSinkBase.Accept/Finish` are SHARED with the 2nd pass
  (`FdrStreamingSink`, --task SecondPassFDR). The 2nd-pass projection is O(survivors ~12.4M),
  NOT the 82->500 blocker, and must stay resident for Stage 7/8. => Stage B (streaming the
  score pass) must be a 1st-pass-ONLY path (fork/parameterize the row source), higher blast
  radius. `FdrProjectionOutputs` is 1st-pass-only, so Stage A is cleanly isolated.

**Stage A (LOW risk, do first): drop `FdrProjectionOutputs`; stream the 3 consumers from disk.**
Score pass + training + resident `FdrProjection[]` UNCHANGED (backstop). Rewrite protein FDR
(detectedPeptides + bestScores from sidecar Score/RunPeptideQ joined w/ parquet-scalar modseq/
IsDecoy), the propagate+phase-2 patch (entry_id->PeptideQvalues[modseq] from parquet scalars),
and compaction (entry_id/RunPeptideQ/RunProteinQ from the finalized sidecar). Add a light
`FdrScoresSidecar` per-file record reader (entry_id -> record) that needs no FdrEntry stubs.
Proves the disk-streaming reconstruction (modseq source + protein-group ordering) in isolation.
Removes the 16 B/row array (~34 GB @500f). Gate: regression `-Dataset Stellar` byte-identical.

**Stage B (HIGH risk): drop the resident `FdrProjection[]` + flat arrays; stream the 1st-pass
score pass + training from parquet (`LoadJoinOnlyScores`).** 1st-pass-only path so the 2nd
pass keeps its resident survivor projection. This is where resident goes FLAT. Gate:
`-Dataset All` byte-identical + FDRBench + the 16f/82f LIVE measurement.

### Progress log
- **2026-07-18 Stage A DONE (byte-identical, committed):** Dropped `FdrProjectionOutputs`.
  - Added `FdrScoresSidecar.ReadRecords(path, pass, onRecord)` -- streaming per-file record
    reader, no FdrEntry stubs; decode single-sourced with `WriteRecord` via `DecodeRecord`.
  - Added pure `ProteinFdr.FirstPassProteinFdrAccumulator` (Add/Finish) + extracted
    `ProteinFdrEngine.LogFirstPassSummary`. Deleted the 3 dead projection overloads
    (`RunFirstPassProteinFdr`/`CollectBestPeptideScores`/`PropagateRunProteinQvalues`) +
    `ProteinFdrEngine.RunFirstPass(projection)`.
  - `FirstJoinTask.RunFirstPassProteinFdrStreaming` (+ `StreamFirstPassFileScores`): pass 1
    reductions from sidecar(Score,RunPeptideQ) x parquet-scalar(modseq,IsDecoy); pass 2 patches
    run_protein_qvalue from PeptideQvalues[modseq] (folds the old propagate + phase-2 patch).
    `ComputeFirstPassBaseIds` streams the finalized sidecar (IsDecoy from the entry_id decoy bit).
  - Removed `FdrProjectionOutputs` class + the sink's `_outputs`/`Outputs`/`SetRunPeptideQvalue`.
  - Gates: Build Debug + ReSharper 0 warnings; 513 unit tests PASS; `regression.ps1 -Dataset
    Stellar` mode1/2/3 byte-identical PASS.
  - NOTE (perf, revisit at Stage B / perf gate): Stage A adds ~2 parquet + ~2 sidecar reads
    per file to the FirstPassFDR path (protein-FDR pass1+pass2 re-read parquet for modseq;
    compaction re-reads the sidecar) WITHOUT yet a memory win (projection still resident) --
    it's the prove-the-plumbing stage. The memory win lands in Stage B. Watch Test-PerfGate.
  - SELF-REVIEW (fresh-context agent, clean byte-identity verdict): 1 MEDIUM fixed
    (StreamFirstPassFileScores now skips a parquet row absent from the sidecar instead of
    aborting -> matches the survivor reload's superset tolerance; byte-neutral). 2 LOW noted,
    no change (OSPREY_PROTEIN_FDR_ONLY patches before exit = diagnostic-only; parquet 3x
    re-read = deliberate memory tradeoff). Confirmed clean: reduction equivalence, modseq
    source, decoy-bit invariant, patch-before-compaction, record layout, log order.
- **2026-07-18 Stage B STARTED** (Brendan: proceed now, one gated commit). 1st-pass-only
  streaming score/reduction/emit off parquet (LoadJoinOnlyScores); recompute SVM score per
  streamed row (no finalScores[n]); rewrite the bounded-lookup builders
  (ComputePepWinnerMap/ComputeExperiment*/ComputePerFileRunQvalues) to consume streamed rows;
  drop resident FdrProjection[] + flat labels/entryIds/peptides/bestScores[n]. Fork from the
  shared 2nd-pass path (keeps its O(survivors) resident projection). Gate: -Dataset All +
  FDRBench + 16f/82f LIVE measurement; Test-Snapshot for bisection if red.
  - DONE (957d21a64): extracted `CompeteFromDicts` (+winnerBaseIds) shared compete+sort finish.
  - DONE (811a29113): `PercolatorFdr.StreamingFirstPassQ` (exp-prec/exp-pept/PEP maps by pushing
    rows) VERIFIED byte-identical to the flat builders by `TestStreamingFirstPassQMatchesFlat`
    (514 tests + inspection green). The riskiest Stage-B math is now proven in isolation.
  - REMAINING (the pipeline-touching wiring; see `ai/.tmp/stageB-design-20260718.md` NEXT §):
    per-file run-q streaming (trivial reuse) -> 1st-pass-only streaming score path (2 passes,
    recompute score, sink Accept gets peptide+charge) -> training subset off parquet ->
    producer stops building the projection -> drop resident projection/flat arrays/finalScores
    -> gate -Dataset All + FDRBench + measurement. All committed pieces are pipeline-untouched
    (branch green); the wiring is the next focused push.
  - **Next session handoff**: For detailed startup protocol, read
    `ai/.tmp/handoff-20260718_osprey_firstpassfdr_resident.md` before starting work (it points at
    `ai/.tmp/stageB-design-20260718.md`, which has the exact NEXT wiring steps + byte-identity invariant).
- **2026-07-18 Stage B WIRING DONE (byte-identical, committed 3fba794c3 + 7562e2fcd):** The
  1st-pass score pass now streams off parquet with NO resident FdrProjection[] -- resident memory
  is projection-free (the O(files) blocker is gone). Two commits:
  - `3fba794c3` (kernel + sink contract, pipeline unchanged): `IFdrOutputSink.Accept` takes
    charge+peptide as args (so the sink needs no resident row); `FdrProjectionSet` gains a
    counts-only shape (`CountsOnly`/`RowCount`/`IsCountsOnly`); `PercolatorFdr.RunStreamingFirstPass`
    -- the 1st-pass-only fork: 3 streaming passes over a row-source delegate (pass 0 = streaming
    best-per-precursor dedup captured w/ identity, sorted ascending-g == SelectBestPerPrecursor,
    then SubsampleByPeptideGroup + RunPercolator; pass 1 = score + StreamingFirstPassQ + per-file
    run-q -> clamp floors; pass 2 = re-score + assign 5 q + sink.Accept). Score recomputed per row
    (no finalScores[n]); reuses ComputePerFileRunQvalues/UpdateExperimentQClampFloor/StreamingFirstPassQ
    unchanged. `RowBuffer` (bounded one-file buffer) + `ComputeStreamedScore` keep the stream
    callbacks closure-clean. **`FdrTest.TestStreamingFirstPassMatchesProjection`** pins it
    byte-identical to the resident projection path on a multi-obs fixture with a FORCED
    peptide-grouped subsample (MaxTrainSize=60 < 80 dedup) -- the ONE path Stellar/Astral don't
    reach (they're under the 300K subsample threshold).
  - `7562e2fcd` (the flip): the 3 lean producers (Run / resume Rehydrate / merge-node
    LoadJoinOnlyScores) build a counts-only projection (Builder(countsOnly:true) -> file names +
    row counts, no rows, no PeptideById). FirstJoinTask.RunFirstPassProjection branches on
    `IsCountsOnly` -> `PercolatorEngine.RunFirstPassStreaming` (row source =
    `ReadFdrStubScalars(perFileParquetPaths[name])`, features via loadFileFeatures). 2nd pass +
    the fat 1st-pass path keep the resident `ScoreProjectionAndComputeFdrInPlace` unchanged.
  - **GATE: `regression.ps1 -Dataset Stellar` PASS all 3 modes byte-identical** (mode1 vs golden,
    mode3 HPC chain==straight, mode2 resume==straight; all blibs 45,064,192 bytes). 515 unit tests
    + ReSharper 0-warning inspection green. Covers BOTH producer paths (in-process + --input-scores)
    and straight/resume/HPC.
  - LOAD-BEARING invariant (holds, gate-confirmed): parquet row order == the resident sort order on
    the 1st pass (parquet is (entry_id,charge,scan)-sorted), so streaming in parquet order
    reproduces the resident (EntryId,Charge,ParquetIndex) sort exactly (incl. competition
    first-seen tie-breaks).
  - NOTE (pre-existing, out of scope): the global row ordinal `g` is `int`, matching the resident
    path's `int n` array indexing -- both cap at ~2.1B pre-compaction rows. Stage B is memory-flat;
    widening ordinals to `long` for >2B-row runs is a separate follow-up (82f @ 344M rows is safe).
  - REMAINING before PR-ready: `-Dataset All` (Astral leg) byte-identical + the 16f/82f LIVE memory
    measurement (prove FLAT: FdrProjection[] block GONE, first-pass-fdr-live flat 16f->82f vs the
    reference O(files) 13.35 GB @82f projection-built) + `/pw-self-review` + mark PR #4435 ready.
- **2026-07-18 Stage B COMPLETE + all gates green; PR #4435 READY (commit ca94388d4 = self-review fixes):**
  - GATES: `regression.ps1 -Dataset Stellar` PASS mode1/2/3 (blibs 45,064,192) + `-Dataset Astral`
    PASS mode1/2/3 (blibs 135,249,920) -- full `-Dataset All` byte-identical. 515 unit tests +
    inspection green. `TestStreamingFirstPassMatchesProjection` proves the FORCED-subsample path.
  - MEMORY (SEA-AD 82-file, OSPREY_LOG_MEMORY LIVE gc_heap post-GC) -- FLAT proven:
    projection-built 2.28 GB @16f -> 2.59 GB @82f (was 13.35 GB @82f resident);
    first-pass-fdr-live 2.65 @16f -> 2.35 GB @82f; transient peak gc_heap 9.35 -> 9.75 GB. All flat
    despite 5x rows (68M->344M). 82f exit 0, 45.9 min, compaction 344M->12.4M survivors.
  - dotMemory 20f before(3fba794c3 resident)/after(Stage B), same lean-lib+Stage A -> ISOLATES the
    FdrProjection[] elimination: stage5-start 4.88->2.28 GB, first-pass-fdr-live 4.70->2.31 GB
    (delta ~2.6 GB = the resident FdrProjection[]). .dmw at ai/.tmp/firstpassfdr-20f-stageB-{before,after}.dmw
    (open side-by-side in the GUI). Both produce identical FDR output; the 20 .1st-pass.fdr_scores.bin
    sidecars are BYTE-IDENTICAL 20/20 (at-scale HRAM subsample-path byte proof; subsumes FDRBench).
  - SELF-REVIEW (fresh agent): 2 fixes committed (null-modseq normalize in RowBuffer.Add;
    FdrStoringSink.OnFinish hard-fail on short streamed count) + [PATH] log dedup; 1 documented
    tradeoff (1st-pass features read 2x = memory-for-IO trade; watch Test-PerfGate).
  - FOLLOW-UPS (out of scope, note in a backlog TODO): (1) widen the int row ordinal `g` to long for
    >2.1B-row runs (pre-existing cap shared with the resident path); (2) Test-PerfGate the extra
    parquet re-reads; (3) fix firstpassfdr-dmw.ps1 hardcoded inner log name (breaks concurrent runs).
  - NEXT: human review + Brendan's MANUAL TeamCity Perf/Regression trigger on pull/4435 (do NOT self-trigger).
- **2026-07-18 review rounds done; PR still green.** Copilot (3 comments) fixed in `5e45a8ef4`
  (StreamFirstPassFileScores doc skip-not-fault; null sidecarBase guards in StreamFirstPassFileScores
  + ComputeFirstPassBaseIds); replied + resolved all 3 threads. Full-branch `/pw-self-review` at HEAD
  found 1 MEDIUM (Stage A `StreamFirstPassFileScores` fed raw null modseq to the protein-FDR
  Dictionary key -> crash; the earlier Stage-B-scoped self-review had skipped Stage A) fixed in
  `df1084f93` (normalize modseq->"" at the pass-1 callback + pass-2 patch lookup; byte-neutral).
  Self-review otherwise clean + confirmed both prior fix rounds correct. Open follow-up it raised:
  `--model-diagnostics` uses the streaming accumulator on main/merge but forces the resident batch
  report on resume (PRE-EXISTING asymmetry from #4355/#4377, not Stage B) -- worth a "are the two
  reports identical" check someday, out of scope here.
- **2026-07-18 PERF HANDOFF (next session): measure before-vs-after wall clock for --task FirstPassFDR.**
  The memory win is proven + PR is review-ready; the ONE remaining question is the SPEED cost.
  Expected: streaming reads each file's 21 PIN feature columns 2x on the 1st pass (recompute-score-per-row,
  no finalScores[n]) -> some slowdown; but at 82f the freedom from GC/allocation pressure may offset or
  win, and the whole point was to make 500+ files feasible on a 64 GB box (prohibitive before).
  - BEFORE = commit `3fba794c3` (pre-flip resident FdrProjection[], SAME lean-lib + Stage A -> isolates
    Stage B's perf effect; matches the dotMemory before/after). AFTER = branch HEAD.
  - Data already captured (task-time, NOT perf-clean -- profiler and/or concurrent load): AFTER 82f
    `firstpass-mem-n.ps1 -MaxFiles 82` = 45.9 min / FirstPassFDR:done 2753.3s (--threads 8, no profiler);
    AFTER 16f = 8.5 min / 509.4s. 20f under dotMemory + contention: before 1454.2s vs after 1376.7s
    (NOT reliable). Need CLEAN uncontended reps.
  - **Next session handoff**: read `ai/.tmp/handoff-20260718_osprey_firstpassfdr_resident_perf.md` for the
    exact perf-run protocol (rebuild the before worktree, the two datasets, the timing harness, reps).
- **2026-07-18 PERF MEASURED (before-vs-after, --task FirstPassFDR; uncontended, no profiler).**
  BEFORE = `C:\proj\pwiz-stageb-before` @ `3fba794c3` (resident `FdrProjection[]`, same lean-lib + Stage A);
  AFTER = branch HEAD `df1084f93`. Driver `ai/.tmp/perf-ab-driver.ps1` (serial, interleaved B/A per rep;
  wraps `firstpass-mem-n.ps1`; parses `[TASK] FirstPassFDR:done (Ns)`). Both Release net8.0.
  - **16f (clean, 3 reps, median):** BEFORE 422.5 s vs AFTER 481.1 s = **+13.9%** (min-vs-min +10.6%; mean
    +4.7% but mean is dragged by BEFORE's cold-cache rep1=528.1 s, the sweep's first run). This is the pure
    algorithmic cost (both fit RAM): the streaming path re-reads the 21 PIN feature columns 2x on pass 1.
  - **82f (1 pair only — sweep killed at 93 min during BEFORE rep2):** BEFORE 2922.7 s (48.7 min) vs AFTER
    2661.8 s (44.4 min) = **-8.9% (AFTER faster)**, but CONFOUNDED: BEFORE ran cold (first run), AFTER ran
    warm (cache primed by BEFORE) -> biased toward AFTER. True 82f delta is between the clean 16f +14% and
    this -9%; heavier BEFORE GC at scale (managed heap 21.8 GB vs AFTER 5.7 GB) gives real GC relief that
    pulls it below +14%, plausibly ~parity. NOT a proven crossover (needs a warm B/A pair to nail).
  - **Memory @82f (Stage 5 start / projection-built, the resident peak) — the decisive result:**
    BEFORE working_set 36.3 GB / committed 28.7 GB / peak_paged 37.8 GB / live managed 12.7 GB;
    AFTER working_set 15.2 GB / committed 11.5 GB / peak_paged 15.9 GB / live managed 2.6 GB.
    Reduction **WS -21 GB (-58%), committed -17 GB (-60%)**. (Brendan observed ~52 GB *system* live = 36 GB
    process + ~16 GB OS/file-cache; no paging at 82f — prior work already put BEFORE under the wall here.)
  - **64 GB crossover (2-point fit, 16f+82f):** BEFORE peak_paged slope ~0.37 GB/file -> crosses 64 GB at
    **~154 files** (committed ~211f); at 200f BEFORE peak ~81 GB, at 300f ~118 GB (severe paging). AFTER
    committed slope ~0.038 GB/file -> 200f ~20 GB, 300f ~20 GB, 500f ~27 GB (WS: 300f ~31 GB, 500f ~45 GB),
    crosses 64 GB only at ~760+ files. **=> on this 64 GB box BEFORE tops out ~150-210 files (below the
    200-300f target); AFTER enables 200-500f with headroom.** Directly answers the sizing question for the
    planned 200-300f runs.
  - **Verdict vs Brendan's criterion (~10% FDR-task slowdown acceptable for 500-file headroom without
    paging):** cost is <= ~10-14% clean (16f), likely less at scale; memory win unlocks exactly the runs
    BEFORE can't do. Clears the bar. PerFile scoring (not FDR) dominates 82f wall clock, so this FDR-task
    delta is a small slice end-to-end.
  - Artifacts (Brendan handles the PR comment): driver `ai/.tmp/perf-ab-driver.ps1` (fixed a median bug --
    PowerShell `[int]1.5`=2 returned the max not the middle; now `[int][math]::Floor`). Run logs under
    `D:\test\osprey-runs\_firstpassmem_{16f,82f}_p{16,82}{Before,After}N\firstpassfdr-mem-*.log`. BEFORE
    worktree `C:\proj\pwiz-stageb-before` (3fba794c3) LEFT IN PLACE (kept for a clean warm 82f pair if
    wanted; remove with `git -C C:/proj/pwiz worktree remove --force C:/proj/pwiz-stageb-before`).
  - OPEN (optional): one warm B/A 82f pair (~1.5 h, pre-warm cache then B then A both warm) would replace
    the confounded -8.9% with a trustworthy headline timing number. Not required for the merge decision.

- **2026-07-19 A/B overnight run + progress-reporting fix (PUSHED).** Ran the full pass2ab A/B on the
  82-file SEA-AD Astral set with the branch's memory work:
  - **A (percolator+mdiag, fresh from mzML, v4 spectra):** exit 0, 10h 2min, PEAK private 44.1 GB / managed
    29.1 GB -- vs the 7/14 pre-#4434/#4435 reference ~100 GB (paged). --model-diagnostics now takes the
    STREAMING first-pass path, so the ~100 GB spike is GONE; runs in 64 GB with ~20 GB headroom. Perfviz:
    PerFileScoring 45-50->35, FirstPassFDR 102.5->39, PerFileRescoring 50-60+->25-30 GB.
  - **Progress-reporting fix (commit 56a726124, PUSHED):** wrapped the 6 previously-silent streaming
    first-pass phases (Pass-1 score, Pass-2 q-assign, subset-load, protein-FDR reduce/patch, compaction) in
    ProgressReporter -- log-only, byte-identical -- so --timestamp/--memstamp perfviz has no multi-minute
    gaps. Gates: 16f FirstPassFDR shows all 6 labels; regression Stellar mode1/2/3 byte-identical; 515 tests +
    inspection clean. Rebased onto Brendan's master-merge (#4428); Brendan reruns TeamCity Perf/Regression.
  - **B (transfer, resume from A):** resume worked (skip Stage 1-4, ~6h saved, v199 override matched A's
    parquet) but **OOM'd at the 82 GB commit ceiling at 46% of loading the resident pool** (managed 80.5 /
    private 82.2 GB, fully paged) -> killed, machine recovered. Transfer (Pass2TransferQ) + mdiag-on-resume
    BOTH force the resident fat pool; the #4435 streaming doesn't apply (resident fork). Confirmed reason the
    82-file transfer arm never completes. Transfer is experimental (default=percolator=A, which works).
    Deferred to a transfer-arm streaming fix -> [[TODO-osprey_transfer_mdiag_resume_resident_streaming]].
  - **Deferred to a NEW memory sprint (NOT this PR):** Stage-6 O(files) survivor-buffer slope + Stage-7
    SecondPassFDR 45 GB peak -> [[TODO-osprey_stage6_rescored_buffer_streaming]]; transfer/mdiag-resume
    resident pool -> [[TODO-osprey_transfer_mdiag_resume_resident_streaming]].

- **2026-07-19 FirstPassFDR 82f before/after -- CLEAN 3-rep median (supersedes the earlier confounded pair).**
  BEFORE (`3fba794c3` resident) median **2641.3 s** vs AFTER (`df1084f93` pure streaming, NO progress fix)
  median **2913.6 s** = **+10.3%** (streaming slower, +272.3 s). Runs: BEFORE {3004.8 cold, 2625.7, 2641.3},
  AFTER {3078, 2668.4, 2913.6}; AFTER has ~15% run-to-run variance (2668-3078). Ran detached via Start-Process
  (a background-bash driver was harness-reaped twice mid-sweep -- see [[feedback_night_session_detached_runs]]).
  - SCALING: **16f +13.9%, 82f +10.3%** -> streaming costs a steady ~+10-14% on the FirstPassFDR task; modest
    GC-relief narrowing at 82f, NOT a crossover (the killed sweep's -8.9% was the cold-BEFORE/warm-AFTER
    artifact + AFTER's high-outlier rep1). Essentially AT Brendan's ~10% tolerance line.
  - VERDICT: acceptable -- small end-to-end (FirstPassFDR is a slice; PerFileScoring dominates the wall clock),
    bought by the memory win (A 44 GB vs ~100 GB reference + flat-in-files headroom to 500 files). Brendan
    handles the PR #4435 comment.
  - END-TO-END dilution (from the Osprey-workflow.html 3-file regression perf table, median-of-3): stage5
    (1st-pass FDR) is only **27% of the Stellar total** (1:01 / 3:42) and **6.4% of the Astral total**
    (1:08 / 17:38), so the +10% streaming cost is **+2.7% end-to-end on Stellar, +0.6% on Astral** -- well
    under 10%, negligible on the hram Astral case where scoring/reconciliation dominate. This is the settled
    trade-off characterization: a small single-stage cost to make FirstPassFDR memory-BOUNDED (O(1) in files)
    instead of the O(files) resident path that thrashes then FAILS at scale (B proved it: 82 GB commit-ceiling
    OOM at 46% load). The change is clearly worth it. (No full-pipeline A/B run needed -- the stage breakdown
    settles it; Test-PerfGate vs the 07-08 perfbase would conflate the streaming with all other recent work.)

## The goal (Brendan)
FirstPassFDR resident memory bounded in file count -- flat from 82 -> 500 files, not linear.
The transient q-value arrays are already gone (PR #4434). The remaining O(files) RESIDENT
structures must be dropped: `FdrProjection[]` (~210 MB/file -> ~105 GB @500f) and
`FdrProjectionOutputs` (~68 MB/file -> ~34 GB @500f).

## Why they're resident today (code-traced)
After the score pass, `FirstJoinTask.RunFirstPassProjection` (FirstJoinTask.cs:~1530) holds the
projection + outputs resident because two consumers read them across ALL rows:
1. **First-pass protein FDR** -- `ProteinFdr.RunFirstPassProteinFdr(projections.PerFile,
   PeptideById, outputs, fullLibrary, config)` (ProteinFdr.cs:~842; called FirstJoinTask.cs:~1653).
   Reads per row: `proj.Score`, `outputs.RunPeptideQvalue`, `IsDecoy`, `peptideById[PeptideId]`
   (modseq), protein IDs (from the library by base_id).
2. **Compaction predicate** -- `ComputeFirstPassBaseIds(projections, outputs, config)`
   (FirstJoinTask.cs:~1812; called ~1689). Reads per row: `IsDecoy`, `EntryId`,
   `outputs.RunPeptideQvalue`, `outputs.RunProteinQvalue`.

## THE KEY FINDING -- feasibility CONFIRMED (code-traced): the resident buffers are REDUNDANT
Both consumers read ONLY data already on disk in the per-file `.1st-pass.fdr_scores.bin`
sidecar + the parquet stub + the library:
- The sidecar record (`FdrScoreRecord`, Osprey.IO/FdrScoreRecord.cs) already carries per row:
  entry_id (decoy bit in 0x80000000 => IsDecoy + base_id), score, run_precursor_q, run_peptide_q,
  exp_precursor_q, exp_peptide_q, pep, run_protein_q (filled by the phase-2 patch).
- The parquet stub (`ParquetScoreCache.LoadFdrStubsFromParquet` / `ReadFdrStubScalars`) carries
  entry_id + modseq -- the EXACT source `PeptideById` was interned from (use THIS, not the
  library, for the modseq so the peptide string is the identical interned instance).
- The library gives protein IDs by base_id.
So the resident `FdrProjection[]` + `FdrProjectionOutputs` can be DROPPED and both consumers
stream per-file from disk.

## The Increment-2 flow (no resident projection / outputs)
1. **Score pass** (already bounded by PR #4434): stream parquet rows (`LoadJoinOnlyScores`, 32 B)
   + features; compute score + the bounded q-value lookups; write the full sidecar per file via
   the sink. Do NOT build the resident projection or the `outputs` array (run_peptide_q lives in
   the sidecar).
2. **Protein FDR**: stream (parquet-stub modseq/proteins + sidecar score/run_peptide_q) per file
   -> O(proteins) best-score reduction -> protein-group q -> patch each entry's run_protein_q in
   the sidecar (this IS the existing phase-2 patch). Bounded (O(proteins)).
3. **Compaction**: stream the sidecar (entry_id, run_peptide_q, run_protein_q) -> passing base_id
   set. Bounded.
4. **Survivor reload**: already streams from parquet + sidecar (unchanged).
5. **Training-subset selection** (`PercolatorEngine.RunStreamingIntoProjection`, ~670): best-per-
   precursor dedup + peptide subsample -- also stream from parquet (bounded reductions), so the
   flat `finalScores`/`entryIds`/`peptides` input arrays go too.

Result: FirstPassFDR resident = library (lean, ~1.4 GB) + bounded lookups
(O(base_ids)+O(peptides)+O(proteins)) + one file's transient. ~a few GB at 500 files, FLAT.

## Scope (files / methods on master post-#4434; grep for exact current lines)
- `Osprey.FDR/ProteinFdr.cs` -- `RunFirstPassProteinFdr` projection overload (~842): rewrite to
  stream from parquet stub + sidecar + library instead of the resident projection+outputs.
- `Osprey.Tasks/FirstJoinTask.cs` -- `RunFirstPassProjection` (~1530, lifecycle);
  `ComputeFirstPassBaseIds` (~1812, compaction) -> stream the sidecar; the protein-FDR call
  (~1653) + phase-2 patch (~1675).
- `Osprey.FDR/PercolatorEngine.cs` -- `RunStreamingIntoProjection` (~670): training off parquet;
  drop the flat input arrays.
- `Osprey.IO/FdrScoresSidecar.cs` + `FdrScoreRecord.cs` -- the on-disk record (has everything).
- `Osprey.IO/ParquetScoreCache.cs` -- `LoadFdrStubsFromParquet` / `ReadFdrStubScalars` (modseq source).
- `Osprey.FDR/FdrProjection.cs` (`FdrProjectionSet`) / `FdrProjectionOutput.cs`
  (`FdrProjectionOutputs`, `IFdrOutputSink`) -- the buffers being dropped.

## Parity-fragile (byte-identity is THE gate)
- Protein-group q ordering (the best-score reduction + group-q assignment must reproduce the
  resident path exactly).
- Use the PARQUET-STUB modseq (`LoadFdrStubsFromParquet`), NOT the library -- exact interned instance.
- The sidecar read must join rows in the same (file, row) order the resident path used.
- Bisect a red gate with `Test-Full-Regression.ps1` / `Test-Snapshot.ps1`.

## Gates
- `regression.ps1 -Dataset All` byte-identical (Stellar + Astral, mode1/2/3) -- THE gate.
- **FDRBench entrapment oracle** -- this moves discovery/q-value plumbing, so the independent
  correctness oracle is required (`ai/docs/osprey-development-guide.md` FDRBench section).
- `Build-Osprey.ps1 -RunTests -RunInspection`.
- **Measurement (the win)**: `ai/.tmp/firstpassfdr-dmw.ps1` (16-file retention) +
  `firstpass-mem-n.ps1 -MaxFiles 82` must show the `FdrProjection[]` + `FdrProjectionOutputs`
  blocks GONE from the retained set and the resident LIVE set FLAT in files (16f vs 82f per-file
  slope -> ~0). READ THE LIVE metrics (gc_heap_last_gc), not peak_paged (Server-GC-slack noise).

## References
- **Stage B execution-ready spec (resume here): `ai/.tmp/stageB-design-20260718.md`** — the
  streaming-competition-core rewrite plan (unit-test-first), row source, byte-identity invariant,
  two-path producer, gates.
- Full design detail while it exists: `ai/.tmp/partB-design-20260717.md` (Increment 2 section).
- `[[TODO-osprey_perfilescoring_calibration_memory_peak]]` (sibling memory frontier).
