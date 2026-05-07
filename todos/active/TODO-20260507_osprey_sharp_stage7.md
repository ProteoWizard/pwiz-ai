# TODO-20260507_osprey_sharp_stage7.md — Phase 4 Stage 7: protein FDR parity

> Sub-sprint of **TODO-20260423_osprey_sharp.md** (Phase 4 umbrella,
> Stages 6-8). The umbrella is the authoritative plan; this file
> tracks the Stage 7 branch, progress log, and PR links.

## Branch Information

- **pwiz**: TBD (suggested `Skyline/work/20260507_osprey_sharp_stage7`)
- **osprey**: TBD (suggested `feature/stage7-protein-fdr`)
- **Base**: `master` (pwiz) / `main` (maccoss/osprey)
- **Created**: 2026-05-07
- **Status**: Not started — Stage 6 closed cleanly, ZSTD-by-default validated end-to-end (see `Predecessors`).
- **GitHub Issue**: (none — tool work, no Skyline integration yet)

### Predecessors

| Predecessor | What it shipped |
|---|---|
| `ai/todos/completed/TODO-20260429_osprey_sharp_stage6.md` | Stage 6 end-to-end byte parity on Stellar + Astral (pwiz #4187) |
| `ai/todos/completed/TODO-20260507_ospreysharp_missing_scoring_columns.md` | Six previously-allowlisted scoring columns now round-trip byte-for-byte (pwiz #4188) |
| `ai/todos/active/TODO-20260428_parquet_zstd.md` | Cross-tool Parquet compatibility with Zstd-only output (pwiz #4172) — pending squash-merge |

Stage 6 is "fully done without caveats": empty allowlist removed
from `Compare-Stage6-Crossimpl.ps1`; Stages 1-4 + Stage 5 + Stage 6
all bit-parity green on Stellar with both impls writing Zstd-
compressed parquet (no Snappy fallback in the cross-tool path).

## Objective

Walk the protein-level FDR pipeline (Stage 7) to bit-identical
cross-impl parity on Stellar + Astral, single-file and 3-file:

- **Parsimony**: bipartite peptide↔protein graph → protein groups
  via identical-set merging + subset elimination + greedy razor
  assignment for shared peptides.
- **Picked-protein TDC**: target-decoy competition on best peptide
  score per protein group. Target winners emitted; decoy winners
  consumed by cumulative FDR only.
- **Protein q-value assignment** at the group level (not per
  individual protein).

`crates/osprey/CLAUDE.md` has extensive design notes on protein FDR
algorithm choices (parsimony tie-breaking, decoy collision rules,
the picked-protein vs. classic-TDC trade-off). Re-read before
starting.

## Strategy

### Step 1: Upstream resync delta catalog

Same template as the Stage 6 sub-sprint's first step. Scan
`maccoss/osprey:main` for commits since the Stage 6 close-out
(2026-05-06 baseline = osprey-mm `main`). Disposition each as:

- **parity-critical port** — must land in OspreySharp before the
  Stage 7 walk starts, otherwise we'd be chasing drift introduced
  upstream rather than bisecting our own gaps
- **stages 1-6 drift** — flag for a small re-validation round
  before Stage 7
- **out-of-scope** — note and move on

Dump findings to `ai/.tmp/stage7_upstream_delta.md`.

### Step 2: Stage 7 diagnostic dump in Rust + C#

Mirror the Stage 5 / Stage 6 four-dump pattern: add an
`OSPREY_DUMP_PROTEIN_FDR` env-var-gated dump in both
implementations, plus a matching `OSPREY_DUMP_PROTEIN_FDR_ONLY`
early-exit. Dump shape per protein group:

```
group_id<TAB>accessions<TAB>n_unique<TAB>n_shared
       <TAB>best_peptide_score<TAB>group_qvalue
       <TAB>is_target_winner
```

Sort stably by `(is_decoy ASC, group_qvalue ASC, group_id ASC)` so
the first PASS row is reproducible across runs.

Land the dump in Rust **first** (enables bisection without C#
needing to be working yet), then mirror in C#. PR each side
separately so the two sides can be reviewed independently.

### Step 3: C# port — parsimony

Port the bipartite-graph reduction from `crates/osprey/src/protein_fdr.rs`
to `pwiz_tools/OspreySharp/OspreySharp.FDR/`. Drive selection of
group representative + razor assignment by stable-sort hooks
(prefer `OrderBy`/`ThenBy` chains with explicit comparers — no
`HashSet<Protein>` orderings, no `Dictionary` enumeration ordering
relied on for parity). Bisection target: per-group `accessions`
match Rust byte-for-byte after sorting.

### Step 4: C# port — picked-protein TDC

Port the target-decoy competition + cumulative FDR + q-value
assignment. The Stage 5 SVM-score scoring function for
"best peptide score per group" is already bit-parity, so
divergence here is most likely in:

- decoy collision rules (which target a decoy displaces)
- tie-breaking when two groups have identical best-peptide scores
- monotone q-value enforcement (in particular, `min(q_i)` over `i >= rank`)

Target: byte-identical `OSPREY_DUMP_PROTEIN_FDR` on Stellar +
Astral, single-file and 3-file.

### Step 5: 3-file regression

Once single-file is bit-identical, run 3-file Stellar + Astral.
Watch for cross-file aggregation differences (a protein passing in
file A but not file B: how does that interact with the experiment-
level group? — this is where Stage 5 multi-file's
"experiment-passing-but-not-run-passing" semantics intersect
with Stage 7).

## Gate for PR

Bit-identical cross-impl parity on Stellar + Astral, single-file
**and** 3-file, through end-of-Stage-7. `Compare-Stage5-AllFiles`
+ `Compare-Stage6-Crossimpl` continue green (no regression).
A new `Compare-Stage7-ProteinFdr.ps1` (or extension to an
existing harness script) covers the new dump.

Stages 1-6 parity gates must still hold:
`Test-Features.ps1` 21/21 @ 1e-6, end-of-Stage-5 Percolator dump
byte-identical, Stage 6 `Compare-Stage6-Crossimpl` green with the
empty allowlist that landed in pwiz #4187 / #4188.

## Notes

- Stage 7 is the last "computational" stage before Stage 8 output
  generation. Once this is bit-parity, the remaining work is a
  row-level `.blib` SQLite comparator + the scaffolding to drive
  it from the existing harness.
- The `ZstdSharp` codec is in the cross-tool path now (pwiz #4172,
  ai script change `bc411e2`); no Snappy fallback. Any new dumps
  this sprint emits should match the existing Stage 6 codec
  conventions (same line endings, same float-formatting helpers in
  `OspreyDiagnostics.cs`).
- The patched `pwiz_tools/Shared/Lib/Parquet/ParquetNet.dll`
  (Thrift skip fix; see `maccoss-developers/skylinedev/Parquet.Net/`
  fork + upstream PR aloneguid/parquet-dotnet#747) is required for
  C# to read Rust-emitted parquet metadata. If that PR lands and
  ships before Stage 7 closes, swap back to the stock NuGet
  release (see PATCH-NOTES.md in the fork for the procedure).

## See also

- `ai/todos/active/TODO-20260423_osprey_sharp.md` — Phase 4
  umbrella (Stages 6-8).
- `ai/todos/completed/TODO-20260429_osprey_sharp_stage6.md` —
  Stage 6 close-out (immediate predecessor).
- `ai/todos/completed/TODO-20260507_ospreysharp_missing_scoring_columns.md`
  — six-column round-trip (immediate predecessor).
- `crates/osprey/src/protein_fdr.rs` — Rust source of truth for
  parsimony + picked-protein TDC.
- `crates/osprey/CLAUDE.md` — protein-FDR design notes (re-read
  before starting Step 3).
- `pwiz_tools/OspreySharp/Osprey-workflow.html` — pipeline diagram
  with "you are here" marker; update at end of sprint.

## Progress log

(empty — sprint not yet started)
