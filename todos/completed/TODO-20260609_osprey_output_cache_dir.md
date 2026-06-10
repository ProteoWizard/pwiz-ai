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
- **Status**: **COMPLETED 2026-06-09** -- both PRs squash-merged. Remains the
  prerequisite for the regression-nightly work (separate TODO, not yet written).
- **GitHub Issue**: (none)
- **PRs**: [ProteoWizard/pwiz#4278](https://github.com/ProteoWizard/pwiz/pull/4278)
  (merged 2026-06-09 as `c5f4d9c`) + [maccoss/osprey#47](https://github.com/maccoss/osprey/pull/47)
  (merged 2026-06-09 as `696c938`).

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

- **2026-06-09 (Track A complete: fingerprint + tests + help, commits `9ecc774`,
  `ffb1c12`)** -- `SpectraCache` VERSION 3 carries source size + mtime (Unix ms,
  matching the planned Rust layout); load rejects a changed source, skips when no
  fingerprint or source absent. Save/Load callers in PerFileScoring/PerFileRescore
  pass the source path. New `ArtifactPathsTest` (3 tests): resolver paths + flag
  precedence + byte-identical defaults + fingerprint invalidation. `--help`
  documents the three flags. Pre-commit gate green: build (both TFMs), **0
  inspection warnings, 384 tests (382 pass / 2 skip)**. Track A code is DONE and
  unit-verified. Track B (Rust) launched as a background subagent mirroring this
  design.
  - **Remaining before merge**: (1) end-to-end C#-side parity gate
    (`Compare-EndToEnd-Crossimpl -SkipRust`, Stellar + Astral) to confirm the
    default path is byte-identical end-to-end and the `--work-dir` path produces
    identical output; (2) `/pw-self-review` + Copilot.
  - **Follow-up found (out of scope here)**: the spectral library cache
    (`<library>.libcache`) is still written beside the `-l` library, so a fully
    read-only INPUT set (library included) needs the same treatment. Per-file
    artifacts + spectra cache are handled by this PR; the libcache is a separate,
    smaller redirect to wire before the nightly reads the library read-only.

- **2026-06-09 (both PRs open; self-review fix)** -- **Track A pwiz PR
  [#4278](https://github.com/ProteoWizard/pwiz/pull/4278)** (commit `f088d410`).
  Fresh-context `/pw-self-review` caught a CRITICAL miss: straight-through FDR /
  `reconciliation.json` sidecars bypassed `ArtifactPaths` and wrote beside the
  read-only input. Fixed by routing `FdrScoresSidecar`/`ReconciliationFile`
  through `ResolveOutputDir` (catches all callers); also unified the spectra-cache
  write on `GetCachePath` and pre-create `--output-dir`/`--cache-dir`. Sidecar
  redirect now has test coverage; gate green (0 warnings, 384/382).
  **Track B Rust PR [maccoss/osprey#47](https://github.com/maccoss/osprey/pull/47)**
  (branch `output-cache-dir`): full mirror, all Rust gates green (fmt/clippy/test),
  fingerprint byte-identical to C# VERSION 3 (`[version u32][size u64][mtime i64]`,
  Unix-ms). Note: `maccoss/osprey` HEAD relicensed Apache-2.0 -> LGPL-3.0 and
  banners "archived in favor of OspreySharp"; Brendan confirmed the Rust change is
  still wanted to normalize cross-impl testing. Both PRs made ready-for-review;
  Copilot reviews in-flight.
  - **Remaining**: address Copilot on both (`/pw-respond`); end-to-end parity gate
    (now that both sides exist, a FULL `Compare-EndToEnd-Crossimpl` with `--work-dir`
    on Stellar + Astral can confirm copy-free parity); then un-draft/merge order.

- **2026-06-09 (no-copy verified both impls; ready for /pw-complete)** -- An
  end-to-end `--work-dir` run (mzML from read-only `osprey-testfiles-mzML`) caught
  a real bug both sides had: the Stage 6 rescore loaded the calibration JSON from
  the input mzML's own directory, not the output dir -> fixed (C# `b936333`, Rust
  `a8855e0`). Separated-vs-default blib parity confirmed at 1e-9 (0 divergence /
  46,115 rows). Then the library `.libcache` was routed through `ResolveCacheDir`
  too (C# `5ab7cd3`, Rust `6fb89db`), closing the last input-adjacent write. **Both
  OspreySharp and Rust now pass a true no-copy run**: `-i` mzML and `-l` library
  both reference the read-only source in place, only `--work-dir` given; the run
  completes end-to-end and the source directory is untouched (no
  `.libcache`/`.spectra.bin`/`.parquet`/`.calibration.json` leaked). Both PRs green
  on their gates and **ready for `/pw-complete`** (#4278 drives the squash-merge +
  shared-TODO move; #47 branch cleanup after its merge).
  - Optional later: a source-size/mtime fingerprint on the `.libcache` (parity with
    the `.spectra.bin` fingerprint) for shared-cache-dir reuse; Rust already does a
    source-newer-than-cache mtime check, C# relies on magic/version.

### 2026-06-09 - Merged

Both PRs squash-merged: **pwiz #4278** as `c5f4d9c` and **maccoss/osprey #47** as
`696c938`. Shipped the full cross-impl change: `--work-dir`/`--output-dir`/
`--cache-dir` on both tools, every per-file artifact (scores parquet, calibration
JSON, FDR/reconciliation sidecars, `.spectra.bin`, and the library `.libcache`)
routed through the resolver, a `.spectra.bin` source size+mtime fingerprint
(byte-compatible across tools), and a fix for the Stage 6 rescore calibration
lookup (caught by the no-copy parity run). Both verified by an end-to-end no-copy
run (read-only mzML + library, only `--work-dir`) with the source dir untouched;
C# separated-vs-default blib parity exact at 1e-9. Deferred (noted below): a
`.libcache` source fingerprint to match the `.spectra.bin` one.

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
