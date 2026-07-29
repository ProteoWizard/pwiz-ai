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

## BLOCKER — N=82 needs the streaming mirror (resident OOMs on the 63GB box)

N=82 resident FirstPassFDR committed **103.6 GB** (private); this machine has **63.7 GB** RAM →
pagefile thrash, killed. (The MEMORY note's "82-file peak 49GB" was the STREAMING path; the RESIDENT
path mean-best-2 requires is O(files) ~104GB at N=82.) So resident mean-best-2 caps at ~N≈25-30 here.
**The streaming-path mirror is now CRITICAL PATH for the N=82 measurement** (not just production
polish): thread the run id into `StreamingFirstPassQ.Add` (:4071), accumulate best-per-(base_id,run),
reduce to mean-best-2. Same work a production default needs. Alternative: run N=82 resident on the
larger-RAM machine. N=20 (below) already validates the lever; N=82 quantifies the full recovery vs
the 37,763 floor / 44,861 frontier.

### Target bars for N=82 (from Brendan's diagnostics, max/min-q arm)
- max exp-wide 1% q floor = **37,763** (down from ~45,015 @ N=20 — max LOSES 16% sensitivity as N
  grows; max-of-N null inflates). k=1 slice FDP: 7.6% @ N=20 → **14.1% @ N=82** (spikes).
- Reproducibility frontier (≥4 runs, floated q=10%) = **44,861 @ 1% true FDP = +7,098 (+18.8%)**;
  ≥2 runs ≈ 43,866. "Reproducibility, not the q statistic, selects them." Goal: mean(best-2) reaches
  ~43-45k at a WELL-CALIBRATED 1% q automatically (no manual run-count filter / q-floating).

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
- [x] Streaming-path mirror (precursor + peptide) — commit 7c827899a5. `StreamingFirstPassQ`
      accumulates top-2 per (base_id, side) + a bounded decoy-floor histogram when mean-best-2;
      the experiment precursor/peptide q-map branches reduce to mean(best-2) + max roll-up,
      matching the resident path (exact for multi-run; floor is a bounded quantile). PEP + max
      path untouched. Flag-OFF Stellar byte-identity PASS (blib 30,597,120). Protein streaming
      still pending (with the resident protein increment).
- [x] Unit tests — commit 7c827899a5 (FdrTest.cs): `TestStreamingMeanBest2MatchesResident`
      (exact streaming==resident maps on a >=2-run fixture, floor unused) +
      `TestStreamingMeanBest2DemotesSingleRun` (single-run floor demotion). 550/550 green.
      (Resident aggregation/floor/1-run already in PercolatorMeanBest2Test.)
- [x] Flag-off byte-identity regression — golden unchanged. Streamlined commit 7c827899a5 PASSED
      **regression.ps1 -Dataset All** (2026-07-29): Stellar + StellarLibDecoy + StellarGenDecoyEntrap +
      Astral, every mode (golden/resume/HPC/diagnostics) - the full correctness gate is banked for a PR.
      (Earlier dd8cd2136e passed Stellar-only, blib 30,597,120.)
- [ ] Flag-on oracle A/B vs transfer (82f/164f, matched TRUE FDP) — Brendan-driven.
      **PROTOCOL (Brendan 2026-07-28): flag-on runs MUST use OSPREY_PASS2_QVALUE=transfer** (only
      transfer carries the mean-best-2 1st-pass experiment q through; percolator re-derives and
      confounds it). Clean A/B = `transfer` (max) vs `mean-best-2`+`transfer`. Until the streaming
      mirror lands, also force the resident path: OSPREY_FDR_PROJECTION=0 + OSPREY_ALLOW_UNBOUNDED_MEMORY=1.

## Regression Test
- Flag-off: committed golden byte-identity (regression.ps1). Flag-on: entrapment-oracle A/B is
  decision evidence, not a regression test.

## Progress Log

### 2026-07-28 (night) - Streaming mirror LANDED + N=82 A/B: mean(best-2) DOMINATES (+14.6%)

**N=82 RESULT (first large-scale measurement, streaming path).** mean(best-2) pass-1 experiment score
vs MAX at N=82 (same 82 Stage-4 parquets, `target+decoy+entrapment` lib, entrapment oracle):

| metric | max | mean-best-2 | delta |
|---|---|---|---|
| disc @ 1% experiment q | 37,676 @0.918% | 42,045 @0.794% | +4,369 (+11.6%), LOWER true FDP |
| disc @ matched 1% TRUE FDP | 38,300 | 43,873 | +5,573 (+14.6%) |

mean(best-2) gives MORE discoveries at a BETTER-calibrated (lower) true FDP. **Trend confirmed and
strengthening: N=3 -4.9% -> N=20 +2.6% -> N=82 +14.6%** (matched true FDP) - the advantage grows with run
count, exactly the reproducibility thesis (1-of-N detection is strong FDR-leakage evidence at large N).
43,873 reaches ~85% of the way from the max floor (38,300) to the reproducibility frontier
(44,861 @1% true FDP) AUTOMATICALLY at a well-calibrated 1% q - no manual run-count filter / q-floating.
This is the first large-scale proof + a usable, bounded-memory (streaming) implementation.

SELF-CONSISTENT (both arms my build, same parquets): confirmed - my-build MAX == source-199 MAX EXACTLY
(37,676 @0.918% / 38,300, +0.0%), so the max path is build-stable and the A/B is clean. FLOOR A/B (median
default / mean / 5th-pct) ALL give identical decision metrics (42,045 / 43,873); the floors demonstrably
apply (pass-1 true-FDP arrays differ slightly) but are immaterial at N=82 (the floor shifts single-run
targets AND decoys equally, preserving the ranking). => +14.6% is the reproducibility mechanism, not floor
tuning; the floor is not a lever at large N.



Implemented the streaming-path mean(best-2) mirror (commit 7c827899a5, pwiz-work1): `StreamingFirstPassQ`
gains top-2 per-(base_id,side) accumulators + a bounded O(bins) decoy-floor histogram (mean exact via
running sum; median/percentile via a fixed 0.001-width histogram over [-100,100] with over/underflow
counts), gated on `OSPREY_EXPERIMENT_AGG=mean-best-2`. `BuildExperimentPrecursorQMap` /
`BuildExperimentPeptideQMap` reduce the top-2 to mean(best-2) and roll peptides up by max, mirroring the
resident `ComputeBaseIdMeanBest2` path. PEP + the default max path untouched. `MeanBest2Acc` made internal
so the streaming struct can hold it. GATES: build clean (0 new inspection); full suite 550/550 (net8.0);
flag-OFF Stellar byte-identity mode1/2/3 PASS (blib 30,597,120). Two new streaming unit tests
(streaming==resident exact on >=2-run; single-run demotion).

Validated `ai/.tmp/extract_pass1_fdp.py` against the resident N=20 reference (reproduces max 45,015 @0.876%
/ matched-TRUE 46,496 -> mb2 45,863 @0.763% / 47,685 = +2.6%).

**N=20 STREAMING cross-check PASSED (exact).** Streaming A/B (`mb2-fpstream-20-{maxstream,mb2stream}`) ==
resident A/B byte-for-byte on all three metrics: max 45,015 @0.876% / 46,496 -> mb2 45,863 @0.763% / 47,685
= +2.6%. Streaming-mb2 == resident-mb2 EXACTLY (+0.0%); the bounded floor histogram introduced zero
divergence. An independent code review of the diff (ai/.tmp/agent-mb2stream-review.md) found no
correctness bug. So the streaming mirror reproduces the validated resident result exactly - the bounded
(N=82-capable) implementation is proven.

**N=82 recipe (corrected - the handoff's fast path OOMs).** The `--task FirstPassFDR --input-scores`
from-parquets path pre-loads ALL features resident (~1.5 GB/file -> ~130 GB at N=82); it does NOT stream
(the handoff's "~49 GB" was the full-pipeline flow). WORKING streaming path on the 63.7 GB box:
`Run-SeaAd.ps1 -LinkFrom <source parquets> -FdrBenchPass 2` (NOT 1 - `--fdrbench-pass 1` trips
`GuardResidentPool`, which needs the O(files) resident pool). `-LinkFrom` adopts Stage 1-4 caches (incl.
`.osprey.task` markers) -> `PerFileScoring:skipping` -> streaming FirstJoin (~14-40 GB). The pass-1
experiment fdpView comes from `--model-diagnostics` (streams; Deliverable B), written at FirstJoin. Needs
`OSPREY_VERSION_OVERRIDE=26.1.1.199` + `OSPREY_EXPERIMENT_AGG=mean-best-2`. Max N=82 baseline already in
the source run's mdiag HTML: **37,676 @0.918% / matched-TRUE 38,300** (== Brendan's 37,763 @0.92%), so
only the mb2 arm is needed. mb2 arm running (out `seaad-82files-libdecoy-r1.0-percolator-mb2stream82b`);
extractor `ai/.tmp/extract_pass1_fdp.py`; exe snapshot `D:\test\osprey-exe-snapshots\mb2stream-20260728\`.

### 2026-07-28 - Night-session handoff: streaming mirror + N=82 A/B

**Next session handoff**: read `ai/.tmp/handoff-20260728-streaming.md` for the full startup protocol,
the streaming-mirror implementation plan (plug the existing `MeanBest2Acc` top-2 reducer into
`StreamingFirstPassQ.Add` + a streaming decoy-median floor — O(base_ids), ~49GB, fits 63GB), the
resident==streaming N=20 cross-check gate, and the N=82 A/B recipe + decision bars (beat 37,763,
approach 44,861). Resident mean-best-2 (precursor+peptide) is done + validated at N=20 (+2.6%);
N=82 is blocked on resident (104GB) and needs the streaming path. Goal: first large-scale
measurement + a usable (bounded-memory) implementation, not just POC.

### 2026-07-28 - Branch created, design pinned
Branched off clean master (independent of #4487, which is a separate 2nd-pass model-persistence
checkpoint awaiting TeamCity). Design fully pinned with Brendan (precursor mean-best-2 + max rollup +
decoy-median floor + flag-gated A/B). Implementation seams mapped. Starting with the flag + precursor
core.
