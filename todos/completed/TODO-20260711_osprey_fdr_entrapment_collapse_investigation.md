# TODO-osprey_fdr_entrapment_collapse_investigation.md -- Why do decoys + entrapment score at the far-right edge, and why does one file collapse to 0 IDs at 1:1 entrapment?

## Status
**Completed (created 2026-07-11, merged 2026-07-13).** Shipped as
[pwiz #4412](https://github.com/ProteoWizard/pwiz/pull/4412) (merged 2026-07-13 as `7e1bb52694`)
+ [maccoss/osprey #53](https://github.com/maccoss/osprey/pull/53) (merged 2026-07-13), a
parity-matched pair. `log10(x+1)` conditioning of peak_apex/area/sharpness (sharpness floored at 0
before the log to avoid a non-finite feature); cross-impl parity re-verified at 1e-9 on Stellar +
Astral (max delta 0), regression golden re-blessed. Validation: r=1.0 10-file file 006 0->34,165 IDs
(+22% total); r=0.5 20-file q-floor 0.88%->0.019%, FDP spike 302%->0%, +37% IDs at 1% q, entrapment
oracle flat/conservative. Deferred median-of-medians per-run intensity normalization ->
[[TODO-osprey_intensity_batch_normalization]]; scale-free sharpness idea ->
[[TODO-osprey_scale_free_sharpness]]. Was: Active (created 2026-07-11). Branch
`Skyline/work/20260711_osprey_intensity_log_conditioning` (pwiz) +
`fix/intensity-feature-log-conditioning` (maccoss/osprey PR #53). The root cause
below is diagnosed, validated, and now SHIPPED as a fix: `log10(x + 1)` conditioning of
`peak_apex` / `peak_area` / `peak_sharpness` in their calculators (C# `PeakShapeCalculators`,
Rust `compute_features_at_peak`), with the regression golden re-blessed and cross-impl
bit-parity re-verified at 1e-9 on Stellar + Astral. The deferred per-run median-of-medians
intensity normalization is spun out to [[TODO-osprey_intensity_batch_normalization]].

Raised by Brendan while validating Osprey's FDR
control with entrapment on Mike's SEA-AD Pilot-MTG dataset (10-20 of the 82 files for
now; see [[project_sead_pilot_mtg_dataset]]). This began as a **diagnosis / root-cause**
TODO, not a fix -- the goal was to understand two linked anomalies the
`--model-diagnostics` entrapment reports surface, before deciding what (if anything)
in scoring / calibration / decoy+entrapment generation needs to change. Related to
[[project_osprey_entrapment_ratio_fdr_collapse]] (the ratio-driven collapse) and the
pass-2 recalibration work ([[project_osprey_pass2_recalibration_inflates_fdr]] / pwiz
#4410), but distinct: those are about the reported-pool null; this is about the
**score distribution itself having high-scoring false members**.

Context: we run **50% entrapment (r=0.5)** because **100% (r=1.0) collapses FDR
estimation entirely.** Mike's initial hypothesis was a Stage-3 failure (RT + mass-error
calibration) on the affected file (see `Osprey-workflow.html`); that did **not** hold up.
So the cause is still open.

## ROOT CAUSE FOUND (2026-07-11, change-immune: data decomposition + code path agree)
**Raw, un-transformed intensity features hijack the Pass-1 Percolator discriminant at the
extreme top of the score ranking.** Both anomalies are the same mechanism; 006 and the r=1.0
whole-experiment collapse are just increasing severity of it. Disposition = **(a) a real Osprey
scoring behavior** -- the entrapment oracle correctly indicts the scoring, not the library.

**The mechanism (each step verified):**
1. `peak_apex`, `peak_area`, `peak_sharpness` reach Percolator **raw** (no log / robust scaling).
   Code: `PeakShapeCalculators.PeakApexCalc` returns the raw reference-XIC apex intensity
   (`reference.ApexValue`); `PercolatorEntryBuilder` passes features straight through.
2. The SVM standardizer is **plain mean/std z-scoring** -- `(x-mean)/std`, no log/clip/winsorize
   (`Osprey.ML/LinearSvmClassifier.cs:363`, `FeatureStandardizer.FitTransform`). Standardization
   centers/scales but does NOT tame a heavy tail: `peak_apex` in 006 spans p50=1,010 -> max=1.7e7
   (4 orders of magnitude), so the most intense peaks standardize to **z = 100-300**.
3. The trained model puts a large coefficient on the intensity features (peak apex +1.53, peak
   area -1.33; the diagnostics already flags peak-area's sign UNEXP). A z=300 outlier x a coef of
   1.5 is a discriminant contribution of ~450 -- swamping the bounded match-quality features
   (median-polish cosine, sg-cosine, xcorr are in [0,~1] so contribute single digits).
4. Intensity is **not target/decoy-discriminating in DIA** -- and this is a known field lesson, not
   a novel claim. In DIA a **single massive interference produces a very high intensity with no
   coelution and no fragment match**, so a decoy or entrapment precursor assigned to that interfering
   peak scores at the top on intensity alone. The observed high-scoring false members are exactly
   this: 006's rank-2 decoy DVKGLNR has `peak_apex=1.7e7` (file max) but `fragment_coelution_sum=0.71`,
   `n_coeluting_fragments=2`, `median_polish_cosine=0.16` -- a lone intense interference, not a real
   coeluting peptide. The hijacked top band is therefore a ~random mix of target / decoy / entrapment
   -- exactly the "decoys + entrapment at the far-right edge" of Anomaly B and the nAcc=1 FDP spike;
   it floors the achievable q at the density of intensity-outlier false members.

**Evidence (from the r=1.0 recheck run's per-file `.1st-pass.fdr_scores.bin` + `.scores.parquet`;
analysis scripts in `C:\proj\ai\.tmp\{read_fdrbin,fdr_curve,score_decomp,corr_check}.py`):**
- 006's #2/#3/#4 scorers are **decoys** at SVM scores 193/191/172 while 006's best *real* targets
  top out ~90-100. The rank-2 decoy DVKGLNR has `median_polish_cosine=0.16` (a non-match) but
  `peak_apex=1.7e7` (the file max) -> score 193. A real HBB hemoglobin target with cosine=0.999,
  xcorr=2.75, 6 fragments scores only 87.6. Score decomposition: for the rank-2 decoy, peak-apex
  contributes +451, peak-area -253, peak-sharpness -101; cosine contributes -5.
- Within 006's **top 1,000** by score, Spearman(score, log peak_apex)=**+0.37** while
  Spearman(score, median_polish_cosine)=**-0.20** (ranking driven by intensity, ANTI-correlated
  with match quality). Across all 4.45M entries the model is healthy (cosine +0.79, intensity
  +0.01) -- the pathology is confined to the extreme tail where FDR control lives.

**Anomaly A is the marginal extreme of Anomaly B, not a separate failure.** 006 does NOT collapse
at calibration or compaction -- it scores 4.45M entries and its `.1st-pass.fdr_scores.bin` has
40,023 entries at q<=2.5%. It reports 0 because its **minimum achievable run-level precursor q =
0.011087 (1.109%)**, a hair above the 1.0% cutoff; healthy files floor at 0.3-0.4%. 006 simply has
~3-4x the density of high-scoring false members in its top band (top-100: 58 false vs 007's 23;
top-1000: 99 vs 27) -- same library composition (~25% each of T/PT/D/PD), so it is a *scoring*
difference, not a library one. At r=1.0 the doubled entrapment competitor count pushes every file's
floor up until the pass-2 retrain drives the whole experiment to 0.

**Compounding: the Pass-1 Percolator SEED shares the calibrator TODO's weakness
([[TODO-osprey_calibrator_selection_review]]).** Pass-1 Percolator seeds from the **single best
individual feature** at a **tight 1% first cutoff** (`PercolatorFdr.cs:407-434`
`FindBestInitialFeature`; relaxes to 5% only if *zero* pass), then re-derives SVM weights freely
each of 10 iterations. This is the same single-best-feature + tight-cutoff pattern the calibrator
review flags, and the log symptom is the same: only "1.5% of training targets at 1% FDR" at
convergence.

**Why intensity is the wrong thing to let a DIA seed/model lean on.** Intensity is a trustworthy
correctness signal on clean **MRM** data (where the original mProphet used it as the seed), but not
on **DIA**: one massive interference yields a huge intensity with no coelution, so intensity no
longer tracks correctness. This is a known DIA lesson, and it is the failure mode measured above.
Skyline's DIA-era practice keeps intensity a **low-weight** term in the fixed composite seed
(`LegacyScoringModel.DEFAULT_WEIGHTS` intensity=1.0 vs identified-count=20, shape=4, dotp=3) +
a **loose 15% first cutoff** + progressive tightening, so intensity stays unimportant *by
construction*. Skyline's intensity feature is ALSO conditioned: `MQuestIntensityCalc` returns
**`Math.Max(0, Math.Log10(area))`** (`Skyline/Model/Results/Scoring/MQuestFeatureCalc.cs:344`) --
log-transformed AND floored at 0, so a lone interference cannot blow the standardized value out.
Osprey is a DIA tool but (a) feeds intensity **raw linear** (`peak_apex`/`peak_area`/`peak_sharpness`,
no log, no floor), and (b) has **no low-intensity prior** -- a single-best-feature seed + free
per-iteration SVM re-derivation lets the model train raw intensity up to a dominant, heavy-tailed
weight, re-introducing exactly the pre-DIA mistake. So Osprey misses all three of Skyline's
guards (log, floor/clip, low fixed seed weight). The two fix levers -- log/robust-condition the
intensity features; anchor the seed so intensity starts and stays low -- are complementary.

**A linear model CANNOT self-correct this -- feature conditioning is mandatory, not optional.**
The classifier is a strictly linear SVM: `LinearSvmClassifier` scores `w . x + b` via dual
coordinate descent (Liblinear), no kernel, no basis expansion (`Osprey.ML/LinearSvmClassifier.cs:26,
639-648`). A general (kernel) SVM can in principle discover a saturating/log response to a feature;
a LINEAR one cannot -- its response to `peak_apex` is exactly linear in the standardized value, which
is exactly linear in the raw value, so a raw intensity 300 sigma out MUST contribute 300x the per-
sigma weight. There is no weight the trainer can pick that both uses intensity's weak real signal and
caps the interference outlier. The transform has to happen BEFORE the model -- which is exactly what
Skyline does with `Math.Max(0, Math.Log10(area))` (log then floor). Worth flagging because a general
(kernel) SVM *can* discover a saturating/log response and "self-determine" the score shape -- so it is easy to
assume the classifier will handle a raw feature -- but that only holds for a kernel SVM; this linear
one has no such capacity, so the conditioning is on us. `log10(1.7e7)~7.2` vs `log10(1010)~3.0` -> the
standardized log-intensity outlier is ~z=3-5, not z=300, and the hijack disappears.

**Two candidate fix directions (NOT to implement until A/B'd; diagnosis TODO):**
- *Feature conditioning (PRIMARY -- forced by the linear model)* -- log-transform (+ floor / winsorize)
  the three intensity features so their standardized values cannot reach z=hundreds. Smallest, most
  direct change, and the only one that structurally removes the outlier leverage.
- *Seed anchoring (SECONDARY / complementary)* -- adopt the mProphet pattern for Pass-1 (and Stage-3
  calibration): fixed composite seed with intensity pinned low + looser first cutoff + progressive
  tightening, so semi-supervised training does not train intensity up in the first place. Helps but is
  not sufficient alone: a small weight x a z=300 feature is still a real contribution, so pair it with
  conditioning. Shared with [[TODO-osprey_calibrator_selection_review]].

**Still to verify before any fix:** (i) does Rust osprey feed raw intensity the same way? (near-
certain -- the C# is a port of `osprey-fdr/src/percolator.rs` and features mirror Rust -- so this is
a shared Osprey algorithm property, not a C# porting bug, and a fix needs golden re-bless +
parity coordination). (ii) A/B log-transform-only vs seed-only vs both, measured on the entrapment
FDP + downstream IDs across r=0.1..1.0, to attribute how much each lever recovers.

## FIX VALIDATED (A/B, 2026-07-11) -- log-conditioning the intensity features recovers 006 and the q-floor
A/B on the 10-file r=1.0 set (gate-off baseline reproduced the recheck exactly: 248,727 / 006=0;
gate-on reused the same scores parquets so only the intensity conditioning differs). Log10(x+1) on
peak_apex/peak_area/peak_sharpness (applied via the FeatureStandardizer diagnostic gate
`OSPREY_LOG_INTENSITY=1` -- see the architecture note below):
- **006: 0 -> 34,165 precursors** (now the 2nd-highest file); its SVM score range collapses from
  -373..+330 to -34..+17 and its top-15 by score become ALL targets (baseline had decoys at ranks
  2/3/4). 006 min run-q 0.011087 -> 0.000135.
- **Experiment q-floor 2.503% -> 0.043%**; **combined FDP@nAcc1 203% -> 0%** (the top-of-ranking
  spike is gone).
- **Total 248,727 -> 303,651 IDs (+22%)** -- the hijack suppressed IDs experiment-wide, not just 006
  (012 +6,871, 010 +3,846, 015 +3,655; healthy 007 flat).
- **Entrapment oracle: FDP@1% q = 0.83% (conservative, below nominal)**, entrapment fraction of the
  accepted set essentially unchanged (0.37% -> 0.39%). So the extra IDs are REAL, not relaxed FDR.

**Architecture (committed fix != the A/B gate).** The A/B used an env-gated log-transform inside
`FeatureStandardizer` as a no-re-score DIAGNOSTIC EXPEDIENT (do not commit). The committed fix moves
the transform INTO the intensity calculators (`PeakApexCalc`/`PeakAreaCalc`/`PeakSharpnessCalc` in
Osprey.Scoring/PeakShapeCalculators.cs), each returning `log10(x+1)`, exactly like Skyline's
`MQuestIntensityCalc`. Confirmed contained: those three fields feed ONLY the PIN vector
(ParquetScoreCache:566-568); quant/blib uses the separate `BoundsArea`. Full PR proposal (scope,
consequences: re-score + golden re-bless + Rust parity, test plan, alternatives) is drafted at
`ai/.tmp/osprey-intensity-fix-pr-proposal.md`. **PR not opened yet** per Brendan.

## Anomaly A -- one file collapses to 0 IDs at 1:1 entrapment
At r=1.0, file **Astral-SEA-AD_2-MTG-May2026_SEA-AD-0002_7297_A02_006** reports
**0 targets / 0 decoys / 0 entrapment**, while the other 9 files report normally
(26K-43K targets each). Evidence (perFile in the embedded JSON):
`D:\test\Pilot-MTG-Tissue-May2026\runs\seaad-10files-entrapment-r1.0-recheck\seaad.model-diagnostics.html`
```
0001_..._005: targets 35989, decoys 293, entrapment 131
0002_..._006: targets 0,     decoys 0,   entrapment 0      <-- collapsed
0003_..._007: targets 43094, decoys 348, entrapment 167
... (0004-0010 all normal)
```
At r=0.5 the 006 file does NOT collapse (it is in the healthy 20-file run). So the
collapse is triggered by the 1:1 entrapment ratio interacting with something specific
to 006.

**Stage-3 calibration is NOT the cause (CONFIRMED from the r=1.0 log, not memory).** Mike's
initial guess was a Stage-3 RT/mass calibration failure on 006; the degenerate-case log
(`...\seaad-10files-entrapment-r1.0-recheck\run.log`) shows 006's calibration SUCCEEDING:
```
Scoring file 2/10: ...SEA-AD-0002_..._006.mzML
Running RT calibration...
Calibration pass 1: 402 RT calibration points (from 483 peptides at 1% FDR)
Calibration pass 2: 503 RT calibration points (from 624 peptides at 1% FDR)
Calibration summary [...006]: RT tolerance +/-4.77 -> +/-0.55 min; RT fit MAD=0.124,
  SD=0.217, R^2=0.9977, n=503
Scored 4506993 entries (2271631 targets, 2235362 decoys) for ...006
```
So 006 calibrates fine (R^2=0.9977, tolerance tightened 4.77->0.55 min) and scores 4.5M
entries. The zero happens LATER (Stage 5+ FDR / compaction), not at calibration. NUANCE
worth keeping: the calibrator count *does* fall as entrapment % rises (fewer peptides pass
the calibrator FDR gate when the entrapment competitors multiply) -- a real phenomenon Mike
just addressed with an RT-calibration-degradation handling PR -- but at r=1.0 006's count
(483->624 peptides) never gets low enough to trip that degradation. So calibration
robustness is a genuine concern (see the separate calibrator-selection TODO) but is not
what zeroes 006.

Open: what actually zeroes 006's output at r=1.0 downstream of calibration? A file-specific
score/threshold interaction, an all-decoy/entrapment top for that file, or an empty
post-compaction pool? Bisect the pipeline stage where 006 goes from 4.5M scored entries to
0 reported.

## Anomaly B -- decoys AND entrapment score at the far-right (high-score) edge
Normally the top of the score ranking is a clean run of pure targets -- a score band
with **no decoys and no entrapment** -- and q therefore starts at ~0. Here it does not:
the reported q **never starts near 0** (it is floored at the best-scoring
decoy/entrapment), and the entrapment-measured FDP **spikes at the very top** of the
ranking before settling. Evidence (Pass-1 experiment-wide fdpView, q grid + combined FDP
+ nTargetAccepted):
- r=1.0 recheck: q floored at **0.02503** (nothing < 2.5% q); combined FDP at the top
  = **2.03 (203%)** at nAcc=1, then 6.6%, 3.4%, 2.3% as nAcc grows (11.6K, 23.2K, 34.8K).
- r=0.5 percolator (20-file): Pass-1 q floored at **0.00877** (nothing < 0.88% q);
  combined FDP = **3.02 (302%)** at nAcc=1, then 99%, 59%, 42%, 33% over the first few
  hundred accepted. (Pass-2 floors q much lower, 0.00024, and still spikes at the top --
  the retrain drives q down but does not remove the high-scoring false members.)
  Source: `runs\seaad-20files-entrapment-r0.5-percolator\seaad.model-diagnostics.html`.

This is visible in the 2nd-pass composite-score plot too: the decoy histogram and the
entrapment trace are not confined to the low-score region; a minority of decoy/entrapment
members reach the high-score edge where only real targets should live. That high-scoring
false tail is what floors the achievable q (you cannot get q below the FDP implied by the
best false member) and produces the top-of-ranking FDP spike.

Anomaly A is likely the extreme of Anomaly B: at r=1.0 there are twice as many entrapment
competitors, so a file already prone to high-scoring false members (006) tips over into
a fully entrapment/decoy-dominated top -> nothing passes -> 0 IDs.

## How to work this -- load the /debugging skill first
This is a root-cause investigation, not a code change: **load the `/debugging` skill before
starting** and follow it. Understanding these anomalies will take the two tools that skill
enforces -- (1) **bisection** (isolate 006 alone; bisect the ratio; bisect the pipeline stage
where 006 goes to zero and where the high-scoring false members first appear), and (2)
**adding diagnostic output** to the runs (Stage 1-5 dumps, per-precursor score/label traces
for the top score band, post-compaction pool sizes per file) to zero in on the mechanism.
Do NOT propose a fix until the root cause is established and verified against a change-immune
anchor -- resist "it's probably calibration" (that guess was already made and did not hold).

## Investigation tasks (diagnosis first, no fix committed until understood)
- [ ] **Isolate 006 at r=1.0.** Run 006 alone (or 006 + 1 healthy file) at r=1.0 with
  full Stage 1-5 diagnostic dumps. Confirm/deny Stage-3 calibration (RT + mass error)
  is sane on 006 (Mike's ruled-out hypothesis -- re-verify with the dump, don't trust
  memory). Check the post-compaction pool size for 006: is it empty (0 survivors) or
  is it non-empty but all q > 1%? Where in the pipeline does 006 go to zero?
- [ ] **Characterize the high-scoring false members.** Pull the actual decoy + entrapment
  precursors in the top score band (e.g. top 1% by composite score). What are they --
  specific sequences, charges, RT/mass, fragment counts? Are they a consistent motif
  (e.g. the N-terminal-Met-clip artifacts already flagged in the entrapment warnings:
  "11745 entrapment peptides have no target pair ... AAAAAEEGGEK ... investigate")?
  Are the high-scoring decoys library-supplied or Osprey-generated (libdecoy vs gendecoy;
  see [[project_osprey_libdecoy_vs_gendecoy_calibration]])?
- [ ] **Entrapment library quality.** The r=0.5b/r1.0 entrapment libraries were built by
  subsample (subset-entrapment-ratio.py) + Carafe. Are the high-scoring entrapment
  peptides real foreign-species sequences, or artifacts of the entrapment generation
  (e.g. sequences that collide with real targets, or Met-clip near-duplicates of targets)?
  A high-scoring entrapment that is actually a near-duplicate of a real target is a
  measurement artifact, not a true Osprey false positive -- separate the two.
- [ ] **Ratio dependence.** Sweep is already done (r=0.1/0.5/0.75/0.9/1.0 collapse cliff at
  r=1.0, [[project_osprey_entrapment_ratio_fdr_collapse]]). Tie THIS finding to that:
  is the r=1.0 collapse the same mechanism (high-scoring false members swamping at 1:1)?
- [ ] **Decide the disposition.** Three outcomes are possible and the TODO should end by
  choosing: (a) a real Osprey scoring/calibration bug (high-scoring false members are
  genuine mis-scores -> fix scoring); (b) an entrapment-library artifact (fix the
  entrapment generation / exclude target-colliding entrapment -> the measurement, not
  Osprey, is off); (c) expected behavior of DIA at this depth (some foreign peptides
  genuinely match well -> the FDP is real and Osprey is correctly reporting a hard
  problem). The entrapment oracle only indicts Osprey if (a).

## References
- Data: `D:\test\Pilot-MTG-Tissue-May2026\runs\seaad-10files-entrapment-r1.0-recheck\`
  (006 = 0 IDs), `...\runs\seaad-20files-entrapment-r0.5-percolator\` (q floor + FDP spike).
- Mike's Stage-3 calibration hypothesis: `Osprey-workflow.html` (ruled out -- re-verify).
- [[project_sead_pilot_mtg_dataset]], [[project_osprey_entrapment_ratio_fdr_collapse]],
  [[project_osprey_natural_entrapment]], [[project_osprey_libdecoy_vs_gendecoy_calibration]].
- The entrapment "no target pair / investigate" warnings in every run.log
  (`AAAAAEEGGEK, AAAAGECYPSR, AAAAPCPQFAR ... 11745 excluded`).
