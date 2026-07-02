# TODO-osprey_calibration_console_output.md -- Restore calibration + C to the default console; move the Percolator feature table behind --verbose

## Status
Backlog (brendanx67). Not started. Motivated by Mike MacCoss's feedback on the new
Osprey console output (2026-07-01), forwarding his 2026-06-26 email plus a follow-up
private-chat note.

## Motivation -- what Mike asked for
Two clear thrusts in his feedback:

1. **Put the calibration results back on the default console.** Verbatim: "We do need
   to put back into the console output the results of the calibration. For example the
   RT window prior to and after calibration. It is great seeing how the RT window gets
   way better with improved AI models. Also, the mass calibration correction and the
   window size is nice to have flagged in the output." And earlier: "The output that is
   very useful is the mass calibration and the quality of the RT calibration and how
   narrow of a RT search window is going to be used. This info is in the json files but
   it is nice to have that highlighted as it is a good sanity check. The RT calibration
   is directly related to whether the AI library is usable and also how fast the search
   is going to be. Going from 0.5 min windows to 1.5 min windows is painful speed wise."

2. **Don't emphasize the Percolator feature table.** Verbatim: "Not sure we should
   emphasize the percolator features and definitely shouldn't put a percentage on them."
   His reasoning (all valid): raw coefficients aren't comparable across features on scale
   alone; the L2-regularized SVM splits signal across correlated scores; a large
   coefficient can be a suppressor/calibrator rather than class signal; and true feature
   *importance* is a CV-stability question (Boruta / SHAP), which this table is not.

He also wants the **C regularization parameter** back: "The C used to be in the console
output as the C controls the margin. It is hard to imagine the coefficients without the
C. C is also learned during the cross validation steps ... I sweep C in log steps."

## Decision (brendanx67)
- **Do items 1 and the C restore** -- these are unambiguously more valuable and belong
  on the default console.
- **Keep the feature table, but gate it behind `--verbose`** and reframe it as a *model
  sanity check* (the mProphet-model-view analog I rely on in Skyline), not as feature
  importance. Keep **both** the raw coefficient and the signed percentage, the way
  Skyline reports them. The rationale for why the percentage is valid for a linear SVM
  is written up under "Rationale" below -- it is the good-faith justification promised to
  Mike, and is intended to survive review by his own Claude Code session.

## Current state (verified via code read, 2026-07-01)
- **Calibration summaries exist but are `LogVerbose`-only** (invisible without `-v`):
  - RT tolerance: `Osprey.Tasks/Calibrator.cs` -- initial `:180`, first-pass `:281`,
    refined `:312` (the refined value is the "after" number; initial is the "before").
    Fit stats produced by `Osprey.Chromatography/RTCalibration.cs` `RTCalibrator.Fit`
    (`:100-188`).
  - Mass calibration: `Calibrator.cs:725-730` logs MS1/MS2 mean, SD, 3*SD, count.
    Computed in `Osprey.Chromatography/MzCalibration.cs` (`CalculateMzCalibration :135`,
    `CalibratedTolerancePpm :173-182`).
- **SVM C is selected but never printed.** `Osprey.FDR/PercolatorFdr.cs`: candidate grid
  `{0.001, 0.01, 0.1, 1.0, 10.0, 100.0}` (`:114`), `GridSearchC` picks best by CV
  (`:1626-1717`), `bestC` consumed at `:1070-1071` -- but not written to console or JSON,
  and there is no dump env var for it.
- **Feature table is always-on.** `EmitFeatureContributions` (`PercolatorFdr.cs:2413-2417`,
  called `:667` direct path and `:786` streaming path) writes unconditionally via
  `OspreyOutput.Out.WriteLine`. Report body in `Osprey.FDR/FeatureContributions.cs`
  `ToReportLines` (`:293-305`); it already emits **coefficient and percent** columns plus
  an "(unexpected direction)" flag.
- **JSON gap for the RT window.** `Osprey.Chromatography/CalibrationParams.cs`:
  `MzCalibrationJson` (`:160-237`) already persists `adjusted_tolerance` (`:184`) and the
  hard-coded `window_halfwidth_multiplier = 3.0` (`:232`). But `RTCalibrationJson`
  (`:262-341`) stores only fit stats (residual SD, MAD, R^2, n) -- **the final RT search
  window width is not persisted**; it is recomputed at scoring time as
  `MAD * 1.4826 * 3.0`. So "this info is in the json files" is true for mass but not for
  the RT window width Mike specifically calls out.
- **Output seam:** `Osprey.Core/OspreyOutput.cs` -- `OspreyOutput.Out` (`:59-63`) is the
  user-facing writer (pointed at `CommandStatusWriter` by `Program.cs`); `Verbose`
  property (`:127`) + `WriteVerbose` (`:134-138`) are the existing verbose gate to reuse.

## Proposed work
1. **Calibration summary on the default console.** Add a compact, curated summary block
   (one per file, default level -- not the full per-pass verbose spew) that flags:
   - **RT:** window before vs. after calibration (initial tolerance -> refined tolerance),
     the final RT search-window half-width actually used, and a fit-quality number (MAD or
     residual SD, R^2, n points). This is the "is the AI library usable / how fast will the
     search be" sanity check.
   - **Mass:** MS1 and MS2 systematic correction (mean offset), SD, and the applied
     tolerance window (adjusted_tolerance / 3*SD), with units.
   Keep the existing detailed per-pass lines at `-v`. Promote only the summary.
2. **Restore the SVM `C`.** Print the selected C (and the log-scale sweep grid it was
   chosen from) after Stage 5 training, on the default console. If C is chosen per fold,
   report per fold or the consensus -- confirm which during implementation.
3. **Gate + reframe the feature table.** Route `EmitFeatureContributions` through the
   verbose gate (`OspreyOutput.Verbose` / `WriteVerbose`) so it appears only under
   `--verbose`. Relabel the heading away from "weight/contribution" wording that reads as
   importance -- frame it as a **model sanity check** (share of target-decoy separation).
   Keep **both** columns (coefficient + signed percent) and the unexpected-direction flag.
4. **Close the RT-window JSON gap.** Persist the final RT search-window width in
   `RTCalibrationJson` so console and JSON agree and the value Mike references is actually
   recorded (mass tolerance is already persisted).
5. **(Open design, not committed) Correlated-score diagnostics.** Mike's strongest point
   is that L2 splits signal across correlated scores, so a genuinely strong feature can
   show a small share. Design a way for a user to *see and debug* that -- candidates: a
   pairwise score-correlation view, grouping of correlated features, or per-fold
   contribution spread (a cheap CV-stability read, since we already train per fold). Prove
   the value before promoting any of it out of `--verbose`.

## Rationale -- why the percentage is a valid sanity check for a linear SVM
(Written for review, including by Mike's own Claude Code session. The deeper derivation
lives in the completed `ai/todos/completed/TODO-20260624_ospreysharp_feature_weight_contributions.md`,
section "How the math works (why it ports across training paradigms)".)

There are two different numbers, answering two different questions:

- **The raw coefficient** is *not* noise and *not* useless -- but it is not comparable
  across features on magnitude alone. Skyline reports it next to the percentage in the
  mProphet model view, and coefficients drive the Compare Peaks window (how a peak's total
  score was composed, why the top peak won). Its cross-feature comparison is confounded by
  (a) feature scale and (b) L2 splitting across correlated scores -- both real, both Mike's
  points.

- **The percentage** is the cross-feature-comparable companion. It is **not** the
  coefficient: it is a target-decoy **mean-difference decomposition** --
  `contribution_j = w_j * dmu_j / sum_k(w_k * dmu_k)`, each coefficient times that
  feature's own target-minus-decoy mean gap, normalized to sum to 100%. Two properties
  follow directly from that construction and answer two of Mike's three objections:
  - **Scale cancels.** Rescale a feature by `a`: to hold the score fixed the coefficient
    scales by `1/a` while `dmu_j` scales by `a`, so `w_j * dmu_j` is invariant. The
    volts/millivolts problem disappears. (Osprey also standardizes inputs before the SVM,
    so it is doubly moot.)
  - **A suppressor/calibrator shows small, not large.** Because each term is weighted by
    the feature's *own* target-decoy separation, a feature that earns a big coefficient
    while barely separating classes (`dmu_j ~ 0`) contributes ~0%. So the percentage is
    closer to Mike's intuition than the coefficient is, not further from it.

**Honest concessions:** the percentage does **not** undo L2's splitting of shared signal
across correlated features (item 5 targets exactly this), and it is **not** feature
importance or feature selection -- CV-stability / Boruta / SHAP are the tools for that.

**Why it applies to a linear SVM at all** (Mike's original doubt): the decomposition is a
property of the model *form* -- a bias plus a weight vector scored on target/decoy data --
not of the fitting objective. LDA and a linear SVM emit the same object; only the numeric
weights differ. So the exact math Skyline uses for mProphet's LDA carries over unchanged,
and the shares sum to 100% by linearity for any linear model.

**What it is for:** a model sanity check. If library dot-product or RT-difference comes out
with almost no share, something is likely wrong with the library or RT calibration and the
model shouldn't be trusted yet; a score weighted *opposite* to its expected direction --
especially at a large percentage -- is a flag to go look. (Observed on Mike's 21-score
model: RT-difference carried very little weight -- an unfollowed lead worth investigating,
and one that dovetails with the RT-calibration quality he wants surfaced.)

## Notes / gotchas
- **Reporting-only.** None of items 1-4 change scoring or q-values. Gate on
  `regression.ps1 -Dataset Stellar` expecting the blib **byte-identical** (as the
  feature-contribution PR #4328 did); run `-Dataset All` before merge.
- **Localizable strings.** New user-facing text must be resource strings, and any string
  captured across an in-process language switch must be a `Func<string>`, not a static --
  gate output tests with `Run-Tests -UseTestList -Language all`, not just an en build (see
  memory: "No localizable string in a static").
- **Verbose gate semantics.** Confirm `--verbose` maps to `OspreyOutput.Verbose`; the
  feature table should be the only thing that *moves* to verbose. The calibration summary
  and C move the other way (verbose -> default).
- **Summary, not spew.** Item 1 is a curated one-block summary at default level; do not
  simply flip every `LogVerbose` calibration line to default.

## References
- Emails: Mike MacCoss "Osprey" (2026-06-26, forwarded 2026-07-01) + private-chat
  follow-up (Gmail thread `19f077a98ebea839`).
- Code: `Osprey.Tasks/Calibrator.cs` (`:180/:281/:312` RT, `:725-730` mass);
  `Osprey.Chromatography/RTCalibration.cs`, `MzCalibration.cs`, `CalibrationParams.cs`
  (`RTCalibrationJson :262-341`, `MzCalibrationJson :160-237`);
  `Osprey.FDR/PercolatorFdr.cs` (`C grid :114`, `GridSearchC :1626-1717`, `bestC :1070`,
  `EmitFeatureContributions :2413`); `Osprey.FDR/FeatureContributions.cs`
  (`ToReportLines :293-305`); `Osprey.Core/OspreyOutput.cs` (`Out :59`, `Verbose :127`).
- Prior output sprints: `ai/todos/completed/TODO-20260623_ospreysharp_console_output.md`,
  `..._io_progress.md`, `..._output_progress.md`, `..._file_parallelism_arg.md`.
- Percentage math derivation + the original "ports across training paradigms" discussion:
  `ai/todos/completed/TODO-20260624_ospreysharp_feature_weight_contributions.md`.
