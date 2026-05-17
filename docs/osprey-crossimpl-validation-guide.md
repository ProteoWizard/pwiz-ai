# Osprey Cross-Implementation Validation Guide

Catalog of the Rust ↔ OspreySharp (C#) parity-testing tooling under
`ai/scripts/OspreySharp/`, plus the standard flow for running it.

This guide is **the inventory**. For the conceptual foundation — env var
reference, HPC split CLI flags (`--join-at-pass`, `--no-join`,
`--join-only`), and the bisection walk order itself — see
[`osprey-development-guide.md`](osprey-development-guide.md), specifically:

- _HPC split CLI flags_ — the `--join-at-pass=N` / `--no-join` /
  `--join-only` axes and parquet-interop gotchas.
- _Environment variable reference_ — control flags and `OSPREY_DUMP_*`
  diagnostic-dump catalog.
- _Cross-impl bisection methodology_ — Stages 1–4 checkpoints, Stage 5
  `OSPREY_DUMP_*` sequence, numeric-formatting gotchas, and why
  sort-order-sensitive diffs are dangerous.

The scripts catalogued below automate each checkpoint in that bisection.

## Script categories

The OspreySharp script directory has three flavors of tool:

- **Validation gates** (`Compare-*.ps1`) — binary pass/fail per stage or
  per dump. Used as both bisection probes and CI-style gates during a port.
- **Regression harnesses** (`Test-*.ps1`) — multi-stage walks that build
  both implementations, capture dumps, run the gate sequence, and either
  freeze outputs as inputs for the next stage or compare against a snapshot.
- **Measurement** (`Bench-*.ps1`, `Profile-*.ps1`) — timing and memory
  profiles, not parity checks.
- **Helpers** (`Diff-Parquet.ps1`, `Dataset-Config.ps1`, the two `.py`
  files, `Generate-AllScoresParquet.ps1`) — primitives the gates and
  harnesses share.

## Standard flow

1. **Build both implementations.** Rust via
   [`Build-OspreyRust.ps1`](../scripts/OspreySharp/Build-OspreyRust.ps1);
   C# via [`Build-OspreySharp.ps1`](../scripts/OspreySharp/Build-OspreySharp.ps1).
   Profile output paths in `Compare-*` scripts assume the release builds at
   their default locations (sibling `osprey/target/release/osprey.exe` and
   the OspreySharp solution output).
2. **Generate parquet inputs** for the stage under test via
   `Generate-AllScoresParquet.ps1` (Stage 1–4 fan-out exit) or by running
   the upstream regression script that froze them.
3. **Run the appropriate Compare-\*** script. Each prints PASS/FAIL and
   the first divergence line.
4. **On failure, bisect**. The script's PARAMETER and EXAMPLE blocks in
   its header are authoritative for env-var setup. If the bisection
   methodology section in `osprey-development-guide.md` is unfamiliar,
   read that first — the comparison scripts assume you know the
   checkpoint sequence.

## Validation gates by stage

### Stages 1–4 (calibration + scoring fan-out)

| Script | What it gates | Pass criterion |
|--------|---------------|----------------|
| `Compare-Diagnostic.ps1` | Per-stage calibration dump (`CalSample`, `CalWindows`, `CalMatch`, `LdaScores`, `LoessInput`) | Line-wise diff match. Sort-order-sensitive — use only for stages that emit deterministic order. |
| `Compare-Baseline.ps1` | End-to-end SHA-256 parity between Rust `osprey:main` and a local feature branch (Rust↔Rust, not cross-impl) | All `.scores.parquet` SHA-256-equal. |
| `Diff-Parquet.ps1` | Single parquet pair or two directories of parquets — column-level content diff | Every non-allowlisted column matches within numeric tolerance (default `1e-6`). |

### Stage 5 (first-pass FDR / Percolator)

| Script | What it gates | Pass criterion |
|--------|---------------|----------------|
| `Compare-Stage5-AllFiles.ps1` | Per-file Stage 5 byte parity across the whole dataset (Standardizer, Subsample, SVM weights, Percolator dumps) | SHA-256 equality of all four dump pairs per file. |
| `Compare-Stage5-Boundary.ps1` | Stage 5 → Stage 6 sidecar parity (`.1st-pass.fdr_scores.bin`, `.reconciliation.json`) | SHA-256 equality of both sidecars per file. |
| `Compare-Percolator.ps1` | Stage 5 Percolator TSV dumps, sort-order-agnostic | Per-column `max_abs_diff` ≤ threshold (default `1e-9`); row-set match on `(file_name, entry_id)`. |

### Stage 6 (reconciliation + rescore)

| Script | What it gates | Pass criterion |
|--------|---------------|----------------|
| `Compare-Stage6-Planning.ps1` | Stage 6 planning-checkpoint dumps (`OSPREY_DUMP_CONSENSUS`, `OSPREY_DUMP_MULTICHARGE`, `OSPREY_DUMP_REFIT`) | SHA-256 equality of all three dump pairs. |
| `Compare-Stage6-Crossimpl.ps1` | Per-iteration Stage 6 worker (`--join-at-pass=1 --no-join`) from a frozen Stage 4 + Stage 5 fixture | `Compare-Percolator.ps1` threshold + post-hydration q-value row-set match. |
| `Compare-Stage6-Worker.ps1` | Worker portability — in-process Stage 6 output vs rehydrated output from renamed working directory | SHA-256 equality of reconciled `.scores.parquet` between Phase A baseline and Phase C renamed-folder run. |

### Stage 7 (protein FDR)

| Script | What it gates | Pass criterion |
|--------|---------------|----------------|
| `Compare-Stage7-Crossimpl.ps1` | Stage 7 protein-FDR TSV dumps (`OSPREY_DUMP_STAGE7_PROTEIN_FDR`), format-tolerant | Per-column `max_abs_diff` ≤ threshold (default `1e-9`); row-set match on `accessions` key. |
| `Compare-Stage7-Rehydration.ps1` | Rust↔Rust bit parity for `--join-at-pass=2` rehydration (reference straight-through vs test rehydrated) | SHA-256 equality of Stage 7 protein-FDR TSV. Gates the rehydration wiring, not the C# port. |

## Regression harnesses

| Script | When to use |
|--------|-------------|
| `Test-Regression.ps1` | Full five-stage walk: build both, isolated dumps + comparisons per stage, freeze each stage as input to the next. Exit 0 only if every stage passes. The "is this branch clean?" command. |
| `Test-Snapshot.ps1` | Same-impl regression against a frozen snapshot baseline. Two modes: compare (fail on mismatch) or `-CreateSnapshot` to capture a new baseline. Used during the OspreySharp pipeline-task rearchitecture where Rust output is the moving target. |
| `Test-Features.ps1` | Single-file Stage 1–4 feature-parity quick check. Compares all 21 PIN features at default `1e-6`; reports wall-clock timings. Stellar ~2 min, Astral ~18 min — fastest gate during active debugging. |

## Measurement tools

| Script | Output |
|--------|--------|
| `Bench-Scoring.ps1` | Ground-truth Stage 1–4 benchmark — median timing + peak RSS across Rust upstream, fork Rust, and OspreySharp. Optional `-BaselineBin -BaselineLabel` for A/B. |
| `Profile-OspreySharp.ps1` | OspreySharp profile via dotTrace CLI. Captures `.dtp` snapshot, generates XML report, prints top hot spots by own/total time. Stage gates: Calibration (1–3), Scoring (1–4), or Full. |

## Helpers (used by the gates above)

| File | Role |
|------|------|
| `Dataset-Config.ps1` | `Get-DatasetConfig` returns dataset hashtables (paths, library, resolution, file lists, decoy mode) for Stellar / Astral / AstralLibraryDecoy. All gates dot-source this. |
| `Generate-AllScoresParquet.ps1` | Per-file `.scores.rust.parquet` + `.scores.cs.parquet` for every mzML in a dataset via `--no-join` (Stage 4 exit). Prerequisite for the Stage 5+ gates. |
| `Diff-Parquet.ps1` | Column-level parquet content diff. Used standalone for ad-hoc checks and called by the heavier gates. |
| `parquet_diff.py` | Row-by-row parquet comparator (sorts on `entry_id`); per-column `[OK]`/`[DIFF]` at configurable tolerance. Promoted out of `ai/.tmp` once it stabilized. |
| `inspect_parquet.py` | Read-only parquet reporter — row count, schema, CWT-candidates population fraction, optional row sampling. Use `-e` flag to exit nonzero if CWT < 50%. |

## Picking the right tool

| You want to… | Use |
|---|---|
| Confirm a branch is clean end-to-end | `Test-Regression.ps1` |
| Quickly check Stage 1–4 features after a code change | `Test-Features.ps1` |
| Confirm Stage 5 didn't drift | `Compare-Stage5-AllFiles.ps1` |
| Confirm Stage 6 didn't drift | `Compare-Stage6-Crossimpl.ps1` |
| Bisect a single divergent feature | `Compare-Diagnostic.ps1` (Stages 1–4), then `Compare-Percolator.ps1` (Stage 5), then a `Compare-Stage6-*` script |
| Detect a parquet column drift (any stage) | `Diff-Parquet.ps1` directly |
| Tune perf, not parity | `Bench-Scoring.ps1` for timing, `Profile-OspreySharp.ps1` for hot spots |
| Capture a snapshot of current output to gate future changes | `Test-Snapshot.ps1 -CreateSnapshot` |

## Skill integration

The `osprey-development` skill auto-loads when working on Rust osprey
(`maccoss/osprey`), OspreySharp, or cross-impl divergence. It pulls in
[`osprey-development-guide.md`](osprey-development-guide.md); this guide
is the operational companion to that conceptual reference.
