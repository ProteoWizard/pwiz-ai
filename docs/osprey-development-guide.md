# Osprey (Rust) Development Guide

Development conventions for work on the `maccoss/osprey` Rust
project. Referenced by `TODO-OR-*.md` files, which may have workflow
rules that differ from the Skyline-mainline conventions documented
in `ai/WORKFLOW.md`.

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

## Repositories

| Path | Remote | Purpose |
|---|---|---|
| `C:\proj\osprey-upstream` *(create when needed)* | `maccoss/osprey` | Primary working tree for new PRs. Brendan has push access (collaborator). |
| `C:\proj\osprey-mm` | `maccoss/osprey` | Read-only clone of upstream `main`. Used as Rust baseline in `Bench-Scoring.ps1`. |
| `C:\proj\osprey` | `brendanx67/osprey` | **Historical fork.** Branches (`fix/parquet-index-lookup`, `coelution-search`, etc.) preserved as archive. Do not extend. |

New work goes to branches on `maccoss/osprey` directly, never to
the fork. Push directly; create PR with
`gh pr create --repo maccoss/osprey`.

## Build and test commands

```bash
# Full workspace build
cargo build --workspace --release

# Run all tests (including inline #[cfg(test)] modules)
cargo test --workspace

# Lint (Rust equivalent of ReSharper inspection)
cargo clippy --workspace -- -D warnings

# Format check
cargo fmt --all -- --check

# Build + test a single crate
cargo test -p osprey-scoring
```

The project targets **Rust 1.75+** (see `Cargo.toml` workspace
`rust-version`). Check `rustup show` if you get compile errors
that look toolchain-related.

## Test data locations

Not committed to the repo; lives on the developer workstation:

- `D:\test\osprey-runs\stellar\` -- small Stellar DIA dataset
  (3 mzML files, ~1 GB each)
- `D:\test\osprey-runs\astral\` -- larger Astral HRAM dataset
  (3 mzML files, ~5-10 GB each)

Both have `.blib` or `.tsv` spectral libraries alongside the mzML.
Dataset-specific configuration lives in
`ai/scripts/OspreySharp/Dataset-Config.ps1`.

## Cross-implementation parity testing

The cross-impl bisection infrastructure lives on the C# side (under
`ai/scripts/OspreySharp/`) but drives both tools:

```
# Stellar parity (fast, ~2 min)
pwsh -File ./ai/scripts/OspreySharp/Test-Features.ps1 -Dataset Stellar

# Astral parity (slow, ~18 min)
pwsh -File ./ai/scripts/OspreySharp/Test-Features.ps1 -Dataset Astral

# Re-use existing Rust output (skip the ~16 min Rust run)
pwsh -File ./ai/scripts/OspreySharp/Test-Features.ps1 -Dataset Astral -SkipRust
```

All 21 PIN features must remain bit-identical at the `1E-06`
threshold. Run this gate after every Rust change that could affect
scoring or calibration.

**Perf benchmark**:

```
pwsh -File ./ai/scripts/OspreySharp/Bench-Scoring.ps1 -Dataset Stellar -Files Single -Iterations 3
```

Compares upstream Rust (`osprey-mm`), our fork Rust (`osprey`), and
OspreySharp. Use `-SkipUpstream` to skip the upstream Rust run when
not needed.

## Environment variable reference

### Control / throttling

| Name | Purpose |
|---|---|
| `OSPREY_EXIT_AFTER_CALIBRATION` | Exit after Stage 3 (calibration done); skip main search |
| `OSPREY_EXIT_AFTER_SCORING` | Exit after Stage 4 (main search done); skip FDR + blib |
| `OSPREY_LOAD_CALIBRATION` | Path to `.calibration.json` to load instead of running Stage 3 (bisection) |
| `OSPREY_LOESS_CLASSICAL_ROBUST` | `1` = use Cleveland (1979) robust LOESS; default matches Rust calibration_ml.rs |
| `OSPREY_MAX_SCORING_WINDOWS` | Cap main-search windows for fast iteration under profilers |

### Diagnostic dumps (cross-impl bisection)

Each dump has a `_DUMP` flag (write the file) and often an `_ONLY`
flag (exit after writing). Filenames begin with `cs_` on the C#
side and `rust_` on the Rust side (when the reference tool writes
them).

| Name | Output | Use |
|---|---|---|
| `OSPREY_DUMP_CAL_SAMPLE` + `_SAMPLE_ONLY` | `*.cs_cal_sample.txt`, `cs_cal_scalars.txt`, `cs_cal_grid.txt` | Stage 2 calibration sample |
| `OSPREY_DUMP_CAL_WINDOWS` + `_WINDOWS_ONLY` | `cs_cal_windows.txt` | Per-entry cal window selection |
| `OSPREY_DUMP_CAL_PREFILTER` + `_PREFILTER_ONLY` | `cs_cal_prefilter.txt` *(Rust-only for now)* | Pre-filter candidates |
| `OSPREY_DUMP_CAL_MATCH` + `_MATCH_ONLY` | `cs_cal_match.txt` | Per-entry calibration match |
| `OSPREY_DUMP_LDA_SCORES` + `_SCORES_ONLY` | `cs_lda_scores.txt` | LDA discriminant + q-value |
| `OSPREY_DUMP_LOESS_INPUT` + `_INPUT_ONLY` | `cs_loess_input.txt` | LOESS input pairs |
| `OSPREY_DIAG_XIC_ENTRY_ID` + `OSPREY_DIAG_XIC_PASS` | `cs_xic_entry_<ID>.txt` | Per-entry calibration XIC (exits after dump) |
| `OSPREY_DIAG_SEARCH_ENTRY_IDS` | `cs_search_xic_entry_<ID>.txt` | Main-search XIC for specific entries (does NOT exit) |
| `OSPREY_DIAG_MP_SCAN` | `cs_mp_diag.txt` | Median polish for a specific scan |
| `OSPREY_DIAG_XCORR_SCAN` | `cs_xcorr_scan.txt` *(Rust-only)* | XCorr detail at a specific scan |

The C# side consolidates these in `pwiz.OspreySharp.OspreyDiagnostics`
(Session 18, 2026-04-17). The Rust equivalent is deferred to
`TODO-OR-20260417_osprey_rust_upstream.md` Batch 1.

## Commit and PR conventions

**Follow the upstream convention** -- do NOT apply Skyline's 10-line
past-tense-title format to `maccoss/osprey` work. Look at recent
`maccoss/osprey` merge commits for style:

```bash
git log --oneline -20 --author="MacCoss"
git show <hash>  # see full message style
```

Key differences from Skyline WORKFLOW.md:

- **No CRLF requirement.** Rust convention is LF on all files.
  Do NOT run `fix-crlf.ps1` on the Rust working tree.
- **No `Co-Authored-By: Claude` trailer** unless Mike explicitly
  opts in. When in doubt, omit.
- **Reasonable prose is fine.** Upstream reviewers read longer
  messages; the Skyline 10-line cap is a Skyline-team convention.
- **Cross-references** to related PRs or issues are welcome
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

## Critical rules (Rust-specific)

- **Byte-identical dump preservation** is non-negotiable when
  touching diagnostic code. Cross-impl bisection against OspreySharp
  depends on it. Run `diff` before/after every dump extraction.
- **`cargo clippy -- -D warnings`** must pass before pushing. The
  project has no tolerance for clippy warnings on `main`.
- **Parity gate after any scoring/calibration change**: Stellar +
  Astral `Test-Features.ps1` at ULP.

## See also

- `ai/WORKFLOW.md` -- Skyline-mainline conventions (different
  product, different rules)
- `ai/todos/active/TODO-OR-20260417_osprey_rust_upstream.md` --
  staged sprint to upstream diagnostics + perf
- `ai/scripts/OspreySharp/` -- cross-impl test tooling (C# side)
- `pwiz_tools/OspreySharp/OspreySharp/OspreyDiagnostics.cs` --
  C# reference implementation for diagnostic extraction
