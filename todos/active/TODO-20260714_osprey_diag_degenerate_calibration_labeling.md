# TODO-osprey_diag_degenerate_calibration_labeling.md -- Model-diagnostics HTML mislabels a degenerate-but-successful calibration as "did not calibrate"

## Status
**In review (created 2026-07-14).** Raised by Brendan while reviewing the first full
82-file `--model-diagnostics` run on the SEA-AD Pilot-MTG Astral-DIA set. Pure
presentation bug in the diagnostics HTML; no calibration-correctness issue.
PR [#4421](https://github.com/ProteoWizard/pwiz/pull/4421) on branch
`Skyline/work/20260714_osprey_diag_degenerate_calibration_labeling` (pwiz-work2).
Verified by regenerating the 82-file run's HTML from the edited template: 0 red
(no `calibrated===false`), the 2 degenerate files (`…0035…051`, `…0070…092`) render
amber single-feature (`libcosine_apex` 100%). Build Debug -RunTests green (506/3).

## Problem
On the 82-file run, the CAL tab flags two files as **"did not calibrate / too few usable
anchors"** (red), and the "Per-file calibration overview" (Reproducibility) scatter panels
draw them as **red dots**:

- `Astral-SEA-AD_2-MTG-May2026_SEA-AD-0035_7045_D02_051` (Summary: 153 anchors)
- `Astral-SEA-AD_2-MTG-May2026_SEA-AD-0070_7064_G04_092` (Summary: 414 anchors)

Both files **calibrated successfully.** The label is wrong.

## Root cause (verified)
The diagnostics data already carries two INDEPENDENT booleans per file --
`CalFileRow.Calibrated` and `CalFileRow.Degenerate`
(`Osprey.FDR/ModelDiagnostics/ModelDiagnosticsData.Cal.cs:138,157,208-209`) -- but the
HTML template collapses them into one "bad" verdict and renders degenerate-but-calibrated
as failure everywhere:

```js
// Osprey.Tasks/ModelDiagnostics/model-diagnostics-template.html:1471
const calIsBad=f=>!!(f&&(f.degenerate||f.calibrated===false));
```

`Degenerate` is set by `IsDegenerateCalibrationModel` (`Osprey.Tasks/Calibrator.cs:1493`):
true when the calibration-phase **LDA** collapses to <= 1 non-zero-weight feature (or all
folds went singular / no refinement ran). It is a property of the anchor-SCORING model, NOT
the RT/MS1/MS2 fit. The `CalFileInput` that carries it is built ONLY on the successful-fit
path, which hardcodes `Calibrated = true` (`Calibrator.cs:1445-1456`); the true no-fit /
fallback paths return null earlier and never produce a CAL row.

Evidence from `D:\test\Pilot-MTG-Tissue-May2026\runs\pass2ab-82file-percolator-Bmdiag\`:
- Embedded HTML data: **all 82 files `"calibrated":true`**; exactly **2 `"degenerate":true`**
  (these two).
- Both files' `.calibration.json`: `calibration_successful:true`, RT `r_squared` ~0.998
  (0.99764 / 0.99788), residual_sd ~0.21 min, MS1 and MS2 `calibrated:true` -- statistically
  identical to healthy files (e.g. `...0001...005` r2=0.99776). Fits are as good as the rest.
- Both files' cal-LDA collapsed to a SINGLE feature -- `libcosine_apex`, coefficient 1.0
  (percent 100.0), every other feature weight 0. That is the `nonZero <= 1` degenerate branch.

So "degenerate" != "failed": the file calibrated fine using a single-feature anchor
discriminant (library cosine at apex is a strong ID signal), and the RT/mass corrections it
produced are indistinguishable from the healthy files. The "too few usable anchors" wording
is also false -- `...092` had 338 confident peptides / 414 anchors, nowhere near too few.

## The fix (presentation only, in model-diagnostics-template.html)
Split the single `calIsBad` verdict into two states and reserve the failure treatment for a
real failure:

- `calNotCalibrated(f)  = f && f.calibrated===false`   -> RED, "did not calibrate" (true failure)
- `calDegenerate(f)     = f && f.degenerate && f.calibrated!==false`  -> AMBER note,
  "calibrated with a single-feature model", NOT red, NOT "failed"

Change points (all in `Osprey.Tasks/ModelDiagnostics/model-diagnostics-template.html`):

1. **`:1471` `calIsBad`** -- replace with the two predicates above; update all call sites.
2. **Reproducibility scatter `:1676-1680`** -- red dot (`COL.decoy`) only for
   `calNotCalibrated`. Degenerate-but-calibrated files render as NORMAL points. Keep the
   existing amber `isOut` statistical-outlier highlight untouched (those are legitimate --
   e.g. the high anchor-FDP amber dots must stay). Fix the tooltip so "⚠ not calibrated" is
   shown only for true failures; degenerate -> "single-feature calibration model".
3. **Model tab `renderCalModel` `:1522-1543`** -- for `calDegenerate`, RENDER the feature
   table (it already holds `libcosine_apex` @ 100% with the rest at 0) plus a short amber
   note ("Calibration reduced to a single feature (libcosine_apex); other features carried no
   separable signal. The file calibrated successfully."), and show the composite discriminant
   distribution if present. Only `calNotCalibrated` keeps the "did not calibrate" NA block;
   correct its "too few usable anchors" wording (`:1529`).
4. **File picker labels `:1496,:1505`** -- reserve "⚠ not calibrated" / "did not calibrate"
   for `calNotCalibrated`; degenerate -> a subtler "single-feature model" tag.
5. **Summary tab `:1722-1724`** -- KEEP a signal (Brendan wants the issue visible) but make
   it honest: true failure keeps the red `neg` row + "did not calibrate"; degenerate gets an
   amber tag / marker (e.g. on the Anchors cell) rather than the red row.
6. **Legend `:476`** ("rows in red failed to calibrate") -- update to describe both states.

No change to `ModelDiagnosticsData.Cal.cs` or `Calibrator.cs` -- the data already separates
`Calibrated` and `Degenerate`. (Optional hardening: a C# test asserting the two flags are
independent so a future refactor can't re-merge them.)

## Tasks
- [ ] Add `calNotCalibrated` / `calDegenerate` predicates; replace `calIsBad` at every call site.
- [ ] Reproducibility scatter: stop drawing degenerate-but-calibrated files red; keep amber
      `isOut` outliers; fix tooltip.
- [ ] Model tab: render the single-feature table + discriminant + amber note for degenerate;
      restrict the "did not calibrate" block to `calibrated===false` and fix its wording.
- [ ] File-picker + Summary: accurate degenerate tag (amber), red reserved for true failures.
- [ ] Legend/help text updated for the two states.
- [ ] Verify by regenerating the diagnostics HTML: the two files show a `libcosine_apex`x1
      (others 0) Model page, no red dots in Reproducibility, and an amber "single-feature"
      Summary tag. Confirm a genuinely-uncalibrated file (`calibrated===false`) is still red.
      (Open question: can the HTML be re-emitted from persisted per-file diagnostics without a
      full 82-file re-run? If not, iterate by extracting the existing data blob from
      `out.model-diagnostics.html` and injecting it into the edited template.)

## Acceptance criteria (Brendan's asks)
1. Model tab shows the single-feature (`libcosine_apex` coefficient 1, other features 0)
   model -- NOT a "too few calibrators" failure message.
2. Summary still indicates the single-feature / degenerate condition, but accurately (not
   "failed to calibrate").
3. Reproducibility panels do NOT highlight these runs with red dots (amber statistical-outlier
   dots are fine and independent).
4. Truly-uncalibrated files (`calibrated===false`) remain clearly flagged red.

## References
- Run: `D:\test\Pilot-MTG-Tissue-May2026\runs\pass2ab-82file-percolator-Bmdiag\out.model-diagnostics.html`
  (+ per-file `.calibration.json`).
- Verdict logic: `model-diagnostics-template.html:1471` (`calIsBad`),
  `:1522-1543` (Model tab), `:1668-1683` (Reproducibility scatter), `:1697-1737` (Summary).
- Degenerate definition: `Osprey.Tasks/Calibrator.cs:1493` (`IsDegenerateCalibrationModel`),
  CalFileInput build `:1445-1456`.
- Data fields: `Osprey.FDR/ModelDiagnostics/ModelDiagnosticsData.Cal.cs:138,157,208-209`.
- Related: [[project_osprey_calibration_anchors_clean_sample_limited]] (anchor selection is
  clean / near-optimal -- consistent with these files' good fits despite the collapsed LDA),
  [[TODO-osprey_calibrator_selection_review]].
