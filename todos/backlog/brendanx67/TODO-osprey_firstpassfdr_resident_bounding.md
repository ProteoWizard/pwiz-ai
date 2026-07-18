# TODO: Osprey FirstPassFDR resident memory bounding (Increment 2)

**Status**: Backlog.
**Priority**: High -- the ONE goal: make `--task FirstPassFDR` memory FLAT in file count.
PR #4434 (merged) bounded the TRANSIENT + trimmed constants (-15 GB LIVE @82f, byte-identical)
but did NOT touch the O(files) RESIDENT core. At 500 files the resident set is still ~140 GB
and grows linearly -- the blocker to a 500-file run.
**Created**: backlog (date on `/pw-startup`).
**Predecessor**: `TODO-20260717_osprey_firstpassfdr_memory_peak.md` (completed, PR #4434).
**Branch when started**: `Skyline/work/YYYYMMDD_osprey_firstpassfdr_resident` (off master).

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
