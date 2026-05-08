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

### 2026-05-07 — Session 1 (sprint kickoff + structural-gap inventory)

Branch off `pwiz/master:a6997be6e` (Stage 7 squash-merge).
Upstream resync delta (Step 1): zero new commits on
`maccoss/osprey:main` since the Stage 7 close-out `17e8ba4`. Clean
baseline; no parity-critical ports needed before starting.

**Inventory pass on existing `.blib` files** from the Stage 7
test fixture (Stellar 3-file, both produced before
`OSPREY_STAGE7_PROTEIN_FDR_ONLY=1` was added so they were
written end-to-end):

- Rust: `D:\test\osprey-runs\stellar\_stage7_test\run_rust\output.blib` (39 MB)
- C#:   `D:\test\osprey-runs\stellar\_stage7_test\run_cs_from_rust\output.blib` (27 MB)

Probed via `System.Data.SQLite.dll` shipped with the Skyline
Debug build. Findings are not subtle — material structural deltas
that need code, not just a comparator.

**Gap 1: C# is missing 4 Osprey extension tables.** The Rust
`.blib` schema has these tables; the C# `BlibWriter.cs` doesn't
declare or populate them at all:

| Table                       | Rust rows | Schema |
|-----------------------------|-----------|--------|
| `OspreyCoefficients`        | 0         | (RefSpectraID, FileName, ScanNumber, RT, Coefficient) — empty for this dataset, table reserved |
| `OspreyExperimentScores`    | 45153     | (RefSpectraID, ExperimentQValue, NRunsDetected, NRunsSearched) |
| `OspreyPeakBoundaries`      | 45153     | (RefSpectraID, FileName, StartRT, EndRT, ApexRT, ApexIntensity, IntegratedArea) |
| `OspreyRunScores`           | 45153     | (RefSpectraID, FileName, RunQValue, DiscriminantScore, PosteriorErrorProb) |

Three of the four are 1-row-per-RefSpectra in this dataset. They
account for most of the 12 MB size delta (`39 MB - 27 MB`).
Adding the schemas to `BlibWriter.cs` is straightforward;
populating them needs the right C# data plumbing (run/experiment
q-values + peak boundaries are already on `FdrEntry`, so the
write step should be a join + projection).

**Gap 2: RetentionTimes cross-file propagation.** Rust emits
`135115` rows; C# emits `90921`. With ~45k passing RefSpectra and
3 input files, Rust's `135115 ≈ 3 * 45k` matches the documented
"one row per (passing RefSpectra, file)" semantic from
`docs/08-blib-output-schema.md`. C#'s `90921 ≈ 2 * 45k` suggests
it's emitting a row for the ID-line file + one cross-replicate
copy, **not** the full cross-replicate fan-out with NULL
`retentionTime` for runs that don't pass run-level FDR but
pass experiment-level via another replicate. This is the exact
NULL-vs-populated gate flagged in this TODO's Step 3 — it is now
definitely a real gap, not a hypothetical concern.

**Gap 3: RefSpectra row-count delta in the OPPOSITE direction
(unusual).** Rust 45153, C# **45636** (C# emits 483 MORE
spectra). Plausible causes (none yet bisected):

- C# is admitting some experiment-level-but-not-run-level passing
  precursors that Rust dedups out of RefSpectra.
- Different "passing" gate at the precursor level (FdrLevel
  default-related? — checked: that landed in Stage 7 fix already).
- Different best-per-precursor selection criterion in the
  `BlibPlanEntry` build.

Worth bisecting independently — the direction (C# bigger) means
this isn't a missing-output gap, it's a different inclusion rule.

**Other small deltas** (all tracked, lower priority):

| Table | rust | cs | delta |
|---|---|---|---|
| `Modifications` | 8710 | 8805 | -95 (C# has 95 more) |
| `Proteins` | 6986 | 6980 | +6 (Rust has 6 more) |
| `RefSpectraProteins` | 49289 | 49797 | -508 (C# has 508 more) |
| `OspreyMetadata` | 4 | 3 | +1 (C# missing one key — likely `protein_fdr` or similar) |

The Modifications / RefSpectraProteins deltas correlate with the
Gap 3 RefSpectra delta (C# RefSpectra has 483 more; protein
mappings + modifications scale with that), so likely all roll up
into one bisection.

**Plan for the next sessions:**

1. **Add the 4 missing tables to `BlibWriter.cs`** (additive,
   doesn't disturb what's already there). Schemas mirror Rust
   exactly. Populate from existing `FdrEntry` / per-file
   observations data. This closes Gap 1 and gives the comparator
   real data to diff against on those tables.
2. **Fix RetentionTimes cross-replicate propagation.** Emit
   one row per (passing-RefSpectra, file) with NULL
   `retentionTime` for runs that don't pass run-level FDR but
   pass experiment-level via another replicate. Closes Gap 2.
3. **Bisect Gap 3** (C# RefSpectra +483 vs Rust). Likely fix
   one place that cascades to Modifications +95 and
   RefSpectraProteins +508.
4. **`Compare-Blib-Crossimpl.ps1`** built incrementally
   alongside the writer fixes — start with row-count + key-set
   diff per table, then numeric-tolerance compare on float
   columns once row counts align.

**Session 1 outcomes (continued):**

| Sprint slice | Status | pwiz commit |
|---|---|---|
| Gap 1 — 4 missing Osprey tables | CLOSED | `b835c2f9e` |
| Gap 3 — RefSpectra +483 over | CLOSED to within 27 | `c230c11d9` |
| Gap 2 — RetentionTimes 44194 missing | CLOSED to within 81 | `8908a3d4f` |

Stellar 3-file row counts after Session 1:

| Table                       | rust | cs | delta |
|-----------------------------|------|----|-------|
| RefSpectra                  | 45153 | 45126 | 27 |
| RefSpectraPeaks             | 45153 | 45126 | 27 |
| Modifications               | 8710 | 8704 | 6 |
| Proteins                    | 6986 | 6980 | 6 |
| RefSpectraProteins          | 49289 | 49262 | 27 |
| RetentionTimes              | 135115 | 135034 | 81 (= 27 × 3 files) |
| OspreyMetadata              | 4 | 3 | 1 |
| OspreyPeakBoundaries        | 45153 | 45126 | 27 |
| OspreyRunScores             | 45153 | 45126 | 27 |
| OspreyExperimentScores      | 45153 | 45126 | 27 |
| OspreyCoefficients          | 0 | 0 | 0 |

`.blib` size: cs 38.3 MB vs rust 39 MB (was 27 MB before the
sprint started — most of the 12 MB gap closed).

**Remaining work:**

- **Bisect the 27-row RefSpectra under-inclusion** (Rust admits
  these, C# doesn't). Probably a subtle Stage 1/Stage 2 fallback
  edge case — three sampled only-in-Rust precursors all have
  `experiment_qvalue` ≈ 0.001-0.003 (well below 0.01 threshold)
  and charge=2, so they should pass Stage 2 outright. Hypothesis:
  the C# `perFileEntries` arriving at `WriteBlibOutput` doesn't
  include these 27 — they got filtered out by a Stage 5 / Stage 6
  upstream step in C# that Rust doesn't filter. Bisection target
  is the C# pipeline's earlier compaction / FDR phase, not
  `WriteBlibOutput`. Likely cascade-fixes Modifications -6 +
  Proteins -6 + RefSpectraProteins -27.
- **OspreyMetadata -1.** Rust writes 4 keys; C# writes 3. Inspect
  Rust's metadata write to find the missing one (likely
  `protein_fdr` value or similar config item).
- **Build `Compare-Blib-Crossimpl.ps1`.** With row counts
  effectively aligned, can now move to per-column numeric
  tolerance + exact-equality gate.
- **Astral validation.** Re-run on Astral 3-file once Stellar
  is at row-count parity and the comparator exists.
