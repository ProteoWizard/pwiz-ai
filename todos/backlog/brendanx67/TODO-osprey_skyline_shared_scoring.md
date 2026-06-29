# TODO: Skyline peak-scoring <-> Osprey scoring — shared-architecture exploration

**Status**: Backlog (design exploration / decision — NOT a coding task yet)
**Priority**: Medium-strategic (no defect; governs the DLL-boundary decision and how Osprey scores eventually reach Skyline)
**Created**: 2026-06-01
**Scope**: `pwiz_tools\Skyline\Model\Results\Scoring`, `pwiz_tools\Osprey\Osprey.Scoring` (+ the scoring code in `Osprey\Tasks`), `pwiz_tools\Shared\Common*`

## Why this exists

Mike wants some Osprey scores available in Skyline's peak-scoring system. Brendan
(2026-06-01) asked whether, instead of one-off porting, the two scoring systems could
share a common architecture (possibly hosted in `pwiz_tools\Shared\Common*`), and
whether that prospect should change the Osprey DLL-boundary decision (see
[[TODO-osprey_assembly_consolidation]]). This doc records a 3-subagent research
synthesis so the decision can be made deliberately later. **No code was changed.**

## The two architectures (as mapped 2026-06-01)

**Skyline (the peak-scoring architecture Dario Amodei helped design)** —
`Model\Results\Scoring\IPeakScoringModel.cs`:
- Clean SPI: `IPeakFeatureCalculator.Calculate(PeakScoringContext, IPeptidePeakData)`,
  split into `SummaryPeakFeatureCalculator` / `DetailedPeakFeatureCalculator`. Each
  score is a small class; identity persisted by `Type.FullName`.
- **Context** = thin: `SrmSettings` + a type-keyed shared-base-calc cache
  (`AddInfo<T>`/`TryGetInfo<T>`) scoped to one peak group — e.g. one cross-correlation
  matrix shared by all shape/co-elution calcs.
- **Data** = chromatogram-centric tree (`IPeptidePeakData` -> transition-group ->
  transition -> `ISummaryPeakData`/`IDetailedPeakData`): interpolated XIC Times/
  Intensities + per-ion areas + RT/Fwhm/massError.
- **No spectra.** Confirmed: a calculator cannot get individual or apex spectra (raw
  files are never fully resident; chromatogram-centric by construction).
- Discovery = a hard-coded ordered `PeakFeatureCalculator.CALCULATORS` array (weights
  persisted positionally). Back end: float[] -> `LinearModelParams.Score` -> mProphet/
  q-value.
- Bound to Skyline domain types (`PeptideDocNode`/`TransitionGroupDocNode`/`SrmSettings`).

**Osprey** — `AbstractScoringTask.ScoreCandidate` (~870 lines) +
`Osprey.Scoring`:
- **Procedural, not per-class.** ~21 PIN features written positionally into a
  `double[21]`; computed by inline blocks + private helpers on the task. No calculator
  objects, no registry, no per-feature identity.
- A `ScoringContext` exists but is a *config + buffer-pool* carrier, not a data-accessor
  / shared-calc cache. Scoring data is passed as explicit parameters down the call tree.
- **Spectra fully in memory** (`Spectrum`/`MS1Spectrum`, incl. apex). Unit of scoring =
  one precursor (`LibraryEntry`) at its best peak within one isolation window -> one
  `FdrEntry`.
- Back end: float[21] -> Percolator (SVM, in `Osprey.ML`) -> q-value.
- Saturated with Rust bit-for-bit parity invariants (exact eval order, `>=`-on-tie
  selection) — any decomposition is mechanical-but-delicate, gated byte-identical by
  `Compare-EndToEnd-Crossimpl`.

## The governing constraint: the spectrum wall partitions Osprey's scores

Skyline's context structurally cannot supply spectra; ~half of Osprey's features
*require* the apex/per-scan spectrum. So which Osprey scores can run in Skyline at all
is decided by this wall:

- **Portable to Skyline today** (computable from extracted chromatograms / per-ion
  areas, which `IDetailedPeakData` already exposes): the **coelution** family, **peak-
  shape** (apex/area/sharpness), and the **Tukey median-polish** residual features
  (mpCosine, mpResidualRatio, mpMinFragmentR2, mpResidualCorr).
- **NOT portable without extending Skyline's results layer** (need apex/per-scan
  spectrum): **xcorr, sg_xcorr, libCosine, sg_cosine, explainedIntensity, massAccuracy,
  consecutiveIons, top-6 matches, ms1PrecursorCoelution, ms1IsotopeCosine**.
- Caveat even on the portable set: Osprey extracts XICs with its own tolerance/binning;
  run on Skyline's chromatograms the algorithm gives *similar, not identical* values
  (fine for a re-weighted model feature).

Giving Skyline's scoring context a spectrum/apex-spectrum provider is possible but is a
deep change to Skyline's *results* pipeline (the memory-driven thing the Dario design
deliberately avoided), not a scoring-layer change.

## Three tiers of ambition (with the recommendation)

1. **Pull-and-reimplement** (today's default): hand-port specific Osprey scores into
   Skyline calculators, using Osprey as the C# reference. Lowest risk; bounded to
   the portable subset; duplicates + drifts. Fine for "a few scores, soon."
2. **Shared SPI + shared back-end** (the leverage point — RECOMMENDED target): a *new,
   clean, multi-targeted* shared scoring core = capability-negotiated calculator/context
   interfaces (optional spectrum provider Skyline returns null for) + the
   feature-vector -> linear-model -> FDR math (both tools already converge here). Each
   tool keeps its own calculators + context impl. Can start with just the back-end.
3. **Mirror the full architecture on both sides** (the "very heavy lift"): re-express
   Osprey's procedural scoring as calculator classes over a Skyline-shaped context.
   Not crazy but high-cost + delicate (bit-parity per feature), and does NOT by itself
   deliver cross-tool sharing (the spectrum wall + domain binding remain). Payoff is
   symmetry, not sharing.

**Recommendation**: aim at tier 2; do tier 1 opportunistically for scores Mike wants
now. Tier 3's cost isn't justified by its (mostly aesthetic) payoff.

## Shared/Common* reality (hosting constraints)

- `CommonUtil` (net472, classic csproj) is the only dependency-light Shared foundation
  (Chemistry/mass, IProgressMonitor, SpectrumMetadata). `Common` is WinForms-heavy
  (but note: it already has a `PeakFinding` CWT detector that overlaps
  `Osprey.Chromatography`'s — a separate dedup opportunity). `CommonMsData` drags
  RemoteApi/x64/native ProteowizardWrapper.
- **Hard blocker**: every shareable Shared assembly is **net472 / Windows / often x64-
  native**; Osprey multi-targets `net472;net8.0` and ships standalone incl. Linux.
  So a shared scoring core must be **new, multi-targeted, dependency-clean** — NOT
  Skyline's `Scoring` namespace as-is (bolted to `SrmSettings`/DocNodes) and NOT
  `Common`/`CommonMsData`. Precedent for non-Skyline consumers of Shared exists
  (MSConvertGUI, SeeMS, the Executables tools) but all are net472/Windows.

## Implication for the DLL-boundary decision (links to [[TODO-osprey_assembly_consolidation]])

This **reverses** the earlier lean toward "collapse the middle." The boundaries
`Core / Scoring / FDR(linear-model)` are exactly the seams a future shared scoring core
(tier 2) would be carved along, and `Osprey.Scoring` already has the property a
Shared-bound assembly needs (dependency-light: no Parquet/SQLite/WinForms). Collapsing
them into the exe now would destroy that scaffolding and force a re-extraction later,
while the perf motive for collapsing is already nil.

**Decision (2026-06-01, Brendan): keep all 8 DLLs as-is for now.** No consolidation and
no shared-scoring code until the sharing direction is taken on fully. Preserve the
scoring/FDR seams as scaffolding. Revisit both together.

## What a future session would do (when ready)

- Decide tier 1 vs tier 2 with Mike, scoped to specific scores he wants in Skyline.
- If tier 2: prototype the shared back-end first (feature-vector -> linear model ->
  q-value) as a new multi-targeted assembly; then the capability-negotiated
  `IScoringContext` + calculator SPI; port the *portable-subset* Osprey scores as the
  first cross-tool calculators.
- Separately consider the duplicated CWT peak-detection (Common\PeakFinding vs
  Osprey.Chromatography) as its own shared-code opportunity.

## Related

- [[TODO-osprey_assembly_consolidation]] — the DLL decision this gates
- [[project_ospreysharp_exe_and_shared]] — the Shared-migration direction
- `Skyline\Model\Results\Scoring\IPeakScoringModel.cs` (IPeakFeatureCalculator,
  PeakScoringContext, LinearModelParams)
- `Osprey\Osprey.Scoring\ScoringContext.cs` + `SpectralScorer.cs`;
  `Osprey\Osprey\Tasks\AbstractScoringTask.cs` (ScoreCandidate, the 21 features)
