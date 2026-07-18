# TODO: Osprey FirstPassFDR resident memory bounding (Increment 2)

## Branch Information
- **Branch**: `Skyline/work/20260718_osprey_firstpassfdr_resident`
- **Base**: `master`
- **Created**: 2026-07-18
- **Status**: In Progress
- **PR**: [#4435](https://github.com/ProteoWizard/pwiz/pull/4435) (draft; Stage A landed, Stage B in progress)

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
- Full design detail while it exists: `ai/.tmp/partB-design-20260717.md` (Increment 2 section).
- `[[TODO-osprey_perfilescoring_calibration_memory_peak]]` (sibling memory frontier).
