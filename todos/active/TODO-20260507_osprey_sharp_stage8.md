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

**Session 1 outcomes (continued — second half of session):**

| Sprint slice | Status | pwiz commit |
|---|---|---|
| 27-row RefSpectra under-inclusion | CLOSED — was protein-FDR gate | `3c6c58aca` |
| OspreyMetadata key-set alignment | CLOSED — 4 Rust keys written | `3c6c58aca` |
| Compare-Blib-Crossimpl.ps1 | LANDED on `ai/master` | `e7e2fe2` |
| best-by-run-qvalue + 4 column fixes | CLOSED | `03662386a` |

**Bisection method that found the protein-FDR gate**: added a temporary
`OSPREY_DUMP_BLIB_ADMISSION` env-var to write three TSVs from
`WriteBlibOutput` — the (modseq, charge) sets at three points in the
admission filter (entries-in-perFileEntries, Stage-1 passingPeptides,
Stage-2 passingPrecursors). Joined externally against the 27 only-in-Rust
list. 22 of 27 were in `passingPrecursors` but didn't make it to the
final write (post-Stage-2 protein-FDR gate dropped them); the other 5
were missing from `perFileEntries` itself. The "5 cys-peptide pattern"
turned out to be coincidence — when the protein-FDR gate was lifted,
all 27 came through, including the 5 cys-peptides. Diagnostic was
removed in `3c6c58aca` after it served its purpose.

**Stellar 3-file row-count gate: PASS, EVERY TABLE.** Per-column
diff via the new `Compare-Blib-Crossimpl.ps1`:

  rows: all 14 tables match exactly (RefSpectra 45153, RetentionTimes
        135115, Modifications 8710, etc.).
  key-set diff: zero asymmetric keys on every table.
  PASSing columns: RefSpectra (precursorMZ, ionMobility, peptideSeq,
        prevAA, nextAA, copies, numPeaks, scoreType),
        Modifications.mass, RetentionTimes (score, bestSpectrum),
        OspreyExperimentScores (NRunsDetected, NRunsSearched),
        OspreyRunScores (RunQValue, DiscriminantScore,
        PosteriorErrorProb), OspreyPeakBoundaries (ApexIntensity,
        IntegratedArea), OspreyMetadata, SpectrumSourceFiles,
        Proteins, RefSpectraProteins, OspreyCoefficients.

**Remaining FAILs (deferred to next session):**

- **`RefSpectra.score` + `OspreyExperimentScores.ExperimentQValue`**
  — both 42247/45153 differ. C#'s
  `EffectiveExperimentQvalue(FdrLevel.Both) = max(precursor, peptide)`
  returns 1.0 because `ExperimentPeptideQvalue` defaults to 1.0
  for entries where C#'s `ComputeExperimentPeptideQvalues` (in
  `PercolatorFdr.cs`) doesn't find the peptide in its
  `peptideQvalue` map. Rust populates this on every entry; C# has
  a gap. Bisection target is `ComputeExperimentPeptideQvalues` —
  the `BestPrecursorPerPeptide` aggregation may be returning a
  smaller peptide set than Rust's equivalent.

- **`RetentionTimes.retentionTime/startTime/endTime` + same on
  `RefSpectra` + `OspreyPeakBoundaries`** — 1-1.3 min spread,
  2963-11232 rows. Rust shares peak boundaries across charge
  states of the same peptide via the `shared_bounds` HashMap
  (pipeline.rs:6219). C# emits per-charge-state boundaries.
  Port the shared-bounds logic to C# `WriteBlibOutput`.

- **`RefSpectraPeaks.peakMZ/peakIntensity`** — 307/345 rows
  differ binary. Fragment-array serialization or order. Likely
  a zlib-vs-no-zlib compression toggle, or fragment sort order
  difference. Targeted blob diff would localize.

- **Astral validation** — re-run on Astral 3-file once the above
  three are closed.

**Bisection helper retained**: `Compare-Blib-Crossimpl.ps1` runs in
~5 seconds against a Rust + C# .blib pair, prints per-table /
per-column PASS/FAIL with first-divergent-row sample. New diagnostic
seams (env-var-gated TSV dumps from `AnalysisPipeline.WriteBlibOutput`)
can be re-added at any time on the `OSPREY_DUMP_BLIB_*` namespace.

### 2026-05-08 — Session 1 (extended even further: down to 109 blob diffs)

Continuing in same session, the three deferred FAILs all chased.

**Bisection found that RefSpectra.score wasn't a `max(precursor, peptide)`
mismatch — Rust's .blib stores experiment_PRECURSOR_qvalue.** Used the
new `OSPREY_DUMP_BLIB_QVALUES` diagnostic to dump per-bestByPrecursor
q-values and joined externally against Rust's persisted
`.1st-pass.fdr_scores.bin` sidecars. Result: every C# entry's q-values
match Rust's sidecar exactly (45153/45153 within 1e-9). So C#'s
COMPUTATION was correct. The bug was at the .blib WRITE site: C# was
calling `EffectiveExperimentQvalue(FdrLevel.Both)` (`max(precursor,
peptide)`), but Rust's `BlibPlanEntry.experiment_qvalue` (line
pipeline.rs:4795) actually uses `best_exp_q.get(...)` which is built
at pipeline.rs:4670-4683 from `e.experiment_precursor_qvalue` only —
the minimum across all observations of each (modseq, charge), NOT
the Both-level value. The misleading `LightFdr.experiment_qvalue =
effective_experiment_qvalue(Both)` at pipeline.rs:4705 is a memory
cache for the fallback branch only. Fixed in pwiz commit `a7645ec14`.

**Shared peak boundaries across charge states.** Ported Rust's
`build_shared_boundaries_from_plan` (pipeline.rs:6020-6063) to C#
WriteBlibOutput. Closes the 1-1.4 minute RT spreads on
RefSpectra/RetentionTimes/OspreyPeakBoundaries. Fixed in pwiz commit
`a12bf85c9`.

**Zlib threshold mismatch.** C# DeflateStream produces 3-4 fewer
bytes of deflate overhead than Rust's flate2 on small fragment-
array inputs (~160 bytes). With the original "any savings ->
compress" rule, Rust falls back to raw on inputs where C# still
compresses, splitting the .blib blob bytes. Tightened C# threshold
to require >4 bytes of savings (`compressed.Length + 4 >=
raw.Length -> return raw`). Fixed 71%/95% of the blob diffs. Fixed
in pwiz commit `6ae307e7f`.

| Sprint slice (Session 1 extended) | Status | pwiz commit |
|---|---|---|
| Diagnostic: OSPREY_DUMP_BLIB_QVALUES (kept) | LANDED | `4434c81ec` |
| RefSpectra.score = experiment_PRECURSOR_q | CLOSED 42247->0 | `a7645ec14` |
| Shared peak boundaries cross-charge | CLOSED 2963/11232/etc->0 | `a12bf85c9` |
| Zlib threshold (raw fallback margin) | CLOSED 71%-95% | `6ae307e7f` |

**Stellar 3-file Compare-Blib-Crossimpl.ps1 final state:**

| Table | Status |
|---|---|
| RefSpectra | PASS all columns |
| RefSpectraPeaks.peakMZ | FAIL 90/45153 (0.20%) |
| RefSpectraPeaks.peakIntensity | FAIL 19/45153 (0.04%) |
| Modifications | PASS |
| Proteins | PASS |
| RefSpectraProteins | PASS |
| RetentionTimes | PASS all columns |
| OspreyExperimentScores | PASS all columns |
| OspreyRunScores | PASS all columns |
| OspreyPeakBoundaries | PASS all columns |
| OspreyCoefficients | PASS (empty both sides) |
| OspreyMetadata | PASS |
| SpectrumSourceFiles | PASS |

**Total content gap: 109 blob bytes out of 45153 entries (0.24%).**

The 109 residual cases are all where BOTH sides compress but C#
produces a 4-byte shorter deflate stream than Rust for the same
input. Pattern is fundamental flate2-vs-DeflateStream micro-difference
at the deflate-block-format level (huffman-table choice,
end-of-block encoding). Closing the rest needs either:

1. A flate2-compatible deflate in C# (port flate2 logic, find a
   third-party C# zlib that matches, or pre-encode blobs identically).
2. A DeflateStream-compatible deflate in Rust (configure flate2 for
   matching output, or switch to a different deflate crate).
3. Accept the 0.24% as a known semantic-equivalence diff (the
   decoded f64 m/z and f32 intensity arrays match exactly when
   uncompressed; only the encoded bytes differ).

Recommended path for the next session: option 1 — explore third-party
C# zlib libraries (e.g., DotNetZip, ZLibPort) that produce flate2-
compatible output, or hand-roll a deflate that matches flate2's
huffman-table strategy on small inputs.

**Astral Stellar validation**: deferred to next session pending
the residual 109 fix.

### 2026-05-08 — Session 1 (still further: zlib backend investigation)

User pointed out that **ProteoWizard/pwiz owns the BLIB format**
(the C++ `pwiz_tools/BiblioSpec` writer is canonical), so the
cross-impl convergence point should NOT be defined by Mike's
Rust deflate library — it should be the ProteoWizard standard.
The long-term plan is to share C# blib-writing code (potentially
a Skyline `Model/Lib/BlibData` move out to `Shared/BiblioSpec`,
or eventually a C# port of `pwiz_tools/BiblioSpec` itself
inspired by Matt Chambers's pwiz/pwiz-aux porting effort), and
to alter Rust to match that standard rather than the inverse.

**Tested three flate2 backends on Stellar Rust .blib**:
* `flate2 = "1.0"` (default, miniz_oxide pure-Rust): 90 + 19 mismatches
* `flate2` with `["zlib-rs"]` (cloudflare zlib pure-Rust port): same
* `flate2` with `["zlib-default"]` (stock zlib via libz-sys): same

All three Rust backends produce **identical compressed bytes** on
the test inputs. They all conform to RFC 1950/1951 stock zlib
encoding. The 90 + 19 residual cases are entries where .NET 4.7.2's
`DeflateStream` produces a 4-byte-shorter deflate stream than stock
zlib — i.e. .NET DeflateStream is the **outlier** here, not Rust.
Both encodings are valid zlib; they just make different
huffman-table / end-of-block choices on small inputs.

**Implication**: the long-term cross-impl byte-parity fix is to
replace C#'s `System.IO.Compression.DeflateStream` with a
stock-zlib-compatible compressor (e.g. SharpZipLib's `Deflater`
in zlib mode, or a managed port of zlib via DotNetZip's
deflate at level 6 — both produce stock zlib output bytes).
Once C# emits stock zlib, all 109 residual cases close
automatically since Rust already emits stock zlib.

Rust `Cargo.toml` reverted to default `flate2 = "1.0"` for now —
no behavior change, and it keeps the door open for whichever
backend ProteoWizard standardizes on. The note here documents
that the fix lives on the C# side.

**Cumulative Stellar 3-file final state:**

| Compare-Blib-Crossimpl gate | Result |
|---|---|
| All row counts | PASS (45153 / 45153) |
| All key sets | PASS (zero asymmetric) |
| All numeric columns (q-values, RTs) | PASS at 1e-9 |
| All exact columns (counts, types) | PASS |
| `RefSpectraPeaks.peakMZ` blob | FAIL 90 / 45153 (0.20%) |
| `RefSpectraPeaks.peakIntensity` blob | FAIL 19 / 45153 (0.04%) |

The 109 (0.24%) residual blob bytes are .NET-DeflateStream-vs-stock-zlib
encoding differences — the **f64 m/z and f32 intensity arrays decode
identically** on both sides. Semantic parity: PASS. Byte parity: held
by C#'s DeflateStream choice, fixable when Skyline's BlibData moves
to Shared/BiblioSpec (or pwiz_tools/BiblioSpec gets ported to C#).

### 2026-05-08 — Session 1 (final: switch C# to Ionic.Zlib — OVERALL PASS)

**Skyline already uses Ionic.Zlib (DotNetZip) for blib peak compression.**
`pwiz.Skyline.Util.Extensions.UtilDB.Compress` at
`Skyline/Util/Extensions/UtilDB.cs:109-200` uses
`Ionic.Zlib.ZlibCodec` at compression level 6 — has done since 2009.
Skyline's BlibData (which already writes valid `.blib` files Skyline
itself reads) uses this routine. So OspreySharp.IO.BlibWriter was
the **outlier in the C# ecosystem** for using
`System.IO.Compression.DeflateStream` instead of the
ProteoWizard-canonical Ionic.Zlib path.

Switched OspreySharp's `CompressBytes` to use the same
Ionic.Zlib level-6 path as Skyline. Added a `Reference Include="DotNetZip"`
to `OspreySharp.IO.csproj` pointing at the already-vendored
`pwiz_tools/Shared/Lib/DotNetZip/DotNetZip.dll` — the same DLL
Skyline references.

**Compare-Blib-Crossimpl on Stellar 3-file:**

  OVERALL: PASS - .blib cross-impl row + content parity within tolerance.

Every per-table content column matches at the SQL row+column level:
RefSpectra (all numeric + exact + blob via byte-identical peakMZ /
peakIntensity), Modifications, Proteins, RefSpectraProteins,
RetentionTimes (per-file rows + NULL retentionTime semantics),
OspreyExperimentScores, OspreyRunScores, OspreyPeakBoundaries,
OspreyMetadata, SpectrumSourceFiles, ScoreTypes, LibInfo,
IonMobilityTypes.

**File-level SHA-256 still differs** (Rust 39 MB / C# 38.8 MB) due
to SQLite engine page-layout differences between rusqlite (Rust)
and System.Data.SQLite (C#) — these are SQLite-internal page
structure / autoincrement / index-ordering details, not logical
content. Every byte we own at the SQL row+column level matches.
The right gate for cross-impl semantic parity is the row+column
comparator we built (Compare-Blib-Crossimpl.ps1), not raw file
bytes — for the same reason the Stage 5/6/7 gates use numeric
tolerance rather than `cmp`.

**Sprint exit gate: GREEN on Stellar 3-file.** Ten pwiz commits
on `Skyline/work/20260507_osprey_sharp_stage8` (4 missing tables;
two-stage admission filter; RetentionTimes propagation;
protein-FDR gate + metadata; best-by-run + 4 secondary;
diagnostic seam; precursor-q score; shared peak boundaries;
zlib threshold; DotNetZip switch). Three ai/ commits (comparator,
multiple progress logs).

**Astral validation queued for next session** (re-run on
the Astral 3-file fixture to confirm the Stellar gate
generalizes).
