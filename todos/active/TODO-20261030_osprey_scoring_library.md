# TODO-20261030_osprey_scoring_library.md - Phase 3

## Branch Information
- **Branches** (local in `D:\Users\brendanx\proj\pwiz-nightbase`, NOT pushed; nothing to GitHub until Brendan says):
  - `Skyline/work/20261107_osprey_protein_best_n` - 0288321816, OSPREY_PROTEIN_BEST trial (first pass only)
  - `nightlywork/20261107_refit_bandwidth` - 4eda4a820a refit bandwidth fix, 06e3c9a131 OSPREY_RECON_REFIT=off
  - `nightlywork/20261107_protein_best_pass2` - e8e5beda58 merge of the refit branch, c213f37184 PROTEIN_BEST through pass 2
  - all from c0c2bcd43c (#4950 head after #5005)
- **Base**: #4950 (`Skyline/work/20261028_osprey_diann_fdr_gap`); the eventual PR may go into #4850 (Brendan)
- **Module**: `osprey`
- **Created**: 2026-10-30; **Phase 3 started**: 2026-11-07
- **Status**: Protein evidence in training (OSPREY_PROTEIN_BEST) plus a transfer-based pass 2 with the reconciliation
  refit off is the best Osprey configuration on the placement-split audit: 5-6% behind DIA-NN final on 3 files with
  reported FDP honest (0.91%). 62- and 82-file confirmation in flight. Expect 1-2 more PRs.

## Phase History
- [Phase 1](TODO-20261030_osprey_scoring_library-phase1.md) (2026-10-30 to 2026-11-03): the candidate-score library
  (median polish, reference correlation, peak profile, time correlation, isotope/tight, dominance, top-3, wide-span),
  the two tight valuing loops, the classifier work (GBDT speedup and DeterministicMath, out-of-fold scoring, two-round
  training), the protein-shuffle entrapment audit. PRs #4967, #4968 (master), #4969 (into #4950).
- [Phase 2](TODO-20261030_osprey_scoring_library-phase2.md) (2026-11-03 to 2026-11-07): fragment tolerance diagnostics and
  correlation XICs, the protein-compact complement fix and goldens, weak-peak scoring (reference XIC, local RT window,
  shadow features), spectrum-match and library-agreement families, the 82-file A/B/C comparison. PRs #4992, #4998,
  #5005 (into #4950), #4993 (master).

## Goal (phase 3, Brendan 2026-11-07)
Close the remaining gap with a statistically defensible use of protein evidence, measured by the #5011 placement-split
audit, and a second pass that does not lose first-pass detections. Candidates: OSPREY_PROTEIN_BEST (protein-best-N
column in round-2 training, decoys reading their paired target's protein), the transfer pass 2 (Brendan's long-standing
preference: it never recompetes, so it needs no special audit to justify), experiment-wide aggregation
(OSPREY_EXPERIMENT_AGG=mean-best-N) at 62-82 runs, and an experiment-wide qualify gate for protein-compact. Brendan
(2026-11-07): about 5% behind DIA-NN is close enough for a first Osprey beta, given a start more than 50% behind.

## Standing rules for this phase
- Read every number on the on-target half of the split (combined estimator e(1+1/r)/(t+e)); own-protein entrapment
  collapses under any protein-aware step and is not an FDP reading.
- Never quote an Osprey vs DIA-NN gap without stating how entrapment is annotated in the library (Carafe's
  per-peptide `_pepNNNNN` accessions vs real protein grouping). Closed-release DIA-NN analysis stays in
  `U:\tools\claude\diann-study\`.
- First-pass variants run as `-Task FirstPassFDR -LinkFrom <scored run>` on hard links (~30 min at 62-82 files).
- `Run-SeaAd.ps1` strips caller-set OSPREY_EXPERIMENT_AGG (and the other levers in OspreyDatasetRun.psm1 ~1022);
  pass `-ExperimentAgg mean-best-N`. Confirm every lever in run.log's "Environment switches" / `[PATH]` lines.
- Log each finding here and push pwiz-ai as it lands.

## Note from the entrapment-in-target-proteins session (2026-11-07, Brendan asked it be left here)
Please review `TODO-20261106_carafe_entrapment_in_target_proteins.md` (PR #5011, branch
`Skyline/work/20261106_carafe_split_entrapment`, now stacked on #4823's branch) before measuring a transfer-based pass 2.
What it gives you for testing a pass 2 that does not recompete:
- **The oracle.** `--model-diagnostics` now splits the entrapment FDP by protein placement (entrapment on real target
  proteins vs on its own proteins) and adds a protein-group FDP card. A pass with no protein information gives the two
  halves the same curve (pass 1 does: 106 vs 123 at q 1% on 3 files). protein-compact pass 2 reads 184 on target proteins
  (1.10%) vs 11 own (0.07%) while the standard design reports 0.07%: that gap is what recompeting against the depleted
  null buys. Success criterion for your transfer-based pass 2: the halves stay together in pass 2 with the yield held
  (51,384 targets at q 1% on the first 3 SEA-AD files). Any first-pass protein-evidence feature (#4580) must reach decoys
  through their paired target's protein, or the halves separate one pass earlier.
- **Libraries** (D:\test\osprey-runs\sea-ad\lib on BRENDANX-UW25; derive your own elsewhere with
  `ai/scripts/Osprey/Library/Build-ProteinShuffledEntrapment.py --in-targets 0.5` on any Carafe-layout library):
  `target+decoy+entrapment-arabidopsis-split` (1:1, half on target proteins), `-r0.2-split` (10% + 10%), unsplit twins.
  The Carafe-built Arabidopsis library has 82 merged decoy/target rows the libdecoy loader refuses; they are dropped from
  these manifests (`find-merged-rows.py` in the session folder does it for another copy).
- **Reader**: `read-placement.py <run dir>` (C:\proj\ai\.tmp\sessions\20261106-carafe-entrap) prints both passes at q 1%
  from the stored products; no HTML needed. Exe snapshots there: `_bin\split-entrap-20261106`, `_bin\before-4993`,
  `_bin\stack-4823-5011`.
- **Numbers to beat/keep** (3 files, 1:1 split): before #4993 pass 2 219 on targets / 73 own, 67 entrapment-only protein
  groups; after #4993 184 / 11, 5 groups; with #4823 stacked the precursor level is unchanged and the protein card gets a
  real q axis (3,887 groups at protein q 1%, 2 entrapment-only vs 19 expected).
Open questions you may hit: (1) 1:1 split vs unsplit differ in pass 1 (34,682 vs 33,978 targets on one file) where the
20% pair is bit-identical; cause unknown, so compare split against split. (2) Brendan's proposal: choose any protein
stratum by a pass-1 protein q from the full-library picked-protein competition, never by target-peptide counts or
per-run q (#4581); a transfer design that never recompetes sidesteps it. (3) Under #4823 a precursor's peptide q can
exceed its precursor q (picked-peptide, best against best by base id); intended, filter at the level you mean.

## Progress log

### 2026-11-07 - Protein evidence (OSPREY_PROTEIN_BEST), pass-2 refit root cause, 3/62/82-file placement audit
Session folder `ai/.tmp/sessions/20261104-night` (library builders `lib_*.py`, readers `read_sized.py`, `read_refit.py`,
`onehit_sized.py`, `read_fdr_sidecar.py`, `read_pb62.py`, chains `pb62-chain.ps1`, `pb62-mb2.ps1`, `s82-chain.ps1`);
runs under `D:\Users\brendanx\test\osprey-runs\sea-ad\runs-pb` (MACS2); minute-by-minute log `ai/.tmp/night-session-budget-20261107.md` (MACS2, not committed).
All numbers are real targets at entrapment FDP 0.5% / 1% read on the on-target half of the split (combined estimator
e(1+1/r)/(t+e)), "q1" = entrapment FDP at reported q 1%. B env: OSPREY_XIC_FRAGMENTS=12, FDR_MODEL=gbdt, LOESS_BANDWIDTH
0.10, MIN_RT_TOLERANCE 1.0, GBT_OOF=1, GBT_PREFILTER_SIZE 200000, TC_HALF_WINDOW 0.40, CORR_FRAGMENT_TOLERANCE 7,
REF_XIC=corr, LOCAL_RT_TOLERANCE 15, FDR_SEED 1, FEATURE_MASK none.

**Comparing with DIA-NN.** The Osprey vs DIA-NN gap depends on how entrapment is annotated in the library (Carafe's
per-peptide `_pepNNNNN` accessions vs real protein grouping); never quote a gap without stating it. Bisection detail
is kept privately. Osprey pass 1 uses no protein information (bit-identical across label variants).

**Audit design.** #5011 split: half the entrapment moved onto target proteins, half on its own proteins. The on-target
half is the auditable reading; the own half collapses under any protein-aware step. The uniform draw by accession
under-reads protein boosts: target peptides land on detected proteins 38.7% vs moved entrapment 31.3% (1.24x;
`placement_bias.py`). Size-weighted variant (`lib_split_entrap.py --sized`, draw proportional to a protein's target
peptides) corrects it: `D:\Users\brendanx\test\osprey-runs\lib\astral\target+decoy+entrapment-20260817-split-sized`.
Pass 1 off is identical on both libraries (control).

**Pass-2 loss root cause (CalibrationRefit).**
- `CalibrationRefit.Refit` hardcoded LOESS span 0.3, ignoring OSPREY_LOESS_BANDWIDTH=0.10. The refit missed the gradient
  end by +0.5 to +1.4 min after 20 min; 6,217 real pass-1 IDs were force-integrated at the wrong RT and floored above q 1%
  (5,845 elute >= 17 min); only 43 entrapment lost.
- Fix 4eda4a820a (`nightlywork/20261107_refit_bandwidth` from c0c2bcd43c): `Refit(..., double bandwidth =
  DEFAULT_BANDWIDTH)`, planner passes `config.RtCalibration.LoessBandwidth`; test
  TestRefitFollowsGradientEndAtConfiguredBandwidth; gate 679/679, inspection 0. Transfer 58,568 / 62,704 -> 61,860 /
  66,040; protein-compact 63,962 / 68,989 -> 67,404 / 72,648.
- Residual: 2,665 still moved at the late bend (refit residual 0.2-0.3 min at 18-22 min vs the 0.1-min tolerance floor),
  231 same-apex score changes (pass-2 rescoring uses the fold-mean model, pass 1 OOF), ~180 from the coarse score-to-q
  table near 1%.
- 06e3c9a131 OSPREY_RECON_REFIT=off (throws on other values): plan reconciliation with the first-pass calibration.
  Transfer pass 2 then equals pass 1 (64,556 / 68,644 vs 64,312 / 68,600): the loss is gone. Gate 679/679.
- Open: whether the refit earns its place at all; if kept, it needs a span that follows the gradient end.

**OSPREY_PROTEIN_BEST** (Brendan's protein-best-N proposal).
- Round-2 GBDT column through the prefilter seam (`TrainWithScorePrefilter`; needs gbdt and OSPREY_GBT_PREFILTER_SIZE):
  per protein, max (or mean of top N) of round-1 scores. OSPREY_PROTEIN_BEST=max|mean-N, _DECOY=paired|own, _SHUFFLE.
- Decoys must read their PAIRED target's protein evidence. "own" collapses FDR; shuffle control flat.
- Trial 0288321816 on `Skyline/work/20261107_osprey_protein_best_n` (`Osprey.FDR/ProteinBestFeature.cs` + tests).
  Through pass 2: e8e5beda58 (merge of the refit branch) + c213f37184 on `nightlywork/20261107_protein_best_pass2`,
  gate 682/682; per-run sidecar `<stem>.1st-pass.protein_best.bin` (OSPRYPBC v1, entry_id -> value, plus floor).
  Rescored rows use the persisted value; rows without one and all gap fills get the floor.
  **Decision for Brendan**: the gap-fill floor (conservative choice).
- Decoy origin (`read_fdr_sidecar.py`, `results_summary.txt`, 3 files, q <= 1%): own-protein entrapment 124 -> 11 and its
  decoys 204 -> 30 together; the entrapment share in the top N of the own pool is unchanged, so the collapse of the own
  half is symmetric and decoy competition stays fair there. The decoy budget moves into the detected stratum
  (target decoys passing 276 -> 456; target:decoy 243 -> 165).
- Exe snapshots: `_bin\n1107-proteinbest` (trial), `n1107-refitbw`, `n1107-norefit`, `n1107-pb-pass2` (all features),
  `n1106night-b` (baseline B, contains #4993).

**3 files, size-weighted split** (`read_sized.py`):

| Arm | FDP 0.5% / 1% | q1 FDP |
|---|---|---|
| DIA-NN final (aggregate, for scale) | 73,765 / 78,666 | 0.59% |
| PB max + transfer, no refit | 69,060 / 74,643 | 0.91% |
| PB max + protein-compact, no refit | 69,001 / 74,413 | 1.47% |
| PB max, pass 1 | 68,700 / 74,378 | 1.03% |
| protein-compact, no refit | 68,465 / 73,918 | 1.55% |
| protein-compact, refit bandwidth fixed (uniform split) | 67,404 / 72,648 | 1.30% |
| today's default (protein-compact, old refit) | 62,309 / 67,721 | 1.42% |
| pass 1 off | 65,656 / 69,794 (uniform) | |

Only PROTEIN_BEST arms report at or under 1%; protein-compact overshoots by ~50% at q 1%, consistent with its
per-run q < 1% union stratum hiding false discoveries. PB + transfer is 6.4% / 5.1% behind DIA-NN final. Transfer is
the pass-2 design that never recompetes, so it needs no new audit method to justify it (Brendan: the long-standing
preference; #4823 and #5011 are what make it the clear answer).

**One-peptide proteins** (`onehit_sized.py`, matched on-target FDP 1%, final): baseline 2,373 real proteins with one
peptide; PB + transfer still detects 68.5% of them, protein-compact 51.4%. Real proteins detected 8,556 / 7,865 / 7,518
(baseline / PB / protein-compact). Uniform split at q <= 1%: 2,263; 74.8% vs 54.0%. PB costs fewer singletons than
protein-compact but still costs some; size normalisation (#4580) may help.

**62 files, uniform split, pass 1** (`read_pb62.py`; the 82-file baseline ran out of disk after scoring files
0001-0062, so each arm is FirstPassFDR on hard links to those 62 score files, ~30 min each):

| Arm | q 1% targets | q1 FDP | own at q1 | FDP 0.5% / 1% |
|---|---|---|---|---|
| off | 84,576 | 0.69% | 192 | 81,828 / 87,738 |
| PB max paired | 96,321 | 1.02% | 10 | 89,931 / 96,209 (+9.9% / +9.7%) |
| PB mean-3 paired | 96,475 | 0.98% | 11 | 90,190 / 96,663 (+10.2% / +10.2%) |
| mean-best-2 (`-ExperimentAgg`) | 86,017 | 0.69% | 172 | 83,361 / 89,266 (+1.9% / +1.7%) |
| mean-best-2 + PB max paired | 97,012 | 1.05% | 13 | 89,848 / 96,413 (+9.8% / +9.9%) |

The PB gain grows with run count (3 files: +4.6% / +6.6% sized) and reported FDP holds. mean-best-2 alone adds
+1.9% / +1.7% at unchanged FDP, and with no protein information its two placement halves stay together (199 on
target vs 172 own). mean-best-2 + PB adds nothing over PB alone: PB already takes the gain mean-best-2 found.
To confirm on the sized split and at 82 files.

**Own-protein half = the standard FDRBench reading** (Wen et al., Nat. Methods 2025, entrapment on its own
proteins; `read_pb62_own.py`, combined estimator with r = 0.5 per half, r = 1.0 pooled). FDP at q 1%:

| Arm | on-target half | own half | both halves pooled |
|---|---|---|---|
| off | 0.69% | 0.68% | 0.91% |
| mean-best-2 | 0.69% | 0.60% | 0.86% |
| PB max paired | 1.02% | 0.03% | 0.70% |
| PB mean-3 paired | 0.98% | 0.03% | 0.68% |
| mean-best-2 + PB max | 1.05% | 0.04% | 0.73% |

With PB the standard reading reports FDP 30x below the reported q (own find rate at "1% FDP" 121k vs the honest
96k), and a pooled library hides the on-target 1.02% as 0.70%. PB is therefore invisible to the standard method:
only the split reading audits it. For scale, DIA-NN (3 files, uniform split, final) keeps own 83 vs on-target 160
at q1, about 1:2; Osprey PB keeps 10 vs ~330, about 1:33. Without PB Osprey is 1:1 (192 vs ~196).
Own:on counts by q (`read_pb62_counts.py`): off 1:1.0 at every q from 0.5% to 5%; mean-best-2 1:1.2 / 1:1.0;
PB max 1:77 at 0.5%, 1:33 at 1%, 1:11 at 5%; mean-best-2 + PB 1:43, 1:28, 1:9 (own 12 vs 10 at 1%, 214 vs 181 at
5%). PB sets the ratio; mean-best-2 softens it slightly without changing the find rate.

**Decision (Brendan, 2026-11-08): PB on by default, with a documented switch to turn it off.** Reason: PB is the
same score the protein-level competition uses, applied through paired decoys, and the #5011 split audits it
(own half = protein-level question, on-target half = peptide-level). DIA-NN has no such switch; its protein use only
showed when one-peptide-per-protein Carafe labels disabled it. To do when promoting: a real CLI/config option (not
only the env var), the active setting in run.log and in the output metadata, and a test that off reproduces the
pre-PB results bit for bit.

**What the PB column is (read from `ProteinBestFeature.cs`, 2026-11-08), and where it differs from the
protein-level competition score.** Per run, from round-1 scores: each peptide reduced to its best row (all charges,
all candidate peaks); a candidate reads max (or top-N mean) over the OTHER peptides of its protein, own peptide
excluded; no sibling -> floor = median of the run's decoy precursor best scores; shared peptide -> max over
accessions. Paired decoy: reads exactly its target's value (decoy scores never enter). So the column is identical
within each target/decoy pair: it sets a per-pair prior, not a target-vs-decoy signal. Differences from protein
FDR: self excluded, per run not experiment-wide, decoys do not form decoy proteins. Consequences to measure: (1)
one-peptide proteins always read the floor, which is below what an absent multi-peptide protein reads (max of k
noise siblings rises with k) - consistent with PB + transfer keeping 68.5% of baseline singletons; (2) size bias
for absent large proteins. Candidate fixes: no-sibling rows as missing / a sibling-count column, size-normalised
value (#4580).

**62 files: PB costs proteins** (`onehit62.py`, q <= 1%, real proteins = target-class peptides): off 9,216 proteins
(2,467 one-peptide), PB max paired 8,628 (1,859): -6.4% proteins while precursors rise ~14%. PB keeps 68.1% of the
baseline one-peptide proteins, loses 849 proteins overall, gains 261 (on-target FDP 1%: 63.2%, lost 1,050). The gain
lands on already-detected proteins (5+ peptides 4,289 -> 4,633). Shape arms running 2026-11-08 03:30
(`pbshape62.ps1`, exe `_bin\n1108-pbshape`, `OSPREY_PROTEIN_BEST_SHAPE`=nosib | size | size-nosib, local commit 39fc1b55fe on
`nightlywork/20261107_protein_best_pass2` in pwiz-nightbase; ProteinBestFeatureTest passes).

**Shape nosib = floor, bit for bit** (`pb62-max-nosib`, fdrbench.tsv md5 705c3863... identical to
pb62-max-paired). Not a dead switch: run.log shows `Shape: nosib` and the stored column
(`read_pbsidecar.py` on `<stem>.1st-pass.protein_best.bin`) holds the sentinel. Almost nothing has no
scored sibling: 1,334 of 4,403,242 entries in A01_005 (1,408 of 3.95M in A04_008), and the floor of a floor run
(-13.9 in P2-pb-pc A01_005) already sits near the 0.1% quantile of real values, so floor and sentinel share
the GBDT's lowest bin and the trees are the same. The one-peptide loss is therefore not about proteins with no
library sibling; a protein detected by one peptide still has unscored-but-present siblings whose max is noise.
That is the size question, which the size arms test.

**Shape size does not recover proteins either** (`pb62-max-size`, F_decoy(max)^k, no sibling 0.5): 96,059
targets at q 1% (paired 96,321), FDP on 1.03% own 0.05% pooled 0.72%, on-target find 88,756/95,748 at 0.5/1%
(paired 89,931/96,209); real proteins 8,625 (paired 8,628), one-peptide 1,866, 68.1% of baseline one-peptide
proteins kept. The column's growth with protein size is not what costs the proteins.

**Most of the protein loss is false proteins** (`entprot62.py`, q <= 1%). Own-protein entrapment proteins are
absent by construction and sit at r = 0.5 per target protein: off 190 detected (188 one-peptide), PB paired 10,
PB size 15. Estimated false target proteins: off ~380 of 9,216 (~4% protein FDP), PB ~20 of 8,628. So of the
net -588 proteins, ~360 are false proteins removed and ~230 are real proteins lost (~2.6% of real proteins);
one-peptide: ~2,090 real -> ~1,840 (~-12%). Estimate assumes own-entrapment proteins match absent target
proteins in size; on-target entrapment cannot test this (its peptides sit on detected proteins).

**Method note (Brendan).** Everything varied here (PROTEIN_BEST, OSPREY_EXPERIMENT_AGG=mean-best-N, a future qualify
gate) acts inside FirstPassFDR, so once one baseline is scored each variant is `-Task FirstPassFDR -LinkFrom <run>`
on hard links: ~30 min at 62-82 files instead of 6-8 h.

**Disk.** The split library nearly doubles candidates (6.18M per file): ~3.9 GB of scores per file, the same again
reconciled in pass 2. Freed ~1.4 TB on D: (now ~1.4 TB free): unregistered the WSL distro OspreyLinux (CHS 446-file
and SEA-AD Linux runs; logs, diagnostic HTML, stats and protein groups in
`D:\Users\brendanx\test\osprey-runs\_archive\wsl-OspreyLinux`; rootfs tarball kept in `D:\WSL`), deleted the TDP-43
.raw on D: (spectra.bin on E:) and this session's 3-file parquets.

**Harness bug found and fixed (23:30 PST).** The first 62-file mean-best-2 arms were set by exporting
OSPREY_EXPERIMENT_AGG, which `Run-SeaAd.ps1` strips (run.log: `[PATH] experiment-agg: max`; fdrbench byte-identical
to off). Both arms were removed and rerun with `-ExperimentAgg mean-best-2` (run.log now `experiment-agg: mean-best-2`).
OSPREY_PROTEIN_BEST and OSPREY_RECON_REFIT are not stripped (listed in run.log's Environment switches), so the PB and
no-refit results stand.

**In flight (2026-11-07 23:40 PST).**
- `pb62-mb2.ps1` (log `runs-pb\pb62.log`): 62 files, uniform split, FirstPassFDR on links: mean-best-2 alone, then
  mean-best-2 + PB max.
- `s82-chain.ps1` (log `runs-pb\s82.log`), waits for PB62MB2DONE: 82 files, size-weighted split, refit off, one exe
  `_bin\n1107-pb-pass2`: baseline (all stages, protein-compact pass 2), then FirstPassFDR-only mean-best-2 and
  mean-best-2 + PB (`-ExperimentAgg`), then transfer, PB + transfer, PB + protein-compact (Stage 5 onward on links;
  reconciled parquets dropped after each arm's pass-2 FDRBench). Baseline ~8 h, whole chain ~12-14 h.

**Next.**
- Read the 82-file arms: does PB + transfer hold, is the transfer-only arm honest (halves stay together, per the note
  from the #5011 session above), does protein-compact's per-run union inflate FDP at scale.
- Experiment-wide qualify gate for protein-compact: OSPREY_PROTEIN_COMPACT_QUALIFY was never committed on any pwiz
  branch (`-QualifyBy experiment` in Run-SeaAd.ps1 is a no-op); design in
  TODO-20260804_osprey_pass2_ab_and_library_production.md; separate OSPREY_PROTEIN_COMPACT_QUALIFY_FDR; the runner should
  refuse it on builds that cannot honour it. Mike's protein-compact testing was at ~3 files.
- Pass-2 consistency: OOF vs fold-mean rescoring; a finer score-to-q table.
- PB refinements: size normalisation (#4580), feedback each iteration.
- Eventually one PR, possibly into #4850. Nothing to GitHub until Brendan says.

#### Recovered detail for 2026-11-07 (sub-agent status files)

- Pass-2 loss counts (agent pass2-loss): transfer keeps pass-1 q for 196,037 peaks; 290,914 moved and 14,276 missing get a new
  run q; "Raised 30,182 of 178,955 experiment q to best run-level". q2 >= q1 always (0 gains). Lost IDs: median q1 0.00016 ->
  q2 0.27, score 7.7 -> -3.7; 5,768 had all three runs' peaks moved. Refit bias reproduced offline: lib 19.72 -> 20.80 min
  where its own data median is 21.99. [unmerged, local nightlywork/20261107_refit_bandwidth]
- Score-to-q table (pass2-loss): 1,000 equal-count bins over ~4.4M rows; near 1% it steps 0.0048 -> 0.0104, so every pass-1
  good row at run q 0.006-0.01 maps above 1% at an unchanged score (8,789/8,789). A 10k/50k-bin table rescues only 173 of 2,896
  residual losses. Tolerance floor 0.1 min binds (within-peptide MAD 0.009); cap 0.58 does not. An earlier "pass-1 clamp" note
  was an np.interp artifact - LoessRegression extrapolates linearly both ways. [unmerged]
- Sidecar format (agent decoy-origin, read_fdr_sidecar.py): FdrExperimentSidecar v3 = 32-byte header, 44-byte records (u32
  entry_id, f64 prec_q, pep_q, prot_q, agg_score, pep), trailing stamp; entry_id = blib RefSpectra row index (id-1) of the
  TARGET, paired decoy = index | 0x80000000 (BlibDecoyPairs.Pair). Validated: all 2,641,338 fdrbench rows join, |dq| <= 5e-12.
  [unmerged, tool]
- PB pass 2 implementation (agent pb-pass2): ProteinBestSidecar; declared FirstPassFDR output and PerFileRescoring input;
  resume requires it; FrozenModelScorer.ScoresProteinBest; Stage 7 verify path loads the column; ModelDiagnostics task and
  library build still refused with PB. TestProteinBestPipeline 2m04s; TestPass2ProteinBestColumn. [unmerged, c213f37184]

## Open questions and unfinished items (carried from phases 1-2)

- OspreyDatasetRun.psm1 gendecoy pairing-manifest elseif is uncommitted (from 2026-10-30); gendecoy q 1% -> FDP 1.76%.
- pwiz-blib branch (42d9c53126, 26ea0d9a9d) unpushed, no PR; issue #4948. Fix must not trip IsRedundantLibrary; needs a
  non-redundant .blib test input. Skyline findings 2-5 in the TODO still unfiled.
- Mutation-decoy library (`decoys\lib\...-mutdecoy1712`) never searched with Osprey; reverse decoys near-copy other targets
  18.6% vs 1.0% for mutation decoys, and Osprey's co-assignment gate checks only the own target.
- Linux regression patch (regression-linux.patch) lived in an agent scratchpad; recover or redo before Linux regression runs;
  WSL OspreyLinux was unregistered on 2026-11-07 (rootfs tarball in D:\WSL).
- SVM path is not bitwise across Windows/Linux (PrecursorPep <= 8.6e-16); only GBDT was made deterministic.
- #4993 decisions flagged for Brendan: per-half +1 vs one +1 for the union; lowered subset floors (0.7 -> 0.6, export floor on
  the total). Post-capture regression-parallel against new goldens was done serially, not in parallel.
- In-stratum protein-aware excess under GBDT OOF (fold-mean rescoring of training rows) remains; affects #4993, PB pass 2 (231
  same-apex score drops) and the GBDT pass-2 FDP on Stellar (1.15-1.19%).
- Shadow-detail round 2 (c34dd8d345): confirm whether it went into #4998; gain +324 at 0.5%, flat at 1%.
- wide_* (93-96) and heavy/tight, dominance families add ~0: candidates for pruning in the feature-cost analysis.
- Coelution scoring cost of OSPREY_CORR_FRAGMENT_TOLERANCE (+65% in twoxic) to account for before any default flip.
- 1.7.12 NN with Osprey features at ~52.9k shows ensemble size (96+ CV nets) gives +5.9% over GBDT at 300k; untested in Osprey
  whether GBDT on all rows + OOF fully matches it.
- Score-to-q table resolution near 1% (1,000 bins) and refit keep/remove decision remain open (TODO lists both).
- Cleanup: C:/t/prBpre clone; protshuf libs (22 GB) and runs (11 GB); diann1712 (9.6 GB); pwiz-cdexp worktree; decomp ablation
  process 61340 may have kept running.
- Decomp ablation finished only 2 variants; per-family offline ablation of the late features is incomplete.
