# TODO-osprey_separate_protein_reporting_from_rescue.md -- Remove the pass-2 protein-FDR rescue; keep protein-FDR reporting

## Status
Active (brendanx67). Branch `Skyline/work/20260701_osprey_protein_rescue_removal`,
PR #4353 (opened 2026-07-01, autonomous night session). PR-1 (versioning) =
PR #4352. Both branched off master b2373f9f9c.

### Progress (2026-07-01 night session)
- DONE (code). Removed the `|| protein-q passes` clause from all THREE survival
  gates: `FirstJoinTask.CompactFirstPass`, `RescoreCompaction.Apply` (HPC path),
  `ConsensusRts.Qualifies` (reconciliation eligibility). Removed the dead
  `proteinFdrThreshold` param from `ConsensusRts.Compute` + caller
  (`Stage6Planner`) + ~11 test calls. Kept 2nd-pass protein-FDR reporting
  (`proteins.csv` + q-values) and the first-pass protein-FDR run (now
  provenance-only in the fdr_scores sidecars, no longer gating survival).
  Rewrote the 2 ConsensusRts rescue tests + 3 IOTest RescoreCompaction tests
  into rescue lock-out tests. `--protein-fdr` is now reporting-only (no error,
  no Carafe change).
- Build+tests+inspection GREEN (446 tests, 0 warnings).
- DEFERRED: `FdrLevel.Protein` restoration (item 4) -- optional per this TODO's
  scope note, touches the FDR gating path, and no C# oracle for the protein-gate
  path yet (see feedback_no_unverified_ports). Flag for a follow-up.
- VALIDATION (in flight): `regression.ps1 -Dataset Stellar` golden diff, and the
  entrapment-oracle re-run (~0.90% target with `--protein-fdr 0.01`). Results +
  any golden re-capture appended below.
- FOLLOW-UP for Mike: remove the same rescue from Rust (pipeline.rs:1488-1491)
  and reconcile his recollection with the code.

## Decision (Brendan + Mike, 2026-07-01)
Protein-FDR **reporting** (per-protein q-values / `output.proteins.csv`) is
desirable and stays. The pass-2 **protein rescue** -- keeping a peptide that
failed peptide/precursor FDR because its parent protein passed protein FDR --
comes out **entirely** (no gating). Mike, in his own words: "At one point I was
being more liberal in letting through peptides from the first step if they were
in a protein that passed the fdr threshold. I am pretty sure I removed that
because it didn't work at all... the second reconciliation step makes the scores
worse ... it can force moving a peak detection from a higher scoring peak to a
lower scoring peak to agree with the consensus. So there was no point in letting
bad scoring peptides through the first step."

**VERIFIED against ground truth (Rust `osprey` 696c938): the rescue is STILL in
Rust** (pipeline.rs:1488-1491 documents it was deliberately added v2->v3 2026-05-02:
`run_peptide_qvalue <= 0.01 OR run_protein_qvalue <= 0.01`). So Mike's recollection
of having removed it is **mistaken**, and the C# port is faithful. Removing it from
C# is therefore a **deliberate divergence from Rust, justified ONLY by the entrapment
oracle** (6.3x enrichment below), not by parity or by "matching Mike." The same
anti-conservative rescue should also be removed from Rust and Mike's memory
reconciled with the code (separate follow-up). The mechanistic
reason: pass-2 reconciliation can only move a marginal peptide's peak from a
higher- to a lower-scoring position (to match consensus), so rescuing bad-scoring
peptides into pass-2 gains nothing and only adds the false/entrapment IDs measured
below.

**Scope note:** restoring the `FdrLevel.Protein` enum is OPTIONAL / not required
for this fix -- Mike's ask is simply to delete the rescue. Do not re-introduce the
rescue under any flag. If `FdrLevel.Protein` is added, it is a reporting/threshold
level only, never a peptide-rescue trigger.

## Evidence it's broken (measured 2026-07-01, current master post-#4347 merge)
Stellar 3-file library-decoy + entrapment, precursor-level, held everything else fixed:
- **without** `--protein-fdr`: 26,777 disc @ 1% q, entrapment rate 0.452%, combined FDP **0.90%** (controlled; matches Mike's Carafe run bit-for-bit).
- **with** `--protein-fdr 0.01`: 30,417 disc, entrapment rate 0.736%, combined FDP **1.46%** (anti-conservative).
- The rescue admits **3,640 extra discoveries; 103 (2.83%) are entrapment/false = 6.3x the 0.452% baseline.** Combined FDP ~= 2x entrapment rate, so 0.90% -> 1.46%.

Root cause: `FirstJoinTask.CompactFirstPass` keeps a base_id if
`RunPeptideQvalue <= RunFdr || (proteinGate > 0 && RunProteinQvalue <= proteinGate)`
(`FirstJoinTask.cs:533`). The `|| protein` clause is the rescue. It fires whenever
`--protein-fdr` is set (default off in Osprey, but Carafe passes `0.01`), and it is
**not gated on `--fdr-level`** -- so `--fdr-level precursor` does not suppress it
(the C# `FdrLevel` enum = {Precursor, Peptide, Both}; the Rust `FdrLevel::Protein`
was dropped in the port -- see `ProteinFdrEngine.cs:125`).

## Work
1. **Remove the protein rescue from compaction.** `FirstJoinTask.CompactFirstPass`
   (`:523-540`): peptide/precursor survival gates on `RunPeptideQvalue <= RunFdr`
   only. Delete the `|| RunProteinQvalue <= proteinGate` clause.
2. **Keep protein-FDR reporting.** Second-pass protein FDR + `output.proteins.csv`
   + reported protein q-values stay. Verify what `RunFirstPassProteinFdr`
   (`FirstJoinTask:234/1101`) feeds: if its `RunProteinQvalue` output *only* fed
   the rescue (and `ConsensusRts`/reconciliation protein-rescue eligibility),
   drop the first-pass protein-FDR run too (it becomes dead work); if anything
   else consumes `RunProteinQvalue`, keep it but ensure it no longer gates survival.
   Also check the reconciliation eligibility protein-rescue (`ConsensusRts.cs`
   `proteinFdrThreshold` path) -- the same "rescue by protein" logic likely lives
   there and should go too, for the same reason.
3. **`--protein-fdr` becomes reporting-only.** Once it no longer changes the
   peptide/precursor set, `--protein-fdr 0.01 --fdr-level precursor` is coherent
   ("control precursor FDR, report protein FDR"). **No error, no Carafe change,
   no breakage** -- this supersedes the earlier hard-error idea, which is no longer
   needed because the contradiction is gone.
4. **Restore `FdrLevel.Protein`** (parity with Rust's enum; the "restore what Rust
   supports" item) for explicit protein-level reporting/control. This is the ONLY
   Rust-parity part; the rescue removal is a deliberate Rust divergence -- do not
   re-add the rescue in the name of parity.
5. **Tests**: a regression test that a peptide failing peptide-FDR whose protein
   passes protein-FDR is NOT admitted to the output (locks out the rescue); confirm
   `proteins.csv` / protein q-values still produced.

## Gates (judge on the entrapment oracle, within ONE hash-stamped binary)
- `Build-Osprey.ps1 -Configuration Debug -RunTests -RunInspection` clean.
- `regression.ps1 -Dataset Stellar` -- note: the committed golden was produced WITH
  the rescue, so plain-Stellar (reverse-decoy) output MAY change; if it does,
  re-capture the golden and confirm the change is only the rescued admissions
  (expected: slightly fewer discoveries, no rescued peptides). Flag for review.
- **Entrapment oracle (the real gate):** Stellar 3-file library-decoy, precursor
  level, WITH `--protein-fdr 0.01` present, must return to ~0.90% combined FDP
  (i.e. protein-fdr no longer perturbs precursor FDR). Harness: run via the
  `ai/.tmp/run-cell.sh`-style command at `--fragment-tolerance 0.4/0.5`, FDRBench
  `-level precursor -fold 1 -pick first -seed 2000`, compare combined/paired FDP.
  Reference numbers above.

## References
- `FirstJoinTask.cs:234` (first-pass protein FDR trigger), `:533` (rescue clause), `:1101` (RunFirstPassProteinFdr)
- `MergeNodeTask.cs` (second-pass protein FDR + blib; keep reporting)
- `ConsensusRts.cs` (`proteinFdrThreshold` reconciliation-eligibility rescue -- likely also remove)
- `OspreyConfig.cs:206` (`ProteinFdr` nullable, default off), `:346` (`FdrLevel` enum, no Protein)
- `ProteinFdrEngine.cs:125` (Rust `FdrLevel::Protein -> Peptide` mapping, dropped in C#)
- Full investigation: `ai/.tmp/mike-repro-forensics.md`; entrapment-enrichment numbers reproduced from `D:\test\osprey-runs\_cells_mikenew` (no-protein) vs `_cells_baseidfix` (protein).
