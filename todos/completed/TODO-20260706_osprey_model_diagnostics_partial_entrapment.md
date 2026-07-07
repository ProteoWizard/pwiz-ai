# TODO: Osprey --model-diagnostics — support non-100% (partial) entrapment

## Branch Information
- **Branch**: `Skyline/work/20260706_osprey_model_diagnostics_partial_entrapment`
- **Base**: `master` (`174e3ddd87`, the #4377 model-diagnostics merge)
- **Created**: 2026-07-06
- **Status**: Completed
- **PR**: [#4380](https://github.com/ProteoWizard/pwiz/pull/4380) (merged 2026-07-07)
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

## Progress 2026-07-06 (later) — PR #4380 opened, reviewed; MS1-decoy research spun up
- **PR [#4380](https://github.com/ProteoWizard/pwiz/pull/4380)** opened (base master),
  6 commits: paired gate + tests; `docs/fractional-entrapment.md` + report link;
  doc-table clean baseline; Wen author list; lower-bound formula fix; Copilot fixes.
  Justification doc anchored on **Fitzgibbon, Li & McIntosh 2008** (ratio-corrected
  classic-FIR = Wen 2025 combined estimator, with the same 1/2·1/4·1/10 experiment).
  Report links the doc via a GitHub blob URL (was githack) when r≠1.
- **Self-review**: clean (fixed the doc lower-bound formula). **Copilot**: 3 comments
  addressed + threads resolved (lower-bound already fixed; githack→blob; XML-doc tolerance).
- Local Debug gate green (453 pass). `SystemMemory.cs` inspection = 9 PRE-EXISTING P/Invoke
  false-positives (untouched file, on master since #4335) — NOT this PR; separate ticket.
- **NEXT for the PR**: watch CI (`get_pr_checks 4380`); optional TeamCity Perf/Regression
  on `pull/4380` (near-formality, off production path); merge + `/pw-complete`.

**New research thread (Brendan's MS1-collision insight, CONFIRMED)** — the Arabidopsis
generator matches on neutral mass ⇒ entrapments/decoys isobaric to targets ⇒ share
precursor m/z ⇒ borrow the real target's MS1 envelope. Measured: MS1 features 0% on
Stellar AND **~0% on Astral HRAM** with isobaric reverse decoys ⇒ **isobaric decoys
suppress MS1 power even where HRAM MS1 is informative**. Matters more for DECOYS (train
the model) than entrapment. NEXT experiment: Astral library with m/z-SEPARATED decoys →
does MS1 gain weight (pass-1 model only)? Road to Brendan's 2008 nr-as-decoys idea.
GOTCHA: Astral pass-2 rescore at `--threads 30` gets memory-killed; `--threads 8` survives.
Full detail in `[[project_osprey_natural_entrapment]]` and `ai/.tmp/natural-entrapment-design.md`.

**Next session handoff**: For detailed startup protocol (build, the Astral run command with
--threads 8, key paths, gotchas), read `ai/.tmp/handoff-20260706_osprey_entrapment_ms1.md`
before starting work.

## Progress 2026-07-06/07 (overnight research session) — decoy m/z-collision, MS1 power, Osprey kill
Full report: `ai/.tmp/night-report-decoy-mz-collision.md`. Lit: `ai/.tmp/night-lit-report.md`.
Key results (Astral HRAM, decoy-only m/z shift, isobaric entrapment = true-FDP oracle):
- **Isobaric decoys suppress MS1** (weight +0.16% ≈ 0). **+10 Th shift (Skyline's default) restores
  MS1 ~20× (3.25%)** and gives **+12.3% more IDs at true FDP=1%**, BUT inflates FDP@reported-1%q
  1.92%→3.05% (anti-conservative). **+0.5 Th control** (in-window): restores MS1 isotope (+3.80%),
  +4.1% IDs at true 1%, milder inflation (2.06%) — isolates the isotope effect from +10's
  window-crossing.
- **Solution that ties to THIS PR**: shifted/foreign decoys for MS1 SENSITIVITY + isobaric-entrapment
  overlay (the combined estimator, PR #4380) for honest CALIBRATION. Neither alone; together = MS1
  sensitivity with honest FDR. This is a concrete new motivation for the partial-entrapment work.
- **Osprey Astral --threads 30 "kill" ROOT-CAUSED**: real commit-limit OOM (pass-2 mem scales with
  threads → ~98GB commit), silent because the Bash Job Object sets DIE_ON_UNHANDLED_EXCEPTION
  (suppresses WER). Not external, not file-parallelism (sequential by default). Fix (separate pwiz
  ticket): catch OOM+log guidance; memory-aware pass-2 thread cap; stream rescored rows. Interim:
  --threads 8. See [[reference_osprey_astral_thread_memory_oom]].
- Tooling (reusable): `ai/.tmp/shift_decoy_mz.py` (decoy m/z shift), `ai/.tmp/extract_mdiag.py`
  (MS1 weights + FDP@q from model-diagnostics HTML), `ai/.tmp/mem-sampler.ps1`, `ai/.tmp/job-probe.ps1`.
- OPEN (designed, not run — confound-prone, deferred): foreign-species/nr decoys at real m/z w/
  collision avoidance (`--min-target-sep-ppm`); the road to the 2008 nr-as-decoys idea. Needs a
  distribution-matched Carafe build. See report §5.

## Progress 2026-07-07 (later) — extended decoy sweep + literature corroboration
Additional Astral experiments (report §4b–4h): **+0.5 Th** charge-3 decoys are 100% in the atomic
mass-defect "no man's land" (defect off 0.44 Da) → artificial isotope separability; **charge-blind
permute** (44% impossible masses) and **charge-preserving permute** (occupied same-charge m/z, FDP
**4.35%** — worst) both anti-conservative. **The reframe**: the reverse decoy's zero MS1 power is the
ANAGRAM (co-locates on the target peak → precursor co-elutes), NOT the isobaric m/z. No decoy m/z
placement gives honest MS1 power. Refined hypothesis (untested, needs Carafe): **isobaric mass-matched
NON-anagram (real foreign) decoys** — match m/z, change fragments — could be honest AND MS1-powerful.

**Literature corroboration (independent, strong):**
- **Bernhardt, Bruderer, …, Reiter (Biognosys), 2016** ("General guidelines for validation of decoy
  models…", poster `ai/.tmp/General_guidelines_for_validation_of_dec.pdf`): on HRAM (Q Exactive) they
  used **E. coli as a ground-truth negative control** to validate decoys — scrambled/inverted
  (isobaric) decoys match the control and give accurate/conservative FDR (0.6% true @ 1% est); a
  **fragment-m/z-shift** decoy underestimates FDR (2.3% true @ 1% est) with the MOST IDs (a mirage).
  "Number of identifications alone should not be used as a qualifier." = our +10 result, 9 yr early.
- **diagFDR — Chion, …, Giai Gianetto, bioRxiv Apr 2026** (`ai/.tmp/biorxiv2026.txt`): formalizes the
  **"equal-chance" assumption** (incorrect matches equally likely to hit a decoy or a false target).
  Our m/z manipulations are textbook equal-chance violations. **Chan, Madej, Chung, Lam (JPR 2025)**:
  template decoys in *predicted* libraries systematically violate equal-chance (our Carafe setting).
  **Granularity paradox** (Couté, Bruley, Burger, Anal Chem 2020): sharpening decoy separation empties
  the decoy tail near the cutoff → FDR numerically fragile (worse on HRAM) — a 2nd failure mode of
  "more IDs from better separation". **TargetDecoy** QC pkg (Debrie…Clement, JPR 2023). Entrapment
  (Wen [22]): interpret FDPentrap **comparatively**; **FDPentrap≫α = anti-conservative evidence**
  (our +10 = 3.05%); **FDPentrap≈α is NOT proof** (optimistic-decoy + pessimistic-entrapment cancel) =
  our shift-both collusion trap, formalized. Three entrapment-proteome criteria (absent / large enough
  / phylogenetically distant) validate the nr choice.
- **Net for THIS PR**: the partial-entrapment/combined estimator is the load-bearing "external
  oracle" the whole field (Bernhardt, Wen, diagFDR) says you need; our night reproduces & extends it
  with the MS1-feature mechanism. The success criterion for any MS1-powered decoy is now stateable in
  their language: **raise MS1 feature weight while keeping the equal-chance diagnostic flat and
  FDPentrap ≈ α under an independent isobaric-human oracle.** Full synthesis in the report §3–§5b.

### 2026-07-07 - Merged
PR #4380 merged as commit `31168db37b`. Shipped: the paired FDP estimator is now suppressed when the
entrapment library is not ~1:1 (paired is 1-fold only; the ratio-aware combined and lower-bound
estimators stay valid at any ratio and the report labels the omission), plus
`pwiz_tools/Osprey/docs/fractional-entrapment.md` justifying a fractional (~10%) entrapment overlay
(Fitzgibbon 2008 / Wen 2025, grounded in the equal-chance framework per Bernhardt 2016 and diagFDR
2026), and tests for the gating + ratio-aware estimators at r<1. The extensive decoy-m/z / MS1 /
RT-constraint research logged above was the *consumer-side motivation* and is NOT part of this PR; it
is carried forward in the night-session-ready [[TODO-osprey_foreign_decoys_honest_ms1_power]] and the
consolidated [[TODO-osprey_assumption_failure_detection]]. No scope from #4380 was deferred.
