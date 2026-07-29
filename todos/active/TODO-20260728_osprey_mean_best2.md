# Osprey: mean(best-2) reproducibility 1st-pass experiment score (sensitivity lever)

## Branch Information
- **Branch**: `Skyline/work/20260728_osprey_mean_best2` (pwiz-work1, off clean master)
- **Base**: `master` (61fa751304)
- **Module**: `osprey`
- **Created**: 2026-07-28
- **Status**: In Progress
- **Parent issue**: [#4484](https://github.com/ProteoWizard/pwiz/issues/4484) (pass-2 FDR default
  decision — this is the honest sensitivity lever vs. the invalid transfer-compete/protein-compact)
- **PR**: (pending)
- **Requester**: Mike + Brendan (Osprey developers) — NO credit line.

## Objective

Replace the 1st-pass experiment score's best-of-runs (**max**) aggregation with a
**reproducibility** score: precursor = **mean of best-2 per-run scores** (decoy-median floor for a
missing run), rolled up by **max** to peptide and protein. Flag-gated A/B so we can measure it vs.
`transfer` on the 82f/164f FDRBench entrapment oracle at matched TRUE FDP. C#-only for now (Rust
match if it graduates to a PR). Goal: give Mike the sensitivity he thought protein-compact gave him,
but from a statistically VALID transform (symmetric decoys, self-calibrating in N).

## Design (PINNED — full spec: `ai/.tmp/mean-best2-spec.md`)

- **Precursor** (ModSeq+Charge) = mean of its best-2 per-run scores (best peak per run, 2 highest
  distinct runs). **1 valid run → mean(score, decoy-median floor)** (typical null score, negative;
  NOT 0). Multi-run experiments only; single-file degenerates to the single score.
- **Peptide** = max over its precursors' scores. **Protein** = max over its peptides' scores.
- TDC + q on the rolled-up scores; **symmetric for decoys** (each decoy computes its own precursor
  mean-best-2). Valid because the transform reads only each unit's own per-run data.
- Floor: decoy **median** (default); decoy mean / low decoy percentile = A/B variants.
- Flag: `OSPREY_EXPERIMENT_AGG` = `max` (default, byte-identical golden) vs `mean-best-2`.

## RESULT — crosses positive at scale (2026-07-28, 1st-pass only, reused parquets)

Fast workflow (Brendan's idea): hard-link a prior 82-file run's Stage-4 parquets
(`pass2ab-82file-percolator-5day`, `OSPREY_VERSION_OVERRIDE=26.1.1.199` past the daily guard) +
`--task FirstPassFDR --model-diagnostics --fdrbench-pass 1`, resident (`OSPREY_FDR_PROJECTION=0`),
first-20 files. ~15 min/arm, NO PerFileScoring. Driver: `ai/.tmp/mb2-firstpass-arm.ps1`.
Pass-1 experiment fdpView from each arm's `out.model-diagnostics.data.json`.

| metric | max | mean-best-2 | Δ |
|---|---|---|---|
| disc @ 1% experiment q | 45,015 | 45,863 | +848 (+1.9%) |
| true FDP @ 1% q | 0.88% | 0.76% | better calibrated |
| disc @ matched 1% TRUE FDP | 46,496 | 47,685 | +1,189 (+2.6%) |

**mean-best-2 DOMINATES max at N=20** — more discoveries at a LOWER true FDP. Trend: N=3 = −4.9%
(net negative), N=20 = +2.6% (net positive) → crosses positive as run count grows; magnitude should
climb toward N=82 (frontier suggested ~+19%). Run-count histogram (N=20) confirms the threshold
basis: a 1-run detection is 16.75% FDP (per-run), leaky enough that demotion is justified — unlike N=3.

**NEXT (all cheap via the fast workflow)**: N=82 (all 82 parquets), floor A/B (decoy mean/median/
low-percentile), then 200/300/500 on the 2nd machine. Streaming-path mirror still needed for a
production default (resident-only today).

## FUTURE REFINEMENT — size-threshold / scale-adaptive demotion (Brendan 2026-07-28)

3-file result showed a modest NEGATIVE (disc@1%q 27,201→25,871, −4.9%; true FDP 0.86%→0.76%):
at small N, "detected in only 1 run" is weak FDR-leakage evidence, so demoting it costs good IDs
without much calibration gain. At larger N, 1-of-N is a strong leakage signal. So we likely want
mean(best-2) to engage only above a run-count threshold. The earlier `mean(best-⌈f·N⌉)`
generalization implements this NATURALLY: pick f so ⌈f·N⌉=1 at small N (= max, no demotion) and
grows with N (e.g. f≈0.1: N≤10→1 [max], N=20→2, N=82→9). One knob unifies "threshold" +
"scale-adaptive reproducibility bar." DECIDE the threshold/f from the run-count-vs-benefit curve
(3f done, 20f running, then 200/300/500 on the 2nd machine) — don't hard-code yet.

## Implementation seams (mapped — see spec)

- Resident: thread existing `fileNames[]` into `ComputeExperimentPrecursorQMap`/`CompeteAll`/
  `CompeteFromIndices` (`PercolatorFdr.cs` :3936/:3064/:2703); group base_id indices by run
  (mirror `ComputePerRunPrecursorQvalues` :3743 idiom); aggregate mean-best-2 instead of max.
  Peptide: `ComputeExperimentPeptideQMap` :3988 → roll up max over precursor scores.
  Protein: `ProteinFdr.ComputeProteinFdr` :664 uses the peptide rollup score.
- Streaming: thread run name into `StreamingFirstPassQ.Add` :4071 + `FirstPassProteinFdrAccumulator.Add`
  :200 (fed per-file; run available at feed site).
- Per-file best-peak-per-precursor already guaranteed by Stage-4 dedup (one FdrEntry per base_id/run).

## Tasks

- [x] Flag `OSPREY_EXPERIMENT_AGG` in OspreyEnvironment (mirror the Pass2* pattern). — commit 2560e04979
- [x] Precursor mean-best-2 aggregation (resident) + decoy-median floor; flag-off byte-identical.
      — commit 2560e04979 (CompeteFromIndicesMeanBest2 + unit tests; 548/548 green).
- [x] Peptide max-rollup over precursor scores (resident). — commit dd8cd2136e. Unified via
      `ComputeBaseIdMeanBest2` (per-row aggScore); CompeteAll (precursor) + BestPrecursorPerPeptide
      (peptide) consume it. Replaced the precursor-only CompeteFromIndicesMeanBest2. 548/548 green.
- [ ] Protein uses the peptide rollup score (ProteinFdr operates on FdrEntry.Score — needs the
      aggScore fed in / entry.Score overwrite; separate increment).
- [ ] Streaming-path mirrors (bounded/HPC).
- [ ] Unit tests (aggregation + floor + 1-run demotion + decoy symmetry).
- [x] Flag-off byte-identity regression (Stellar mode1/2/3) — golden unchanged. PASSED 2026-07-28
      (blib 30,597,120 all 3 modes) on commit dd8cd2136e; confirms mean-best-2 is golden-neutral off.
- [ ] Flag-on oracle A/B vs transfer (82f/164f, matched TRUE FDP) — Brendan-driven.
      **PROTOCOL (Brendan 2026-07-28): flag-on runs MUST use OSPREY_PASS2_QVALUE=transfer** (only
      transfer carries the mean-best-2 1st-pass experiment q through; percolator re-derives and
      confounds it). Clean A/B = `transfer` (max) vs `mean-best-2`+`transfer`. Until the streaming
      mirror lands, also force the resident path: OSPREY_FDR_PROJECTION=0 + OSPREY_ALLOW_UNBOUNDED_MEMORY=1.

## Regression Test
- Flag-off: committed golden byte-identity (regression.ps1). Flag-on: entrapment-oracle A/B is
  decision evidence, not a regression test.

## Progress Log

### 2026-07-28 - Branch created, design pinned
Branched off clean master (independent of #4487, which is a separate 2nd-pass model-persistence
checkpoint awaiting TeamCity). Design fully pinned with Brendan (precursor mean-best-2 + max rollup +
decoy-median floor + flag-gated A/B). Implementation seams mapped. Starting with the flag + precursor
core.
