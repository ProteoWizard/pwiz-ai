# osprey: Surface single-peak multiple-ID co-assignment in --model-diagnostics

## Branch Information
- **Branch**: `Skyline/work/20260808_peak_coassignment_diagnostics`
- **Base**: `master`
- **Created**: 2026-08-08
- **Status**: In Progress
- **GitHub Issue**: [#4522](https://github.com/ProteoWizard/pwiz/issues/4522)
- **Module**: `osprey`
- **PR**: (pending)

## Objective

DIA search can assign two IDs to a single chromatographic peak without sequence-specific
differentiating evidence. Entrapment makes this measurable: an entrapment peptide sharing a peak
with a better-scoring target is a demonstrated false co-assignment.

Measured on a 40-file Astral cohort (TDP-43 plasma-EV, q <= 0.01), the target background sits at
4.3-5.1% of accepted precursors across all seven library variants -- roughly 1,200 accepted target
IDs per run on a peak a better-scoring same-mass precursor already explains. Entrapment is enriched
4.0-6.6x over that background in every arm.

This issue asks only to **surface the effect in the `--model-diagnostics` report**. What to do about
it is a separate question.

A precursor pair "shares a peak" when it is in the same run, at the same apex RT (+/- 0.05 min), and
within +/- 0.01 Da in precursor mass. No knowledge of the sequence relationship is required -- the
metric is pure geometry, which is why it finds relationships nobody thought to look for.

## Design (settled 2026-08-08 -- read this before re-deriving)

**Both passes are covered, and NEITHER needs the FDR score path touched.**

Pass 2 is what the user actually receives, so it is the one that must be covered; pass 1 is the
scoring/peak-assignment property the issue is about. Reporting both makes the **delta** the
interesting quantity -- reconciliation manufactures co-assignment by design (`MultiChargeConsensus`
pulls disagreeing charge states onto the leader's peak; `ForcedIntegration` gap-fills at a consensus
RT), so pass2 - pass1 is "how much did reconciliation add on top of scoring".

* **Pass 2**: `SecondPassFdrTask` already hands `WritePass2AndFinalize` the resident
  `RescoredEntries` pool -- real `FdrEntry` with `ApexRt` populated (`ParquetScoreCache.cs:809`,
  `:1284` on the survivor reload; `PerFileRescoreTask.cs:1545` on the rescore overlay), and O(survivors),
  not O(rows). A new builder call inside `BuildPass2`; nothing else.
* **Pass 1**: apex RT is NOT on the streaming path the report is built from -- `FdrProjection` was
  shrunk to 32 bytes (#4355) and the counts-only reader pulls only entry_id / charge / is_decoy /
  coelution_sum / modseq. Do NOT plumb it through the score pass. Instead do what the prototype did:
  a bounded per-file pass at report time over the two artifacts already on disk.

**The per-file pass-1 join (from `ai/scripts/Osprey/Entrapment/pass1_entrap.py`):**

| prototype | C# equivalent |
|---|---|
| `read_sidecar(stem + '.1st-pass.fdr_scores.bin')` | `FdrScoresSidecar.ReadRecords(path, Pass.First, onRecord)` -- already streams |
| `pq.read_table(stem + '.scores.parquet', ['entry_id','apex_rt'])` | `ParquetScoreCache` already reads `apex_rt` by name (`:790`, `:1226`) |
| parquet paths | `perFileParquetPaths[fileName]`, in hand in the method that writes the report |
| `sequence` / `protein_ids` -> mass, class | `libraryById` is resident at report time -- exact `PrecursorMz`, no sequence parsing |

Rows are positionally aligned between the sidecar and the parquet. **Assert it, do not assume it** --
the prototype checks full `entry_id` array equality per file and raises on mismatch; carry that check
over. One file resident at a time.

Why this over plumbing: no touch to `ReadFdrStubScalars` / `RowBuffer` / `Accept` /
`Accumulator.Add`, no 6-arg row callback, no perf-gate exposure, and it works on the
resident-projection path (`OSPREY_FDR_PROJECTION=0`) which the plumbing approach would have left
with NaN. Cost to name explicitly: re-reads two columns of every `.scores.parquet` at report time
(~340M rows on the 82-file Astral run). Opt-in behind `--model-diagnostics`; log the wall time so it
is visible rather than a silent tax.

**Deliberate deviations from the prototype (note them in the panel so the numbers do not silently
disagree with the issue):**
* Gate accepted on `EffectiveRunQvalue` at the configured `FdrLevel`, not the prototype's
  experiment precursor q, so the panel's denominators match the per-file / cross-run tables on the
  same page.
* Rank "better-scoring" by SVM score, not q -- it is the same ordering in practice and it gives the
  offenders listing a real score gap.
* At report time the pass-1 sidecar holds PARTIAL records (run_protein_qvalue = 1.0 placeholder;
  first-pass protein FDR patches [52..60] later). The panel uses precursor/peptide q and score only,
  so this is fine -- but say so in a comment, because the prototype read a fully-patched sidecar.

**Exclude same-sequence pairs** (the prototype's `s2 == seq` check). Without it, multi-charge
consensus alone guarantees a large artificial pass-2 rate that means nothing: one peptide, correctly
on one peak, at two charges.

**No existing gate to integrate with.** Nothing in either tree (C# or Rust) attempts to stop two
different sequences from claiming one peak; verified 2026-08-08. `MultiChargeConsensus` /
`select_post_fdr_consensus` group by modified sequence only; the decoy generator's fragment-overlap
gate (`DecoyGenerator.IsCandidateAcceptable`) is target-vs-its-own-decoy at library build time; all
"interference" handling in scoring is intra-precursor (does one precursor's own fragments agree).
The 5% is the absence of a filter, not a broken one.

## Tasks

- [x] Locate the Stage 5 `--model-diagnostics` report generation and the per-file apex RT source
- [x] Confirm which RT source is the true per-run detection -- pass 1 (pre-compaction detection);
      pass 2 is post-reconciliation and is reported alongside as the delivered-to-user number
- [ ] Pure builder in Osprey.FDR over per-file (apexRt, mass, score, key, class) rows, shared by
      both passes
- [ ] Pass-1 per-file sidecar + parquet join at report time, with the entry_id alignment assert
- [ ] Pass-2 build from the resident `RescoredEntries` pool
- [ ] Compute co-assignment: % of accepted precursors sharing a peak with a better-scoring same-mass
      precursor, reported separately for targets, entrapment, and decoys
- [ ] Report the enrichment ratio entrapment/target (the interpretable, density-controlled quantity)
- [ ] Add a dRT histogram for co-assigned pairs, separating same-feature jitter from chance
      co-elution
- [ ] Add a listing of the worst offenders (co-assigned pairs ranked by score gap) -- this is what
      makes the panel actionable rather than merely informative
- [ ] Report the pass1 -> pass2 delta (how much co-assignment reconciliation adds)
- [ ] Decide and document the RT tolerance; make the choice visible in the panel rather than baked in
- [ ] Regression test (see below)

## Caveats to carry into the implementation

- **RT tolerance sensitivity.** Entrapment is enriched at every tolerance tested, but the magnitude
  depends on it: 2.3x at +/-0.01 min, 2.9x at +/-0.02, 5.7x at +/-0.05, 4.3x at +/-0.10, 3.4x at
  +/-0.25. The +/-0.05 figure is physically motivated (it matches the observed same-feature apex
  jitter of 0.046 min) but it also maximises the ratio, so the honest headline is a range. The dRT
  histogram makes the choice visible.
- **The set-wise isobaric gate reduces entrapment co-assignment but not the target background**
  (issue comment). It moved entrapment enrichment 6.6x -> 3.7x (shuffle) and 5.7x -> 4.2x (foreign),
  and moved the target background not at all. That gate has since been reverted as too broad, so
  shipping libraries sit at the `-no-il` row (I/L filter only), where entrapment enrichment is
  5.7-6.6x.

## Regression Test

- **Test name**: (filled in once written)
- **Test project**: Osprey.Test
- **Fails on master**: (pending)
- **Passes on fix**: (pending)

## References

- Prototype: `ai/scripts/Osprey/Entrapment/peak_coassignment.py` (takes a `pass1_entrap.py` arm JSON)
- Measurement series: `ai/todos/active/TODO-20260801_decoy_similarity_gate.md`

## Progress Log

### 2026-08-08 - Session Start

Starting work on this issue. Created branch and TODO; next step is locating the
`--model-diagnostics` report generation and the per-file apex RT source in Osprey.
