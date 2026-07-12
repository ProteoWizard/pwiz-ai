# TODO-20260711_osprey_calibrator_selection_review.md -- Review the Stage-3 RT/mass calibrator-selection scheme for robustness improvements

## Branch Information
- **Branch**: `Skyline/work/20260711_osprey_calibrator_selection_review`
- **Base**: `master`
- **Created**: 2026-07-11
- **Status**: In Progress
- **GitHub Issue**: (none)
- **PR**: (pending)

## Status
**Active (moved to active 2026-07-11).** Raised by Brendan: he wants to understand how Osprey's
Stage-3 calibration CHOOSES its calibrator peptides, because the mechanism is the lever for
making calibration **less likely to degrade in cases where tens of thousands of peptides are
detectable** (rich data should never produce a weak calibration). This is a **review +
improvement-hypothesis** TODO -- first document the mechanism precisely, then propose and A/B
concrete robustness changes. Not a bug fix. Adjacent to (but distinct from)
[[TODO-osprey_fdr_entrapment_collapse_investigation]] (that one is about high-scoring
false members downstream; calibration itself is confirmed to SUCCEED on the degenerate file).
Load `/osprey-development` before working it.

Mike's recent work already addressed calibration *degradation under scarcity* (issue #4401,
restored in #4402: retry ladder + graduated-RT fallback). This TODO looks at the other end --
the selection quality and its heuristics -- and whether the picker is leaving robustness on
the table when data is abundant.

**Update 2026-07-11 -- the seed weakness is NOT calibration-only; it also lives in Pass-1
Percolator.** While root-causing [[TODO-osprey_fdr_entrapment_collapse_investigation]] we confirmed
Pass-1 Percolator uses the same **single-best-feature seed at a tight 1% first cutoff**
(`Osprey.FDR/PercolatorFdr.cs:407-434` `FindBestInitialFeature`, relaxes to 5% only if zero pass),
vs Skyline mProphet's fixed-composite seed + loose 15% cutoff + progressive tightening. Coupled with
**raw (un-logged) intensity features** run through a plain mean/std standardizer, the free
per-iteration SVM re-derivation trains raw `peak_apex`/`peak_area` up to a dominant, heavy-tailed
weight, and intensity outliers (a lone DIA interference: huge intensity, no coelution) hijack the top
of the ranking -- flooring the achievable q and producing the entrapment-run FDP spike. So the two
seed levers proposed below (fixed composite seed; keep intensity low by construction) should be
evaluated for **Pass-1 Percolator as well as Stage-3 calibration**, and paired with a feature-
conditioning fix (log/robust-scale the intensity features). Details + evidence in that TODO's
"ROOT CAUSE FOUND" section.

## The mechanism as it stands (reviewed 2026-07-11, cited) -- answers to the open questions
Entry: `Calibrator.RunCalibration` (`Osprey.Tasks/Calibrator.cs:180`, port of Rust
`run_calibration_discovery_windowed`). The log lines "N RT calibration points (from M
peptides at 1% FDR)" are `Calibrator.cs:1063-1065`; summary in `PerFileScoringTask.cs:1814`.

1. **What scores the candidates (the calibrator scorer).** A dedicated *lightweight*
   calibration scorer, NOT the Stage-4 search scorer. Candidates come from co-elution/XICs
   via a unit-resolution XCorr (`s_calXcorrScorer`, `:90`); each gets **4 features** at the
   apex (`CalibrationScorer.ExtractFeatureMatrix:581-597`): mean pairwise corr (/6), LibCosine
   apex, top-6-matched (/6), XCorr (/3) -- the /6,/3 are **hardcoded normalizers**. These feed
   an **LDA trained on THIS file** (`TrainLdaWithNonNegativeCv:227`): Percolator-style iterative
   CV, 3-fold stratified by peptide, average fold weights, **clip negative weights to 0 +
   renormalize**, `MAX_ITERATIONS=3`, early-stop after 2 non-improvements; baseline = single
   best feature.

2. **How calibrators are selected -- a REAL target-decoy q (answers "does it compute q?": YES).**
   Not top-N, not a fixed cutoff. On the final LDA discriminant, `CompeteCalibrationPairs:150`
   runs paired target-decoy competition per `base_id = entry_id & 0x7FFFFFFF` (ties -> decoy,
   conservative), then `QValueCalculator.ComputeQValues:49` computes q = cumulative decoys/targets
   with reverse-pass monotonization; the calibrator set is those with **q <= CAL_FDR_THRESHOLD
   (0.01)** (`Calibrator.cs:56`). So "1% FDR" is a genuine target-decoy q on the *calibration
   LDA score*, computed independently of the main search. (Relaxes to 5% if nothing passes at 1%.)

3. **Two-pass = inner refinement (orthogonal to the outer retry ladder).** Pass 1 scores in the
   wide initial RT window; its LOESS MAD narrows the tolerance to `3*MAD*1.4826`; pass 2
   (`RunRefinementPass:840`) re-scores the same sample inside the tighter, better-centered window
   using pass-1 LOESS to predict RT, so more true peptides clear the prefilter + LDA threshold
   (402 -> 503). Pass 2 accepted only if `R^2 >= pass1.R^2 * 0.99`; skipped if pass 1 was linear.

4. **M peptides -> N points.** Best-per-`entry_id` dedup + one competition winner per base_id,
   then `CollectCalibrationPoints:1274` drops decoys, drops q>1%, applies **S/N >= 5.0**
   (`MIN_SNR_FOR_RT_CAL`). Notable: the LOESS fit runs with **`OutlierRetention = 1.0`
   (`:1126`) -- fit-time outlier trimming is DISABLED** -- relying entirely on upstream LDA+S/N,
   softened only by `RobustnessIterations = 2` (Theil-Sen in the linear tier).

5. **Degradation/floors (#4402).** Outer retry ladder samples 100K targets, grows x2, final
   attempt = ALL targets. Floors: `MinCalibrationPoints=200`, `ABSOLUTE_MIN=50`,
   `MIN_LINEAR_FIT_POINTS=15`. Graduated fallback: >=200 -> LOESS bw 0.3; 100-200 -> widened bw;
   <100 -> Theil-Sen line; <15 confident -> Fallback (null -> `FallbackRtTolerance=2.0`). Guards:
   `HasSufficientRtSpan` (>=50% of library RT range), `IsPlausibleLinearFit` (slope within 2x).

6. **Decoy reuse + entrapment contamination.** Decoys are the LDA negatives + the FDR denominator
   (`SampleLibraryForCalibration:1392`). Entrapment peptides are **targets**, invisible to the
   target-decoy q -- so a high-scoring co-eluting entrapment can pass the 1% gate and enter the
   calibrator set as a library-RT-vs-measured-RT outlier. Defenses: S/N>=5, RobustnessIterations=2,
   Theil-Sen breakdown -- but `OutlierRetention=1.0` disables LOESS's own trimming. Under scarcity,
   `SelectPositiveTrainingSet:513` relaxes the *training* positive threshold through {5,10,25,50}%
   to reach `MIN_POSITIVE_EXAMPLES=50`, admitting lower-confidence targets into LDA training.

## Measured evidence + the Skyline seed recipe (2026-07-11)
Gathered while framing this TODO -- the concrete numbers the next session should start from.

**(1) Calibrator 1% FDR count vs final per-file count -- a ~40-60x gap.** The calibrator picker
finds a few hundred where the full search finds tens of thousands, same file (r=1.0 recheck log):
006 = **624 cal / 0 final** (calibrates normally, collapses downstream -- NOT a calibration
problem), 007 = 684 / 33,615, 008 = 328 / 23,613, others ~330-650 / 21k-31k. Some gap is expected
(the calibrator is a lightweight unit-res bootstrap before the HRAM search, and RT calibration only
needs a few hundred well-spread anchors), but 40-60x is a lot of left-on-the-table signal on a
weak seed. This gap is the primary symptom to move.

**(2) Feature contributions.** The FINAL model is single-feature-dominated: Pass-1 = Median-polish
cosine **40%**, SG-weighted cosine 22%, fragment co-elution 13%, xcorr 8% (from the model table in
`runs\seaad-20files-entrapment-r0.5-percolator\seaad.model-diagnostics.html`); Pass-2 retrain =
Median-polish cosine 46%, co-elution 27%. So one spectral-similarity feature does ~40-46% of the
work -- a single strong feature is not crazy per se. BUT the calibration seed picks *the single
best of 4 CRUDER features* (LibCosine-apex, XCorr, top-6-matched, pairwise-corr on unit-res),
"best on THIS file" = the per-run-varying quantity we distrust, and a coarser cosine than the
final Median-polish cosine. The calibration LDA's OWN per-feature weights are **not exposed in any
output** -- see the observability deliverable below.

**(3) Skyline's mProphet seed = a FIXED COMPOSITE + loose bootstrap + per-run re-derivation.**
The proven recipe (`Skyline/Model/Results/Scoring/LegacyScoringModel.cs:34-52`,
`MProphetScoringModel.cs:172,221-353`), attributed to the mProphet paper (Reiter 2011; Dario Amodei
is original author on the surrounding peak-scoring infra):
- Seed = hardcoded 7-feature composite `LegacyScoringModel.DEFAULT_WEIGHTS`: log-intensity **1.0**,
  unforced-count **1.0**, identified-count **20.0**, library dotp **3.0**, shape **4.0**,
  co-elution **-0.05**, RT **-0.7** (RT weight zeroed for the seed pass). NOT a single feature.
- The seed only has to rank well enough to pick a first true set at a **LOOSE 15% FDR**.
- Then LDA re-derives FRESH per-run weights, tightening the cutoff **0.15 -> 0.02 -> 0.01** over up
  to **10 iterations** (`DEFAULT_CUTOFFS`, `MAX_ITERATIONS=10`), stopping when the true-peak count
  stops growing at the tightest cutoff.

**Reconciles Brendan's two intuitions:** "the good score changes per run" -> YES, so final weights
are re-derived per run; "a single-score seed is a bad idea" -> YES, so the seed is a *fixed
composite* (robust-enough universally, not optimal for any run). Osprey's calibrator diverges from
this recipe on **THREE axes**, which compound: **single-best-feature seed** (vs fixed composite),
**tight 1% first cutoff** (vs 15%), **3 iterations** (vs 10 with a tightening schedule). A weak
per-run-variable seed judged at a strict 1% cut leaves almost nothing to train on -> what *looks*
like "LDA is insensitive" is really seed + cutoff starvation. So the improvement is not just "use a
composite seed" -- it is **adopt the whole Skyline pattern**: fixed composite seed + loose (~15%)
first cutoff + progressive tightening over more iterations, then measure against the §1 count gap.

## MEASURED (2026-07-11) -- the depleted pool is primarily FEATURE-limited, seed is ~2x secondary
Authoritative dumps on 006 (`OSPREY_DUMP_LDA_SCORES` for the real discriminant+q,
`OSPREY_DUMP_CAL_MATCH` for the 4 features; analysis in `ai/.tmp/lda_analysis.py`,
`cal_seed_experiment.py`). My competition-q reproduces the pipeline's own q exactly (479 @1% both
ways), so these numbers are trustworthy:

- **Real calibration LDA yield (006): 479 targets @ q<=1%, 178 @ q<=0.1%.** The LDA discriminant
  **barely separates**: target median 0.627 vs decoy median 0.624 (a 0.003 gap). The 150,673 sampled
  matches are ~balanced (76,321 target / 74,352 decoy).
- **The model already extracts near the feature ceiling; the seed is not the lever.** Single-feature
  competition-q yields @1%: libcosine 229, xcorr 150, correlation 0, top6 0. The pipeline's trained
  LDA already reaches **479** (~2x the best single feature) and a fixed equal-weight composite reaches
  **~500** -- i.e. the current iterative LDA is ALREADY close to the best a linear model can do on
  these 4 features. So the LDA is NOT seed-starved (it is not stuck at the single-feature 229); a
  fixed-composite seed would mainly help convergence/stability, not raise the endpoint past ~500.
  This REFUTES the "weak seed starves the LDA -> few pass" framing below as the primary cause: the
  ceiling is the features, not the seed.
- **The primary limiter is FEATURE QUALITY.** The 4 unit-resolution apex features (correlation,
  libcosine, top6, xcorr) cannot separate true from false peaks at this stage. The full HRAM search
  finds ~34K IDs on 006 (70x more) using HRAM fragment-match features (median-polish cosine etc.).
  So "are we just using low-value scores?" -> largely YES.
- **Direct answer to the user's questions.** (a) Better seed? worth ~2x (do it, cheap, via a fixed
  composite over the 4 features). (b) Other explanation? YES -- the features are weak. (c) Low-value
  scores? YES, unit-resolution apex features. (d) Could higher-value scores be computed quickly
  enough? THIS is the real lever: a stronger fragment-similarity feature over the elution profile
  (not just the apex), computable at the pre-calibration wide window before RT/mass are calibrated,
  is what would lift the 0.1% yield materially. Next experiment: add one stronger cheap feature to
  the calibration scorer and re-measure the @0.1% yield + RT-fit robustness.
- NOTE: the calibration still SUCCEEDS today (006: 503 RT points, R^2=0.9977) -- a few hundred
  well-spread anchors suffice for the LOESS fit. The aspiration ("many more at 0.1%") is about
  robustness margin (purer anchors, less leverage from the ~1% contamination), which needs the
  feature lever, not just the seed.

## Candidate robustness improvements to evaluate (hypotheses, A/B each)
Flagged as heuristic/fragile in the review -- the point is to test whether tightening them makes
calibration more robust when data is abundant (tens of thousands detectable) without hurting the
scarce case:
- [ ] **LEADING HYPOTHESIS -- the seed, not the LDA, is weak (Brendan, 2026-07-11).** Mike reads
  the low sub-1%-FDR calibrator yield as "LDA is less sensitive than SVM," but mProphet uses LDA
  and Skyline finds plenty -- so it is likely not the model. The review shows the calibration LDA
  **seeds from the single best individual feature** (`CalibrationScorer.cs:237-251`) and iterates
  only `MAX_ITERATIONS=3`. In semi-supervised training (mProphet / Percolator) the SEED determines
  the initial confident-positive set the discriminant trains on; a weak single-feature seed picks a
  small/noisy positive set -> poor boundary -> few peptides pass 1% -> *looks* like weak LDA. Dario
  Amodei's work on mProphet-in-Skyline produced a fixed **default composite score** that discriminates
  well on its own across many datasets and seeds fast convergence (usually <10 iterations). HYPOTHESIS:
  replace the single-best-feature seed with a fixed composite over the calibration features (or a small
  offline-derived weight vector), and expect (a) many more peptides at q<=1%, (b) faster convergence,
  (c) far less degradation when tens of thousands are detectable. TELL to confirm the diagnosis first:
  is the current picker hitting the 3-iteration cap / early-stopping with a still-small positive set?
  Also check whether the 4 calibration features even contain a good composite, or whether a couple more
  discriminating features are needed. Caveat: this is the Stage-3 CALIBRATION LDA (lightweight, per-file),
  NOT the Stage-4/5 Percolator SVM -- a contained change to the calibrator picker.
- [ ] **ENABLER (do this first) -- make the calibration LDA training observable.** Today it is far
  more opaque than the Percolator trainings: it emits only a few processing lines (enough to make
  observation §1, the count, and nothing more) while Percolator dumps its per-feature weights /
  contributions. You cannot tune the seed, diagnose per-run seed instability, or judge any of the
  hypotheses below without seeing what the calibration LDA actually learned. Add, mirroring the
  Percolator dumps:
  - Under **`--verbose`**: a per-iteration **per-feature %-contribution / weight dump** for the
    calibration LDA (which feature seeded, per-iteration weights, positive-set size + FDR cutoff per
    iteration, iteration count and stop reason). This alone tests the §3 diagnosis: is the seed
    per-run-variable? is it hitting the 3-iteration cap with a small positive set?
  - Possibly a **Model-diagnostics HTML** panel for the calibration LDA -- the calibration analog of
    the existing feature-model table (the 4 calibration features + their contributions + the
    target/decoy calibration-score histogram), so the calibrator model gets the same scrutiny the
    search model already gets. (Coordinate with the diagnostics Pass-1/Pass-2 switch TODO.)
- [ ] **Re-enable fit-time outlier rejection.** `OutlierRetention=1.0` disables LOESS inlier
  trimming; a high-scoring entrapment/decoy or a chimeric co-elution becomes a leverage point.
  A/B a modest retention (e.g. 0.9-0.95) or an explicit robust residual gate against the current
  LDA+S/N-only defense. Measure RT-fit MAD/SD and downstream IDs.
- [ ] **Entrapment-aware calibrator hygiene.** The q gate cannot see entrapment (they are targets).
  When an entrapment manifest exists, consider excluding manifest-entrapment from the calibrator
  set (or at least measuring how many enter it and their RT-residual leverage). This also gives a
  clean number for "how contaminated is the calibrator set" as a diagnostic.
- [ ] **Scale the calibrator target with available signal.** `MinCalibrationPoints=200` /
  100K sample is a floor tuned for scarcity; when tens of thousands of confident peptides exist,
  does using more (and RT-span-stratified) calibrators tighten the fit / stabilize the tails? A/B
  more calibrators + span-stratified selection vs the current top-of-q selection.
- [ ] **Revisit the hardcoded feature normalizers (/6, /3) and S/N=5.0** -- are they optimal across
  instruments/depths, or should they be data-driven? Low priority; measure sensitivity first.
- [ ] **Relaxed-FDR training ladder ({5,10,25,50}%).** Admitting 50%-FDR positives into LDA
  training under scarcity may teach the discriminant the wrong boundary; check whether it ever
  fires on rich data and whether it degrades the selection.

## Deliverables
1. A written **mechanism doc** (the above, expanded) -- candidate home:
   `pwiz_tools/Osprey/docs/` (sibling of the calibration workflow notes) so Mike has a reference.
2. A prioritized, A/B-tested shortlist of the improvements above, each measured on RT-fit quality
   (MAD/SD/R^2), calibrator count/composition, and downstream IDs + entrapment FDP, on the SEA-AD
   dataset across entrapment ratios. Gate real changes on `regression.ps1` (calibration is
   algorithm-affecting -> golden must be re-blessed deliberately if output changes) + the
   entrapment oracle.

## BOTTOM LINE (2026-07-11 night) -- PR PROPOSAL
The low calibration yield is **sample-limited, not feature-limited**. On file 006 the library is
3.17M targets with only ~1.06% present; the default random 100K sample holds ~1K present peptides,
so calibration selects only ~479 anchors @1% (~45% of present-in-sample). Growing the sample scales
anchors ~linearly (300K->1478, 1M->4958 @1%; 1M gives **2298 anchors @0.1%** and **5885 RT points**
vs 503). Adding the top Percolator feature (median-polish cosine) did almost nothing (redundant with
libcosine_apex). **Recommended PR: make the calibration anchor target adaptive** -- keep sampling/
growing while confident anchors keep rising materially, instead of stopping at the first attempt
past MinCalibrationPoints=200; on scarce files behavior is unchanged (protected by #4402 floors).
Ship the `--verbose` calibration report (already implemented) alongside so the effect is observable.
Drop the dead `top6_matched` feature (0% contribution). Median-polish cosine: optional, low priority.
Landed this session behind default-off env flags (byte-identical): `--verbose` report,
`OSPREY_CAL_MEDIANPOLISH`, `OSPREY_CAL_SAMPLE_SIZE` (the last demonstrates the mechanism).
VALIDATION: build clean (net472+net8.0); tests 503/506 (+3 expected skips); inspection clean on
changed files; **regression.ps1 -Dataset Stellar mode1/2/3 all PASS (byte-identical to golden)** so
the default path is provably unchanged.

DOWNSTREAM A/B DONE (`full006-s1m` 1M sample vs `seaad-006only-r1.0-baseline` 100K; regression proved
my default == golden, so the baseline is a valid 100K reference). Calibrating on **5885 RT anchors +
35,192 MS2 mass-cal matches** (vs 503 + 3,004) yields, on this already-succeeding file:
- First-pass Percolator: **34,452 vs 33,712 = +740 (+2.2%)**; decoys 343 vs 336 (FDR still 1.0%).
- Second-pass: **39,489 vs 38,041 = +1,448 (+3.8%)**; protein groups 4988 vs 4856 (+2.7%).
- RT fit R^2 unchanged (0.9976 vs 0.9977); MS2 mass SD 1.60 vs 1.53 ppm on 11.7x more matches.
=> **Real, FDR-clean ID gain (+2-4%) even where calibration already works**, driven mostly by the
much richer MS2 mass calibration (11.7x fragment matches -> more reliable tolerance). On files where
calibration is currently MARGINAL the benefit should be larger. This confirms the adaptive-anchor
fix is worth building. (FDRBench true-FDP not recomputed; decoy fractions identical + model-
diagnostics HTML present in both run dirs for a deeper morning check.)

## SESSION 2026-07-11 night (autonomous) -- observability landed + median-polish lever in flight
Branch `Skyline/work/20260711_osprey_calibrator_selection_review` (pwiz-work2). Goal this session
(from Brendan): (1) add --verbose visibility into the calibration LDA mirroring the Percolator
contribution report; (2) raise calibration peak-selection yield toward >=50% of a full Percolator
training by adding the features that dominate the Percolator model.

### 1. --verbose calibration-LDA report -- DONE + committed (7d9663295a)
`CalibrationScorer.TrainAndScoreCalibration` gained an `out CalibrationTrainingReport` overload;
the Calibrator logs it under `--verbose`. Shows: candidate pool (target/decoy), seed feature +
FDR, per-iteration refinement trace (positive pool, passing, "new best"), stop reason, 1%/0.1%
calibrator yield, and the per-feature share-of-separation table (same shape as the Percolator
`FeatureContributions`). Unit test `TestCalibrationTrainingReport`; full suite 503/506 (+3 expected
skips) green; inspection clean on changed files (the 9 SystemMemory.cs warnings are the known
pre-existing #4379 local-only issue). Non-algorithm-affecting (diagnostic only).

### 2. BASELINE observed on file 006 (r=1.0 entrapment lib, `runs/cal006-baseline`)
```
Calibration LDA pass 1: 150,673 matches (76,321 target / 74,352 decoy)
  seed libcosine_apex @1% (229) -> iters 229->417->479->467 (cap hit, best=479 @ iter2)
  yield: 479 @ q<=1%, 178 @ q<=0.1%          [matches the earlier MEASURED numbers exactly]
  contributions: libcosine_apex 64.0% | xcorr 19.7% | coelution_corr 16.2% | top6_matched 0.0%
```
KEY: `top6_matched` is DEAD (weight clipped to 0) -- effectively only 3 of 4 features work.
`libcosine_apex` (HRAM apex cosine) carries 64%.

### 3. RECONCILED the "unit resolution is absurdly wide" concern (important)
Observed, not inferred (`cal006-baseline/run.log`): calibration runs at **fragment tolerance
10 ppm** (config default, HRAM) -- NOT unit resolution. Only the *XCorr feature value* is
unit-resolution-binned (`s_calXcorrScorer`); the XIC extraction, libcosine, top6, and the MS1/MS2
mass-error collection all use the 10 ppm HRAM tolerance. And the instrument is already near-
calibrated: **MS1 correction 0.98 ppm (SD 1.77), MS2 correction 0.08 ppm (SD 1.53)** -- so 10 ppm
easily catches true fragments; widening the mass window would only admit noise. Initial RT window
is +/-4.77 min (0.2x the mzML RT range). => The limiter is NOT the mass/RT window; it is FEATURE
QUALITY: the 4 apex-only features cannot separate the 76K-target pool (only 479 clear 1%). This
confirms the TODO's MEASURED conclusion by direct observation. The lever is adding the strong
full-profile HRAM features that dominate Percolator, exactly as Brendan proposed.

### 4. median_polish_cosine lever -- implemented behind OSPREY_CAL_MEDIANPOLISH (experiment in flight)
Sub-agent mapped the Percolator features (spec in this session's notes): `median_polish_cosine`
(~40% of the search model) is the single best value x cheapness -- fully computable from the
peak-cropped calibration XICs the scorer already extracts, via the public `TukeyMedianPolish.Compute`
+ `.LibCosine` (same crop as `CoelutionScorer.ScoreCandidate`, maxIter=10 tol=0.01). Added as an
OPTIONAL 5th calibration LDA feature gated on `OSPREY_CAL_MEDIANPOLISH` (default OFF -> matrix stays
4 features -> output byte-identical AND perf-neutral: the feature is neither computed nor scored when
off). Files: `OspreyEnvironment.CalMedianPolishFeature`, `CalibrationMatch.MedianPolishCosine`,
`ScoreCalibrationCandidate` compute + `ComputeCalibrationMedianPolishCosine` helper,
`ExtractFeatureMatrix` 5th column, `s_featureNames`. Committed 063e2bbe92 (default off -> byte-identical).

RESULT (`cal006-medianpolish`, pass 1): **491 @ q<=1%, 180 @ q<=0.1%** vs baseline 479/178 -- only
**+12 / +2**, and `median_polish_cosine` earns just **5.9%** of the separation (libcosine still 56.7%).
=> median-polish cosine is **largely REDUNDANT with libcosine_apex** (both measure library-spectrum
agreement); adding it barely moves yield. **Feature richness is NOT the dominant lever here.** This
was the surprise that redirected the investigation.

### 5. ROOT CAUSE of the low yield: the calibration is SAMPLE-LIMITED, not discrimination-limited
The numbers reconcile cleanly:
- Full first-pass Percolator on file 006 finds **33,712 targets @1%** (`seaad-006only-r1.0-baseline`
  run.log) out of a **3,173,636-target** entrapment library => only **~1.06% of the library is
  actually present**.
- Calibration samples a **random 100K** targets per attempt and STOPS at attempt 1 once >= 200
  clear (`ComputeMaxAttempts`/the ladder only grows the sample on SHORTFALL). A 100K random draw
  from a 3.17M library holds only **~1,070 present peptides** (100K x 1.06%).
- Calibration finds **479 @1%** = **~45% of the present-in-sample peptides**, and 178 @0.1%.
So the calibration LDA is ALREADY recovering ~half the present peptides IN ITS SAMPLE. It looks
weak (479 of 76K matched) only because the 76K "matched" pool is ~99% not-actually-present library
entries the 4 apex features cannot reject -- but the CEILING is set by how many present peptides are
in the sample, and a 100K random sample of a 3.17M library only contains ~1K of them. **To surface
"thousands of high-quality peaks at near-zero FDR" (Brendan's goal), the dominant lever is the
SAMPLE (size/enrichment), not the feature set.** The retry ladder is tuned for a MINIMAL sufficient
calibration (stop at 200 points), the opposite of using the rich signal.

### 6. CONFIRMED: yield scales ~linearly with sample size (`OSPREY_CAL_SAMPLE_SIZE` sweep, file 006)
| sample | pass-1 @1% | pass-1 @0.1% | pass-2 @1% | pass-2 @0.1% | pass-2 RT points | total wall |
|--------|-----------:|-------------:|-----------:|-------------:|-----------------:|-----------:|
| 100K (default) | 479 | 178 | 618* | ~230* | 503 | ~90s |
| 300K | 1478 | 816 | 2193 | 1067 | 1712 | 102s |
| 1M | 4958 | 2298 | 7443 | 2259 | 5885 | 223s |

(*pass-2 100K numbers approximate from the --verbose iter trace.) Pass-1 @1% scales essentially
PERFECTLY LINEARLY: 100K->479, 300K->1478 (3.08x), 1M->4958 (**10.4x**) -- textbook sample-limited.
@0.1% is slightly super-linear (178->2298 = 12.9x at 10x sample). At 1M the LOESS is fit on **5885
anchors (pass 2) vs 503 default**, and there are **2298 anchors at q<=0.1%** -- exactly Brendan's
"thousands of high-quality peaks at near-zero FDR." Calibration cost stayed modest (1M = 223s total
incl. the ~60s library load; the scoring itself ~2-3 min). NOTE: even 4958 @1% is only ~15% of
Percolator's 33,712 on this file -- reaching the aspirational 50% via sampling alone would need
near-full-library (~3.17M) sampling (~10 min) AND may saturate below Percolator because the 4 apex
features are weaker than the full-search HRAM feature set. But the stated goal (thousands of pure
anchors) is met at 300K-1M.

### 7. The principled fix (for the PR proposal, NOT committed tonight)
The clean change is NOT "always sample everything" (a 3.17M full sample would be ~10x slower for
marginal gain past saturation). It is to **make the calibration anchor target adaptive to the
available signal**: keep the retry ladder, but instead of stopping at the first attempt that clears
MinCalibrationPoints=200, grow the sample while confident anchors keep rising materially (rich file
-> thousands of anchors; scarce file -> unchanged behavior, still protected by #4402's floors).
Equivalent framings to evaluate: (a) raise the default CalibrationSampleSize and/or the "enough"
threshold; (b) a signal-proportional target (e.g. grow until @0.1% anchors plateau or the sample is
exhausted); (c) enrich the sample toward library entries with >=1 in-window top-6 fragment match
before drawing (cuts the ~99% not-present dilution so a smaller sample yields more true anchors).
OPEN VALIDATION (needs a full-pipeline A/B, expensive, not done tonight): does calibrating on 1712
vs 503 anchors measurably improve DOWNSTREAM IDs / FDP? The calibration already succeeds
(R^2=0.9977) with 503, so the win is robustness margin (purer, more numerous anchors, less leverage
from the ~1% contamination) rather than a guaranteed ID lift -- must be measured before shipping.

### Levers ranked by impact (this session's evidence)
1. **Sample size / adaptive anchor target** -- DOMINANT (3x sample -> ~3x anchors). The real fix.
2. Feature richness (median-polish cosine) -- MINOR (+2.5% @1%), redundant with libcosine_apex.
3. Dead `top6_matched` feature (0% contribution) -- cosmetic; drop it, but no yield effect.
4. Iteration cap (3, best often at iter 2) / Skyline tightening schedule -- untested this session.

## PRIOR ART (2026-07-12, Brendan-provided) -- curated anchor lists beat random sampling
The random-sampling weakness Brendan flagged (hit rate <0.5-1% -> too few confident calibrators) is
exactly what the DIA field solved with CURATED, high-observability anchor sets. Two sources:

**Bruderer, Bernhardt, Gandhi, Reiter (2016), Proteomics 16:2246-2256, "High-precision iRT prediction
in the targeted analysis of DIA" (Biognosys/Spectronaut), DOI 10.1002/pmic.201500488** (ai/.tmp/PMIC-16-2246.pdf):
- Standard iRT = 11 Biognosys iRT spike-in peptides + LINEAR regression. Their improvement = a LARGE
  CURATED anchor set (**21,155 HeLa/human peptides**) + SEGMENTED per-bin robust regression.
- How the curated set was built (the key part): DIA triplicates of HeLa; keep only precursors
  identified in ALL 3 runs; bin into 20 equal RT bins; **per bin keep the lowest-SD 80%** (drop
  outliers / in-source frag). => a high-reproducibility, RT-SPAN-STRATIFIED endogenous human anchor DB.
- Segmented regression: bins of max(n/40,20) points, 50% overlap, **robust Theil-Sen per bin**, connect
  bin refs with lines, linear-extrapolate edges. Adaptive extraction-window width = 2x a regression on
  (median peak width + 75th-pct RT residual). Mass calibration = LOCAL (RT-dependent) mass recalibration.
- IMPACT: segmented + large curated set = **18% more identified precursors vs 11-pep linear** (p=7.6e-5).
- NOTE the parallels to Osprey: Theil-Sen, RT-binning, residual-gated outliers, adaptive window are
  ALREADY in Osprey's calibrator. The gap is ANCHOR SELECTION (random 100K vs a curated high-observability
  set), not the fit.

**OpenSWATH / Rost -- CiRT ("common internal retention time") endogenous peptides** -- THIS is the
"priority list in human samples" Brendan recalls: Parker, Rost, Rosenberger, Collins, Malmstrom,
**Amodei** (yes, the mProphet Amodei), Venkatraman, Raedschelders, Van Eyk, Aebersold, "Identification
of a Set of Conserved Eukaryotic Internal Retention Time Standards for DIA MS," MCP 2015 14(10):2800-2813,
DOI 10.1074/mcp.O114.042267 (open: PMC4597153).
- **113 CiRT peptides** (+ a hand-picked **14-peptide CiRT-SW** SWATH subset). ENDOGENOUS, no spike-in.
- Selection = curation, not random: started from the **500 most-common tryptic peptides** in
  UniProt/Swiss-Prot (conserved housekeeping), cross-referenced for detectability across human+yeast
  (84/113 human, 98/113 yeast), validated over 5 datasets (human/yeast/mouse). => near-universally
  present, so the effective calibrator hit rate is ~100%, NOT ~1%. RT predicted within ~2 min for most.
- OpenSWATH (Rost 2014, Nat Biotech, nbt.2841) uses anchors via `tr_irt`; recommends the Biognosys
  iRT-kit if spiked, else CiRT. RT transform default linear (lowess/b_spline for many/noisy anchors).
- RUNTIME OUTLIER REJECTION on anchors: `RTNormalization:outlierMethod` = iter_residual (default,
  drop largest-residual each iter) / iter_jackknife (drop the point whose removal most improves R^2) /
  **RANSAC** / none; `estimateBestPeptides` peak-shape prefilter; `NrRTBins`(10) enforces RT coverage.
  CiRT's filter "confidently removes low-scoring signals up to a **10x excess of false signals**."
- m/z correction from the SAME anchors: `mz_correction_function=quadratic_regression_delta_ppm` -> one
  curated anchor set solves RT AND m/z together (Osprey currently derives both from the random draw).
- Escher 2012 (Proteomics, pmic.201100463): the original 11 synthetic iRT peptides + the selection
  criteria (high intensity, no mod-prone residues, non-natural sequence, EVEN RT distribution).

### On the "~1000-anchor precision-iRT second pass" (Brendan's recollection) + the RIGOR point
Could NOT source a named OpenSWATH/Rost "precision-iRT pass expanding to ~1000 self-derived anchors";
the ~1000 figure is in no doc/paper found. What IS real and adjacent:
- OpenSWATH `-RTNormalization:alignmentMethod` lowess/b_spline + `estimateBestPeptides` = nonlinear
  alignment against MANY/noisy ENDOGENOUS anchors (one configurable step, not a documented 2-stage
  iRT->endogenous re-fit).
- **DIAlignR** (Gupta & Rost, MCP 2019, PMC6442363): closest "self-derived confident anchors" method,
  but aligns RUN-TO-RUN (not library/iRT->run), post-identification, anchor counts in the HUNDREDS
  (406-437), LOESS span 0.27.
- The "expand small set -> large self-derived set + segmented/nonlinear regression" is really
  Spectronaut (Bruderer 2016), n-dependent binning, no fixed ~1000.
- Likely a blend of DIAlignR (self-derived, hundreds) + Spectronaut, or a direct-from-Hannes detail
  not in public docs. Neither confirmed nor refuted.
KEY INSIGHT (directly answers Brendan's quality/rigor concern): every method that expands to a large
self-derived anchor set pairs it with a QUALITY FILTER STRONGER THAN A PER-RUN IN-SAMPLE q --
DIAlignR uses post-pyProphet high-confidence peaks; Spectronaut uses all-3-replicate + lowest-SD-per-
bin; OpenSWATH endogenous mode leans on RANSAC/iter-residual outlier rejection. Osprey's calibration
q<=0.01 is the WEAKEST of these: (1) optimistically biased/resubstitution (CV stabilizes weights but
the final discriminant+q are scored on the same points, positive set re-selected from current scores),
(2) entrapment-blind (entrapment are targets, invisible to target-decoy competition), (3) small-count
noisy (~5 decoys support the 1% cut at ~479 anchors). => "sample more" scales COUNT but inherits the
same weak q; it does NOT improve anchor QUALITY. Curated CiRT (known-present) + RANSAC (geometric, no q
needed) is what improves quality. PROPOSED MEASUREMENT (pending Brendan go-ahead): use the SEA-AD
entrapment library to measure the TRUE FDP of the anchor set (how many q<=1% calibration anchors are
entrapment/known-absent) at 100K vs 1M -- turns the q-rigor question into a number.

### Reference implementations to consult (cloned 2026-07-12) + the CARAFE library-quality direction
Brendan authorized pulling two open-source reference engines into C:\proj for direct code review:
- **DIA-NN 1.8** (`C:\proj\DiaNN`, tag 1.8, one 11,260-line `src/diann.cpp`) -- the field-leading DIA
  engine, open in this era; Vadim Demichev says core principles are stable. Mike: Vadim was compelled
  to fix over-optimistic q-value estimation AFTER FDRBench -- directly relevant to our q-rigor worry.
- **OpenSWATH** (`C:\proj\OpenMS`, OpenSWATH algs under src/openms/.../OPENSWATH). Faded in the field
  (Aebersold retired, Rost -> Toronto / small-molecule) but the RANSAC/iter-residual RT normalizer +
  m/z correction are canonical reference code.
Two sub-agents reviewed each for: RT calibration, WHICH peptides are anchors, mass correction, q rigor.

**DIA-NN 1.8 code review (src/diann.cpp; validates BOTH our suspicions):**
- ANCHOR SELECTION: NEVER random-samples. Scores the FULL (batched) library, ranks by classifier
  confidence (cscore), takes the **top-N best**: `iRTTopPrecursors=50` for RT, `iRTRefTopPrecursors=250`
  for the reference/peak-width set (diann.cpp:9597-9599, 9706-9725). RT anchors = q<=iRTMaxQvalue(**0.1**,
  looser than our 0.01) OR in the top-50 by score -> a GUARANTEED FLOOR of the 50 best even if few pass
  q, so calibration never starves. Mass cal uses a stricter q<=MassCalQvalue set.
- Bootstrapped/semi-supervised: small batches (MinBatch=2000) -> fit classifier -> q -> calibrate ->
  grow -> refit, with hard min-ID gates (MinCal=1000, MinCalRec=100; run() 10361-10578). Optional
  reference_run() calibrates on a curated .ref set first.
- RT fit = monotone cubic-Hermite SPLINE, outlier-trimmed (drop residuals > 80th pct, refit), bidirectional
  (1153-1201). Mass = RT-binned linear-in-m/z least-squares (Eigen SparseQR), MS1+MS2 separately, with a
  **REVERT-IF-WORSE self-check** (reverts if correction didn't beat no-correction; 9909-9924).
- Q RIGOR: TDC on the classifier score, but the NN is a **12-network bagged CROSS-VALIDATION** ensemble
  where each net scores only precursors it did NOT train on (830-840, 9306-9359, 9476-9480) + revert-if-
  worse + a separate GLOBAL profile-q across runs (6116-6147, 11177). BUT the agent notes the residual
  optimism is real: "TDC counting is still on the same precursors used to fit the classifier" -- exactly
  the over-optimism FDRBench exposed (Mike's point about Vadim's fix).
- NO detectability/observability PRIOR: DIA-NN carries no pre-search per-entry detection-probability score;
  it derives quality empirically by scoring the whole library and ranking by cscore. => Osprey's Carafe
  quality flag is our EFFICIENT SUBSTITUTE for DIA-NN's brute-force full-library scoring (we can't cheaply
  co-elution-score all 3.17M; a Carafe prior enriches the scored subset for present peptides).
- PORTABLE IDEAS: (i) confidence-RANK anchor selection with a guaranteed top-N floor (vs our hard q<=0.01
  that starves); (ii) looser q (0.1) + geometric outlier trim beats a strict q with few anchors; (iii)
  revert-if-worse mass-cal guard; (iv) held-out/CV scoring for a less-optimistic q.
**OpenSWATH code review (OpenMS CalibrationWorkflow/MRMRTNormalizer; confirms the GEOMETRIC thesis):**
- Anchor trust is PURELY GEOMETRIC -- **NO per-run q/target-decoy/FDR on the RT anchors anywhere**
  (grep-confirmed across CalibrationWorkflow.cpp, MRMRTNormalizer.cpp, OpenSwathHelper.cpp,
  SwathMapMassCorrection.cpp). Decoys are excluded once at sampling (library-level), not a per-run TDC.
- Anchors = a CURATED set (iRT/CiRT) -> optional peak-quality pre-screen (`estimateBestPeptides`,
  OverallQualityCutoff=5.5; OFF by default -- they trust the curated list) -> **geometric outlier
  rejection**: `iter_residual` (drop largest-residual, refit until R^2>=0.95 or coverage<0.6; DEFAULT) or
  **RANSAC** (consensus inliers within 3% of gradient, most-inliers-wins ties-by-RSS, 1000 iters) ->
  RT-bin coverage gate (NrRTBins=10, MinBinsFilled=8) -> fit linear/lowess/b_spline.
- m/z correction REUSES the exact surviving RT anchors (quadratic_regression_delta_ppm etc.), same set.
- => OpenSWATH proves a curated set + geometric filter needs NO per-run q at all.

**THE TWO ENGINES BRACKET THE DESIGN SPACE; Osprey is the outlier.**
- DIA-NN: score the FULL library, rank by (cross-validated) confidence, loose q(0.1)+floor+spline-trim.
- OpenSWATH: small CURATED anchor set + PURELY geometric RANSAC/residual rejection, no per-run q.
- Osprey (today): strict per-run resubstitution q<=0.01 on a RANDOM 100K sample. NEITHER reference does
  this -- not the random sample, not the strict per-run q for anchor trust. CONVERGENT LESSONS:
  (1) don't random-sample (DIA-NN scores all + ranks; OpenSWATH curates; our Carafe flag = the efficient
  middle path); (2) don't lean on a strict per-run q -- use geometric robustness. Osprey ALREADY has
  Theil-Sen+LOESS but **OutlierRetention=1.0 DISABLES the trim** (this TODO's item) -- re-enable it and
  add RANSAC/iter-residual, directly endorsed by BOTH engines; (3) select by confidence RANK + a floor
  (DIA-NN top-50) not a hard q that starves; (4) reuse anchors for m/z (both do; Osprey already does);
  (5) revert-if-worse mass-cal guard (DIA-NN) is a cheap robustness win.

**BRENDAN'S KEY ARCHITECTURAL IDEA (2026-07-12) -- self-generated quality anchor list from Carafe.**
Hannes's "~1000 anchors" was likely just him configuring many endogenous anchors / curating a ~1000
list for his OWN samples (any researcher would). Osprey's situation is BETTER: we detect tens of
thousands of peptides per sample AND we BUILD the spectral library ourselves from separate library
runs via Carafe. So instead of importing a fixed external CiRT list, we can **encode a per-entry
QUALITY / observability flag into the library** -- either measured during Carafe library generation
(these peptides WERE confidently detected in the library runs, with peak-quality / reproducibility
stats) or PREDICTED by Carafe. Then Stage-3 calibration seeds from that high-quality subset instead
of a random 100K/1M draw. This is a SELF-GENERATING CiRT analog, tailored to the actual sample/library,
and it fixes BOTH problems at once: (1) high calibrator hit rate (start from known-good entries, not
1%-present random) and (2) anchor QUALITY independent of the weak per-run q. Design threads to work
out: what quality signal Carafe can expose (detection reproducibility across library runs, peak-shape,
precursor intensity rank, prediction confidence); the library-format field to carry it; how Osprey
prioritizes/samples by it; whether to combine with geometric (RANSAC) outlier rejection as a backstop.
This is the leading long-term direction; the adaptive-sample fallback + entrapment-purity measurement
remain the near-term steps.

CARAFE MECHANISM CONFIRMED (Carafe-mm code review, 2026-07-12): transfer learning is PURE
RE-PREDICTION (answer A). Base = AlphaPeptDeep (peptdeep); Carafe fine-tunes 3 models (MS2 intensity,
RT/iRT, CCS) on sample-specific search results (measured intensities from psm_pdv.txt +
fragment_intensity_df.tsv used ONLY as training targets; MS2 20 epochs lr1e-4, RT 40 epochs, ~10%
seq-unique held-out test), saves fine-tuned WEIGHTS ONLY, then Phase 2 digests the output -db FASTA and
predicts EVERY peptide from the fine-tuned model -- NO "use measured if seen" branch. So a seen
peptide's library row is a fresh prediction, identical in kind to an unseen one; the measured data
influenced it only by nudging shared weights (generalization/"coloring"). IMPLICATIONS FOR THE
QUALITY-FLAG HOOK: (1) the output `carafe_spectral_library.tsv` schema carries NO provenance/observed/
confidence field -- the "was detected in the sample-specific search" info EXISTS in Phase 1 but is
DISCARDED before the library. (2) Carafe ALREADY computes a per-peptide measured-vs-predicted
correlation (`cor_n_*` in psm_pdv_with_correlation.txt) for internal NCE selection but does not write
it to the library -- that (for SEEN peptides) is a natural quality signal to propagate. (3) Nice
parallel to DIA-NN/our plan: Carafe's MS2 model is used only if all 4 similarity metrics improve on
the held-out test, else it REVERTS to the generic model (a revert-if-worse guard). => a future Carafe
quality flag = emit training-set membership + `cor_n_*` per entry (measured-quality for seen; model
prediction / uncertainty for unseen). DEFERRED per Brendan (near-term = Osprey-only refinements).

### Refined recommendation (updates the BOTTOM LINE)
Two tiers, not either/or:
1. **Fallback / immediate (validated tonight)**: when random sampling is used, sample MORE on rich files
   (adaptive anchor target). +2-4% IDs on file 006, FDR-clean. "Simply finding more beats degrading."
2. **Principled fix (prior-art-backed)**: preferentially draw calibration candidates from a CURATED
   high-observability PRIORITY LIST (CiRT-style, species/tissue-appropriate) instead of uniform random,
   so the calibrator hit rate is ~100% not ~1%. This is what Spectronaut (21,155-pep set) and OpenSWATH
   (CiRT-113/14) both do. CONCRETE OSPREY DESIGN:
   - Ship the published **CiRT-113 / CiRT-SW-14** sequences (human/eukaryotic; SEA-AD is human brain,
     so directly applicable). At calibration, MATCH them to assay-library entries by sequence and draw
     those FIRST as calibration candidates (they carry fragment info, so Osprey's co-elution scorer can
     score them unchanged). This slots into the existing pass-1 (wide) calibration: seed pass 1 with the
     CiRT anchors instead of a random 100K draw, then the existing pass-2 refinement (and/or the adaptive
     sample from tier 1) expands to a high-precision fit -- exactly Spectronaut's "start from iRT-11,
     grow to 21,155 from confident IDs" pattern.
   - Add OpenSWATH-style **anchor OUTLIER REJECTION** (RANSAC / iterative-largest-residual) on top of the
     current S/N + Theil-Sen; it survives up to 10x false-anchor excess and directly addresses the
     entrapment-contamination + OutlierRetention=1.0 gaps this TODO already flagged.
   - Derive **m/z correction from the same anchors** (as OpenSWATH does) rather than a separate draw.
   - For non-eukaryotic/custom libraries, reuse the CiRT METHODOLOGY (top-N most-common conserved tryptic
     peptides, filtered by cross-run detectability) to generate a per-library anchor list offline.
Both tiers are consistent with the measured driver: calibration/anchor quality materially moves IDs (18%
in Spectronaut's controlled test; +2-4% in our file-006 A/B even where calibration already succeeds).

## References
- Code: `Osprey.Tasks/Calibrator.cs` (RunCalibration :180, retry ladder :318-622, CollectCalibration
  Points :1274, floors/constants :53-56), `Osprey.Scoring/CalibrationScorer.cs` (ExtractFeatureMatrix
  :581, TrainLdaWithNonNegativeCv :227, CompeteCalibrationPairs :150, SelectPositiveTrainingSet :513),
  `QValueCalculator.cs:49`, `RTCalibrationConfig.cs`, `PerFileScoringTask.cs:1814` (summary log).
- #4401/#4402 (calibration degradation retry ladder + graduated-RT fallback).
- [[TODO-osprey_fdr_entrapment_collapse_investigation]] (shares the high-scoring-false-member theme).

## SESSION 2026-07-12 (autonomous) - Step A: anchor entrapment-purity MEASURED -> REFRAME

### Diagnostic added (default-off / verbose-only, byte-identical)
- `CalibrationMatch.IsEntrapment` (Osprey.Scoring) populated at anchor construction from
  `EntrapmentLibraryClassifier.IsEntrapment(entry.ProteinIds)` (FDRBench `_p_target` marker).
- `Calibrator.RunCalibration` tallies the full-library entrapment composition once (verbose-gated);
  `RunLdaAndCollectPoints` emits an anchor-purity report per pass via `--verbose`: scored-pool
  composition + a q-sweep (0.1/1/2/5/10%) of anchor counts and entrapment-FDP (lower + combined,
  ratio-corrected per docs/fractional-entrapment.md). Never used by scoring -> output unchanged.
- Library confirmed r=0.986 (near 1:1 shuffled-anagram entrapment): fasta has 5,563,916 headers,
  exactly half `decoy_` and half `_p_target` => equal Target/PTarget/Decoy/PDecoy quartet. At the
  precursor level: 3,173,636 target-side = 1,597,693 real + 1,575,943 entrapment.

### THE FINDING (reframes the whole review)
The calibration anchors are **essentially PURE**, and the q<=0.01 gate is **well-calibrated, even
slightly conservative** - NOT anti-conservative. File 006, 100K sample:
| pass | q<=1% anchors | entrapment | combined FDP | q<=0.1% anchors | entrapment |
|---|---|---|---|---|---|
| 1 | 479 | 3 | 1.26% | 178 | 0 (0.00%) |
| 2 | 618 | 2 | 0.65% | 193 | 0 (0.00%) |
The worry ("not confident of anchor quality / q rigor at 0.01") is **empirically unfounded** on this
file at 100K: combined entrapment-FDP is at/below the claimed 1%, and at q<=0.1% it is exactly 0%.
=> Calibration anchor SELECTION is clean and decoupled from the SEARCH-level entrapment-FDR collapse
documented elsewhere ([[project_osprey_intensity_hijacks_percolator]]) - different stage, different
cause. The calibration limitation is **purely sample-limited YIELD, not purity or q-rigor.**

### Consequence for the plan (priorities updated)
- **Step B (geometric outlier rejection) drops in priority**: on a file whose anchors are already pure
  there is almost nothing to reject. Keep it only as a safety net for larger samples / looser gates
  (pending the 1M purity check + q-sweep curve).
- **The yield levers are primary**: (D) more / adaptive sample (validated: 1M->4958 anchors, +2-4% IDs),
  and (enrichment) a CiRT-style / observability-weighted PRIORITY DRAW so the calibrator hit rate rises
  above ~1% (the real ceiling: only ~1070 of a 100K uniform draw are present).
- **Step C (loosen the q gate) is a cheap multiplier** now that the entrapment-FDP q-sweep is the
  built-in safety check: if q<=2-5% keeps FDP acceptable it buys more anchors with zero extra sampling.
- The entrapment-FDP report is now the standing ACCEPTANCE ORACLE for every subsequent anchor-selection
  change (does it add anchors without raising true FDP?).

### MEASURED - anchor yield + purity q-sweep (file 006, cal-only, --verbose; commit c56fa9b7b4)
The calibration q-value estimator is **well-calibrated across 0.1-10% at BOTH sample sizes**, and a
larger sample gives MORE and slightly CLEANER anchors. Combined true-FDP (entrapment oracle, r=0.986)
vs the claimed q, pass 1 (wide):
| q gate | 100K anchors | 100K FDP | 1M anchors | 1M FDP |
|---|---|---|---|---|
| 0.1%  |  178 | 0.00% |  2298 |  0.00% |
| 1.0%  |  479 | 1.26% |  4958 |  1.10% |
| 2.0%  |  657 | 2.76% |  6922 |  2.36% |
| 5.0%  |  829 | 5.83% |  9137 |  5.40% |
| 10.0% |  978 | 9.88% | 11113 | 11.09% |
- combined FDP ~= claimed q everywhere; true FDP bracketed [lower, combined] straddles q -> the q is
  rigorous, refuting the "not confident of q rigor at 0.01" worry (it holds across the whole range).
- 1M is slightly CLEANER than 100K at the same q (1%: 1.10 vs 1.26; 2%: 2.36 vs 2.76) - more decoys
  -> better-conditioned LDA + q. So bigger sample is strictly better (more AND cleaner).
- **Goal met by sampling: q<=0.1% at 1M = 2298 anchors at 0.00% measured entrapment-FDP** ("thousands
  of peaks at near-zero FDR"). RT points after the S/N>=5 filter: 100K default 503, 1M 5885 (q<=1%).
- Scored pool @1M pass1 = 793,739 candidates (402,463 real + 391,276 entrapment ~ r=1); only ~1.2% of
  the real-target candidates that produce a peak pass at q<=1% -> the gate correctly keeps the cleanly
  detectable subset. The ceiling is #cleanly-detectable peptides in the file, reached only via more sample.

### DOWNSTREAM - does better calibration help IDs without inflating true FDP? YES (full006 pass-2, FDRBench)
Computed directly from the existing full-run FDRBench tsvs (100K baseline vs full006-s1m), true-FDP via
the combined estimator (r=0.986):
| cal sample | q<=1% target IDs | true-FDP | q<=0.1% IDs | true-FDP |
|---|---|---|---|---|
| 100K (baseline) | 37,947 | 0.47% | 33,775 | 0.46% |
| 1M | 39,375 (+3.8%) | 0.53% | 34,302 (+1.6%) | 0.44% |
**+1,428 real IDs at q<=1%, downstream true-FDP FLAT (~0.5%, HALF the claimed 1%).** The calibration-yield
gain is a genuine, entrapment-validated, FDR-clean win - not a mirage. (300K full run launched for the
sweet-spot midpoint; result to be appended.)

### COST (cal-only, file 006): 100K = 67s, 1M = 180s (task 58 -> 179s). ~10x anchors (and cleaner) for
only ~2.7x wall-clock; the fixed library/spectra load dominates, so scaling the sample is affordable.

### PR PROPOSAL (evidence-backed; ALGORITHM-AFFECTING -> needs golden re-bless + Brendan cost/benefit sign-off)
Root problem is now precisely: the ladder stops as soon as nConfident >= MinCalibrationPoints (200)
(DecideLadderAction, Calibrator.cs:704), so a RICH file halts at 100K and leaves ~10x clean anchors on
the table. Raise the anchor yield; the q is trustworthy and the downstream is FDR-clean, so this is safe:
  (a) SIMPLEST - raise default CalibrationSampleSize (e.g. 100K -> 300K). One config value; rich files get
      ~3x anchors at ~1.5x cost, scarce files unaffected (ladder still grows them to all-targets).
  (b) ADAPTIVE - add a TargetCalibrationAnchors knob and keep growing the sample (geometric, CAPPED near
      ~1M or a config max - NOT the ladder's current jump straight to all 3.17M targets) while confident
      anchors keep rising materially. Best cost control; more code. Gate behind OSPREY_CAL_ANCHOR_TARGET,
      default 0 = current behavior (byte-identical) until blessed.
  Optional coupling: at high sample the STRICT q<=0.1% gate already yields thousands of anchors at 0.00%
      measured FDP, so the anchor gate could be TIGHTENED (cleaner RT points), never loosened past 1%
      (the q-sweep shows FDP rises ~linearly with q; >1% buys anchors at a real FDP cost).
  The --verbose anchor-purity report (c56fa9b7b4) is the standing acceptance oracle for whichever option
  ships. Step B (geometric outlier rejection) is DEMOTED: the anchors are already pure -> little to reject.

### MASS-CALIBRATION check (addresses Brendan's PPM concern) - no actionable lever
Measured on file 006 (1M cal): MS1 correction 0.94 ppm / SD 1.53 -> search tol +/-5.53 ppm; MS2
correction 0.05 ppm / SD 1.60 -> +/-4.86 ppm; RT +/-4.77 -> +/-0.58 min (R^2=0.9976, 5885 pts). Initial
fragment extraction = 10 ppm (HRAM). => the instrument is ~1 ppm (MS1) / ~0 ppm (MS2) calibrated, far
under the MacCoss 5-ppm rule; extraction is HRAM (10 ppm, within Brendan's +/-20 guideline), refined to
+/-5 ppm - NOT unit resolution. The "unit resolution absurdly wide" concern is real but confined to the
XCorr *scoring feature* (s_calXcorrScorer = BinConfig.UnitResolution, Calibrator.cs:90), NOT the mass
extraction window, and that feature is not the yield limiter (median-polish addition was near-null last
session). Conclusion: the mass/PPM path has no yield lever; sample size is the sole driver. (A HRAM-bin
calibration XCorr feature could be tried for marginal discrimination, but the reframe says it won't move
yield materially - deprioritized.)
