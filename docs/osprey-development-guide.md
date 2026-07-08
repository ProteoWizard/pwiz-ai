# Osprey Development Guide

> **Conventions -- read this first.** This guide's deep-dives (parity doctrine,
> bisection, HPC flags, determinism) are shared by both implementations, but **which
> coding-convention set applies depends on which tree you touch** -- and that changed
> once the C# port became the path forward (it is no longer "maccoss/osprey is the
> master project"):
> - **C# Osprey (`pwiz_tools/Osprey`)** follows the Skyline rules in the `ai/*.md`
>   files IN FULL: `ai/CRITICAL-RULES.md` (no async/await, resource strings, CRLF,
>   `_camelCase`, helpers-after-callers), `ai/STYLEGUIDE.md` (control flow -- incl. **no
>   single-line `if`** -- using-directive order, file headers), `ai/TESTING.md`, and
>   `ai/WORKFLOW.md` (branch/commit/PR format). They are not optional just because this
>   file's deep-dives are Rust-heavy; the `/osprey-development` skill points at them.
> - **Rust osprey (`C:\proj\osprey`)** follows upstream conventions (LF endings,
>   `cargo fmt` / `clippy -D warnings`, upstream commit prose); the `ai/*.md` Skyline
>   rules do NOT apply there.

Development conventions for work on the `maccoss/osprey` Rust
project. Referenced by `TODO-OR-*.md` files, which may have workflow
rules that differ from the Skyline-mainline conventions documented
in `ai/WORKFLOW.md`.

## File header attribution (C# Osprey)

The `Original author:` line names **the developer who created the file with
Claude** -- i.e. the author of the PR that adds it -- NOT a fixed person.
`ai/STYLEGUIDE.md` already spells this out (`[Author Name]`); the osprey-only
trap is that **every existing Osprey C# file was authored by Brendan (he wrote
the port), so seeding a new file's header by copying a sibling carries
`Brendan MacLean` forward verbatim** -- wrong whenever someone else is the
author. Skyline never hits this because its files have many authors. When you
add a file, set `Original author:` to the real author, not whatever the
neighboring file says.

For example, files added by a Mike MacCoss PR use:

```csharp
/*
 * Original author: Michael MacCoss <maccoss .at. uw.edu>,
 *                  MacCoss Lab, Department of Genome Sciences, UW
 * AI assistance: Claude Code (Claude <Model>) <noreply .at. anthropic.com>
 *
 * Based on osprey (https://github.com/MacCossLab/osprey)
 *   by Michael J. MacCoss, MacCoss Lab, Department of Genome Sciences, UW
 *
 * Copyright <Year> University of Washington - Seattle, WA
 * ...
 */
```

The rest of the `ai/STYLEGUIDE.md` header applies in full -- only the
`Original author:` identity varies by who wrote the file. Existing files keep
their original author (Brendan's port files stay Brendan); do not rewrite
history. Keep the `Based on osprey ... by Michael J. MacCoss` line on every
Osprey file regardless of author -- that credits the tool's origin, separately
from who authored this particular file.

## Workspace structure

`maccoss/osprey` is a Cargo workspace with 7 crates:

| Crate | Role | Notable source |
|---|---|---|
| `osprey-core` | Data types, configs, enums | `src/types.rs`, `src/config.rs` |
| `osprey-io` | mzML reader, library loaders, blib writer | `src/mzml/parser.rs`, `src/library/` |
| `osprey-scoring` | XCorr, cosine, batch scoring | `src/lib.rs` (SpectralScorer), `src/batch.rs` |
| `osprey-chromatography` | RT calibration, peak detection | `src/calibration/`, `src/cwt.rs` |
| `osprey-ml` | Machine learning (SVM, matrix, q-value) | `src/svm.rs`, `src/matrix.rs` |
| `osprey-fdr` | Percolator, protein FDR | `src/percolator.rs` |
| `osprey` (binary) | Main entry + pipeline orchestration | `src/pipeline.rs`, `src/main.rs` |

Workspace manifest: `Cargo.toml` at the repo root lists all seven
as workspace members.

## Osprey project layering

The C# port at `pwiz_tools/Osprey/` mirrors the Rust crate split
with seven `.csproj`s:

| Project | Role |
|---|---|
| `Osprey.Core` | Data types, configs, enums, env-var wrapper (`OspreyEnvironment`). **Bottom of the dependency graph -- everything else depends on Core.** |
| `Osprey.IO` | Library loaders, parquet readers/writers, blib writer |
| `Osprey.ML` | Machine learning (SVM, PEP, matrix) |
| `Osprey.Chromatography` | RT calibration (`RTCalibrator`), peak detection |
| `Osprey.Scoring` | XCorr, cosine, batch scoring |
| `Osprey.FDR` | Percolator, protein FDR, reconciliation |
| `Osprey` (main) | Pipeline orchestration, CLI, diagnostics |

### Sharing rule: push down to Core

When a class defined in one component is needed by another, **push it
down into `Osprey.Core`**. Don't reference across siblings (cycles
are impossible on Core's level; everywhere else, cross-references either
fail to compile or invite hidden coupling), and don't duplicate the
logic (DRY -- see `ai/CRITICAL-RULES.md`).

The default move when a new cross-component need surfaces is "move the
existing class down to Core" (one file move + namespace change + caller
using-statement updates), not "create a new project". Reserve a new
project (e.g. a hypothetical `Osprey.Util`) for when multiple
shared utilities accumulate enough to justify the project boilerplate.

### No direct env-var reads in business code

Production code MUST NOT call `System.Environment.GetEnvironmentVariable`
inline. Env-var-derived settings live in dedicated wrapper classes:

- `OspreyEnvironment` (in `Osprey.Core`) for production / throttling
  / algorithm-variant flags read by the pipeline.
- `OspreyDiagnostics` (in `Osprey` main) for cross-impl bisection
  dump flags.

Both expose env vars as `static readonly` fields read once at process
start, so call sites stay clean and the env-var contract is documented
in one place. The same Rust convention applies in `osprey-core`'s
`diagnostics` module (`is_dump_enabled`, `exit_if_only`).

When a new env var is needed in a project that the wrapper class doesn't
yet live in, push the wrapper down to Core first (see "Sharing rule"
above), then add the new field.

### Atomic file writes: FileSaver (never a cross-volume temp + move)

Every DURABLE artifact -- anything a later step, a resume, or the user reads
back (`calibration.json`, `reconciliation.json`, `.fdr_scores.bin`,
`.osprey.task`, `.spectra.bin`, `.libcache`, `.scores.parquet`, `.blib`, the
`--fdrbench` input) -- is written through `FileSaver` (in `Osprey.Core`),
never straight to its final path:

```csharp
using (var saver = new FileSaver(finalPath))
{
    using (var stream = new FileStream(saver.SafeName, FileMode.Create, FileAccess.Write))
    using (var w = new BinaryWriter(stream))   // or StreamWriter / File.WriteAllText(saver.SafeName, ...)
    {
        // ... write to saver.SafeName ...
    }
    saver.Commit();   // after the inner writer closes (flushed), inside the saver using
}
```

`FileSaver.SafeName` is a **same-directory sibling** temp; `Commit()` is a
same-volume rename (a metadata-only op) -- atomic, and it CANNOT truncate. A
failure before `Commit()` disposes the temp and leaves the previous final
content (or nothing), never a partially-written destination a resume check
could mistake for finished output.

**Never write to a separate temp directory (e.g. `Path.GetTempPath()`) and
then `File.Move`/`File.Copy` to the final path.** That crosses volumes, so
`File.Move` degrades to a byte copy that can silently land a *truncated* file
on CIFS/NFS/NAS -- the failure mode Rust guards with `copy_and_verify`. The
same-directory rename sidesteps it entirely, so no post-move size/hash
verification is needed on the C# side (`copy_and_verify` need not be ported).
The parquet writer once did exactly this anti-pattern (temp in the system temp
dir + `File.Move`, mislabelled "safe NAS writes"); it now uses `FileSaver`.

**Exempt:** `-d` diagnostic dumps (`OspreyFileDiagnostics` etc.), the streaming
CLI log, and test fixtures -- transient or append-streaming files that are not
durable pipeline artifacts.

## Repositories

| Path | Remote | Purpose |
|---|---|---|
| `C:\proj\osprey` | `maccoss/osprey` (SSH) | **Primary working tree.** Branches for new PRs live here. Also serves as upstream baseline for `Bench-Scoring.ps1` when checked out to `main`. Brendan has push access. |
| `C:\proj\osprey-fork` | `brendanx67/osprey` | **Retired fork.** Preserved as archive; do not extend. Several session's scripts still reference it for legacy but new work ignores it. |

(Rename from `osprey-mm`/`osprey` to `osprey`/`osprey-fork` completed
2026-04-21. Any remaining scripts or docs that mention `osprey-mm`
should be updated to `osprey` when touched.)

New work goes to branches on `maccoss/osprey` directly, never to
the fork. Push directly; create PR with
`gh pr create --repo maccoss/osprey`.

**Bench-Scoring discipline**: `C:\proj\osprey` is shared between
active branch work and `Bench-Scoring.ps1`'s upstream-baseline role.
Before running a benchmark, check out `main` (`git checkout main`)
so the baseline measurement isn't polluted by in-progress changes.

## Build and test commands

**Use the wrapper scripts under `ai/scripts/Osprey/`**, not raw
`cargo` commands. Wrappers enforce a consistent build environment
across developer machines (independent of which Visual Studio version
happens to be installed), and also serve as the single place to thread
new knobs like `-OspreyRoot` through every caller.

The wrappers set:

- `CMAKE_GENERATOR = "Ninja"` -- avoids the `cmake` crate's
  auto-detected "Visual Studio NN YYYY" generator string, which will
  not match the `cmake.exe` on PATH once a developer installs a newer
  VS than the bundled `cmake.exe` knows about.
- `VCPKG_ROOT = "$env:USERPROFILE\vcpkg"` -- required by
  `openblas-src` and friends to locate prebuilt BLAS.

**One-time setup: Ninja must be on PATH.** Visual Studio installs
bundle a Ninja binary. Add the VS 2022 Community copy to the User
PATH once, then restart your shell:

```powershell
[Environment]::SetEnvironmentVariable(
    "Path",
    "$([Environment]::GetEnvironmentVariable('Path','User'));C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja",
    "User"
)
```

Prefer the VS 2022 path over VS 2026 preview -- the 2026 folder may
be renamed as the preview evolves. If VS is installed under a
non-Community edition (Professional, Enterprise), substitute the
edition name.

Raw `cargo build`/`test`/`clippy` works only if the developer happens
to have both of these set (e.g. in a shell profile) *and* the machine's
installed `cmake.exe` understands the `cmake` crate's picked generator.
That's fragile across machines; the wrapper is authoritative.

**Primary wrapper**:

```bash
# Build release (default is C:\proj\osprey = maccoss/osprey primary)
pwsh -File ./ai/scripts/Osprey/Build-OspreyRust.ps1

# Build a different tree (rare; e.g. the retired fork at C:\proj\osprey-fork)
pwsh -File ./ai/scripts/Osprey/Build-OspreyRust.ps1 -OspreyRoot C:/proj/osprey-fork

# With format + lint + tests (mirrors what CI runs -- use before every push)
pwsh -File ./ai/scripts/Osprey/Build-OspreyRust.ps1 -Fmt -Clippy -RunTests
```

**CI parity check**: the `maccoss/osprey` GitHub Actions workflow
runs `cargo fmt --check`, `cargo clippy --all-targets --all-features
-- -D warnings`, and `cargo test` on Linux/macOS/Windows. Running
the wrapper with `-Fmt -Clippy -RunTests` exercises the same gates
locally. A few lints are CI-only flavored (e.g.
`clippy::items-after-test-module` — test modules must be the last
item in the file, not sandwiched between pub items); check CI on the
first push of every new branch to catch these early.

**Raw cargo reference** (for understanding what the wrappers run):

```bash
cargo build --workspace --release
cargo test --workspace                         # includes inline #[cfg(test)]
cargo clippy --workspace -- -D warnings        # Rust equivalent of ReSharper
cargo fmt --all -- --check
cargo test -p osprey-scoring                   # single crate
```

Targets **Rust 1.75+** (see workspace `rust-version`). Check
`rustup show` if you get toolchain-related compile errors.

**If the wrappers don't cover your task** (e.g. full-workspace
test + clippy for a baseline sanity check, or running the binary from
a non-default tree): extend the existing script. See "Running against
a non-fork tree" below for script-by-script parameterization status.

### Running against a non-default tree

Under the post-2026-04-21 layout, `C:\proj\osprey` is the single
primary tree (what was previously `osprey-mm`). Scripts have
residual parameterization from the dual-tree era:

| Script | Accepts alternate tree? | Notes |
|---|---|---|
| `Build-OspreyRust.ps1` | `-OspreyRoot` param, default `C:\proj\osprey` | Works on any tree |
| `Bench-Scoring.ps1` | Hardcoded two-tree comparison (historical) | May need updating once the legacy fork references are swept out |
| `Run-Osprey.ps1` | Check before invoking on a non-default tree | Older script; may still hardcode a path |
| `Test-Features.ps1` | `-CsharpRoot` param with auto-detect across `pwiz-work1` / `pwiz` / `pwiz-work2` | The Rust side always uses `C:\proj\osprey` |

When extending these scripts, the canonical Rust root is
`C:\proj\osprey`. Do not reintroduce the `osprey-mm` name.

## Test data locations

Not committed; lives on the developer workstation:

- `D:\test\osprey-runs\stellar\` -- 3 Stellar mzML files, ~1 GB each
- `D:\test\osprey-runs\astral\` -- 3 Astral HRAM mzML files, ~5-10 GB each

Dataset-specific configuration:
`ai/scripts/Osprey/Dataset-Config.ps1`.

## Cross-implementation parity testing

### The parity gate is a STANDING requirement -- mirror every substantive change in Rust

The C#<->Rust byte-identity gate is **not** being retired soon. It is kept
deliberately because it is too valuable: Mike's parallel Rust work plus the
byte-identity comparison keep catching real divergences, and that extra testing
outweighs the double-PR overhead. Treat it as a durable gate, not an
about-to-go one.

**Rule: every SUBSTANTIVE C# change ships with a companion Rust PR** in
`maccoss/osprey` that keeps the two implementations at bit-parity. "Substantive"
= anything that can move the numbers or the discovery set: scoring, calibration,
LOESS/KDE, SVM/Percolator, FDR, decoy generation, reconciliation, blib output.
Pure-C# refactors that are byte-neutral (file moves, comments, renames that don't
touch output) do NOT need a Rust mirror.

Workflow:
- Open the C# PR and a companion Rust PR in `maccoss/osprey`, branched off the
  **current parity base** (e.g. `reconciliation-v3-first-pass-base-ids`).
- Validate the pair with `Compare-EndToEnd-Crossimpl` at 1e-9 on **Stellar AND
  Astral** before merging either side.
- For a **parity-affecting** change (one that deliberately changes the numbers --
  e.g. making Percolator streaming-only, which drops the direct/no-stream path),
  switch BOTH tools together and re-baseline the golden. Parity stays green
  because both sides move to the same new behavior; only the absolute values
  change.

Canonical template pair: **pwiz#4390 (C#) <-> maccoss/osprey#49 (Rust)** -- the
experiment-q best-of-runs clamp. The Rust PR is a single-commit diff whose body
opens with "Mirrors the C# Osprey ... (ProteoWizard/pwiz#NNNN) so the two
implementations stay in cross-impl parity," validated on Stellar + Astral.

The cross-impl bisection infrastructure lives on the C# side (under
`ai/scripts/Osprey/`) but drives both tools:

```
# Stellar parity (fast, ~2 min)
pwsh -File ./ai/scripts/Osprey/Test-Features.ps1 -Dataset Stellar

# Astral parity (slow, ~18 min)
pwsh -File ./ai/scripts/Osprey/Test-Features.ps1 -Dataset Astral

# Re-use existing Rust output (skip the ~16 min Rust run)
pwsh -File ./ai/scripts/Osprey/Test-Features.ps1 -Dataset Astral -SkipRust
```

All 21 PIN features must remain bit-identical at the `1E-06`
threshold. Run this gate after every Rust change that could affect
scoring or calibration.

**Perf benchmark**:

```
pwsh -File ./ai/scripts/Osprey/Bench-Scoring.ps1 -Dataset Stellar -Files Single -Iterations 3
```

Compares upstream Rust (`osprey-mm`), our fork Rust (`osprey`), and
Osprey (C#). `-SkipUpstream` skips the upstream Rust run.

## FDRBench entrapment validation (the correctness oracle)

Cross-impl parity (above) proves the two implementations *agree*. It
says nothing about whether the FDR they both report is *correct*.
**FDRBench is the independent oracle that answers the second question**,
and it is now a first-class gate for any change that can move the
discovery set or the reported q-values (scoring, calibration, FDR,
compaction, reconciliation, decoy handling).

**FDRBench** ([Noble-Lab/FDRBench](https://github.com/Noble-Lab/FDRBench))
is an external Java tool that measures the *true* false-discovery
proportion (FDP) of a search result by the entrapment method: the
search library is spiked with **entrapment** sequences that are known
to be absent from the sample, so any entrapment peptide reported at a
given q-value is a known-false discovery. FDRBench counts them across
the reported ranking and produces an FDP-vs-reported-q curve. Perfect
calibration is the `y = x` line; a curve **above** it means the search
is anti-conservative (under-reporting its true error rate).

- Local install: **FDRBench v1.1.1** jar at `D:\test\fdrbench\`.
- Ground-truth data: Carafe-built entrapment libraries delivered by
  Mike via Panorama (`StellarTest-TargetDecoyLibraries/`,
  `AstralTest-TargetDecoyLibraries/`), each with `target+decoy/` and
  `target+decoy+entrapment/` variants (a `carafe_spectral_library.tsv`
  + an `osprey_library_db_pairing.tsv` FDRBench pairing manifest +
  fasta). Entrapment ratio is 1:1. Staged at
  `D:\test\osprey-runs\{stellar,astral}-libdecoy\`; decoy-stripped
  "generated-decoy" variants at `...-gendecoy\`.

### The doctrine: the oracle wins over parity

When entrapment FDP and cross-impl parity disagree, **the oracle
wins.** Matching a late-breaking (possibly-incorrect) reference is not
a correctness proof. Two decisive precedents:

- **The base_id reconciliation fix** reached Rust byte-parity
  (30674 = 30674, stage-7 + blib @ 1e-9) yet **degraded** entrapment
  FDP on Stellar library-decoy from 0.82% to 1.46% (above the line).
  It was held back rather than shipped to match Rust -- see
  [[project_osprey_libdecoy_vs_gendecoy_calibration]] and
  [[feedback_parity_vs_impact]]. Rust HEAD was simply anti-conservative
  there too.
- **The pass-2 protein-FDR investigation:** the oracle showed the
  `--protein-fdr` rescue removal was a near no-op on output and that the
  real anti-conservative source was the 2nd-pass Percolator
  *recalibration* on a decoy-depleted null -- a conclusion no parity
  gate could have reached. See
  [[project_osprey_pass2_recalibration_inflates_fdr]].

Corollary: report every measured cell honestly, and judge any
FDR-affecting code change on the entrapment oracle, not on parity or on
raw discovery count. More raw IDs at a claimed 1% q is *worse*, not
better, if the extra IDs are disproportionately entrapment hits.

### The pipeline (Osprey run -> FDRBench input -> FDP curve)

The committed driver **`ai/scripts/Osprey/Run-FdrBench.ps1`** runs all three
stages below for one cell and prints the calibration metrics (it dot-sources
`Dataset-Config.ps1`, resolves the jar, and parses `fdp.csv` natively -- no
Python needed for the numbers):

```
# Calibrated reference cell (library-supplied decoys, reported level):
pwsh -File ./ai/scripts/Osprey/Run-FdrBench.ps1 -Dataset StellarLibraryDecoy

# Anti-conservative demonstration (Osprey-generated reverse decoys):
pwsh -File ./ai/scripts/Osprey/Run-FdrBench.ps1 -DecoySource Generated

# The --protein-fdr pass-2 A/B (same binary, cell A off vs cell B on):
pwsh -File ./ai/scripts/Osprey/Run-FdrBench.ps1 -ProteinFdr '' -FragmentTolerance 0.4 -OutName A_noprotein
pwsh -File ./ai/scripts/Osprey/Run-FdrBench.ps1 -ProteinFdr 0.01 -FragmentTolerance 0.4 -OutName B_proteinfdr
```

The three stages it wraps:

1. **Osprey emits the FDRBench input TSV.** The committed CLI is
   `--fdrbench <input.tsv>` (one row per precursor, experiment-level
   q) plus `--fdrbench-per-run` (one row per precursor+run, run-level
   q; adds a `run` column). The writer is
   `pwiz_tools/Osprey/Osprey.Tasks/FdrBenchInputWriter.cs` (a port of
   Rust `osprey-io/src/output/fdrbench.rs`
   `write_fdrbench_peptide_input`). It emits **every reported
   (compaction-surviving) target regardless of q-value**, with the raw
   SVM discriminant as the `score` column, so FDRBench sees the full
   reported ranking without truncation at Osprey's threshold.
   Entrapment sequences are marked by `_p_target` in the protein
   accessions and pass through as targets; decoys are excluded. The
   `protein` column is capped at 4000 chars (FDRBench's bundled
   Univocity CSV parser aborts past 4096).

2. **Run the FDRBench jar** on that TSV. The score is
   "higher-is-better", so invoke with `-score 'score:1'`. Runs to date
   are **precursor-level** (`-level precursor`); the FDP is
   parameter-sensitive, so pin `-fold` / `-r`, `-pick first`, and
   `-seed` (the pass-2 oracle used `-level precursor -fold 1
   -pick first -seed 2000`). Entrapment is recognized via the
   `_p_target` marker. FDRBench emits an FDP CSV.

3. **Read the curve.** FDRBench reports **combined FDP** and **paired
   FDP** vs Osprey's reported q. Plot both against `y = x`, **zoomed to
   q,FDP in [0, 0.02]** -- the whole point is deviations below 1%, and
   a 0->1.0 axis hides them. For comparing two methods fairly, also
   read **discoveries at true 1% FDP** (walk the ranking to the point
   where true FDP crosses 1%): a method with a better score recovers
   more real IDs at matched true FDP even if its reported q is equally
   calibrated.

**Pass 1 vs pass 2.** Osprey can emit the FDRBench input at either
pipeline point via `--fdrbench-pass <1|2|both>`.
Pass 1 = the full **pre-compaction** first-pass pool with first-pass q
(byte-equal to Rust `write_fdrbench_peptide_input`); pass 2 (default) =
the **post-compaction** reported set with final q; `both` emits both in
one run, suffixing the `--fdrbench` path with `.pass1` / `.pass2` so a
single run validates both passes. **Quote pass-2 for reported FDR** (it
is what the user sees). The p1->p2 delta is itself diagnostic:
library-supplied decoys *tighten* calibration from p1 to p2, generated
decoys *degrade* it.

### The `--model-diagnostics` report (in-process FDP + model views)

`--model-diagnostics` is the SELF-CONTAINED alternative to the FDRBench-jar
pipeline above: Osprey computes the entrapment FDP **in-process** (no jar, no
Python for the numbers) and writes ONE interactive HTML report (printable to
PDF) beside the run output. It carries the FDRBench-matching FDR-calibration
curve (both passes, experiment + per-run scope), the trained-model
feature-contribution table, composite + per-feature score distributions, the
paired decoy-win-fraction, and a per-file summary. Opt-in and off the default
output path -- production scoring output is byte-identical without it. Merged
in #4377.

**Generate + validate one dataset (the committed runner):**

```
# calibrated reference (no --protein-fdr):
bash ai/scripts/Osprey/ModelDiagnostics/Run-ModelDiagnostics.sh stellar
# dual model + inflated pass 2 (adds --protein-fdr 0.01, into a separate -pfdr dir):
bash ai/scripts/Osprey/ModelDiagnostics/Run-ModelDiagnostics.sh stellar pfdr
```

The runner clears the FDR-stage caches but KEEPS `*.scores.parquet`, so Osprey
resumes from the (expensive) per-file scoring checkpoint and only re-runs the
fast FDR / rescore / merge stages (~2 min Stellar; Astral re-scores under
`--resolution hram`, ~15-20 min). The report is emitted INSIDE those stages
(`FirstJoinTask` writes pass 1 + a data sidecar; `MergeNodeTask` appends pass 2
and re-renders) -- there is **no standalone "render the HTML from disk" path**,
and FirstPassFDR must actually RETRAIN (the runner clears the 1st-pass sidecars
to force it) or the model table + per-feature histograms are absent. The runner
then diffs the HTML pass-2 curve vs a stock-FDRBench run of the same TSV via
`Compare/Compare-Fdrbench-Html.py --pass <1|2>` (`RESULT: MATCH` at each gated q).

**Why `--protein-fdr` matters right now (the usual reason to ask for it).** It
fires a SECOND Percolator retrain on the post-reconciliation reported pool,
which does two visible things:
1. **Populates the Model tab's "1st pass / 2nd pass" selector.** Without
   `--protein-fdr` the run trains a single model, so there is no second model to
   compare and the selector does not appear. With it, you see how the retrained
   model reweights the features (e.g. Stellar SG-weighted cosine ~44% -> ~30%
   contribution) and can switch the composite + per-feature distributions
   between the two models.
2. **Shifts the pass-2 FDR upward**, because that retrain runs against a
   decoy-DEPLETED null -- the known anti-conservative source
   ([[project_osprey_pass2_recalibration_inflates_fdr]]). On Stellar libdecoy
   the pass-2 combined FDP goes ~0.90% (off) -> ~1.5% (on). Since #4390's
   best-of-runs q-clamp landed, `--protein-fdr` ALSO drops ~5% of reported IDs
   on standard runs -- the clamp removing exactly those pass-2 recalibration
   violators. So run WITHOUT it to reproduce the well-calibrated reference; run
   WITH it to demonstrate the dual model and the pass-2 recalibration story.

**Screenshots** (the browser extension can't screenshot `file://`): headless
Chrome via `ai/scripts/Osprey/ModelDiagnostics/Shot-ModelDiagnostics.py <html>
<outdir> <stem>` (it drives the tab / view / feature / pass clicks first). And
the standing gotcha: **NEVER run two Osprey processes at once** (SQLite /
parquet cache corruption) -- serialize dataset runs.

**Library-type behavior** (a quick robustness + degeneracy check): with **no
entrapment** (a plain target+decoy library) the report DROPS the
FDR-calibration tab and keeps the rest; with **Osprey-generated decoys**
(gendecoy) it loudly flags the anti-conservative decoys -- ~11-12% combined FDP
at a reported 1% q with the KPIs in red.

### Validated reference anchors (as of 2026-07-03)

Use these as regression anchors -- a change that moves them needs a
science explanation, not just a green build:

- **Library-supplied (Carafe) decoys are near-calibrated** at the
  reported pass-2 level: Stellar 0.82% (below the line), Astral 1.32%
  (just above). **Osprey-generated reverse decoys are severely
  anti-conservative**: Stellar 16.05%, Astral 12.19% true FDP at a
  claimed 1%. Confirmed on both instruments -- this is Mike's original
  motivation for library-supplied decoys, and the product guidance is
  to prefer them on entrapment libraries.
- **`--protein-fdr` is not reporting-only today**: it triggers the
  2nd-pass Percolator recalibration, which inflates Stellar
  library-decoy FDP from 0.92% (off) to 1.57% (on). Carrying the full
  1st-pass score->q null to Stage 7 and transferring q through it
  (TRIC-style) restores 0.86%.

### Caveats

- **Precursor-level only** so far. Peptide-level FDRBench has errored
  ("entrapment hits > k=1") on these libraries; get Mike's exact
  peptide-level invocation before trusting it.
- The oracle rests on entrapment assumptions: the entrapment sequences
  are truly absent from the sample, the 1:1 target:entrapment ratio,
  and FDRBench's own estimator. It is the best independent signal we
  have, not an absolute truth.
- **The committed driver is `ai/scripts/Osprey/Run-FdrBench.ps1`**
  (single-cell: Osprey run -> FDRBench jar -> metrics). It replaces the
  per-session bash scripts that used to live under `ai/.tmp/`
  (`run-cell.sh`, `run-fdrbench.sh`, `drive-all.sh`, `strip-decoys.sh`).
  Its `Get-FdrBenchCalibration` metric parser is validated against the
  recorded Stellar libdecoy pass-2 reference (28517 disc @ 1% q, 0.82%
  combined FDP, 30503 disc @ 1% true FDP). The **q-q calibration
  *plots*** (the zoomed 2x2 grid) still come from a Python helper
  (`plot-calibration.py`, matplotlib) that reads each cell's `fdp.csv`
  -- promote that too if plotting becomes routine; the numeric gate does
  not need it.

## HPC split CLI flags

Since the 2026-04-19 HPC split sprint, both tools expose CLI flags
that break the pipeline at Stage 4 / Stage 5 so workers can score in
parallel and a merge node runs FDR + .blib output:

The pipeline alternates per-file fan-out phases (Stages 1-4 scoring,
Stage 6 per-file rescore) with join phases (Stage 5 first-pass FDR
+ reconciliation planning, Stages 7-8 second-pass Percolator +
protein FDR + .blib). The CLI exposes two orthogonal axes: an
**entry-point selector** (`--join-at-pass=<N>`) and a **phase-shape
modifier** (`--no-join` runs only the per-file fan-out from the
entry; `--join-only` runs only the join from the entry).

| Flag | Behavior |
|---|---|
| `--no-join` (modifier) | Run only the per-file fan-out from the entry point. With `-i ...` (Stage 1 entry), runs Stages 1-4 — per-file `.scores.parquet` written next to each input mzML, no FDR, no blib. With `--join-at-pass=<N>`, runs only the per-file phase that follows that join (PR 2 wires this for `--join-at-pass=1`). |
| `--join-only` (modifier) | Run only the join phase at the entry point, stopping before the per-file fan-out that follows. Used when an HPC coordinator wants to ship plan files to N worker nodes. Requires `--join-at-pass=<N>`; not valid alone. (PR 2 wires this for `--join-at-pass=1`.) |
| `--join-at-pass=<N>` | Enter the pipeline at a specific join checkpoint, consuming per-file Parquet score files via `--input-scores`. `1` = post-Stage-4 (raw scoring) → run Stages 5-8. `2` = post-Stage-6 (reconciled scoring) → run Stages 7-8. Mutually exclusive with `--input`. |
| `--input-scores <PATH...>` | One or more `.scores.parquet` files (or a directory; non-recursive glob). Required when `--join-at-pass` is set. |
| `--parquet-compression {zstd,snappy}` | Write the scores Parquet with the requested codec. Rust default is `zstd`; use `snappy` when the output must be read back by Osprey (Parquet.Net 3.x on .NET Framework supports Snappy only). Production default stays Zstd; Snappy is a cross-impl interop affordance. |

Parquet interop gotchas:

- **Version lock**: the Parquet footer validator aborts on a `major.minor`
  mismatch between the writer's `osprey.version` and the reader's.
  Rust and Osprey must share the same `major.minor` for a
  cross-impl Parquet to round-trip. When Rust bumps to a new minor
  (e.g., `26.4.0`), bump Osprey's `Program.VERSION` in lockstep.
- **Path-dependent library hash**: `library_identity_hash` hashes
  `lib_path.display()` verbatim, so passing `/d/test/...` (Bash-style)
  hashes differently from `D:\test\...` (Windows-style) even when
  the file is the same. Invoke cross-impl parity runs via `pwsh`
  with Windows-native paths so the hash matches across tools.
- **Snappy disables dictionary encoding** in Rust (RLE_DICTIONARY
  isn't supported by Parquet.Net 3.x). Expect ~3x larger files on
  the Snappy path compared to the default Zstd.

## Environment variable reference

### Control / throttling

| Name | Purpose |
|---|---|
| `OSPREY_EXIT_AFTER_CALIBRATION` | Exit after Stage 3; skip main search |
| `OSPREY_LOAD_CALIBRATION` | Path to `.calibration.json` to load instead of running Stage 3 |
| `OSPREY_LOESS_CLASSICAL_ROBUST` | `1` = Cleveland (1979) robust LOESS; default matches Rust |
| `OSPREY_MAX_SCORING_WINDOWS` | Cap main-search windows for fast iteration under profilers |
| `OSPREY_TRACE_PEPTIDE` | Modified-sequence filter for the per-peptide diagnostic trace (`[trace]` log lines across Stages 3-7). Comma-separated for multiple. Paired decoys auto-matched. |

`OSPREY_EXIT_AFTER_SCORING` (retired 2026-04-19) was replaced by the
`--no-join` CLI flag; bench/profile scripts have migrated.

### Diagnostic dumps (cross-impl bisection)

Each dump has a `_DUMP` flag (write the file) and often an `_ONLY`
flag (exit after writing). Filenames begin with `cs_` on the C#
side and `rust_` on the Rust side.

| Name | Output | Use |
|---|---|---|
| `OSPREY_DUMP_CAL_SAMPLE` + `_SAMPLE_ONLY` | `*.cs_cal_sample.txt`, `cs_cal_scalars.txt`, `cs_cal_grid.txt` | Stage 2 calibration sample |
| `OSPREY_DUMP_CAL_WINDOWS` + `_WINDOWS_ONLY` | `cs_cal_windows.txt` | Per-entry cal window selection |
| `OSPREY_DUMP_CAL_PREFILTER` + `_PREFILTER_ONLY` | `cs_cal_prefilter.txt` *(Rust-only for now)* | Pre-filter candidates |
| `OSPREY_DUMP_CAL_MATCH` + `_MATCH_ONLY` | `cs_cal_match.txt` | Per-entry calibration match |
| `OSPREY_DUMP_LDA_SCORES` + `_SCORES_ONLY` | `cs_lda_scores.txt` | LDA discriminant + q-value |
| `OSPREY_DUMP_LOESS_INPUT` + `_INPUT_ONLY` | `cs_loess_input.txt` | LOESS input pairs |
| `OSPREY_DUMP_STANDARDIZER` + `_STANDARDIZER_ONLY` | `*_stage5_standardizer.tsv` | Per-feature mean/std from `FeatureStandardizer` (Stage 5 boundary) |
| `OSPREY_DUMP_SUBSAMPLE` + `_SUBSAMPLE_ONLY` | `*_stage5_subsample.tsv` | Stage 5 best-per-precursor subsample membership + fold assignment per entry |
| `OSPREY_DUMP_SVM_WEIGHTS` + `_SVM_WEIGHTS_ONLY` | `*_stage5_svm_weights.tsv` | Per-fold final SVM weights + bias + iteration count |
| `OSPREY_DUMP_PERCOLATOR` + `_PERCOLATOR_ONLY` | `*_stage5_percolator.tsv` | End-of-Stage-5 per-FdrEntry dump: score, pep, 4 q-values |
| `OSPREY_DIAG_XIC_ENTRY_ID` + `OSPREY_DIAG_XIC_PASS` | `cs_xic_entry_<ID>.txt` | Per-entry cal XIC (exits after dump) |
| `OSPREY_DIAG_SEARCH_ENTRY_IDS` | `cs_search_xic_entry_<ID>.txt` | Main-search XIC for specific entries (no exit) |
| `OSPREY_DIAG_MP_SCAN` | `cs_mp_diag.txt` | Median polish for a specific scan |
| `OSPREY_DIAG_XCORR_SCAN` | `cs_xcorr_scan.txt` *(Rust-only)* | XCorr detail at a specific scan |

Stage 5 dumps all land via `osprey-fdr/src/percolator.rs` (Rust) and
`pwiz.Osprey.FDR.PercolatorFdr` (C#); the end-of-stage
Percolator dump also uses the main-crate `osprey/src/diagnostics.rs`.
Floats route through `osprey_core::diagnostics::format_f64_roundtrip`
(normalizes `-0.0` to `0`, stable for `NaN`/`inf`).

The C# side consolidates cal-phase dumps in
`pwiz.Osprey.OspreyDiagnostics`; Stage 5 dumps are inlined in
`PercolatorFdr.cs` (the `Osprey.FDR` assembly cannot reference
main-crate helpers due to a circular-dep risk).

## Cross-impl bisection methodology

When the two tools diverge on a dataset, debug from the first
divergent stage downstream. **Do not start by comparing top-level
counts or summary statistics** -- they hide the structure of the
drift. Bisect stage-by-stage, prove each matches via `diff`, never
compare downstream values before upstream is proven identical.

### Bisection walk order

Walk the checkpoints in sequence; advance only after the previous
one matches:

**Stages 1-4 (calibration + scoring):**

1. **Calibration sample** (`OSPREY_DUMP_CAL_SAMPLE=1 + OSPREY_CAL_SAMPLE_ONLY=1`)
2. **Calibration match** (`OSPREY_DUMP_CAL_MATCH=1 + OSPREY_CAL_MATCH_ONLY=1`)
3. **LDA scores + q_values** (`OSPREY_DUMP_LDA_SCORES=1 + OSPREY_LDA_SCORES_ONLY=1`)
4. **LOESS input** (`OSPREY_DUMP_LOESS_INPUT=1 + OSPREY_LOESS_INPUT_ONLY=1`)
5. **Main-search XICs** (`OSPREY_DIAG_SEARCH_ENTRY_IDS=id1,id2,...`)
6. **21 PIN features** (via `Test-Features.ps1` — Stellar + Astral must pass at ULP)

**Stage 5 (Percolator FDR) via `--join-at-pass=1` on a canonical
Rust Parquet input** — the Stage 5 bisection uses the `OSPREY_DUMP_*`
dumps added by PR #18 (osprey) / the C# Osprey mirror PR:

7. **Feature standardizer** (`OSPREY_DUMP_STANDARDIZER=1 + OSPREY_STANDARDIZER_ONLY=1`)
   → per-feature mean + std. Divergence means feature extraction or
   standardizer math differs.
8. **Subsample + fold assignment** (`OSPREY_DUMP_SUBSAMPLE=1 + OSPREY_SUBSAMPLE_ONLY=1`)
   → per-entry `in_subsample` + `fold_id` + `native_position`.
   Divergence means input-array ordering or the stratified CV
   selection differs.
9. **Per-fold SVM weights** (`OSPREY_DUMP_SVM_WEIGHTS=1 + OSPREY_SVM_WEIGHTS_ONLY=1`)
   → 21 feature weights + bias per fold, plus iteration count. Isolates
   SVM training drift from Granholm calibration.
10. **End-of-Stage-5 Percolator** (`OSPREY_DUMP_PERCOLATOR=1 + OSPREY_PERCOLATOR_ONLY=1`)
    → per-FdrEntry `score, pep, run_precursor_q, run_peptide_q,
    experiment_precursor_q, experiment_peptide_q`. The acceptance
    gate. Compared via `ai/scripts/Osprey/Compare-Percolator.ps1`
    (hash-joins on `(file_name, entry_id)`, sort-order-agnostic —
    not the row-wise `diff` that `Compare-Diagnostic.ps1` uses).

Diff the SORTED output at each stage. Look for structural patterns
(all decoys? all short peptides? all charge-3?), not aggregate stats.

**Tool support**:

- `ai/scripts/Osprey/Compare-Diagnostic.ps1` — row-wise `diff`
  with context, drives Stages 1-4 dumps. Fails if the two tools
  render rows in different orders even when values match; invest in
  stable sort on both sides before diffing.
- `ai/scripts/Osprey/Compare-Percolator.ps1` — hash-joined
  per-column numeric compare with per-column thresholds; drives the
  Stage 5 Percolator dump. Extendable to other Stage 5+ dumps with
  `(file_name, entry_id)` keys.

### Numeric formatting is NOT just noise

.NET `F10` default rounds half-away-from-zero; Rust `{:.10}` rounds
half-to-even (banker's). A value like `0.15` can format differently.
Osprey's `OspreyDiagnostics.F10()` (C#) rounds half-to-even
before formatting to match Rust's `{:.10}`. The Rust diagnostics
side uses `{:.10}` directly.

**Cast `float` to `double` before F10 formatting** to defeat the
shortest-round-trip float formatter. When a "just formatting" drift
of 3e-15 appears on a LOESS input line, reproduce bit-identical
output by re-running through F10 before dismissing it. This
distinguishes true noise from a real algorithmic drift that happens
to round identically in 999 of 1000 cases.

## Parallel Rust + C# gotchas

Hard-won patterns from the Osprey port:

### Shared mutable state across parallel files

`OspreyConfig` is passed by reference to `ProcessFile`. Any mutation
during file processing leaks to sibling parallel files. Session 14
caught `config.FragmentTolerance = calibratedTolerance` overwriting
concurrently. Fix: `OspreyConfig.ShallowClone()` at the top of
`ProcessFile`. When Batch 2b brings parallel files to Rust, add
`OspreyConfig::clone()` with the same semantics.

Treat config as immutable post-entry. If you must adjust per-file,
clone first.

### f32 vs f64 in XCorr

`maccoss/osprey` stores f32 in the per-window `preprocessed_xcorr`
cache. Preprocessing runs in f64 internally; only the per-window
cache store narrows to f32. This halves the 100K-bin HRAM cache
memory without losing precision. C# mirrors via
`SpectralScorer.PreprocessSpectrumForXcorrInto(spec, scratch, float[]
output)`. Drift vs a pure-f64 cache is ~1e-7 absolute on xcorr score
(confirmed on Astral 945K entries).

Cross-language sqrt parity: `(intensity as f64).sqrt() as f32` in
Rust, `(float)Math.Sqrt((double)intensity)` in C#. Both go through
f64 sqrt then round to f32, avoiding double-rounding drift.

### Randomness

Never use unseeded randoms in the scoring pipeline. .NET's
`new Random()` defaults to `Environment.TickCount`; Rust defaults to
thread time. The calibration sampler uses seed 43 deliberately
(matches Rust's `42 + attempt=1` on first attempt). Always pass an
explicit seed.

**Custom `Xorshift64` PRNG**: both sides implement `Xorshift64`
(not stdlib `Random` / `thread_rng`) for fold-assignment shuffles
and SVM coordinate descent. `Osprey.ML.LinearSvmClassifier.cs`
has a unit test verifying byte-parity of the Rust and C# outputs at
`seed=42` (`MLTest.TestXorShiftMatchesRust`). Don't swap one side to
a different PRNG without the matching swap on the other.

### Determinism: sorted iteration + serial reduction

HashMap iteration in Rust is randomized per process; `.NET
Dictionary<,>` is insertion-ordered but not stable across logically
equivalent inserts. Any pipeline step that iterates a HashMap and
then feeds the output into a float accumulation has a per-process
drift risk that shows up as 1-ULP differences across runs.

Patterns the pipeline now relies on:

- **Sort the union of base_ids** before building competition
  winners in `compute_fdr_from_stubs` (`osprey-fdr/src/percolator.rs`).
  Don't iterate `targets.iter().chain(decoys.iter())` directly —
  that leaks HashMap order into `PepEstimator::fit_default`.
- **Serial `iter().fold()`** for the KDE `pdf` sum in
  `osprey-ml/src/pep.rs`. Rayon's `par_iter().sum()` is non-deterministic
  across calls; serial accumulation is left-to-right and
  deterministic for a fixed input (it is still order-dependent
  across different input permutations — same-input reproducibility is
  the invariant the downstream pipeline requires).
- **Deterministic tie-break** in `grid_search_c` (first-C wins on
  ties; matches the comment "first C as tiebreaker" that the Rust
  code didn't originally implement). `Iterator::max_by_key` returns
  the *last* tied element per stdlib docs — don't use it for
  tie-sensitive selection. Manual scan with strict `>` is what both
  tools now use.
- **Non-conservative FDR formula `n_decoy / n_target`** for
  internal grid-search counting in
  `count_passing_targets_svm` — matches `compute_qvalues` on the
  same path and `Osprey.FDR.PercolatorFdr.ComputeQvalues`. The
  conservative `(n_decoy + 1) / n_target` formula is reserved for
  final reported q-values (`ComputeConservativeQvalues`), not for
  hyperparameter-tuning heuristics.
- **`-0.0` normalized to `"0"`** in
  `osprey_core::diagnostics::format_f64_roundtrip`. Rust's default
  `{}` emits `-0` for `-0.0`; .NET's G17 emits `0`. Without
  normalization the two texts disagree even when the values are
  numerically equal. Route every float in a cross-impl dump
  through the shared formatter.

### Steel-thread parity doctrine

Cross-impl parity projects stall when a small bit-level gap blocks
the rest of the pipeline (a compression codec, a numerical
ordering, etc.). The working discipline, proven in Brendan's
K-score / Comet effort (Keller et al. 2006):

1. Establish bit-parity gates at every stage boundary (dumps + a
   compare script).
2. When a single stage won't close, add the **smallest possible
   switch** (env var, Cargo feature, or runtime flag) that lets the
   "non-default" side match the other for end-to-end testing. Keep
   the production default fast/correct.
3. Ship the switch as a **debt item** — always retire it by fixing
   the underlying gap, not by making it the default.

Active steel-thread switches:

- `--parquet-compression snappy` (Rust default Zstd; Snappy bridges
  to Osprey's Parquet.Net 3.x reader). Retires when Osprey
  grows Zstd support.

Historical (retired the same session they were introduced):

- `OSPREY_CSHARP_SCALAR_SVM` — was planned as a scalar-SVM shim;
  the root cause turned out to be a formula mismatch in
  `count_passing_targets_svm`, not the SVM math. Switch was removed
  before it landed upstream; see the TODO for the audit.

When proposing a new switch, ask: **is the underlying difference
worth fixing on one side instead?** If so, fix it and skip the
switch. The session where Stage 5 parity landed ended up replacing a
fully-drafted `OSPREY_CSHARP_SCALAR_SVM` switch with a 20-LOC fix in
`count_passing_targets_svm` once the switch had localized the gap.

### Stable vs unstable sort

Rust `slice::sort_by` is stable. .NET `Array.Sort` and
`List<T>.Sort` are introsort (unstable). When the C# comparator
can return 0 (a true tie), unstable reorder produces a different
output from the Rust stable sort on the same input — silent
cross-impl divergence the moment an actual tie shows up.

**Default for new sort sites**: use LINQ `OrderBy(...).ThenBy(...)`
in C# (stable). Matches Rust `sort_by` semantics without further
thought.

**Enforcement (Array.Sort only)**: `CodeInspectionTest.TestNoUnstableArraySort`
in `Osprey.Test/CodeInspectionTest.cs` scans production code
for `Array.Sort(` calls and fails the test unless an inline
`// Array.Sort OK: <reason>` comment is on the same line. New
`Array.Sort` uses MUST carry that exemption explaining why ties
cannot occur (typically: the comparator's key is unique per
element by construction, so 0 is unreachable). The test catches
new violations at PR time.

**Same rule applies to `List<T>.Sort` even though the regex
doesn't catch it**: when you write `someList.Sort(Comparison)`,
add the same `// Array.Sort OK: <reason>` inline comment when the
key is unique by construction. The tag is a convention — the
inspection just happens to not enforce it on `List<T>.Sort` yet.
If the comparator CAN return 0, switch to
`someList.OrderBy(...).ThenBy(...).ToList()` instead.

**Why this matters for parity, not just within-C# correctness**:
upstream arithmetic drift can mask the failure for a long time —
the sort never actually hits a tie because float noise breaks
every would-be equality. Once the upstream becomes bit-equal
cross-impl (the goal of every parity push), every previously-
hidden tie surfaces at once and the unstable sort is suddenly
the only thing standing between you and a clean gate.

### Explicit element types in tests

C# `var xs = new[] { 1, 2, 3 }` infers `int[]`, not `double[]`.
ReSharper's auto-fix to drop the explicit type broke
`MLTest.TestMatrixSlice` in Session 18 (integer inference mismatched
`double[]` on the comparison target). Keep `new double[] {...}` in
test assertions that compare against typed arrays. See STYLEGUIDE.md
"Array Literal Type Inference".

### Bug-class regression tests

Each time you close a cross-impl divergence, add a regression test
named after the bug class (e.g. `TestXcorrFragmentBinDedup`,
`TestPerFragmentDaTolerance`, `TestPercentileValueRounding`). Pattern:

1. Synthetic library + spectrum that triggers the bug
2. Expected output precomputed from a known bit-identical reference
3. Test passes iff output matches expected

Catches regressions during refactors months later.

## Performance patterns

### Allocation hotspots

On .NET Framework 4.7.2, the two worst hot-path patterns are:

1. **Per-call `double[NBins]`** for XCorr preprocessing (800 KB at
   HRAM NBins=100K hits LOH -> gen-2 pressure). Fixed by
   `XcorrScratchPool` at
   `pwiz_tools/Osprey/Osprey.Scoring/XcorrScratchPool.cs` --
   grows to NThreads sets, never shrinks, gen-2 holds the arrays.
2. **Per-candidate `bool[NBins]`** for fragment dedup (100 KB each).
   Fixed by `WindowXcorrCache.VisitedBins` with O(n_fragments)
   selective clear.

When `gen2_count` stays constant across a run, LOH churn is
eliminated. The `[MEM pre/post-main-search]` log line reports it.

Rust has Vec allocation instead of LOH but the pattern is the same.
Batch 2a of `TODO-OR-20260417_osprey_rust_upstream.md` brings the
pool + per-window cache pattern to Rust.

### Release vs debug

Both sides must run release mode for benchmarks. `cargo build
--release` and `Build-Osprey.ps1 -Configuration Release`. A
Debug C# build vs release Rust is 10x misleading.

### Server vs workstation GC

`Osprey.exe.config` sets `gcServer enabled="true"`. Without it
you lose 30-50% on parallel workloads. Confirm with `GC.IsServerGC`
or check the .config file.

### Profiling C# via dotTrace

`ProfilerHooks.cs` wraps `JetBrains.Profiler.Api.MeasureProfiler`.
Drive via:

```
pwsh -File ai/scripts/Osprey/Profile-Osprey.ps1 \
    -Dataset Astral -ScopeToMainSearch -MaxWindows 2 -TopN 30
```

`-MaxWindows N` sets `OSPREY_MAX_SCORING_WINDOWS=N` so profile cycle
time stays small (Astral ~15 min -> ~2 min with `-MaxWindows 2`).

Rust equivalent: `cargo flamegraph` or `perf record / perf report`
with `OSPREY_MAX_SCORING_WINDOWS` equally applicable.

## Validation before pushing to a PR

**Cross-impl parity tests are not gated by CI on either side.** The
`maccoss/osprey` GitHub Actions workflow runs only the basic unit
tests (`cargo fmt --check`, `cargo clippy -D warnings`, `cargo test`).
ProteoWizard/pwiz has **no CI applied at all** for Osprey.

The cross-impl harnesses (`Test-Features.ps1`,
`Compare-Stage5-AllFiles.ps1`, `Compare-Stage6-Planning.ps1`) are
the only thing that catches divergences between Rust and Osprey,
and they run only when a developer (or Claude) invokes them locally.
Treat them as *required* gates — not optional checks.

**Before opening or updating a PR**, run the parity harness for the
stage(s) the change touches. For Stage 4 / scoring changes, run
`Test-Features.ps1` on both Stellar and Astral. For Stage 5 / FDR
changes, add `Compare-Stage5-AllFiles.ps1`. For Stage 6 / consensus
+ reconciliation changes, add `Compare-Stage6-Planning.ps1`.

**Be especially careful with late changes** — every commit pushed
into an existing PR (e.g. addressing review feedback) needs the
appropriate harness re-run before merge. A real incident:
PR #4173 (Osprey Stage 6 planner) passed 9-of-9 dumps before
the Copilot review, then a "minor" follow-up commit (`f964cc45e`)
added a `cwtRows.Count == kvp.Value.Count` defensive guard from
Copilot's *first* of two suggested checks. The first was wrong
(post-compaction stubs are smaller than the parquet's raw Stage-4
rows by design); the second (`>= max ParquetIndex+1`) was correct.
Without re-running the Stage 6 harness on the post-review commit,
the regression slipped through merge and only surfaced when the
next sprint tried to start from a green baseline. Lesson: re-run
the harness after every push to an open PR, not just on the first
push.

The `Compare-*` harnesses are the project's substitute for CI; the
discipline that they get re-run is on us.

## Commit and PR conventions

**Follow the upstream convention** -- do NOT apply Skyline's 10-line
past-tense-title format to `maccoss/osprey` work. Look at recent
`maccoss/osprey` merge commits:

```bash
git log --oneline -20 --author="MacCoss"
git show <hash>
```

Differences from Skyline WORKFLOW.md:

- **No CRLF requirement.** Rust convention is LF. Do NOT run
  `fix-crlf.ps1` on the Rust working tree.
- **No `Co-Authored-By: Claude` trailer** unless Mike opts in.
- **Reasonable prose is fine.** The Skyline 10-line cap is a
  Skyline-team convention.
- **Cross-references** to related PRs are welcome
  (`Follow-up to #3`, `Relates to osprey#12`).

**PR creation**:

```bash
gh pr create --repo maccoss/osprey \
    --base main \
    --head diagnostics-extraction \
    --title "Add cross-implementation bisection diagnostics" \
    --body "$(cat <<'EOF'
## Summary
- ...
## Test plan
- [x] ...
EOF
)"
```

## Differences from Skyline's WORKFLOW.md

| Topic | Skyline default | Osprey Rust |
|---|---|---|
| Shell | `pwsh` required | Any shell; `cargo` is the tool |
| Build | MSBuild / quickbuild.bat | `cargo build --workspace` |
| Tests | `TestRunner.exe` + vstest.console.exe | `cargo test --workspace` |
| Static analysis | ReSharper / `jb inspectcode` | `cargo clippy -- -D warnings` |
| Code format | CRLF, space indent | LF, rustfmt defaults |
| Naming | `_camelCase` private, `PascalCase` types | snake_case everywhere |
| Commit title | Past tense, <=10 lines total | Upstream-style prose |
| Co-author trailer | `Co-Authored-By: Claude <noreply@anthropic.com>` | Only if maintainer opts in |
| PR target | `ProteoWizard/pwiz:master` | `maccoss/osprey:main` |
| Review gate | Brendan / Nick | Mike (maccoss) |
| Resource strings | Required for user text | N/A -- `log::info!` and CLI output are plain |

## Glossary

- **CWT** -- Continuous Wavelet Transform. A signal-processing technique
  for finding peaks in noisy 1-D data by convolving with wavelets
  (typically Mexican Hat / Ricker) at multiple scales. Osprey uses CWT
  for chromatographic peak detection: given an extracted ion chromatogram
  (XIC) -- intensity vs RT for one fragment -- CWT returns a list of peak
  candidates with start / apex / end indices. The `cwt_consensus_peaks`
  function in Rust and `CwtPeakDetector.DetectConsensusPeaks` in C# are
  the entry points; both produce the `CwtCandidate` records that Stage 6
  reconciliation reads to choose alternate peak boundaries.
- **ULP** -- Unit in the Last Place. The gap between two adjacent
  representable f64 values at a given magnitude. Around 0.1, ULP is
  about 1.4e-17; around 1000, about 1.1e-13. "1-ULP difference" means
  two doubles' bit patterns differ by exactly 1 (the smallest possible
  non-zero difference at that precision). The natural unit for measuring
  cross-impl numeric closeness: 0 ULP = bit-identical, 1 ULP = one
  rounding step apart, etc. Distinct from the `Test-Features.ps1`
  absolute-tolerance gate of 1e-6 -- a value can be within 1e-6 yet
  hundreds of ULPs apart in the high-precision range, or bit-identical
  yet drift to 1 ULP if a downstream `min` or `max` chooses differently.

## Critical rules

- **Byte-identical dump preservation** when touching diagnostic
  code. Cross-impl bisection depends on it. `diff` before/after
  every dump extraction.
- **`cargo clippy -- -D warnings`** must pass before pushing.
- **Parity gate after any scoring/calibration change**: Stellar +
  Astral `Test-Features.ps1` at ULP.

## See also

- `C:\proj\osprey\CLAUDE.md` -- project overview (architecture, CI,
  critical invariants). Read this first when joining the Rust side.
- `ai/WORKFLOW.md` -- Skyline-mainline conventions (different
  product, different rules)
- `ai/docs/debugging-principles.md` -- "Cross-implementation
  bisection" section (generic protocol; this guide is the
  dataset-specific workflow)
- `ai/todos/active/TODO-OR-20260417_osprey_rust_upstream.md` --
  staged sprint to upstream diagnostics + perf to `maccoss/osprey`
- `ai/todos/active/TODO-20260423_osprey_sharp.md` -- Osprey
  Phase 4 sprint (Stages 6-8 cross-impl parity walk). Bisection
  methodology + Stage 5 resolution documented in
  `ai/todos/completed/TODO-20260422_ospreysharp_stage5_diagnostics.md`.
- `ai/scripts/Osprey/` -- cross-impl test tooling (C# side):
  `Test-Features.ps1` (Stages 1-4 parity), `Compare-Diagnostic.ps1`
  (row-wise dump diff), `Compare-Percolator.ps1` (hash-joined
  Stage 5 compare), `Bench-Scoring.ps1` (perf),
  `Profile-Osprey.ps1` (C# profiling),
  `Run-FdrBench.ps1` (FDRBench entrapment-calibration driver)
- `pwiz_tools/Osprey/Osprey/OspreyDiagnostics.cs` --
  C# diagnostic constants + cal-phase dump methods
- `pwiz_tools/Osprey/Osprey.FDR/PercolatorFdr.cs` -- C#
  Stage 5 implementation with the four inlined dumps
- `pwiz_tools/Osprey/Osprey.Scoring/XcorrScratchPool.cs`
  -- per-window buffer reuse pattern Batch 2a will mirror
