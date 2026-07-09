# Osprey C# drops Rust's calibration retry ladder and the >=50-point acceptance floor

**Status:** open, not started
**Issue:** https://github.com/ProteoWizard/pwiz/issues/4401
**Found:** 2026-07-09, while reading the 82-file SEA-AD Astral run log for unrelated memory work.

## Symptom

Three of 82 SEA-AD files fell back to **uncalibrated** m/z and RT tolerances:

```
[COUNT] Calibration pass 1 LDA winners [...0071_7043_G05_093]: 241 target wins, 2 decoy wins at 1% FDR
[COUNT] Calibration pass 1 high-quality (S/N>=5) [...0071_7043_G05_093]: 193
[WARN] Insufficient calibration points in pass 1 (193 < 200).
[WARN] Calibration pass 1 failed. Using fallback tolerance.
   RT: calibration failed - using fallback RT tolerance
```

Affected: `SEA-AD-0071_7043_G05_093` (193 pts), `SEA-AD-0073_7181_G07_095` (178),
`SEA-AD-pool-07_G10_098` (141). Each scored ~3.1 M entries normally (162 k MS2 + 974 MS1,
167 windows) -- nothing crashed. They simply ran the whole search with **fallback tolerances**,
which widens the candidate set and costs identifications. ~3.7 % of the cohort, silently degraded.

A healthy file has ~823 LDA target wins; these have 241.

## Root cause: the port stopped after attempt 1

**Rust** (`crates/osprey/src/pipeline.rs:686-760, 982-1032`):

1. `max_attempts` derived from `calibration_sample_size` / `calibration_retry_factor` (`:693`).
2. `for attempt in 1..=max_attempts` (`:734`), sampling with seed `42 + attempt` (`:736`).
3. If `num_confident_peptides < min_calibration_points` **and** attempts remain, grow the sample by
   `retry_factor` and retry; the final attempt uses **ALL** library targets (`:988-990`).
4. On the final attempt, if `num_confident_peptides >= ABSOLUTE_MIN_CALIBRATION_POINTS` (50),
   **proceed with LOESS anyway** (`:1012`), with
   `effective_min_points = min(num_confident_peptides, min_calibration_points)` (`:1032`).
5. Only `< 50` is a hard error (`:1024`).

**C#** (`pwiz_tools/Osprey/Osprey.Tasks/Calibrator.cs`):

- `SampleLibraryForCalibration(library, config.RtCalibration.CalibrationSampleSize, 43UL, ...)`
  at `:197` -- **called once**, seed hardcoded `43UL` (= Rust's `42 + attempt` for attempt 1).
  The comment at `:193-194` even says "on the first calibration attempt". There is no loop.
- `RTCalibrationConfig.CalibrationRetryFactor` (`Osprey.Core/RTCalibrationConfig.cs:56`) is
  **never read by any calibration code**. It exists, it is hashed into `SearchIdentity`
  (`SearchIdentity.cs:119`), and `CoreTypesTest.cs:595` asserts its default. Dead config.
- `ABSOLUTE_MIN_CALIBRATION_POINTS = 50` (`:60`) is used **only** for the pass-2 refinement
  (`:317`, `:360`). It is never the pass-1 acceptance floor.
- Pass 1 passes `MinCalibrationPoints` (200) as `minLoessPoints` (`:259`). Below it,
  `RunCalibrationScoringPass` returns `null` (`:476-486`) and the caller falls back to
  `MzCalibrationResult.Uncalibrated()` (`:261-266`).

**Consequence:** at 193 / 178 / 141 points -- all far above 50 -- **Rust calibrates and C# does not.**

## Why no gate caught it

Stellar and Astral regression files are clean; their calibration never dips below 200, so the
branch is never executed. `regression.ps1` and `Compare-EndToEnd-Crossimpl` both pass. Byte-parity
gates only prove agreement on paths the test data traverses -- this is a coverage hole, not a gate
failure. **Any fix needs a regression file (or a synthetic library subsample) that lands in the
50-200 band**, or the same hole swallows the fix.

## Fix (restore parity first -- do NOT design a new algorithm yet)

1. Implement the retry ladder in `Calibrator.cs`: loop `attempt = 1..max_attempts`, seed
   `42 + attempt`, grow `currentSampleSize *= CalibrationRetryFactor`, final attempt uses all
   targets. Mirror `pipeline.rs:686-760` exactly, including `max_attempts` derivation.
2. Accept `>= ABSOLUTE_MIN_CALIBRATION_POINTS` on the final attempt and fit LOESS with
   `effectiveMinPoints = Math.Min(nConfident, MinCalibrationPoints)`.
3. Hard-fail only below 50, matching Rust's `OspreyError::ConfigError`. (Decide: C# currently
   degrades to fallback tolerances rather than erroring. Rust errors. Which is right for a
   82-file batch where one bad file should not kill the run? **This is a real design question --
   Rust's behavior may itself be wrong for batch use.**)
4. Re-run the three SEA-AD files and check they now calibrate.

## Open question (Mike, 2026-07-09): bootstrap the window

> "If we have <200 points after the second attempt but ~100 points, should we do a calibration
> step with that and then use those windows to repeat the calibration again? We start with 25% of
> the entire RT range; for noisy files that wide RT window might be the problem. I'm a bit worried
> about the calibration making an error and making it worse."

The worry is well-founded and worth stating precisely: **Rust's ladder increases the *evidence*
(sample more library entries) while Mike's bootstrap narrows the *window* (re-search with a fit
derived from weak data).** Narrowing a window using a fit estimated from 100 noisy points is
self-confirming: points outside the (possibly wrong) window can no longer be recovered, so a bad
pass-1 fit is entrenched rather than corrected. Rust's approach has no such failure mode.

Note also that the existing pass-2 refinement already does a guarded version of this: it only
re-scores when `pass1Tolerance < initialTolerance * 0.5` (`Calibrator.cs:306`) -- i.e. only when
pass 1 was confident enough to tighten by 2x -- and it requires only 50 points on the refit.

**Sequence:** restore the ladder (step 1-3), then measure. The retry samples *more library entries*,
which raises the confident-peptide count -- it is entirely possible these three files clear 200 on
attempt 2 or 3 and the graduated-fit question becomes moot. Do not build the linear-fit /
restrictive-LOESS tier until we know the ladder does not already solve it.

If a graduated tier is still needed after measurement, the proposal on the table is:
- 100-200 points: LOESS with a larger bandwidth (smoother, fewer effective dof)
- 50-100 points: linear fit only
- <50: fallback tolerances (or error)

## Validation

- **Correctness oracle, not parity:** this changes which files get calibrated, so it moves the
  discovery set. `regression.ps1` goldens will shift for any file in the 50-200 band. The arbiter is
  **FDRBench entrapment** (see `ai/docs/osprey-development-guide.md`), not the golden.
- **Cross-impl:** restoring the ladder should *converge* C# to Rust, so
  `Compare-EndToEnd-Crossimpl` on a 50-200-band file becomes the real test. Today both agree only
  because the band is never hit.
- **Caution -- `SearchIdentity`:** `min_calibration_points`, `calibration_sample_size`, and
  `calibration_retry_factor` are all hashed (`SearchIdentity.cs:117-119`). Changing defaults
  invalidates every cache. Changing *behavior* at a fixed config does **not** bump the identity --
  so a stale `.calibration.json` from a pre-fix run will be silently reused. Wipe work-dirs when
  testing, or bump the identity deliberately.

## Files

- `pwiz_tools/Osprey/Osprey.Tasks/Calibrator.cs` (`:58-60`, `:193-197`, `:250-266`, `:306`, `:317`,
  `:360`, `:476-486`)
- `pwiz_tools/Osprey/Osprey.Core/RTCalibrationConfig.cs` (`:41` MinCalibrationPoints=200,
  `:53` CalibrationSampleSize=100000, `:56` CalibrationRetryFactor=2.0)
- `pwiz_tools/Osprey/Osprey.Core/SearchIdentity.cs` (`:117-119`)
- Rust reference: `crates/osprey/src/pipeline.rs:686-760`, `:982-1032`;
  `crates/osprey-core/src/config.rs:735-757`
- Evidence log: `ai/.tmp/osprey-82-prior/run.log` (grep `Insufficient calibration`)
