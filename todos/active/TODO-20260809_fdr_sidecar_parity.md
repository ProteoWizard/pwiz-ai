# Straight-through drops Score and RunProteinQvalue that the task-by-task route keeps

## Branch Information
- **Branch**: `Skyline/work/20260809_fdr_sidecar_parity`
- **Worktree**: `C:\proj\pwiz`
- **Base**: `master`
- **Created**: 2026-08-09
- **Status**: In Progress
- **GitHub Issue**: [#4553](https://github.com/ProteoWizard/pwiz/issues/4553)
- **Module**: `osprey`
- **Other labels**: none yet (candidate: `bug`)
- **PR**: (pending)
- **Requester/Reporter**: none - found by Brendan and Claude while building the FDRBench
  oracle for #4486. No credit line (Osprey developers on Osprey code).

## Objective

The straight-through pipeline and the four-task (`--task`) route write DIFFERENT values
into every `<stem>.2nd-pass.fdr_scores.bin`, and no gate compares that file. Add the
comparison (it goes red immediately), then fix the divergence.

## Root cause - ALREADY DIAGNOSED, do not re-derive

`OverlayRescoredEntries` (`PerFileRescoreTask.cs:1437`) calls `FdrEntry.ResetScores()` on
every entry Stage 6 touches - both the successfully rescored ones (`:1459`) and the
"no peak at the override boundary" ones (`:1468`). `ResetScores()` (`FdrEntry.cs:169`)
clears EIGHT fields:

```
Score = 0.0;  RunPrecursorQvalue = 1.0;  RunPeptideQvalue = 1.0;  RunProteinQvalue = 1.0;
ExperimentPrecursorQvalue = 1.0;  ExperimentPeptideQvalue = 1.0;
ExperimentProteinQvalue = 1.0;  Pep = 1.0;
```

The DEFAULT pass-2 mode (`protein-compact`, via `ComputePass2TransferCompeteFull`) writes
back only five of them - `RunPrecursorQvalue`, `RunPeptideQvalue`,
`ExperimentPrecursorQvalue`, `ExperimentPeptideQvalue`, `Pep`. It never writes `Score` or
`RunProteinQvalue`, so those two are persisted at their reset defaults.

**Why the task-by-task route is unaffected**: `--task SecondPassFDR` cannot use live
in-memory state, so it rehydrates from `.1st-pass.fdr_scores.bin` and
`OverlayFirstPassSidecar` writes all seven scalar fields back - including the two nothing
else restores. The distributed route accidentally REPAIRS what the in-process route drops.
So the more-correct output comes from the path we would have assumed was riskier.

The sibling mode does it right: `AssignPerRunQ` (`OSPREY_PASS2_QVALUE=transfer`) sets
`entry.Score` on all three of its branches. Only the frozen-competition modes
(`transfer-compete`, `protein-compact`) omit it.

## Measured (StellarGenDecoyEntrap, 3 files, 260,419 records)

Each route's OWN 1st-pass sidecar vs its 2nd-pass sidecar:

| | straight-through | task-by-task |
|---|---|---|
| `score`: real in 1st -> **0** in 2nd | **99,992** | 0 |
| `run_protein_qvalue`: real in 1st -> **1.0** in 2nd | **32,450** | 0 |
| `protq`: 1.0 in both (legitimately) | 129,627 | 129,627 |
| `score`: eid absent from 1st-pass (gap-fill) | 741 | 741 |

Zero-score totals in the straight-through 2nd-pass sidecar: **100,733 of 260,419 (39%)** -
targets 33,207 and decoys 67,526. Decoys are hit at 52% vs targets at 25%, so the persisted
null is disproportionately zeroed. At 82 files the protein-q divergence is 1,355,103 of
86,581,597 (1.57%).

Protein-level consistency (Brendan's invariant - all peptides of a protein should share a
protein q): straight-through leaves **14,325 of 28,806 proteins mixed** (some peptides real,
some 1.0); the task route leaves **622**. No protein on either route has two DIFFERENT real
values, so the q itself is consistent - only its propagation is not.

## Why no gate sees it

* `regression.ps1`'s four-task-chain leg asserts `Compare-BlibFull` and nothing else about
  per-file outputs. Protein q and per-entry SVM score are not in the blib, and they move no
  count the gate reads: peptides at 1% experiment FDR (26,714), protein groups passing 1%
  (21,861) and the blib (23,292 spectra from 69,876 passing entries) are IDENTICAL between
  the two routes.
* The cross-impl C#/Rust comparison does not cover it either. Both
  `Compare-EndToEnd-Crossimpl.ps1` and the committed golden compare the Stage 7 protein FDR
  dump, whose columns are per-protein-GROUP (`accessions, n_unique, n_shared,
  best_peptide_score, group_qvalue, is_target_winner`); its emitter notes it "reads only the
  parsimony / FDR result (not the stubs)". These fields live on the stubs.

## Tasks

- [x] Add `Regression/FdrSidecars.ps1` (`Compare-Pass2Sidecars`) comparing all seven scalar
      fields per entry_id, byte-equality fast path, per-field failure tallies
- [x] Wire it into the four-task-chain leg as its own summary line
- [x] Verify it FAILS on the current divergence (Pass=False, Compared=260419, Issues=9)
- [ ] Decide whether Rust has the same defect (see below) before choosing the fix
- [ ] Fix the divergence - two candidates, both narrow:
      1. have the frozen pass-2 modes write `entry.Score` (the frozen-model score is already
         in hand) and restore/recompute `RunProteinQvalue` after the reset; or
      2. make `ResetScores()` stop clearing fields no caller intends to recompute, so it
         means "this peak moved" rather than "discard everything"
- [ ] Re-run `regression.ps1 -Dataset All` green with the check in place
- [ ] Consider whether the golden needs rebaselining (the fix changes sidecar bytes)

## Is the bug in Rust too? - OPEN, and likely

`OverlayRescoredEntries`' own comment at `:1466` says the reset is "to match Rust's
behavior", so Rust performs the same clear. Whether Rust's pass 2 restores `Score` /
`run_protein_qvalue` afterwards is unverified. Rust writes the identical sidecar
(`pipeline.rs`, `run_protein_qvalue` at bytes `[52..60]`), so a Rust straight-through run
diffs directly against the C# one.

If Rust also persists zeros, this is a shared design defect rather than a port error - and
the C#/Rust parity gate has been agreeing on the wrong value, which is the more important
finding.

**Attempt 2026-08-09 FAILED to launch, not a result**:
`Compare-EndToEnd-Crossimpl.ps1 -TestBaseDir D:\test\osprey-runs\crossimpl-4553` errored
immediately - it copies the dataset FROM `<TestBaseDir>\stellar`, so the base dir must
already hold the mzML. Stage the data there (or use the default base) and re-run.

## Regression Test

- **Test name**: `regression.ps1` four-task-chain leg, `mode3 (per-file FDR sidecars==straight)`
- **Test project**: `pwiz_tools/Osprey/regression.ps1` (+ `Regression/FdrSidecars.ps1`)
- **Fails on master**: **yes** - verified standalone against a preserved
  `-KeepOutput` run: `Pass=False  Compared=260419  Issues=9`, naming `score`,
  `pep` and `run_protein_qvalue` per file.
- **Passes on fix**: not yet - the fix is not written.

This is the guard the issue exists to add: the divergence was invisible because the only
per-file assertion was the blib, which carries neither field.

## Gotchas

* `-o out.blib` is RELATIVE to the process working directory, not to `--output-dir`. A
  wrapper launched from `C:\proj\pwiz` wrote a 211 MB blib into the repo root. Pass an
  absolute `-o`, or set the working directory.
* The `--task PerFileRescoring` workers write NO `.2nd-pass.fdr_scores.bin`, so
  `regression.ps1`'s `if (Test-Path $pass2)` copy into the SecondPassFDR phase is a no-op
  and that node always recomputes. Any reasoning that assumes the workers' values are
  relayed is wrong.

## Progress Log

### 2026-08-09 - Session Start

Split out of the #4486 Stage 7 memory work, where this was found while building the
FDRBench oracle for that branch's review finding 1. Root cause is diagnosed (above) and the
failing check is written; the fix and the Rust question remain. Kept off the #4486 branch
deliberately: the check turns `-Dataset All` red, which would block a PR that has nothing
to do with this defect.
