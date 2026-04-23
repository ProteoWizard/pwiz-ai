# TODO-20260423_osprey_sharp_stage6.md — Phase 4 Stage 6: refinement parity

> Sub-sprint of **TODO-20260423_osprey_sharp.md** (Phase 4
> umbrella, Stages 6-8). The umbrella is the authoritative plan;
> this file tracks the Stage 6 branch, progress log, and PR links.

## Branch Information

- **pwiz branch**: `Skyline/work/20260423_osprey_sharp_stage6`
- **osprey branch**: TBD (created only if a parity-critical upstream port needs landing)
- **Base**: `master` (pwiz at `80f5341bc`) / `main` (maccoss/osprey at `2b73ba8`)
- **Created**: 2026-04-23
- **Status**: In Progress
- **GitHub Issue**: (none — tool work, no Skyline integration yet)
- **PR**: (pending)

## Scope

Covers Priorities 1-3 of the umbrella TODO:

1. **Upstream resync delta catalog**: scan `maccoss/osprey:main`
   for commits since the last review (2026-04-21 session caught
   up to `885339b`). Disposition each as parity-critical port /
   Stages 1-5 drift / out-of-scope. Dump to
   `ai/.tmp/stage6_upstream_delta.md`.
2. **Multi-file Stage 5 validation**: extend the single-file
   Stellar Stage 5 parity (already bit-identical at 462,802 rows /
   34,158 precursors / 30,712 peptides / 5,471 protein groups) to
   3-file Stellar + Astral. Exercises best-per-precursor
   subsampling across files + experiment-level FDR compaction,
   neither of which single-file touches.
3. **Stage 6 refinement parity**: multi-charge consensus leader
   pick + cross-run RT reconciliation + second-pass re-score at
   locked boundaries + re-trained Percolator SVM. Add the three
   new diagnostic dumps per the umbrella (`OSPREY_DUMP_CONSENSUS`
   / `OSPREY_DUMP_RECONCILIATION` / `OSPREY_DUMP_REFINED_FDR`,
   each with matching `_ONLY` early-exit), mirroring the Stage 5
   four-dump pattern that shipped in PR #18 / pwiz #4160.

## Gate for PR

Bit-identical cross-impl parity on Stellar + Astral, single-file
and 3-file, through end-of-Stage-6. `Compare-Percolator.ps1`
extended (or a sibling harness script added) for consensus +
reconciliation dump comparisons. Stages 1-5 parity gates
(`Test-Features.ps1` 21/21 @ 1e-6 + end-of-Stage-5 Percolator
dump byte-identical) must still hold.

## See also

- `ai/todos/active/TODO-20260423_osprey_sharp.md` — Phase 4
  umbrella plan (Stages 6-8 in detail).
- `ai/todos/completed/TODO-20260422_ospreysharp_stage5_diagnostics.md`
  — Stage 5 precedent: one-commit-per-logical-change, bisection-
  to-ULP discipline, four-dump diagnostic harness +
  `Compare-Percolator.ps1`.
- `ai/docs/osprey-development-guide.md` — HPC flags, env-var
  reference, bisection methodology, determinism patterns,
  steel-thread parity doctrine.
- `C:\proj\osprey\CLAUDE.md` — Rust-side project overview and
  critical invariants.

## Progress log

### Session 1 (2026-04-23) — Kickoff + Percolator streaming port

**Priority 1 (upstream delta catalog)**: shipped as
`ai/.tmp/stage6_upstream_delta.md`. Eight commits from
`885339b..2b73ba8`; no outstanding ports other than the reconciliation
gate broadening (Stage 6 work, handled natively when we write the
Stage 6 port).

**Priority 2 (multi-file Stage 5 validation)**: partial. After
shipping the Stage 5 dump-text-format fix (pwiz #4163, merged
`80f5341bc`):
- Stellar 3/3 files byte-identical on all four Stage 5 dumps.
- Astral 0/3 files — structural divergence (Rust subsample dump has
  300,000 rows all `in_subsample=true`; C# has 1,683,779 rows with
  300,000 `true` + 1,383,778 `false`). Root-caused to a missing C#
  code path, not a regression. Details below.

**Root cause of Astral divergence — Percolator streaming path**

Rust's `osprey/src/pipeline.rs::run_percolator_fdr` has two branches
gated by `total_entries > max_train * 2` (i.e. > 600K entries):
- **Direct**: all entries to `run_percolator`, Percolator itself
  subsamples to `max_train = 300K` for training. Stellar (462K)
  uses this; OspreySharp uses it unconditionally.
- **Streaming**: best-per-precursor dedupe of all entries across
  all files (~500K for Astral single-file), peptide-grouped
  subsample to 300K, train `run_percolator(subset, train_only=true)`,
  then score ALL entries via the averaged fold models + standardizer
  and compute q-values on that flat score array.

Committed by Mike 2026-03-25 (commit `1d4a9a0e`), which predates
OspreySharp's Phase 1-3 port. The optimization is what mokapot
does too on large datasets — train on deduped per-precursor, avoid
training-set correlation. OspreySharp never had the streaming path;
Stellar never triggered it so the gap was latent.

**Port plan**

Add a streaming branch to `OspreySharp.AnalysisPipeline.RunPercolatorFdr`
mirroring the Rust phases:

| Phase | Rust src | C# work | Notes |
|---|---|---|---|
| Best-per-precursor dedup | `pipeline.rs:4256-4296` | new `SelectBestPerPrecursor` helper | two `Dictionary<uint, (int fi, int li, double score)>`; `base_id = entry.EntryId & 0x7FFFFFFF` |
| Peptide-grouped subsample | `pipeline.rs:4300-4360` | new `SubsamplePeptideGroups` helper | XOR-shift RNG seeded at `config.seed = 42`; constants 13/7/17; sort groups by peptide key before shuffle |
| Train-only Percolator | `pipeline.rs:4447-4460` | extend `PercolatorConfig.TrainOnly` flag; split `PercolatorFdr.RunPercolator` | returns `FoldWeights` + `Standardizer` + `IterationsPerFold` only, no scoring |
| Score all entries | `pipeline.rs:4460-4620` | new `ScoreAllEntriesWithModel` | apply standardizer -> averaged SVM weights; score = dot + bias |
| Q-values + PEP | `pipeline.rs:4620-4800` | wire existing `PercolatorFdr.ComputeQValues` + `PepEstimator` into streaming finish | per-file + experiment-level |

Byte-parity risks:
- XOR-shift RNG must use identical seed + constants + call order.
- Dict iteration order: Rust sorts `HashMap.keys().copied()` before
  use; C# must call `.OrderBy` explicitly (C# Dictionary iteration
  is insertion-order on .NET Core, but Rust's is randomized).
- Peptide-group sort key: byte-ordinal peptide string.
- Float reductions during scoring stay serial.

**Branch**: `Skyline/work/20260423_osprey_sharp_stage6` (pwiz-work1).
**Gate**: `Compare-Stage5-AllFiles.ps1` 3/3 PASS on Stellar (regression
check) AND 3/3 PASS on Astral (new parity).

**Path-normalization follow-up** (`LibraryIdentityHash` slash-
direction issue): deferred to a later PR; hitting it only when the
CLI is invoked with mixed slash styles, so Compare-Stage5 is
unaffected.
