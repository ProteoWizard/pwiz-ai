# TODO: Osprey --model-diagnostics — decoy-modeling goodness diagnostics (null-alignment ratio + paired-coin collapse)

**Status**: Completed — PR [#4399](https://github.com/ProteoWizard/pwiz/pull/4399) (merged 2026-07-09 as babcebdb6e).
  Branch `Skyline/work/20260708_osprey_storey_null_ratio` (from master).
**Created**: 2026-07-08 (night session)
**Requested by**: Brendan (Mike weighed in on the design)
**Scope** (`--model-diagnostics`-only; blib/FDR golden UNCHANGED — tripwire):
  `pwiz_tools/Osprey/Osprey.FDR/ModelDiagnostics/ModelDiagnosticsData.cs`,
  `pwiz_tools/Osprey/Osprey.Tasks/ModelDiagnostics/model-diagnostics-template.html`,
  `pwiz_tools/Osprey/Osprey.Test/ModelDiagnosticsDataTest.cs`.
**Parent design**: `ai/todos/backlog/brendanx67/TODO-osprey_assumption_failure_detection.md` §B
  (equal-chance null alignment) — this PR is the non-parametric visual slice of it.
**Handoff**: `ai/.tmp/handoff-20260708-osprey-model-diagnostics-two-prs.md` (PR 2).

## Broadened scope (2026-07-09, with Brendan): goodness of decoy modeling
This PR is NOT limited to the one density-ratio plot; it targets the overall
question "**are the decoys good nulls?**" with a small family of complementary
report checks, each catching a DIFFERENT failure mode. Two land here:

1. **Marginal decoy-shape check — the non-parametric null-alignment density ratio
   (below).** DONE. Validated on the oracle: `target:decoy` flatness KPI 0.055
   (libdecoy, calibrated) vs 3.08 (gendecoy, generated) = ~56x separation.

2. **Pairing check — the paired-coin collapse detector.** ADD NOW. Promote the
   already-computed null-band paired decoy-win scalars (`WinFractionData.
   NullBandReal` / `NullBandEnt`, Competition tab) to a KPI badge + qualitative
   flag: the **real** null-band coin collapsing below the **entrapment** coin =
   real targets beating their own decoys unfairly. Report-only (no console/FDR
   abort); diagnostics-only, golden unchanged.

### Why the pairing check is the important one (Brendan's boost study)
The adversarial case we MUST be able to detect: **false-targets:decoys do NOT
match, but entrapment:decoys DO match** — a target-side score boost
(`OSPREY_BOOST_TARGET_DISCRIMINANT`, parent TODO §F) that slides real target
scores up while the decoy AND entrapment marginals stay put. Study result
(`ai/.tmp/OspreyFDR/density/whatif_shift_targets.png`, `winfrac_boost.png`):
- Detected count rises 22038 -> 47874 across boosts +0..+3, and the decoy-q vs
  entrapment **FDP plot stays great (0.7-0.8% @ q=0.01)** — anyone would accept it.
- **Every marginal density and every entrapment-anchored estimator is blind**,
  because both nulls are intact and the real target marginal shift is
  indistinguishable from a genuinely better search (more/steeper true hits).
- The ONLY fingerprint is in the pairing: the **real** paired decoy-win in the
  null band collapses 47.4% -> 27.2% while the **entrapment** coin holds 50%
  (`winfrac_boost.png` top-right vs bottom-right). Within-pair, not marginal.

**Consequences (locked):**
- **Rejected option (b) `p_target:decoy`** (entrapment-as-empirical-false-target
  density ratio). It is entrapment-anchored, so under the boost it rides flat and
  actively REASSURES — the exact false comfort to avoid. Do NOT add it.
- Option (a) parametric f_false:decoy (§A) is fragile here (the boost pushes false
  targets into the true-target region; a marginal mixture reads it as improvement)
  — leave to the §A follow-up, not this PR.
- The density-ratio card copy must be scoped honestly: a **marginal** decoy-shape
  check, NOT an equal-chance validator (a flat plateau does not clear the boost).
- The paired-coin collapse KPI is §C of [[TODO-osprey_assumption_failure_detection]]
  made concrete. A calibrated **console warning** on the FDR path (threshold tuned
  on the boost sweep) is the natural next step but stays a follow-up (needs
  calibration; keep this PR report-only).

## What & why
Mike's Storey-style null check: the RATIO of per-class score DENSITIES on the
null-dominated **left** side. A calibrated decoy pairing rides a **flat** plateau
there; a decoy that mistracks the false-target null makes the left side **slope** —
visible with **no parametric fit** (the decoy-normal overlay misfits the skewed
decoys; this sidesteps that).

Two lines (ratios of densities, each class density integrates to 1):
- **target : decoy** — the diagnostic (Mike's check). Flat on the left at the null
  fraction π0 (<1; target carries true-hit mass), then rises where real hits begin.
- **p_target : p_decoy** — matched-null reference (both pure null) ≈ 1 flat
  everywhere; the "what a matched null pair looks like" anchor. Only when entrapment.

**Flatness KPI** = tilt of the target:decoy plateau across the null region
(weighted LS slope of ln(ratio) vs a null-region-normalized score; ~0 = flat). KPI
badge only — **no alarm / no threshold-gating** this PR (Brendan's scope). Plateau
height reported as a bonus Storey π0 read.

## Placement
New card on the **Density tab, directly below "Score density by class"** — reuses the
same per-class count arrays already reduced for that plot (`ScoreHistogram.Target/
Decoy/PTarget/PDecoy`), no new binning pass. Same standardized x so it stacks cleanly.

## Design (confirmed against source)
- `DensityRatioData` on `ModelDiagnosticsData`, computed in `Build()` from
  `data.Scores` → flows through the FirstJoin→sidecar→MergeNode(append-only)→HTML
  round-trip untouched (MergeNode only appends pass-2 views / sets ModelPass2).
- `public static BuildDensityRatio(ScoreHistogram, bool hasEntrapment)` for
  deterministic unit testing (mirrors BuildPass2FdpViews / BuildModelPass2).
- Undefined ratio bins = `NaN` (NOT Infinity — JS `isNaN` misses Infinity; the HTML
  serializer writes NaN→"NaN", which JS skips). Guard all denominators.
- Null region = usable left bins (target≥1 & decoy≥1) up to the true-hit onset
  (target density sustainedly ≥ decoy density), capped at ~decoy 95th pct. Weighted LS
  slope over that window normalized to [0,1]; weight = t·d/(t+d) (inverse log-ratio
  variance). RefFlatnessSlope = same on p_target:p_decoy over the same window.

## Validation (the built-in oracle — testable overnight)
libdecoy (calibrated, Carafe library decoys) target:decoy left = FLAT; gendecoy
(Osprey reverse decoys, ~22% coin, ~10× off) = NON-FLAT.
Data: `D:\test\osprey-runs\stellar-libdecoy\` (mzML 20/21/22 + carafe lib + pairing).
gendecoy = same inputs WITHOUT `--decoys-in-library`. Assert flatness(gendecoy) >>
flatness(libdecoy); p_target:p_decoy flat on both.
See [[project_osprey_libdecoy_vs_gendecoy_calibration]].

## Gates
- `Build-Osprey.ps1 -Configuration Debug -RunTests -RunInspection` (0-warn + tests).
- `regression.ps1 -Dataset Stellar` — GOLDEN UNCHANGED (if it moves, the change leaked
  into the FDR path → STOP + back out).
- Open PR → `/pw-self-review` → address in new commits → TeamCity
  `ProteoWizard_OspreyWindowsNetPerfRegressionTests` on `pull/<N>` green → review-ready.
  **Do NOT merge — Brendan reviews.**

## Guardrails
- Diagnostics-only; do not touch blib/FDR output. No console alarm / no parametric
  f_false. Localize user-facing strings ([[no_localizable_string_in_static]]) — but
  note the HTML report text lives in the embedded template, not C# resources.

## Progress Log

### 2026-07-09 — Merged
PR #4399 merged as commit babcebdb6e. Shipped both decoy-modeling goodness
diagnostics: the non-parametric null-alignment **density ratio** (Density tab,
target:decoy + p_target:p_decoy, left-side flatness KPI) and the
**paired-coin-collapse** KPI (Competition tab). Validated end-to-end on the
libdecoy (flat 0.055) vs gendecoy (steep 3.08) oracle and, via the recovered
`OSPREY_BOOST_TARGET_DISCRIMINANT` instrument, on the target-boost case the coin
catches (real coin 47.8% → 22.7% while entrapment held 50%) — trial set at
`D:\test\osprey-runs\_ratio_trial\`. Copilot review addressed (null-region cap
made inclusive; KPI labels aligned to series names). Diagnostics-only: blib/FDR
output and the regression golden unchanged. Deferred/parked: option (b)
`p_target:decoy` (rejected — entrapment-anchored, boost-blind); the parametric
f_false (§A) and a console/FDR-path alarm remain in
[[TODO-osprey_assumption_failure_detection]]; the broader reduced-pool FDR
program is captured in [[TODO-osprey_reduced_pool_fdr_calibration]]. Boost
instrument stays on the local-only `osprey-boost-demo2` branch (not pushed).
