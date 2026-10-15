# Slim FirstPassFDR: delete the pass-2 row walk, move Stage 6 planning pass 2 into PerFileRescoring

## Branch Information
- **Branch**: `Skyline/work/20261015_osprey_firstpassfdr_slimming` (local, created from master `a5a3fc3dbb`, not pushed)
- **Base**: `master`
- **Created**: 2026-10-15
- **Status**: Not started. Design and measurements below; read them before touching code.
- **GitHub Issue**: (none)
- **Module**: `osprey`
- **PR**: (none yet). Planned as two PRs, A then B (see "Plan").
- **Checkout**: `C:\proj\pwiz`

## Objective

FirstPassFDR is the first join and the one node an HPC run waits for. On CHS-SEER 446 it took
9,048 s (2 h 31 m). A review of the stage (2026-10-15, UW8 session) found that about 5 minutes of that is
genuinely experiment-wide compute (SVM training, the experiment competition merge, parsimony, the consensus
build). The rest is per-run walks that sit in the join only because they fall between barriers.

Brendan's scope (2026-10-15): move work out of the `*PassFDR` joins only where it lands in an EXISTING
fan-out (`PerFileScoring` or `PerFileRescoring`) with nothing more than a new per-run output. Do not add a
new per-file task segment now. "Pass 1: score all rows" as its own fan-out is the one candidate with that
shape, and it is deferred.

So this TODO does three things:

1. **PR A1 - delete the pass-2 "Assigning q-values" row walk** (CHS 923 s, SEA-AD 160 s). It persists
   nothing per row.
2. **PR A2 - resolve first-pass protein q through the library** instead of re-walking every parquet
   (CHS 63 s, SEA-AD 16 s). Small, independent, optional.
3. **PR B - move Stage 6 planning pass 2** (calibration refit, reconciliation planning, gap-fill
   identification, `.reconciliation.json` write) **from FirstPassFDR into the PerFileRescoring per-run
   loop** (CHS 2,533 s, SEA-AD 404 s out of the join).

Full analysis: `ai/.tmp/firstpassfdr-decomposition.html`. It also covers the larger decomposition we
decided against for now.

## Measured baseline (binary `4c2eba1af8`, UW8 i9-14900, 30 threads)

FirstPassFDR sub-phases from run-log milestones. Logs:
- CHS: `D:\test\osprey-runs\chs-seer\runs\chs-446files-libdecoy-r1.0-protein-compactsprintfinal\run.log` (8 lanes)
- SEA-AD: `D:\test\osprey-runs\sea-ad\runs\seaad-82files-libdecoy-r1.0-protein-compactsprintfinal\run-20261013_232908.log` (7 lanes)

| Sub-phase | CHS 446 s | SEA-AD 82 s | Fate in this TODO |
|---|---|---|---|
| Pass 0 ingest/dedup (training set) | 527 | 129 | stays |
| Training feature load | 1,012 | ~240 | stays |
| SVM training | 55 | 47 | stays |
| Pass 1: score, run q, floors, sidecar write | 2,063 | 270 | stays (gains the tallies + entry set) |
| **Pass 2: "Assigning q-values"** | **923** | **160** | **deleted (A1)** |
| Model-diagnostics co-assignment | 184 | 36 | stays |
| Protein FDR (reduce 202 / resolve 63 on CHS) | 265 | 63 | resolve walk replaced (A2) |
| Stratum, experiment sidecar, FDRBench pass 1 | 20 | 53 | stays |
| Compaction | 23 | 6 | stays |
| Planning pass 1 (survivor load, consensus reductions) | 1,410 | 128 | stays |
| Consensus RT build | 12 | 3 | stays |
| **Planning pass 2 (refit, plan, gap-fill, envelopes)** | **2,533** | **404** | **moved to PerFileRescoring (B)** |
| Total | 9,048 | 1,556 | |

**Planning at one lane** (measured 2026-10-15; SEA-AD `--task FirstPassFDR` resumed at the compaction gate
in a hard-linked copy, `-FdrFileLanes 1`; log
`D:\test\osprey-runs\sea-ad\runs\seaad-82files-planonly-lanes1\run.log`):

| SEA-AD 82 | 7 lanes | 1 lane | per run, 1 lane |
|---|---|---|---|
| Planning pass 1 | 131 s | 313 s | 3.8 s |
| Planning pass 2 | 404 s | 658 s | 8.0 s |

- Outputs at 1 lane are byte-identical to the 7-lane run (82/82 `.reconciliation.json`,
  `out.1st-pass.retained_base_ids.bin`).
- Pass 2 is I/O-bound. It read 73.4 GB (60.7 GB parquet), about 0.9 GB per run, and spent 282 of its 658 s
  in block reads. Most of that is the whole `cwt_candidates` column (`CwtCandidateLoader.LoadOneFile`
  reads every parquet row's candidates; only ~25% of rows survive compaction).
- Planning code has NO parallelism inside a run. FirstPassFDR's only parallelism here is the file lanes,
  and they bought just 1.6x.
- **Expected effect of PR B on a single machine with sequential rescoring**: PerFileRescoring already loads
  the same survivors (the same `FirstPassSurvivorLoader`) and the run's calibration. The added cost is the
  CWT read + refit + plan + gap-fill, about 4-4.5 s per run on SEA-AD (8.0 s minus the ~3.8 s survivor
  load), against a ~54 s per-run rescore. So about +350 s in PerFileRescoring for -404 s in FirstPassFDR:
  roughly break-even on one machine. On HPC the full 42 minutes (CHS) leaves the join.
- **Possible follow-up in PR B**: read `cwt_candidates` for survivor rows only, if the parquet row-group
  layout allows it to save real I/O.

## Plan

### PR A1 - delete pass 2's row walk (`PercolatorScorer.RunStreamingFirstPass`)

Code: `pwiz_tools/Osprey/Osprey.FDR/PercolatorScorer.cs`. Pass 0 is `:609-723`, training `:816-868`,
pass 1 `:912-1078`, pass 2 `:1099-1229`.

What pass 2 produces today, and where each product goes:

| Product of pass 2 | Why the row walk is not needed | New home |
|---|---|---|
| Per-file `.1st-pass.fdr_scores.bin` | Already written by pass 1 for every scored file (`flushFileRunScope`), and by an earlier run for resumed files. `FdrStoringSink.AcceptOutput` writes only when `!_writtenElsewhere`, which is never true on this path | nothing to do; assert it |
| Experiment records (`FdrExperimentAccumulator`) | Per-entry functions of the finished maps: exp precursor q by entry (`expPrecByWinnerId`, else 1.0, raised to `clampFloors` by entry), exp peptide q by (peptide, decoy) with its floor, PEP by entry, aggregate by entry. `FdrExperimentAccumulator.Add` (`Osprey.IO/FdrExperimentAccumulator.cs:73`) THROWS if two rows of one entry disagree, and `FdrExperimentSidecar.Write` sorts by entry_id, so the file does not depend on visit order | build directly from the maps over the set of entry_ids present, which pass 1 collects (with peptide and decoy flag) in `ApplyScoredFile` |
| Per-file passing target/decoy tallies, passing-precursor set (`FdrProjectionSinkBase.Accept`, `Osprey.Tasks/FdrProjectionSinks.cs:~94`) | Read only run q (`EffectiveRunQvalue`) | pass 1 (the run q values are computed there) |
| `--model-diagnostics` accumulator fold (`_mdiagAccumulator.Add`) | Needs each row's experiment q, so it does need a walk, but only when diagnostics are on | keep a diagnostics-only walk (or fold it into the co-assignment walk, which already reads every run); the default run pays nothing |

Verify before relying on it:
- `expAggByEntryId` covers every entry present. Pass 2 falls back to the row's own score (`:1184`);
  that is per-entry only if the fallback never fires for an entry seen in more than one run.
- The single-file shortcut (`isSingleFile`: experiment q = the row's run q). One run has one row per
  entry, so it is per-entry; confirm.
- The `FdrStoringSink` resume path (`MarkSidecarWritten`) and `OnFinish`'s "flush never fired" check, which
  counts rows through `Accept`.
- `LogFirstPassResultsProjection` reads `sink.FilePassingTargets`.

### PR A2 - first-pass protein q from the library

`FirstPassFdrTask.RunFirstPassProteinFdrStreaming`, pass 2 (`Osprey.Tasks/FirstPassFdrTask.cs:2749-2815`),
re-walks every parquet to map entry_id -> modseq -> peptide q. Replace it with a loop over the experiment
records that looks up each entry's modseq in the library (`LibraryById` / `LibraryIdentity`).

Check the `OSPREY_STUB_IDENTITY=0` arm: it takes modseq from the parquet, so confirm parquet and library
modseq agree (the pass-1 `PeptideQvalues` keys come from the same source). Also preserve the
null-modseq-to-"" normalization.

### PR B - planning pass 2 into PerFileRescoring

Code: `Osprey.Tasks/Stage6Planner.cs` (`ScanFiles` `:165`, `BuildConsensus` `:250`, `PlanFiles` `:316-435`),
`FirstPassFdrTask.PlanStage6` (`:1118`), `WriteReconciliationFile` (`:1370`), `BuildReconciliationFile`
(`:1516`), `PerFileRescoreTask` (per-run worker ~`:1380`, survivor refill `:2630`),
`RescoreHydration` (envelope read `:432`).

Shape:
- FirstPassFDR keeps planning pass 1 and the consensus build. At their end it writes ONE new
  experiment-wide artifact (name TBD, e.g. `<blib-stem>.1st-pass.consensus.bin`) holding everything
  `PlanOneFile` reads from outside the run:
  - the consensus RT list (`PeptideConsensusRT`; CHS: 55,904 target + 55,446 decoy peptides);
  - `scan.PassingBaseIds` (`HashSet<(uint, byte)>`);
  - `scan.PassingPrecursors` (`HashSet<(string, byte)>`);
  - `scan.GlobalBaseIds`.
  Like the retained summary, it is written at the end of the phase that computes it (P7/P12), never
  replicated per run (P1). It is O(distinct).
- The library lookups (`BuildGapFillLibraryLookups`: `(modseq, charge) -> (target, decoy)` and
  entry_id -> precursor m/z) are O(library) and rebuilt from the library on the rescore node.
- The isolation-window coverage comes from the run's own `.calibration.json`, which the rescore already
  reads.
- `ReconciliationPlanner.FilePlanner` and `GapFillTargetIdentifier.FileIdentifier` read only
  `perFileOriginalCal[fileName]` (`ReconciliationPlanner.cs:295,313`, `GapFillTargetIdentifier.cs:211`),
  so a rescore node needs only its own calibration. Verified 2026-10-15.
- PerFileRescoring, per run, before rescoring:
  - load survivors once (already done);
  - load CWT candidates;
  - refit (`CalibrationRefit.Refit`), plan (`PlanFile`), identify gap-fill (`IdentifyFile`);
  - build and write `.reconciliation.json` (it stays a per-run product, now written by this task), then
    rescore from the in-memory plan rather than reading the envelope back.
- The retained summary (`.1st-pass.retained_base_ids.bin`) is `GlobalBaseIds` UNION every action target's
  base_id (`AccumulateActionTargetBaseIds`, `FirstPassFdrTask.cs:1430`). Action targets are survivor rows,
  so their base_ids should already be in `GlobalBaseIds`; if so, FirstPassFDR can write the summary
  without planning. **Verify** (assert equality on SEA-AD and Stellar; CHS logged 648,048).
  `ReleaseUnscorableLibraryFragments` and PerFileRescoring's compaction both read that set, so it must stay
  identical.
- Consider dropping the envelope's replicated `first_pass_base_ids` (2.79 GB of duplication at 446 runs,
  per doc 00 P1) now that the retained summary exists. Optional; check every reader first.

Contract and plumbing to update (doc 00 is the authority; read it first):
- `00-pipeline-architecture.md`:
  - the contract table: `.reconciliation.json` is written by PerFileRescoring; the new consensus
    artifact is added;
  - the Boundary 2->3 relay list: ship the consensus artifact to every rescore node; the envelope is no
    longer an input;
  - the Boundary 3->4 relay list (the envelope still goes to SecondPassFDR);
  - the "In flight" section (item 3 may be stale; check).
- Docs 14 (bytes/format/version of the new artifact), 15 (HPC recipe), 10 (reconciliation).
- **PerFileRescoring's per-run "done" predicate (P7)** must cover the envelope: a kill between the envelope
  write and the reconciled-parquet write must leave the run "not done". Also decide whether a current
  envelope is reused on resume or re-planned.
- `FirstPassFdrTask.Outputs` / declared outputs (no more envelopes; add the consensus artifact),
  `--task FirstPassFDR` completion message, `PlannedActionCount` byproduct (action counts are now known
  per run in rescoring), the "Cross-run reconciliation: N peak re-picks ..." total line.
- Diagnostic dumps that write every run's refit or plan at once (`DumpRefit`, `DumpLoessFit`, the
  reconciliation dump) and their `*_ONLY` exits: decide per-run append or retirement. Check
  `ai/scripts/Osprey/Test-Snapshot.ps1` stage6 and the cross-impl bisection docs before changing dump order.
- `regression.ps1` mode 3 (HPC split) staging lists, `SubsetPipelineTest` (HPC chain, resume, sidecar
  contracts), `RescoreHydration`, `FirstPassFdrTask.Rehydrate` / `RehydrateForPerRunRescore`, the
  diagnostics-only arms.
- The `OSPREY_DUMP_*` Stage 6 bisection seams listed in `ai/docs/osprey-development-guide.md`.

## Gates (every PR)
- Unit + inspection: `pwsh -File ./ai/scripts/Osprey/Build-Osprey.ps1 -Configuration Debug -RunTests -RunInspection`
- Golden: `pwiz_tools/Osprey/regression-parallel.ps1 -Dataset All`, byte-identical. These are refactors.
- Cross-impl: `Compare-EndToEnd-Crossimpl.ps1` on Stellar Single + Astral All (1e-9).
- Timing: SEA-AD 82 on UW8, `Run-SeaAd.ps1 -Tag <pr> -Exe <snapshot>`. Compare FirstPassFDR and
  PerFileRescoring `[TIMING]` against the baseline table above. Use `-LinkFrom` the acceptance run dir to
  re-run only from FirstPassFDR on, and pin `OSPREY_VERSION_OVERRIDE` as the osprey-development skill
  describes. Products must match the acceptance run byte-for-byte (`out.stats.tsv` `45F2E16C...`,
  `out.protein_groups.tsv` `906B6ED8...`).
- TeamCity Perf/Regression: ask Brendan first, once per merge candidate.

## Not in scope (decided 2026-10-15)
- A new per-file segment for planning pass 1 / consensus detections ("F2" in the HTML). Its survivors need
  the compaction set, so it cannot join an existing fan-out, and 24 min (CHS) does not justify an extra
  HPC hop.
- Splitting "Pass 1: score all rows" into its own fan-out with a Train join before it. This is the one
  candidate with the right shape (inputs: the model + the run's parquet; outputs: the existing sidecar +
  one reduction file; CHS 34-38 min). Revisit after A and B show what FirstPassFDR costs without them.
- Moving pass 0 / training candidates into PerFileScoring (CHS 9 min). This would be a new per-run output
  of an existing fan-out, so it fits the rule, but it needs a size measurement first. Candidate for a later TODO.

## Housekeeping
- Scratch dir from the 2026-10-15 measurement: `D:\test\osprey-runs\sea-ad\runs\seaad-82files-planonly-lanes1`
  (hard links to the acceptance run plus about 2 GB of new envelopes and an FDRBench TSV). Delete when no
  longer useful; deleting it does not affect the acceptance run dir.

## Progress Log

### 2026-10-15 - Created from the FirstPassFDR review

- Reviewed FirstPassFDR against the CHS 446 and SEA-AD 82 acceptance logs; the analysis is in
  `ai/.tmp/firstpassfdr-decomposition.html`.
- Brendan chose the scope above.
- Measured planning at one lane (table above).
- Created the branch from master `a5a3fc3dbb`. No code changes yet.

**Next session handoff**: read `ai/.tmp/handoff-20261015_osprey_firstpassfdr_slimming.md` before starting
work.
