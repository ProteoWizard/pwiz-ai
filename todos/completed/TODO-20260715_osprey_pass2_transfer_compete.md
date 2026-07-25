# TODO: Osprey pass-2 FDR — honest FDR (transfer-compete) then sensitivity recovery (GBDT + protein compaction)

**Created:** 2026-07-15  **Requested by:** Mike

## Branch Information
- **Branch**: `Skyline/work/20260715_osprey_pass2_transfer_compete`
- **Base**: `master`
- **Created**: 2026-07-15
- **Status**: In Progress
- **GitHub Issue**: [#4436](https://github.com/ProteoWizard/pwiz/issues/4436)
- **PR**: (pending)

## Background / arc of the work

### 1. transfer-compete — fixed the pass-2 FDR (SUCCESSFUL, but cost sensitivity)
Osprey's default 2nd-pass FDR retrained the Percolator SVM on the decoy-depleted
compacted pool, which was **anti-conservative** on entrapment libraries (Stellar true FDP
1.08%, Astral 1.24% at 1% reported q). `OSPREY_PASS2_QVALUE=transfer-compete` fixes it:
apply the FROZEN 1st-pass model to the reconciled targets+decoys (no retrain), then recompute
q + PEP by a fresh target-decoy competition over the full pre-compaction population (streamed
one file at a time, flat in file count). Restores control (Stellar exp 0.36%, Astral 0.82%).
**This is the honest FDR baseline — but honest FDR means FEWER IDs, i.e. it cost sensitivity.**

### 2. The DIA-NN sensitivity gap (the motivation for everything below)
On **Astral**, Osprey detects **significantly FEWER precursors than DIA-NN (107.5k vs 142.8k)
but a SIMILAR / slightly HIGHER number of proteins (9,260 vs 8,800).** So the missing
precursors are additional peptides of proteins BOTH tools already detect — a depth problem.

**Peak-finding is NOT the problem — it's discrimination.** Boundary-overlap analysis
(`rt_boundary_analysis.py`): of DIA-NN's 1%-FDR precursors, Osprey had integrated the EXACT
SAME peak for **~86%** — **97% of the 100k shared** precursors and **62% of the 42.7k
DIA-NN-only** precursors are the *same integrated peak*. So for most of what DIA-NN finds and
Osprey misses, Osprey already found the right peak and simply scored it below threshold.
(Minor: ~16% out-of-window / RT-prediction; a late-RT ceiling ~7% of the Astral gap.)

### 3. GBDT — non-linear scoring to close part of the gap (SUCCESSFUL on Astral, +8%)
Implemented a pure-managed non-linear **gradient-boosted decision tree** scorer (`--fdr-method
fasttree`) with **L1 (RegAlpha) + L2 (RegLambda)** regularization (XGBoost/Chen-Guestrin form),
so we could bring in some of the misbehaving Rust `CoelutionFeatureSet` features that a linear
SVM couldn't use (non-monotone / collinear / interaction). It shares the Percolator
semi-supervised target-decoy framework (only the classifier differs). **Result: Astral +8.1%
precursors at matched true entrapment FDP, calibrated.** On unit-res **Stellar** it did NOT
help (−5 to −11% vs SVM at matched FDP regardless of regularization — trees are underpowered
on unit-res). **Decision: use the SVM going forward; GBDT is OFF by default** (Percolator is
the default; fasttree is opt-in). Resolution-keyed classifier (SVM=unit, GBDT=hram) deferred.

### 4. Protein compaction — recover the peptide depth (VALIDATED on Stellar)
Take the peptides of every protein **detected at 1% FDR with >= 2 peptides** and carry them
forward into the **reconciliation** step (as target+decoy pairs). During reconciliation,
**rescore ONLY the peptides that moved to a new peak** (consensus-RT alignment), applying the
**frozen ML model**, then **recompute the FDR** with a competition constrained to that
present-protein stratum. **Mechanism = reducing the curse of dimensionality:** the
full-population competition tests millions of hypotheses, so honest 1% FDR needs a strict
threshold that leaves marginal true peptides behind; constraining the competition to the
present-protein stratum shrinks the hypothesis space, so the (mostly-real) retained peptides
clear FDR with more power (reduced multiple testing / Bourgon 2010 independent filtering). It
stays honest because protein membership is ~independent of a peptide's own decoy score — the
>= 2-peptide anchor excludes single-hit proteins, which would break that independence.

## Status

- [x] **transfer-compete** shipped + validated (honest pass-2 FDR). Streaming, flat in file count.
- [x] **GBDT/fasttree** scorer built, shares Percolator path, L1+L2, extra features. Astral +8.1%.
      Off by default (SVM chosen). Regularization sweep confirmed it can't fix Stellar.
- [x] **Protein compaction — increment 1** (honest FDR engine): streaming stratified competition
      (`ComputeFullPopulationPrecursorFdrStreaming` + optional `stratumBaseIds`, flat memory);
      `ComputeStratifiedCompetitionQvalues` + unit test `TestStreamingStratifiedMatchesResident`.
- [x] **Protein compaction — increment 2** (reconciliation expansion): compaction gate admits
      the >= 2-peptide-protein stratum on BOTH first-pass paths; movers get reconciled + rescored
      via the frozen model; persist/HPC-worker covered. `ProteinCompactStratum` byproduct.
- [x] **Validated end-to-end on Stellar (entrapment):** protein-compact pass-2 = **25,680
      precursors @ 0.466% true FDP** vs the SVM transfer-compete baseline's 20,721 @ 0.357% =
      **+24% at 1% reported q, FDR controlled**; matched true FDP +19.7% @0.5%, +20.2% @0.75%.
      pass2 now EXCEEDS pass1 (recovering peptides pass1 missed). Reproduces the +25-27% prototype.

## Remaining work

1. **Astral protein-compact validation** (expect a bigger win — Astral is where the DIA-NN gap is).
2. **The <=1% true-FDP tail** — matched_fdp reports a nonsensical +911% at exactly 1.0% (curve is
   non-monotonic over the 1.7M-entry expanded reported set). Operating point (1% reported q) is
   clean/honest; understand the tail before trusting the <=1% boundary.
3. **Gate-expansion unit tests** (the compaction-gate stratum admission on both paths).
4. **>= 3-peptide anchor** as a tuning lever — the expanded reconciliation reconciles ~8x more
   base_ids (300,727 vs 36,768) / 1.7M vs 216k entries → ~2x reconciliation time + more memory;
   >= 3 shrinks the stratum with similar/higher yield.
5. **DIA-NN precursor overlap venn** (protein-compact vs DIA-NN) — does the recovered depth match
   DIA-NN's precursors? (regular-lib runs for apples-to-apples).

## Separate / blocking: scoring performance regression (NOT this feature's code)
Cold Stellar regular-lib is **46 min vs the 12.8 min baseline (3.6x), ~40% CPU, ~32 GB peak** —
the branch lacks master's **PR #4424** scoring-memory optimization (`consumeInputMzs` MS2 m/z
free + `float[][]` calibration cache, ~6.6 GB), which on this RAM-constrained box (file
parallelism forced to 1) drives GC/paging that stalls the scoring threads. Compounded by the
data now living on the Z: NAS. **Plan:** remove the extra-features (add back later if needed),
pull in #4424, rebuild, re-benchmark on a quiet machine. Parallelism code is byte-identical to
master (verified); the regression is memory/systemic, not the scoring algorithm.

## Key files / scripts
- FDR: `Osprey.FDR/PercolatorFdr.cs` (streaming + stratified competition), `Osprey.Tasks/Pass2FdrSidecar.cs`
  (dispatch), `Osprey.Tasks/FirstJoinTask.cs` (stratum build + compaction gate).
- GBDT: `Osprey.ML/GradientBoostedTrees.cs`.
- Bench/validation (on Z:): `Z:\osprey-test-data\benchmark-results\` — `Run-ProteinCompact-Entrapment.ps1`,
  `Run-Stellar-Reg-Sweep.ps1`, `prototype_protein_compact.py`, `matched_fdp.py`, `extract_any.py`,
  `rt_boundary_analysis.py`. First DIA-NN comparison run: `run-20260714-213641/`.
