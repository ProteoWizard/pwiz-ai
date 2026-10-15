# Slim FirstPassFDR: delete the pass-2 row walk, move Stage 6 planning pass 2 into PerFileRescoring

## Branch Information
- **Branch**: `Skyline/work/20261015_osprey_firstpassfdr_slimming` (local, created from master `a5a3fc3dbb`, not pushed)
- **Base**: `master`
- **Created**: 2026-10-15
- **Status**: A1 in progress (2026-10-15). Design and measurements below; read them before touching code.
- **Overlap with #4848 (decided 2026-10-15)**: draft PR #4848 (`Skyline/work/20261009_blib_protein_fdr_pep`,
  stacked on #4823) adds `PeptidePep` inside the pass-2 row walk A1 deletes, plus edits to
  `FdrExperimentRecord/Accumulator/Sidecar` and `FdrProjectionSinks`. This work is expected to merge FIRST
  (Mike is not settled on #4848; Nick and Mike are on vacation). After A1 merges, we merge master into
  #4823 then #4848 and resolve: `PeptidePep` is per-peptide (`peptidePepByPeptide`), so it becomes one more
  field in A1's per-entry record build. Ask Brendan before pushing to either branch.
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
- **No replicated per-run copies (decided 2026-10-15, Brendan; REQUIRED in PR B).** An experiment-wide
  artifact is written ONCE under the analysis name, never copied under every run stem - Mike has
  complained about how many files Osprey produces, and an HPC orchestration script can copy one file
  to every node. Newer artifacts already follow this (`out.1st-pass.retained_base_ids.bin`,
  `out.1st-pass.fdr_experiment.bin`). In PR B:
  - the new consensus artifact is analysis-named;
  - `<stem>.1st-pass.model.json` (82 identical copies on SEA-AD, ~4 KB each) and
    `<stem>.1st-pass.stratum.json` (82 identical copies, 9.2 MB each = 753 MB; ~4 GB at 446 runs,
    estimated) become single analysis-named files; update `LoadFromAny`, the resume gates, the HPC
    relay lists in doc 00 (P1's "replicated" exception goes away), docs 12/14, regression.ps1 mode 3
    staging and SubsetPipelineTest;
  - **full inventory of every per-run (`<stem>.*`) file**: confirm each holds information unique to
    the run it is named for; anything experiment-wide moves to an analysis-named file. Record the
    inventory (file, writer, readers, per-run or not, size on SEA-AD) in this TODO and doc 14.
  - Doc 00 ~line 880 "In flight" note on the stratum split is stale (it landed).
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

### 2026-10-15 (session 2) - A1 implemented, regression running

- Sequencing vs #4848 decided (see Status): this branch merges first; we resolve #4823/#4848 after.
- A1 design as built (uncommitted, `C:\proj\pwiz`):
  - New `IFdrFirstPassSink` (`Osprey.FDR/FdrProjectionOutput.cs`): run scope per file
    (`PrepareRunScope` on the lane / `AcceptRunScope` in order), experiment scope once per distinct
    entry (`AcceptExperimentEntry`, ascending entry_id), and a per-row fold only when
    `FoldsRowExperimentValues` (--model-diagnostics).
  - `RunStreamingFirstPass`: pass 2 deleted. Pass 1 merges per-entry facts (peptide, side, run q)
    from the lanes into 64 shards (same pattern/hash as `ExperimentQClampFloors`, lowest file index
    wins); after the barrier `ExperimentScope.Resolve` computes the four values per entry. The
    diagnostics walk (`FoldRowExperimentValues`) reuses `Resolve` per row.
  - Aggregate-map miss now THROWS (was: fall back to the row's score). Every row keys its
    (base_id, side), so a miss means decoy flag != entry_id decoy bit.
  - Verify-list items: aggregate coverage - holds by construction (above); single-file shortcut -
    per-entry (unique entry ids per file); resume / `OnFinish` - `FdrStoringSink` replaced by
    `FdrFirstPassSink` with no write path (pass 1 writes every scored file incl. empty ones; the
    row-count check moved to `AcceptRunScope`); `FilePassingTargets` kept.
  - `[COUNT]` tally extracted to `FdrPassingTally`, shared with `FdrStreamingSink` (2nd pass,
    behavior unchanged).
  - Experiment records now enter the accumulator in ascending entry_id rather than first-seen order;
    the resume path already reads them sorted from the sidecar, and every reader is order-free.
  - Tests: `CapturingSink` also implements `IFdrFirstPassSink` and joins run scope + entries back
    into per-row values, so every oracle comparison is unchanged; read-back arms now exercise the
    diagnostics walk.
- Gates so far: Osprey unit 637/637 + inspection 0 warnings
  (`ai/.tmp/sessions/20261015-a49aea24/test-run2.log`). `regression-parallel.ps1 -Dataset All` running
  (`ai/.tmp/sessions/20261015-a49aea24/regression-a1.log`).
- A1 regression-parallel All: 48/48 PASS, 29:48 (`regression-a1.log`).
- A2 implemented: `AcceptExperimentEntry` carries the peptide; `FdrFirstPassSink.ApplyProteinQvalues`
  replaces the resolve walk in `RunFirstPassProteinFdrStreaming` (its `patchFailures` out param and 3
  resource strings removed). Unit 637/637, inspection 0; regression-parallel All 48/48, 26:47
  (`regression-a2.log`).
- NOTE: the SEA-AD acceptance run has `mdiag=True`. With --model-diagnostics the row walk still runs
  for the report, so A1's saving there is only the per-row sink work. The full saving is for runs
  without diagnostics.
- Decided 2026-10-15 (Brendan): the diagnostics report stays where it is (written in FirstPassFDR,
  right after the score pass). Merging its walk into the co-assignment walk would save only ~10 s:
  the walk's wall time is the fold itself (in-order `ModelDiagnosticsData.Accumulator.MergeFile`
  131.9 s of 138.7 s on SEA-AD), not the file reads. ModelDiagnostics performance is out of scope
  here; Brendan will review it as its own sprint.
- SEA-AD run 1 (mdiag on) FirstPassFDR: 1,602 s vs 1,556 s acceptance. Diagnostics walk + entry
  loop 143 s vs pass 2 153.6 s; protein FDR 44.8 vs 62.4 s (A2); pass 1 wall 303.5 vs 270.5 s, the
  increase all in parquet walk / sidecar write I/O (entry facts merge adds nothing visible), with
  untouched phases also ~39 s slower - read as disk noise.
- SEA-AD run 1 products byte-identical to acceptance through SecondPassFDR: out.stats.tsv 45F2E16C,
  out.protein_groups.tsv 906B6ED8, both fdr_experiment.bin, retained_base_ids, both fdrbench TSVs.
  Run dir `D:\test\osprey-runs\sea-ad\runs\seaad-82files-libdecoy-r1.0-protein-compacta1a2-20261015_120508`.
- SEA-AD run 2 (`-Task FirstPassFDR -NoModelDiagnostics`): FirstPassFDR 1,347.8 s; pass 1 wall 280.0 s,
  experiment scope 4.5 s, no row walk; protein FDR 46.8 s. Outputs identical to acceptance
  (experiment sidecar, retained summary, fdrbench pass 1, 82/82 reconciliation.json). Run dir
  `...\seaad-82files-libdecoy-r1.0-protein-compacta1a2-nomdiag-20261015_140359`.
- `/code-review medium`: 8 findings. Fixed:
  - (1, 2, 3) The per-row accumulator's "observations of an entry must agree" check was lost.
    Production files hold one row per entry per run (verified: SEA-AD file 0001 sidecar, 4,324,599
    records = distinct entry_ids, strictly ascending), but multi-candidate files (test fixtures) do
    not. `EntryFactsByEntryId.MergeFile` now refuses an entry_id with a different peptide or side in
    another run, and marks rows of one file that disagree on run q; a single-file run refuses such an
    entry (the old accumulator threw there too). Test arm `AssertEntryDisagreementsRefused`, proven
    by disabling the check (arm fails).
  - (4) Decoy-flag vs entry_id decoy-bit mismatch now refused per file during pass 1, not after it.
  - (7) Stale "pass 2" comments in FirstPassFdrTask / PercolatorScorer.
  Dropped: (5) ~100 MB of unread run-q doubles at 6.2 M entries - needed for the single-file case
  and the disagreement check, peak is elsewhere; (6) ApexRts.ToArray on resumed files - one array
  copy per file, and the resumed-file test arm compares apex RT through it; (8) ~75 MB transient
  entry/peptide lists until protein FDR - small, and simpler than holding the facts map longer.
- Unit 637/637, inspection 0 (`test-run5.log`). regression-parallel All rerun: 48/48, 29:26
  (`regression-review.log`).
- **Committed A1+A2 locally as `89dc0dfefd`** (not pushed, no PR yet). Next: Brendan decides push/PR
  for PR A (TeamCity Perf/Regression: ask first, on `pull/<N>`); then PR B per the plan above,
  including the no-replicated-copies inventory.
- Timing (exe snapshot `D:\test\osprey-runs\_bin\firstpass-slim-a1a2`, version pinned 26.1.1.286):
  1. Stage 5 on, mdiag on, `-LinkFrom` the acceptance run: product byte-identity + timing. Running.
  2. `-Task FirstPassFDR -NoModelDiagnostics`: the no-diagnostics saving. Queued after 1.
- A2 plan (done) was: carry each entry's peptide (already in A1's entry facts) to the sink, keep
  `(entry_id, peptide)` in ascending order, and resolve protein q from that instead of re-walking the
  parquets. Byte-identical by construction in every `OSPREY_STUB_IDENTITY` mode; no library lookup.
