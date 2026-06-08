# TODO-20260607_ospreysharp_modular_scoring.md

## Branch Information
- **Branch**: `Skyline/work/20260607_ospreysharp_modular_scoring`
- **Base**: `master` (`6774740f99`, post-#4276 calibrator extraction)
- **Created**: 2026-06-07
- **Status**: Completed — [#4277](https://github.com/ProteoWizard/pwiz/pull/4277) (merged 2026-06-08 as 08e0710fcf)
- **Delivery**: ONE branch, ONE final PR; one byte-parity-gated **commit** per
  feature family (peak-shape → coelution → median-polish → rt-dev → apex-match →
  xcorr+sg → ms1). Per-family *gate* is unchanged (build+tests+inspection +
  Stellar/Astral 1e-9 each commit); only the per-family PR overhead is dropped.
  (Revised 2026-06-07 from stacked-PRs — the gate, not the PR boundary, is what
  protects parity; one coherent refactor reviews better as one PR. May peel the
  high-risk xcorr+sg commit into its own PR if it warrants isolated review.)
- **Parent (backlog)**: `TODO-ospreysharp_modular_scoring_context.md` (stays as the
  broader design doc); strategic alignment from
  `brendanx67/TODO-ospreysharp_skyline_shared_scoring.md`
- **Plan**: `C:\Users\brendanx\.claude\plans\let-s-begin-planning-the-wobbly-dragon.md`

**Priority**: Medium-High — highest-leverage structural change in the scoring path,
highest parity risk.
**Type**: Architecture / scoring decomposition. **Execution**: ultracode (parallel
authoring + adversarial parity verification; serial gated integration).

## Goal

Replace the ~870-line inline 21-feature block in
`AbstractScoringTask.ScoreCandidate` with **one class per score**, driven by an
`OspreyScoringContext`, mirroring Skyline's `IPeakFeatureCalculator` /
`PeakScoringContext` / `ISummaryPeakData`/`IDetailedPeakData` shapes — so the two
scoring systems are close enough to imagine sharing scores later.

**Decisions (locked):** mirror inside Osprey only (new SPI in `OspreySharp.Scoring`;
no `Shared` assembly, no Skyline edits this sprint); **all 21 features** incl. the
spectrum-wall set; flattened Skyline-shaped peak data **plus** an apex/MS1 spectral
accessor on `IOspreyDetailedPeakData` (the "ApexSpectrum that Skyline would throw
on"); stacked PRs per family, low→high risk; transferability matrix skipped.

## Architecture (in `OspreySharp.Scoring`)

- `IOspreyFeatureCalculator.Calculate(OspreyScoringContext, IOspreyPeakData)` +
  `Name`; abstract `Summary`/`Detailed` bases mirroring Skyline.
- `IOspreyPeakData` (summary: Candidate, PeakBounds, ExpectedRt, ApexRetentionTime)
  → `IOspreyDetailedPeakData` (Xics + cropped-peak helpers + spectral accessor:
  ApexSpectrum, window spectra apex±2, Ms1Spectra/nearest-MS1, ApexGlobalIndex).
- `OspreyScoringContext` (Config, Resolution, Scorer, XcorrScratchPool,
  preprocessedXcorr, RT/mass calibration, tolerances) + `AddInfo<T>`/`TryGetInfo<T>`
  byproduct cache. **Reused per file/window, byproduct dict Clear()'d between
  candidates** (hot-loop allocation discipline; mirrors XcorrScratchPool).
- `OspreyFeatureCalculators` registry — the ordered array owns the parity-critical
  PIN order as data.
- Per-family shared intermediates published via `AddInfo<T>`: `PeakShapeStats`,
  `CoelutionStats`, `MedianPolishResult`.
- Non-feature byproducts (`libCosine` at apex, `top6Matches`) stay inline — not
  calculators.

## Feature families → PRs (low → high risk)

| PR | Family (PIN idx) | Source | Risk |
|---|---|---|---|
| 0 | Scaffolding (SPI, context, registry, interfaces) | — | none |
| 1 | Peak-shape (3,4,5) | `ComputePeakShapeFeatures` | low |
| 2 | Coelution (0,1,2) | `ComputeCoelutionStats` | low |
| 3 | Median-polish (15,16,19,20) | inline Tukey + `TukeyMedianPolish.*` | low-med |
| 4 | RT-deviation (11,12) | inline | low |
| 5 | Apex-match (7,8,9,10) | `CountConsecutiveIons`, `ComputeApexMatchFeatures` | med |
| 6 | Xcorr+SG (6,17,18) | `resolution.ScoreXcorr`, SG loop, `ComputeCosineAtScan` | **high** (perf gate) |
| 7 | MS1 (13,14) | `ComputeMs1Features` | high |

## Constraints / gates (per PR)

- **Byte-for-byte parity.** Each extraction is a pure value-preserving move; if a
  feature value moves, the math changed — **bisect and fix; do NOT widen tolerance**
  (needs explicit sign-off + end-of-pipeline review).
- **GATE VALIDITY (learned 2026-06-07): `Compare-EndToEnd-Crossimpl` runs the
  Release net8.0 exe via `Get-OspreySharpExe` and does NOT build** — it errors only
  if the exe is missing. So the per-family gate order MUST be: (a)
  `Build-OspreySharp -Configuration Debug -RunTests -RunInspection` (logic/tests),
  THEN (b) `Build-OspreySharp -Configuration Release` (so Compare runs THIS family's
  code), THEN (c) `Compare-EndToEnd-Crossimpl` Stellar + Astral. Skipping (b) makes
  Compare run a stale exe; because each extraction is byte-identical by construction,
  a stale exe PASSES regardless, so the gate would NOT catch an extraction bug. Do
  not commit a family until parity passes against a FRESH Release build. (Do not
  rebuild Release while a Compare run is in flight — Windows locks the running exe.)
- Gates: (1) per-feature golden diff — `--write-pin` `{file}.cs_features.tsv`
  byte-identical (merge-base vs branch); (2) `Compare-EndToEnd-Crossimpl.ps1 -Files
  All -SkipRust` on Stellar + Astral, net8.0, Stage7 + blib at 1e-9; (3)
  `Build-OspreySharp.ps1 -Configuration Debug -RunTests -RunInspection`; (4)
  per-calculator unit tests vs pre-extraction values.
- **Performance (no stage-4 regression)** — baseline = recently-updated
  `Osprey-workflow.html` on this machine (do NOT re-record). Watch stage-4 "Coelution
  scoring" / stage1to4 vs baseline; if apparent regression (most likely PR-6),
  confirm via A/B (`Bench-Scoring.ps1 -BaselineBin <merge-base exe> -BaselineType
  CSharp -Iterations 3`) at the same machine state before concluding.
- **EARLY infrastructure perf screen (after family 1 / peak-shape).** The
  per-candidate model overhead (reused context, `ClearByproducts`/`Set`, registry
  dispatch, `AddInfo`/`TryGetInfo` Type-keyed dict ops) is in the hot loop for ALL
  candidates regardless of feature, so measure it in isolation now -- a serious
  regression here would otherwise compound and be hard to attribute at PR-6. Run a
  clean (idle-machine) Astral branch run, compare stage1to4 / coelution-scoring to
  the HTML baseline; escalate to the rigorous master-vs-branch A/B only on a signal.
  Going forward, capture the perf datapoint from the family's parity Astral run by
  running it WITHOUT a concurrent build (one run yields both parity + timing).
- **Perf A/B recipe (worked out 2026-06-07; archived Bench-Scoring.ps1 is STALE).**
  The archived `Bench-Scoring.ps1` dot-sources Dataset-Config.ps1 from its own dir
  (wrong: it's one level up) AND uses the retired `--no-join` flag (PR #4273 replaced
  mode flags with `--task`). Working approach: baseline worktree
  `git worktree add --detach C:/proj/pwiz-perfbase HEAD~1`; build both Release via
  `Build-OspreySharp.ps1 -SourceRoot <tree> -Configuration Release`; A/B each exe on
  ONE Astral file with `--task PerFileScoring` (stages 1-4, emits
  `[INFO] [TIMING] Coelution scoring: Xs (N candidates)` = the per-candidate stage);
  interleave master/branch + warmup; median the stage-4 timing. Self-contained driver:
  `ai/.tmp/Run-PerfAB-Manual.ps1`. (`--write-pin` is the golden-feature-dump flag for
  gate #1.)
- Skyline conventions: no async/await, resource strings, `_camelCase`, CRLF, helpers
  after public methods, AI-attribution headers.

## Progress log
- 2026-06-08 (post-merge cleanup): **Non-PIN score port retired.** Mike confirmed (chat)
  the 21 are the empirically-chosen set out of 100+ scores tried over months (overfitting,
  the dual HRAM/unit-resolution requirement, LDA behavior, hyperscore = noise); leaving the
  others out is intentional. Deleted the backlog `TODO-ospreysharp_nonpin_scores_port.md`
  and folded its catalog + Mike's rationale into "Non-PIN scores — intentionally excluded"
  below. Also deleted the duplicate parent backlog `TODO-ospreysharp_modular_scoring_context.md`
  (superseded by this PR; a fresh /pw-oop-review will regenerate any residual
  FirstJoinTask/transferability scope). The `brendanx67/` shared-scoring strategy doc is kept.
- 2026-06-08: **MERGED.** PR #4277 squash-merged to master as `08e0710fcf`. Shipped
  the full 21-feature decomposition onto the Skyline-shaped SPI across 7 family
  commits, each Stellar (unit-res) + Astral (HRAM) 1e-9 vs Rust; perf −1.6% (no
  regression). Copilot round (5 comments) + fresh-context self-review (clean, no
  CRITICAL/HIGH) both addressed; both review rounds re-passed parity. **Deferred**:
  the Percolator weight/contribution table (`TODO-ospreysharp_feature_weight_contributions.md`).
  (The ~26 non-PIN scores were later left out by design — see "Non-PIN scores —
  intentionally excluded" below.)
- 2026-06-08 (night session): **Apex-match + xcorr+SG committed; 6 of 7 families done.**
  - **apex-match (7/8/9/10)** `41e37977b8`: `ApexMatchCalculators` — `ConsecutiveIonsCalc`
    (separate `HasMatch` pass) + `ApexFragmentMatchSet` byproduct serving
    explained_intensity / mass_accuracy_deviation_mean / abs_mass_accuracy_deviation_mean.
    Added the `ApexSpectrum` accessor to `IOspreyDetailedPeakData` (first spectral family).
    Stellar+Astral 1e-9 vs fresh Release; +`TestApexMatchCalculators` (incl. the feature-10
    no-match fallback = live `FragmentTolerance.Tolerance`, not 0.0).
  - **xcorr+SG (6/17/18)** `0664a0260e`: `XcorrCalculators` — `XcorrCalc` (single apex call)
    + shared `SgWeightedSweep` byproduct (apex±2 sweep once, serving sg_weighted_xcorr /
    sg_weighted_cosine); relocated `ComputeCosineAtScan` + `SG_WEIGHTS`. Added per-window
    machinery to the context via `SetWindow` (Resolution/PreprocessedXcorr/Scorer/
    XcorrScratchPool) and the apex index surface to the peak-data (ApexGlobalIndex /
    ApexLocalIndex / WindowStartIndex / WindowLength / WindowSpectra) — global-vs-local
    INDEX TRAP preserved; removed the dead `preprocessedXcorr` param from ScoreCandidate.
    XcorrScratchPool still threaded to ScoreXcorr (`[POOL] scratch_allocs=0`). Stellar+Astral
    1e-9 vs fresh Release; +`TestXcorrSgCalculators` (index-echo resolution fake pins the SG
    weights + asymmetric edge skip). Perf A/B (model overhead vs merge-base) in progress.
  - Both spectral families' extraction specs + draft calculators came from parallel ultracode
    planning sub-agents (dossier-driven); persisted under `ai/.tmp/xcorr-sg/` and `ai/.tmp/ms1/`.
  - **MS1 (13/14)** `552e0aa4ed`: `Ms1Calculators` — a shared `Ms1ScoringByproduct`
    (one HRAM-gated pass) serving ms1_precursor_coelution / ms1_isotope_cosine, with the
    MS1-specific ref-XIC pick (seed 0.0 / >= last-wins), skip-not-zerofill sampling,
    <1e-10 Pearson guard, apex isotope-envelope cosine. Relocated the nearest-MS1 search
    into Core (`MS1Spectrum.FindNearest`, single <=-tie-break impl; the exe `FindNearestMs1`
    is now a forwarder still used by `Calibrator`). Added `SetMs1Machinery` to the context +
    `ScanRetentionTimes` to the peak-data. Stellar+Astral 1e-9 vs fresh Release; +`TestMs1Calculators`.
  - **ALL 21 PIN features now decomposed.** 7 family commits on master `6774740f99`:
    peak-shape `55b8da50ce`, coelution `e0c72e7cdf`, median-polish `31692ee098`,
    rt-deviation `01a53e2d1d`, apex-match `41e37977b8`, xcorr+sg `0664a0260e`, ms1 `552e0aa4ed`.
  - **Perf gate PASS** (xcorr+SG family, the perf-dominant one): Astral single-file stage-4
    "Coelution scoring" (1,699,771 candidates, median of 3, interleaved vs merge-base):
    master 61.50s [66.0,61.5,58.2] vs branch 60.50s [65.3,60.5,59.3] = **-1.6% (within noise,
    no regression)**. The full calculator+context model across all families is unmeasurably
    different from the inline original.
  - **Non-PIN scores deferred to backlog (2026-06-07 decision).** A request to also port the
    ~26 EXCLUDED scores (hyperscore, dot-product/Top-N family, DIA-NN pCos, coverage, etc.)
    surfaced that **most** are Rust-computed with **no C# code** (the `CoelutionFeatureSet`
    non-PIN fields are a never-assigned mirror; a unit test asserts the 0.0 defaults) — so no
    cross-impl oracle exists for that tier. (Correction 2026-06-08: a few — `dot_product`/
    `lib_cosine`, `signal_to_noise`, `top6_matches` — ARE already computed in C# as
    byproducts/bounds and are cheap to wire; the backlog TODO splits the two tiers.)
    Per the user, NOT ported now (would be unverified math); captured in
    `ai/todos/backlog/TODO-ospreysharp_nonpin_scores_port.md` for a future parity-gated sprint
    that builds a full-feature-set Rust↔C# verification harness first. pCos must stay 0.0.
  - **PR opened: [#4277](https://github.com/ProteoWizard/pwiz/pull/4277)** (2026-06-08).
    pwiz branch pushed; ai-repo records pushed. Remaining: `/pw-self-review 4277` +
    address Copilot's auto-review (`/pw-respond 4277`); optional `/ultrareview 4277`.
    Optional cleanup: `git -C C:/proj/pwiz worktree remove C:/proj/pwiz-perfbase`.
  - Follow-up backlog: `TODO-ospreysharp_feature_weight_contributions.md` (Skyline-style
    Percolator weight + percent-contribution table). (The non-PIN-scores port backlog was
    later retired — see "Non-PIN scores — intentionally excluded" below.)
- 2026-06-07: **PR-3/PR-4 committed.** Median-polish `31692ee098`, RT-deviation
  `01a53e2d1d` (added `ApexRetentionTime`/`ExpectedRt` to the peak-data interface).
  Both Stellar+Astral 1e-9 vs fresh Release. **4 of 7 families done** (peak-shape,
  coelution, median-polish, rt-deviation). Architecture + perf hold byte-for-byte.
  Remaining = the 3 spectral families (apex-match, xcorr+sg, ms1) — these grow the
  peak-data's spectral surface (ApexSpectrum / window spectra / MS1) and the
  context's machinery (scorer / preprocessedXcorr / resolution); xcorr is the
  perf-gate family (worktree baseline ready at `C:\proj\pwiz-perfbase`).

  **Next session handoff**: For detailed startup protocol, read
  `ai/.tmp/handoff-20260607_ospreysharp_modular_scoring.md` before starting work.
- 2026-06-07: **PR-3 median-polish implemented** (trickiest family). 4 calculators
  (`MedianPolishCosine/ResidualRatio/MinFragmentR2/ResidualCorrelation`) read a
  **harness-published** `MedianPolishByproduct{polish, peakXics}` (public — the crop +
  `WriteMpInputsRow` + `Compute` must stay in `ScoreCandidate` because
  `OspreyDiagnostics` is exe-layer, unreferenceable from `OspreySharp.Scoring`).
  Per-feature no-fit defaults `0 / 1.0 / 0 / 0` (the `residualRatio=1.0` trap).
  `ClearByproducts`/`Set` moved ABOVE the median-polish block so the byproduct
  survives; `WriteMpDump` moved just after the feature vector (reads `features[]` +
  byproduct) — content + candidate-order preserved, and the standard gate compares
  Stage7+blib not the `-d` dumps anyway. **Debug gate green** (377 tests +
  `TestMedianPolishCalculatorDefaults`, inspection clean); **Stellar end-to-end 1e-9
  PASS** vs fresh Release; Astral running.
- 2026-06-07: **PR-2 coelution committed `e0c72e7cdf`.** FragmentCoelutionSum/Max +
  NCoelutingFragments (PIN 0-2) behind a shared `CoelutionStats` byproduct (one i<j
  pairwise-Pearson pass); inline `ComputeCoelutionStats` removed, Stage-6 byproduct
  reads `features[0]`. **Re-validated BOTH families against a FRESH Release build**
  (the gate-validity fix): Stellar + Astral end-to-end 1e-9 PASS (precursors
  59768=59768 / 167285=167285), 376 tests + `TestCoelutionCalculators`, inspection
  clean. Two of seven families done; architecture + perf validated.
- 2026-06-07: Branch created off master (`6774740f99`, post-#4276). Plan approved
  (full 21-feature scope, stacked PRs, ultracode execution). Sprint TODO opened.
- 2026-06-07: **Phase A (ultracode) done** — 9 agents (7 family + harness +
  synthesis), ~446K tokens, ~6 min. Produced the SPI blueprint + a per-feature
  parity-hazard catalog. Persisted: `ai/.tmp/osprey-scoring-spi-dossier.json`.
  Registry order (21 calc class names) + 6 byproduct intermediates +
  data/context member split all defined there.

### Resolved design decisions (from Phase A open questions)
- **All 21 calculators are "Detailed"** — Osprey has no Summary-only score.
  Mirror Skyline's *data* split (IOspreyPeakData → IOspreyDetailedPeakData) but
  use a **single Detailed calculator base** (no SummaryOspreyFeatureCalculator —
  would be dead). Documents a real limit of "how close to Skyline."
- **Three distinct reference-XIC selections stay separate** byproducts (peak-shape
  `>=`/seed -1.0; MS1 `>=`/seed 0.0; harness fallback `>`/seed 0.0). Do NOT unify.
- **Diagnostics are harness-owned** — the orchestrator in ScoreCandidate emits
  WriteMpInputsRow (before Compute) / WriteMpDump (after the 4 MP features);
  calculators are pure and never call OspreyDiagnostics. So the calculator-facing
  context carries no Diagnostics member.
- **Incremental interface/context growth**: each family PR adds only the
  IOspreyDetailedPeakData / OspreyScoringContext members its features read
  (minimal-honest, inspection-clean per PR). PR-1 needs only Xics + the byproduct
  cache; spectral members (ApexSpectrum, WindowSpectra, ApexGlobalIndex, StartScan,
  RangeLen, Ms1Spectra) + machinery (Scorer, PreprocessedXcorr, calibrations)
  arrive with apex-match/xcorr/ms1.
- **Concrete domain types in the interface** (LibraryEntry, XICPeakBounds, XicData,
  Spectrum, MS1Spectrum via covariant IReadOnlyList) — allocation-free + dependency-
  correct; a future shared assembly would abstract them. The SHAPE (calculator +
  context + data-split + AddInfo/TryGetInfo) is the mirror, not the member types.
- **Peak-data + context are reused mutable class instances** (one per file/window,
  fields set per candidate; byproduct dict Clear()'d per candidate) — no per-
  candidate heap alloc, no boxing. Calculators run **sequentially** within a
  candidate (shared XcorrScratchPool/VisitedBins safe).
- **Scaffolding folds into PR-1** (peak-shape) so the SPI is born used (no
  dead-code-only PR).
- 2026-06-07: **PR-1 (scaffolding + peak-shape) implemented.** New in
  `OspreySharp.Scoring`: `IOspreyFeatureCalculator` (+ `DetailedOspreyFeatureCalculator`
  base), `IOspreyPeakData`/`IOspreyDetailedPeakData`, `OspreyScoringContext`
  (`AddInfo`/`TryGetInfo`/`ClearByproducts`), `OspreyFeatureCalculators` registry,
  `PeakShapeCalculators.cs` (`PeakShapeReference` byproduct + `PeakApexCalc`/
  `PeakAreaCalc`/`PeakSharpnessCalc`). New in exe: `Tasks/OspreyPeakData.cs` (reused
  adapter). `ScoreCandidate` now routes features 3/4/5 through the registry
  (reused per-window context+peak-data created in `ScoreWindow`); inline
  `ComputePeakShapeFeatures` deleted. **Gates:** build net8.0+net472 PASS; 372
  tests PASS; inspection clean; **Stellar end-to-end 1e-9 PASS** (precursors
  59768=59768, Stage7 + blib content) + **Astral end-to-end 1e-9 PASS** (precursors
  167285=167285). Committed `55b8da50ce`.
- 2026-06-07: **Early infrastructure perf screen PASS (no regression).** Astral
  single-file `--task PerFileScoring` A/B (merge-base worktree vs branch, median of 3),
  stage-4 "Coelution scoring" with 1,699,771 candidates both: master 59.20s
  [59.1,59.6,59.2] vs branch 59.50s [58.7,59.9,59.5] = **+0.5%, within noise** (ranges
  overlap; branch fastest < master median). The per-candidate model overhead is
  unmeasurable; architecture validated. Baseline worktree kept at
  `C:\proj\pwiz-perfbase` for the PR-6 xcorr perf check.

## Out of scope (future)
- Shared multi-targeted SPI assembly under `pwiz_tools\Shared` (tier 2). The strategic
  exploration for this lives in `ai/todos/backlog/brendanx67/TODO-ospreysharp_skyline_shared_scoring.md`.
- Skyline-side `ApexSpectrum`-throws stub + Skyline referencing the contract.
- Transferability matrix; `FirstJoinTask` de-inheritance.

## Non-PIN scores — intentionally excluded (design context + reference catalog)

The Rust engine computes a ~47-field `CoelutionFeatureSet` but selects only the 21 for
the PIN. A follow-up to also port the ~26 non-PIN scores was filed as a backlog item
(`TODO-ospreysharp_nonpin_scores_port.md`) and then **retired** — per Mike (and Brendan,
2026-06-08), the 21 are the empirically-chosen set and leaving the rest out is
intentional, not an oversight. The still-useful catalog is folded here.

### Mike's design rationale (the durable "why", from chat 2026-06-08)
- He tried **100+ different scores in total**, over **months** of work.
- Many **made the analysis worse**, or **overfit** — a score that cleanly separates
  targets from decoys is overfitting, not signal.
- He made **distribution plots for all** of them, and looked in Skyline at the
  **peptides gained vs. lost** as he added/removed each.
- **Every score had to work for BOTH accurate-mass (HRAM) and unit resolution** — good
  on one but not the other was dropped. (Exactly why the parity gate runs both
  Stellar=unit-res and Astral=HRAM.)
- The **LDA step (Skyline's mProphet) struggles more with poorly-behaving scores than
  Percolator** (Osprey's SVM) does — a score must be well-behaved for the Skyline side
  too, not just survive Percolator.
- **Hyperscore specifically added a lot more noise** — a concrete rejected example.
- He iteratively **added/subtracted** scores from the model, and also experimented with
  using different scores to **pick the "best" peak** before computing the full set.
- He has a **full list elsewhere** of every score tried and the ones removed, and is
  **comfortable with the current 21**.

Takeaway: the 26 exclusions are a tuned result, not a backlog gap. Any future port
should be motivated by a specific new need, not completeness — and clears a high
empirical bar (re-check gained-vs-lost on both resolutions, watch LDA behavior, avoid
overfitting) on top of the engineering bar below.

### Reference catalog (if ever revisited)
Computed in Rust, excluded from the PIN. On the C# side they are NOT computed (the
`CoelutionFeatureSet` non-PIN fields are a never-assigned mirror; a unit test asserts
the 0.0 defaults), so there is **no cross-impl oracle** for them today — a port would
first need a full-feature-set Rust↔C# 1e-9 verification harness. Two tiers:
- **C#-AVAILABLE (math already in the tree, cheap to wire):** `dot_product`
  (= `lib_cosine`; `SpectralScorer.LibCosine`, run vestigially at the apex),
  `signal_to_noise` (on `XICPeakBounds`, computed for bounds), `top6_matches`
  (`CountTop6Matches`, a dedup byproduct).
- **NO C# CODE (from-scratch verified port):** hyperscore, dot_product_smz, the
  dot_product[_smz]_top4/5/6 family, fragment_coverage, sequence_coverage,
  base_peak_rank, mass_accuracy_std, peak_symmetry, peak_width, n_scans, coelution_min,
  n_fragment_pairs, fragment_corr_0..5, elution_weighted_cosine (**pCos** — Rust deleted
  its computation, hard-coded 0.0 "removed: expensive per-scan ppm matching"; must stay
  0.0), modification_count, peptide_length, missed_cleavages, median_polish_rsquared.
- Rust computes these in `crates/osprey/src/pipeline.rs` (~7498-7544 feature assembly)
  and `crates/osprey-scoring/src/lib.rs`; the exclusion list is at
  `crates/osprey-fdr/src/mokapot.rs:957-964` + osprey `CLAUDE.md` ("removed during
  feature weight optimization").
