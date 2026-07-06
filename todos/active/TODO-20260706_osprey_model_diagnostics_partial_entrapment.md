# TODO: Osprey --model-diagnostics — support non-100% (partial) entrapment

## Branch Information
- **Branch**: `Skyline/work/20260706_osprey_model_diagnostics_partial_entrapment`
- **Base**: `master` (`174e3ddd87`, the #4377 model-diagnostics merge)
- **Created**: 2026-07-06
- **Status**: Active — in progress
- **Worktree**: `C:\proj\pwiz`

**Priority**: High-value — unlocks the "routine ~10% entrapment overlay for FDR visibility"
  use case; the 100% (1:1) doubling is too costly to add to ordinary experiments.
**Requested by**: Brendan
**Scope**:
  - `pwiz_tools\Osprey\Osprey.FDR\ModelDiagnostics\ModelDiagnosticsData.cs` — the paired
    estimator in `BuildFdpView` (~line 901) + estimator-validity labeling.
  - `Osprey.Tasks\ModelDiagnostics\ModelDiagnosticsReport.cs` — ratio already computed
    dynamically at line 295 (`entrapmentRatio = (double)nPTarget / nTarget`); no change needed
    there beyond surfacing it.
  - `Osprey.Tasks\ModelDiagnostics\model-diagnostics-template.html` — show the computed `r` and
    which estimators are valid at that `r`.
  - `Osprey.Test\...ModelDiagnostics...` — tests at r<1.
**Related**: extends PR [#4377](https://github.com/ProteoWizard/pwiz/pull/4377); sibling to
  [[TODO-osprey_model_diagnostics_null_alignment_decoy_qc]] and
  [[TODO-osprey_model_diagnostics_training_pool_distributions]]. Depends conceptually on a
  partial-entrapment *generator* (see "Generation" below). Ties to
  [[project_osprey_natural_entrapment]] (the ratio-sweep that motivated this).

## Why this exists — the 10% overlay vision
The 100% (1:1) entrapment library **doubles** the searched precursors. We measured the cost
directly (Stellar): at r=1 the entrapment perturbs the target search and suppresses IDs
(N_T 30,772 → 27,931 at 1% q) and adds noise that reduces what's measurable at 1% FDR. That's
too high a price to pay to add FDR-accuracy visibility to a normal experiment.

But the capture-recapture / combined estimator is **ratio-invariant** — we proved it holds
at ~1.1% across a 10× range (r = 0.10 → 1.00), and at r=0.1 the search is nearly unperturbed
(N_T recovers to ~30,650). So a **small, regular ~10% entrapment overlay** would give honest
FDR visibility at low cost — tempting to fold into many experiments by default. For that,
`--model-diagnostics` must be correct at r < 1.

## Findings — runtime validation (2026-07-06, Stellar 10% overlay)
Ran the merged `--model-diagnostics` on a real r=0.1 library (`make_natural_entrapment.py
--method relaxed --ratio 0.1`) with master-HEAD Osprey. Report at
`D:\test\carafe-repro\stellar\osprey_project\osprey.model-diagnostics.html`:

| Pass-2 experiment view | report | our independent (r=0.10) |
|---|---|---|
| computed `r` | **0.099** ✅ (dynamic, correct) | 0.10 |
| combined | **1.09%** ✅ | 1.15% |
| lower_bound | 0.99% ✅ | — |
| paired | **0.18%** ❌ nonsensical | (paired is a 1-fold method) |

- **Runs end-to-end, no crash**; ratio computed from library counts; Met-clip artifact drop works.
- **combined + lower_bound already correct** at r<1 (they carry the `r` term:
  `combined=(1+1/r)·nE/(nT+nE)`, `lower=nE/(r·(nT+nE))`).
- **paired is the one gap**: `paired=(nE+vt)/(nT+nE)` has **no `r` term** — it's FDRBench's
  1-fold formula and collapses for partial entrapment (0.18% at r=0.1). Wen et al. derive the
  paired estimator only for r=1 (every target has exactly one twin).

## Work
1. **Paired estimator at r≠1 — DECIDED: (a) gate + relabel** (Brendan, 2026-07-06). When
   `|r−1| > tol` (small tolerance, e.g. 0.05), **suppress the paired curve** and mark it
   "1-fold only (paired requires r≈1)"; keep combined (the ratio-invariant workhorse) +
   lower_bound. Honest, mirrors FDRBench's own 1-fold limitation. Do NOT invent an unvalidated
   r-generalized paired formula. (Subset-paired over the twinned subset is a possible future
   enhancement, explicitly NOT part of this task.)
2. **Surface `r`** prominently in the FDR-calibration tab + a note on which estimators are
   valid at that `r` (combined/lower always; paired only near 1-fold or via subset-paired).
3. **Competition tab / win-fraction** under partial: the entrapment win-fraction is over the
   small paired subset — confirm it renders sensibly and flag low power (small N).
4. **Tests**: combined correct at r=0.1 vs the oracle; paired gated/subset-correct at r≠1;
   partial classification counts (targets without a twin); no-entrapment still degrades.
5. **Validate** on the existing ratio-sweep runs (r=0.5/0.25/0.1) — data already on disk
   (`D:\test\carafe-repro\stellar\osprey_project\FDRBench\FDRBench-Input.arab_relaxed_r*.tsv`).

## Progress
### 2026-07-06 — paired estimator gated (commit `31658cd525`, branch)
Done: **1** (paired gate+relabel) and **4** (tests).
- `ModelDiagnosticsData.cs`: added `FdpView.PairedSuppressedPartial` + const
  `PairedRatioTolerance = 0.05`; `BuildFdpView` now sets `Paired = null` and the flag
  when `|r−1| > 0.05` (applies to both passes, both scopes). Combined/lower untouched.
- `model-diagnostics-template.html`: FDR-tab note explains the omission when
  `pairedSuppressedPartial`; legend filters out the dead paired toggle.
- Tests: `TestPairedSuppressedForPartialEntrapment` (paired null + flagged, combined/
  lower r-aware at r=0.1); `TestPairedEstimator` asserts not-suppressed at r=1.
- Gate GREEN: `Build-Osprey.ps1 -Configuration Debug -RunTests -RunInspection` →
  453 passed, 0 failed, inspection clean.
- **End-to-end verified** on the 10% Stellar run (`D:\test\carafe-repro\stellar`):
  all 4 views now `paired:null` + `pairedSuppressedPartial:true` + note shown; combined
  intact and r-aware (r=0.099). Pass-1 combined byte-identical pre/post change
  (2.27% exp, 1.99% per-run) → my change has zero effect on the FDP math. (Pass-2
  combined drifts run-to-run, 1.09%→1.82%, in the `--protein-fdr` recalibration path —
  pre-existing, [[project_osprey_pass2_recalibration_inflates_fdr]], not this change.)

Remaining: **2** (surface r) is largely covered by the note (r already shown in the
tab); **3** (competition/win-fraction low-power note under partial — renders fine, no
crash; optional polish); **5** (spot-check r=0.5/0.25 too). Then push + self-review + PR.

## Design decisions
- **Paired at r<1**: DECIDED — (a) gate + relabel (Brendan, 2026-07-06). Subset-paired deferred.
- **Generation**: partial entrapment is currently produced by the prototype
  `ai/.tmp/make_natural_entrapment.py --ratio`. Productionizing the *generator* is a separate
  question — a Carafe `-entrapment_ratio` / `-entrapment_source foreign` mode (a PR on
  maccoss/Carafe, since `EntrapmentFastaGear` is Mike's), OR an Osprey-side overlay. This TODO
  is the *consumer* side (model-diagnostics correctness); note the cross-tool dependency.
- Whether a ~10% overlay should eventually be a **default-on** diagnostic for routine runs.

## Repro / references
- Generator + estimator: `ai/.tmp/make_natural_entrapment.py`, `ai/.tmp/mr_estimate.py`.
- Design + sweep results: `ai/.tmp/natural-entrapment-design.md`.
- Ratio computed: `ModelDiagnosticsReport.cs:295`; estimators: `ModelDiagnosticsData.cs:~893-901`.
- Feature: PR #4377 (`174e3ddd87`); completed TODO
  `ai/todos/completed/TODO-20260705_osprey_model_diagnostics.md`.
