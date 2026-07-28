# Osprey: retire OSPREY_PASS2_QVALUE=percolator as the default; choose the pass-2 FDR default

## Branch Information
- **Branch**: `Skyline/work/20260727_osprey_pass2_fdr_default` (pwiz-work1)
- **Base**: `master`
- **Created**: 2026-07-27
- **Status**: In Progress
- **GitHub Issue**: [#4484](https://github.com/ProteoWizard/pwiz/issues/4484)
- **PR**: (pending)
- **Requester/Reporter**: Mike + Brendan (both Osprey developers) — NO credit line
  (developer planning on their own project, per version-control crediting rules)

## Objective

Mike and Brendan have decided the current default 2nd-pass FDR mode --
`OSPREY_PASS2_QVALUE=percolator` (retrain the Percolator SVM + recompute a
target/decoy null on the reconciled **+ compacted** pool) -- is **not a valid
approach**. The compacted pool is decoy-depleted, so the retrained null is
thin/biased and the reported q is anti-conservative (Stellar libdecoy
entrapment: 1.57% true FDP @ nominal 1% vs 0.92% for the 1st-pass q -- see
#4363).

This issue is the **decision + default-flip**: pick the replacement default
among the frozen-model modes and resolve the open question of whether
`transfer-compete` is actually valid and/or better than plain `transfer`.
All frozen modes already shipped **off by default** in #4446 (C#), with the
Rust port in maccoss/osprey#57. This is the umbrella "flip the default"
decision that consumes #4363 (calibration root cause) and #4436 (sensitivity
recovery) as inputs.

## The four modes (`OspreyEnvironment.cs`, `docs/12-second-pass-fdr.md`)

| Mode | Retrain? | Null population | Level |
|---|---|---|---|
| `percolator` (default today) | yes | reconciled + **compacted** (decoy-depleted -> anti-conservative) | precursor + peptide |
| `transfer` | no | pass-1 q carried; only reconciliation-**moved** peaks re-mapped via each file's full-pool score->q table | precursor + peptide |
| `transfer-compete` | no (frozen) | fresh full-population target-decoy competition on frozen 1st-pass scores | precursor |
| `protein-compact` | no (frozen) | competition constrained to the protein stratum; off-stratum survivors keep pass-1 q | precursor |

Diagnostic A/B lever: `OSPREY_PROTEIN_COMPACT_RETRAIN` (retrain instead of
frozen within `protein-compact`, to isolate frozen-vs-retrain calibration).

## Open question: is `transfer-compete` valid / better than `transfer`?

- `transfer` reads each peak's q from a fixed co-monotone 1st-pass full-null
  score->q table (Rost 2016 TRIC). #4363 cell E validated it calibrated
  (0.86% true FDP @ nominal 1% on Stellar). Recovers only reconciliation
  peak-move ranking gain.
- `transfer-compete` re-runs a fresh target-decoy competition over the full
  reconciled population using frozen scores -- a peak can change rank vs
  decoys it did not face in pass 1. Potential source of both extra
  sensitivity AND any new mis-calibration.

Questions to answer:
1. Is `transfer-compete`'s fresh competition a statistically valid q, or does
   re-competing frozen scores re-introduce optimism vs `transfer`'s
   co-monotone inheritance?
2. On the FDRBench entrapment oracle, is `transfer-compete` more sensitive at
   matched TRUE FDP than `transfer`, or is the gain just looser calibration?
3. How do the three modes compose? Is a `transfer`-style (co-monotone)
   stratum worth comparing? Is the right default `protein-compact`
   (best measured: +24% precursors @ 0.466% true FDP on Stellar -- #4436)
   or a more conservative `transfer`?

## Prior measured evidence (re-confirm under current binary before deciding)

From #4363 (Stellar 3-file libdecoy, precursor, `--fragment-tolerance 0.4`,
ground truth = FDRBench entrapment):

| variant | reported FDP @1% q | disc @ TRUE 1% FDP | note |
|---|---|---|---|
| A -- 1st-pass q (no pass-2) | 0.92% | 27,292 | no 2nd-pass Percolator |
| B -- retrain (`percolator`, ships today) | 1.57% | 27,682 | anti-conservative; best ranking |
| E -- `transfer` + FULL 1st-pass null | 0.86% | 27,496 | transfer + full null -> calibrated |

From #4436: `protein-compact` measured +24% precursors @ 0.466% true FDP vs
the `transfer-compete` baseline (Stellar); matched true FDP +19.7% @0.5%,
+20.2% @0.75%.

## Tasks

- [ ] FDRBench entrapment-oracle A/B: `transfer` vs `transfer-compete` vs
      `protein-compact` at matched TRUE FDP -- Stellar AND Astral
      (`-Dataset All`; Astral has the selenocysteine gotcha + largest DIA-NN gap)
- [ ] Statistical-validity write-up: `transfer-compete` fresh-competition vs
      `transfer` co-monotone inheritance (is re-competing frozen scores valid?)
- [ ] Pick the default; decide `percolator`'s fate (keep for parity / remove)
- [ ] Coordinated C#+Rust golden-rebaseline PR to flip the default
      (parity with maccoss/osprey#57)
- [ ] Optional: promote `OSPREY_PASS2_QVALUE` to a `--pass2-fdr` CLI flag
- [ ] Docs: update `docs/12-second-pass-fdr.md` default + command-line docs

## Regression Test

- **Test name**: (filled in once written)
- **Test project**: Osprey regression (golden rebaseline) + any unit coverage
- **Fails on master**: (TBD)
- **Passes on fix**: (TBD)

This is a golden-output-changing default flip. The primary verifier is the
committed C# golden regression rebaseline (regression.ps1) coordinated with
the Rust golden. Entrapment-oracle A/B measurements are decision evidence, not
regression tests; capture their on-disk paths in the Progress Log.

## Related

- #4363 -- root cause (decoy-depleted null) + validated `transfer` + full-null
- #4436 -- honest FDR + sensitivity recovery (`transfer-compete`, `protein-compact`, GBDT)
- #4446 (merged) -- shipped all frozen modes off by default (C#)
- maccoss/osprey#57 -- Rust port of the frozen modes
- `pwiz_tools/Osprey/docs/12-second-pass-fdr.md`, `Osprey.Core/OspreyEnvironment.cs`

## Progress Log

### 2026-07-27 - Session Start

Starting work on this issue. Created branch
`Skyline/work/20260727_osprey_pass2_fdr_default` in pwiz-work1. This is the
umbrella default-flip decision anticipated in prior pass-2 work; #4446 (C#) and
osprey#57 (Rust) already shipped the frozen modes off by default.

### 2026-07-27 - Statistical-validity analysis + oracle run launched

Discussion-first (Mike/Brendan want the methodology settled before the flip).

- Mechanical flip is trivial: `OspreyEnvironment.NormalizePass2QValue` returns
  `PASS2_QVALUE_PERCOLATOR` on empty input (`OspreyEnvironment.cs:361`); all four
  modes + `OSPREY_PROTEIN_COMPACT_RETRAIN` already present. Substance = the decision.
- **Verified transfer-compete competes over the full PRE-compaction population**
  (`PercolatorFdr.cs:2928-2929`) — not decoy-depleted, not retrained. Both
  `percolator` sins gone; if reconciliation moved nothing it reproduces pass-1 q.
- **Verified reconciliation is structurally target/decoy asymmetric.** Every gate
  that selects what gets reconciled / where it re-integrates is a target-only q
  quantity: consensus qualification excludes decoys (`ConsensusRts.cs:99-133`),
  planner gated on target min-q (`ReconciliationPlanner.cs:131-144`), gap-fill
  targets-only at the target's ExpectedRt (`GapFillTargetIdentifier.cs:103-197`).
  Direction: harmless for true targets, anti-conservative for reproducible false
  targets → `transfer` (experiment-q frozen) is immune by construction;
  `transfer-compete` is exposed. Confirms Brendan's "only targets can carry a q".
- Orthogonal-axes analysis (protein corroboration = mean-top-2/posterior-product;
  reproducibility = binomial-tail not raw count, scale-correct; overlap → joint
  CV-trained feature model, not more q-cutoff modes; decoy-fairness constraint).
- **Write-up captured**: `ai/.tmp/pass2-fdr-default-validity.md` (Task 2, the
  statistical-validity deliverable; pre-measurement draft — distill to
  `docs/12-second-pass-fdr.md` after testing).
- **Harness**: added `-Pass2QValue` to `ai/scripts/Osprey/Run-FdrBench.ps1`
  (sets/restores OSPREY_PASS2_QVALUE, folds into OutName + metrics.csv). Built a
  fresh Release net8.0 Osprey in pwiz-work1 (master-equivalent; HEAD == origin/master).
- **Oracle run launched** (background): 3-way `transfer` / `transfer-compete` /
  `protein-compact` on Stellar 3-file libdecoy, matched (precursor, pass 2,
  --protein-fdr 0.01, --fragment-tolerance 0.4). `transfer` doubles as the #4363
  cell-E anchor (~0.86%). Driver: `ai/.tmp/run-pass2-oracle-3way.ps1`;
  log `ai/.tmp/pass2-oracle-3way.driver.log`. Results pending.
