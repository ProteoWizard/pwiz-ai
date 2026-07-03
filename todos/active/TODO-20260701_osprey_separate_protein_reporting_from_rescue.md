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
- **BLOCKER FOUND — PR #4353 set to DRAFT.** `regression.ps1 -Dataset Stellar`:
  mode2 PASS; mode1 (golden) FAIL (expected: 2nd-pass Percolator retrains on the
  smaller set); **mode3 (HPC==straight) FAIL** — a real regression (clean master
  passes all 3). ROOT CAUSE (confirmed via -KeepOutput compaction counts):
  straight compacts to a GLOBAL first-pass base_id set (66793; a base_id passing
  peptide-q in ANY file kept in ALL files); the HPC PerFileRescore worker sees
  one file and recomputes a PER-FILE set. On master the worker predicate's
  `|| protein-q` clause was LOAD-BEARING — it inflated the per-file worker set to
  ≈ global (66749≈66857). Removing it drops workers to per-file peptide-q (62991)
  vs global 66793, so workers drop ~3800 cross-file entries straight keeps; the
  chaotic 2nd-pass Percolator amplifies -> wholesale mode3 divergence. FIX
  (architectural, do NOT guess): plumb FirstJoin's global base_id set to the
  workers via the reconciliation bundle so `RescoreCompaction` retains the global
  set, not a per-file recompute. Latent HPC production-parity issue the rescue
  removal merely EXPOSED (cf. [[project_osprey_firstjoin_order_sensitivity]]);
  flag to Mike as its own fix. Full write-up: ai/.tmp/handoff-20260702-morning.md.
  Entrapment-oracle re-run (~0.90% gate, ai/.tmp/pr2-oracle-ab.sh) DEFERRED behind
  the mode3 fix. Do NOT re-capture the golden until mode3 is green.

### 2026-07-02 - mode3 FIXED (commit 1dd206b831)
- ROOT CAUSE (confirmed): HPC per-file rescore worker recomputed a PER-FILE
  first-pass base_id set (62,991) instead of the straight-through GLOBAL set
  (66,793); the `|| protein-q` clause had been masking the gap. See memory
  project_osprey_hpc_worker_compaction_global_coupling.
- FIX: FirstJoin now persists the join-wide first-pass base_id set in
  `reconciliation.json` (bumped to **v3**, required `first_pass_base_ids`).
  `RescoreHydration` reads it into `RescoreInputs.GlobalFirstPassBaseIds`;
  `RescoreCompaction.Apply(inputs)` compacts to exactly that set and HARD-FAILS if
  absent (no silent per-file fallback); dropped its unused `config` param. Chose
  the envelope (not a standalone sidecar): already staged at every HPC/NextFlow
  boundary + is the cross-impl byte-parity format. NextFlow implementer approved
  the design.
- VERIFIED: regression **mode3 PASS** (worker keeps 66,793) + mode2 PASS, on the
  final envelope code. Build + 446 unit tests + inspection green. mode1 still FAILs
  = intended rescue-removal golden change (re-capture pending).
- REMAINING: (1) push branch (local commits 2d14ca1e4d + 1dd206b831, unpushed);
  (2) port `first_pass_base_ids` v3 to Rust reconciliation_io.rs (Brendan wants
  cross-impl parity kept); (3) re-capture golden (mode1) after confirming the diff
  = only removed rescue admissions; (4) run entrapment oracle (~0.90%);
  (5) strip TODO-file refs from PR-2 code comments (feedback_no_todo_refs_in_code);
  (6) /pw-self-review 4353, un-draft.

### 2026-07-02 (evening) - ORACLE RE-RUN OVERTURNS THE ROOT-CAUSE ATTRIBUTION
The entrapment oracle (deferred until now) was finally run on the rescue-removed
build. It shows the rescue removal did NOT fix the anti-conservative `--protein-fdr`
FDR, and that the stated justification was misattributed. Full write-up:
`ai/.tmp/pr2-oracle-finding.md`; memory `project_osprey_pass2_recalibration_inflates_fdr`.

Stellar libdecoy, precursor, --fragment-tolerance 0.4, same Release binary:
- A: --protein-fdr OFF                              -> 27050 disc, FDP **0.92%** (good).
- B: --protein-fdr ON                               -> 30788 disc, FDP **1.57%** (bad).
- C: --protein-fdr ON + OSPREY_PASS2_NO_RECALIBRATE -> 27050 disc, **0.92%** = **C==A exactly**.

- **The 2nd-pass Percolator RECALIBRATION is the entire anti-conservative source, NOT
  the rescue.** `MergeNodeTask.cs:127` gates the 2nd-pass Percolator retrain on
  `--protein-fdr`; that retrain re-estimates q from the reconciliation-biased,
  decoy-paired null and radically underestimates q (curve jumps to 1.46% by q~=0.001
  then plateaus). Skipping it (cell C) restores 0.92% and makes `--protein-fdr`
  genuinely reporting-only.
- **The 6.3x entrapment figure that "ONLY justified" the rescue removal was measured
  WITH recalibration on -> it was measuring the recalibration, not the rescue.** The
  mode1 golden diff (rescue-removed vs rescue-present, both with recalibration) was
  only **net -3 discoveries**, confirming the rescue removal is ~no-op on final output.
- **CONSEQUENCE:** PR-2's premise ("remove the rescue -> fix anti-conservative
  --protein-fdr / make it reporting-only") is invalid. The rescue removal is at best a
  cosmetic cleanup matching Mike's intent; the mode3-fix + reconciliation-v3 parity
  fix a *latent* HPC coupling (worth keeping) but only manifest once the rescue is
  removed. Do NOT ship #4353 on the old narrative.

**RECOMMENDATION (pending Brendan+Mike science call):**
1. The real fix is TRIC-style (Rost 2016) confidence *transfer*: pass 2 re-picks peaks
   but does NOT recompute FDR -- score the reconciled peak with the FROZEN 1st-pass
   model and map through the 1st-pass score->q table (co-monotonic), never re-estimating
   a null on the biased decoys. Variant (iii). Minimal proof-of-direction lives behind
   experimental env var OSPREY_PASS2_NO_RECALIBRATE (uncommitted in the pwiz worktree:
   OspreyEnvironment.cs + Pass2FdrSidecar.cs).
2. Rust PR maccoss/osprey#48 (reconciliation.json v3 parity) is INDEPENDENT and ready --
   byte-identical to C# (SHA 3896e545). Keep it.
3. HOLD pwiz #4353 (draft) -- fold rescue-removal + mode3 + reconciliation-v3 into the
   coherent pass-2 recalibration-fix rework, OR reframe narrowly as an HPC-hardening +
   cleanup PR. Brendan to decide. Golden re-capture is deferred behind that decision.
4. Whether Osprey stops recalibrating in pass 2 by default (and variant ii vs iii) is
   the science decision. Osprey is now the platform to A/B it rigorously (the 2016
   Horowitz-Gelb aim); the oracle harness produces one FDP curve per variant.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260701_osprey_protein_rescue_removal.md` before starting work.
- FOLLOW-UP for Mike: the rescue in Rust (pipeline.rs:1488-1491) is now a lower priority
  than the pass-2 recalibration question above; reconcile his recollection with the code.

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
