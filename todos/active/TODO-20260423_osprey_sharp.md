# TODO-20260423_osprey_sharp.md — Phase 4: Stages 6-8 parity walk

> **Pipeline diagram**:
> [`pwiz_tools/OspreySharp/Osprey-workflow.html`](../../../pwiz/pwiz_tools/OspreySharp/Osprey-workflow.html)
> — open this first for the canonical stage definitions, current
> "you are here" marker, and per-stage parity/performance evidence.
> Every "Stage N" reference in this TODO refers to the stages in
> that diagram.
>
> **Terminology note**: "Phase N" in TODO filenames refers to
> development sprints. Phases 1-3 covered Stages 1-4. Stage 5 parity
> + the diagnostic harness shipped as a separate sub-sprint
> (**TODO-20260422_ospreysharp_stage5_diagnostics.md**, five PRs in
> review). This TODO is the continuing Phase 4 sprint covering
> pipeline **Stages 6-8** plus the Stage 5 multi-file validation
> that the 2026-04-22 sub-sprint didn't exercise.

## Branch Information

- **Branch**: TBD. Will create a new `Skyline/work/20260423_*`
  branch (pwiz) + matching `feat/*` branch (osprey) at the start of
  the Step 1 upstream resync catalog.
- **Base**: `master` (pwiz) / `main` (maccoss/osprey). Both are
  aligned as of 2026-04-23 post-merge of the Stage 5 sub-sprint +
  Gauss fix.
- **Created**: 2026-04-20 (original planning); rescoped 2026-04-22
  after Stage 5 split; renamed + started 2026-04-23.
- **Status**: Active — Phase 4 (Stages 6-8) begins 2026-04-23.
- **GitHub Issue**: (none — tool work, no Skyline integration yet)

## Phase History

Phases 1-3 brought pipeline Stages 1-4 to bit-identical 21 PIN
feature parity on Stellar + Astral vs `maccoss/osprey:main`, plus
net472+net8.0 multi-targeting and the `--no-join` / `--join-only`
HPC split. Full session-by-session history in:

- `TODO-20260409_osprey_sharp-phase1.md` — Sessions 1-7
- `TODO-20260409_osprey_sharp-phase2.md` — Sessions 8-11
- `TODO-20260409_osprey_sharp.md` — Sessions 12-19

(Moved to `ai/todos/completed/` on 2026-04-21 after PR #4155 merged.)

Phase 4's Stage 5 sub-sprint (2026-04-21/22, merged 2026-04-23)
shipped Stage 5 cross-impl bit-parity on single-file Stellar + the
diagnostic harness. See
**ai/todos/completed/TODO-20260422_ospreysharp_stage5_diagnostics.md**
for the complete log (osprey #16/#17/#18 + pwiz #4159/#4160, all
merged 2026-04-23). The coordinated Gauss-solver robustness fix
(osprey #15 + pwiz #4156, same day) also landed; see
**ai/todos/completed/TODO-20260421_osprey_gauss_solver.md**. Key
outcomes feeding this TODO:

- `D:\test\osprey-runs\stage5\stellar\rust_scores.parquet` is the
  canonical Rust-generated Stage 4 output, ready as input for
  Stages 6-8 walks via `--join-only --input-scores`.
- Four Stage 5 diagnostic dumps + `Compare-Percolator.ps1` are in
  place as the regression gate.
- Rust and OspreySharp both emit identical 34,158 precursors / 30,712
  peptides / 5,471 protein groups at 1 % FDR on Stellar single-file.

## Objective

Extend cross-implementation parity from the now-bit-identical Stage
5 boundary through Stages 6, 7, and 8:

| Stage | Name | Scope |
|-------|------|-------|
| 5 (multi-file) | First-pass FDR (Percolator SVM) | Best-per-precursor across files, experiment-level FDR compaction — single-file is done; 3-file remains |
| 6 | Refinement | Multi-charge consensus, cross-run RT reconciliation, second-pass re-score at locked boundaries, re-trained Percolator SVM |
| 7 | Protein FDR | Parsimony, subset elimination, razor assignment, picked-protein TDC on best peptide scores |
| 8 | Output | BiblioSpecLite .blib (RefSpectra, RetentionTimes, Modifications, Proteins, Osprey fragment tables) |

The Phase 1-3 bisection-to-ULP discipline applies stage-by-stage
here too. Each stage adds its own diagnostic dump(s); each stage
must pass bit-parity (or near-parity at a principled tolerance)
before advancing to the next.

## Strategy

### Step 1: Upstream resync review (may be partial from 2026-04-22 already)

Mike continued Stages 5-8 work in `maccoss/osprey:main` during the
Phase 1-3 sprint. Several commits were already identified in the
2026-04-21 session (`06905be` protein FDR always-on, `f03f162` +
`778460e` reconciliation, `3551668` LOESS, `2db5f1c` RT penalty
sigma, `4d0119d` CWT intensity tiebreaker, `885339b` peak boundary
truncation). Re-catalog any further upstream commits landed since
2026-04-22 and disposition each:

- **Parity-critical** → first-pass port into OspreySharp, one commit
  per logical upstream change.
- **Stages 1-4 drift** → port immediately, re-run `Test-Features.ps1`
  on Stellar + Astral, confirm 21/21 @ 1e-6 still holds.
- **Stage 5 drift** → port, re-run the end-of-Stage-5 compare, confirm
  it still matches.
- **Out of scope** → skip; note in the review dump.

Dump to `ai/.tmp/stage6_upstream_delta.md`.

### Step 2: Multi-file Stage 5 (3-file Stellar + Astral)

Extend the Step 2 work from the Stage 5 sub-sprint to 3-file
datasets. Exercises:

- Best-per-precursor subsampling across files (not just within one).
- Experiment-level FDR compaction.
- Rust and OspreySharp agreeing on precursor count across
  replicates.

Canonical 3-file Rust Parquets land at
`D:\test\osprey-runs\stage5\stellar\` and `...\astral\`
(extending the single-file layout).

### Step 3: Stage 6 refinement parity

Starting from the canonical Rust Parquets + Stage 5 checkpoint
(cross-impl identical), walk forward:

- **Multi-charge consensus**: consensus leader pick among
  FDR-passing charge states of each peptide. Dump leader picks +
  scores per peptide group.
- **Cross-run RT reconciliation**: shared RT boundaries across
  replicates from the consensus set. Dump reconciled boundaries
  per entry.
- **Second-pass re-score at locked boundaries**: re-extract XICs,
  re-compute PIN features, re-train Percolator SVM. Dump second-pass
  SVM weights + final q-values.

Expected new dumps (mirror the Stage 5 pattern):
`OSPREY_DUMP_CONSENSUS` / `OSPREY_DUMP_RECONCILIATION` /
`OSPREY_DUMP_REFINED_FDR`. Each with its own `_ONLY` early-exit.

### Step 4: Stage 7 protein FDR parity

Walk the protein-level FDR pipeline:

- **Parsimony**: bipartite graph → protein groups via identical-set
  merging + subset elimination + greedy razor assignment.
- **Picked-protein TDC**: target-decoy competition on best peptide
  score per group. Target winners emitted; decoy winners consumed
  by cumulative FDR only.
- **Q-value assignment** at the protein group level.

Dump: per-protein-group `(group_id, accessions, qvalue,
best_peptide_score, n_unique, n_shared)`. Sort stably.

CLAUDE.md (in osprey) has extensive design notes on protein FDR;
re-read before starting.

### Step 5: Stage 8 .blib output parity

The end of the pipeline: row-level comparison between Rust-written
and C#-written `.blib` on the same input. The .blib is SQLite; the
tables to compare:

- `RefSpectra` (one row per passing precursor)
- `RetentionTimes` (one row per per-file observation, including
  NULL retentionTime for run-non-passing-but-experiment-passing
  observations)
- `Modifications`
- `Proteins`
- Osprey fragment tables (library theoretical fragments)

SQLite timestamp columns (e.g. `createTime`) differ trivially — a
row-level diff tool that ignores those is needed. SHA-256 of the
table contents minus timestamps is a cheap gate.

### Step 6: End-to-end pipeline parity

Drop `--input-scores` entirely. Run both tools end-to-end (no
Parquet boundary) on single-file + 3-file, confirm the full
pipeline is wire-compatible. This catches any Stage 4 → Stage 5
join-side bug that the explicit `--join-only` path could hide.

## Tasks

### Priority 1: Upstream resync delta catalog

- [ ] Re-scan `maccoss/osprey:main` for any commits landed between
      the 2026-04-22 Stage 5 sub-sprint merge and the Phase 4 restart.
      Dump dispositions to `ai/.tmp/stage6_upstream_delta.md`.
- [ ] Port parity-critical Stages 5-8 changes, one commit per
      logical upstream change.
- [ ] Re-run end-of-Stage-5 parity gate + Stellar/Astral Stage 1-4
      parity after every port.

### Priority 2: Multi-file Stage 5 validation

- [ ] Capture 3-file Rust + C# Parquets for Stellar and Astral.
- [ ] Re-run end-of-Stage-5 Percolator dump on the 3-file inputs.
- [ ] Confirm Rust vs OspreySharp cross-impl parity on the dump
      (same Compare-Percolator.ps1 harness, no new tooling).
- [ ] Update `Osprey-workflow.html` if multi-file evidence adds
      per-dataset numbers worth showing.

### Priority 3: Stage 6 refinement

- [ ] Cross-impl-diff tooling for consensus / reconciliation
      (extend Compare-Percolator.ps1 or add a sibling).
- [ ] Multi-charge consensus dump parity (single-file + 3-file).
- [ ] Cross-run RT reconciliation dump parity (3-file only —
      single-file doesn't exercise it).
- [ ] Second-pass re-score + SVM parity.
- [ ] Refined-q-value end-of-Stage-6 dump parity.

### Priority 4: Stage 7 protein FDR

- [ ] Parsimony dump parity (per-group accessions, n_unique, n_shared).
- [ ] Protein q-value dump parity (picked-protein TDC winners).

### Priority 5: Stage 8 .blib output

- [ ] `RefSpectra` row-level parity.
- [ ] `RetentionTimes` row-level parity (including NULL
      retentionTime semantics for experiment-only-passing entries).
- [ ] `Modifications` / `Proteins` / fragment-table parity.
- [ ] Update `Osprey-workflow.html` footer: final status, "you are
      here" marker retired, final evidence numbers.

### Priority 6: End-to-end pipeline parity

- [ ] Single-file end-to-end Stellar + Astral (no Parquet boundary).
- [ ] 3-file end-to-end Stellar + Astral.

## Quick Reference — must-know commands and locations

**Stage 1-4 parity (carried forward)**:
```bash
pwsh -File './ai/scripts/OspreySharp/Test-Features.ps1' -Dataset Stellar
pwsh -File './ai/scripts/OspreySharp/Test-Features.ps1' -Dataset Astral
```

**Stage 5 end-of-stage parity (established 2026-04-22)**:
```bash
# With OSPREY_DUMP_PERCOLATOR=1 / OSPREY_PERCOLATOR_ONLY=1 set on
# each tool, pointed at the canonical Rust Parquet:
pwsh -File './ai/scripts/OspreySharp/Compare-Percolator.ps1'
```

**HPC split flags**:
- `--no-join --parquet-compression snappy` — Rust writes
  Snappy-compressed per-file scores parquet, exits before Stage 5.
- `--join-only --input-scores <path>` — resume from a prior
  scores parquet. VERSION / library-hash / search-hash validators
  must match.

**Repos**:
- `C:\proj\osprey` — `maccoss/osprey:main` (primary).
- `C:\proj\osprey-fork` — `brendanx67/osprey` (retired; do not extend).
- `C:\proj\pwiz-work1` (or `pwiz-work2` / `pwiz` — depends on which
  worktree is free) — OspreySharp C# branch for this TODO.

**Test data**: `D:\test\osprey-runs\{stellar,astral}\`.

Canonical Stage 5 inputs:
- `D:\test\osprey-runs\stage5\stellar\rust_scores.parquet`
- `D:\test\osprey-runs\stage5\astral\rust_scores.parquet` (to be
  created in Priority 2).

## Critical reminders

1. **Don't break earlier-stage parity.** Every upstream port +
   every Stage 6+ change must re-run the Stage 5 end-of-stage dump
   and the Stage 1-4 parity gate. Any drift there must be
   root-caused before advancing.
2. **Bisection-to-ULP discipline.** If a Stage 6-8 port doesn't
   produce bit-identical output, add the dumps needed to isolate the
   drift. Prefer dumps over speculation; prefer the smallest
   possible dump that isolates the drift over a large
   one-size-fits-all dump.
3. **Cross-impl changes go to BOTH tools the same session.** Any
   scoring- or FDR-affecting change applied in C# needs the
   matching change in Rust — otherwise parity walks diverge.
4. **Steel-thread parity doctrine.** When a small gap blocks the
   walk, prefer a tiny fix over a parity switch. When a switch is
   the only option, ship it as debt-tracked (the 2026-04-22
   session's `OSPREY_CSHARP_SCALAR_SVM` audit is the template: a
   switch that helped localize the bug got replaced by a 20-LOC fix
   once the gap was clear).
5. **Record each session's progress** in this TODO under a dated
   section. Future sessions pick up where the last left off.

## See also

- `ai/docs/osprey-development-guide.md` — full dev guide. HPC
  flags, env-var reference, bisection methodology (Stages 1-5),
  determinism patterns, steel-thread doctrine, commit/PR
  conventions vs. Skyline.
- `C:\proj\osprey\CLAUDE.md` — Rust-side project overview and
  critical invariants.
- `ai/todos/completed/TODO-20260422_ospreysharp_stage5_diagnostics.md`
  — sibling TODO, Stage 5 parity + diagnostic harness. Completed
  2026-04-23 (all five PRs merged).
- `ai/todos/active/TODO-20260423_osprey_sharp_stage6.md` — Stage 6
  sub-sprint (Priorities 1-3 of this umbrella). Created 2026-04-23.
- `ai/todos/active/TODO-OR-20260417_osprey_rust_upstream.md` —
  staged sprint to upstream Rust diagnostics + perf.
- `ai/scripts/OspreySharp/` — harness scripts: `Test-Features.ps1`,
  `Compare-Diagnostic.ps1` (Stages 1-4), `Compare-Percolator.ps1`
  (Stage 5+), `Bench-Scoring.ps1`, `Profile-OspreySharp.ps1`.

## Progress log

### 2026-04-22 — Rescoped after Stage 5 sub-sprint

Original TODO split into two. The Stage 5 parity + diagnostic
harness work (which grew to fill 2026-04-21 and 2026-04-22) is now
captured in **TODO-20260422_ospreysharp_stage5_diagnostics.md**. It
completes when its five open PRs merge. This TODO is trimmed to the
remaining Stages 6-8 forward walk.

First working session against this trimmed scope starts after those
PRs merge. Expected first step: Priority 1 (upstream resync delta
check), then Priority 2 (multi-file Stage 5 validation) to confirm
the 3-file case inherits single-file parity before moving to Stage
6 refinement.

### 2026-04-23 — Renamed and unblocked

Renamed from `TODO-20260420_osprey_sharp.md` to
`TODO-20260423_osprey_sharp.md` to reflect the actual Phase 4
start date. All blockers cleared 2026-04-23:

- Stage 5 diagnostics sub-sprint merged (osprey #16/#17/#18, pwiz
  #4159/#4160). `main`/`master` now carry the aligned baseline.
- Gauss-solver robustness coordinated fix merged (osprey #15, pwiz
  #4156). Stellar + Astral `Test-Features.ps1` still 21/21 @ 1e-6.
- A stale WIP on `feat/stage5-diagnostics` in `C:\proj\osprey` that
  looked like it might be un-committed cleanup turned out to be an
  unrelated experimental revert; discarded and the repo is now on
  `main` at `2b73ba8`.

Ready to start Priority 1: re-scan `maccoss/osprey:main` for any
commits landed since the 2026-04-22 delta catalog attempt and
disposition each (parity-critical port vs. out-of-scope). Dump
findings to `ai/.tmp/stage6_upstream_delta.md`.
