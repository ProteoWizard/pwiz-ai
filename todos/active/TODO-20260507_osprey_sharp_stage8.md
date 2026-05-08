# TODO-20260507_osprey_sharp_stage8.md — Stage 7 .blib output: cross-impl row-level parity

> Final substep of Stage 7's merge-node phase (collapsed Stage 7
> per the 2026-05-07 architectural review — see
> `TODO-20260507_osprey_sharp_stage7.md` Session 7). The file name
> `_stage8` is retained as the operational sprint identifier; the
> `.blib` SQLite output is **not** a separate architectural stage —
> it runs in the same process as second-pass Percolator and
> protein FDR, sharing in-memory state, with no
> sidecar / rehydration / per-file-fan-out boundary preceding it.

> Sub-sprint of **TODO-20260423_osprey_sharp.md** (Phase 4 umbrella,
> Stages 6-7).

## Branch Information

- **pwiz**: `Skyline/work/20260507_osprey_sharp_stage8` (created
  2026-05-07 off pwiz/master `a6997be6e` — the Stage 7 squash-merge)
- **osprey**: TBD — likely no Rust changes needed for the .blib
  substep (Rust's `osprey-io::output::blib` is the reference);
  branch off `maccoss/osprey/main` `17e8ba4` if a Rust-side
  diagnostic seam turns out to be needed.
- **Base**: `master` (pwiz) / `main` (maccoss/osprey)
- **Created**: 2026-05-07
- **Started**: 2026-05-07
- **Status**: In progress — branch off Stage 7's squash-merge.
- **GitHub Issue**: (none — tool work, no Skyline integration yet)

### Predecessors

| Predecessor | What it shipped |
|---|---|
| `ai/todos/completed/TODO-20260507_osprey_sharp_stage7.md` | Stage 7 second-pass Percolator + protein FDR (parsimony + picked-protein TDC) cross-impl PASS at 1e-9 on Stellar (6204) + Astral (11779) — pwiz #4192, maccoss/osprey #31 |
| `ai/todos/completed/TODO-20260429_osprey_sharp_stage6.md` | Stage 6 byte-parity end-to-end on Stellar + Astral — pwiz #4187 |
| `ai/todos/completed/TODO-20260507_ospreysharp_missing_scoring_columns.md` | Stage 5/6 scoring columns round-trip byte-for-byte — pwiz #4188 |

Stages 1-6 plus second-pass-FDR + protein-FDR substeps of Stage 7
are at cross-impl parity end-to-end on Stellar + Astral 3-file.
`Compare-Stage5-AllFiles` + `Compare-Stage6-Crossimpl` +
`Compare-Stage7-Crossimpl` all green with empty allowlists.

## Objective

Walk the BiblioSpecLite `.blib` SQLite output (final substep of
Stage 7's merge-node phase) to row-level cross-impl parity on
Stellar + Astral, single-file and 3-file.

The output is a SQLite database. The schema (see
`crates/osprey-io/src/output/blib.rs`):

- **RefSpectra** — one row per passing precursor: modified sequence,
  charge, precursor m/z, score, q-values, PEP, file ID, scan
  number. Skyline's primary identification table.
- **RefSpectraPeaks** — fragment m/z + intensity arrays (one row per
  RefSpectra). Library theoretical fragments, **not** observed DIA
  peaks (per the Stage 5 fix).
- **RefSpectraPeakAnnotations** — fragment annotations (b/y ion
  labels, neutral losses, charge states).
- **Modifications** — 1-based-position modification list per spectrum.
- **Proteins** + **RefSpectraProteins** — protein accessions + the
  many-to-many link to RefSpectra.
- **RetentionTimes** — per-file (file, RefSpectra) RT data. The
  nullable `retentionTime` column controls Skyline ID-line display:
  populated = "ID line here", NULL = "use start/end for
  quantification but no ID line" (run failed run-level FDR but
  passed experiment-level via another replicate). See
  `osprey/docs/08-blib-output-schema.md`.
- **Osprey extension tables** — library theoretical fragments + any
  Osprey-specific fields the C# port has been carrying through
  Stages 1-6 plus Stage 7's first two substeps.

## Strategy

### Step 1: Upstream resync delta catalog

Same template as the Stage 7 sub-sprint's first step. Scan
`maccoss/osprey:main` for commits since the Stage 7 close-out
baseline `17e8ba4`. Disposition each as:

- **parity-critical port** — must land in OspreySharp before the
  .blib walk starts.
- **stages 1-6 / stage 7 first-two-substeps drift** — flag for a
  small re-validation round before .blib.
- **out-of-scope** — note and move on.

Dump findings to `ai/.tmp/stage8_upstream_delta.md`.

### Step 2: Cross-impl `.blib` row-level diff harness

`Compare-Percolator.ps1`, `Compare-Stage6-Crossimpl.ps1`, and
`Compare-Stage7-Crossimpl.ps1` work on TSV dumps with stable
composite keys. `.blib` is SQLite, not text, so the harness needs
a different shape. Two approaches:

1. **`sqlite3 .dump` → diff TSV.** Cheap, but the `.dump` order
   is row-insertion order which isn't guaranteed to match
   cross-impl. Would need a stable sort per table.
2. **Per-table SQL projection → join on stable key →
   numeric-tolerance compare per column.** More work, but mirrors
   the established Compare-Percolator pattern (already accepted by
   the user for Stages 5/6/7) and naturally handles tables with
   floating-point columns (RetentionTimes start/end/retentionTime,
   RefSpectra precursorMZ + score + q-values + PEP).

Pick approach 2. Write `Compare-Blib-Crossimpl.ps1` modeled on
Compare-Stage7-Crossimpl.ps1:

- Per-table reader that runs a fixed
  `SELECT ... ORDER BY <stable key>` on each side.
- Stable composite keys: `(modifiedSequence, charge)` for
  RefSpectra; `(RefSpectraID, fileID)` for RetentionTimes; etc.
- Numeric columns at 1e-9 absolute (consistent with Stage 5/6/7
  gates — flagged for the end-of-pipeline review per the
  project-wide bit-parity memory).
- String/integer columns at exact equality.
- Row-set diff (keys-only-in-Rust, keys-only-in-C#) per table.

### Step 3: NULL-vs-populated `retentionTime` semantics

The single most common Skyline-visible difference between two
correct implementations isn't a numeric drift, it's the
`retentionTime IS NULL` vs `retentionTime = X` decision in
RetentionTimes rows for cross-replicate-passing precursors. Add
an explicit gate: for every (RefSpectra, file) row, the RT
field's NULL-ness must match between the two sides exactly.
Mismatches here silently change Skyline's identification
rendering even when every numeric column passes tolerance.

### Step 4: Bisection — single-file first

Run on Stellar 1-file first (drop two of the three Stage 7
inputs). Single-file paths skip experiment-level FDR (uses
run-level directly per the FDR pipeline notes). This isolates
the simpler case. Once 1-file is row-level identical, advance to
3-file where multi-file observation propagation + the
NULL-retentionTime semantics kick in.

### Step 5: 3-file Stellar + Astral

Once single-file is identical, run 3-file on both datasets.
Watch for:

- Cross-file aggregation differences
  (passing-via-experiment-level-but-not-run-level — the
  NULL-retentionTime case from Step 3).
- Per-file RT boundary differences (each file gets its own
  start/end RT — does the C# port preserve them?).
- Extension-table column drift (Osprey fragment tables — are
  they emitted in the same order on both sides?).

## Gate for PR

Row-level cross-impl parity on Stellar + Astral, 1-file **and**
3-file, on the `.blib` SQLite output.
`Compare-Stage5-AllFiles` + `Compare-Stage6-Crossimpl` +
`Compare-Stage7-Crossimpl` continue green (no regression). New
`Compare-Blib-Crossimpl.ps1` covers the `.blib` SQLite output.

Stages 1-6 plus Stage 7 first-two-substeps parity gates must
still hold: `Test-Features.ps1` 21/21 @ 1e-6, end-of-Stage-5
Percolator dump byte-identical, Stage 6 reconciled-parquet diff
with the empty allowlist that landed in pwiz #4187 / #4188,
Stage 7 protein-FDR dump cross-impl PASS at 1e-9 (Stellar 6204 +
Astral 11779).

## Notes

- The `.blib` substep is the LAST cross-impl validation gate.
  Once row-level parity lands, the C# port has end-to-end
  functional parity with the Rust reference; what remains is
  the user's eventual full-pipeline parity review to decide
  whether to tighten the 1e-9 numeric tolerance the
  Stage 5/6/7 gates inherit (per the project-wide
  `feedback_bit_parity_tolerance.md` memory).
- The `.blib` output is what Skyline actually consumes, so this
  substep's gate is also the end-user-visible parity gate. A
  passing gate means a Skyline session against a C#-produced
  `.blib` shows the same identifications, RT boundaries, and
  quantification inputs as a session against a Rust-produced
  `.blib`.
- The `ZstdSharp` codec is in the cross-tool path
  (pwiz #4172); no Snappy fallback. `.blib` is SQLite, not
  parquet, so this is inherited rather than directly relevant
  — but related cross-impl artifacts (e.g. `.proteins.csv`
  from the protein-FDR report) share the Stage-6+ codec
  conventions.

## See also

- `ai/todos/active/TODO-20260423_osprey_sharp.md` — Phase 4
  umbrella.
- `ai/todos/completed/TODO-20260507_osprey_sharp_stage7.md` —
  Stage 7 sub-sprint (immediate predecessor; documents the
  2026-05-07 stage-7-and-8 collapse decision).
- `crates/osprey-io/src/output/blib.rs` — Rust source of truth
  for the `.blib` writer + schema.
- `crates/osprey/docs/08-blib-output-schema.md` — `.blib`
  schema + Skyline integration notes (NULL-retentionTime
  semantics in particular).
- `pwiz_tools/OspreySharp/Osprey-workflow.html` — pipeline
  diagram with "you are here" marker on the .blib sub-bar of
  Stage 7; update at end of sprint to mark .blib green.

## Progress log

### 2026-05-07 — Session 1 (sprint kickoff)

Branch off `pwiz/master:a6997be6e` (Stage 7 squash-merge).
Stages 1-7-first-two-substeps cross-impl parity confirmed via the
preceding Stage 7 close-out. `.blib` substep work begins next
session.
