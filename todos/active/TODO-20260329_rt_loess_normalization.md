# RT Loess Normalization

## Branch Information
- **Branch**: `Skyline/work/20260428_PeakScoringAndNormalization` (shared with sibling TODOs below)
- **Worktree**: `sky_peakscoringandnormalization` (second machine) / `sky_normalization` (this machine)
- **Base**: `master`
- **Created**: 2026-03-29
- **Status**: Superseded in direction on 2026-09-02 by [[TODO-20260902_pluggable_peak_detection_normalization]] (plug-in contract on the .NET 10 branch). Kept as a cherry-pick source; PR #4170 still open.
- **GitHub Issue**: [#4094](https://github.com/ProteoWizard/pwiz/issues/4094)
- **PR**: [#4170](https://github.com/ProteoWizard/pwiz/pull/4170) — bundled "New peak scoring and normalization options" (open)
- **Related**:
  - [[TODO-20260329_sum_coelution_score]] — sibling on same branch / same PR (#4096)
  - Also bundled in PR #4170: issue [#4097](https://github.com/ProteoWizard/pwiz/issues/4097) (peptide/protein rollup — no TODO file)

### Branch history
- Original per-feature branch was `Skyline/work/20260329_rt_loess_normalization`.
- First combined PR was [#4127](https://github.com/ProteoWizard/pwiz/pull/4127) on branch
  `skyline/work/20260329_PeakScoringAndNormalization` — closed (not merged) because the
  branch name had a lowercase "skyline". Superseded by PR #4170 on the correctly-cased
  branch above.


## Objective

Port the quantification methods from [skyline-prism](https://github.com/maccoss/skyline-prism) into Skyline so
they are available in Peptide Settings > Quantification and group comparisons without the external tool.

The first piece was "RT Loess" normalization: a LOWESS fit of peptide abundances across the RT gradient per
sample, with each sample's curve normalized to the median curve. This is how DIA-NN and MapDIA perform
normalization between samples. Tukey median polish rollups (transition -> peptide and peptide -> protein)
followed on the same branch.

Reference implementation (C#, .NET 10): `C:\git\skyline-prism\dotnet\src\SkylinePrism.Core`. The Python
engine the first round was verified against (v26.3.5) was removed from the PRISM repo on 2026-08-28; the
C# code reproduces it to 1e-9 on the deterministic stages.

## Tasks

### Round 1 - RT LOESS and median polish (done, in PR #4170)

- [x] Add RT Loess to NormalizationMethod.cs
- [x] Implement normalization data tracking in NormalizationData for different retention times (`RtLoessCurves`, `PolishedPeptideAbundances`)
- [x] Update PeptideQuantifier to use the RT Loess normalization factor
- [x] Make available in group comparisons and peptide settings > quantitation tab (separate peptide and protein rollup options)
- [x] Tukey median polish transition -> peptide and peptide -> protein (`MedianPolisher`, `MedianPolish.GetConvergedMedianPolish`, converged stopping rule, keys x replicates orientation)
- [x] Summed summary method
- [x] View > Peak Areas > RT LOESS Curves graph (legend, peptides toggle, adaptive alpha, replicate selection)
- [x] Respect MS level from QuantificationSettings in RT LOESS
- [x] Tests: `MedianPolishScenariosTest` (Small and Medium datasets, golden parquet files from skyline-prism), `RtLoessGraphTest`

### Round 2 - port the skyline-prism work done since May 2026

Surveyed 2026-09-01. Of 139 PRISM commits and 30 releases since the round 1 verification (v26.3.5),
these are the pieces that change what Skyline computes. Everything else (DuckDB merge, streaming,
memory budgets, stage caching, QC report and plot tabs, headless export handling, .NET 10) is
external-tool plumbing and is not portable.

Verified that PRISM's median polish and RT LOESS numerics did not change after round 1
(`TukeyMedianPolish`: tol 1e-4, 20 iterations; `RtLowessNormalize`: frac 0.3, 100 grid points,
20-point minimum), so the round 1 parity still holds.

- [ ] **ComBat batch correction** (PRISM v26.4.0 through v26.15.0). Standard empirical-Bayes ComBat plus the
      reference-anchored variant that estimates each batch's effect from the Standard-type replicates only.
      One estimator serves both (`BatchCorrection/ComBatCore.cs`, 554 lines, `ComBatPlan` chooses the fit set).
      Rules to preserve: every reduction ignores NaN by compacting observed values; a feature is held out
      unchanged when it has no variance or some batch never observed it; a (batch, feature) scale is skipped
      and excluded from the batch prior when the fit set has < 2 observations or spread below 1e-12 of magnitude;
      batches with 0 references fall back to location-only from the batch mean (`no_reference_batch`
      fallback/skip/error); correct each arm once at its reporting level (v26.15.0). Golden fixtures against
      R `sva::ComBat` 3.58.0 live in `dotnet/tests/fixtures/sva/` and `refanchored/`. Skyline has no batch
      correction today; needs a batch column source (replicate annotation, or per-document) and a settings UI.
- [ ] **Marker-protein normalization** (v26.19.0, `Normalization/MarkerNormalization.cs`, 224 lines). z-score
      each marker across samples (ddof=1, sd 0 left at zero), PC1 by SVD of the m x n block, sign-orient so the
      score correlates positively with the mean z-scored marker profile, then residualize every feature on
      [1, score] keeping the intercept. Runs after loading normalization (and after batch correction), score
      computed at protein level and applied to both peptide and protein output. Skip a feature with < 3
      observations or a constant score; hard error with < 3 quantified markers; warn when PC1 variance
      explained < 40%. Alternative `method: mean`. Maps to a new `NormalizationMethod` whose marker set is a
      Skyline protein list. PRISM ships 57 curated panels (`Qc/BuiltInProteinPanels.cs`), and matches
      `H4_HUMAN` / `H4_MOUSE` style names by stripping the species suffix.
- [ ] **Marker normalization diagnostics** (v26.20.0): per-sample score and per-marker loadings, flag when one
      marker carries > 50% of the loading. Report columns or a graph.
- [ ] **Additional protein rollups** (`Rollup/ProteinMatrixRollup.cs`): top-N (selection by median abundance or
      frequency), maxLFQ, iBAQ (needs theoretical peptide count). Add to `SummarizationMethod` for the protein
      level. Also consider transition-level consensus (inverse-variance weighted, regularization 0.1) and
      top-N (`Rollup/ConsensusRollup.cs`, `Rollup/TopNRollup.cs`).
- [ ] **Sample outlier detection** (`Normalization/OutlierDetector.cs`, 70 lines). One-sided low-signal only:
      per-sample median of 2^value on the linear scale, flag below Q1 - 1.5 IQR or below 0.1 x overall median.
      Report or exclude. Small; could surface as a replicate report column or annotation.
- [ ] **Median polish residuals as output** (v26.14.0). Both rollup stages write their residuals (Plubell et al.
      2022: a consistently large residual flags interference, a PTM, or processing). `MedianPolishResult`
      already holds them; expose as a report column at transition and peptide level.
- [ ] **Enzyme-aware protein parsimony** (v26.4.3, `Parsimony/ParsimonyEngine.cs`). A shared peptide is attached
      to a protein only when its termini are consistent with the digestion enzyme; shared-peptide handling
      `all_groups` / `unique_only` / `razor`. Lower priority: Skyline has its own protein association, so check
      whether the razor option is the only missing piece.

Suggested order: ComBat first (the one thing the external tool does that Skyline cannot), then marker
normalization, with outlier detection and residual output riding along with either.


## Progress Log

### 2026-03-29 - Session Start

Starting work on this issue. Key files identified by the issue:
- NormalizationMethod.cs - Add new normalization option
- NormalizationData - Track normalization factors per RT
- PeptideQuantifier - Apply the normalization factor
- Reference implementation: https://github.com/maccoss/skyline-prism/blob/main/skyline_prism/normalization.py

### 2026-05-20 - Cross-machine handoff (MedianPolishScenariosTest parity work)

This entry is the durable handoff (resuming on a **different computer**, so it lives in the
committed TODO, not in `ai/.tmp`).

**Goal of this session**: build `MedianPolishScenariosTest` to verify Skyline's per-peptide
quantities match the `skyline-prism` Python pipeline for each rollup/normalization method, using
parquet "expected" files that skyline-prism produces from the same `PRISM.parquet` Skyline export.

**What was done (committed in sky_normalization as `efce936b95 "Preparing to hand off."` on branch
`Skyline/work/20260428_PeakScoringAndNormalization`):**

- `MedianPolishScenariosTest.cs` (TestFunctional): exports the `PRISM` report to
  `PRISM-current.parquet` and asserts it matches the committed `PRISM.parquet` (`CompareParquetFiles`).
  Then verifies four per-peptide quantities via `VerifyPeptideAreas` against skyline-prism parquet:
  - `unnormalized_polished_peptides.parquet` — median-polish rollup (tol `_epsilon`=1e-6)
  - `unnormalized_summed_peptides.parquet` — sum rollup (tol 1e-2)
  - `median_normalized_peptides.parquet` — median-polish + EQUALIZE_MEDIANS (tol 1e-1)
  - `rtloess_normalized_peptides.parquet` — median-polish + RT_LOESS (tol 1), **skipped when
    `< MIN_PEPTIDES_FOR_RT_LOESS` (100) peptides** because sparse-data LOESS is unstable.
  - Helpers build a `PeptideQuantifier` with `ImputeMissingValues = true` and call
    `PolishUnnormalizedTransitions` / `GetPeptideLog2Abundances(AVERAGING)` /
    `GetMedianPolishQuantities(EQUALIZE_MEDIANS|RT_LOESS)`.
- `PeptideQuantifier.cs`:
  - Added `bool ImputeMissingValues` property (default **false**). Gates imputation of missing/zero
    transition cells (`impute = max(0.5*P1(positive),1.0)`) in the shared `GetTransitionLog2Abundances`
    used by both median polish and the AVERAGING sum. skyline-prism imputes for ALL methods; Skyline
    only matches when this is true.
  - Refactored `MedianPolishWithMethod` to use `GetTransitionLog2Abundances`; AVERAGING branch of
    `GetPeptideLog2Abundances` now sums the same imputed matrix when `ImputeMissingValues`.
  - Added `GetPeptideMeanRetentionTime(settings)` = single per-peptide mean of per-precursor peak RTs
    across ALL replicates. Replaced per-replicate `GetPeptideRtForReplicate` (removed) in
    `ApplyPeptideLevelAdjustment` so RT_LOESS evaluates the correction at one RT per peptide for every
    replicate — fixes peptides absent in a replicate getting nulled.
- `PolishedPeptideAbundances.cs`: sets `ImputeMissingValues = true` on its quantifiers; uses the new
  single per-peptide `GetPeptideMeanRetentionTime` for the LOESS curve x-values (removed per-replicate
  `GetPeptideMeanRt`).

**skyline-prism (SEPARATE repo `../skyline-prism`) — NOT yet committed (ACTION NEEDED):**
- `scripts/generate_peptide_rollups.py` is **untracked**. Point it at a folder containing
  `PRISM.parquet`; it runs skyline-prism's merge + Stage-2 rollup + Stage-2b normalization and writes
  the 4 expected parquet files. **Commit+push it to skyline-prism or it will not be on the other
  machine.** It needs Python deps `duckdb` and `statsmodels` (installed here via `pip install --user`;
  reinstall on the new machine).

**Build / run workflow (learned this session):**
- Build: `Build-Skyline.ps1 -SourceRoot <sky_normalization> -Configuration Release` works under Windows
  PowerShell 5.1. (We build/run **Release**; binaries in `pwiz_tools/Skyline/bin/x64/Release`.)
- `Run-Tests.ps1` does NOT parse under PS 5.1 (needs `pwsh` 7, which was not installed on this machine).
  Fallback that works: run `TestRunner.exe test=TestMedianPolishMedium` directly from the Release dir.
  On the new machine, check whether `pwsh` 7 is available and prefer `Run-Tests.ps1`.

**Status of the RT_LOESS fix verification — UNFINISHED:**
- `TestMedianPolishMedium` previously failed: `Assert.IsNotNull` on `VVERHQSAC(unimod:4)K` replicate 1
  (peptide only measured in replicate 0; Skyline's old per-replicate RT was NaN → nulled the value,
  while skyline-prism uses one mean_rt). The single-mean-RT fix above targets exactly this.
- A rebuild succeeded and `TestMedianPolishMedium` was re-launched but had **not finished** when the
  session ended — **re-run it on the new machine to confirm the fix passes** (and watch for any
  residual numeric RT-loess diff).

**Open decisions / caveats:**
- `ImputeMissingValues` defaults to **false**. `PolishedPeptideAbundances` and the test set it true, but
  other production median-polish callers (`ProteinQuantifier` two-stage, `Peptide` databinding column)
  still get false → they no longer impute. Decide whether to flip the default to true or set it at those
  call sites. (User guidance: match skyline-prism unless it's a real bug.)
- RT_LOESS may still differ numerically from skyline-prism beyond the single-RT fix because the LOESS
  engines differ: statsmodels `lowess` (it=3, delta speedup, all points) vs Skyline `LoessInterpolator`
  (it=2, downsampled to 500 bins). Current RT-loess test tolerance is 1 (log2) to absorb this; small
  (33-peptide) dataset skips RT-loess entirely.
- Per-transition vs per-precursor RT: skyline-prism's `mean_rt` averages per-transition RTs;
  `GetPeptideMeanRetentionTime` uses per-precursor peak RT (negligible diff for the smooth correction).

**Next steps (new machine):**
1. `pwsh -File ai/scripts/Skyline/Build-Skyline.ps1 -SourceRoot <sky_normalization> -Configuration Release`
   (or PS 5.1 `& Build-Skyline.ps1 ...`).
2. Run `TestMedianPolishSmall` and `TestMedianPolishMedium` (via `Run-Tests.ps1` if pwsh7, else
   `TestRunner.exe test=...`). Confirm the single-mean-RT fix makes Medium pass.
3. Commit `scripts/generate_peptide_rollups.py` to the skyline-prism repo.
4. Resolve the `ImputeMissingValues` default question for production callers.
5. Remaining objective task: expose RT_LOESS in group comparisons and Peptide Settings > Quantification UI.

**Next session handoff**: this Progress Log entry is self-contained (cross-machine); no `ai/.tmp`
handoff file. Run `/pw-continue` and start from "Next steps" above.

### 2026-05-20 - RT fix verified on second machine

Resumed via `/pw-continue` on the second computer (worktree `sky_peakscoringandnormalization`,
HEAD = `efce936b95`). `pwsh` 7.5.5 is installed here, so used `Run-Tests.ps1` directly.

- Built Release: `Build-Skyline.ps1 -SourceRoot sky_peakscoringandnormalization -Configuration Release`.
- Ran `TestMedianPolishSmall,TestMedianPolishMedium` via
  `Run-Tests.ps1 -TestName ... -SourceRoot ... -Configuration Release` (note: `Run-Tests.ps1`
  defaults to Debug; must pass `-Configuration Release` to find the Release `TestRunner.exe`).
- **Both PASSED.** `TestMedianPolishMedium` max diffs: median-polished 2.49e-14, summed 7.9e-4,
  median-normalized 0.011, **RT-loess normalized 0.088** (tol 1). The single-mean-RT fix
  (`GetPeptideMeanRetentionTime`) resolves the prior `Assert.IsNotNull` failure on
  `VVERHQSAC(unimod:4)K` replicate 1. Handoff next-step #2 is complete.
- skyline-prism `generate_peptide_rollups.py` already committed+pushed here
  (`9e2939f` on branch `20260520_GenerateExpectedFiles`) -> handoff next-step #3 also complete.

**Remaining**: (a) resolve `ImputeMissingValues` default for production median-polish callers
(`ProteinQuantifier`, `Peptide` databinding); (b) expose RT_LOESS in group comparisons +
Peptide Settings > Quantification UI.

### 2026-05-20 - Protein-level rollup parity (issue #4097)

Extended `MedianPolishScenariosTest` to verify Skyline's peptide -> protein median polish matches
skyline-prism, on top of the existing peptide checks.

- **skyline-prism** (`scripts/generate_peptide_rollups.py`, branch `20260520_GenerateExpectedFiles`):
  added a peptide -> protein median-polish rollup. Peptides are grouped into proteins by the
  `Protein` column of `PRISM.parquet` (skyline-prism's "Skyline CSV-based parsimony"), so grouping
  matches the Skyline document exactly - no FASTA, no document edits. Shared peptides (142 in the
  medium set) are included under each protein they map to, matching Skyline's per-protein peptide
  nodes. Reuses `rollup_protein_matrix(method="median_polish", min_peptides=2)`. Writes two new
  expected files per dataset: `protein_medianpolish_median_normalized.parquet` and
  `protein_medianpolish_rtloess_normalized.parquet` (LOG2). Regenerated for Small + Medium `.data`
  folders (peptide files were rewritten identically -> reverted to avoid binary churn).
- **min_peptides decision**: chose 2 (the skyline-prism config-template default). At 2, skyline-prism's
  rollup reduces to "1 peptide -> use directly; >=2 -> median polish", which Skyline's
  `MedianPolisher` already does (keys.Count==1 returns the peptide directly). So **no `ProteinQuantifier`
  change was needed** - it already matches. (min_peptides=3 would have sent 2-peptide proteins to a
  linear sum; not what the lab ships.)
- **Test** (`MedianPolishScenariosTest.cs`): added `ReadExpectedProteinAreas` (keyed by protein name =
  `PeptideGroupDocNode.Name`) and `VerifyProteinAreas`, which builds a `ProteinQuantifier` per protein
  from its `PeptideQuantifier`s (peptide+protein summarization MEDIANPOLISH, normalization
  EQUALIZE_MEDIANS / RT_LOESS, `ImputeMissingValues=true`) and compares `log2(abundance)` to expected.
  RT-loess gated by the same `MIN_PEPTIDES_FOR_RT_LOESS` (100) as the peptide check.
- **Scope**: only the **median-polished-peptide** inputs (combos 1 & 2). Transition-summed + peptide-level
  normalization is NOT verifiable without a Skyline change: `GetPeptideLog2Abundances(AVERAGING)` passes
  the normalization down to the transition level and never calls `ApplyPeptideLevelAdjustment`, and that
  adjustment derives factors from the polished matrix (skyline-prism normalizes each method's own
  matrix). Deferred.
- **Result**: built Release, ran `TestMedianPolishSmall` + `TestMedianPolishMedium` -> both PASS. Protein
  max diffs: Small median-normalized = 0 (1 protein, exact); Medium median-normalized = 0.024 (tol 0.1),
  RT-loess = 0.064 (tol 1).

### 2026-05-20 - RT LOESS graph: Legend + Peptides "Show" menu items

Added two independent toggles to the RT Loess Curves graph's "Show" context submenu (alongside the
mutually-exclusive Median / Normalization Factor / Normalized Median items):
- **Legend**: shows/hides the graph legend (`Settings.Default.RtLoessShowLegend`, default true).
  Replaced the old logic that auto-hid the legend in Normalized Median mode - it's now user-controlled.
- **Peptides**: shows/hides the individual per-precursor (RT, log2 area) points for the currently
  selected replicate (`RtLoessShowPeptides`, default false). One dot per precursor. Each dot's Y is
  shifted by the same transform that maps a replicate's raw curve to the displayed curve, so dots always
  scatter around the visible curve: Median -> raw log2 area; Normalization Factor -> `P - G(rt)` (raw
  minus global median, centers on the factor); Normalized Median -> `P - adjustment` (normalized).
  Clicking a dot selects that peptide in the Targets tree (`StateProvider.SelectPath`).

Files: `Settings.settings`/`.Designer.cs`, `AreaGraphController` (two bool props),
`PeakAreasContextMenu` (.Designer/.cs/.resx - two checkable items + separator + handlers),
`SkylineGraphs.cs` (`SetRtLoessShowLegend`/`SetRtLoessShowPeptides`), `AreaRtLoessGraphPane`
(`AddPeptidePoints`/`TransformPeptidePoint`, `_peptidesCurve`, `TryFindPeptideAt`, legend logic),
`GraphsResources` ("Peptides" label). New test `RtLoessGraphTest` (toggles + click-to-select);
built Release, `TestRtLoessGraph` + `TestMedianPolishSmall` PASS.

### 2026-05-20 - Round 1 verified against skyline-prism

Protein median polish rollup verified against skyline-prism for median and RT LOESS normalization
(`MedianPolishScenariosTest.VerifyProteinAreas`, expected parquet files for the Small and Medium datasets).
Median polish implementation changed to the converged R / skyline-prism stopping rule and the
(keys x replicates) orientation to match `tukey_median_polish`. Branch handed off 2026-05-21.

### 2026-09-01 - Survey of skyline-prism changes since round 1

Merged master into the branch (post accidental-merge revert). Surveyed `C:\git\skyline-prism` for work
since v26.3.5 and added the Round 2 task list above. PRISM is now C# only; the Python engine was removed
on 2026-08-28.
