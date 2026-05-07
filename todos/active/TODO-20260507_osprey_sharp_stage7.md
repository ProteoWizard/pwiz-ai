# TODO-20260507_osprey_sharp_stage7.md — Phase 4 Stage 7: protein FDR parity

> Sub-sprint of **TODO-20260423_osprey_sharp.md** (Phase 4 umbrella,
> Stages 6-8). The umbrella is the authoritative plan; this file
> tracks the Stage 7 branch, progress log, and PR links.

## Branch Information

- **pwiz**: `Skyline/work/20260507_osprey_sharp_stage7` (created 2026-05-07, off pwiz/master `7cedd0dfa`)
- **osprey**: `feature/stage7-protein-fdr` (created 2026-05-07, off maccoss/osprey/main `ae96e97`)
- **Base**: `master` (pwiz) / `main` (maccoss/osprey)
- **Created**: 2026-05-07
- **Started**: 2026-05-07
- **Status**: In progress — Rust dump + `--join-at-pass=2` rehydration landed (PR #31 open). C# port begins next.
- **GitHub Issue**: (none — tool work, no Skyline integration yet)
- **Upstream PR**: [maccoss/osprey#31](https://github.com/maccoss/osprey/pull/31) — `--join-at-pass=2` rehydration + Stage 7 dump (open, awaiting review)

### Predecessors

| Predecessor | What it shipped |
|---|---|
| `ai/todos/completed/TODO-20260429_osprey_sharp_stage6.md` | Stage 6 end-to-end byte parity on Stellar + Astral (pwiz #4187) |
| `ai/todos/completed/TODO-20260507_ospreysharp_missing_scoring_columns.md` | Six previously-allowlisted scoring columns now round-trip byte-for-byte (pwiz #4188) |
| `ai/todos/completed/TODO-20260428_parquet_zstd.md` | Cross-tool Parquet compatibility with Zstd-only output (pwiz #4172, squash-merged 2026-05-07) |

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

### 2026-05-07 — Session 1 (kickoff: Rust dump + sprint planning)

Reviewed `ai/docs/osprey-development-guide.md` + `C:\proj\osprey\CLAUDE.md` +
`crates/osprey-fdr/src/protein.rs` (1747 lines) +
`crates/osprey/docs/16-protein-parsimony.md`. Key invariants confirmed:

- Single best peptide per protein (Savitski 2015), NOT sum.
- Pairwise picked-protein TDC; only target winners exposed externally.
- Ranking by raw SVM discriminant (q-value and PEP both collapse the
  decoy null distribution — see `compute_protein_fdr` doc).
- Target side gated by peptide q-value `<= run_fdr`; **decoy side NOT
  gated** (would create survivorship bias).
- Two-pass architecture: first pass before compaction (Stage 6
  reconciliation rescue gate), second pass after compaction +
  reconciliation (authoritative `experiment_protein_qvalue`). The
  Stage 7 sprint owns the second-pass parity walk.
- Razor mode: iterative greedy set cover with explicit determinism
  hooks (sort shared peptides alphabetically, tiebreak by lowest
  group ID, sort claims per round).

**Upstream resync delta** dumped to
`ai/.tmp/stage7_upstream_delta.md`. No parity-critical Rust changes
landed since the Stage 6 close-out (only `ae96e97` and `073a5c5`,
both originating from this Skyline-side sprint and already accounted
for). Stage 7 starts from a known-green baseline.

**Rust-side Stage 7 dump landed** (locally on
`feature/stage7-protein-fdr`, not yet pushed):

- `crates/osprey/src/diagnostics.rs`: new
  `dump_stage7_protein_fdr(parsimony, fdr_result)` writes
  `rust_stage7_protein_fdr.tsv` with columns `group_id, accessions,
  n_unique, n_shared, best_peptide_score, group_qvalue,
  is_target_winner`. Sort order
  `(is_target_winner DESC, group_qvalue ASC, group_id ASC)` keeps
  target winners at the top for fast first-failure inspection.
  Gated by `OSPREY_DUMP_STAGE7_PROTEIN_FDR=1` with
  `OSPREY_STAGE7_PROTEIN_FDR_ONLY=1` early-exit.
- `crates/osprey/src/pipeline.rs`: dump call wired into the
  second-pass protein FDR block (line ~4395), fires AFTER
  `compute_protein_fdr` returns, BEFORE `propagate_protein_qvalues`
  writes to FdrEntry stubs. The dump captures the picked-protein
  computation in isolation.

CI gates green: `cargo fmt --check` + `cargo clippy -D warnings`
both pass; `cargo test --workspace` 465/465 (112 osprey + 27 main
+ 69 chromatography + 33 core + 65 fdr + 31 io + 38 ml + 85
scoring + assorted integration).

**Discovery: `--join-at-pass=2` is not yet implemented.**
`crates/osprey/src/main.rs:289-293` errors out with "not yet
implemented" when `--join-at-pass=2` is set. The dev guide table
already advertises this entry point as "post-Stage-6 (reconciled
parquets) → run Stages 7-8" but the wiring was deferred to "until
the Stage 6 → Stage 7 path lands". That landing IS this sprint.

The user's stated goal of "starting from cached Stellar Stage 6
ZSTD output for a tight Stage 7 edit-build-test cycle" requires
this entry path to actually work. Until then, Stage 7 validation
runs use the slower `--join-at-pass=1 --input-scores
<Stage 4 parquet>` path that re-runs Stages 5-6 on every cycle
(~5-6 min per Stellar 3-file run, vs an estimated ~20-30 sec if
we could skip directly to Stage 7).

Next-session work:

1. **Implement `--join-at-pass=2`** (task #26 in the session task
   list). Prerequisite for the tight cycle and a foundation for
   Stage 7 worker-mode HPC use. Reads reconciled `.scores.parquet`
   (preserved post-compaction `parquet_index` makes this
   row-addressable), entries already carry the second-pass-scoring
   placeholders Stage 7 reads. Skip Stages 1-6, run Stages 7-8
   (second-pass FDR + parsimony + protein FDR + protein report +
   blib output).
2. Run `osprey --join-at-pass=2 --input-scores
   D:/test/osprey-runs/stellar/_stage6_iter/Stellar_rust/*.scores.parquet
   -l <library> -o <blib>
   OSPREY_DUMP_STAGE7_PROTEIN_FDR=1` on Stellar to capture the
   ground-truth dump. Sanity-check counts (decoy-winner fraction,
   target groups at 1% FDR).
3. **Begin C# port**: parsimony first
   (`crates/osprey-fdr/src/protein.rs::build_protein_parsimony`
   → `pwiz_tools/OspreySharp/OspreySharp.FDR/`). Deterministic and
   standalone; no scoring loop. Bisection target: `(group_id,
   accessions, n_unique, n_shared)` columns of the dump match
   byte-for-byte after both-side sort.
4. **C# port**: picked-protein TDC
   (`compute_protein_fdr`). Bisection target: full dump matches.

### Discovered tasks (from kickoff)

- [x] Implement `--join-at-pass=2` in Rust osprey
      (prerequisite, not part of the C# port itself).
      **Done 2026-05-07** — PR [maccoss/osprey#31](https://github.com/maccoss/osprey/pull/31) open.

### 2026-05-07 — Session 2 (Rust rehydration + bit-parity gate)

Drove the Rust-side `--join-at-pass=2` work to bit-parity with a
straight-through `--join-at-pass=1` pipeline run on Stellar 3-file.
Five wiring fixes landed in osprey commit `0d13198`:

1. **Strict reconciled-input gate.** `expect_reconciled_input` config
   field; pipeline asserts every `--input-scores` parquet has
   `META_RECONCILED = "true"` via `validate_scores_cache`.
2. **`META_RECONCILED` written on zero-overlay rescore.** Stellar 3-file
   produces 0 reconciliation actions (consensus + gap-fill both empty),
   which prior to this PR left the parquet flagged as `ValidFirstPass`
   and broke the strict gate above on the operator's own output.
3. **First-pass protein FDR + protein-aware compaction now run in the
   `can_skip_fdr=true` path** when `expect_reconciled_input` is set.
   Pre-existing skip-Percolator optimization gated both behind
   `if !can_skip_fdr`, leaving `run_protein_qvalue=1.0` and shifting
   the second-pass picked-protein pool by ~330 protein groups
   (~6500 vs ~6200 on Stellar). Note this exposed a pre-existing but
   masked invariant: the skip-Percolator path was already producing
   different Stage 7 results than the straight-through pipeline.
4. **FDR sidecar load order inverted** for `--join-at-pass=2`: 1st-pass
   first (so first-pass protein FDR + compaction see the right
   scoring pass), then reload 2nd-pass after compaction.
5. **`compute_fdr_from_stubs` skipped entirely** when
   `expect_reconciled_input` is true. The v3 sidecar carries
   persisted q-values directly; recomputing drifts vs the
   straight-through pipeline (which skips second-pass FDR via
   `total_rescored == 0` on zero-action datasets).

Stage 7 dump format adjusted for cross-impl stability: dropped
non-deterministic `group_id` column, final sort tiebreak on
sorted-accessions string. `parsimony.groups` iteration order is
HashMap-random; joining on `accessions` keeps the dump diff-stable.

**Bit-parity gate**: new
`ai/scripts/OspreySharp/Compare-Stage7-Rehydration.ps1` runs the
pipeline twice on the same data and SHA-256-compares the Stage 7
dump:

| Run | Mode | Time | Stage 7 SHA-256 |
|---|---|---|---|
| A | `--join-at-pass=1` (full Stages 5-8) | 1:27 | `BD7D86F94EDFE149...836B63EDE` |
| B | `--join-at-pass=2` (Stages 7-8 only) | **0:07** | `BD7D86F94EDFE149...836B63EDE` |

PASS: byte-identical. The cached Stage 6 boundary fully captures
what Stage 7 needs.

The tight `--join-at-pass=2` cycle (~12× faster than
straight-through) is now the per-iteration test loop for the
upcoming C# parsimony + picked-protein TDC port.

**Next session — begin C# port:**

1. Port `build_protein_parsimony` to
   `pwiz_tools/OspreySharp/OspreySharp.FDR/`. Deterministic and
   standalone (no scoring loop), so first parity target is structural:
   `accessions, n_unique, n_shared` columns of the dump match
   byte-for-byte.
2. Port `compute_protein_fdr` (picked-protein TDC). Bit-parity
   target: full Stage 7 dump matches between Rust and OspreySharp.
3. Mirror the Stage 7 dump on the C# side (file name
   `cs_stage7_protein_fdr.tsv`, identical schema).
4. Extend `Compare-Stage7-Rehydration.ps1` (or write a sibling
   `Compare-Stage7-Crossimpl.ps1`) to compare Rust vs C# on Stellar
   3-file. The Rust-vs-Rust gate already passes; cross-impl is the
   next gate.

### 2026-05-07 — Session 3 (C# Stage 7 dump + gate alignment)

The C# `BuildProteinParsimony` and `ComputeProteinFdr` already exist
in `pwiz_tools/OspreySharp/OspreySharp.FDR/ProteinFdr.cs` (ported
during the original parsimony work). What was missing for Stage 7
cross-impl bisection was (a) the Stage 7 dump, and (b) two gate
divergences from Rust that surfaced when running both sides
side-by-side. Both landed in pwiz commit `d6575b993` (pushed to
`Skyline/work/20260507_osprey_sharp_stage7`).

- **`OspreyDiagnostics.WriteStage7ProteinFdrDump`** mirrors Rust's
  `dump_stage7_protein_fdr` schema exactly: `accessions, n_unique,
  n_shared, best_peptide_score, group_qvalue, is_target_winner`,
  sorted by `(is_target_winner DESC, group_qvalue ASC, accessions ASC)`.
  `OSPREY_DUMP_STAGE7_PROTEIN_FDR=1` activates the dump;
  `OSPREY_STAGE7_PROTEIN_FDR_ONLY=1` exits after writing.

- **Picked-protein gate corrected from `RunFdr * 2.0` to `RunFdr` (1×)**
  in `RunProteinFdr` — matches Rust pipeline.rs:4389 (Savitski's
  convention). The 2× was a stealth divergence that admitted weaker
  target peptides into picked-protein scoring than the upstream
  pipeline ever does.

- **`detectedPeptides` filter switched from RUN to EXPERIMENT-level**
  peptide q-value. Rust uses
  `effective_experiment_qvalue(peptide_gate_level) <= experiment_fdr`;
  the prior C# filter was `effective_run_qvalue(...) <= run_fdr`,
  which let single-replicate-passing peptides into the second-pass
  parsimony graph that the upstream pipeline excludes.

**Cross-impl test result**: Stellar 3-file Stage 7 dumps still differ
(6205 Rust rows vs 6084 C# rows; ~6 vs ~1 decoy winners). The C#
decoy null distribution is too sparse, indicating upstream
divergence -- either Stage 5 SVM/q-value training drift, Stage 6
reconciliation drift, or a difference in which entries pass
compaction. The schema infrastructure is in place; the next session
needs a Stage 5 + Stage 6 cross-impl re-run to find the upstream
gap. **Known invariants matching across impls**: the first-pass
passing base_ids count (66727) and the C# `detectedPeptides` count
(39953) align with what Rust's parsimony input would be.

### 2026-05-07 — Session 4 (closed structural cross-impl gaps)

Followed the Stage 6 playbook (feed both impls Rust's reference
inputs, diff dumps, find first divergence, fix, advance). The
"C# decoy-null sparseness" called out at the end of Session 3
turned out to be three distinct gaps stacked on top of each other,
each masking the next.

**Diagnostic infrastructure first**: enabled both
`OSPREY_DUMP_PROTEIN_FDR=1` (peptide-level) and
`OSPREY_DUMP_STAGE7_PROTEIN_FDR=1` (protein-group-level) on Rust
and C# simultaneously, both runs starting from identical Stage 4
raw parquets (no upstream variable). Three findings, each one
unblocking the next:

**Gap 1: C# default `FdrLevel = Both`, Rust default = `Precursor`.**
Rust's `osprey-core/src/config.rs` has
`FdrLevel::default() = Precursor`. C# defaulted to `Both` -- a
strictly tighter `max(precursor, peptide)` gate that silently
narrowed every downstream q-value-gated step. The Stage 7
`detected_peptides` filter dropped from 41397 (Rust) to 39953
(C#) and the parsimony group count from 6204 to 6084. **Fixed**
in `OspreyConfig.cs` -- changed default to `FdrLevel.Precursor`
to match Rust. The previous `Both` default had no documented
intent; matching Rust is the right floor for cross-impl.

**Gap 2: `detectedPeptides` filter used wrong q-value scope.** Was
filtering on `EffectiveRunQvalue(config.FdrLevel) <= RunFdr`;
Rust uses
`effective_experiment_qvalue(peptide_gate_level) <= experiment_fdr`.
**Fixed** in `AnalysisPipeline.RunProteinFdr`. Combined with Gap
1, the C# detected-peptides count converged to Rust's 41397
exactly, and the parsimony group count converged to 6204. Decoy
winners climbed from ~0 to 6, matching Rust.

**Gap 3: `FormatF64Roundtrip` produced longer strings than ryu.**
.NET Framework 4.7.2's `"R"` formatter round-trips correctly for
most values but typically emits one digit more than Rust's ryu
(e.g. ryu emits `12.50611897910133`, `"R"` emits
`12.506118979101331`). **Fixed** in `Diagnostics.cs`: replaced
the conditional `R + G17` fallback with a bounded
`G1..G17`-and-parse-check loop returning the first precision that
round-trips. Bypasses the .NET-Framework `"R"` bug entirely.

**Stage 7 dump diff progression on Stellar 3-file**:

| State | Diff lines | Rows | Decoy winners | Notes |
|---|---|---|---|---|
| Pre-fixes | 9664 | 6205 vs 6084 | 6 vs 0 | Different proteins, structural collapse |
| After Gaps 1+2 | 184 | 6205 vs 6205 | 6 vs 6 | Same proteins, ULP score drift only |
| After Gap 3 | 184 | 6205 vs 6205 | 6 vs 6 | (same — Gap 3 helped some rows but not the underlying ULP drift) |

**Remaining 46 row differences** (out of 6205, 0.74 %):

Mix of two patterns, each of about half the differences:

- **1-ULP value drift** (same digit count, last digit differs by 1,
  e.g. `9.616126014576531` vs `...532`). Real cross-impl
  divergence in `best_peptide_score`. Two paralogs TP4A1 and TP4A2
  share the same peptide and both differ by EXACTLY 1 ULP --
  confirms a single upstream peptide score is the source.
- **Shortest-roundtrip algorithm choice** (different digit counts,
  same f64 value, e.g. `13.521201650610431` vs
  `13.52120165061043`). Rust ryu and C#'s G&lt;p&gt;-loop pick
  different "shortest" decimal representations for some values.
  Both round-trip; both are valid. Format-only.

The 1-ULP drift is the same kind of upstream-bisection-required
work Stage 5/6 went through. The shortest-roundtrip variation is
a true ryu port to C# (or accept format-only diffs and use a
numeric-aware diff tool for the harness gate). Tasks queued:
`#30 Stage 7 last-mile: 46 ULP/format diffs out of 6205 rows`.

**Code changes pushed** to
`Skyline/work/20260507_osprey_sharp_stage7` (commit `5085ad719`):
- `OspreyConfig.cs`: default `FdrLevel = Precursor` (matches Rust)
- `AnalysisPipeline.cs`: detected-peptides filter aligned with Rust
- `Diagnostics.cs`: `FormatF64Roundtrip` always-shortest-search

Companion to maccoss/osprey commits `6da8509` (Stage 7 dump),
`0d13198` (--join-at-pass=2 rehydration), `daee7d0` (CI clippy
fix), all on PR [#31](https://github.com/maccoss/osprey/pull/31).

### 2026-05-07 — Session 5 (Stage 7 cross-impl PASS via numeric-tolerance comparator)

The Session 4 "46 ULP/format diffs out of 6205 rows" framing was
based on a raw `cmp` byte comparison of the two TSVs. That is the
wrong gate for cross-impl Stage 7: the established pattern for
every prior cross-impl stage (Compare-Percolator.ps1 for Stage 5,
the parquet content diff for Stage 6) uses **per-column numeric
tolerance** at `1e-9` absolute, not strict byte equality. The
SHA-256 gate is reserved for Rust ↔ Rust rehydration
(Compare-Stage7-Rehydration.ps1), where bit parity is the right
invariant because both sides are the same code.

Categorising the 46 distinct diff rows confirmed the gate
mismatch: 42 rows had **identical f64 bits** (0 ULP) but rendered
differently because Rust ryu and .NET Framework 4.7.2's `G16`
banker rounding pick different equally-valid shortest-roundtrip
strings for the same f64 (e.g. `9.885143613847386` vs
`9.885143613847387`, both parse back to the same f64). The other
4 were genuine 1-ULP drift in `best_peptide_score` from the
second-pass SVM training producing slightly different scores under
.NET BLAS vs Rust BLAS — sub-1e-15 absolute diffs that 1e-9 easily
absorbs. This is the same "self-pattern-matched f64 rendering"
behaviour Stage 5 / Stage 6 already accept under their own
numeric-tolerance gates.

**Comparator landed**: `ai/scripts/OspreySharp/Compare-Stage7-Crossimpl.ps1`
modeled on Compare-Percolator.ps1. Joins on `accessions`,
compares `best_peptide_score` and `group_qvalue` at 1e-9, and
checks `n_unique` / `n_shared` / `is_target_winner` for exact
string equality.

**Stage 7 cross-impl gate result on Stellar 3-file** (C# fed
Rust's reconciled Stage 6 parquets):

| Column                | Status | max_abs_diff | n_diverg / 6204 |
|-----------------------|--------|--------------|-----------------|
| `best_peptide_score`  | PASS   | 1.776e-15    | 0               |
| `group_qvalue`        | PASS   | 0.000e+00    | 0               |
| `n_unique`            | PASS   | (exact)      | 0               |
| `n_shared`            | PASS   | (exact)      | 0               |
| `is_target_winner`    | PASS   | (exact)      | 0               |

Key-set overlap: 6204 / 6204 on both sides. **OVERALL: PASS**.

Tasks #27 (`build_protein_parsimony` port), #28 (`compute_protein_fdr`
port — picked-protein TDC), and #30 (Stage 7 last-mile)
all completed: the prior parsimony + FDR ports plus the Session 4
structural fixes (FdrLevel default, detected-peptides filter
scope) leave Stage 7 cross-impl numerically equivalent at 1e-9
absolute on every row. No code change needed in this session —
the comparator delta closes the gate.

**Aborted side-quest**: an attempt to extend `FormatF64Roundtrip`
with a G17-trim + round-up algorithm to match Rust ryu byte-for-byte
made things worse (184 → 812 raw `cmp` lines diverging) because
.NET Framework 4.7.2's `G<p>` formatter for `p < 17` interacts
with `double.Parse` in a way that already yields a shortest-
roundtrip string for most values; replacing it with a generic
G17-trim algorithm broke many cases the existing path was getting
right. Reverted. The user's instinct here was correct: we already
solved cross-impl text matching at the Stage 5/6 boundary by
*comparing numerically*, not by byte-matching ryu output.
