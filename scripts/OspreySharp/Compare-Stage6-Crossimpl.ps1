<#
.SYNOPSIS
    Per-iteration cross-impl Stage 6 worker (--join-at-pass=1 --no-join)
    byte-parity gate. Operates against a frozen fixture built once by
    Build-Stage6Fixture.ps1.

.DESCRIPTION
    Companion to:
      - Build-Stage6Fixture.ps1            (one-time fixture build)
      - Compare-Stage5-AllFiles.ps1        (Rust v C# in-process Stage 5)
      - Compare-Stage6-Planning.ps1        (Rust v C# in-process Stage 6 planning)
      - Compare-Stage6-Worker.ps1          (Rust-only portability gate)
      - Compare-Percolator.ps1             (Stage 5 Percolator dump diff)

    This script is the FAST iteration loop for Stage 6 development.
    Build-Stage6Fixture.ps1 produces a frozen test fixture once: Stage
    1-4 Snappy parquets + verified-identical Stage 5 sidecars + spectra
    cache + library. Every Stage 6 code change re-runs this script,
    which copies the fixture into a fresh per-iteration workdir and
    runs only --join-at-pass=1 --no-join on each binary against
    byte-identical inputs.

    Per-iteration flow:

      Stage A — Materialize workdir
        Copy <testDir>/_stage6_fixture/<dataset>/ to a fresh
        <testDir>/_stage6_iter/<dataset>_<tool>/ for each tool. Each
        tool gets its own private workdir so output writes don't
        collide.

      Stage B — Run Rust worker
        osprey --join-at-pass=1 --no-join from the Rust workdir, with
        OSPREY_DUMP_PERCOLATOR=1. Captures rust_stage5_percolator.tsv
        plus (when Phases 2+3 of the C# port land) reconciled
        .scores.parquet output.

      Stage C — Run C# worker
        OspreySharp.exe with the same flags + env from the C# workdir.

      Stage D — Compare
        Hand off to Compare-Percolator.ps1 for the post-hydration
        per-precursor q-value / score / PEP diff. PASS iff every
        numeric column is within its threshold and the (file_name,
        entry_id) row sets match.

    Future extensions (post-Phase 3 parquet write-back):
      - Add a parquet content-diff phase after Compare-Percolator
        passes, to validate end-of-Stage-6 reconciled .scores.parquet
        byte parity.

    Per-iteration runtime: ~30s on Stellar (no Stage 5 work, just
    Stage 6 hydrate + compact + rescore). Stage 5 boundary parity is
    locked when Build-Stage6Fixture.ps1 succeeds, so we don't pay for
    it on every Stage 6 iteration.

.PARAMETER Dataset
    Stellar | Astral | Both (default Stellar). The fixture for the
    requested dataset must already exist (run Build-Stage6Fixture.ps1
    first).

.PARAMETER TestBaseDir
    Override test data root.

.PARAMETER CsharpRoot
    pwiz worktree with built OspreySharp.exe. Auto-detect if omitted.

.PARAMETER TargetFramework
    net472 or net8.0 (default net8.0).

.PARAMETER Threads
    --threads value passed to osprey (default 16). Held constant
    across both binaries.

.EXAMPLE
    # Tight per-iteration loop after a C# Stage 6 code change.
    .\Compare-Stage6-Crossimpl.ps1 -Dataset Stellar
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("Stellar", "Astral", "Both")]
    [string]$Dataset = "Stellar",

    [string]$TestBaseDir = $null,

    [string]$CsharpRoot = $null,

    [ValidateSet("net472", "net8.0")]
    [string]$TargetFramework = "net8.0",

    [int]$Threads = 16,

    # On-demand bisection: enable OSPREY_DUMP_MP_INPUTS on both binaries
    # so each emits its tukey_median_polish input matrix per entry.
    # Adds ~800 MB per workdir to dump volume but lets us verify whether
    # peak_xics divergences are upstream (XIC extraction) or downstream
    # (peak shape feature compute). Mirrors the methodology that
    # bisected the in-process vs worker compaction gap.
    [switch]$DumpMpInputs,

    # On-demand bisection: enable OSPREY_DUMP_PREDICT_RT on both
    # binaries so each emits per-file calibration arrays + per-call
    # (entry_id, library_rt -> expected_rt) tuples. Use to narrow
    # whether apex-divergence root cause is RT calibration drift
    # (cal_arrays diverge), Predict() drift on identical arrays, or
    # downstream of RT calibration entirely.
    [switch]$DumpPredictRt,

    # On-demand bisection: enable OSPREY_DUMP_CWT_PATH on both
    # binaries. Each emits one row per (file, entry) reaching the
    # CWT detection path: file_name, entry_id, n_cwt_peaks,
    # n_final_peaks, n_scored, scored. Diff cross-impl to localize
    # which entries diverge and at which seam (CWT detection vs
    # fallback vs apex-acceptance).
    [switch]$DumpCwtPath
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

. "$PSScriptRoot\Dataset-Config.ps1"

$scriptRoot = Split-Path -Parent $PSCommandPath
$aiRoot = Split-Path -Parent (Split-Path -Parent $scriptRoot)
$projRoot = Split-Path -Parent $aiRoot

$rustBinary = Join-Path $projRoot "osprey\target\release\osprey.exe"
if (-not (Test-Path $rustBinary)) { Write-Error "Rust binary not found: $rustBinary"; exit 1 }

$csharpRelBin = "pwiz_tools\OspreySharp\OspreySharp\bin\x64\Release\$TargetFramework\OspreySharp.exe"
if ($CsharpRoot) {
    $csharpBase = $CsharpRoot
} else {
    $csharpBase = $null
    foreach ($c in @("pwiz", "pwiz-work1", "pwiz-work2")) {
        $p = Join-Path $projRoot $c
        if (Test-Path (Join-Path $p $csharpRelBin)) { $csharpBase = $p; break }
    }
    if (-not $csharpBase) { $csharpBase = Join-Path $projRoot "pwiz" }
}
$csharpBinary = Join-Path $csharpBase $csharpRelBin
if (-not (Test-Path $csharpBinary)) { Write-Error "OspreySharp binary not found: $csharpBinary"; exit 1 }

Write-Host "Rust binary: $rustBinary" -ForegroundColor DarkGray
Write-Host "C#   binary: $csharpBinary" -ForegroundColor DarkGray
Write-Host "Threads:     $Threads"     -ForegroundColor DarkGray
Write-Host ""

$datasets = if ($Dataset -eq "Both") { @("Stellar","Astral") } else { @($Dataset) }
$totalStart = [Diagnostics.Stopwatch]::StartNew()
$allResults = @()

# Helpers -------------------------------------------------------------

function Invoke-Worker {
    param(
        [string]$Tool,
        [string]$Binary,
        [string]$WorkDir,
        [string[]]$ParquetNames,
        [string]$LibraryName,
        [string]$Resolution,
        [int]$Threads
    )
    $outBlib = Join-Path $WorkDir ("_discard_{0}.blib" -f $Tool.ToLower())
    $args = @("--join-at-pass=1", "--no-join")
    foreach ($p in $ParquetNames) { $args += "--input-scores"; $args += $p }
    $args += @("-l", $LibraryName, "--output", $outBlib,
               "--resolution", $Resolution, "--protein-fdr", "0.01",
               "--threads", $Threads.ToString())
    # OspreySharp Parquet.Net only handles Snappy; Rust default is ZSTD.
    # Force Snappy on Rust so the reconciled .scores.parquet from Phase
    # 3 can be byte-compared cross-impl. OspreySharp doesn't recognize
    # the flag (it always writes Snappy), so only pass it to the Rust
    # binary.
    if ($Tool -eq "Rust") {
        $args += @("--parquet-compression", "snappy")
    }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    Push-Location $WorkDir
    try {
        & $Binary @args 2>&1 | Out-Null
        $exit = $LASTEXITCODE
    } finally { Pop-Location }
    $sw.Stop()
    return [PSCustomObject]@{
        Tool = $Tool; ExitCode = $exit
        ElapsedSec = [math]::Round($sw.Elapsed.TotalSeconds, 2)
    }
}

function Materialize-Workdir {
    param([string]$FixtureDir, [string]$WorkDir)
    if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force }
    New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
    Get-ChildItem -Path $FixtureDir -File | Where-Object { $_.Name -ne ".fixture-version" } |
        ForEach-Object {
            Copy-Item -Path $_.FullName -Destination (Join-Path $WorkDir $_.Name) -Force
        }
}

# Per-dataset loop ----------------------------------------------------

foreach ($dsName in $datasets) {
    $ds = Get-DatasetConfig $dsName -TestBaseDir $TestBaseDir
    $testDir = $ds.TestDir
    $stems = $ds.AllFiles | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_) }

    Write-Host ("=== {0} (TestDir: {1}) ===" -f $ds.Name, $testDir) -ForegroundColor Cyan

    $fixtureDir = Join-Path $testDir ("_stage6_fixture\{0}" -f $ds.Name)
    if (-not (Test-Path (Join-Path $fixtureDir ".fixture-version"))) {
        Write-Host ("  Missing fixture at {0}" -f $fixtureDir) -ForegroundColor Red
        Write-Host "  Run Build-Stage6Fixture.ps1 first." -ForegroundColor Red
        $allResults += [PSCustomObject]@{
            Dataset = $ds.Name; Status = "FIXTURE_MISSING"
        }
        continue
    }

    $rustWorkDir = Join-Path $testDir ("_stage6_iter\{0}_rust" -f $ds.Name)
    $csWorkDir   = Join-Path $testDir ("_stage6_iter\{0}_cs"   -f $ds.Name)

    # Stage A: materialize per-tool workdirs from the fixture.
    Write-Host "  Stage A: materializing workdirs from fixture..." -ForegroundColor Yellow
    $matStart = [Diagnostics.Stopwatch]::StartNew()
    Materialize-Workdir -FixtureDir $fixtureDir -WorkDir $rustWorkDir
    Materialize-Workdir -FixtureDir $fixtureDir -WorkDir $csWorkDir
    $matStart.Stop()
    Write-Host ("    Stage A: {0:F1}s" -f $matStart.Elapsed.TotalSeconds)

    $parquetNames = $stems | ForEach-Object { "$_.scores.parquet" }

    # Stage B: Rust worker with both dumps enabled.
    Write-Host "  Stage B: Rust worker..." -ForegroundColor Yellow
    $env:OSPREY_DUMP_PERCOLATOR = "1"
    $env:OSPREY_DUMP_RESCORED   = "1"
    # OSPREY_DUMP_MP_INPUTS / OSPREY_DUMP_PREDICT_RT on Rust take paths;
    # on C# they're booleans that write to cs_stage6_*.tsv in cwd.
    # Pass the Rust-side path so each binary emits its dump in its own
    # workdir.
    if ($DumpMpInputs) {
        $env:OSPREY_DUMP_MP_INPUTS = "rust_stage6_mp_inputs.tsv"
    }
    if ($DumpPredictRt) {
        $env:OSPREY_DUMP_PREDICT_RT = "rust_stage6_predict_rt.tsv"
    }
    if ($DumpCwtPath) {
        $env:OSPREY_DUMP_CWT_PATH = "rust_stage6_cwt_path.tsv"
    }
    try {
        $rustRun = Invoke-Worker -Tool "Rust" -Binary $rustBinary -WorkDir $rustWorkDir `
            -ParquetNames $parquetNames -LibraryName $ds.Library `
            -Resolution $ds.Resolution -Threads $Threads
    } finally {
        Remove-Item Env:\OSPREY_DUMP_PERCOLATOR -ErrorAction Ignore
        Remove-Item Env:\OSPREY_DUMP_RESCORED   -ErrorAction Ignore
        Remove-Item Env:\OSPREY_DUMP_MP_INPUTS  -ErrorAction Ignore
        Remove-Item Env:\OSPREY_DUMP_PREDICT_RT -ErrorAction Ignore
        Remove-Item Env:\OSPREY_DUMP_CWT_PATH   -ErrorAction Ignore
    }
    Write-Host ("    Stage B: {0}s (exit {1})" -f $rustRun.ElapsedSec, $rustRun.ExitCode)

    # Stage C: C# worker with both dumps enabled.
    Write-Host "  Stage C: C# worker..." -ForegroundColor Yellow
    $env:OSPREY_DUMP_PERCOLATOR = "1"
    $env:OSPREY_DUMP_RESCORED   = "1"
    if ($DumpMpInputs) {
        $env:OSPREY_DUMP_MP_INPUTS = "1"
    }
    if ($DumpPredictRt) {
        $env:OSPREY_DUMP_PREDICT_RT = "1"
    }
    if ($DumpCwtPath) {
        $env:OSPREY_DUMP_CWT_PATH = "1"
    }
    try {
        $csRun = Invoke-Worker -Tool "Cs" -Binary $csharpBinary -WorkDir $csWorkDir `
            -ParquetNames $parquetNames -LibraryName $ds.Library `
            -Resolution $ds.Resolution -Threads $Threads
    } finally {
        Remove-Item Env:\OSPREY_DUMP_PERCOLATOR -ErrorAction Ignore
        Remove-Item Env:\OSPREY_DUMP_RESCORED   -ErrorAction Ignore
        Remove-Item Env:\OSPREY_DUMP_MP_INPUTS  -ErrorAction Ignore
        Remove-Item Env:\OSPREY_DUMP_PREDICT_RT -ErrorAction Ignore
        Remove-Item Env:\OSPREY_DUMP_CWT_PATH   -ErrorAction Ignore
    }
    Write-Host ("    Stage C: {0}s (exit {1})" -f $csRun.ElapsedSec, $csRun.ExitCode)
    # Note: the C# worker exits non-zero today (rescore engine stub
    # after Phase 1) AFTER writing the dumps. That's fine for parity —
    # the dumps are what we compare here.

    # Stage D: two-pass compare via Compare-Percolator.ps1.
    #   D.1 — post-hydration (stage5_percolator): proves the boundary
    #         file pair was hydrated identically on both binaries.
    #   D.2 — post-rescore (stage6_rescored): proves the rescore loop
    #         (consensus + reconciliation overlay + future gap-fill)
    #         produced identical Score/PEP/q-values on both binaries.
    $compareScript = Join-Path $scriptRoot "Compare-Percolator.ps1"

    $rustHydration = Join-Path $rustWorkDir "rust_stage5_percolator.tsv"
    $csHydration   = Join-Path $csWorkDir   "cs_stage5_percolator.tsv"
    $rustRescored  = Join-Path $rustWorkDir "rust_stage6_rescored.tsv"
    $csRescored    = Join-Path $csWorkDir   "cs_stage6_rescored.tsv"

    $hydrationStatus = "MISSING"
    $rescoredStatus  = "MISSING"

    if ((Test-Path $rustHydration) -and (Test-Path $csHydration)) {
        Write-Host "  Stage D.1: Compare-Percolator (post-hydration)..." -ForegroundColor Yellow
        & pwsh -File $compareScript -RustTsv $rustHydration -CsTsv $csHydration
        $hydrationStatus = if ($LASTEXITCODE -eq 0) { "PASS" } else { "FAIL" }
    } else {
        Write-Host "  Stage D.1 skipped (post-hydration dump missing)" -ForegroundColor Red
    }

    if ((Test-Path $rustRescored) -and (Test-Path $csRescored)) {
        Write-Host "  Stage D.2: Compare-Percolator (post-rescore)..." -ForegroundColor Yellow
        & pwsh -File $compareScript -RustTsv $rustRescored -CsTsv $csRescored
        $rescoredStatus = if ($LASTEXITCODE -eq 0) { "PASS" } else { "FAIL" }
    } else {
        Write-Host "  Stage D.2 skipped (post-rescore dump missing)" -ForegroundColor Red
    }

    # Stage E: column-level content diff of the reconciled .scores.parquet
    # outputs. Allowlisted columns are the ones the C# scoring path
    # doesn't yet populate (tracked in the Stage 6 TODO under
    # "implement missing scores"). Real divergences are NOT allowlisted
    # — they're bisected upstream via diagnostic dumps until root cause
    # surfaces (the same methodology that nailed the Stage 5/6 vs.
    # sidecar-rehydrate split).
    #
    # Diff-Parquet's default 1e-6 NumericTolerance absorbs the broader
    # ULP-level Stage 1-4 drift (TODO open follow-up #2) so it doesn't
    # pollute Stage 6 output here.
    $diffParquetScript = Join-Path $scriptRoot "Diff-Parquet.ps1"
    $expectedDiff = @(
        'fragment_mzs', 'fragment_intensities',
        'reference_xic_rts', 'reference_xic_intensities',
        'bounds_area', 'bounds_snr'
    )
    Write-Host "  Stage E: Diff-Parquet (reconciled .scores.parquet)..." -ForegroundColor Yellow
    # In-process invocation (not `pwsh -File`): array-typed parameters
    # like -ExpectedDiffColumns survive bind across script boundaries
    # only when the call stays inside one PowerShell host.
    & $diffParquetScript -DirA $rustWorkDir -DirB $csWorkDir `
        -ExpectedDiffColumns $expectedDiff -Quiet
    $parquetStatus = if ($LASTEXITCODE -eq 0) { "PASS" } else { "FAIL" }

    $stages = @($hydrationStatus, $rescoredStatus, $parquetStatus)
    $overallStatus = if ($stages -contains "FAIL") {
        "FAIL"
    } elseif ($stages -contains "MISSING") {
        "PARTIAL"
    } else {
        "PASS"
    }

    $allResults += [PSCustomObject]@{
        Dataset = $ds.Name
        Hydration = $hydrationStatus
        Rescored = $rescoredStatus
        Parquet = $parquetStatus
        Status = $overallStatus
        RustSec = $rustRun.ElapsedSec
        CsSec = $csRun.ElapsedSec
    }

    Write-Host ""
}

$totalStart.Stop()

Write-Host "--- Summary ---" -ForegroundColor Cyan
Write-Host ""
$allResults | Format-Table -AutoSize Dataset, Hydration, Rescored, Parquet, Status, RustSec, CsSec

$pass = ($allResults | Where-Object { $_.Status -eq "PASS" }).Count
$total = $allResults.Count
$timeStr = "{0:mm\:ss}" -f $totalStart.Elapsed
Write-Host ("{0}/{1} dataset(s) passed cross-impl Stage 6 worker parity. Total: {2}" `
    -f $pass, $total, $timeStr) `
    -ForegroundColor $(if ($pass -eq $total) { "Green" } else { "Yellow" })

exit $(if ($pass -eq $total) { 0 } else { 1 })
