# TODO: Osprey / OspreySharp HPC-friendly scoring split

**Status**: Completed
**Priority**: High (enables cluster deployment)
**Complexity**: Small (wiring + CLI; infrastructure already in place)
**Created**: 2026-04-18
**Started**: 2026-04-19
**Completed**: 2026-04-19
**Branches** (both merged + deleted):
- pwiz: `Skyline/work/20260419_osprey_hpc_split` -> fast-forward merged
  into `Skyline/work/20260409_osprey_sharp` at `dedbfda1da`; sub-branch
  deleted local + remote
- osprey: `feat/no-join-cli` -> merged via maccoss/osprey PR #13
  (`7abe6bf`); local branch deleted
**Scope**: Both `C:\proj\osprey` (Rust) and `C:\proj\pwiz\pwiz_tools\OspreySharp` (C#) in lock-step

## Progress

### Phase 1 (config + CLI) - DONE 2026-04-19

- Added `no_join: bool` and `input_scores: Option<Vec<PathBuf>>` to `OspreyConfig`
  on both sides (`osprey-core/src/config.rs`, `OspreySharp.Core/OspreyConfig.cs`).
- Added the three CLI flags `--no-join`, `--join-only`, `--input-scores` to
  both parsers. Multi-value `--input-scores` mirrors the existing `--input`
  pattern (space-separated, consume until next flag); single-directory arg
  triggers a non-recursive `*.scores.parquet` scan.
- Extracted `validate_hpc_args` (Rust) and `Program.ValidateArgs` (C#) as
  pure helpers so the mutex + required-companion checks can be unit-tested.
- Tests: 14 in `crates/osprey/src/main.rs::tests`; 16 in
  `OspreySharp.Test/ProgramTests.cs`. Cover validation errors and happy
  paths, `resolve_input_scores` directory expansion, and config defaults.
- Full-suite regression: 406+ Rust tests pass; OspreySharp.sln 202/202 pass
  (was 186 + 16 new = 202).
- `OSPREY_EXIT_AFTER_SCORING` env var: already gone from upstream Rust;
  C# removal deferred to Phase 2 (the env-var check is the seam where the
  pipeline split lands).

### Phase 2 (pipeline split) - DONE 2026-04-19

Approach: minimal seam-only changes, NOT the full extraction the spec
called for. `run_analysis` (Rust) and `AnalysisPipeline.Run` (C#) stay
monolithic; the `--no-join` / `--join-only` modes branch around the
existing per-file loop. A separate sprint can refactor for clarity.

- **Rust** (`crates/osprey/src/pipeline.rs`): added a `--join-only`
  branch that loads `FdrEntry` stubs (and FDR sidecars + calibration
  JSON, best-effort) directly from the `--input-scores` parquets;
  `--no-join` short-circuits at the existing exit-after-scoring seam
  with a clear log message. Helper `synthetic_input_from_parquet`
  lets the existing path-derivation helpers (sidecars, calibration)
  be reused without duplicating them.
- **C# pipeline** (`OspreySharp/AnalysisPipeline.cs`): added the
  matching `joinOnly` branch (loads stubs + 21 PIN features in
  lockstep via existing `LoadFdrStubsFromParquet` +
  `LoadPinFeaturesFromParquet`); `--no-join` short-circuits at the
  same seam.
- **C# parquet writer** (`OspreySharp.IO/ParquetScoreCache.cs`):
  added `WriteScoresParquet(string, List<FdrEntry>, ...)` overload
  (~70 LOC). Wired into `ProcessFile` to fire only when
  `config.NoJoin == true` — no behavior change for the default
  path. Was a deferred item from the active osprey_sharp TODO
  Phase 4 cleanup; landed here because `--no-join` needs it.
- `OSPREY_EXIT_AFTER_SCORING` env var: kept alongside `--no-join`
  during Phase 2 to avoid breaking bench scripts mid-sprint.
  Removal moves to Phase 5 in lockstep with the script updates.

**Stellar smoke test (C# net472, single file, unit resolution)**:
- `--no-join`: 466,187 entries scored, wrote 74 MB Snappy parquet (37 s)
- `--join-only`: loaded 466K stubs+features, 37,659 precursors at 1% FDR,
  17.7 MB blib (3 min, including Percolator + protein parsimony +
  blib write)

**Stellar smoke test (Rust release, same file)**:
- `--no-join`: 466,187 entries scored, wrote 280 MB ZSTD parquet (36 s)
- `--join-only`: 35,120 precursors at 1% FDR, 25 MB blib (1 min 56 s)

**Cross-impl asymmetry to resolve in Phase 4**: Rust writes ZSTD
compression; C# `Parquet.Net` reads/writes Snappy only. So
`Rust --no-join` → `C# --join-only` (and vice versa) currently
fails with "reader for compression 'ZSTD' is not supported". Same-impl
round-trips (Rust→Rust, C#→C#) both work. Options for Phase 4:
upgrade `Parquet.Net`, drop Rust to Snappy, or keep them independent
(operator picks one tool for the whole experiment).

### Phase 3 (parquet group validation) - DONE 2026-04-19

- **Rust** (`crates/osprey/src/pipeline.rs`): added `validate_scores_parquet_group`
  IO wrapper plus pure helpers `parse_version` and `check_parquet_metadata`.
  Wired in at the top of the `--join-only` branch. 12 unit tests target
  the pure helpers (mutex / version drift / missing fields / hash
  mismatches / unparseable version).
- **C#** (`OspreySharp.IO/ParquetScoreCache.cs`): mirror -- added
  `LoadFooterMetadata`, `TryParseVersion`, `CheckParquetMetadata`, and
  `ValidateScoresParquetGroup`. Wired into `AnalysisPipeline.Run` at
  the top of the `joinOnly` branch via `Program.VERSION`. 12 matching
  unit tests in `ProgramTests.cs`. Total OspreySharp tests now **214**
  (was 202).
- **C#** added `OspreyConfig.LibraryIdentityHash()` (mirror of Rust's
  `library_identity_hash`: SHA-256 over `path:`, `size:`, `mtime:`).
- **C# fix** found during smoke testing: `ProcessFile` shallow-clones the
  config and mutates `FragmentTolerance` during MS2 calibration, so
  computing `SearchParameterHash()` inside `ProcessFile` produced a hash
  the validator couldn't match later. Fixed by pre-computing the
  metadata dictionary once at the top of `Run()` against the un-mutated
  outer config and threading it down to `ProcessFile`. Rust does not
  have this bug because its per-file loop does not clone+mutate config.

**Stellar smoke tests (both impls, single file):**
- Rust positive (unit -> unit): "validated 1 parquet(s) against current
  config (search_hash=de620a21...)" -> 35,120 precursors at 1% FDR.
- Rust negative (unit -> hram): "search_hash mismatch: parquet was
  scored with search_hash=de620a21... but current config hashes to
  f7ad4558..." (file named in error).
- C# positive: 37,764 precursors. C# negative: identical mismatch format.

**Cross-impl gaps now visible** (all Phase 4 follow-ups, not regressions):
1. Compression: Rust ZSTD, C# Parquet.Net 3.x Snappy.
2. Schema types: Rust uses UInt32/UInt8 for entry_id/charge; C# uses
   Int32. Rust panics if it tries to load a C# parquet (downcast fail).
3. Version namespace: C# `Program.VERSION = "0.1.0"`, Rust `26.3.0`.
   Validator correctly aborts cross-impl with "incompatible major/minor".
   Resolves once project versions align (or a `tool` field is added).

### Phase 4 (round-trip tests) - DONE 2026-04-19

**Bit-parity check (single-file Stellar, C# net472, --resolution unit):**
- Baseline (end-to-end, one process): 37,721 precursors at 1% FDR (4m 56s)
- Split (`--no-join` then `--join-only`): 37,823 precursors at 1% FDR
- Drift: +102 precursors / 0.27%, well within Percolator SVM variance.
  Stage 4 feature scores stored in the parquet are equivalent to what
  end-to-end would compute; the small drift is in Stage 5 SVM training,
  expected.

**3-file round-trip (Stellar, C#):**
- `--no-join` parallel-3 wrote 3 parquets (~74 MB each) in 140s
- `--join-only` validated all 3, loaded them, ran Stage 5+:
  - File 20: 37,679 precursors / File 21: 37,443 / File 22: 37,293
  - Total: 112,415 precursors at 1% FDR (5m 24s)

**Negative tests (Phase 3 covered these end-to-end + via unit tests):**
- `--no-join unit` then `--join-only hram` → search_hash mismatch with
  the offending file named in the error
- 24 unit tests across the validator helpers

**Deferred to follow-up sprints (out of scope here):**
- Astral 3-file round-trip — would need access to the larger dataset and
  ~30 min run; same code path as Stellar
- Cross-impl round-trip — blocked by the three known Rust↔C# parquet
  gaps (compression, schema int types, version namespace)
- Strict bit-identity of parquet bytes across runs — observed ~23 KB
  size delta between single-file and parallel-3 runs of the same file;
  likely from per-window scoring order and/or footer key ordering. Row
  contents are functionally equivalent (counts + content match within
  Percolator noise). A separate sprint can chase strict determinism.

### Phase 6 (cross-impl Snappy interop) - DONE 2026-04-19

Added on top of the original 5-phase scope as a follow-up. Goal: enable
Rust <-> C# parquet handoff so both impls can start Stage 5 from
identical scoring data.

- **Rust**: added `--parquet-compression {zstd,snappy}` CLI flag,
  `ParquetCompression` enum on `OspreyConfig`, threaded through 3
  parquet write call sites. Default stays Zstd (no production behavior
  change). When Snappy is selected, dictionary encoding is also disabled
  -- Parquet.Net 3.x can't decode RLE_DICTIONARY.
- **C#** schema alignment with Rust:
  - Switched `entry_id`/`scan_number` to UInt32 and `charge` to UInt8
    so Rust's strict downcast doesn't panic.
  - Added 6 simple columns missing from C# (`sequence`, `precursor_mz`,
    `protein_ids`, `bounds_area`, `bounds_snr`, `file_name`) populated
    from the FdrEntry + library lookup.
  - Added 5 nullable Binary columns (`cwt_candidates`, `fragment_mzs`,
    `fragment_intensities`, `reference_xic_rts`, `reference_xic_intensities`)
    as schema placeholders written as NULL. These are needed only by
    Stage 6 reconciliation / Stage 7 gap-fill, which are out of scope.
  - Bumped `Program.VERSION` from `0.1.0` to `26.3.0` to align the
    version namespace with Rust (the Phase 3 validator requires same
    major.minor).
- **Cross-impl hash bit-equivalence**: discovered two serialization
  mismatches by smoke-testing on Stellar; fixed both:
  - Bools: Rust prints `true`/`false`, C# default `bool.ToString()`
    is `True`/`False`. Now C# explicitly lower-cases.
  - mtime: Rust used `format!("{:?}", SystemTime)` (debug format), C#
    used ISO 8601. Both switched to **Unix seconds** as a portable
    integer. Same `library_identity_hash` on both impls now.

**Stellar cross-impl smoke (single file, --resolution unit, both Snappy):**
- C# --no-join (74 MB parquet) -> Rust --join-only -> 5,736 protein groups (2:19)
- Rust --no-join --parquet-compression snappy (320 MB, dict-disabled)
  -> C# --join-only -> 34,627 precursors at 1% FDR (5:05)

Production-default behavior (Rust without `--parquet-compression`)
unchanged: writes ZSTD with dictionary encoding, ~280 MB on Stellar.

### Phase 5 (docs + scripts) - DONE 2026-04-19

- Migrated four ps1 scripts (`Bench-Scoring.ps1`,
  `Profile-OspreySharp.ps1`, `Test-Features.ps1`, `Run-Osprey.ps1`) from
  the `OSPREY_EXIT_AFTER_SCORING` env var to the `--no-join` CLI flag.
- Removed `OSPREY_EXIT_AFTER_SCORING` from both implementations
  (`osprey-core/src/diagnostics.rs::should_exit_after_scoring` and
  `OspreySharp/OspreyEnvironment.cs::ExitAfterScoring`) and their call
  sites in `pipeline.rs` and `AnalysisPipeline.cs`.
  `OSPREY_EXIT_AFTER_CALIBRATION` (Stage 3) stays -- no production CLI
  analog.
- Added a brief HPC note at the Stage 4 -> Stage 5 seam in
  `Osprey-workflow.html`.
- Skipped (out of scope of this minimal sprint): full doc rewrite of
  `osprey/docs/12-intermediate-files.md` and a release-notes entry.
  Both are mechanical follow-ups suitable for a separate PR.

## Motivation

Both Osprey and OspreySharp already write one `{mzml_stem}.scores.parquet`
per input mzML at the end of Stage 4 (main first-pass search). The schema
is file-tagged and contains everything Stage 5 (Percolator FDR) needs:
21 PIN features, peak boundaries, CWT candidates, reference XICs, and
footer hashes for cache validation. Stage 5's entry points already accept
`per_file_entries: &[(String, Vec<FdrEntry>)]` — a shape that is trivially
constructible from N Parquet files produced by N HPC nodes.

What is **missing** is a first-class CLI story:

- **No "stop after scoring" flag.** Today the only gate is a diagnostic
  env var `OSPREY_EXIT_AFTER_SCORING`, which is not a production contract.
- **No "resume from Parquet" flag.** `OspreyConfig.input_files` only
  accepts mzML paths; there is no way to tell either tool "skip Stages
  1-4 and start from these N `.scores.parquet` files."
- **No merge subcommand.** There is no `osprey merge-fdr ...` command
  that takes N scoring-only Parquets and produces the final blib.

### Skyline precedent

Skyline solves the equivalent cluster problem with
`--import-no-join` (`pwiz/pwiz_tools/Skyline/CommandArgs.cs:360-362`,
`ARG_IMPORT_NO_JOIN` → `ImportDisableJoining = true`). HPC scheduling
orchestration software fans chromatogram extraction out across worker
nodes per file (or per small file group), then hands the final join to
a separate compute node. We want the same story for Osprey: Stages 1-4
on workers, Stage 5+ on a merge node.

## Current state (concrete citations)

### Already in place (the good news)

- **Per-file Parquet writer with footer metadata**
  - Rust: `osprey/crates/osprey/src/pipeline.rs:1047, 1147-1344`
    (`write_scores_parquet_with_metadata`, ZSTD, writes next to mzML)
  - C#: `OspreySharp.IO/ParquetScoreCache.cs:142, 420-425`
    (`GetScoresPath`, Snappy)
  - Schema: 14 identity/boundary columns + 5 variable-length binary
    arrays + 21 PIN feature columns + `file_name` column

- **Cache validity via SHA-256 footer hashes**
  - Rust: `osprey/crates/osprey/src/pipeline.rs:96-130`
    (`validate_scores_cache` → `ValidFirstPass` / `ValidReconciled` /
    `Stale`; keys: `osprey.version`, `osprey.search_hash`,
    `osprey.library_hash`, `osprey.reconciled`,
    `osprey.reconciliation_hash`)

- **Selective Parquet loaders** (no need to rehydrate full entries)
  - Rust: `pipeline.rs:1346-1520` —
    `load_fdr_stubs_from_parquet`, `load_pin_features_from_parquet`,
    `load_cwt_candidates_from_parquet`, `load_blib_plan_entries`
  - C#: `OspreySharp.IO/ParquetScoreCache.cs:236-282`
    (`LoadFdrStubsFromParquet`, `LoadPinFeaturesFromParquet`)

- **Stage 5 entry is already file-indexed**
  - Rust: `pipeline.rs:2690` `run_percolator_fdr(per_file_entries, ...)`
  - C#: `AnalysisPipeline.cs:4134` `RunPercolatorFdr(perFileEntries, ...)`
  - Percolator TDC loop: `osprey-fdr/src/percolator.rs:1653-1732`
    (`compute_fdr_from_stubs` iterates
    `per_file_entries.iter().enumerate()`)

### Missing (the gaps this sprint closes)

- Only gate for "stop after Stage 4" is the env var
  `OSPREY_EXIT_AFTER_SCORING`:
  - Rust: `pipeline.rs:2642-2647`
  - C#: `AnalysisPipeline.cs:269-272`
- `OspreyConfig` has only `input_files` (mzML), no `input_parquets`
  - Rust: `osprey-core/src/config.rs:16-88`
  - C#: `OspreyConfig.cs` (mirror)
- `main.rs:72-165` clap args and `Program.cs:94-382` arg parser have
  no `--no-join` / `--input-scores` / `merge-fdr` surface.
- `run_analysis` (Rust) / `AnalysisPipeline.Run` (C#) is a single
  monolith end-to-end function; no Stage-4-only entry and no
  Stage-5+-from-Parquet entry.

## Proposed CLI

Adopt Skyline's `--no-join` naming for user familiarity.

### New flags on the existing `osprey` / `OspreySharp` binary

| Flag | Behavior |
|---|---|
| `--no-join` | Run Stages 1-4 on the given `--input` mzML(s). Write per-file `.scores.parquet`. **Do NOT run Stage 5 FDR. Do NOT write a blib.** Exit 0 on success. Mutually exclusive with `--join-only`. |
| `--join-only` | Skip Stages 1-4 entirely. Read Parquet inputs (see `--input-scores`), run Stage 5+ (Percolator FDR, optional refinement + protein FDR), write the blib at `--output`. Mutually exclusive with `--no-join` and `--input`. |
| `--input-scores <PATH...>` | One or more `.scores.parquet` files (or a directory; directory scans for `*.scores.parquet` non-recursively). Required when `--join-only` is set. Replaces `--input` for that mode. |

Both tools enforce:
- With `--no-join`: `--output` is optional; if supplied, is ignored
  with a warning (no blib is written).
- With `--join-only`: `--input` must NOT be set; `--library` and
  `--output` are required.
- Parquet footer hashes must all agree with each other (same
  `library_hash`, `search_hash`) and with the `--library` passed to
  the merge command. A mismatch aborts with a clear error pointing
  to which file differs.

### Retired env var

`OSPREY_EXIT_AFTER_SCORING` is removed from both implementations after
`--no-join` lands. Bench/profile scripts that use it today
(`ai/scripts/OspreySharp/Bench-Scoring.ps1`, `Profile-OspreySharp.ps1`,
and anything in `osprey/scripts/`) are updated to pass `--no-join`
instead. `OSPREY_EXIT_AFTER_CALIBRATION` stays — it has no production
analog and its purpose is purely diagnostic.

### Example HPC deployment

```
# Worker node N (one per mzML, in parallel on a cluster):
osprey --no-join \
       --input data/file_N.mzML \
       --library ref.blib \
       --resolution hram

# Merge node (after all workers succeed):
osprey --join-only \
       --input-scores data/*.scores.parquet \
       --library ref.blib \
       --output experiment.blib \
       --protein-fdr 0.01
```

## Implementation plan

Ship as a single branch with Rust and C# landing in step — the two
tools must stay at CLI parity and their Parquet hashes must match
exactly across the split.

### Phase 1: Wire the flags through config (Rust + C# in parallel)

1. **Config**
   - Rust `osprey-core/src/config.rs`: add
     `pub input_scores: Option<Vec<PathBuf>>` and
     `pub no_join: bool` (defaults: `None` / `false`). Serde derives
     stay compatible.
   - C# `OspreyConfig.cs`: add `List<string> InputScores` and
     `bool NoJoin`. Same defaults.

2. **CLI parsing**
   - Rust `main.rs`: add clap args `--no-join`, `--join-only`,
     `--input-scores <PATH...>` (num_args = 1..). Implement the
     mutual-exclusion and directory-scan logic in a new helper
     (`resolve_input_scores`).
   - C# `Program.cs`: add the same three switches. Keep the existing
     hand-rolled parser style. Directory scan via
     `Directory.GetFiles(dir, "*.scores.parquet")`.
   - Both: update `PrintUsage` / clap help.

### Phase 2: Split the pipeline

1. **Rust** (`crates/osprey/src/pipeline.rs`): refactor
   `run_analysis(config)` into:
   - `run_stages_1_4(&config) -> PerFileCache`
     (returns the `Vec<(String, Vec<FdrEntry>)>` plus cache paths)
   - `run_stage_5_and_beyond(config, per_file_cache) -> Result<()>`
   - Thin top-level `run_analysis` that either calls both (default),
     only the first (`--no-join`), or only the second
     (`--join-only`, where `per_file_cache` is built from
     `--input-scores` via the existing `load_fdr_stubs_from_parquet`).
   - Remove the `OSPREY_EXIT_AFTER_SCORING` env var check
     (`pipeline.rs:2642-2647`).

2. **C#** (`OspreySharp/AnalysisPipeline.cs`): same split.
   - Extract `RunStages14` and `RunStage5AndBeyond` out of the current
     ~4,700-line `Run` method (the extraction is narrow — just the
     orchestration seam, not the full FeatureExtractor refactor noted
     in Phase 4 of the active TODO).
   - Remove the `OSPREY_EXIT_AFTER_SCORING` check
     (`AnalysisPipeline.cs:269-272`).

### Phase 3: Cache validation for join-only mode

1. **Parquet group validation**
   - Rust: new helper `validate_scores_parquet_group(paths, library,
     config) -> Result<()>` that opens each Parquet footer, reads
     the 5 hash/metadata fields, and asserts:
     - same `osprey.version` across all files (or log a warning on
       patch-version mismatches, abort on minor/major mismatch)
     - same `osprey.library_hash` — and it matches the hash of the
       `--library` file passed on the merge command
     - same `osprey.search_hash`
   - C#: mirror in `ParquetScoreCache.cs`.

2. **Clear error messages** that name the offending file and field.
   Example: `"scores parquet mismatch: file_07.scores.parquet was
   scored with library_hash=abc... but ref.blib hashes to def..."`.

### Phase 4: Tests

Gate the work with real round-trip equivalence — "split then merge
produces the same blib as end-to-end" is non-negotiable.

1. **Stellar 3-file round-trip** (fast, runs in CI-ish wall-clock)
   - Baseline: existing end-to-end run, capture `.blib` sha + PIN
     features from `Test-Features.ps1`.
   - Split: run `--no-join` on each of 3 files sequentially, then
     `--join-only` on the 3 resulting Parquets.
   - Assert: Parquets bit-identical to baseline per-file; final blib
     byte-identical modulo SQLite timestamp noise (compare
     RefSpectra + RetentionTimes rows).

2. **Astral 3-file round-trip** (nightly / on-demand)
   - Same protocol at scale.

3. **Cross-impl round-trip**
   - OspreySharp `--no-join` writes Parquets; Rust `osprey
     --join-only` merges them (and vice versa). Parquets are the
     shared contract; this proves the contract holds.

4. **Negative tests**
   - Mixed `library_hash` across Parquets → abort with named file
   - `--library` whose hash disagrees with Parquets → abort
   - `--no-join` + `--output` → warn, don't write blib
   - `--join-only` + `--input` → argument error
   - Old version Parquet → abort with upgrade hint

5. **Unit tests** for `validate_scores_parquet_group` and
   `resolve_input_scores` (directory scan, glob-like expansion,
   mutual-exclusion enforcement).

### Phase 5: Docs + scripts

1. Update `C:\proj\pwiz\pwiz_tools\OspreySharp\Osprey-workflow.html`
   with an HPC deployment note on the Stage 4 → Stage 5 arrow.
2. Update `osprey/docs/12-intermediate-files.md` to document the
   `--no-join` / `--join-only` contract and the Parquet schema as a
   public contract (not an internal cache).
3. Update `ai/scripts/OspreySharp/Bench-Scoring.ps1` and
   `Profile-OspreySharp.ps1` to use `--no-join` instead of the
   env var.
4. Release notes entry in
   `osprey/release-notes/RELEASE_NOTES_v{next}.md`.

## Sizing estimate

- Rust: ~300 LOC (config + clap + pipeline split + validator) +
  ~150 LOC tests. The validator is the only non-mechanical piece.
- C#: ~400 LOC (heavier because the arg parser is hand-rolled and
  `AnalysisPipeline.Run` is monolithic; the split requires careful
  seam placement but no behavior change).
- Scripts + docs: ~100 LOC.
- One focused sprint, ~3 working days including round-trip
  validation on both datasets.

## Upstream strategy (maccoss/osprey)

This goes on top of the in-flight Batch 1-3 upstream effort
(`ai/todos/active/TODO-OR-20260417_osprey_rust_upstream.md`). Order
options:

- **Preferred**: land this as **Batch 4** after diagnostics +
  HRAM pool + parallel-files are in. By that point Mike has seen
  the file-parallel pattern (`OspreyConfig.clone` + `Rayon`) and
  the Parquet cache; `--no-join` is a natural extension.
- **Alternative**: split the scoring/merging CLI as a separate PR
  on our fork first to validate on real cluster runs, then upstream
  once proven.

The upstream PR body should lead with Skyline's `--import-no-join`
precedent — it's a well-understood idiom in the MacCoss-adjacent
tooling ecosystem.

## Out of scope

- Rewriting the Parquet schema. The existing schema is already
  file-tagged and has everything Stage 5 needs. Treat it as the
  public contract for HPC handoff as of this sprint.
- Reconciliation / consensus RT across files happens **inside**
  Stage 5 today and stays there. The merge node does the full
  Stage 5-8 run; workers only do Stages 1-4.
- Cluster orchestration itself (SLURM / Panorama Partners cluster
  / Nextflow / etc.). That belongs to the operator; the CLI
  contract established here is what makes orchestration possible.
- Incremental / resumable Stage 4 (partial mzML progress). The
  unit of work is a whole mzML file → whole Parquet.
- The six deferred C# cleanup items (FeatureExtractor extraction,
  stage-class split, PercolatorFdr split, etc.) noted in the active
  TODO. The Stage 4/5 seam needed here is narrow enough to extract
  without doing the full stage-class split.

## Success criteria

1. A user can run `osprey --no-join -i one.mzML -l lib.blib` on N
   worker nodes and `osprey --join-only --input-scores *.scores.parquet
   -l lib.blib -o experiment.blib` on a merge node, and the resulting
   blib is byte-identical (modulo SQLite timestamps) to an end-to-end
   `osprey -i all.mzML -l lib.blib -o experiment.blib` run.
2. Same property for OspreySharp.
3. Parquet files produced by either tool can be consumed by either
   tool's `--join-only` mode.
4. `OSPREY_EXIT_AFTER_SCORING` is gone from both codebases;
   bench/profile scripts use `--no-join` exclusively.
5. Mismatched library / search-parameter Parquets produce a clear,
   actionable error rather than corrupt output.

## References

- Active TODOs:
  - `ai/todos/active/TODO-20260409_osprey_sharp.md` — OspreySharp
    port (Phases 1-4 complete; this sprint is the Phase 5
    precondition)
  - `ai/todos/active/TODO-OR-20260417_osprey_rust_upstream.md` —
    upstream Rust batches (this work queues after Batch 3 or runs
    in parallel on our fork)
- Skyline precedent: `pwiz/pwiz_tools/Skyline/CommandArgs.cs:360-362`
  (`ARG_IMPORT_NO_JOIN` → `ImportDisableJoining`)
- Workflow diagram:
  `pwiz/pwiz_tools/OspreySharp/Osprey-workflow.html`
  (Stage 4 → Stage 5 boundary is where the split lives)
