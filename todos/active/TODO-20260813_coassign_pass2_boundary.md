# Pass-2 co-assignment decoy row uses pass 1's acceptance boundary

## Branch Information
- **Branch**: `Skyline/work/20260813_coassign_pass2_boundary`
- **Base**: `master` (at `8d0a2aa6cf`, the #4558 merge)
- **Created**: 2026-08-13
- **Status**: In Progress
- **GitHub Issue**: [#4573](https://github.com/ProteoWizard/pwiz/issues/4573)
- **Module**: `osprey`
- **PR**: (pending)

Follow-up to #4558, which shipped the diagnostic that exposes this but deliberately did not
change the admission rule. Reporter is Brendan (project developer) - no credit line per
version-control-guide "Crediting Reporters and Requesters".

## Objective

Make the pass-2 co-assignment panel derive its acceptance boundary from **its own population**
instead of inheriting `min(aggregate)` over a set whose q-values were carried over from pass 1.

The composite score per entry does not change between passes, but the score at which
target-decoy competition reaches a given q is a property of the population being counted, and
pass 2 counts over a compacted pool. Golden evidence on stellar-gendecoy-entrap:

```
pass2.coAssign.experiment.decoy.n        10        <- class table, admitted on the inherited cutoff
pass2.coAssign.cutoff                     0.2106   <- pass 1's, bit-identical
pass2.coAssign.fdrCrossing               -1.9960
pass2.coAssign.fdrCrossingDecoys          325      <- what the row should be
pass2.coAssign.fdrCrossingNonDecoys    32,549
```

`325 / 32,549 = 1.0%`, as the definition requires. The row reads 10.

The lower bar is not a threshold relaxation: it admits +3,606 targets and entrapment
(32,549 vs 28,943) alongside +36 decoys.

## Tasks

- [ ] **Settle the design question BEFORE writing code** (see below) - it changes every row,
      not only the decoy one
- [ ] Locate the pass-2 boundary derivation and the class-table gating in the panel source
- [ ] Implement the recomputed boundary per the settled definition
- [ ] Regression test (see Regression Test section) - red on master, green on the fix
- [ ] Rebaseline the three `diagnostics.tsv` goldens (~2.4 KB each; diagnostics-only, no
      `.blib` / sidecar / protein-FDR output touched)
- [ ] Cross-impl verify at 1e-9 BEFORE `-CreateGolden` (this ordering caught a real C# bug on
      08-12 that 578 unit tests did not)
- [ ] `-Dataset All` verify
- [ ] `/code-review max`, fold fixes into the opening commits
- [ ] One TeamCity cycle on the exact tip proposed for merge

## The design question to settle first

Today target and entrapment rows are gated on `experiment q <= 1%` (23,134 + 157); decoys are
gated on **score**, with the cutoff bridging the two. The crossing's 32,549 is score-gated on
both sides. These are not the same population definition. Decide whether the target/entrapment
rows re-gate on the recomputed score, or stay q-gated.

## Known caveat on the null (not a blocker)

`protein-compact` selects in-stratum base_ids on a target-strength criterion (per-run q < 1%),
and a decoy that *wins* its competition has by construction a weak target. Measured: of pass-1
above-bar decoys that won, 10 of 288 survive (3.5%) and 0 of 288 had an accepted target,
against 50 of 50 for those that lost. The compacted decoy pool is loser-enriched. That is a
caveat on how well the pool estimates error - not grounds for keeping a stale cutoff, which is
simply the wrong pool.

## Withdrawn reasoning (do not re-derive)

An earlier analysis argued the remap would be harmful because the remapped threshold scores as
~7% FDR "judged by the pass-1 null". **Withdrawn** - it evaluated a pass-2 threshold against
the pass-1 population, the wrong denominator. The related "0 new acceptances at pass 2"
measurement was circular: it defined acceptance by q, and q is inherited, so it could only
return zero. Full detail in the 2026-08-13 CORRECTION at the end of
`ai/todos/completed/`-bound `TODO-20260808_peak_coassignment_diagnostics.md`; ignore that
file's earlier section titled "REMAPPING WOULD BE HARMFUL".

## Regression Test

- **Test name**: (filled in once written)
- **Test project**: Osprey C# unit tests (Osprey.FDR / Osprey.Tasks) or the regression golden
- **Fails on master**: (pending)
- **Passes on fix**: (pending)

## Analysis scripts available

In `ai/.tmp/` (gitignored), all taking a folder of `*.fdr_scores.bin` sidecars:
`pass2_loser_by_score.py`, `pass2_stratum_split.py`, `pass2_tie_check.py`,
`pass_pool_sizes.py`, `pass2_qmap_remap.py`, `pass2_band_cost.py`, `pass2_stratum_bias.py`.
Get sidecars with `regression.ps1 -KeepOutput -SkipResume -SkipWarmRerun -SkipRehydrate
-SkipHpcChain` (`-KeepRunDirs` does NOT retain them).

## Progress Log

### 2026-08-13 - Session Start

Starting work on this issue. Branch created off `8d0a2aa6cf` (the #4558 merge). Read the
2026-08-13 CORRECTION in the #4558 TODO and the handoff before touching code. Next step is the
design question above, which is a decision for Brendan, not an inference from the code.
