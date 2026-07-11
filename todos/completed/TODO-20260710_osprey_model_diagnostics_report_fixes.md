# TODO-20260710_osprey_model_diagnostics_report_fixes.md -- --model-diagnostics report bugs, cross-run reproducibility graphs, and a global-vs-run-FDR view

## Status
**Completed (2026-07-11).** Branch `Skyline/work/20260710_osprey_model_diagnostics_report_fixes`
off master `babcebdb6e`. PR [#4408](https://github.com/ProteoWizard/pwiz/pull/4408) (merged 2026-07-11
as squash commit `9128e9635e`). Merged green: Osprey Windows .NET unit build 501 tests, CodeQL/Core
green; Perf/Regression passed on earlier heads and was not re-run for the small final changes.
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
- **Phase A (DONE -- commit `c7c1f9b413`, pushed): the tab-level toggle + `max` semantics.** Data:
  `CrossRunView` (the 7 reproducibility arrays under one gate) held twice on `CrossRunDetection` --
  `PerRun` (gate: run q) and `Experiment` (gate: `max(run q, exp q)`), via a shared
  `ComputeCrossRunView` helper. Template: one tab-level `reproScopeSel` toggle (unified IIFE)
  re-renders the yield chart and both cross-run plots together; new "FDR scope" intro card with the
  Collins/Rosenberger citations. Tests: `TestCrossRunDetection` now asserts both views + the
  experiment-wide subset gate (`EntryRunExp` helper; `Entry` now sets `ExperimentPeptideQvalue`).
  480 tests green. VERIFIED on the regenerated 20-run r=0.5 (healthy): flipping to experiment-wide
  collapses k=1 from 10,859 (17%) -> 322 (1%), shrinks the union 63,747 -> 36,149, leaves the
  intersection ~unchanged (13,593 -> 13,573), and turns the histogram into a clean monotone ramp to
  the k=N peak -- exactly the global-FDR effect. Report:
  `D:\test\Pilot-MTG-Tissue-May2026\runs\verify-toggle-r0.5\seaad.model-diagnostics.html`.
- **Phase B (DONE -- implemented + verified, NOT yet committed): entrapment adjudication overlay.**
  Added the entrapment (p_target) precursors' own run-count distribution (previously excluded) as a
  second series on the "precursors by number of runs detected" histogram, plus a per-k
  entrapment-measured FDP (FDRBench combined estimator `(1 + 1/r) * n_p / (n_t + n_p)`). Data:
  `CrossRunView` gained `EntrapmentRunCountHistogram` + `EntrapmentFdpByRunCount` (both null on a
  plain target+decoy run); `BuildCrossRunDetection` now routes p_target to parallel entrapment sets
  under the SAME two gates and threads `entrapmentRatio` through; extracted a shared
  `TallyRunCountHistogram` helper. Template: amber entrapment overlay line + legend on the run-count
  chart (ymax includes the overlay so a dominant entrapment k is shown, not clipped), hover shows
  n_p + FDP per k, and the note carries the **adjudication verdict** -- k=1 FDP ~nominal => real rare
  biology; >> nominal => exp-q admitting excess 1-hit-wonders. Tests: `TestCrossRunDetection` asserts
  the entrapment histogram, the combined-FDP values, r-scaling (r=0.1 -> 11.0), and null-when-no-manifest.
  Also qualified three pre-existing invalid `<see cref>` (CrossRunView members referenced unqualified
  from CrossRunDetection). 480 tests green, inspection clean on touched files. VERIFIED via a synthetic
  4-run render headless-screenshotted at both scopes (`scratchpad/shot-phaseb.py`, green "JS OK"
  banner both scopes): per-run shows the k=1 bump (real+entrapment) at 550% FDP; experiment-wide drops
  the real singletons, leaving entrapment-only k=1 at 1100% -- the toggle + adjudication working together.
- **Phase C (DONE -- committed `cd37122c84`, pushed): "union FDP vs number of runs" curve.**
  `CrossRunView` gained `CumUnionEntrapment` + `UnionFdp` (null without entrapment): `ComputeCrossRunView`
  accumulates the entrapment union alongside the real-target `CumUnion` and reports the FDRBench combined
  FDP of the accumulated union at each prefix i = 1..N. New **scope-independent** card plots BOTH scopes
  at once (per-run red vs experiment-wide indigo; the gap is the point, so it ignores the tab toggle),
  nominal-FDR dashed line, hover per i. Tests extended (union counts, per-prefix FDP, ratio scaling,
  null-without-manifest). VERIFIED on a from-scratch regeneration of the real 20-run r0.5b data
  (`D:\test\Pilot-MTG-Tissue-May2026\runs\verify-phaseb3-r0.5\seaad.model-diagnostics.html`): per-run
  union FDP climbs 0.9% (1 run) -> 2.0% (5) -> 3.1% (10) -> **4.4% (20)**, crossing above the 1% nominal
  and accreting 923 entrapment into the union; experiment-wide stays **under 1%** (0.2% -> 0.8%, only 99
  entrapment). The textbook run-vs-global FDR gap, growing with N -- extrapolates to materially worse at 82.

## Current status (2026-07-10, session 2)
Phases A + the two report bugs + the two graphs + the self-review and Copilot fixes are LANDED on
PR #4408 (4 commits: `e10464f035`, `e300d3fd02`, `9e3164fda5`, `c7c1f9b413`), pushed, verified on
real SEA-AD data. **Phase B is now COMMITTED locally (commit `d27c1f6556`) but NOT yet pushed.**
480 tests green, inspection clean on touched files, and verified on a **from-scratch regeneration**
of the real 20-run r0.5b data (not just the re-skin): the FDP curve peaks at k=1 and decays to 0 at
the k=20 peak; per-run k=1 = 10,859 real / 713 entrapment / 18.9% FDP, experiment-wide k=1 = 322 /
47 / 39.0% FDP (the global gate cuts real singletons harder than the false ones, so surviving
low-k FDP roughly doubles -- exp-q anti-conservative at its own tail). Report:
`D:\test\Pilot-MTG-Tissue-May2026\runs\verify-phaseb2-r0.5\seaad.model-diagnostics.html` (regen via
the full hardlink+cached-outputs recipe, ~8 min). **Remaining = push Phase B (awaiting Brendan's
go-ahead), then Phase C** (union-FDP-vs-N curve, specced above). Nothing is blocked.

Phase B UI iteration (all in the committed template): entrapment plotted as a per-k **FDP curve on a
second right axis** (not raw counts, which are dwarfed by the real bars), the axis **shared across
both scopes** (max of both) so the toggle visibly moves the curve, a nominal-FDR dashed reference,
and a per-k count/FDP tooltip. Screenshot harness: `scratchpad/shot-real.py` + `reskin.py` (re-skins
a real report's JSON with the current template for fast headless preview without a rerun; NOTE the
re-skin cannot preview NEW data-model fields -- Phase C needed a real regen because `unionFdp` wasn't
in the old JSON).

## ALL THREE PHASES LANDED (2026-07-11)
Phases A + B + C are committed and pushed to PR #4408 (`c7c1f9b413` toggle, `d27c1f6556` entrapment-FDP
adjudication overlay, `cd37122c84` union-FDP-vs-N), plus the master merge someone pushed
(`2a9267810a`) reconciled via merge `e1208ae3b5`. Merged state: **501 tests, 498 pass / 3 skipped**,
inspection clean on touched files. The Reproducibility tab now tells the full story: reproducibility
(bars) -> per-k entrapment adjudication (FDP curve) -> cumulative run-vs-global gap (union FDP).
**Self-review DONE** (`a58d69c355`, pushed): fresh-context agent pass found no CRITICAL/HIGH; fixed a
latent `hist[-1]` crash in `ComputeCrossRunView` for the degenerate zero-input-files case
(`Math.Max(half, 1)`), and added a 3-run test where entrapment run-q/exp-q diverge (covers the two
scopes producing different entrapment histograms + union FDP, and union-FDP accretion past N=2).
Dismissed by design: the yield curve uses pure precursor-q per scope while the run-counting plots use
run-q bars + `max(run q, exp q)` for the experiment view -- intentional and correct (pure exp-q would
make the run-counting bars degenerate/flat; the run plots are inherently run-resolved, and max(run,exp)
is what produces the Collins union-saturation). Left honest: combined FDP can read >100% on an
all-entrapment k-slice (doesn't occur on real calibrated data). Two more master merges were reconciled
into the branch along the way (`d851d1282e` #4406 etc.); merged state 504 tests, 501 pass / 3 skipped.

**Remaining:** run the Astral Perf/Regression gate before human review (ASK Brendan first --
[[feedback_ask_before_teamcity_triggers]]); optional Copilot review (billed). The 82-run union-FDP is
the natural real-data follow-up when that dataset is processed.

**Do NOT trigger the TeamCity Perf/Regression gate during this sprint** -- Brendan gates the shared
agents manually and kills premature runs; ask before triggering (see memory
[[feedback_ask_before_teamcity_triggers]]). The red Perf/Regression on the PR is infrastructure
(build #141 `9e3164fd` died in 11s with `pwsh not found` / exit 9009 on a spot agent), not a code
failure; the two builds that ran on MacCoss TeamCity Agent 1 passed.

**Next session handoff**: For detailed startup protocol (skills to load, build/verify commands, the
hardlink-reprocess recipe, and the Phase B starting point), read
`ai/.tmp/handoff-20260710_osprey_model_diagnostics_report_fixes.md` before starting work.

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

## Progress Log

### 2026-07-11 - Merged
PR #4408 merged as squash commit `9128e9635e`. Shipped all planned scope: the two report-bug fixes
(yield-scope switch, no-entrapment Reproducibility tab), the two cross-run graphs, and Phases A/B/C --
the per-run vs experiment-wide FDR toggle (`max(run q, exp q)`), the per-k entrapment-FDP adjudication
curve on a shared right axis, and the "union FDP vs number of runs" curve (run-vs-global gap). All
verified on from-scratch regenerations of the real 20-run r0.5b SEA-AD data (per-run union FDP climbs
0.9%->4.4% over 20 runs while experiment-wide stays <1%). Fresh-context self-review found no
CRITICAL/HIGH; its fixes (an N=0 `hist[-1]` guard + scope-divergence/accretion tests) landed in
`a58d69c355`. Three master merges were reconciled into the branch during the work. Merged green on the
unit build (501 tests); Perf/Regression was not re-run for the small final changes (Brendan's call, it
had passed on earlier heads). Nothing deferred; no follow-up issues filed. The 82-run union-FDP is the
natural real-data follow-up when that dataset is processed.
