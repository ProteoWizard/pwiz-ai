# OspreySharp Build and Test Scripts

Scripts for building, testing, benchmarking, and running OspreySharp (C#)
and Osprey (Rust) in the cross-implementation bisection workflow.

All scripts support `-Dataset Stellar` (default) or `-Dataset Astral`.
Dataset-specific settings (library, resolution, file names) are defined
in `Dataset-Config.ps1`.

## Scripts

### Build-OspreySharp.ps1

Build the C# OspreySharp solution and optionally run unit tests.

```bash
# Build (Release, all projects)
pwsh -File './ai/scripts/OspreySharp/Build-OspreySharp.ps1'

# Build + run all unit tests
pwsh -File './ai/scripts/OspreySharp/Build-OspreySharp.ps1' -RunTests

# Build + run specific test
pwsh -File './ai/scripts/OspreySharp/Build-OspreySharp.ps1' -RunTests -TestName TestXcorrPerfectMatch

# Debug build with summary output
pwsh -File './ai/scripts/OspreySharp/Build-OspreySharp.ps1' -Configuration Debug -Summary
```

### Build-OspreyRust.ps1

Build the Rust Osprey reference binary from `C:\proj\osprey`.

```bash
# Build release
pwsh -File './ai/scripts/OspreySharp/Build-OspreyRust.ps1'

# Format + build + lint
pwsh -File './ai/scripts/OspreySharp/Build-OspreyRust.ps1' -Fmt -Clippy
```

### Run-Osprey.ps1

Run either tool on a test dataset. Applies dataset-specific resolution
and library automatically.

```bash
# Run C# on Stellar single file (default)
pwsh -File './ai/scripts/OspreySharp/Run-Osprey.ps1'

# Run Rust on Astral single file, clean caches first
pwsh -File './ai/scripts/OspreySharp/Run-Osprey.ps1' -Dataset Astral -Tool Rust -Clean

# Run C# on all 3 Stellar files with feature dump
pwsh -File './ai/scripts/OspreySharp/Run-Osprey.ps1' -Files All -Clean -WritePin

# Run with search XIC diagnostic for specific entries
pwsh -File './ai/scripts/OspreySharp/Run-Osprey.ps1' -DiagEntryIds "0,1080,5765,28988"

# Run both tools with diagnostic (two calls)
pwsh -File './ai/scripts/OspreySharp/Run-Osprey.ps1' -Tool Rust -Clean -DiagEntryIds "0,1080"
pwsh -File './ai/scripts/OspreySharp/Run-Osprey.ps1' -Tool CSharp -DiagEntryIds "0,1080"

# Run Rust with cal_match dump and exit
pwsh -File './ai/scripts/OspreySharp/Run-Osprey.ps1' -Tool Rust -DiagCalMatch -DiagCalMatchOnly
```

### Test-Features.ps1

Automated 21-feature cross-implementation comparison. Runs Rust (produces
calibration + PIN), then C# with shared calibration, then compares all 21
PIN features via awk join.

```bash
# Stellar comparison (default)
pwsh -File './ai/scripts/OspreySharp/Test-Features.ps1'

# Astral comparison
pwsh -File './ai/scripts/OspreySharp/Test-Features.ps1' -Dataset Astral

# Skip Rust (reuse existing output for faster C# iteration)
pwsh -File './ai/scripts/OspreySharp/Test-Features.ps1' -SkipRust
```

### Bench-Scoring.ps1

Performance benchmark comparing Rust and C# on Stages 1-4. Supports
single-file (per-stage breakdown) and multi-file (wall-clock only) modes.

```bash
# Single file, Stellar (default)
pwsh -File './ai/scripts/OspreySharp/Bench-Scoring.ps1' -SkipUpstream -Iterations 2

# All 3 files (C# parallel vs Rust sequential)
pwsh -File './ai/scripts/OspreySharp/Bench-Scoring.ps1' -Files All -SkipUpstream -Iterations 2

# Astral single file benchmark
pwsh -File './ai/scripts/OspreySharp/Bench-Scoring.ps1' -Dataset Astral -SkipUpstream -Iterations 2
```

### Profile-OspreySharp.ps1

dotTrace profiling of OspreySharp for performance optimization.

### Clean-TestData.ps1

Clean cached and diagnostic files from the test data directory.

```bash
# Clean everything (caches + diagnostics)
pwsh -File './ai/scripts/OspreySharp/Clean-TestData.ps1'

# Clean only diagnostic dump files
pwsh -File './ai/scripts/OspreySharp/Clean-TestData.ps1' -DiagOnly
```

## Test Data

| Dataset | Directory | Library | Resolution | Files |
|---------|-----------|---------|------------|-------|
| Stellar | `D:\test\osprey-runs\stellar\` | `hela-filtered-SkylineAI_spectral_library.tsv` | `unit` | 20, 21, 22 |
| Astral  | `D:\test\osprey-runs\astral\`  | `SkylineAI_spectral_library.tsv` | `hram` | 49, 55, 60 |

Source files at `D:\test\osprey-testfiles\{stellar,astral}\`.

**CRITICAL**: Always use the correct `--resolution` flag per dataset.
Stellar requires `unit`; Astral requires `hram`. The scripts handle
this automatically via `Dataset-Config.ps1`.
