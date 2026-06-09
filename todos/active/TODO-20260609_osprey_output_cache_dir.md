# TODO-20260609_osprey_output_cache_dir.md -- Decouple input dir from output/cache dir (cross-impl)

> OspreySharp and Rust `maccoss/osprey` both write every per-file derived artifact --
> including the 6 GB `.spectra.bin` cache -- *next to the input mzML*. On read-only
> data this forces the test harness to copy the multi-GB mass-spec files into a
> writable workdir. Add `--work-dir` (sets both of the below), `--output-dir` (all
> non-cache derived artifacts), and `--cache-dir` (the spectra cache only) to **both
> tools, with identical names and semantics**, so each reads data in place and writes
> only derived output elsewhere. This is the tracked **prerequisite** for the
> overnight "Osprey Windows .NET Regression" TeamCity config (data from a read-only
> download cache; all writes confined to `OspreySharp\TestResults`) AND for keeping
> the cross-impl parity gate copy-free.

## Branch Information

- **Track A branch (OspreySharp / pwiz)**: `Skyline/work/20260609_osprey_output_cache_dir`
  (created 2026-06-09 in `C:\proj\pwiz`)
- **Track B branch (maccoss/osprey, Rust)**: upstream-style branch on
  `maccoss/osprey` (e.g. `output-cache-dir`); PR via `gh pr create --repo maccoss/osprey`
- **Base**: `master` (pwiz) / upstream default branch (osprey)
- **Created**: 2026-06-09
- **Status**: **IN PROGRESS (Track A).** Design converged 2026-06-09; Track A branch
  created and development started. Track B (Rust) follows once Track A lands.
  Prerequisite for the regression-nightly work (separate TODO, not yet written).
- **GitHub Issue**: (none)
- **PRs**: one pwiz PR (Track A) + one maccoss/osprey PR (Track B); must stay in
  lockstep on flag names/semantics.

## Mission

Make the data file location and the analysis output location independent **in both
implementations**, so the mass-spec data (`.mzML` now, `.raw` once `pwiz_data_cli.dll`
is wired in) is never copied to run an analysis. After this change both tools support
the proven HPC topology -- data files at a root, any number of analyses as subfolders
below it, zero copies of the spectrum data. The OspreySharp regression harness reads
from a read-only `osprey-testfiles-mzML` tree while writing only under
`pwiz_tools/OspreySharp/TestResults`, and `Compare-EndToEnd-Crossimpl.ps1` runs
**both** tools over one read-only dataset with zero copies on either side.

## Background -- root cause and disk cost

Every per-file artifact's path is derived from the input file path, so all of them
land next to the input mzML.

OspreySharp (C#):
- `.spectra.bin` -- `SpectraCache.GetCachePath` = `inputFile + ".spectra.bin"`
  (`SpectraCache.cs`), written at `PerFileScoringTask.cs:1490`.
- `.scores.parquet` -- `ParquetScoreCache.GetScoresPath(inputFile)`
  (`PerFileScoringTask.cs:1398`; "Same path convention as Rust `scores_path_for_input`").
- `.calibration.json` -- inline `{inputStem}.calibration.json` "in the same
  directory as the mzML input" (`PerFileScoringTask.cs:1278`).
- Stage 6 sidecars (`.scores-reconciled.parquet`, `.1st-pass.fdr_scores.bin`,
  `.2nd-pass.fdr_scores.bin`, `.reconciliation.json`) follow the same convention.

Rust `maccoss/osprey` (symmetric seams the C# was ported from):
- `crates/osprey-io/src/mzml/spectra_cache.rs` (the `.spectra.bin` cache)
- `scores_path_for_input` in `crates/osprey/src/pipeline.rs`
- clap CLI in `crates/osprey/src/main.rs`
- (exact write-site line numbers to be confirmed when speccing Track B)

The `.spectra.bin` cache is a settings-independent reorganization of the parsed,
centroided, **sorted** MS2+MS1 peak lists (`MzmlReader.LoadAllSpectra`, no settings
filter -- confirmed). It is **uncompressed**, so on already-centroided DIA data it is
~the same size as the mzML and yields *no* disk savings, only load-speed:

| File (Astral file 49) | Size |
|---|---|
| `...49.mzML` | 6.0 GB |
| `...49.spectra.bin` | 5.9 GB |
| `...49.scores.parquet` | 777 MB |
| `...49.{calibration,reconciliation}.json` + fdr sidecars | < 0.1 GB |

Because the cache must be co-located with the (read-only) input, the test harness
copies the mzML into a writable workdir -- and the stage-isolated regression copies
it into *every* per-stage workdir. The result is the `_`-prefixed folders in
`D:\test\osprey-runs\{stellar,astral}` each carrying a 6 GB mzML + 6 GB cache.

## Design (identical in both tools)

### CLI surface (three new options)

- **`--work-dir <dir>`** -- convenience that sets *both* `--output-dir` and
  `--cache-dir` to `<dir>`. The **testing** flag and the simple "everything in one
  place" option. Because it sets `--cache-dir` explicitly, the cache lands in
  `<dir>` regardless of whether the input directory is writable -- so testing does
  **not** depend on the data being on a read-only drive.
- **`--output-dir <dir>`** -- base directory for *all non-cache* per-file derived
  artifacts. Keyed by input basename: `<outputDir>/<inputBasename><ext>`.
  **Default = each input file's own directory** (current behavior; an analysis
  subfolder under a writable data root still "just works").
- **`--cache-dir <dir>`** -- override for `.spectra.bin` *only*. Default resolved by
  the order below.

**Precedence:** an explicit `--output-dir`/`--cache-dir` overrides the corresponding
component of `--work-dir` when both are supplied (`--work-dir D --cache-dir E` ->
outputs in `D`, cache in `E`). Keeps `--work-dir` a pure convenience.

**Cross-impl constraint:** the flag names and semantics are **identical** in both
tools so `Compare-EndToEnd-Crossimpl.ps1` passes `--work-dir <dir>` to each without
per-tool special-casing.

### Cache-location resolution order (when `--cache-dir` is not set)

`.spectra.bin` is settings-independent, so it should be shared across analyses, not
duplicated per run. Resolution:

1. **`--cache-dir <path>`** explicit (or via `--work-dir`) -> use it. The dedicated
   shared-pool / HPC "many settings tweaks on one dataset" case: point every
   analysis subfolder at one cache root and parse once.
2. else **beside the data file**, if that directory is writable (the logical
   default; mirrors `.mzML` beside `.raw`; auto-reuse for a naive user who just
   points at the data).
3. else **the `--output-dir`** (read-only data root).

Writability is **probed, not assumed** (ACL checks are unreliable): attempt the
beside-data write, fall back to `--output-dir` on IO failure, and **log the chosen
location** so the cache never silently "vanishes." C#'s save is already wrapped in
try/catch (`PerFileScoringTask.cs:1528`); the Rust side gets the equivalent.

### Centralize path derivation

Route the cache path, scores-parquet path, calibration path, and Stage 6 sidecar
paths through one resolver per tool (C#: e.g. `ArtifactPaths(inputFile, outputDir,
cacheDir)`; Rust: extend `scores_path_for_input` + the cache-path fn to take the
dirs). **Filenames are unchanged** (basename + extension) -- only the directory
moves -- so the "same path convention" parity note still holds and produced bytes
are identical regardless of directory.

### Cache becomes content-keyed (required, both tools)

Once `.spectra.bin` can live apart from its source, a basename match no longer proves
the data matches. Add a **source fingerprint** (mzML size + last-write-time) to the
cache header alongside the existing version; the loader validates it against the
actual input and re-parses on mismatch. The C# and Rust cache headers must agree on
the fingerprint layout (the format is shared / round-tripped).

## Back-compat and cross-impl parity

- Default `--output-dir` = next-to-input and default cache = beside-data preserve
  today's behavior and the HPC/end-user expectation; harnesses opt in via `--work-dir`.
- Directory redirection does not change any artifact's bytes, so the OspreySharp
  same-impl snapshot baselines and the cross-impl 1e-9 byte-parity gate are
  unaffected. The parity oracle: each tool must produce byte-identical output to its
  own pre-change behavior (just relocated) AND still match the other tool.
- A spectra-cache **format** change (new fingerprint field) bumps the cache version
  in both tools; old caches invalidate and re-populate.

## Track A -- OspreySharp (pwiz, Skyline conventions)

1. Add the three clap-equivalent options to the CLI/options parser.
2. Introduce the artifact-path resolver; route `SpectraCache.GetCachePath`,
   `ParquetScoreCache.GetScoresPath`, the inline calibration write, and the Stage 6
   sidecar writes through it.
3. Add the fingerprint to `SpectraCache` header + load validation.
4. Unit tests: resolver path math; read-only-input fallback; fingerprint
   invalidation; default-invocation byte-identity.
5. Gate: `Build-OspreySharp.ps1 -RunTests -RunInspection`, then the C#-side
   refactor gate `Compare-EndToEnd-Crossimpl.ps1 -Files All -SkipRust` on Stellar +
   Astral (bytes must be unchanged).

## Track B -- maccoss/osprey (Rust, upstream conventions)

> Skyline rules do NOT apply here: LF endings, `cargo fmt --check` +
> `clippy -D warnings` + `cargo test`, upstream-style commit prose, no
> `Co-Authored-By` unless the maintainer opts in. PR via `gh pr create --repo
> maccoss/osprey`.

1. Add `--work-dir`/`--output-dir`/`--cache-dir` to the clap args in
   `crates/osprey/src/main.rs`, identical names/semantics to Track A.
2. Thread the dirs into `scores_path_for_input` (`pipeline.rs`) and the spectra
   cache path fn (`spectra_cache.rs`), plus calibration/reconciliation sidecar
   writes.
3. Add the matching fingerprint to the Rust cache header + load validation; keep the
   header layout byte-compatible with Track A.
4. `cargo test` coverage for the path resolution + fingerprint; confirm default
   behavior unchanged.
5. After both tracks land, re-run the full cross-impl gate (drop `-SkipRust`) on
   Stellar + Astral to confirm copy-free parity end to end.

## Harness and nightly implications

- Reference the input mzML by **absolute path** from read-only
  `osprey-testfiles-mzML` -- never copied.
- Pass **`--work-dir <date-stamped TestResults run folder>`** (mirrors how the unit
  test `TestFilesDir` date-stamps per run). One flag puts outputs *and* cache there;
  no copy, no reasoning about input-dir writability, per-run isolation.
- Stage isolation then moves only the small derived artifacts (parquets, sidecars)
  between stages, never the raw mzML or the cache. Only the scoring/rescore stages
  load spectra, so the cache is built once.
- Two-mode nightly (straight-through vs. resume self-consistency): the two runs can
  share **one** spectra cache via a common `--cache-dir` while writing to separate
  `--output-dir`s for comparison -- parse the files once.
- Cross-impl gate: pass each tool its own `--work-dir` (or shared `--cache-dir` +
  per-tool `--output-dir`) over the read-only dataset -- zero copies on either side.

## Open decisions -- RESOLVED 2026-06-09

1. **Option names** -- `--work-dir` (both), `--output-dir` (non-cache artifacts),
   `--cache-dir` (spectra cache only); identical across both tools.
2. **Default `--output-dir`** -- next to each input file (unchanged behavior).
3. **Default `--cache-dir`** -- resolution order above (explicit/`--work-dir` ->
   beside-data if writable -> output-dir). Cache header gains size+mtime fingerprint.
4. **Precedence** -- explicit `--output-dir`/`--cache-dir` override the matching
   `--work-dir` component.
5. **Scope** -- both OspreySharp (Track A) and maccoss/osprey (Track B), to keep
   cross-impl parity testing copy-free.

## Progress log

- **2026-06-09 (Track A, commit `45c8762`)** -- CLI options + resolver landed and
  verified. `OspreyConfig.OutputDir/CacheDir` + `--work-dir`/`--output-dir`/
  `--cache-dir` parsing (precedence wired). New `OspreySharp.IO/ArtifactPaths`
  holder (set once in `Main`) routes the scores parquet, reconciled parquet,
  spectra cache, and calibration JSON through one place; the FDR /
  reconciliation sidecars cascade automatically (they hang off the redirected
  scores-parquet path), and the rescore spectra-cache/calibration lookups resolve
  through the same holder so straight-through and resume agree. Pre-commit gate
  green: build (net472 + net8.0), **0 inspection warnings, 379/381 tests pass**
  (2 pre-existing skips); existing path tests pass unchanged -> default path is
  byte-identical. Still TODO on Track A: spectra-cache fingerprint (size+mtime),
  new unit tests for the flags/fallback/fingerprint, and the C#-side parity gate
  (`Compare-EndToEnd-Crossimpl -SkipRust`, Stellar + Astral) for end-to-end
  byte-identity. Then Track B (Rust).

## Out of scope / future

- `pwiz_data_cli.dll` direct `.raw` reading. When it lands, the same cascade applies
  (`.raw -> .mzML -> .spectra.bin`, each generated beside its source when writable);
  vendor-centroided reads may make `.spectra.bin` optional -- a deliberate, separate
  evaluation (the sort step + cross-impl parity layout still matter).
- Compressing `.spectra.bin` (currently uncompressed and ~mzML-sized).

## Acceptance criteria

- Both tools run end-to-end with the input mzML on a **read-only** directory and all
  artifacts (incl. `.spectra.bin`) written under `--work-dir`; no copy of the data
  file is required.
- `--cache-dir` shared across two separate `--output-dir` runs parses the mzML once;
  the second run loads from cache.
- A changed source file (size/mtime) invalidates a stale `.spectra.bin` and triggers
  a re-parse, in both tools.
- Default invocation (no new flags) is byte-identical to current behavior in both
  tools; the OspreySharp snapshot regression and the cross-impl 1e-9 gate still pass.
