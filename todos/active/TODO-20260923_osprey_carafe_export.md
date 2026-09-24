# TODO-20260923_osprey_carafe_export.md

## Branch Information
- **Branch**: `Skyline/work/20260923_osprey_carafe_export` (not yet created)
- **Base**: `Skyline/work/20260612_net8_port` (PR [#4619](https://github.com/ProteoWizard/pwiz/pull/4619))
- **Created**: 2026-09-23
- **Status**: Not started (design below)
- **Module**: `osprey`
- **PR**: (pending)
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

## Step 3 - run metadata

- `<stem>.run-info.json` beside `.spectra.bin`, written in `ScoringTaskShared.EnsureSpectraCache`
  through FileSaver before the cache: instrument model/vendor/serial/analyzer, run start, MS1/MS2
  counts, MS2 scan window (first ~200 spectra), dissociation-method and collision-energy
  histograms, source fingerprint (size, mtime ms). `.spectra.bin` unchanged.
- rt_max and the isolation range come from `SpectraWindowIndex` (AllMs2Rts, IsolationWindows).

## Step 4 - part B: TrainingExportTask

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

## Risks
- Skyline has never loaded peptide fragment annotations - load a CarafeSharp blib in Skyline first.
- Osprey XICs take the closest peak unsmoothed; Carafe the max within tolerance with Savitzky-Golay.
  Carafe's 0.8 correlation threshold may need retuning (XIC blobs allow recomputing).
- NCE semantics differ by vendor (Thermo NCE, Sciex eV, stepped HCD) - export the histogram.

## Gates
- `pwsh -File ./ai/scripts/Osprey/Build-Osprey.ps1 -Configuration Debug -RunTests -RunInspection`
- `pwsh -File ./pwiz_tools/Osprey/regression.ps1 -Dataset Stellar`, then `-Dataset All` (options off, 1e-9)
- `pwsh -File ./ai/scripts/Osprey/Test-PerfGate.ps1 -Dataset Stellar`
- TeamCity Perf/Regression only on the finished PR candidate, and only after asking.
