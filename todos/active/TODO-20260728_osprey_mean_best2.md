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
- [ ] Flag-off byte-identity regression (Stellar mode1/2/3) — golden unchanged.
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
