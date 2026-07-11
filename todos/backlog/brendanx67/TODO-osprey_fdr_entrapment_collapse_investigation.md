# TODO-osprey_fdr_entrapment_collapse_investigation.md -- Why do decoys + entrapment score at the far-right edge, and why does one file collapse to 0 IDs at 1:1 entrapment?

## Status
**Backlog (created 2026-07-11).** Raised by Brendan while validating Osprey's FDR
control with entrapment on Mike's SEA-AD Pilot-MTG dataset (10-20 of the 82 files for
now; see [[project_sead_pilot_mtg_dataset]]). This is a **diagnosis / root-cause**
TODO, not a fix -- the goal is to understand two linked anomalies the
`--model-diagnostics` entrapment reports surface, before deciding what (if anything)
in scoring / calibration / decoy+entrapment generation needs to change. Related to
[[project_osprey_entrapment_ratio_fdr_collapse]] (the ratio-driven collapse) and the
pass-2 recalibration work ([[project_osprey_pass2_recalibration_inflates_fdr]] / pwiz
#4410), but distinct: those are about the reported-pool null; this is about the
**score distribution itself having high-scoring false members**.

Context: we run **50% entrapment (r=0.5)** because **100% (r=1.0) collapses FDR
estimation entirely.** Mike's initial hypothesis was a Stage-3 failure (RT + mass-error
calibration) on the affected file (see `Osprey-workflow.html`); that did **not** hold up.
So the cause is still open.

## Anomaly A -- one file collapses to 0 IDs at 1:1 entrapment
At r=1.0, file **Astral-SEA-AD_2-MTG-May2026_SEA-AD-0002_7297_A02_006** reports
**0 targets / 0 decoys / 0 entrapment**, while the other 9 files report normally
(26K-43K targets each). Evidence (perFile in the embedded JSON):
`D:\test\Pilot-MTG-Tissue-May2026\runs\seaad-10files-entrapment-r1.0-recheck\seaad.model-diagnostics.html`
```
0001_..._005: targets 35989, decoys 293, entrapment 131
0002_..._006: targets 0,     decoys 0,   entrapment 0      <-- collapsed
0003_..._007: targets 43094, decoys 348, entrapment 167
... (0004-0010 all normal)
```
At r=0.5 the 006 file does NOT collapse (it is in the healthy 20-file run). So the
collapse is triggered by the 1:1 entrapment ratio interacting with something specific
to 006. Mike guessed Stage-3 (RT/mass) calibration failure on 006 -- reportedly ruled
out. Open: what actually zeroes 006's output at r=1.0? (Calibration retry ladder #4402?
A file-specific score/threshold interaction? An empty post-compaction pool for that file?)

## Anomaly B -- decoys AND entrapment score at the far-right (high-score) edge
Normally the top of the score ranking is a clean run of pure targets -- a score band
with **no decoys and no entrapment** -- and q therefore starts at ~0. Here it does not:
the reported q **never starts near 0** (it is floored at the best-scoring
decoy/entrapment), and the entrapment-measured FDP **spikes at the very top** of the
ranking before settling. Evidence (Pass-1 experiment-wide fdpView, q grid + combined FDP
+ nTargetAccepted):
- r=1.0 recheck: q floored at **0.02503** (nothing < 2.5% q); combined FDP at the top
  = **2.03 (203%)** at nAcc=1, then 6.6%, 3.4%, 2.3% as nAcc grows (11.6K, 23.2K, 34.8K).
- r=0.5 percolator (20-file): Pass-1 q floored at **0.00877** (nothing < 0.88% q);
  combined FDP = **3.02 (302%)** at nAcc=1, then 99%, 59%, 42%, 33% over the first few
  hundred accepted. (Pass-2 floors q much lower, 0.00024, and still spikes at the top --
  the retrain drives q down but does not remove the high-scoring false members.)
  Source: `runs\seaad-20files-entrapment-r0.5-percolator\seaad.model-diagnostics.html`.

This is visible in the 2nd-pass composite-score plot too: the decoy histogram and the
entrapment trace are not confined to the low-score region; a minority of decoy/entrapment
members reach the high-score edge where only real targets should live. That high-scoring
false tail is what floors the achievable q (you cannot get q below the FDP implied by the
best false member) and produces the top-of-ranking FDP spike.

Anomaly A is likely the extreme of Anomaly B: at r=1.0 there are twice as many entrapment
competitors, so a file already prone to high-scoring false members (006) tips over into
a fully entrapment/decoy-dominated top -> nothing passes -> 0 IDs.

## How to work this -- load the /debugging skill first
This is a root-cause investigation, not a code change: **load the `/debugging` skill before
starting** and follow it. Understanding these anomalies will take the two tools that skill
enforces -- (1) **bisection** (isolate 006 alone; bisect the ratio; bisect the pipeline stage
where 006 goes to zero and where the high-scoring false members first appear), and (2)
**adding diagnostic output** to the runs (Stage 1-5 dumps, per-precursor score/label traces
for the top score band, post-compaction pool sizes per file) to zero in on the mechanism.
Do NOT propose a fix until the root cause is established and verified against a change-immune
anchor -- resist "it's probably calibration" (that guess was already made and did not hold).

## Investigation tasks (diagnosis first, no fix committed until understood)
- [ ] **Isolate 006 at r=1.0.** Run 006 alone (or 006 + 1 healthy file) at r=1.0 with
  full Stage 1-5 diagnostic dumps. Confirm/deny Stage-3 calibration (RT + mass error)
  is sane on 006 (Mike's ruled-out hypothesis -- re-verify with the dump, don't trust
  memory). Check the post-compaction pool size for 006: is it empty (0 survivors) or
  is it non-empty but all q > 1%? Where in the pipeline does 006 go to zero?
- [ ] **Characterize the high-scoring false members.** Pull the actual decoy + entrapment
  precursors in the top score band (e.g. top 1% by composite score). What are they --
  specific sequences, charges, RT/mass, fragment counts? Are they a consistent motif
  (e.g. the N-terminal-Met-clip artifacts already flagged in the entrapment warnings:
  "11745 entrapment peptides have no target pair ... AAAAAEEGGEK ... investigate")?
  Are the high-scoring decoys library-supplied or Osprey-generated (libdecoy vs gendecoy;
  see [[project_osprey_libdecoy_vs_gendecoy_calibration]])?
- [ ] **Entrapment library quality.** The r=0.5b/r1.0 entrapment libraries were built by
  subsample (subset-entrapment-ratio.py) + Carafe. Are the high-scoring entrapment
  peptides real foreign-species sequences, or artifacts of the entrapment generation
  (e.g. sequences that collide with real targets, or Met-clip near-duplicates of targets)?
  A high-scoring entrapment that is actually a near-duplicate of a real target is a
  measurement artifact, not a true Osprey false positive -- separate the two.
- [ ] **Ratio dependence.** Sweep is already done (r=0.1/0.5/0.75/0.9/1.0 collapse cliff at
  r=1.0, [[project_osprey_entrapment_ratio_fdr_collapse]]). Tie THIS finding to that:
  is the r=1.0 collapse the same mechanism (high-scoring false members swamping at 1:1)?
- [ ] **Decide the disposition.** Three outcomes are possible and the TODO should end by
  choosing: (a) a real Osprey scoring/calibration bug (high-scoring false members are
  genuine mis-scores -> fix scoring); (b) an entrapment-library artifact (fix the
  entrapment generation / exclude target-colliding entrapment -> the measurement, not
  Osprey, is off); (c) expected behavior of DIA at this depth (some foreign peptides
  genuinely match well -> the FDP is real and Osprey is correctly reporting a hard
  problem). The entrapment oracle only indicts Osprey if (a).

## References
- Data: `D:\test\Pilot-MTG-Tissue-May2026\runs\seaad-10files-entrapment-r1.0-recheck\`
  (006 = 0 IDs), `...\runs\seaad-20files-entrapment-r0.5-percolator\` (q floor + FDP spike).
- Mike's Stage-3 calibration hypothesis: `Osprey-workflow.html` (ruled out -- re-verify).
- [[project_sead_pilot_mtg_dataset]], [[project_osprey_entrapment_ratio_fdr_collapse]],
  [[project_osprey_natural_entrapment]], [[project_osprey_libdecoy_vs_gendecoy_calibration]].
- The entrapment "no target pair / investigate" warnings in every run.log
  (`AAAAAEEGGEK, AAAAGECYPSR, AAAAPCPQFAR ... 11745 excluded`).
