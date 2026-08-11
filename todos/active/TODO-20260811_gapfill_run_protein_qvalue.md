# Gap-fill entries get a run protein q on the batch-hydrate arm but not straight-through

## Branch Information
- **Branch**: `Skyline/work/20260811_gapfill_run_protein_qvalue`
- **Worktree**: `C:\proj\pwiz`
- **Base**: `master`
- **Created**: 2026-08-11
- **Status**: In Progress
- **GitHub Issue**: [#4559](https://github.com/ProteoWizard/pwiz/issues/4559)
- **Module**: `osprey`
- **Other labels**: none yet (candidate: `bug`)
- **PR**: (pending)
- **Requester/Reporter**: none - filed by Brendan while verifying #4557. No credit line
  (Osprey developers on Osprey code).

## Objective

A gap-fill entry created in Stage 6 has no first-pass protein FDR result by construction,
yet the two pass-2 routes give it DIFFERENT `run_protein_qvalue`:

* the chain's `SecondPassFDR` node recomputes protein q via `ProteinFdrEngine.RunFirstPass`
  (the `!preCompacted` batch-hydrate path) and assigns **0.0**
* straight-through leaves the **1.0** `ResetScores()` default because nothing assigns one

Decide which value a gap-fill entry should carry - or whether it should carry one at all -
and make both routes agree.

## Prior context - do NOT re-derive

Read `ai/todos/completed/TODO-20260809_fdr_sidecar_parity.md` first. #4557 added the first
comparison of the per-file FDR sidecars, which is the only reason this is visible. Key facts
already established there:

* All 390 diverging records (Stellar, 3 files: 133/116/141) are **absent from the 1st-pass
  sidecar** - they are gap-fill entries created in Stage 6, so #4557's seed provably cannot
  reach them (it only reads sidecar records).
* Every OTHER field agrees on those same records (0 mismatches).
* The two 1st-pass sidecars agree exactly (0 of 482,891) - nothing upstream diverged.
* `mode1 (vs golden)` PASSES on the projection-off arm, so the reported output is correct
  either way today.
* The DEFAULT streaming arm skips the recompute entirely, which is why `-Dataset All` is
  green and TeamCity is unaffected.

## Reproduce

`OSPREY_ALLOW_UNFIXED_RESIDENT` takes NAMED tokens, not a boolean (`projection-off` here;
`1` aborts in `PerFileScoringTask.GuardResidentPool`). Nested `Start-Process -ArgumentList`
can deliver the token with literal quote characters, which also fails to match - a wrapper
script that sets both vars directly is the reliable form.

```powershell
$env:OSPREY_FDR_PROJECTION = '0'
$env:OSPREY_ALLOW_UNFIXED_RESIDENT = 'projection-off'
pwsh -File ./pwiz_tools/Osprey/regression.ps1 -Dataset Stellar -KeepOutput
```

`-KeepOutput` matters: `regression.ps1` self-cleans its run directory, so on an abort the
`straight.log` the error points at is already gone. With it, both routes' sidecars survive
and can be diffed by entry_id (`straight/<stem>.1st-pass...` against
`chain/phase4_SecondPassFDR/<stem>.2nd-pass...`).

Expected failure:

```
pass2: ..._20: run_protein_qvalue differs on 133 record(s); first entry_id=1341 1 -> 0
```

`mode5` and `mode6` also fail on that arm - default-arm log assertions firing against a
switch that disables the streaming and library-fragment-release paths. Unrelated; do not
chase them.

## MEASURED 2026-08-11 - the chain is right and straight-through is internally inconsistent

Reproduced exactly (133/116/141 = 390 records). Run log
`ai/.tmp/regression-projoff-4559.log`; run dir preserved at
`C:\proj\pwiz\pwiz_tools\Osprey\TestResults\regression-20260811_044537` (`-KeepOutput`).
Analysis scripts: `ai/.tmp/analyze-gapfill-protq-4559.ps1`,
`ai/.tmp/check-protq-per-run-4559.ps1` (shared decoder `ai/.tmp/gapfill-protq-decoder.ps1`).

**1. The diverging population IS the gap-fill population - exactly, not a subset.**

| | count |
|---|---|
| gap-fill records (in 2nd pass, absent from 1st pass) | **390** |
| diverging records | **390** |
| ...absent from the 1st-pass sidecar | 390 |
| ...straight-through value exactly 1.0 | 390 |
| 1st-pass sidecar `run_protein_qvalue` disagreements | **0** |

**2. The chain assigns the value straight-through ITSELF already uses for that precursor.**
`entry_id` is library-derived and stable across files, so each diverging precursor can be
looked up in the OTHER files' STRAIGHT-THROUGH 1st-pass sidecars, where it was an ordinary
detection:

| | count |
|---|---|
| diverging entry_ids found in another file's straight 1st-pass sidecar | **390 / 390** |
| chain value MATCHES that established value | **390** |
| chain value DIFFERS from it | **0** |

e.g. `entry_id=1341`: straight-through writes **1.0** in file `_20` (gap-fill there) and
**0.0** in file `_21` (ordinary detection). The chain writes 0.0 in both.

**3. `run_protein_qvalue` is a per-RUN, per-peptide value - it is NOT per-file.** Over the
straight-through 1st-pass sidecars alone (no chain, no gap-fill involved):

| | count |
|---|---|
| distinct entry_ids | 484,747 |
| appearing in 2+ files | 483,820 |
| ...carrying ONE value across those files | **483,820** |
| ...carrying DIFFERENT values across files | **0** |

### What that means for the question

The issue asks "0.0 or 1.0 for an entry that never competed". Measurement 3 reframes it:
the first-pass protein FDR is pooled over all files and propagated by `ModifiedSequence`, so
a precursor has **exactly one** `run_protein_qvalue` per run - confirmed on 483,820 of
483,820 precursors. Straight-through's 1.0 on a gap-fill row is therefore not "no value for
this file"; it is a **second, different value for a quantity that has one**, and the same
precursor carries both 0.0 and 1.0 in the same run's output depending only on how it was
found.

**This refutes the fail-closed argument for Option A below.** 1.0 would be the honest
"absent" marker only if the field were per-detection. It is not. The peptide earned its
protein q from its evidence pooled across files, and a gap-fill row is another observation
of that same peptide - the same reason every other non-passing observation of it already
carries the real value.

## Mechanism - established from the code 2026-08-11

**The chain does not invent a value for gap-fill entries. It propagates the ordinary one.**

`ProteinFdr.PropagateProteinQvalues` (`ProteinFdr.cs:893-912`) walks EVERY entry in the pool
and assigns `PeptideQvalues[ModifiedSequence]`, falling back to 1.0 only when the sequence is
absent. It does not consult whether the entry passed anything. So a non-gap-fill entry in a
file where its peptide did NOT pass already carries the real protein q - the "it never
competed" argument does not single out gap-fill.

The only difference between the routes is **which pool the propagation loop walks**:

* straight-through: first-pass protein FDR runs in Stage 5 (`FirstPassFdrTask.cs:423`, or the
  streaming reducer at `:2532`), BEFORE Stage 6 creates gap-fill stubs. The stubs are then
  born at `ResetScores()` defaults (`PerFileRescoreTask.cs:2016` and `:2070`) and nothing
  assigns one afterwards.
* chain: `--task SecondPassFDR` rehydrates from the RECONCILED parquet, which already
  contains the gap-fill rows, then re-runs `ProteinFdrEngine.RunFirstPass`
  (`PerFileRescoreTask.cs:531`) over that pool - so the propagation loop reaches them.

The issue's own measurement corroborates that this is the whole difference: if the larger
pool had changed the computed protein FDR, non-gap-fill entries' `run_protein_qvalue` would
differ too. They do not (0 mismatches).

Rust is the same design, not a divergence: `pipeline.rs:4980` gates the identical block on
`!can_skip_fdr || config.expect_reconciled_input` and calls `propagate_protein_qvalues` at
`:5023` over the reconciled pool.

### The divergence has no output consumer

Worth stating plainly before choosing, because it de-risks the decision:

* `RunProteinQvalue` is a GATE at Stage 5/6 only - protein-aware compaction
  (`FirstPassFdrTask.cs:1420`, `:2742`) and consensus rescue (`ConsensusRts.cs:249`). Both run
  BEFORE gap-fill entries exist, so a gap-fill entry can never be gated by it.
* The pass-2 sidecar is written at `SecondPassFdrTask.cs:175`, and
  `ProteinFdrEngine.RunSecondPass` overwrites `RunProteinQvalue` on every stub at `:199`
  (via `PropagateProteinQvalues(..., true, true)`) twenty lines later, at `:197`. So the
  persisted value is transient in memory on every route that loads it.
* The C# chain never reads a `.2nd-pass.fdr_scores.bin` back (the `--task PerFileRescoring`
  workers do not write one - see the #4553 gotcha), and Rust's `--join-at-pass=2` reload
  (`pipeline.rs:5187`) is followed by the same second-pass overwrite.

That is consistent with `mode1 (vs golden)` passing on both routes. This is a question about
a persisted artifact being self-consistent, not about reported output.

## Open design question - the actual deliverable

Should a gap-fill entry carry a run protein q at all? If it should, which route is right?

* **0.0** is a real best-group value, but it lands on an entry that never competed at the
  protein level - the more surprising of the two, and 0 is the accept side of the boundary.
* **1.0** is the "no value" default and is what straight-through reports today.

Note the related invariant from #4553: all peptides of a protein should share a protein q.
Whichever value is chosen has to be checked against that.

### The two implementable options, with costs

**Option A - a gap-fill entry carries NO first-pass protein q (1.0), both routes.**
One place: `Pass2FdrSidecar.RestorePass1Scalars` already streams each file's 1st-pass sidecar
and knows exactly which entries have no record there - that set IS the gap-fill set. Setting
`RunProteinQvalue = 1.0` for them makes both routes agree BY CONSTRUCTION at the same seam
#4557 used for `Score` / `Pep` / `RunProteinQvalue`, rather than by the chain's recompute
happening to land somewhere. Both routes run it (`ComputeAndPersist`, called from
`SecondPassFdrTask.cs:175`).

* default arm: no change at all (already 1.0), so the golden cannot move
* Rust twin: the same rule in `restore_pass1_scalars`
* argues that 1.0 is the honest representation: the field's purpose is a Stage-5/6 gate, and
  a gap-fill entry never faced that gate
* **fails closed.** A future consumer gating on `run_protein_qvalue <= protein_fdr` would
  auto-pass every gap-fill entry under 0.0 and auto-reject them under 1.0. Same hazard shape
  as [[project_osprey_zero_is_the_score_boundary]] - a value sitting on the accept side of a
  gate assigned to something that never competed
* cost: leaves the "all peptides of a protein share a protein q" invariant violated for
  gap-fill rows, which has to be stated as deliberate rather than ignored

**Option B - a gap-fill entry carries its peptide's protein q, both routes.**
Straight-through would have to propagate onto the new stubs in Stage 6, which means carrying
the first-pass `PeptideQvalues` map (`FirstPassProteinFdrResult.ProteinFdr.PeptideQvalues`)
from Stage 5 into Stage 6 on BOTH arms - it exists on the streaming arm too
(`FirstPassFdrTask.cs:2568`), it is just not published past Stage 5.

* satisfies the shared-protein-q invariant
* costs new O(unique peptides) retention across Stage 6, the memory-critical stage
* CHANGES the default arm's persisted sidecar, so it needs the Rust twin landed together or
  the cross-impl sidecar leg goes red, and it moves a shipped artifact for a field with no
  consumer

**Implementation path for B is cheaper than first assumed.** `PlanStage6` runs INSIDE
`FirstPassFdrTask` (`:503`), i.e. AFTER first-pass protein FDR (`:423`, or the streaming
reducer at `:2532`) and while `fullLibrary` is still in scope; it produces
`_perFileGapFillForRescore`, published at `:547`. So the gap-fill target set is known while
the peptide -> q map still exists. Publish a small `entry_id -> run protein q` byproduct
covering ONLY the gap-fill targets (hundreds of entries, not O(unique peptides)) alongside
`PerFileGapFillForRescore`, and consume it at the two `ResetScores()` sites in
`RunGapFillTwoPass` (`PerFileRescoreTask.cs:2016`, `:2070`). `GapFillTarget` already carries
`ModifiedSequence`, so the lookup needs no new joins.

Only straight-through needs it: the `--task PerFileRescoring` worker writes no 2nd-pass
sidecar, and the SecondPassFDR node recomputes. So the `reconciliation.json` wire format
(`Osprey.IO.GapFillEntry`) does NOT have to change - keep the carrier an in-process
byproduct rather than a field on `GapFillTarget`.

Expected blast radius: sidecar-only. Gap-fill `RunProteinQvalue` is not an input to the
Stage 7 protein FDR (which reads `Score` and experiment q), so the committed golden should
NOT move - to be verified, not assumed.

## RECOMMENDATION (needs Brendan's sign-off)

**Option B.** Measurement 3 is the deciding fact: the field has exactly one value per
precursor per run, so 1.0 on a gap-fill row is a wrong value rather than a missing one, and
the chain is already writing the right one. An earlier reading of this TODO favored Option A
on a fail-closed argument; that argument assumed the field was per-detection and does not
survive the measurement.

Whatever is decided must land on **both** C# and Rust, or the cross-impl sidecar leg
(`Compare-FdrSidecars-Crossimpl.ps1`, added by #4557) goes red - it exists precisely to
catch a one-sided fix. Also note maccoss/osprey#61 (the Rust half of #4557) may still be
open; check before measuring cross-impl.

## Tasks

- [ ] Reproduce the failure on the projection-off arm with `-KeepOutput`
- [ ] Confirm the 0.0 assignment site in `ProteinFdrEngine.RunFirstPass` (`!preCompacted`)
      and identify why gap-fill entries land there with a best-group value
- [ ] Check the Rust side for the same behavior before choosing a fix
- [ ] Decide the contract: does a gap-fill entry carry a run protein q, and which value
      - **needs Brendan's sign-off**, this is a contract decision not a defect fix
- [ ] Implement on both C# and Rust
- [ ] Verify `mode3` green on the projection-off arm; confirm `-Dataset All` (default arm)
      unmoved, or rebaseline the golden if it moves
- [ ] Cross-impl sidecar leg green with both sides changed

## Regression Test

- **Test name**: (filled in once written)
- **Test project**: `pwiz_tools/Osprey/regression.ps1` mode 3 (per-file FDR sidecars) -
  currently only red on the projection-off arm, which no scheduled gate runs. Part of this
  work is deciding whether that arm needs a gate at all, or whether the fix makes the
  question moot on the default arm.
- **Fails on master**: (yes - `run_protein_qvalue` differs on 390 records, Stellar 3-file,
  projection-off arm; to be re-verified with a run log path)
- **Passes on fix**: (pending)

## Progress Log

### 2026-08-11 - Session Start

Filed out of #4557 (`ai/todos/completed/TODO-20260809_fdr_sidecar_parity.md`) as a
deliberate deferral: it is a decision about the protein-compact contract, not a defect in
that fix. Starting work.
