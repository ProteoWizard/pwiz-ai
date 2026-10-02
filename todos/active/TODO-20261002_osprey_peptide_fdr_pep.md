# TODO-20261002_osprey_peptide_fdr_pep.md

## Branch Information
- **Branch**: `Skyline/work/20261002_osprey_peptide_fdr_pep`
- **Base**: `Skyline/work/20260612_net8_port` (0386082cc1)
- **Created**: 2026-10-02
- **Status**: In Progress
- **Module**: `osprey`
- **PR**: (pending)
- **Checkout**: `I:\git_i\sky_proteinfdr`
- **Related**: `Skyline/work/20261001_osprey_blib_protein_fdr` (stashed in the same checkout) writes these values
  to the .blib once this lands: protein groups as `Proteins` rows with `qValue`, `RefSpectra.peptideQValue`.

## Objective

Make Osprey produce the peptide- and protein-level statistics a .blib needs so Skyline can filter on
peptide, protein and per-run confidence. Best-guess fixes for Mike MacCoss to keep or drop.

1. **Second-pass experiment peptide q is not a peptide-level q.** On-stratum entries get
   `FdrExperimentRecord(id, eq, eq, ...)` (Pass2FdrSidecar FinishRecord): peptide q := precursor q.
   Off-stratum entries carry pass-1 peptide q. On Stellar 3-file, 2,078 of 28,965 reported peptides had
   different values on different charge states. Fix: a real peptide-level competition in pass 2, mirroring
   pass 1 (ComputeExperimentPeptideQMap / StreamingFirstPassQ.BuildExperimentPeptideQMap).
2. **Experiment peptide PEP**: fit PepEstimator on the peptide-level winners, both passes.
3. **Protein-group PEP**: fit on the picked-protein winners (ProteinFdr.ComputeProteinFdr). Open question
   for Mike: target groups are gated by best peptide q, decoys are not, so pi0 and the decoy density are
   biased; best guess documented in the code.
4. **Run-level (per-observation) precursor PEP**: fit per file on that file's run-level competition
   winners, pass 1 and pass 2; stored in the per-run sidecar (FdrScoreRecord). For the .blib's
   RetentionTimes rows.

## Not in scope (noted for the PR)
- Pass-2 RUN peptide q is also set to run precursor q (Pass2PerFileWorker). Fixing it moves the protein
  FDR gate (ProteinFdr uses RunPeptideQvalue), so it is left for Mike.

## Progress
- [x] Step 1: pass-2 experiment peptide q (StreamedCompetitionState.CompetePeptides)
- [x] Step 2: experiment peptide PEP (experiment sidecar v3)
- [x] Step 3: protein-group PEP (ProteinFdr.ComputeGroupPeps, symmetric ungated fit)
- [x] Step 4: run-level precursor PEP (per-run sidecar v8, RECORDS_PER_CHUNK 2048 -> 1536)
- [x] Unit tests (643 pass; new FdrTest.TestPeptideRunAndProteinPeps), docs (07, 08, 12, 14, DIVERGENCES)
- [x] Stellar regression PASS (regression-20261002_120644_38408); blib/protein_fdr goldens unchanged
- [x] Real-data check: 2nd-pass experiment sidecar, 83,279 multi-entry peptides, 0 disagree on
      peptide q or peptide PEP (was 2,078 reported peptides disagreeing on peptide q)
- [x] Committed locally b636c35466
- [ ] /code-review max, triage
- [ ] regression-parallel -Dataset All
- [ ] Push, open PR against the port branch (label osprey)

## Decisions (best guesses for Mike)
- Run PEP under OSPREY_PASS2_QVALUE=transfer: moved/gap-filled peaks report 1.0 (no score->PEP table).
- Protein-group PEP: fitted on ungated-target vs ungated-decoy picked winners, evaluated at the
  gated target score; the q-value competition itself is unchanged.
- FdrEntry grows 16 bytes (RunPep, ExperimentPeptidePep); per-run sidecar grows 22% (36 -> 44 B).
