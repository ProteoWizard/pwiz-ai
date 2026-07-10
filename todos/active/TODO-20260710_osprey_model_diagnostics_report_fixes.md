# TODO-20260710_osprey_model_diagnostics_report_fixes.md -- --model-diagnostics report bugs, cross-run reproducibility graphs, and a global-vs-run-FDR view

## Status
**Active (2026-07-10).** Branch `Skyline/work/20260710_osprey_model_diagnostics_report_fixes`
off master `babcebdb6e`. PR **#4408** (https://github.com/ProteoWizard/pwiz/pull/4408) OPEN and
green (both Osprey Perf/Regression builds SUCCESS; unit build 477 tests; CodeQL/Core green).
Reporting-only change (off the production FDR path; golden regression unaffected). Implements the
cross-run graphs specced in the backlog sibling
[[TODO-osprey_model_diagnostics_cross_run_detection_consistency]], fixes two report bugs found on
the 2026-07-09 SEA-AD run, and is now being extended (Brendan's request) with a global-vs-run FDR
view. Context: [[project_sead_pilot_mtg_dataset]], [[project_osprey_entrapment_ratio_fdr_collapse]].

## Landed on the PR (3 commits)
1. `e10464f035` -- **Bug A** (yield chart didn't switch experiment-wide/per-run scope: `IdYieldData`
   now carries `TargetsExperiment[]`+`TargetsRun[]` over one grid + a scope selector) + **Bug B**
   (FDR tab and the yield inside it were hidden without entrapment -> moved yield + the two new
   graphs to a new always-present **Reproducibility** tab; entrapment FDP card stays in the gated
   `fdr` tab) + the **two cross-run graphs** (`CrossRunDetection`: "precursor detections by run"
   with cumulative union/intersection + at-least-half line; "precursors by number of runs detected"
   histogram, J/U shape, growing k=1 bump = FDR trouble).
2. `e300d3fd02` -- self-review fixes: exclude entrapment (p_target) from the cross-run counts (match
   the id-yield curve); half-bin hover-index offset in both bar charts; k=N histogram color tie.
3. `9e3164fda5` -- Copilot fix: gate the "passing" set on `FdrEntry.EffectiveRunQvalue(FdrLevel)`
   (configured level: precursor/peptide/both) instead of a hardcoded `RunPeptideQvalue`, in BOTH
   `BuildCrossRunDetection` and the per-file Summary loop. Threaded the `FdrLevel` enum through
   `Build`. Added `TestPassingSetHonorsFdrLevel`. (Note: a red "TeamCity failure" flagged 2026-07-10
   was build 4085939, an auto-triggered duplicate that Matthew Chambers manually canceled -- not a
   real failure; the same commit passed on 4085910. Re-triggered 4086145 on the fixed head.)

## Verification of landed work
- Pre-commit gate green: Debug build, 480 tests pass (incl. new tests), zero inspection warnings in
  touched files (the 11 reported are pre-existing SystemMemory.cs #4379 / PerFileScoringTask.cs #4381).
- Headless-Chrome screenshots on no-entrapment (decoy), r=0.1, r=1.0-recheck, 20-run r=0.5 -- Bug A/B
  fixed, both graphs render + scale, no JS error. Runs under `D:\test\Pilot-MTG-Tissue-May2026\runs\`.

## Scientific context (the reason for the extension)
The two new plots exposed a real FDR effect on the SEA-AD data, and it is a KNOWN, named problem:
**per-run FDR does not bound the dataset-wide (experiment-wide / "global") FDR, and the gap grows
with run count.** False positives are ~random per run -> they land at k=1 and the cumulative union
climbs ~linearly with N; true positives are shared biology -> they land at k=N and the union
saturates. So each added run pours ~1%-of-its-detections of fresh FPs into the union. Confirmed
empirically: the per-run id-yield curve keeps climbing ~linearly (no plateau, ~135K @10% q) while
the experiment-wide curve decelerates/saturates (~78K) -- the ~57K gap is the union FP inflation.
At the full **82-run** dataset this will be materially worse.

**Citations (add to the report/docs):**
- Collins B.C. et al., *"Multi-laboratory assessment of reproducibility, qualitative and
  quantitative performance of SWATH-mass spectrometry,"* Nat Commun 8:291 (2017).
  doi:10.1038/s41467-017-00249-5 -- the multi-lab benchmark Brendan cited.
- Rosenberger G. et al., *"Statistical control of peptide and protein error rates in large-scale
  targeted DIA analyses,"* Nat Methods 14:921 (2017). doi:10.1038/nmeth.4398 -- the companion that
  formalized run-specific vs global FDR (the cohort matrix requires the peptide to clear the GLOBAL
  q for identity AND the RUN q to trust it in a given run -> our `max(run q, exp q)` gate).

**Ratio sweep already done (10-file SEA-AD):** collapse is entrapment:target RATIO-driven, a sharp
cliff at exactly r=1.0 (min q / %<1%): r0.1 0.0045/59.6%, r0.5 0.00048/63.0%, r0.75 0.004/60.2%,
r0.9 0.0067/38.2% (healthy but degrading), r1.0 0.025/0% COLLAPSE (deterministic). 20-run r=0.5 is
milder than 10-run (43.6% vs 63%) -> the experiment-wide amplification scales with N too. So the
experiment-wide q is itself known to be anti-conservative at the edge -- see the calibration caveat
below.

## NEW PLAN -- extend the Reproducibility tab (still PR #4408)

### Design agreed with Brendan
- **Tab-level experiment-wide / per-run toggle** driving ALL THREE plots (yield + detections-by-run
  + histogram), not just the yield card. Promote the yield's scope selector to the tab.
- **experiment-wide view = `max(run q, experiment q) <= run FDR`** per (precursor, run), i.e. locally
  AND globally credible. NOT pure experiment q (that makes per-run membership constant and flattens
  the reproducibility axis). Under `max`: reproducible reals keep run-q (pooled exp-q is tiny);
  single-run FPs have small run-q but large exp-q -> drop entirely, so the union saturates and the
  k=1 bump collapses vs the per-run view. That contrast IS the demonstration of the Collins/Rosenberger
  effect, live in one toggle.
  - Honesty footnote for the plot: exp-q is computed on the FULL dataset, so a cumulative-union-over-
    runs-1..i curve under exp-q gating uses full-dataset global control at each partial i -- a
    "given global control, how does the credible set accumulate" view, not a strict streaming FDR.
- **The k=1 exp-q-survivor set is the key diagnostic.** Precursors detected in exactly one run at
  run-q < FDR that ALSO pass exp-q < FDR. Two interpretations, and the reproducibility split alone
  CANNOT distinguish them (Brendan's caveat -- do not call survivors "biology"):
    (a) exp-q well-calibrated -> real rare / donor-specific precursors (legit biology), or
    (b) exp-q anti-conservative -> we are accepting too many 1-hit-wonders; still FPs, a calibration
        failure one level up (and we KNOW exp-q can be anti-conservative from the sweep).
- **Entrapment is the adjudicator** (this is what makes the entrapment overlay load-bearing, not
  decorative). Within the exp-q-surviving k=1 (and low-k) set, measure the entrapment-equivalent FDP:
  entrapment fraction ~ nominal (~1%) -> exp-q calibrated, survivors are biology; entrapment fraction
  >> nominal -> exp-q accepting too many 1-hit-wonders (miscalibration). Two separable FDR questions
  the tab should make visible: (1) run-vs-global gap [the toggle]; (2) is global itself calibrated
  [the entrapment measurement].

### Phases
- **Phase A (in progress): the tab-level toggle + `max` semantics.** Data: `CrossRunView` (the 7
  reproducibility arrays under one gate) held twice on `CrossRunDetection` -- `PerRun` (gate: run q)
  and `Experiment` (gate: `max(run q, exp q)`). Both q's already on every `FdrEntry`; no new plumbing.
  Template: one tab-level toggle re-renders the yield chart and both cross-run plots together. Tests:
  extend `TestCrossRunDetection` to assert the `Experiment` view is a subset (an entry with small run
  q but large exp q is in `PerRun` but not `Experiment`). Regenerate the 20-run and confirm the k=1
  bump collapses / union flattens under experiment-wide.
- **Phase B: entrapment adjudication overlay.** Add the entrapment (p_target) precursors' own
  run-count distribution (currently excluded) as a second histogram series, and report the
  entrapment-measured FDP of the exp-q-surviving k=1/low-k set. This turns the visibility into an
  adjudicated biology-vs-miscalibration number. (Only shown when a manifest is present.)
- **Phase C (before/with the 82-run): "union FDP vs number of runs" curve.** Walk N = 1..82; at each
  N plot the entrapment-measured true FDP of the accumulated union (run-q vs exp-q gated). The direct
  empirical version of the Collins/Rosenberger concern -- answers "how bad at 82 runs" quantitatively.
  Fast to prototype on the existing 20-run first (compute from the per-file passing sets; no rerun).

## Implementation status (WIP -- uncommitted in the working tree, does NOT yet build)
`ModelDiagnosticsData.cs`: `CrossRunView` class added and `CrossRunDetection` restructured to
`RunNames` + `PerRun` + `Experiment`. STILL TO DO for Phase A: rewrite `BuildCrossRunDetection` to
compute both views (run-q set and max(run-q,exp-q) set) via a shared view-builder; the template
tab-level toggle + wiring the two cross-run render functions to a `view`; update `TestCrossRunDetection`
(now `cr.PerRun.*` / add `cr.Experiment.*` subset assertions). Either complete per the plan above or
`git checkout -- pwiz_tools/Osprey/...` to revert the WIP and redo cleanly. Gate: Debug build +
tests + inspection; regenerate the 20-run via the hardlink-reprocess trick (copy scores.parquet +
.PerFileScoring.osprey.task + calibration into a fresh dir; no deletions).

## Files
- `pwiz_tools/Osprey/Osprey.FDR/ModelDiagnostics/ModelDiagnosticsData.cs`
- `pwiz_tools/Osprey/Osprey.Tasks/ModelDiagnostics/model-diagnostics-template.html`
- `pwiz_tools/Osprey/Osprey.Test/ModelDiagnosticsDataTest.cs`
- (Phase C tooling may add a small analysis script under `ai/.tmp/`.)

## Gotchas
- Data model round-trips through a Newtonsoft JSON sidecar (camelCase, NaN/Infinity literals)
  FirstJoin->MergeNode; new public props survive automatically. JS reads camelCase (`crossRun.perRun`,
  `crossRun.experiment`, `.runCountHistogram`, ...).
- CRLF, no async/await, resource strings for user-facing text (report labels live in the template);
  helpers after public methods. Report changes must NOT alter the golden regression output.
