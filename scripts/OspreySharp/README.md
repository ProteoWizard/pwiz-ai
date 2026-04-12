# OspreySharp Build and Test Scripts

Scripts for building, testing, and running OspreySharp (C#) and Osprey (Rust)
in the cross-implementation bisection workflow.

## Scripts

### Build-OspreySharp.ps1

Build the C# OspreySharp solution and optionally run unit tests.

```bash
# Build (Release, all projects)
pwsh -File './ai/scripts/OspreySharp/Build-OspreySharp.ps1'

# Build + run all 167 unit tests
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

### Run-Stellar.ps1

Run either tool on the Stellar test dataset with common flags.
Always applies `--resolution unit` (required for Stellar data).

```bash
# Run C# on single file (file 20)
pwsh -File './ai/scripts/OspreySharp/Run-Stellar.ps1'

# Run Rust on single file, clean caches first
pwsh -File './ai/scripts/OspreySharp/Run-Stellar.ps1' -Tool Rust -Clean

# Run C# on all 3 files with feature dump
pwsh -File './ai/scripts/OspreySharp/Run-Stellar.ps1' -Files All -Clean -WritePin

# Run with search XIC diagnostic for specific entries
pwsh -File './ai/scripts/OspreySharp/Run-Stellar.ps1' -DiagEntryIds "0,1080,5765,28988"

# Run both tools with diagnostic (two calls)
pwsh -File './ai/scripts/OspreySharp/Run-Stellar.ps1' -Tool Rust -Clean -DiagEntryIds "0,1080"
pwsh -File './ai/scripts/OspreySharp/Run-Stellar.ps1' -Tool CSharp -DiagEntryIds "0,1080"

# Run Rust with cal_match dump and exit
pwsh -File './ai/scripts/OspreySharp/Run-Stellar.ps1' -Tool Rust -DiagCalMatch -DiagCalMatchOnly
```

### Clean-TestData.ps1

Clean cached and diagnostic files from the test data directory.

```bash
# Clean everything (caches + diagnostics)
pwsh -File './ai/scripts/OspreySharp/Clean-TestData.ps1'

# Clean only diagnostic dump files
pwsh -File './ai/scripts/OspreySharp/Clean-TestData.ps1' -DiagOnly
```

## Test data

Stellar test data lives at `D:\test\osprey-runs\stellar\`:
- 3 mzML files (files 20-22)
- DIA-NN TSV spectral library

Source files at `D:\test\osprey-testfiles\stellar\`.

**CRITICAL**: Always use `--resolution unit` for Stellar data. Without this
flag, the tool uses Auto resolution detection which produces ~37x fewer results.
