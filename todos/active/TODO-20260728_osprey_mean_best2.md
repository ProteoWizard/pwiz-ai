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

### 2026-07-29 (afternoon) - BOTH SWEEPS COMPLETE: N-curve peak + crossover is F=4, not a fraction

All 17 probe arms plus the Axis-1@82 tail finished unattended (last mdiag 09:55; machine now free).
Harvest: `python ai/.tmp/extract_all.py` (re-runnable). Numbers are pass-1 experiment fdpView,
`disc @ matched 1% TRUE FDP` (oracle-fair) with `disc @ 1% reported q` / trueFDP alongside.

**AXIS 1 - N-curve (disc @ matched 1% true FDP; frontier expPeak ~44,938):**
| N | 82 files (max 38,300) | vs max | 20 files (max 46,496) | vs max |
|---|---|---|---|---|
| best-2 | 43,873 | +14.6% | 47,685 | +2.6% |
| best-3 | 44,260 | +15.6% | **47,716** | **+2.6% (peak)** |
| best-4 | 44,469 | +16.1% | 47,488 | +2.1% |
| best-6 | **44,581** | **+16.4% (peak)** | 47,054 | +1.2% |
| best-8 | 44,275 | +15.6% | - | |
| best-12 | 43,658 | +14.0% | - | |
| best-20 | 42,825 | +11.8% | - | |

- Broad, gentle peak; overshooting N is cheap (best-20 at 82f still +11.8%). **N* grows SUBLINEARLY
  with F**: N*=2-3 @ F=20 (f=0.10-0.15), N*=6 @ F=82 (f=0.073) - so f* is not constant either.
- **Second-order finding: large N over-conservatizes the reported q.** trueFDP @ 1% q falls
  monotonically with N (82f: 0.918% max -> 0.794% @2 -> 0.729% @12 -> 0.691% @20; 20f: 0.876% ->
  0.763% -> 0.602% @6). So at the operating point a user actually ships (1% reported q), the optimum
  is LOWER than the matched-TRUE optimum: 82f disc@1%q peaks at N=4 (42,622) vs matched-TRUE peak
  N=6; 20f peaks at N=2 (45,863). Both metrics matter - matched-TRUE for the mechanism, disc@1%q for
  what ships.

**AXIS 2 - best-2 vs max by file count (matchedTRUE, trueFDP@1%q in parens):**
| F | max | best-2 | delta | f=2/F |
|---|---|---|---|---|
| 3 | (prior anchor) | | **-4.9%** | 0.667 |
| 4 | 42,304 (0.77%) | 43,490 (0.58%) | **+2.8%** | 0.500 |
| 5 | 40,893 (0.85%) | 44,510 (0.56%) | +8.8% | 0.400 |
| 6 | 40,535 (0.81%) | 44,398 (0.64%) | +9.5% | 0.333 |
| 8 | 44,387 (0.83%) | 47,672 (0.70%) | +7.4% | 0.250 |
| 10 | 42,805 (0.83%) | 46,182 (0.74%) | +7.9% | 0.200 |
| 12 | 42,572 (0.87%) | 44,092 (0.76%) | +3.6% | 0.167 |
| 20 | 46,496 (0.88%) | 47,685 (0.76%) | +2.6% | 0.100 |
| 82 | 38,300 (0.92%) | 43,873 (0.79%) | +14.6% | 0.024 |

- **The crossover is between F=3 and F=4 - it is NOT a fraction f\*.** best-2 wins at EVERY measured
  F>=4, including f=2/4=0.50 (+2.8%) and f=2/5=0.40 (+8.8%), which the working `f*` hypothesis
  predicted would still be negative. The hypothesis is dead as a *threshold* criterion; f only
  survives as a possible shape for N*(F), and even there it is not constant (0.15 -> 0.073).
- best-2 also LOWERS true FDP at every F, F=3 included - the calibration gain is universal; only the
  ID count flips sign, and only at F=3.
- CAVEAT on the delta-vs-F shape: the max baseline itself swings 38.3k-46.5k across cohorts (first-F
  subsets differ in content), so the non-monotonic magnitude (+9.5% @6, +2.6% @20, +14.6% @82) is
  cohort composition, not an N-dependence. Each row is a clean within-cohort A/B; the *trend* across
  rows is not. The deferred 2-D (N, F) harness with a fixed cohort per F is what makes the surface
  publishable.
- Implication for auto-N: gate on F (engage at F>=4, keep max at F<=3 - matching Brendan's
  batches-of-3 domain worry exactly), then let N grow sublinearly. N=2 is safe everywhere F>=4 and
  already captures 14.6 of the 16.4 points at F=82, so a conservative first default is defensible
  even before the surface is mapped.

Code state unchanged (4 commits, tree clean). Still open: `-Dataset All` flag-off byte-identity on
b7c375b905, the protein roll-up increment, then the 2-D harness / PR.

### 2026-07-29 (morning) - mean(best-N) generalization + Axis-1 N-curve

Generalized best-2 -> best-N (commit b7c375b905): `OSPREY_EXPERIMENT_AGG=mean-best-<N>` carries N;
top-2 accumulator -> fixed-capacity top-N buffer (MeanBestNAcc); aggregate = mean(top-min(k,N) per-run
scores + (N-k) floor). Resident (ComputeBaseIdMeanBestN) + streaming both generalized; N=2 bit-identical
to old best-2 (commutative add). OspreyEnvironment: MeanBestN int + ExperimentAggMeanBest. Tests: resident
N=3 + streaming==resident EXACT at N=2/3/4; 553/553 green. Flag-off untouched by construction; -Dataset All
byte-identity PENDING (machine busy with the sweep). Exe snapshot D:\test\osprey-exe-snapshots\mbN-20260729.

**AXIS 1 - vary aggregation N at 82 files (disc @ matched 1% true FDP), toward frontier expPeak ~44,938:**
| agg | matched-TRUE | vs max | step |
|---|---|---|---|
| max | 38,300 | - | |
| best-2 | 43,873 | +14.6% | |
| best-3 | 44,260 | +15.6% | +387 |
| best-4 | 44,469 | +16.1% | +209 |
Diminishing, converging on the frontier (soft approach). Sweep N=6/8/12/20 running (ai/.tmp/sweep-mbN.ps1)
to map the peak + tail. k=1 acceptances deplete with N (639->194->76->31); k=1 FDP% is small-count noise at high N.

**AXIS 2 (queued) - vary FILE COUNT at best-2 to find the worse<->better crossover** (3f=-4.9%, 20f=+2.6%):
bisect ~10 first. Small file counts fit the resident from-parquets path (fast). Informs the auto-N threshold
(crossover moves UP with N). Domain (Brendan): only too-large-N worry = drug-perturbation batches-of-3 where a
real signal is in exactly 3 plates; otherwise larger N just favors reproducibly-quantifiable peptides.


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

**k=1 over-admission slice (crossRun.experiment, the decision bar) - mean(best-2) controls the spike:**
accepted 1-run precursors 639 -> 194 (-70%); their entrapment hits 72 -> 11 (-85%); k=1 slice FDP
20.6% -> 10.9%. The accepted-set run-count histogram shifts from k=1-heavy (max) to k>=2-enriched
(mean-best-2). So the +14.6% net gain comes WITH a large reduction in the leaky 1-run admissions - it is
reproducibility, not just more IDs. `frontier`: peakK=2, bestPeak 42,095 @0.79%. (Tools:
scratchpad/k1_slice.py, dump_crossrun.py.)

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
