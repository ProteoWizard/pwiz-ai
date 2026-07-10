# Osprey C# drops Rust's calibration retry ladder and the >=50-point acceptance floor

**Status:** Completed — pwiz #4402 merged 2026-07-10 as `9b5b4105d7`.
**Issue:** https://github.com/ProteoWizard/pwiz/issues/4401 (auto-closed on merge)
**PR (pwiz):** https://github.com/ProteoWizard/pwiz/pull/4402 (merged 2026-07-10 as `9b5b4105d7`)
**PR (maccoss/osprey):** https://github.com/maccoss/osprey/pull/52
**Branch (pwiz):** `Skyline/work/20260709_osprey_calibration_retry_parity` (off `origin/master` c9526f0e6)
**Branch (maccoss/osprey):** `fix/calibration-pass2-min-points` (off `origin/main` f6d2a0f)
**Found:** 2026-07-09, while reading the 82-file SEA-AD Astral run log for unrelated memory work.

## Symptom (reproduced, Gate 0)

Three of 82 SEA-AD files fell back to **uncalibrated** m/z and RT tolerances. Reproduced
exactly on master `c9526f0e6`:

```
Calibration pass 1: 193 RT calibration points (from 243 peptides at 1% FDR)
[WARN] Insufficient calibration points in pass 1 (193 < 200).
[WARN] Calibration pass 1 failed. Using fallback tolerance.
```

`SEA-AD-0071_7043_G05_093` (193 pts), `SEA-AD-0073_7181_G07_095` (178),
`SEA-AD-pool-07_G10_098` (141).

## Root cause: the port stopped after attempt 1

Rust has **two orthogonal loops**; C# ported only the inner one.

| Loop | Rust | C# (before) |
|---|---|---|
| Outer *attempt ladder* | `for attempt in 1..=max_attempts` (`pipeline.rs:750`): seed `42+attempt`, accumulate matches per entry across attempts (`:730,:812-825`), retrain LDA on the accumulated set, grow sample on shortfall, final attempt uses ALL targets, accept `>=50` (`:1028`) | **absent** -- one `SampleLibraryForCalibration(..., 43UL)` |
| Inner *tolerance refinement* | narrow RT tolerance from MAD, re-score, accept if R^2 holds (`:1087-1238`) | `pass1`->`pass2` in `RunCalibration` |

`CalibrationRetryFactor` existed, was hashed into `SearchIdentity`, and was read by nothing.

### Two corrections to the original issue text

1. **Rust does NOT abort the run below the 50-point floor.**
   `run_calibration_discovery_windowed` returns `Err`, but its only caller
   (`pipeline.rs:4278`) catches it, logs "Calibration failed ... Using fallback
   tolerance", and searches that file uncalibrated. Net behaviour is a per-file
   graceful degrade -- exactly what C# does, and what `docs/02-calibration.md:402`
   documents. **There is no divergence**, so the "one bad file kills an 82-file batch"
   design question was moot.

2. **`CalibrationMatch.score`'s doc comment was wrong.** `batch.rs:869` claimed
   "Primary score (XCorr, same as xcorr_score)", but the field means "the primary score
   of whichever scorer produced this match": XCorr from `run_xcorr_calibration_scoring`
   (`:2210,:2367`), and the **co-elution correlation sum** from
   `run_coelution_calibration_scoring` (`:2773`) -- the one the pipeline actually calls.
   The accumulate step compares that field, so the C# equivalent is `CorrelationScore`,
   **not** `DiscriminantScore` (LDA overwrites that in place between attempts).
   Mutation-tested: swapping to `DiscriminantScore` fails `TestCalibrationMatchAccumulation`.

## A latent Rust bug on exactly the band files

Pass 2 reused pass 1's `calibrator`, whose `min_points` is `effective_min_points`. On a
band file that is `n_pass1` (e.g. 193), not 50 -- so a refit yielding 50..192 points
cleared Rust's own `>= 50` guard (`pipeline.rs:1141`) and then tripped
`RTCalibrator::fit`'s `min_points` check (`rt.rs:109`). The error propagated to the caller,
which discarded a **perfectly good pass-1 calibration** and ran the file uncalibrated --
the same failure mode as #4401, reached by another route. `docs/02-calibration.md:145`
says the pass-1 calibration should be kept. Clean files never hit it (`n_refined ~ 800`).

## A second bug, in both trees, that two self-review passes missed

Copilot (on maccoss/osprey#52) caught what neither self-review did. Pass 2 calls
`select_fit_plan(n_refined)` like pass 1, so it can land in the **linear tier**
(`n_refined` in `[50, 100)` -- reachable, because pass 2 only runs when pass 1 was LOESS,
i.e. `n_pass1 >= 100`, and pass 2 requires `>= 50`). But the linear-tier guards
(`has_sufficient_rt_span`, `is_plausible_linear_fit`) were applied **only to pass 1**, and
pass 2 was accepted on **R^2 alone**. A line through points clustered in a narrow RT span
scores R^2 ~ 1 while extrapolating badly, so it could displace a perfectly good pass-1
LOESS calibration. Fixed in both trees via `is_refined_fit_acceptable` /
`IsRefinedFitAcceptable`, which is a no-op for a LOESS refit and applies both guards to a
linear one. Mutation-tested: forcing it to always accept fails
`TestRefinedLinearFitMustClearPass1Guards`.

**Lesson:** both self-review passes checked the *new* guards' internal arithmetic and the
pass-1 call site, and neither asked "where *else* can a linear fit be produced?" The guard
was reviewed; the guard's coverage was not. Worth adding to the review prompt: for any new
validation, enumerate every path that can produce the validated object.

## What was implemented

### pwiz (`Osprey.Tasks/Calibrator.cs`, `Osprey.Chromatography/RTCalibration.cs`)

* Outer **retry ladder** mirroring `pipeline.rs:700-1271`: `ComputeMaxAttempts`, seed
  `42+attempt`, per-`EntryId` accumulation (best `CorrelationScore`, carrying its S/N and
  RTs), LDA retrained on the accumulated set, growth by `CalibrationRetryFactor`, final
  attempt uses all targets.
* `>=50` acceptance floor with `effectiveMinPoints = Math.Min(nConfident, MinCalibrationPoints)`.
  `MinPoints` is a fit-time guard only (the other branch reading it is behind
  `OutlierRetention < 1.0`, pinned to 1.0), and `effectiveMinPoints <= n` always, so the
  clean path cannot shift.
* Sub-50: graceful fallback, loud, `calibration_successful=false` (already wired via
  `rtCalibration != null`).
* **Graduated fit tier** (Mike, 2026-07-09): a LOESS local window holds `bandwidth * n`
  points, so a fixed 0.3 bandwidth lets the window collapse as n falls (n=729 -> 219 pts,
  193 -> 58, 100 -> 30, 50 -> 15). `SelectFitPlan` holds the window near the size the
  default config yields at `MinCalibrationPoints` (0.3*200 = 60) by *widening* bandwidth
  as n shrinks, and below `LINEAR_FIT_MAX_POINTS = 100` fits a global line
  (`RTCalibratorConfig.LinearFit`, reported as `RTCalibrationMethod.Linear`). The linear
  path reuses the existing knot representation, so `Predict`/`InversePredict`/model params
  /resume/HPC merge are untouched.
* **Low-n regime** (Mike, 2026-07-09: "even for <50 peptides a fit ... is better than just
  the range", worried those 50 may not be confident):
  * **Fit floor 50 -> `MIN_LINEAR_FIT_POINTS` = 15**, but guarded rather than trusted:
    also requires the points to span >= 50% of the library RT range
    (`HasSufficientRtSpan` -- leverage, not just count) and the fitted line to pass
    `IsPlausibleLinearFit` (slope within 2x of the range mapping either way, positive,
    predictions inside the acquisition window +/-10%). Any failure -> fallback.
  * **Theil-Sen replaces OLS** for the linear tier. Those peptides cleared LDA + 1% FDR +
    S/N, but at n~40 the FDR estimate is granular so a false positive or two can survive,
    and OLS lets one at an RT extreme lever the slope. Theil-Sen's ~29% breakdown removes
    that. Test: 3 false positives, 2 at the extremes, slope still recovered to 1e-9.
  * **n-aware minimum RT tolerance** (Mike's explicit ask -- "if the MAD is small by luck
    I'd rather have a minRTtolerance larger than 0.5 min"). The sampling error of a scale
    estimate shrinks like `1/sqrt(n)`, so
    `EffectiveMinRtTolerance(n) = MinRtTolerance * sqrt(MinCalibrationPoints / n)`:
    0.50 min at n>=200 (unchanged), 0.71 at 100, 1.00 at 50, 1.83 at 15, capped at
    `MaxRtTolerance`. Applied at all four floor sites (both calibration passes, the main
    search, and the persisted JSON half-width) so they cannot disagree. The window still
    tightens from the MAD -- just no further than the fit's own precision supports.
  * **Pass-2 refinement is skipped off a linear fit.** Pass 2 re-scores *inside* the
    narrowed window, so points outside a mis-centred window can never be recovered --
    harmless at n=729, the whole risk at the bottom of the tier. This is Mike's original
    self-confirming worry, now structurally impossible in the linear regime.
  * **A pass-2 fit that lands in the linear tier must clear the same guards as pass 1**
    (`IsRefinedFitAcceptable`) -- see the Copilot finding above. R^2 alone is not evidence
    that a line is right; a narrow-span line scores R^2 ~ 1.
* **Fallback now uses the range line, not the identity.** Both trees previously searched
  at the raw library RT when calibration failed (C# `PeakDataExtractor.cs:97`, Rust
  `pipeline.rs:8265` + `MzRTIndex::build`), discarding the `rtSlope`/`rtIntercept` range
  mapping that calibration had already computed. `RTCalibration.FromLinearMapping` /
  `RTCalibration::from_linear_mapping` now supplies it as a predict-only calibration
  (C# via `ScoringContext.FallbackRtMap`, Rust via `fallback_rt_map`). It is the identity
  -- hence a strict no-op -- whenever the two RT scales already agree, and only bites for
  scale-mismatched libraries (e.g. Carafe `Tr_recalibrated` in seconds vs a minutes-keyed
  mzML), where the search currently runs at a completely wrong RT. It carries no
  residuals: the tolerance stays `FallbackRtTolerance`, `calibration_successful` stays
  false, and Rust's reconciliation retention was re-gated on `cal_params` so the range
  line cannot seed inter-replicate reconciliation.
* Refactor: the monolithic `RunCalibrationScoringPass` split into `EmitScoringDumps`,
  `MergeCalibrationMatches`, `BuildSortedMatchArray`, `RunLdaAndCollectPoints`,
  `FitCalibrationPass`, `RunRefinementPass`, plus pure `ComputeMaxAttempts`,
  `DecideLadderAction`, `SelectFitPlan`. Window preprocessing hoisted out of the loops.

### maccoss/osprey (`pipeline.rs`, `rt.rs`, `batch.rs`)

* Fixed the pass-2 `min_points` bug: the refit builds its own adaptive floor
  (`n_refined.min(min_calibration_points)`) instead of reusing pass 1's calibrator.
* Ported the same graduated tier (`select_fit_plan`, `LINEAR_FIT_MAX_POINTS`,
  `RTCalibratorConfig::linear_fit`, `RTCalibration::method()`), so the two trees stay
  comparable on band files.
* Corrected the `CalibrationMatch.score` doc comment.

## Gates

* **Gate 0 (baseline, master c9526f0e6):** bug reproduced; 193/178/141 points, all fell back.
* **Gate 1 (Stellar regression, 1e-9 vs golden):** PASS -- `mode1 (vs golden)`,
  `mode2 (resume)`, `mode3 (HPC chain)` all bit-identical. The ladder and the tier are
  unreachable at n >= 200, so clean data cannot move.
* **Gate 3 (SEA-AD 093/095/098, wiped work-dir):** all three now calibrate. The ladder
  rescues them on **attempt 2** -- no file reaches the graduated tier.

| File | pts (attempt 1) | pts (attempt 2) | after pass-2 | precursors before | after | delta |
|---|---|---|---|---|---|---|
| 0071 G05_093 | 193 | 633 | 729 (R^2 0.9984, SD 0.187) | 15,602 | 17,470 | +12.0% |
| 0073 G07_095 | 178 | 554 | 691 (R^2 0.9985, SD 0.185) | 12,999 | 14,235 | +9.5% |
| pool-07 G10_098 | 141 | 457 | 611 | 12,552 | 14,326 | +14.1% |
| **total** | | | | **41,153** | **46,031** | **+11.9%** |

Experiment-level: 17,735 -> **19,797** peptides at 1% FDR (+11.6%).
Wall clock **26m46s -> 19m22s**: the tighter RT window (fallback +/-2.0 min -> +/-0.50 min)
shrinks the main search more than the extra attempt costs. MS1/MS2 mass calibration also
goes from "not calibrated" to +1.10 / +0.19 ppm corrections.

Note 193 -> 633 is a **3.3x** jump from a 2x larger sample: matches accumulate across the
two differently-strided samples, and the larger LDA training set sharpens the discriminant.

* **Gate 1 re-run after every phase** (tier; low-n floor + Theil-Sen + tolerance floor;
  fallback range line): PASS each time. Every new path is unreachable at n >= 200, and
  the tolerance floor reduces exactly to 0.5 min there.
* **Calibration-only re-check** (`OSPREY_EXIT_AFTER_CALIBRATION=1`, file 093): bit-identical
  to Gate 3 -- 193 -> 633 -> 729 points, MAD=0.103, R^2=0.9984, +/-0.50 min floor,
  MS1 +1.10 ppm, MS2 +0.19 ppm. The low-n work is inert on these files.
* **"Inert at n >= 200" confirmed empirically, not just argued.** Self-review pointed out
  the claim depends on every golden's *accepted* calibration (including an accepted pass-2
  refit, whose narrowed window can yield fewer points than pass 1) having n >= 200.
  Stellar: Gate 1 passes against the committed golden with no regeneration. Astral,
  measured directly via `OSPREY_EXIT_AFTER_CALIBRATION`: n_points = 3145 / 3207 / 3011,
  method LOESS. Both datasets are far above the threshold.
* **Self-review (fresh-context agent) found no HIGH.** It independently verified from the
  Rust source that `CalibrationMatch.score` is the co-elution correlation sum (so
  `CorrelationScore`, not `DiscriminantScore`, is the right accumulation key), that Rust
  runs LDA on a *clone* while C# mutates in place but only ever reads feature columns LDA
  never writes, and that the `(base_id, entry_id)` sort makes the Dictionary/ConcurrentBag
  order irrelevant. Two LOW divergences it found were fixed: `FromLinearMapping` accepted a
  non-finite `libMaxRt` where Rust rejects it, and pass 2's `MinPoints` was
  `Math.Min(20, n)` where Rust uses `min(n, min_calibration_points)` (inert today, since
  both are <= n and the guard is the only consumer, but a latent divergence if `MinPoints`
  ever becomes fit-affecting).
* **Third self-review, targeted at the pass-2 guard alone** (the one behaviour change no
  independent reviewer had seen): no HIGH, no MEDIUM. It independently enumerated every
  `Fit` call site to confirm the guard's *coverage*, not just its arithmetic: pass 1 is
  guarded pre- and post-fit, pass 2 now at both acceptance sites, `CalibrationRefit.Refit`
  never sets `LinearFit` (always LOESS), resume loads a stored model without refitting, and
  the HPC reduce merges PSMs rather than RT fits. It also proved the guard is a strict
  no-op above the tier: `SelectFitPlan` gates on `n < 100` *unconditionally*, so
  `n_refined >= 100` can never be linear even under a non-default `MinCalibrationPoints`.
  Two LOWs, both accepted as-is: the Rust test builds its LOESS case with default
  bandwidth/min_points where C# pins 0.3/20 (both only assert the method and the guard
  result, so no parity risk), and C# rejects a non-finite fitted slope via the ratio check
  where Rust rejects it earlier via `!is_finite()` (same outcome on every input;
  pre-existing, and a slope over finite points cannot be infinite).
* **Rust:** `cargo fmt` clean, `clippy -D warnings` clean (against `stable` 1.97, after a
  `rustup update` -- CI tracks stable and 1.97 added a `clippy::question_mark` lint that
  fires on untouched `osprey-io/src/mzml/parser.rs`, which is what turned CI red, not this
  PR), 557 tests pass. **GitHub CI green on ubuntu, macOS and windows** (`38604e6`).
* **C#:** 486 tests pass, 3 skipped (cross-impl parity tests that need Rust parquet
  fixtures not present locally). Inspection adds **zero** new warnings (the 11 remaining, in
  `SystemMemory.cs` and `PerFileScoringTask.cs`, are pre-existing on master -- verified
  against a stashed clean tree).

## Why those three files, specifically: low yield, not bad chromatography

Worth recording, because the obvious hypotheses are all wrong. Controlled comparison of
the healthy `SEA-AD-0001_..._A01_005` against the failing `SEA-AD-0071_..._G05_093`, with
an identical 100k sample, the same seed 43, and the same 1,594,868-target library:

| | healthy 005 | failing 093 |
|---|---|---|
| LDA target wins | 823 | 241 |
| after S/N filter | 689 pts (-16.3%) | 193 pts (-19.9%) |
| MS1 mass precision | 1.56 ppm SD | **1.29 ppm SD** |
| fit once enough pts accumulate | R^2 ~ 0.998 | R^2 = 0.9984 |

So 093 is **~3.4x less detectable**, and *nothing else* differs: S/N attrition is
comparable, its mass precision is actually **tighter**, and its RT behaviour is fine --
once the ladder gives it enough points it fits as well as any healthy file. It is not an
RT problem, a peak-shape problem, or an instrument problem. The ladder is therefore the
right fix in kind: it buys **more evidence** rather than stretching thin evidence further,
which is why the +12% recovered IDs rest on 729 genuinely confident peptides rather than
on a loosened threshold.

## Known gaps

**Gate 4 (FDRBench entrapment) as originally scoped is vacuous.** Because the change is
bit-identical on Stellar/Astral, running entrapment there measures nothing about the band
path. Validating that the +4,878 recovered precursors are real needs an entrapment library
on a *band* file. Accepted for now (Mike, 2026-07-09) on indirect evidence: the IDs are
target-decoy FDR-controlled exactly as before, and arise from a 4x tighter RT window plus
m/z recalibration, not from loosening anything.

The graduated tier, the low-n linear regime, the pass-2 linear guard and the range-line
fallback are likewise **not exercised by any real data** -- no file in the 82 lands below
200 after the ladder, and none fails calibration. They are covered by unit tests only,
which is the same coverage-hole shape that produced #4401. (The pass-2 guard is the
sharpest instance: `n_refined` in `[50, 100)` occurs in no file in Stellar, Astral, or the
82, which is precisely why the missing guard survived implementation and two reviews.)

**Next step: expose the ladder knobs so those paths can be tested on real data.**
`--calibration-sample-size` / `--calibration-retry-factor` / `--min-calibration-points`
exist in `RTCalibrationConfig` and are already hashed into `SearchIdentity` (so no stale
cache), but are reachable from neither the CLI nor an env var. With them:
* `retry_factor = 1.0` makes `ComputeMaxAttempts` return 1, pinning 093 at exactly
  **193 points** -- a real-data band fixture whose right answer we already know (the
  729-point fit, R^2=0.9984).
* shrinking `calibration_sample_size` walks 093 down through the band and below 50,
  exercising the stiffened LOESS, the Theil-Sen line, and finally the fallback.
`OSPREY_EXIT_AFTER_CALIBRATION=1` makes each such run cheap (calibration only, no search).

Cross-impl: `Compare-EndToEnd-Crossimpl.ps1` only accepts `-Dataset Stellar|Astral`, so it
cannot be pointed at a SEA-AD file as-is. With the knobs above, a band fixture could be
built on Stellar instead and compared properly.

## Handoff (2026-07-09)

Everything reachable from this account is green. Two steps remain, both for a maintainer:

1. **TeamCity** `ProteoWizard_OspreyWindowsNetPerfRegressionTests`, triggered with
   `branch=pull/4402`. It **must** be the `pull/4402` ref -- passing the branch name
   silently builds master and reports a meaningless green.
2. **Brendan** to review, test and merge (pwiz #4402), and to merge maccoss/osprey#52.
   Merge order does not matter: neither PR depends on the other at build time, and the two
   trees are only compared by `Compare-EndToEnd-Crossimpl.ps1`, which is run manually.

Mike cannot trigger TeamCity from his account (2026-07-09).

### 2026-07-10 - Merged

PR #4402 merged as commit `9b5b4105d7`. Reviewed via `/pw-review`: build + 494 tests
green (after merging current master, which pulled in #4395/#4399/#4400/#4403 — the
`Calibrator.cs`/`PerFileScoringTask.cs` overlap auto-merged cleanly, no conflicts). Shipped
the full retry ladder + graduated fit + low-n linear regime + range-line fallback as
described above. Squash subject dropped the "Reported by Mike" line (Mike authored both the
issue and the fix — no external reporter to credit).

**Gates at merge:** GitHub checks green (18/18); the manual Osprey Perf/Regression
(`ProteoWizard_OspreyWindowsNetPerfRegressionTests`) was **triggered on `pull/4402`
(build 4086146)** but merged before it finished — Astral legs not confirmed green at merge
time; check 4086146 post-hoc. Local `regression.ps1 -Dataset Stellar` was set up but not run
(merged first); Stellar was already covered by the committed golden + the branch's own Gate 1.

**Deferred (unchanged from Known gaps above):** the graduated tier / low-n linear regime /
pass-2 linear guard / range-line fallback remain unexercised by real data — Brendan's
entrapment FDR + model-performance tooling on the 82-run SEA-AD set is the intended coverage,
plus exposing `--calibration-retry-factor` / `--calibration-sample-size` /
`--min-calibration-points` to pin file 093 at 193 points as a real-data band fixture. The
FDRBench-on-a-band-file check (Gate 4) is likewise deferred to that tooling. Companion
**maccoss/osprey#52** still to be merged separately (no build-time dependency either way).

## Files

- `pwiz_tools/Osprey/Osprey.Tasks/Calibrator.cs`
- `pwiz_tools/Osprey/Osprey.Chromatography/RTCalibration.cs`, `CalibrationParams.cs`
- `pwiz_tools/Osprey/Osprey.Test/CalibrationTest.cs`
- Rust: `crates/osprey/src/pipeline.rs`, `crates/osprey-chromatography/src/calibration/rt.rs`,
  `crates/osprey-scoring/src/batch.rs`
- Run artifacts: `C:\temp\osprey-4401\{gate0-baseline,gate3-fixed}\` (SEA-AD tree kept
  read-only via `--work-dir`; `--output-dir` alone is NOT enough -- the spectra cache still
  lands beside the data).
