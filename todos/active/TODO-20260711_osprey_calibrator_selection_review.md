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

## References
- Code: `Osprey.Tasks/Calibrator.cs` (RunCalibration :180, retry ladder :318-622, CollectCalibration
  Points :1274, floors/constants :53-56), `Osprey.Scoring/CalibrationScorer.cs` (ExtractFeatureMatrix
  :581, TrainLdaWithNonNegativeCv :227, CompeteCalibrationPairs :150, SelectPositiveTrainingSet :513),
  `QValueCalculator.cs:49`, `RTCalibrationConfig.cs`, `PerFileScoringTask.cs:1814` (summary log).
- #4401/#4402 (calibration degradation retry ladder + graduated-RT fallback).
- [[TODO-osprey_fdr_entrapment_collapse_investigation]] (shares the high-scoring-false-member theme).
