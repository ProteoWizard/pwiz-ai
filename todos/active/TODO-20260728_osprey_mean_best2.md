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

## IDEA (Brendan 2026-07-30): extend mean(best-N) from RUNS to PROTEINS — `mean-2-prot`

`mean-2-prot` = mean of (this peptide's score, the best OTHER peptide of its protein), with the same
decoy mean/median floor when a protein has only one peptide. Brendan: "not at all sure this is a
good idea... but it seems like the fairer starting point for a truly symmetric model".

**Why it is the right instinct.** It does by SCORING what protein-compact does by SELECTION. A
decoy peptide would use its own decoy-protein's best decoy peptide - own data only, no target
conditioning - so it is symmetric by construction in the same way mean(best-N) over runs is. Decoy
proteins are well defined here (the pairing manifest gives decoys their source-protein accessions)
and carry matched peptide complements in a 1:1 library, so TDC validity is plausible.

**Design points to settle first**
- **Leave-one-out is required.** "Best peptide of the protein" must exclude self, else the protein's
  own best peptide boosts a second peptide which boosts it back - mutual inflation. If the current
  peptide IS the best, use the second best.
- Floor: reuse the decoy-median floor for single-peptide proteins, exactly as the 1-run case.
- Protein grouping must be identical in construction for target and decoy (true in libdecoy; check
  gendecoy, where decoys are generated per peptide).
- Peptides of one protein become score-correlated, which double-counts evidence downstream in
  protein-level FDR. Needs thought before it feeds ProteinFdr.

**The argument that does NOT carry over from runs.** For runs, requiring 2 observations is free
because 1 measurement yields no CV or ratio - detection and quant usability coincide. For proteins
that is false: a single well-measured peptide IS quantifiable. So `mean-2-prot` really does cost
sensitivity for single-good-peptide proteins with no compensating quant argument, unlike
`mean-best-2` over runs. That weakens the "not a sensitivity tax" case considerably.

**BLOCKING PROBLEM - we cannot currently validate it.** Entrapment peptides belong to entrapment
proteins that are ABSENT from the sample; real false targets very often belong to proteins that ARE
present. Any protein-level score boosts the second class and not the first, so entrapment stops
representing the false-target population and the oracle UNDER-reports. That is the same blindness as
protein-compact ([[TODO-osprey_selected_null_diagnostics]]), reached through scoring instead of
selection - and it means a favourable entrapment result for `mean-2-prot` would not be trustworthy.
**Design consequence, useful beyond this idea: to audit ANY protein-level prior the entrapment set
must contain false peptides attributed to PRESENT proteins** - i.e. entrapment inserted into real,
detected proteins - not a foreign proteome, which only supplies false peptides in absent proteins
(the easy case). That is a different entrapment design from `fractional-entrapment.md` and should be
built before this lever is measured.

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
      confounds it). Clean A/B = `transfer` (max) vs `mean-best-2`+`transfer`.
      **OBSOLETE (corrected 2026-07-30): do NOT force the resident path.** This line used to read
      "until the streaming mirror lands, also force the resident path: OSPREY_FDR_PROJECTION=0 +
      OSPREY_ALLOW_UNBOUNDED_MEMORY=1". The streaming mirror LANDED in `7c827899a5` (task marked
      [x] above), and the 82-file arm has since run on the streaming path, so flag-on runs need
      NO resident forcing and NO `OSPREY_ALLOW_UNFIXED_RESIDENT` token at all. If a run demands a
      token, that is a signal it is on a path you did not intend - diagnose rather than name it.
      (The blanket `OSPREY_ALLOW_UNBOUNDED_MEMORY=1` is a silent no-op since #4508 regardless.)

## Regression Test
- Flag-off: committed golden byte-identity (regression.ps1). Flag-on: entrapment-oracle A/B is
  decision evidence, not a regression test.

## Progress Log

### 2026-07-31 (night session) - PORTED onto post-#4490 master

`#4490` deleted `PercolatorFdr.cs` and split it into ~10 files, so the 4-commit branch could not
rebase (delete-vs-modify on all 425 FDR lines). Re-landed hunk-by-hunk as ONE commit
(`1d85c1726f`) on `Skyline/work/20260728_osprey_mean_best2`, reset onto master `4641fe4b77`:

| what | new home |
|---|---|
| `ComputeBaseIdMeanBestN` + `MeanBestNAcc` + decoy floor + `PercentileOfSorted` | `Osprey.FDR/TargetDecoyCompetition.cs` (end of class) |
| experiment-precursor + experiment-peptide mean-best-N branches | `Osprey.FDR/PercolatorQValues.cs` |
| `StreamingFirstPassQ` top-N accumulators, `Mb2Entry`, `StreamingDecoyFloor` | `Osprey.FDR/StreamingFdr.cs` |
| `new StreamingFirstPassQ(OspreyEnvironment.MeanBestN)` | `Osprey.FDR/PercolatorScorer.cs:794` |
| flag + `MeanBestN` + floor toggles (+70, unchanged) | `Osprey.Core/OspreyEnvironment.cs` |
| streaming==resident tests | `Osprey.Test/FdrTest.cs` |
| aggregation/floor tests | `Osprey.Test/MeanBestNAggregationTest.cs` (renamed from `PercolatorMeanBest2Test.cs`) |

**Port fidelity was verified mechanically, not by eye** (`ai/.tmp/verify-port.ps1` pattern, script
kept in the session scratchpad): normalize both sides' added lines by stripping the qualifiers the
decomposition forced onto formerly intra-class calls (`TargetDecoyCompetition.`,
`PercolatorQValues.`, `PercolatorSampling.`, `PercolatorEntry.`, `StreamingFdr.`), collapse
whitespace, diff the multisets. Residual = comment re-wrapping plus exactly four intended deltas:
`ComputeBaseIdMeanBestN` `public`->`internal` (host class is internal), `using pwiz.Osprey.Core` in
`StreamingFdr.cs` (needs `OspreyEnvironment`), one `<see cref="ComputeFloorFromDecoyScores"/>` ->
`<c>...</c>` (now private in another class, so the cref would not resolve), and the test-class
rename. **No executable-code difference.** Re-run that comparison before trusting any future
restatement of this port.

Test-file rename rationale: `PercolatorMeanBest2Test` named a class #4490 deleted, and an N the
code stopped being restricted to at `b7c375b905`.

GATES: Debug build + **563/563** + inspection 0 warnings (master 556 + 7 new).
**`regression.ps1 -Dataset All` PASSED** (18/18 legs: Stellar / StellarLibDecoy /
StellarGenDecoyEntrap / Astral x golden, resume, HPC chain, diagnostics). 1 h 48 m, contended.

**PR [#4509](https://github.com/ProteoWizard/pwiz/pull/4509)** opened, label `osprey`. The remote
branch was force-pushed off `2560e04979` (only the 1st original commit was ever pushed, no PR
existed) using `--force-with-lease` pinned to that exact SHA.

**Copilot did NOT review #4509**: "unable to review this pull request because the user who
requested the review has reached their quota limit." So the PR currently has **no independent AI
review**. Re-request it once quota resets, or run `/code-review max` on the branch.

**SELF-REVIEW FINDING, FIXED (`67217afcc9`, 2nd commit on the PR).** Copilot never ran, so I
reviewed the diff myself. `OSPREY_EXPERIMENT_AGG` fell back to the max default SILENTLY on any
unparseable value (`mean-best-1`, `meanbest2`, `mean`). For a flag that exists only to be A/B'd
that is the worst failure mode: the operator records the arm as mean(best-N) and the comparison is
corrupted rather than failed. Added `OspreyEnvironment.ExperimentAggUnrecognized` + a one-line
`ctx.LogWarning` at the head of `FirstJoinTask`'s Stage-5 block, mirroring the
`OSPREY_PASS2_QVALUE` treatment already in the same file. **Warn, not throw**, to match the
established in-repo bar for this class of flag; a hard failure for measurement flags specifically
would be a defensible one-line overrule. Gate re-run: 563/563, 0 inspection warnings.

**FLAG-ON LIVENESS - the gap byte-identity cannot close.** Flag-off byte-identity proves the
default path is untouched, but a flag that was never wired would pass that gate identically. So
`regression.ps1 -Dataset Stellar` was run WITH `OSPREY_EXPERIMENT_AGG=mean-best-2` expecting an
intentional RED, and got one: **74 issues**, `RetentionTimes.score` differing on 894/906 rows,
`OspreyRunScores` 9 keys only-in-golden and 9 only-in-run (the reported set changed membership),
16 `bestSpectrum` rows. The RT / peak-boundary shifts (~0.03 min on a few rows) are NOT aggregation
leaking into peak picking - the experiment-precursor q gates Stage 6 reconciliation and the
calibration refit, so a changed q changes the consensus and can change a 2nd-pass picked peak. That
is the documented contract of `ComputeExperimentPrecursorQMap`. Log:
`ai/.tmp/liveness-meanbest2-20260731.log`. Re-run this whenever the flag is refactored.

### 2026-07-30 (night session) - MECHANISM found; the gain is a TWO-FACTOR product, not a scale law

Autonomous night session (start 21:49). Goal from Brendan: "what causes the loss of sensitivity and
the apparent recovery with mean-N". Running record + timeline:
`ai/.tmp/night-session-budget-20260729.md`. Analysis scripts (re-runnable, all in `ai/.tmp/`):
`mbn_surface.py` (harvest + figure), `mechanism.py`, `perfile_audit.py`, `entrap_k.py`,
`twofactor.py`, `predict.py`, `kcompare.py`, `brief.py`.

**WHY SENSITIVITY IS LOST (mechanism, from fields already in every mdiag).**
`crossRun.perRun.unionFdp` / `cumUnion` / `cumUnionEntrapment` give the accepted union's purity as
files accumulate. The real proteome SATURATES while the null accrues at a roughly CONSTANT rate:
new real precursors per added file fall 920 (F=4) -> 86 (F=82) while new entrapment per file stays
~27-65 throughout. Applying the tool's own FDP estimator to the increment, the marginal file's new
union members go from ~4% false (F<=8) to essentially ALL false (F>=60; the 1:1 estimator saturates
past 100%). A max-of-runs statistic accepts on the strength of ONE good run, so the accepted pool
inherits that collapsing purity and the 1% cut must tighten - which costs IDs in every file. By
F=82, **41.3% of everything detected at run level (union 65,200) fails the experiment cut (38,300)**,
vs 7.0% at F=4. Note the reported q stays CONSERVATIVE at every scale (true FDP 0.77-0.97% at
nominal 1%), so this is a SENSITIVITY loss, not an FDR violation.

**WHAT mean(best-N) RECOVERS.** Acceptance delta by run-count slice (max -> best-2): k=1 is negative
in all 20 cohorts (leaky singletons demoted) and the freed FDR headroom is spent on reproducible
precursors - on k=2 at F<=10 (+957..+1,605) and on k>=6 at F>=40 (+1,578..+3,600 at F=82). The
lever is the threshold shift: substituting mean-of-top-2 for max lowers all scores but lowers the
NULL's more (its highs are single lucky runs), so separation improves and more targets clear 1% q.

**THE TWO-FACTOR MODEL - MODERATE OUT-OF-SAMPLE SKILL, USABLE ONLY AS AN EXTREME-CASE SCREEN.**
Fitted on 20 cohorts, then pre-registered against every later cohort from its MAX arm alone (both
factors are max-arm quantities, so no refit): 7 tests, errors +4.0 (28f), -5.0 (20+60), +1.1
(10+10), -1.1 (10+30), -1.5 (10+50), -3.2 (40+20), -1.3 (40+30). **Mean |err| 2.5 pts, worst 5.0,
out-of-sample Spearman ~0.54.** It is unreliable in the middle of the range, but it flagged BOTH
extreme cohorts in advance - contiguous-28 (+14.4% actual) and files 31-70 (+12.9% actual), each
~4x its neighbours. So do NOT quote it as an effect-size predictor; it may be worth keeping as a
cheap screen that says "this cohort is a large-recovery candidate" from the max arm alone. (An
earlier entry called it outright falsified after only the first two tests - that was premature.)
  A = share of accepted FALSE hits resting on a single run  (the removable population)
  B = (union - accepted) / union                            (reservoir available to backfill)
Over 20 cohorts: A alone Spearman +0.55, B alone +0.16, **A x B: Pearson +0.79 / Spearman +0.75**,
fit `gain% = 82.8*(A*B) - 1.24`, mean |residual| 1.85 pts. Both factors read off the MAX arm, so
`predict.py` pre-registers a prediction before each cohort's best-2 arm lands (out-of-sample, not a
refit). This explains why EVERY single-factor predictor failed (all |rho| <= 0.22: run count,
k=1 leakage, reservoir, union FDP, model Delta-mu, max efficiency) - a cohort can have removable
leakage but no reservoir (spread21 A .32/B .22 -> +1.8%) or both (82f A .41/B .41 -> +14.6%;
spread17 A .52/B .23 -> +11.8%). Residual: F=5/6 under-predicted by ~3.7 pts.

**Cohort-structure facts established tonight** (all disc @ matched 1% true FDP):
- WITHIN-SIZE VARIANCE IS SOMETIMES HUGE - the single most important caveat for any effect-size
  claim. Four disjoint 20-file cohorts were tight (+2.6 / +2.5 / +2.7 / +3.8%, spread 1.3 pts) and
  four 10-file cohorts moderate (+7.9 / +5.3 / +6.3 / +4.2%, spread 3.7 pts), but FIVE ~40-file
  cohorts spanned **+2.9 / +3.3 / +12.9 / +5.6 / +4.0%** - a 10-point spread at fixed size, as
  large as anything attributable to size. (An earlier entry called fixed-size behaviour
  "essentially deterministic" off the 20-file quartet alone; that was luck of the draw.) Any single
  cohort's number - including the 82-file +14.6% - is one draw from a wide distribution.
- **FINAL SIZE CURVE (81 arms, 35 cohort comparisons, replicates at 6 sizes -
  `CohortAnalysis/sizecurve.py`)**: F=5 n=4 mean +7.0% (+5.4..+8.8) | F=10 n=4 +5.9% (+4.2..+7.9) |
  F=12 n=2 +4.7% | F=15 n=2 **+5.0/+5.0** | F=20 n=4 +2.9% (+2.5..+3.8) | F=40 n=3 +6.4%
  (+2.9/+3.3/+12.9) | F=60 n=2 +4.3% | F=75 n=2 +8.5% (+6.7/+10.3) | F=82 n=1 +14.6%.
  Median **+5.6%**, range +1.8..+14.6%.
  - A real MINIMUM near 20 files: the four 20-file cohorts sit entirely below the two 15-file and
    four 5-file cohorts with no overlap, so the small-cohort hump replicates and is not noise.
  - **The number to quote when anyone cites a single cohort**: the largest within-size spread
    (9.9 pts at F=40) EXCEEDS half the total range across all sizes (6.4 pts). Cohort composition
    matters more than cohort size.
- UNION EFFICIENCY is the cleanest cross-cohort summary (share of run-level detections surviving
  the experiment cut; the union is aggregation-independent so sizes are comparable):
  F=4 93.0% -> 95.6%, F=20 79.6% -> 81.6%, F=40 74.2% -> 76.4%, F=60 70.6% -> 74.6%,
  F=75 63.3% -> 69.8%, F=82 58.7% -> 67.3% (max -> best-2). **Scale costs ~34 points of efficiency;
  mean(best-2) recovers 1.4-10.4 of them.** The loss is large and mostly UNADDRESSED - a better
  framing for the paper than any single gain percentage.
- REJECTED: "best-2 is a stabiliser". The nested contiguous series looked like it (max 46,496 /
  41,623 / 45,832 / 47,290 at 20/28/30/40 files vs best-2 47,685 / 47,617 / 48,431 / 48,672), but
  normalised by the union across 21 cohorts the scatter is identical (max/union sd 8.11 vs
  best2/union sd 8.15). F=28 is a local anomaly where max dipped and best-2 held.
- Run count is NOT the driver: at constant content span (every 5th/4th/3rd/2nd/all) the series is
  +11.8% (17f) / +1.8% (21f) / +7.4% (28f) / +4.0% (41f) / +14.6% (82f) - non-monotone, neighbours
  differing 6-10 pts.
- Size alone is NOT the driver either: contiguous-17 = +5.2% vs spread17 (same size, spread across
  the acquisition) = +11.8%.
- Rejected: "adjacent runs repeat their interferences" - the entrapment k>=2 share supports it only
  for the 17-file pair (+20.4 pts), not 20/21 (-2.6) or 40/41 (+1.9).
- NEGATIVE RESULT, do not retry: the `frontier` block is NOT a usable upper bound (`expPeak` differs
  between the max and best-N arms of the same cohort, and 4 cohorts sit ABOVE their own frontier -
  it is scoped differently from the fdpView). **The earlier "43,873 = ~85% of the way to the 44,861
  frontier" line in this TODO compares incommensurate quantities and should not be repeated.**
- Diagnostics gap worth filing: `scores.decoyMean` is byte-identical between max and best-N arms in
  every cohort, i.e. the score histogram is the per-precursor raw best score. The mdiag never shows
  the AGGREGATE score distribution that the experiment q is computed from.

**Headline framing for the paper/default decision**: gains span +1.8% to +14.6% (median ~+5.7%,
n=28 cohorts) with only F=3 negative (-4.9%) - asymmetric payoff, as Brendan put it: rarely
harmful, sometimes a large recovery. **The +14.6% is one draw and even the LARGE-cohort magnitude
does not reproduce**: three cohorts at 75-82 files give **+6.7% / +10.3% / +14.6%**, and the two
75-file sets differ by 3.6 points despite 91% file overlap (files 1-75 donors-only +10.3%; files
8-82 +6.7%). Quote "roughly +7 to +15% on large cohorts, ~+3-6% typical, one cohort's number
unreliable to +/-4 points" - never the maximum alone.

**Out-of-sample record of the A x B screen, final: 9 tests, mean |err| 2.6 pts, systematic -1.4 pt
over-prediction, worst 5.0.** It called both extreme highs in advance (28f, files 31-70) and both
75-file cohorts within 2.8 pts. Screen, not estimate.

**Next session handoff**: For the detailed startup protocol, read
`ai/.tmp/handoff-20260728_osprey_mean_best2.md` before starting work. It covers BOTH threads this
session touched - this branch (mean(best-N), PR-ready) and the pass-2 default decision
(TODO-20260727), where a one-line regression in shipped master is now the top action.

**PROTEIN ROLL-UP - deliberately NOT implemented tonight.** Brendan's design (add
`double? AggregateScore`; protein path takes `Max(AggregateScore ?? Score)`; the peptide code stamps
it when mean(best-N) is active; null default keeps flag-off byte-identical) runs into a wrinkle I
had not noticed: the field would go on `FdrEntry` (`Osprey.Core\FdrEntry.cs:33`), which is
documented as mapping to Rust `osprey-core/src/types.rs FdrEntry`, so it is a cross-impl parity
type (see the side-by-side preservation note in memory). A C#-only nullable that is never
serialized is probably safe, but "probably" plus no `regression.ps1 -Dataset All` gate (the machine
was saturated with measurement arms all night) is not a combination worth committing unattended.
Morning task, ~20 min with the gate free: decide the parity question, add the field, stamp it in
the peptide roll-up, `Max(AggregateScore ?? Score)` in `ProteinFdr.ComputeProteinFdr`, unit test,
then the gate.

### 2026-07-29 (evening) - REVISION: the "gain grows with N" trend does NOT survive the filled-in middle

Brendan asked for the missing 30/40 file counts before trusting the 20f -> 82f jump. Filling them
in (plus F=60) **contradicts the recorded monotone-growth conclusion**. best-2 vs max at matched
1% true FDP, all cohorts measured so far:

| F | 4 | 5 | 6 | 8 | 10 | 12 | 20 | 30 | 40 | 60 | 82 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| gain | +2.8% | +8.8% | +9.5% | +7.4% | +7.9% | +3.6% | +2.6% | +5.7% | +2.9% | +5.7% | **+14.6%** |

**F=4 through F=60 sit in a flat 2.6-9.5% band with no trend in F. F=82 is an outlier, not the end
of a ramp.** The earlier "N=3 -4.9% -> N=20 +2.6% -> N=82 +14.6%, the advantage grows with run
count" reading came from three anchors with a 60-file hole in the middle; the hole is now filled and
it is flat. DO NOT restate the growth claim. New arms: F=30 max 45,832 / best-2 48,431; F=40 max
47,290 / best-2 48,672; F=60 max 41,314 / best-2 43,654.

**Why F=82 differs is now the whole question.** It is uniquely mis-calibrated in the max arm: true
FDP 0.918% at 1% reported q (every other cohort 0.77-0.88%) and a k=1 slice FDP of 20.6% (elsewhere
7-10%). Over F=60 it adds exactly the 7 pooled QC injections plus the last ~15 (most drifted) donors.

**ROOT CAUSE of the cohort confound: this dataset drifts hard across its acquisition series, and
`-NumFiles F` takes the FIRST F files by name, which is also the EARLIEST (best) F acquisitions.**
The 7 QC pools are the same sample injected 7 times across the series and their passing targets fall
monotonically 23,472 / 23,855 / 23,731 / 17,842 / 15,598 / 14,012 / **10,882** (acq order 009->098) --
pure instrument/column degradation, >2x. Files 1-40 pass a median 27,074 targets vs 19,173 for files
41-82 (-29%; 19,269 excluding pools, so it is not just the pools). The pools sort to positions 76-82,
so they enter ONLY the 82-file cohort. Cohort SIZE and cohort QUALITY are therefore confounded in
every F-trend measured to date.

**Second finding: the trained first-pass model varies 3x in quality, NON-monotonically with F.**
`modelComposite` (FeatureContributions.cs:287 = Delta-mu of the composite score, i.e. target-decoy
separation): 0.156 (F=20), 0.245 (30), 0.237 (40), **0.077 (60)**, 0.163 (82). Per-file run-level
passing (a clean control - run q is computed WITHIN a file, so the only cross-file channel is the
shared model; mean-best-N leaves it byte-identical) tracks it exactly: 20->40 **+0.5%** (no cost),
40->60 **-13.6% with 40/40 files losing**, 60->82 **+5.9% with 0/60 losing**. So adding files 41-60
craters the shared model for every file and 61-82 partially repairs it. The uniformity across files
means the symptom is global (shared model), NOT a few files dragging an average - though a few files
could still be the cause of the model damage.

**Model weakness is NOT the mechanism for the gain**: F=60 has the worst model (0.077) and F=30 the
best (0.245), and both give exactly +5.7%. Killed that confound.

Tooling (all re-runnable, no new runs needed): `ai/.tmp/mbn_surface.py` (generic arm discovery from
directory names -> tidy CSV + the 4-panel figure incl. the k=1 mechanism panel),
`ai/.tmp/perfile_audit.py` (per-file outliers + cohort-step contamination), `ai/.tmp/cohort_split.py`
(pools vs donors, acquisition halves), `ai/.tmp/model_health.py` (Delta-mu per cohort).
`Run-SeaAd.ps1` gained `-SkipFirstFiles`, `-EveryNthFile`, `-ExcludePattern` (all dry-run verified) so
cohorts can be drawn at matched size but different content.

**IN FLIGHT (single serial driver `ai/.tmp/run-interactive-queue.ps1`)**: files 41-82 as a 42-file
cohort (matched size vs F=40, degraded content); `spread41` = every 2nd file (matched size, spans the
whole acquisition); `nopool75` = 82 minus the 7 pools (does the headline collapse without them?).
Whatever they say, the claim must be conditioned on cohort character, not run count.

PROCESS NOTE: two bugs in my own queue scripts cost ~10 min of machine time - an UNANCHORED wait
sentinel ('GRID ALL DONE' matched the waiter's own "waiting for 'GRID ALL DONE'" log line, so the
wait fell through) and a blanket `Get-Process Osprey | Stop-Process` that killed an unrelated
in-flight arm. Both fixed (anchored `^=== ... ALL DONE`, kills scoped to the arm's own output-dir
tag) and all probes now run from ONE serial driver - no cross-process coordination.

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
