# TODO-20260923_osprey_carafe_export.md

## Branch Information
- **Branch**: `Skyline/work/20260923_osprey_carafe_export` (worktree `D:\Dev\pwiz-osprey-export`, upstream unset)
- **Base**: `Skyline/work/20260612_net8_port` (PR [#4619](https://github.com/ProteoWizard/pwiz/pull/4619))
- **Created**: 2026-09-23
- **Status**: Merged into #4717 (2026-09-30, Brendan's request for one PR to test): #4717's d3b12cd989 takes
  this branch at 23389009a0, and #4708 is closed. #4749 (Osprey types blib fragments from m/z) replaced #4730
  and landed on the base; the export flags those types `LIBRARY_MZ_MATCHED` (c0c7428206). Further Osprey work
  for this goes to #4717's branch, `Skyline/work/20260923_carafesharp`.
- **GitHub Issue**: [#4705](https://github.com/ProteoWizard/pwiz/issues/4705)
- **Module**: `osprey`
- **PR**: [#4708](https://github.com/ProteoWizard/pwiz/pull/4708), closed; continues in [#4717](https://github.com/ProteoWizard/pwiz/pull/4717)
- **Consumer**: `ai/todos/active/TODO-20260923_carafesharp.md`

## Objective

Give CarafeSharp everything it needs from Osprey so that only Osprey reads raw data:

- **Part A - blib library input fidelity.** Osprey reads fragment ion annotations and library
  decoys/entrapment from a .blib library, so a CarafeSharp blib searches as well as a DIA-NN TSV.
- **Part B - training export.** A new optional task writes, per run, the observed intensities
  of the full theoretical b/y ladder of every confidently identified target precursor plus
  per-ion interference evidence from Osprey's own peak boundaries, median polish and
  shared-fragment logic. CarafeSharp applies the masking thresholds.

With the new options off, every existing output must be byte-identical (regression.ps1 at 1e-9).

## Review 2026-09-28 (Brendan) - required before merge

PR #4708 builds, passes 612 tests with clean inspection, and is output-neutral on TSV
libraries (checked on the Stellar subset: 177 precursors either way). But part B adds an
optional fifth stage to the pipeline, which the architecture does not need and the pay-later
principle (P16 in `pwiz_tools/Osprey/docs/00-pipeline-architecture.md`) exists to avoid. The
PR must be split and part B re-architected to follow the `--model-diagnostics` pattern.

### How to pick this up (a new Claude session, Mike's or Brendan's)
1. Pull pwiz-ai, then load `/osprey-development` and `/version-control`. Read this whole
   "Review 2026-09-28" section first. Where it conflicts with the original plan below (Steps 3
   and 4, "run metadata" and "TrainingExportTask"), THIS section wins.
2. Read, before touching code: `pwiz_tools/Osprey/docs/00-pipeline-architecture.md` P15 and
   P16 (the pay-later / resume model); `Osprey.Tasks/ModelDiagnosticsTask.cs`; and the fold
   arms `OnlyDiagnosticsProductOutstanding` / `FoldDiagnosticsOnly` in `FirstPassFdrTask.cs`
   and `FoldPass2DiagnosticsOnly` in `SecondPassFdrTask.cs`. R2 asks for the same mechanism in
   PerFileRescoring, so understand that one first.
3. Prerequisite: the #4360 PR (branch `Skyline/work/20260927_osprey_subset_pipeline_test`,
   `SubsetPipelineTest` + `Osprey.Test/TestData/*.zip`) is expected to merge into the port branch
   first. Once it has, `git merge origin/Skyline/work/20260612_net8_port` into this work (never
   rebase a branch with an open PR). R6 builds on those tests.
4. Checkout: Mike's session uses his worktree (`D:\Dev\pwiz-osprey-export`). A Brendan session
   adopts the branch with `/pw-adopt 4708`. Either way, cut PR A from it first (R1), then PR B
   stacked on PR A.
5. Work R1 -> R9 in order. A PR is ready for review only when every item is done or
   explicitly answered in its description, and the Gates at the end of this TODO pass.

### R1. Split into two PRs
- **PR A - blib annotations** (#4705 part A): `BlibPeakAnnotations`, `BlibLoader`,
  `PeptideFragmentMass`/`FragmentLadder` extraction, mod-text snapping, `;libext=ann`, and their
  tests. Independently useful and small enough to review on its own.
- **PR B - training export**, stacked on A (its b/y ladder uses `PeptideFragmentMass`),
  re-architected per R2-R5.

### R2. The training export is a PerFileRescoring product, not a stage
Follow `--model-diagnostics` / `--task ModelDiagnostics` exactly - the pattern proven on the
CHS 446-run cohort (flag added to a finished run: 1:51:53, 37 GB peak, report identical to
the flag-up-front run; see `completed/TODO-20260906_osprey_stage7_lean_row.md` and
`TODO-20260910_osprey_mdiag_resident_removal.md`).

| | ModelDiagnostics (existing) | TrainingExport (required) |
|---|---|---|
| Flag | `--model-diagnostics` | `--training-export` |
| Declared output under the flag | `.1st-pass`/`.2nd-pass.model-diagnostics.json` (FirstPassFDR / SecondPassFDR `Outputs`) | `<stem>.training.parquet` (PerFileRescoring `Outputs`, per run) |
| Flag up front | Each FDR task folds while its data is in hand | PerFileRescoring writes the export while the run's `.spectra.bin` (already streamed for rescoring), reconciled boundaries and 2nd-pass run q are in hand |
| Flag added to a finished run | `OnlyDiagnosticsProductOutstanding` -> `FoldDiagnosticsOnly` / `FoldPass2DiagnosticsOnly` (`FirstPassFdrTask.cs`, `SecondPassFdrTask.cs`); "Nothing is re-run" | "only the export is outstanding" -> an export-only arm per run: reads that run's own durable artifacts, writes only the parquet, no re-scoring |
| Other tasks | PerFileScoring, PerFileRescoring skip | PerFileScoring, FirstPassFDR, SecondPassFDR skip |
| `--task X` | selector, never a stage (`ModelDiagnosticsTask`) | selector running the canonical pipeline with `--training-export` set |
| HPC | no new node type | no new node type - rides the existing per-file PerFileRescoring nodes |

Why: an appended optional fan-out after the final join makes NextFlow schedule optional work
on another round of nodes, each re-loading the library, reconciled parquet and `.spectra.bin`
that PerFileRescoring already had; it serializes behind the last join; it adds an
"optional stage" membership concept (`IsEnabled`) and per-run stamps listing every run's
inputs. Selection needs nothing from SecondPassFDR: targets and claimants are chosen by
2nd-pass RUN q, from the per-run sidecar the Stage 6 worker writes.

Remove: `TrainingExportTask` as a pipeline stage (keep it as a selector), `IsEnabled`, the
fifth entry in `OspreyTasks.Pipeline`. Keep: `TrainingEvidence`, the parquet writer/codec and
their tests - they move under PerFileRescoring unchanged.

### R3. No new sidecar in the scoring path
Drop `run-info.json` and the `RunInfoCollector` work added to every default parse. Capturing
it at parse time is the fan-out-memory trap P16 describes: a cohort cached before this change
never gets it, and `IN_SCAN_RANGE` then silently marks every ion in range. Derive per-window
MS2 scan ranges from the observed m/z extent in `.spectra.bin` (conservative: outside the
observed extent = unknown, not an observed zero). Instrument / NCE / dissociation: parquet
footer keys from the source when present, empty otherwise.

### R4. Decisions the rework must make explicit
- Experiment-level q-values and PEP exist only after SecondPassFDR and per-run files are
  write-once: drop them from the export; the consumer joins `output.2nd-pass.fdr_experiment.bin`
  by entry_id.
- Transfer pass-2 (`OSPREY_PASS2_QVALUE=transfer`) and runs where Stage 6 re-scored nothing
  write the per-run 2nd-pass sidecar in Stage 7, so PerFileRescoring has no 2nd-pass run q
  there: either refuse `--training-export` in those modes with a clear error, or select by
  1st-pass run q and say so in the footer.

### R5. Documentation - make the missed principle explicit (in PR B)
- `00-pipeline-architecture.md`: generalize P16 from diagnostics to OPTIONAL PRODUCTS - the
  work goes to the existing task that already holds its inputs (experiment-wide reductions to
  the FDR joins, per-run evidence over spectra to PerFileRescoring), declared as an output
  under its flag, with an "only this product outstanding" arm; never a new stage.
- Add the list above of why an appended optional stage is wrong (HPC scheduling, reloads,
  serialization behind the join, membership/stamp complexity).
- Reconcile P16's corollary ("diagnostics work belongs in the FDR tasks, never in the fan-out")
  and the rule against flag-conditional fan-out sidecars with R2: what they forbid is a product
  that can only come from fan-out MEMORY; a product the fan-out can re-derive from its own
  durable inputs on a pay-later resume is the same pattern.
- Update "Two selectable tasks that are not pipeline tasks" to describe the fold arms and the
  selector-runs-the-canonical-pipeline behavior (it currently says only "processes nothing").
- Remove the "non-degenerate version - a fifth canonical stage after SecondPassFDR" paragraph
  from the `ModelDiagnosticsTask.cs` class doc; it contradicts P16 and invites this design.
- Revert this PR's doc edits that describe a fifth stage (docs 00, 14, 15, 20, 22).

### R6. Tests - required, not optional
#4708 as posted has no test that runs the training export through the pipeline:
`TrainingExportTaskTest` covers only `PairTargets`, and the parity and pay-later claims rest on
one manual Stellar run. Neither PR is ready without the tests below.
- **PR B pipeline legs** in `Osprey.Test/SubsetPipelineTest.cs` (from #4360; in-process via
  `InProcessOsprey.Run` on the committed Stellar/Astral subsets, a few seconds per run):
  - straight-through with `--training-export`: parquet written for every run, rows > 0, parity
    count equal to the exported count;
  - the SAME command re-run with `--training-export` added to a finished directory that ran
    without it: assert PerFileScoring, FirstPassFDR and SecondPassFDR log
    "skipping (outputs valid)", no `[PATH] rescore-file` / `score-file` line, and each parquet is
    byte-identical to the flag-up-front run's;
  - `--task TrainingExport` on a finished directory: same assertions;
  - the HRAM (Astral) subset, which exercises the ppm and MS1 paths the unit-resolution data
    does not;
  - whatever R4 decides for transfer pass-2 and no-rescore runs (the single-file leg in
    `TestSubsetNothingRescoredAndBlibLibrary` is a no-rescore run).
- **PR A tests**: a unit test that a decoy of a peptide with stacked modifications at one
  position (N-term acetyl + oxidized Met) carries both mass deltas on every recomputed fragment
  (fails on the current `DecoyGenerator`); the `ProbeOnce` failure-not-cached case; a/c/x/z
  names counted separately from unreadable ones; and a pipeline leg that searches an ANNOTATED
  blib built from the subset library, showing its decoys now differ from their targets.
- Red before green: each fix above gets a test that fails without it, and the PR says so.

### R7. Part A review items
- `DecoyGenerator.cs:716-727` still overwrites stacked mods (`modMasses[newPos] = m.MassDelta`);
  use `PeptideFragmentMass.ModMassesByPosition`. Changes TSV decoys (N-term acetyl + Met ox), so
  it needs a key term and a Rust check.
- `BlibLoader.ProbeOnce` caches `false` on any exception; cache only successes.
- a/c/x/z ion names are counted as "unreadable" (`BlibPeakAnnotations.cs:105-108`).
- Version `;libext=ann` (e.g. `ann2`) like `blib_reader:2`.
- Annotation cursor `ORDER BY RefSpectraID, peakIndex, id` sorts the whole table unindexed;
  `ORDER BY RefSpectraID, id` suffices. Time the precision probe on a large blib.
- Blibs without annotations (including Osprey's own output) still give decoys identical to
  their targets; `BlibWriter` should write `RefSpectraPeakAnnotations` (follow-up). The #4360
  branch turns the resulting `LinearDiscriminant` crash into a plain error.
- `docs/01-decoy-generation.md:191` still places `CalculateFragmentMz` in `DecoyGenerator`.

### R10. BLIB writing belongs in PR A (#4730) - decided 2026-09-28 (Brendan)
Brendan is taking #4730 to merge. Instead of a test-only helper that builds an annotated blib
(the first R6 leg did exactly that, in `SubsetPipelineTest.WriteSubsetLibraryBlib`), #4730 gets
the production utilities, and the tests use them:
1. **Osprey writes fully annotated output blibs.** `BlibWriter` writes one
   `RefSpectraPeakAnnotations` row per peak whose ion type is known, in the grammar
   `BlibPeakAnnotations` reads (`y5`, `b3-H2O`, charge column, `mzTheoretical`), plus proteins.
   An Osprey output blib then searches as a library with real decoys (today it is refused by the
   #4727 decoy check, every decoy copying its target).
2. **Any loaded library can be persisted as a fully compatible BLIB** (targets, fragments with
   annotations, proteins, library RT, modifications in blib mass form): a library-to-blib utility,
   exposed as a command-line option, readable by Skyline and re-importable by Osprey.
3. **Tests use the utilities**: TSV -> BLIB -> search equals the TSV search (tight tolerance);
   Osprey's own output blib searches back; the refusal leg keeps an unannotated blib.
Future, NOT in #4730: a shared BLIB writer/reader in `pwiz_tools/Shared/BiblioSpec` used by Skyline
and Osprey, and BLIB replacing `.libcache` as the library cache (Nick's Skyline BLIB-reader work
made a private cache unnecessary there; measure load time vs `.libcache` on full Astral first).

### R8. Code coverage must show the new code is exercised
Run `pwsh -File ./ai/scripts/Osprey/Build-Osprey.ps1 -Configuration Debug -Coverage` and
`ai/scripts/Osprey/Summarize-Coverage.ps1` on each PR's final state, and put in its test plan:
- overall Osprey coverage before and after (it must not drop; it was 83.3% on the #4360
  branch);
- the statement coverage of every NEW type (`BlibPeakAnnotations`, `FragmentLadder`,
  `PeptideFragmentMass`, `TrainingEvidence`, `TrainingExportParquet`, `ParquetBlobCodec`, the
  export arm in PerFileRescoring, ...): each at least 80%, with any uncovered block named and
  justified (e.g. an I/O error path);
- coverage of the CHANGED lines in existing types (`BlibLoader`, `DecoyGenerator`,
  `PerFileRescoreTask`), from the dotCover snapshot.
Coverage that comes only from unit tests of pieces, with nothing through the pipeline, does not
meet R6 even when the percentage is high.

### R9. Part B smaller items
- The "mp_cosine parity N/N" line counts peaks with no fit as matches
  (`TrainingEvidence.cs:99-101`); log the fitted count beside it.
- Decide and document the exit code when one run's export fails after the blib is written; as
  posted it sets exit 1 and stops the remaining runs (`TrainingExportTask.cs:209-214`).
- Run `Test-PerfGate.ps1 -Dataset Stellar` if anything on the default path still changes after
  R3 (as posted, `RunInfoCollector` adds per-spectrum work to every parse).

## Verified facts (on `origin/Skyline/work/20260612_net8_port` @ `40312c7979`)

- `BlibLoader.DecodeBlibPeaks` makes every fragment IonType.Unknown (ordinal i+1, charge 1);
  `DecoyGenerator.RecalculateFragments` copies non-B/Y fragments, so generated decoys of a
  blib keep the target's m/z. `BlibWriter` creates `RefSpectraPeakAnnotations` empty.
- Skyline reads `RefSpectraPeakAnnotations` for every blib (`BiblioSpecLite.ReadPeakAnnotations`):
  it `Assume.Fail`s when `mzObserved` differs from the peak m/z by >1e-7 and calls GetString on
  every text column (NULL throws). No existing writer names peptide fragments - the grammar is ours.
- `LibraryDeduplicator` renumbers ids 0..n-1 by (ModifiedSequence, Charge), so RefSpectraID-keyed
  data must be resolved to (peptideModSeq, charge) inside BlibLoader.
- Osprey captures no NCE or instrument metadata. The net8 `MsDataFileImpl`
  (`pwiz_tools/Shared/ProteowizardWrapper.PwizSharp`) exposes `GetInstrumentConfigInfoList()`,
  `MsPrecursor.PrecursorCollisionEnergy`, `DissociationMethod`, `GetSpectrumMetadata(i)`;
  `SpectrumFileReader.AddSpectrum` drops them.
- `scan_number` in parquet is the 0-based source spectrum index (no nativeID anywhere).
- `FdrEntry.StartRt/EndRt/ApexRt` are exact window-spectrum RTs; reconciled parquet has final
  boundaries, `.2nd-pass.fdr_scores.bin` run q, `<blib>.2nd-pass.fdr_experiment.bin` experiment q/PEP.
- All four regression datasets use TSV libraries, so part A needs its own tests.

## Step 1 - output-neutral refactors (own commit; full regression + perf gate)

- `Osprey.Core/PeptideFragmentMass.cs`: move `DecoyGenerator.STANDARD_AA_MASSES`, `PROTON_MASS`,
  `H2O_MASS`, `CalculateFragmentMz`; DecoyGenerator delegates. New `Osprey.Core/FragmentLadder.cs`
  (b/y z1/z2, AlphaPeptDeep slot order p*4+t, t in [b_z1,b_z2,y_z1,y_z2]; NaN when z > min(zprec,2)).
- `ScoringPipeline`: extract `DoubleCountingTolerance(ms2Cal, cfg, ...)` and `DoubleCountingRtNeighborhood(ms2Rts)`.
- `TukeyMedianPolish.FragmentR2` (MinFragmentR2 calls it).
- `SpectraWindowIndex.BuildFromCache(loadMs1: false)` overload.
- Move `PerFileRescoreTask.LoadSpectraForRescore` / `LoadMassCalibrations` to `ScoringTaskShared`.
- Parquet blob encoders internal/shared (`ParquetBlobCodec`); `SearchIdentity.FileIdentityTerm`.

## Step 2 - part A (Osprey.IO/BlibLoader.cs, LibraryLoader.cs, new BlibPeakAnnotations.cs, BlibDecoyPairs.cs)

- Annotation grammar `<ion><ordinal>[-<loss>]` (a/b/c/x/y/z; loss H2O | NH3 | H3PO4 | decimal
  mass snapped within 0.005 Da); `charge` column wins, lenient `^2`/`++`/`+2` suffix when 0/NULL.
  Validate each against recomputed m/z (max(0.02 Da, 20 ppm)); failures stay Unknown and are counted.
  Merge-join `SELECT RefSpectraID, peakIndex, id, name, charge, adduct, mzTheoretical ... ORDER BY
  RefSpectraID, peakIndex, id` with the spectra cursor. Absent/empty table = unchanged behavior.
- Writer rules (doc 13): text columns empty strings never NULL; `mzObserved` == peak m/z exactly.
- `LibraryCompositionHash`: append `blib_reader:2` only for blib sources. Validity key suffix
  `;libext=ann[,pairs]` only for annotated/paired blibs (never touch SearchParameterHash/LibraryIdentityHash).
- `DecoyPairs(RefSpectraID, IsDecoy, IsEntrapment, PairID, Method)` (Carafe fork, pair semantics):
  keyed by (modseq, charge); library-decoy mode order = prefix marking -> DecoyPairs -> recount ->
  manifest -> composition; `PairingStats.NPairedViaLibraryTable`, logged only when > 0. Generated
  mode: one warning, no change. `BlibDecoyPairs.ReadEntrapmentKeys` for the export.
- Tests: `BlibLibraryInputTest` (grammar table, typing, rejection, cache round trip, blib-vs-DIA-NN-TSV
  parity), `TestBlibDecoyPairs`, `TestAnnotatedBlibDecoyGeneration`, `FragmentLadderTest`, validity-key test.

## Step 3 - run metadata (SUPERSEDED by R3: no run-info.json)

- `<stem>.run-info.json` beside `.spectra.bin`, written in `ScoringTaskShared.EnsureSpectraCache`
  through FileSaver before the cache: instrument model/vendor/serial/analyzer, run start, MS1/MS2
  counts, MS2 scan window (first ~200 spectra), dissociation-method and collision-energy
  histograms, source fingerprint (size, mtime ms). `.spectra.bin` unchanged.
- rt_max and the isolation range come from `SpectraWindowIndex` (AllMs2Rts, IsolationWindows).

## Step 4 - part B: TrainingExportTask (SUPERSEDED by R2: a PerFileRescoring product, not a stage)

- Optional fifth fan-out task after SecondPassFDR (`TASK_NAME = "TrainingExport"`, appended to
  HpcTask; `IsIncluded = cfg.TrainingExport.Enabled && ...`; `--task TrainingExport` selects a
  one-task list). Not Stage 7 (SecondPassFDR is a join with no spectra; adding outputs there
  would re-run the join) and not Stage 6 (no experiment q/PEP yet). Pay-later: adding the flag to
  a finished run runs only this task.
- CLI (OspreyCommandArgs, Argument instances): `--training-export`, `--training-export-max-q`
  (default --run-fdr), `--training-export-claimant-q 0.01`, `--training-export-xics`.
- Output `<stem>.training.parquet` (ZSTD, FileSaver, validity sidecar; zero-row file when empty).
  Validity key = base + fdrsidecar version + `pass2exp=` file identity of the experiment sidecar +
  `;trainexport=1;maxq=;claimq=;xics=`; omits the -i-subset reconciliation hash (P4).
- Per precursor: entry/base id, is_decoy, is_entrapment, peptide_kind, sequence, modified sequence,
  mod positions/masses/unimod ids, charge, precursor m/z, library RT, proteins, file, scan_number,
  apex/start/end RT, n_peak_scans, isolation bounds, bounds_area, coelution_sum, 2nd-pass score,
  run and experiment q, PEP, apex TIC, explained intensity, n ions observed, median-polish summary
  (converged, iterations, overall, cosine, residual MAD, core source), boundary medians,
  claimant and DDC-neighbor counts.
- Per ion (4*(L-1) slots): m/z, flags (applicable, in scan range, matched at apex, core, library
  annotated), observed apex intensity and mass error, library relative intensity, finite-scan count,
  XIC start/end/max, correlation to the polish profile and to the reference XIC, polish row effect,
  R2, positive-residual max, apex residual, outlier z, apex ratio, relative intensity,
  shared_apex/shared_coelute counts, min claimant q, better-claimant flags. Optional XIC matrix.
- Median polish reuses Osprey's fit: core = `TopFragmentExtractor.ExtractFragmentXics` over the
  final boundaries -> `TukeyMedianPolish.Compute(core, rts, 10, 0.01)`, byte-identical to
  CoelutionScorer; every ladder ion is projected on (Overall, ColEffects). Built-in check:
  `mp_cosine` equals the reconciled parquet's `median_polish_cosine` for every row.
- Shared evidence: apex scope (same apex scan and peak index - Carafe semantics) and co-elution
  scope (claimant's [start,end] contains the apex and its ladder is within the calibrated
  tolerance - Osprey semantics); DeduplicateDoubleCounting neighbor count.
- Tests: TrainingEvidenceTest, TrainingExportParquetTest, RunInfoFileTest, membership/CLI/
  validity-key updates; regression.ps1 mode 13 (pay-later, resume, relay task, zero mp_cosine
  mismatches). Docs 00, 13, 14, 15, 19, 20 and new 21-training-export.md.

## Progress Log

### 2026-09-23
- Worktree `D:\Dev\pwiz-osprey-export` from `origin/Skyline/work/20260612_net8_port` @ `bba770990a`.
- This machine has only VS 2022 (MSBuild 17.14), which cannot load the .NET 10 SDK the #4619
  branch needs (MSBuild 18). `ai/scripts/Osprey/Build-Osprey.ps1` now falls back to the SDK's own
  msbuild and test runner in that case. Baseline on the branch: 598 tests pass.
- Step 1 (partial): `Osprey.Core/PeptideFragmentMass.cs` - residue masses, PROTON/H2O and
  `CalculateFragmentMz` moved verbatim out of DecoyGenerator, which delegates (TheoreticalLadder too).
- Step 2 (part A, annotations): `Osprey.IO/BlibPeakAnnotations.cs` (grammar; one annotation per
  peak - no loss first, then lowest charge; m/z validated at max(0.02 Th, 20 ppm); b/y only),
  merge-joined in `BlibLoader.LoadSpectra` through a second ordered cursor; one summary log line;
  `LibraryCompositionHash` gains `blib_reader:2` for blib sources only. Test
  `BlibLibraryInputTest` (grammar table, typing, rejection, preference, plain blib unchanged,
  generated decoys recompute annotated m/z).
- **Scope change (proposed):** DecoyPairs support deferred. Osprey's existing
  `--decoy-pairing-manifest` path already pairs Carafe-style libraries and is regression-tested;
  CarafeSharp writes `decoy_` accessions plus the FDRBench manifest exactly as Carafe does.
- Part A committed `cdbab8c8ac` (600 tests, inspection clean). Developer approved the regression
  bundle download (14.3 GB actual, `~/Downloads/Perftests`). `regression.ps1 -Dataset Stellar -NoBuild`
  from a detached gate worktree `D:\Dev\pwiz-osprey-gate` at `cdbab8c8ac` (Release built there, so
  part B edits in the main worktree cannot leak in): **PASSED** all modes (1, 1c, 2, 3, 4, 5, 6).
  Note: `regression.ps1`'s own build step uses VS MSBuild, so on a VS 2022 machine build Release
  with `Build-Osprey.ps1 -Configuration Release -SourceRoot <tree>` first and pass `-NoBuild`.
- Build race on the #4619 branch: two configurations of pwiz-sharp's `Vendor.Common` build in
  parallel and both run `VendorPinsGenerator`, so one fails to write its dll ("being used by another
  process"). Rerunning the build succeeds. Worth reporting on #4619.
- Part B `0a0b74432a`: `regression.ps1 -Dataset All -NoBuild` from the gate worktree (Release
  built there) **PASSED**: 42 phases over Stellar, StellarLibDecoy, StellarGenDecoyEntrap and Astral,
  3.9 h wall on a contended machine (log `ai/.tmp/sessions/20260923-carafesharp/gate-all.log`).
- Part A in use: a CarafeSharp blib (968,437 spectra, 16.9M peaks) loads with 0 annotation
  failures; Skyline-daily 26.1.1 (SkylineCmd) opens CarafeSharp blibs with peak annotations.
  Part B in use: exports on Stellar _21 (Carafe TSV and CarafeSharp blib libraries), mp_cosine
  parity 23,036/23,036 and 23,105/23,105; CarafeSharp trains on them (85% slot agreement with Carafe).
- Found while comparing libraries: the Stellar experiment-level count is bimodal (about 21k or
  28-30k at the same FDP) on 1e-4 library changes; see the CarafeSharp TODO. Separate task.
- Not done yet: the perf gate (`Test-PerfGate.ps1 -Dataset Stellar`, needs an uncontended machine).

### 2026-09-24
- `/code-review max` (11 finder angles, 9 verifiers, sweep; diff `ai/.tmp/sessions/20260923-carafesharp/export-review.diff`):
  15 reported, all fixed in the review commit, then the branch was squashed to ONE commit `255ad17504`
  (backup ref `backup/export-pre-squash-25b8316`). The fixes:
  - `ModMassesByPosition` sums stacked mods (N-term + residue 0); DecoyGenerator's own last-wins map is untouched
    (matches Rust and the goldens; decoy b ions of such targets still lose the N-term mass - a separate, gated change).
  - `;libext=ann` task-key term and `blib_reader:2` libcache term only for blibs whose annotation table has rows;
    `blib_mods:2` libcache term for blibs with low-precision or 100-200 mod text (re-parse once).
  - Blib mod masses: absolute-Cys reading only on unsigned C text; snap tolerance max(0.01, half the last digit).
  - `--task TrainingExport` validates upstream footers (`ValidateScoresParquetGroup` overload) and refuses a row whose
    sequence/charge differ from its library entry.
  - Per-run export key (`OspreyTask.OutputValidityKey`): reconciled parquet, 2nd-pass sidecar, run-info identities;
    stale run-info (fingerprint vs `.spectra.bin` header) ignored; relay must keep mtimes (`cp -p`).
  - 2nd-pass records paired by (entry_id, apex-RT bits); collisions throw.
  - NaN custom loss rejected; separate out-of-range annotation counter; log line only when the export runs.
  - Shared `TukeyMedianPolish.SCORING_*` polish arguments; parity test now runs the real CoelutionScorer.
  - Projected reconciled read (`LoadTrainingExportRows`) and `RetainFragmentsFor` on pay-later loads.
  - run-info v2: per-isolation-window MS2 scan ranges, UTC start time, `\n` JSON; v1 still read.
  - `ddc_neighbor_n` asks pairs in the dedup's order; `DoubleCountingTolerance` delegates to `CalibratedTolerance`.
  - Style, ASCII dashes, stale docs (four tasks -> five; NThreads windows resident).
  Gate: 606/606 tests, 0 inspection warnings.
- Open questions for the developer: drop `ddc_neighbor_n` (about 0 by construction, unread by CarafeSharp)?
- End-to-end on Stellar _21 with the annotated CarafeSharp blib (`D:\test\osprey-runs\export-smoke-255ad17`): straight-through
  mp_cosine parity 23,169/23,169; pay-later skipped all four upstream tasks and wrote data identical to the
  straight-through export; `--task TrainingExport` re-run skipped as current; run-info v2 with 125 window ranges.
- `regression.ps1 -Dataset All` (options off): PASSED (`ai/.tmp/sessions/20260923-carafesharp/export-regression-all.log`).
- PR #4708 opened against the port branch.
- Copilot review (7 threads) addressed in `481e75680a`: `;libmods=2` task-key term for blibs whose mod text the
  new reader parses differently; `;calib=`/`;spectra=` in the per-run export key; malformed caret charge
  suffixes rejected; structurally damaged run-info reads as absent; docs/14 v2. Not changed: `double.IsFinite`
  (net10.0-only build); DecoyGenerator's last-wins stacked-mod map (pre-existing, mirrors Rust).
- Follow-ups: DecoyGenerator stacked mods at one position (change C# and Rust together); `ddc_neighbor_n`
  removal is #4709 (developer: leave for now, low priority). Remaining here: perf gate (needs a quiet machine).

## Risks
- (Resolved) Skyline loads peptide fragment annotations from a CarafeSharp blib.
- Osprey XICs take the closest peak unsmoothed; Carafe the max within tolerance with Savitzky-Golay.
  Carafe's 0.8 correlation threshold may need retuning (XIC blobs allow recomputing).
- NCE semantics differ by vendor (Thermo NCE, Sciex eV, stepped HCD) - export the histogram.

## Gates
- `pwsh -File ./ai/scripts/Osprey/Build-Osprey.ps1 -Configuration Debug -RunTests -RunInspection`
- `pwsh -File ./pwiz_tools/Osprey/regression.ps1 -Dataset Stellar`, then `-Dataset All` (options off, 1e-9)
- `pwsh -File ./ai/scripts/Osprey/Test-PerfGate.ps1 -Dataset Stellar`
- `pwsh -File ./ai/scripts/Osprey/Build-Osprey.ps1 -Configuration Debug -Coverage` + `Summarize-Coverage.ps1`, numbers in the PR test plan (R8)
- `SubsetPipelineTest` legs for the export (R6) pass, and each fix's test fails without its fix
- TeamCity Perf/Regression only on the finished PR candidate, and only after asking. Review requested from Brendan (2026-09-25); he triggers the TeamCity Osprey Perf/Regression run - the developer (Mike) has no trigger access, so do not ask him to.

### 2026-09-28 (Brendan session) - #4730 taken to merge

Mike split part A out as #4730 (R1, R7 done, own `/code-review max`, CI green). Brendan decided to
finish #4730 here and leave #4708 (part B, R2-R6) to Mike. In `C:\proj\pwiz-work1`, branch
`Skyline/work/20260928_osprey_blib_annotations` (NOT pushed, 3 commits ahead of origin):
merged the port branch (brings #4727: `SubsetPipelineTest`, `InProcessOsprey`, subset zips) with no
conflicts, and added `TestSubsetAnnotatedBlibLibrary` (d06c03edc2): an annotated blib of the
subset library gives first-pass counts identical to the TSV (128/154/143) and passes; the
unannotated version is refused. Full gate on the merged state: 620 tests, inspection clean.
Found (pre-existing, not yet filed): a library with no protein information cannot finish
second-pass FDR (no protein has 2 detections -> empty stratum -> "Second-pass FDR cannot run");
the test blib now carries proteins via `BlibWriter.AddProteinMapping`. Next: R10.

### 2026-09-28 (Mike session) - #4708 reworked as a PerFileRescoring product (R2-R5, R9)

In `D:\Dev\pwiz-osprey-export`, branch `Skyline/work/20260923_osprey_carafe_export` (stacked on
the pushed #4730 head f7f28dd1a9; NOT yet merged with Brendan's unpushed #4730 work). Commits
b76267f9f9 (R2-R4), 9a59d07c3f (R5 docs, key fix, tests), f636fb2b6f (`/code-review max`
fixes), local until pushed.
- R2: the export is a declared output of PerFileRescoring, written in flight after the per-run
  second pass or by an export-only arm (`OnlyTrainingExportsOutstanding`); `--task
  TrainingExport` is a selector; the pipeline is four stages again.
- R3: no run-info.json; per-window scan range from the spectra (`ObservedMzRange`); instrument
  and activation footer keys from the data file when present (first 200 MS2 spectra).
- R4: format v2 without experiment q/PEP; run q from the worker's pass-2 sidecar (its stamp AND
  its decoys file - the driver stamps every existing declared output, so the stamp alone can be
  a SecondPassFDR file), else pass 1 with `run_q_pass=1` and a warning; transfer refused.
- R5: P17 in docs/00; fifth-stage text removed from docs 14/15/20/22, help, ModelDiagnosticsTask;
  doc 13's leftover copy of part A's sections removed.
- R9: fitted parity count; failure policy (others still export, task fails before the blib, a
  re-run retries only the failed exports - measured); OOM propagates, defects keep their stack.
- Verified: 617/617 + zero inspection; Stellar 3-run exports byte-identical flag-up-front vs
  pay-later (pay-later 15 s, three upstream tasks skipped, nothing re-scored); blib tables equal
  with and without the flag (only `LibInfo` differs); single-run analysis selects on pass 2 and is
  stable over three invocations; failure injection + retry byte-identical.
- `/code-review max`: 15 findings, all fixed. Pre-existing issues it found are drafted, NOT filed,
  in `ai/.tmp/sessions/20260927-osprey-export/issue-drafts.md` (driver stamps outputs a task did not
  write; a no-work run keeps PerFileRescoring never current; stamp bytes grow as runs squared;
  pwiz-sharp VendorPinsGenerator CS2012 build race).
- Still open for #4708: R6 pipeline legs (after Brendan's #4730 push brings #4727's
  `SubsetPipelineTest`; then merge #4730 into this branch), R8 coverage (dotCover blocked on this
  machine), perf gate on a quiet machine, TeamCity (ask Brendan).

### 2026-09-28 (Mike session, later) - #4708 R6 and R8 done, merged with #4730

- Merged the port branch (#4727) and then Brendan's pushed #4730 (d2aa967af6, R10) into #4708;
  one conflict (Program.ValidateArgs: `--export-library` check kept first, then the export check).
  Pushed a5d15e6a4f; GitHub reports it mergeable. #4708 stays a draft.
- R6: `Osprey.Test/SubsetPipelineTest.TrainingExport.cs` (SubsetPipelineTest made partial): Stellar
  up front / pay-later / repeat / `--task TrainingExport` / second pass outstanding / failure and
  retry; Astral HRAM; a `--task PerFileRescoring` node; library decoys + entrapment; the one-run
  no-rescore case (pass 1 + warning, stable; accepts #4729's SecondPassFDR error until it is fixed).
- R8 (needs VS 2026; `pwiz_tools/Osprey/build.ps1 -Coverage`, dotCover 2023.3.3): overall 83.3% on
  #4730 + #4727 vs 84.0% with #4708; `TrainingExportWriter` 87.3%, `TrainingEvidence` 98.3%,
  PerFileRescoring export methods 97-100%. Numbers are in the #4708 test plan.
- Gate on the merged head: 631/631, zero inspection warnings. Filed #4731-#4734 (issue drafts).
- Still open: perf gate on a quiet machine; TeamCity (ask Brendan).

### 2026-09-28 (Brendan session, evening + night) - R10 done, #4730 merge candidate
- **R10**, pushed as d2aa967af6 (Mike merged it into #4708) and 2e88e21746 (review fixes, NOT yet in
  #4708 - merging it will conflict in `Program.ValidateArgs` again, where the export check moved to
  the top of the method):
  - `Osprey.IO/BlibSpectrum.FromLibraryEntry` is the one LibraryEntry-to-blib-rows composition
    (Brendan: no second copy), used by the search output (`BlibOutputWriter.PrepareSpectra`, in
    parallel), `--export-library` (`LibraryBlibWriter`, parallel blocks of 10,000) and the old
    convenience overload; `BlibWriter.AddSpectrum(BlibSpectrum, ...)` writes it.
  - Peaks sorted by m/z (Brendan: better for Skyline; Skyline `ReadPeaks` keeps stored order).
    Modseq from `Modifications`, masses as `+0.0###` (keeps printed precision: `K[+114.0]` stays,
    Skyline matches at the printed precision); an entry whose text has more mod tokens than parsed
    mods keeps its own text (no two precursors share a key). One `RefSpectraPeakAnnotations` row per
    b/y peak whose recomputed m/z matches (ordinal < length; custom losses printed with >= 4
    decimals); `mzObserved` = peak m/z exactly (Skyline asserts 1e-7).
  - `;blibout=2` (`BlibSpectrum.FORMAT_VERSION`) in the SecondPassFDR key, unconditional.
  - Export: one RetentionTimes row per spectrum (rt, NULL start/end); column-only decoys get the
    first decoy prefix on their accessions; progress; locked output -> `BlibOutputException`;
    validated and dispatched before input checks; refuses `--export-library` == `--library`.
  - Fixed the output blib keeping `[UniMod:N]` text for ids outside the writer's table (Skyline's
    `MassModification.Parse` accepts only numbers).
- Goldens: only `tables/PeakDigest.tsv` recaptured (every spectrum re-sorted); `blib_summary.tsv`
  recapture was last-digit sum-order noise, restored.
- Rust parity PR maccoss/osprey#72 (`fix/sort-blib-peaks`, stable m/z sort in `add_spectrum`):
  Stellar `Compare-EndToEnd-Crossimpl -Files All` OVERALL PASS, 0/31,720 peak blobs divergent.
  Running Rust needs `C:\vcpkg\installed\x64-windows\bin` on PATH (0xC0000135 otherwise).
- Second `/code-review max`: 15 findings, 10 fixed; dropped as pre-existing/out of scope: wrong
  masses for UniMod 28/122/214/312/385/747 in `DiannTsvLoader.UnimodIdToMass` (and Rust);
  HPC join adopts worker parquets by footer only (under version override); one-decimal unknown blib
  mods not refined from the Modifications table; the reader-version probe gating design; export
  journal mode. NEEDS BRENDAN: BiblioSpec `BlibMaker::transferPeakAnnotations`
  (BlibMaker.cpp:1025-1039) formats text columns unquoted, so BlibBuild cannot merge ANY annotated
  blib (CarafeSharp's too, now Osprey's) - fix is `sqlite3_snprintf` + `%Q`; needs a BiblioSpec
  build, separate pwiz PR.
- Gates (final): 621/621 en/ja-JP/fr-FR, inspection clean; coverage 83.4% (BlibSpectrum 99%,
  LibraryBlibWriter 98.1%, BlibPeakAnnotations 100%, FragmentLadder 100%, BlibWriter 90.8%,
  Program 88.1%, BlibOutputWriter 87.2%, BlibLoader 81.2%). regression-parallel All and TeamCity
  Perf/Regression (build 4192947): see the night-session report.

**PR B (#4708), 2026-09-28 night session:**
- Perf gate PASSED: `Test-PerfGate.ps1 -Dataset Stellar`, a5d15e6a4f against #4730's head d2aa967af6 (a new
  baseline worktree `D:/Dev/pwiz-perfbase-4730`; the shared pwiz-perfbase was left alone). Median total wall
  5:02 vs 5:00, +0.2% (per repeat +0.2 / +2.8 / -1.6), no stage flagged. Verdict:
  `ai/.tmp/perf-gate/20260929-060001Z/verdict.md`.
- Merged #4730's 2e88e21746 (ae0b22806d): conflicts in `Program.ValidateArgs` (kept #4730's `--export-library`
  check at the top, then `TrainingExportError`) and `OspreyResources.resx` (both sides' strings). 631/631,
  inspection clean, pushed. PR body updated (perf + consumer check).
- Consumer check: the Stellar `_21` export this build wrote from the .raw (22,761 rows, second-pass run q)
  gives CarafeSharp's masking parity 85.0%, and CarafeSharp's 68 tests pass on it (#4717 reads format 2).
- Remaining: TeamCity Perf/Regression (ask first); #4729 (Brendan's) still blocks the single-run leg's
  SecondPassFDR.
