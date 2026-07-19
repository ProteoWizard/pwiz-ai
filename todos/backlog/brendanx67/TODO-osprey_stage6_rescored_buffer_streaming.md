# TODO: Osprey Stage-6 PerFileRescore all-files survivor buffer -- O(files) resident

**Status**: Backlog.
**Priority**: High -- the remaining O(files) RESIDENT structure between us and a 500-file
run on a 64 GB box, now that Stage-5 FirstPassFDR is memory-flat (PR #4435). Observed as a
real slope in the 82-file perfviz PerFileRescoring band (drastically reduced in absolute
terms by prior work, but still linear in file count).
**Created**: 2026-07-19
**Scope**: `pwiz_tools/Osprey/Osprey.Tasks/PerFileRescoreTask.cs` (the `_perFileEntries`
buffer + `RescoreAllFiles`), `Osprey.FDR/Reconciliation/*` (the cross-file reconciliation
that requires the all-files view).

## What we observed (2026-07-19, 82-file SEA-AD Astral pass2ab run, perfviz --memstamp)
PerFileRescoring's private-bytes band is far lower than before the 5-day memory push
(~50-60+ GB -> ~25-30 GB) BUT has a **positive slope in file count** -- i.e. it still grows
O(files), unlike the now-flat FirstPassFDR band. At 500 files this slope re-crosses the wall.

## Root cause (code-verified 2026-07-19, df1084f93)
`PerFileRescoreTask` holds **every file's post-compaction survivor `FdrEntry` lists resident
at once**:
- `PerFileRescoreTask.cs:113` -- `private List<KeyValuePair<string, List<FdrEntry>>> _perFileEntries;`
- set from the compacted survivor set for ALL files (`ctx.Get<CompactedEntries>().Value`, ~:201),
  overlaid in place, then rescored across `nTotalFiles = perFileEntries.Count` (~:539).
- the code labels it: ~:590 -- *"clean PERSISTENT managed heap (all files' rescored FdrEntry
  buffer + ...)"*, probed as `reconciliation-resident`.
So the resident cost is O(total survivors) = O(files). @82f the survivor pool is ~12.4M
entries (~5.39M passed to the blib); at 500f it is ~5-6x. This is GENUINE live O(files)
growth -- distinct from the Server-GC committed-but-free "gray" seen elsewhere
([[project_osprey_pipeline_peak_is_servergc_retained_committed]]); it will not decommit away.

This is the **persistent-reload lever that #4394 (Requested by Mike, Fixes #4376) explicitly
DEFERRED**: that work bounded the Stage-6 reconciliation *transients* (per-file drop+GC) but
left this all-files survivor buffer resident. Completed transient work:
[[TODO-20260717_osprey_stage6_chunked_reconciled_transfer]].

## Why this is harder than the FirstPassFDR streaming
The Stage-5 first-pass reductions were per-file-independent, so PR #4435 streamed them one
file at a time. Stage-6 reconciliation is **cross-file** (consensus targets, reconciliation
actions, gap-fill match peaks ACROSS runs), so a file's rescore needs cross-file context. The
fix is not a straight per-file stream; it needs a pass to separate:
- the bounded cross-file state that must stay resident (consensus/reconciliation-action maps,
  keyed by peptide/precursor -- O(distinct), not O(files x survivors)), from
- the per-file survivor `FdrEntry` lists, which can be reloaded per file on demand from the
  ORIGINAL parquet + sidecar (the survivor reload `ReloadFirstPassSurvivors` ALREADY does this
  per-file) rather than all held at once.

## The lever (proposed direction -- validate before committing)
1. Add `[MEM]` probes to confirm `_perFileEntries` (not the transients) is the slope source at
   82f, and measure the per-file B/row so the 500f projection is exact (`[[reference_osprey_perfile_mem_measurement]]`).
2. Trace which reconciliation inputs genuinely need all files resident vs. which are already
   bounded (O(distinct peptides/precursors)). The survivor `FdrEntry` payload is the O(files) bulk.
3. Rescore per file streaming: hold only the bounded cross-file reconciliation state resident;
   load each file's survivor `FdrEntry` (parquet + sidecar overlay) just before its rescore and
   release after -- mirroring the FirstPassFDR fork. Byte-order of the rescored output must stay
   identical (the canonical (EntryId, Charge, ScanNumber, ParquetIndex) sort still applies).

## Gates
- `regression.ps1 -Dataset All` byte-identical (Stellar + Astral, mode1/2/3) -- reconciliation
  is byte-parity-sensitive; this is THE gate.
- `Build-Osprey.ps1 -RunTests -RunInspection`.
- Memory A/B: 16f vs 82f perfviz PerFileRescoring band slope -> ~0 (flat in files), like the
  FirstPassFDR band now is; confirm the 500f projection clears 64 GB.

## Companion (same future sprint): Stage-7 SecondPassFDR peak
Stage 7 (SecondPassFDR) is the whole-run memory HIGH POINT: **~45 GB private** on the 82-file
pass2ab run (2026-07-19, measured peak 44.1 GB private / 29.1 GB managed, at SecondPassFDR;
no reporting gaps there -- progress coverage is fine, only the memory peak). Brendan's call:
the Stage-6 slope (above) AND this Stage-7 peak are BOTH deferred to a new memory sprint, NOT
packed into the current FirstPassFDR-streaming PR (#4435), which is already a big win. Root
cause of the Stage-7 peak is uncharacterized -- likely the 2nd-pass Percolator retrain +
scoring on the reconciled survivor pool holding the survivor FdrEntry + features resident (the
`FdrStreamingSink` / 2nd-pass projection is O(survivors), see the Stage-B caveat in
[[TODO-20260718_osprey_firstpassfdr_resident]]). First step of the sprint: `[MEM]` probes +
dotMemory at the SecondPassFDR peak to pin what the 45 GB is (live survivor pool vs Server-GC
committed gray) before choosing a lever.

## References
- Precedent (same idea, one stage earlier): PR #4435 FirstPassFDR streaming,
  `[[TODO-20260718_osprey_firstpassfdr_resident]]`.
- Sibling per-file memory frontiers: `[[TODO-osprey_perfilescoring_calibration_memory_peak]]`,
  `[[TODO-osprey_perfile_scored_entry_streaming]]`.
- Deferred-from: `[[TODO-20260717_osprey_stage6_chunked_reconciled_transfer]]` (transient bound).
- `[[project_osprey_pipeline_peak_is_servergc_retained_committed]]` (this slope is LIVE, not gray).
- `[[reference_osprey_perfile_mem_measurement]]` (how to read the [MEM] probes).
