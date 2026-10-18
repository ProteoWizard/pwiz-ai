# Slim FirstPassFDR: delete the pass-2 row walk, move Stage 6 planning pass 2 into PerFileRescoring

## Branch Information
- **Branch**: `Skyline/work/20261016_osprey_planning_into_rescoring` (PR B; local, created from master
  `fcb0dcb0ca`, not pushed, no upstream). PR A was `Skyline/work/20261015_osprey_firstpassfdr_slimming`
  (merged, deleted).
- **Base**: `master`
- **Created**: 2026-10-15
- **Status**: PR B complete: steps 1-3 + defect fixes + P16 pay-later fix committed (`c398ff986c`,
  `21f51395ca`, `7b21b0b239`, `0cd3c6fa16`, review fixes). Gates green (unit, regression-parallel All 48/48,
  cross-impl Stellar + Astral 1e-9). Pushing / PR / TeamCity approved by Brendan 2026-10-17. ai/ script
  changes commit at merge. Follow-up PR prepared: TODO-20261017_osprey_remove_write_pin.
- **Owed to #4823 / #4848 (decided 2026-10-15)**: draft PR #4848 (`Skyline/work/20261009_blib_protein_fdr_pep`,
  stacked on #4823) adds `PeptidePep` inside the pass-2 row walk PR A deleted, plus edits to
  `FdrExperimentRecord/Accumulator/Sidecar` and `FdrProjectionSinks`. PR A merged first (Mike is not settled
  on #4848; Nick and Mike are on vacation), so we merge master into #4823 then #4848 and resolve:
  `PeptidePep` is per-peptide (`peptidePepByPeptide`), so it becomes one more argument of
  `IFdrFirstPassSink.AcceptExperimentEntry`, built in the per-entry loop. Ask Brendan before pushing to
  either branch.
- **GitHub Issue**: (none)
- **Module**: `osprey`
- **PR**: A = [#4853](https://github.com/ProteoWizard/pwiz/pull/4853) (merged 2026-10-16 as `c30a5af221`).
  B = (none yet).
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

#### Per-run file inventory (measured 2026-10-16, SEA-AD 82 acceptance run)

Run dir `D:\test\osprey-runs\sea-ad\runs\seaad-82files-libdecoy-r1.0-protein-compactsprintfinal`
(`--model-diagnostics` on, protein-compact). Script: `ai/.tmp/sessions/20261016-b2pr/inventory.py`
(SHA-256 over every copy when all copies share one size) and `envelope_keys.py` (per-key breakdown of
4 sampled envelopes). `.spectra.bin` lives in the cache dir, not here.

| `<stem>.*` | Writer | Readers | Content scope | Mean / total (82) |
|---|---|---|---|---|
| `.calibration.json` | PerFileScoring (Stage 3) | all four tasks | run | 0.05 MB / 4 MB |
| `.scores.parquet` | PerFileScoring (Stage 4) | FirstPassFDR, PerFileRescoring | run | 1,873 MB / 153.6 GB |
| `.1st-pass.fdr_scores.bin` | FirstPassFDR pass 1 | PerFileRescoring (+ SecondPassFDR under `OSPREY_PASS2_VERIFY_WORKER`) | run | 155 MB / 12.7 GB |
| `.1st-pass.model.json` | FirstPassFDR training | PerFileRescoring, SecondPassFDR, FirstPassFDR resume (`LoadFromAny`, `LoadCurrentModelSidecar`) | **exp - 82 identical copies** | 3.4 KB / 0.3 MB |
| `.1st-pass.stratum.json` | FirstPassFDR protein FDR | same as model (paired by stem + stamp in `LoadFromAny`) | **exp - 82 identical copies** | 9.6 MB / **790 MB** |
| `.reconciliation.json` | FirstPassFDR planning pass 2 (PR B moves it to PerFileRescoring) | PerFileRescoring, SecondPassFDR (gap-fill entry ids) | run, **except** `first_pass_base_ids` | 25.2 MB / 2.07 GB |
| `.scores-reconciled.parquet` | PerFileRescoring | SecondPassFDR, PerFileRescoring resume / training export | run | 474 MB / 38.9 GB |
| `.2nd-pass.fdr_decoys.bin` | PerFileRescoring pass-2 worker (protein-compact) | SecondPassFDR | run | 6.4 MB / 0.53 GB |
| `.2nd-pass.fdr_scores.bin` | PerFileRescoring pass-2 worker | SecondPassFDR, training export | run | 39.5 MB / 3.24 GB |

Inside `.reconciliation.json` (v3), per key, 4 sampled runs: `first_pass_base_ids` 5.68 MB
(727,101 ids) is **identical in all 4**, as are `file_stems`, `library_hash`, `search_hash`,
`osprey_validity` (small). The run-specific keys are `use_cwt_peak_actions` 3.86 MB,
`forced_integration_actions` 3.56 MB, `refined_rt_calibration` 2.62 MB, `gap_fill_targets` 1.02 MB.
So ~466 MB of the 2.07 GB is replicated `first_pass_base_ids` here (2.79 GB at CHS 446 per doc 00 P1).

**`first_pass_base_ids` has no live reader** (grep 2026-10-16): `RescoreHydration` copies it into
`GlobalFirstPassBaseIds` and nothing reads that property; `ReconciliationFile` only refuses a null
array. Its consumer was the all-runs reconciliation bundle removed 2026-10-12. Since PR B moves the
envelope writer anyway, drop the field (format v3 -> v4) rather than keep it optional.

**Rule (Brendan, 2026-10-16): Osprey never writes the same content to a `<stem>.<ext>` file for
every run.** Experiment-wide content goes to `<blib-stem>.<ext>`, written once. Enforce with a
`SubsetPipelineTest` arm: after a straight-through multi-run analysis, group every `<stem>.*` output
by suffix and fail when one suffix is byte-identical across all runs. That cannot see a replicated
payload INSIDE an otherwise per-run file (the envelope's `first_pass_base_ids`), so doc 00 P1 states
that case too and drops its "replicated under each run stem" exception.

Decisions from the inventory:
- Model and stratum become `<blib-stem>.1st-pass.model.json` / `<blib-stem>.1st-pass.stratum.json`,
  path from `ArtifactPaths.ResolveOutputDir(ScoringTaskShared.ArtifactSiblingPath(config))` like
  `RetainedBaseIdSidecar.PathFor`. `OutputBlib` is required on every pipeline path
  (`Program.cs:915`, `OspreyTask.cs:95`), so the name is always available.
- The new consensus artifact follows the same rule: `<blib-stem>.1st-pass.consensus.bin` (name TBD).
- No other per-run file carries experiment-wide content.

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
- Done 2026-10-17: the 2026-10-15 `seaad-82files-planonly-lanes1` scratch dir and the 2026-10-16 scratch runs and
  exe snapshots are deleted (see the 2026-10-16/17 progress entry).

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
- Committed A1+A2 as `89dc0dfefd`, then rebased onto master `773aa1bf63` (#4852, #4846, #4831 - no
  overlapping files). After rebase: unit 637/637, inspection 0, regression-parallel All 48/48 in 27:45.
- **PR A opened: #4853** (pushed with Brendan's OK). TeamCity Osprey Perf/Regression triggered on
  `pull/4853` with his OK: build 4220191 (https://teamcity.labkey.org/build/4220191).
- TeamCity Osprey Perf/Regression build #321 (ID 4220191) SUCCESS on `b8d1e1c0`. Copilot did NOT
  review: its one review is the quota refusal (first reported here, wrongly, as "reviewed with no
  inline comments").

### 2026-10-16 - PR A merged

PR #4853 merged as commit `c30a5af221` (squash), on top of #4854 (blib Osprey* tables dropped,
LibMetadata/DecoyPairs added), which merged minutes earlier and was not in the tested base - the two
touch disjoint files (FDR vs blib writer). Shipped: A1 (pass-2 row walk removed; experiment scope per
entry; per-row walk only for --model-diagnostics) and A2 (protein q from pass 1's entry peptides).
Work branch deleted locally and on origin. TODO kept active for PR B.

PR B branch created: `Skyline/work/20261016_osprey_planning_into_rescoring` from master `fcb0dcb0ca`
(local, no upstream). Line numbers in the "PR B" section are from `a5a3fc3dbb`; re-check them.

**Next session handoff**: read `ai/.tmp/handoff-20261016_osprey_planning_into_rescoring.md` before starting
work. (The 2026-10-15 handoff file is for PR A and is obsolete.)
- Timing (exe snapshot `D:\test\osprey-runs\_bin\firstpass-slim-a1a2`, version pinned 26.1.1.286):
  1. Stage 5 on, mdiag on, `-LinkFrom` the acceptance run: product byte-identity + timing. Running.
  2. `-Task FirstPassFDR -NoModelDiagnostics`: the no-diagnostics saving. Queued after 1.
### 2026-10-16 (session 2) - PR B steps 1-2: inventory, model/stratum to analysis names

- Step 1 inventory done (table in the PR B section). Only model and stratum are whole-file
  replicated; the envelope's `first_pass_base_ids` is a replicated payload with no live reader.
- Brendan (mid-session): the sprint must also ASSERT the rule - no `<stem>.<ext>` output may be the
  same for every run. Done as `SubsetPipelineTest.AssertNoReplicatedPerRunOutputs`, called from
  `ValidateStraightThrough` (3-run default) and `TestSubsetLibraryDecoysAndReports` (diagnostics,
  fdrbench, --write-pin). Proven: a temporary per-run model copy fails it with
  "identical in every run ... <stem>.1st-pass.model.json" (`probe-replication.log`), then removed.
- Step 2 (uncommitted, `C:\proj\pwiz`):
  - `FirstPassModelIO`: `PathFor(config)` / `StratumPathFor(config)` -> `<blib-stem>.1st-pass.{model,stratum}.json`
    via `ResolveOutputDir(ArtifactSiblingPath)`; `LoadFromAny` -> `LoadForAnalysis` (pairs by stamp);
    `SerializeStratum` folded into `SaveStratum`; legacy inline `ModelDto.StratumBaseIds` removed
    (model file bytes lose `"StratumBaseIds": null`; pin updated).
  - `FirstPassFdrTask`, `Pass2FdrSidecar.EnsureFrozenFirstPassPublished(ctx)`,
    `PerFileRescoreTask.CreatePass2Worker`, `SecondPassFdrTask`: one write / one read.
  - Resources: 8 keys removed (all 3 resx), 5 added (English + Designer, inserted in place).
  - Tests: FirstPassModelIoTest arms rewritten around an analysis config; SubsetPipelineTest HPC chain
    and TrainingExport node ship `output.1st-pass.{model,stratum}.json`.
  - `regression.ps1` mode 3 staging renamed. Docs 00 (P1 rewritten: no replication exception;
    contract table gains retained_base_ids/model/stratum rows; stale stratum "In flight" removed),
    07, 12, 14 updated.
  - ai scripts (UNCOMMITTED in ai/ - commit when PR B merges, since master builds still write
    per-stem names): `OspreyDatasetRun.psm1` moves model/stratum to `$ANALYSIS_ARTIFACTS` (its glob
    also adopts an old bed's per-stem copy under the new name), `New-OspreyResumeStage.ps1`,
    `Run-SeaAd.ps1` help text.
- Gate run 1: inspection 0, unit 636/637 - the failure was the removed legacy inline-stratum arm,
  rewritten (`test-run1.log`). Run 2: unit 637/637, inspection 0 (`test-run2.log`).
- regression-parallel All: 48 PASS / 0 FAIL in 28:58, mode 3 (HPC chain==straight) green on the
  renamed staging (`regression-step2.log`).
- Brendan: update `Osprey-workflow.html` before committing (done: FirstPassFDR 2 files/run + 4
  experiment-wide, 168 files at 82 runs; rescoring and SecondPassFDR inputs list the analysis-named
  model/stratum; SecondPassFDR inputs also gained the retained summary).
- **Committed step 2 as `c398ff986c`** (local, no upstream).
- **Committed step 3 as `21f51395ca`** (local, no upstream) after: unit 637/637 + inspection 0
  (`test-step3-run5.log`), regression-parallel All 48/48 twice (before and after review fixes),
  SEA-AD byte-identity + all 82 envelopes identical.
- **Decided (Brendan, 2026-10-16): remove unused outputs rather than keep them for Rust parity.**
  Rust is becoming a stale reference; the cross-impl test stays as a validation tool, so its
  comparators strip C#-only differences (as they already must for `osprey_validity`). So step 3
  drops the envelope's `first_pass_base_ids` (v4) and updates the bisection comparators to strip it
  from the Rust side.
- Deferred to step 3: drop `first_pass_base_ids` (envelope v4). The cross-impl bisection tools
  (`Compare-CrossImpl-Reference.ps1`, `Compare-EndToEnd-Bisect-Crossimpl.ps1`) SHA-compare the
  envelope against Rust, which still writes the field; they would need to strip it as they must
  already strip `osprey_validity`. Answered below: drop it.

### 2026-10-16 (session 2, continued) - PR B step 3: planning pass 2 into PerFileRescoring

Design as built (uncommitted until gates pass):
- FirstPassFDR: `Stage6Planner` keeps ONLY pass A + `BuildConsensus` and returns
  `Stage6Planner.Result { Stage6Consensus Consensus, HashSet<uint> GlobalBaseIds }`. `PlanStage6`
  writes `<blib-stem>.1st-pass.consensus.json` (new `Stage6ConsensusFile`: JSON, stamp first,
  consensus list + PassingBaseIds + PassingPrecursors as sorted parallel arrays, doubles via
  RoundtripDoubleConverter) and the retained summary = GlobalBaseIds alone. No envelopes.
  Declared outputs: envelopes out, consensus in. `PlannedActionCount` byproduct removed.
- Retained summary equality (`GlobalBaseIds` == old union): holds by construction - pass B planned
  over entries from the same survivor loader that built GlobalBaseIds, so every action target's
  base_id was already in it. Confirmed empirically: SubsetPipelineTest straight-through/HPC chain
  pass; byte-compare against SEA-AD acceptance pending.
- PerFileRescoring: new `RunReconciliationPlanner` (built once in `CreateRunPlanner` from the
  consensus file, PerFileCalibrations, PerFileIsolationMz, library lookups). `HydrateOneRun` takes a
  `planRun` callback instead of loading the envelope; `PlanAndWriteRun` plans over a canonically
  sorted copy of the compacted survivors (the order FirstPassSurvivorLoader gave the old planner),
  saves `<stem>.reconciliation.json` with the reconciled parquet's stamp BEFORE rescoring, and the
  plan goes through the same PlanActions/CaptureCalibrationAndGapFill conversions as a read-back.
  Planning runs inside `_survivorLoadLock` (CWT column load is a large transient like the stub
  load). Per-run log line kept; summary (refit count, action count) logged by the planner.
- Envelope v4: dropped file_stems, first_pass_base_ids, library_hash, search_hash (+ their Load
  checks, 2 IO resources). `RunRescoreInputs.JoinFileStems/GlobalFirstPassBaseIds` removed.
- Done predicate: `Pass2FdrSidecar.HasWorkerStamp` also requires the envelope stamp == reconciled
  stamp; `PerFileRescoreTask.Outputs` declares the envelope; Stage 7 `LoadGapFillEntryIds` now
  throws instead of folding everything on a missing plan.
- Retired OSPREY_DUMP_REFIT / _REFIT_ONLY / _DUMP_LOESS_FIT / _LOESS_FIT_ONLY (all-runs dumps;
  each refit is in its envelope). Consensus + inv_predict dumps stay in FirstPassFDR.
- Resources: Tasks -8/+6, IO -2 (patch script `patch_resx.py` now refuses unless parsed Designer
  properties tile the file - it silently dropped multi-separator properties once; caught by build).
- Tests: IOTest envelope fixtures v4; TaskValidityKeyTest worker-answer fixture adds the plan;
  SubsetPipelineTest HPC chain ships consensus (not envelopes) to phase 3; TrainingExport node same.
- regression.ps1 mode 3 ships consensus to phase 3; RegressionData.ps1 resume invalidation no
  longer deletes envelopes (PerFileRescoring's now).
- Docs: 00, 14 (section 5 rewritten + 5a consensus), workflow page; 05/10/11/15 by a doc agent.
- ai/ (uncommitted until merge): runner link tables (envelope -> PerFileRescoring, consensus ->
  analysis-wide), Run-SeaAd help; cross-impl comparators now content-compare envelopes via new
  `Compare/reconciliation_diff.py` (drops stamp + the 4 v4-removed fields + format_version).
- Gate run 1: inspection 0, unit 635/637 (two fixture failures, fixed). Run 2: 637/637, inspection 0.
  Comment sweep + CLI help example ("and once for the analysis: out.1st-pass.*"); run 3: 636/637,
  the one being the self-updating CommandLine.html test regenerating en/ja/zh (expected).
- regression-parallel All: 48 PASS / 0 FAIL in 27:31 (`regression-step3.log`) - byte-identical with
  planning moved, HPC chain shipping the consensus instead of envelopes.
- SEA-AD 82 result (`ai/.tmp/sessions/20261016-b2pr/seaad-step3-compare.txt`), vs the acceptance run:
  - byte-identical: out.stats.tsv 45F2E16C, out.protein_groups.tsv 906B6ED8, retained_base_ids
    C722D325 (equality with the old GlobalBaseIds-union-actions set CONFIRMED on SEA-AD), both
    fdr_experiment.bin, both fdrbench TSVs, 2nd-pass model-diagnostics, all 246 per-run FDR
    sidecars; model + stratum content identical; ALL 82 envelopes identical by content
    (reconciliation_diff semantics) - planning moved without changing a single plan.
  - out.1st-pass.model-diagnostics.json differs ONLY by `cal` = null, which is pre-existing on every
    -LinkFrom run (PR A run, 10-12/10-13 runs too): Stage 1-4 calibration diagnostics are not in
    memory on a resume. Content otherwise identical to the PR A run. Separate P16 gap - report to
    Brendan, not in scope.
  - Envelopes 2.07 GB -> 1.30 GB; consensus.json 27.7 MB.
  - Wall (vs PR A run, same setup): FirstPassFDR 1,602 -> 1,328 s (-274); PerFileRescoring
    4,461 -> 4,809 s (+347); SecondPassFDR 1,041 -> 1,367 s (+326). The first two are the predicted
    break-even. The Stage 7 rise is uniform across every parquet-streaming fold pass (+30-45%)
    while compute steps match - looks like disk throughput. Reconciled parquet volume is identical
    (38,883,121,348 bytes both runs). Same-session A/B via the resume route (`-LinkUpTo
    SecondPassFDR`, no --task; Run-SeaAd.ps1 gained -LinkUpTo, as Run-Chs.ps1 has): PR A build
    (`_bin\firstpass-slim-a1a2`) Stage 7 = 1,427 s (products 45F2E16C / 906B6ED8) - slower than the
    step-3 run's 1,367 s, so the rise is the machine, not the change. Candidate leg (`_bin\planrescore-21f5139`,
    the committed step 3 incl. review fixes): Stage 7 = 1,354 s, products 45F2E16C / 906B6ED8, and
    PerFileRescoring resumed as "skipping (outputs valid)" with the envelopes linked (the new done
    predicate holds on resume). Stage 7 is NOT slower. Run dirs `...ab7base-20261016_165733`,
    `...ab7new-20261016_173419`.
- Pre-existing defects found and FIXED on this branch (Brendan, 2026-10-16: "fix issues as we find
  them and write new tests"; both found by the SEA-AD verification, missed by existing tests):
  1. `--task SecondPassFDR --model-diagnostics` died before loading a run when the node lacked
     `out.1st-pass.model-diagnostics.json`. Root cause: `FirstPassFdrTask.WillOnlyFoldDiagnostics`
     answered "only the report is owed" for a FirstPassFDR this process does not run, sending
     `PerFileScoringTask.Rehydrate` down the fold route, which refuses reconciled-input nodes. Fix:
     add `ScoringTaskShared.Includes<FirstPassFdrTask>`. Test: new leg at the end of
     `TestSubsetDiagnosticsWithoutReanalysis` (no blib, no diagnostics products, --task SecondPassFDR
     -> exit 0, same blib, no pass-1 product written). Red on the old code with the exact exception.
     Regression mode 3 never saw it: it ships the pass-1 product.
  2. Report's calibration view (`cal`) null on every resume past Stage 3 and every HPC join. Root
     cause: Stage 3's `CalFileRow`s lived only in a byproduct. Fix: PerFileScoring writes
     `<stem>.calibration-diagnostics.json` (row + mass unit, calibration's stamp) when it computes the
     row; `BuildCalibrationData` reads it for runs not in the byproduct, only when its stamp matches
     `.calibration.json`. Test: `AssertSameFirstPassProduct` no longer excludes `cal` - it had listed
     it as "a view a fold cannot rebuild", which is how the gap passed. Red before, green after.
     Relayed in regression.ps1 mode 3 phase 2 + SubsetPipelineTest chain phase 2; docs 00, 14;
     runner link table (PerFileScoring). NOT fixed yet - and Brendan (2026-10-16) ruled it a BUG, not a
     design choice: P16 requires a run WITHOUT the flag to store enough to reproduce the report fully
     later. Adding --model-diagnostics AFTER Stage 3 ran still has no calibration view - the rows need Stage 3's in-memory matches and
     Stage 3 skips that work when the flag is off. Required: always persist what the report needs.
     Missing test (Brendan's plan had it backwards-incomplete): start from a run WITHOUT
     --model-diagnostics, then (3) --task ModelDiagnostics and (4) the original command line + flag
     must reproduce the WITH-flag run's diagnostics files exactly. Write it first; likely a
     regression - bisect. Same
     class: the `model`, `featureHistEdges`, `modelComposite` views remain excluded from the fold
     comparison.
- Former note: Pre-existing defects found (now fixed above):
  - `Run-SeaAd.ps1 -Task SecondPassFDR -LinkFrom <run>` fails on the PR A build in 22 s:
    "A reconciled-input (--task SecondPassFDR) configuration reached the per-file scoring load"
    (`PerFileScoringTask.AssertLeanProjection` via `PerFileRescoreTask.Rehydrate`). The HPC-merge
    route from the runner is broken on master-era builds; regression mode 3 phase 4 passes, so it
    is something in the runner's command line (e.g. --model-diagnostics/--fdrbench) on that route.
  - `out.1st-pass.model-diagnostics.json` has `cal = null` on every -LinkFrom resume (P16 gap).
- `/code-review medium`: 8 findings, no correctness bug. Fixed (uncompiled until the SEA-AD run's
  timed stages finish):
  - (1) planning ran inside `_survivorLoadLock`, serializing it across rescore lanes. Split:
    `HydrateOneRun` (under the lock) now returns survivors only; `RescoreHydration.ApplyPlan` +
    `RescorePassInputs.PlanRun` plan, write and apply OUTSIDE the lock on the file lanes.
    (SEA-AD measures sequential rescore, so its timing is unaffected.)
  - (2) consensus loaded eagerly even when every run is done (and leaked the Pass2Worker on a
    throw): `RunReconciliationPlanner` loads it lazily (`Lazy<State>`) on the first PlanRun.
  - (4) consensus JSON: `double?` MAD bypassed RoundtripDoubleConverter and a NaN would have
    failed FirstPassFDR; now Json.NET default round-trip doubles (bit-exact, NaN-tolerant).
  - (5) 4th copy of the blib-stem path rule: shared `ScoringTaskShared.AnalysisArtifactPath`
    (model, stratum, consensus).
  - (7) `Inputs` null guard; (8) dead DiagnosticsOnly branch in PlanAndWriteRun removed.
  - Dropped: (3) null-path writer/reader mismatch - OutputBlib is required on every pipeline path;
    reading the consensus back in-process is deliberate (P10). (6) per-run log order under lanes -
    lanes already buffer per-file output.
- SEA-AD 82 timing run started 14:07 (exe snapshot `D:\test\osprey-runs\_bin\planrescore-step3`,
  -LinkFrom acceptance, version pinned 26.1.1.286): run dir
  `D:\test\osprey-runs\sea-ad\runs\seaad-82files-libdecoy-r1.0-protein-compactplanrescore-20261016_140730`.
- Next: regression-parallel All; SEA-AD -LinkFrom timing run from FirstPassFDR on, compare products,
  retained summary bytes, and every envelope (reconciliation_diff.py vs the acceptance v3 files).

- A2 plan (done) was: carry each entry's peptide (already in A1's entry facts) to the sink, keep
  `(entry_id, peptide)` in ascending order, and resolve protein q from that instead of re-walking the
  parquets. Byte-identical by construction in every `OSPREY_STUB_IDENTITY` mode; no library lookup.

### 2026-10-16/17 (session 3) - defect fixes committed; P16 pay-later design decided

- Gates for the two defect fixes: unit 637/637 + inspection 0 (`sessions/20261016-b2pr/test-defects-run1.log`),
  regression-parallel All 48/48 in 30:00 (`regression-defects.log`). Committed `7b21b0b239`.
- New acceptance test `TestSubsetDiagnosticsAddedLater` (no-flag run, then `--task ModelDiagnostics` and the
  original command line + flag must reproduce the with-flag products) and `AssertSameFirstPassProduct` made
  strict (only generatedUtc excluded). Red as expected: `featureCount, modelComposite, model, featureHistEdges`
  (+ `cal` from a no-flag start). Uncommitted.
- NOT a regression: Brendan's scenario (flag on, delete both diagnostics JSON + html, rerun) scripted
  (`sessions/20261016-b2pr/paylater-scenario.ps1`) and run on 09-03 `51c0c24837`, 10-05 `dfcb8d17ef` and
  `7b21b0b`: pass-1 Model views missing on all three ("not retrained" note dates from #4377, 07-06). Mode 11 /
  AssertSameFirstPassProduct hid it with a named skip-list; TODO-20260906's "removing the skip-list is the
  acceptance test for item 2" was lost to a second, unrelated "Item 2" being marked CLOSED.
- Cost measured (`D:/test/osprey-runs/mdiag-cost-20261016_222220`): Astral FirstPassFDR +7.7 s with the flag,
  of which ~5 s is report-only; keeping per-row standardized vectors costs +1.8 GB transient at 3 files and
  ~0.5 GB per in-flight cohort file.
- DECIDED (Brendan, 2026-10-17):
  1. Rust is reference only - never shape a C# format to Rust's schema; change the parity check instead.
  2. CAL row goes INTO `<stem>.calibration.json` (no separate .calibration-diagnostics.json), written every run.
     Compare-EndToEnd-Bisect-Crossimpl's Stage 3 byte compare becomes a content compare ignoring the member.
  3. Model view: each run's share (target/decoy feature sums in row order, class counts, fixed-bin histogram
     counts) goes into its `<stem>.1st-pass.fdr_scores.bin` (v9, every run), summed on the lane (no vectors
     kept); shares summed in run order; coefficients from `.1st-pass.model.json`. No model-view.json. Also
     fixes a pre-existing defect: a partially resumed FirstPassFDR reported contributions of re-scored runs only.
     Last-digit shift vs today's row-order sums accepted; FdrTest oracle follows.
  4. Separate PR off master: remove `--write-pin` / `.cs_features.tsv`; feature parity via
     `Compare/parquet_diff.py` on Stage 4 `.scores.parquet` (Rust `--no-join`).
- ai/ uncommitted: `Run-Osprey.ps1 -Output` (keeps the blib for re-runs).
- IMPLEMENTED (uncommitted, 2026-10-17):
  - CAL row: `CalibrationParams.ModelDiagnostics` (`model_diagnostics`, opaque JObject) filled by
    `ModelDiagnosticsReport.CalibrationDiagnosticsToJson`; Calibrator builds the row on every run (its gates
    were the only cost: library accession scan; the training report was always built). Separate file,
    relays (SubsetPipelineTest chain, regression mode 3) and runner link-table entry removed.
  - Model view: `Osprey.Core/FeatureSums` (counts, standardized sums, 60-bin histograms, ~10 KB);
    `BinarySidecarStamp` header [28..32] = extension length (0 for every other format, so unchanged);
    `FdrScoresSidecar` v9 writes/reads it (`ReadFeatureSums`). `PercolatorScorer.ScoreRows` reduces the
    share on the lane (no per-row vectors kept; keepLinearVectors / AccumulatesTreeFeatures gone); resident
    path also sums per file; resumed files read their share (`tryLoadFeatureSums`); a missing share gives
    null contributions, never a partial report. Fold: `FirstPassFdrTask.ModelViewFromArtifacts` = model.json
    (stamp must match) + shares via `PercolatorEngine.FirstPassContributionsFromShares`.
  - Tests: TestSubsetDiagnosticsAddedLater + strict AssertSameFirstPassProduct green; FdrTest resume arm now
    asserts resumed contributions == scored, and null without a share; AssertContributionsEqual bit-exact.
  - Gates: unit 638/638 + inspection 0 (`sessions/20261016-b2pr/test-shares-run5.log`). regression-parallel
    run 1: 46/4, all four = mode 3 "per-file FDR sidecars==straight" refusing v9 in `Regression/FdrSidecars.ps1`
    (fixed: v9 + [28..32] length + feature-sums byte compare); mode1b diagnostics vs golden PASSED. Run 2
    in flight (`regression-shares2.log`).
  - ai/: `Compare/calibration_diff.py` (new; Stage 3 of the bisect driver was a SHA compare that could never
    pass - stamp + metadata.timestamp), psm1 link table.
  - regression-parallel All run 2: 48/48 in 27:46 (`regression-shares2.log`). Cross-impl: Stellar 1-file PASS,
    Astral 3-file PASS (Rust 21:10, C# 6:54) (`crossimpl-stellar.log`, `crossimpl-astral.log`). Committed
    `0cd3c6fa16`.
- `/code-review medium` on the branch (4 commits): 10 findings. Fixed: (1) the resident scorer (also pass 2)
  built shares and, under gbdt, serially standardized every row with no reader - now gated on
  captureContributions/--verbose; (4) `FeatureSums.Read` overflowed int on corrupt counts and threw past
  `ReadFeatureSums` - long arithmetic, new `IOTest.TestFdrScoresSidecarFeatureSums`; (10) `--task
  FirstPassFDR` completion message still said "reconciliation planning done". Dropped: (2) calibration
  diagnostics cost - the decided trade-off (training report was always built); (3) last-digit shift vs Rust
  - decided; (5) consensus stamp not checked on load - same as the retained summary, existing pattern for
  FirstPassFDR's analysis-wide products (possible follow-up); (6) lane exception text on net472 - net10 only;
  (7) refit dumps - retired deliberately in step 3; (8) Rust v8 sidecars in FdrSidecars.ps1 - refuted, the
  cross-impl sidecar compare passed (Rust goes through the fused reader); (9) actions= count on resume -
  adopted runs perform no actions. Unit 639/639 + inspection 0 (`test-review-run1.log`).
- Housekeeping done (Brendan OK): removed C:\proj\pwiz-bisect worktree, paylater-bisect-*, mdiag-cost-*, the
  four 10-16 SEA-AD scratch runs, _bin bisect-51c0c24837 / defects-7b21b0b / planrescore-*.
