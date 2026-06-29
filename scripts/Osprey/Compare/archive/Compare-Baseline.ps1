<#
.SYNOPSIS
    End-to-end byte-parity check between osprey-mm baseline
    (maccoss/osprey:main) and the local feature/stage6-worker tree.

.DESCRIPTION
    Companion to Compare-Stage6-Worker.ps1. Where the Stage 6 worker
    harness proves the new --join-at-pass=1 --no-join code path is
    byte-identical to in-process, this harness proves that the changes
    in feature/stage6-worker have NOT perturbed end-to-end pipeline
    output relative to the maccoss/osprey:main baseline.

    The two binaries:

      Baseline: C:\proj\osprey-mm\target\release\osprey.exe
                (built from maccoss/osprey, currently main @ 1a18bc8)
      Feature:  C:\proj\osprey\target\release\osprey.exe
                (built from feature/stage6-worker)

    Both binaries are run end-to-end (osprey -i mzML -l lib -o blib)
    against identical staged inputs (mzML + library only; no Stage 4
    parquet pre-staged so Stages 1-4 run fresh on each side). The
    .scores.parquet files produced by Stages 1-8 are SHA-256
    byte-compared.

    PASS criterion: every .scores.parquet pair is byte-identical.
    The changes in feature/stage6-worker that COULD affect end-to-end
    output are:

      - serde_json float_roundtrip feature flag (Cargo.toml)
        - end-to-end flow does not parse f64s from JSON at runtime,
          so this should be a no-op
      - persist_fdr_scores call-site moved AFTER first-pass protein
        FDR (pipeline.rs)
        - only changes WHEN the .1st-pass.fdr_scores.bin sidecar is
          written (still pre-Stage-6); the in-memory state used for
          Stages 5-8 is unchanged
      - Sidecar v3 record format (added run_protein_qvalue, 52 -> 60
        bytes)
        - written-only in end-to-end mode; not consumed by Stage 6
      - rescore::run_rescore worker compaction
        - in a different code path; never invoked in end-to-end mode
      - synthesize config.input_files from --input-scores at top of
        run_analysis
        - guarded by --input-scores; end-to-end populates input_files
          from -i naturally so this branch is dormant

    All five are expected to be no-ops for end-to-end. If parquets
    diverge, that's a real regression worth blocking the PR.

.PARAMETER Dataset
    Stellar | Astral | Both (default Stellar).

.PARAMETER TestBaseDir
    Override test data root (defaults to OSPREY_TEST_BASE_DIR or
    D:\test\osprey-runs).

.PARAMETER Clean
    Force a fresh staged work dir.

.PARAMETER Threads
    --threads value passed to osprey (default 16). Held constant
    across both binaries.

.EXAMPLE
    # Stellar end-to-end baseline regression (~25-30 min wall-clock,
    # both binaries run Stages 1-8 from mzML).
    .\Compare-Baseline.ps1 -Dataset Stellar -Clean
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("Stellar", "Astral", "Both")]
    [string]$Dataset = "Stellar",

    [string]$TestBaseDir = $null,

    [switch]$Clean,

    [int]$Threads = 16
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

. "$PSScriptRoot\Dataset-Config.ps1"

$scriptRoot = Split-Path -Parent $PSCommandPath
$aiRoot = Split-Path -Parent (Split-Path -Parent $scriptRoot)
$projRoot = Split-Path -Parent $aiRoot

$baselineBinary = Join-Path $projRoot "osprey-mm\target\release\osprey.exe"
$featureBinary  = Join-Path $projRoot "osprey\target\release\osprey.exe"
foreach ($b in @($baselineBinary, $featureBinary)) {
    if (-not (Test-Path $b)) {
        Write-Error "Binary not found: $b"
        exit 1
    }
}

Write-Host "Baseline (main):              $baselineBinary" -ForegroundColor DarkGray
Write-Host "Feature  (stage6-worker):     $featureBinary"  -ForegroundColor DarkGray
Write-Host "Threads:                      $Threads"        -ForegroundColor DarkGray
Write-Host ""

$datasets = if ($Dataset -eq "Both") { @("Stellar","Astral") } else { @($Dataset) }
$totalStart = [Diagnostics.Stopwatch]::StartNew()
$allResults = @()

# Helpers ----------------------------------------------------------------

function Invoke-OspreyEndToEnd {
    param(
        [string]$Binary,
        [string]$WorkDir,
        [string[]]$MzmlNames,
        [string]$LibraryName,
        [string]$Resolution,
        [int]$Threads,
        [string]$Tag
    )
    $outBlib = Join-Path $WorkDir "_out_$Tag.blib"
    $args = @()
    foreach ($m in $MzmlNames) { $args += "-i"; $args += $m }
    $args += @("-l", $LibraryName, "-o", $outBlib,
               "--resolution", $Resolution, "--protein-fdr", "0.01",
               "--threads", $Threads.ToString())
    $sw = [Diagnostics.Stopwatch]::StartNew()
    Push-Location $WorkDir
    try {
        & $Binary @args 2>&1 | Out-Null
        $exit = $LASTEXITCODE
    } finally { Pop-Location }
    $sw.Stop()
    return [PSCustomObject]@{
        Binary = $Binary; ExitCode = $exit; Tag = $Tag
        ElapsedSec = [math]::Round($sw.Elapsed.TotalSeconds, 2)
    }
}

function Hash-ParquetFiles {
    param([string]$WorkDir, [string[]]$Stems)
    $h = @{}
    foreach ($stem in $Stems) {
        $p = Join-Path $WorkDir "$stem.scores.parquet"
        if (Test-Path $p) {
            $h[$stem] = @{
                Hash = (Get-FileHash -Path $p -Algorithm SHA256).Hash
                Bytes = (Get-Item $p).Length
            }
        }
    }
    return $h
}

function Stage-EndToEndWorkDir {
    param([string]$WorkDir, [string[]]$Stems, [string]$TestDir, [string]$Library)
    New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
    foreach ($stem in $Stems) {
        # Only stage the mzML; let each binary build its own
        # spectra cache + calibration + Stage 4 parquet from scratch
        # so the comparison covers the full Stages 1-8 path.
        $mzmlSrc = Join-Path $TestDir "$stem.mzML"
        if (-not (Test-Path $mzmlSrc)) {
            Write-Error "mzML not found: $mzmlSrc"
            exit 1
        }
        Copy-Item -Path $mzmlSrc -Destination (Join-Path $WorkDir "$stem.mzML")
    }
    $libPath = Join-Path $TestDir $Library
    Copy-Item -Path $libPath -Destination (Join-Path $WorkDir $Library)
    $libcache = Join-Path $TestDir ($Library + ".libcache")
    if (Test-Path $libcache) {
        Copy-Item -Path $libcache -Destination (Join-Path $WorkDir ($Library + ".libcache"))
    }
}

# Phases -----------------------------------------------------------------

foreach ($dsName in $datasets) {
    $ds = Get-DatasetConfig $dsName -TestBaseDir $TestBaseDir
    $testDir = $ds.TestDir
    $stems = $ds.AllFiles | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_) }

    Write-Host ("=== {0} (TestDir: {1}) ===" -f $ds.Name, $testDir) -ForegroundColor Cyan

    foreach ($stem in $stems) {
        $mzml = Join-Path $testDir "$stem.mzML"
        if (-not (Test-Path $mzml)) {
            Write-Host ("  missing mzML for {0}" -f $stem) -ForegroundColor Red
            exit 1
        }
    }

    $workDirBase    = Join-Path $testDir ("_baseline_regression\{0}_baseline" -f $ds.Name)
    $workDirFeature = Join-Path $testDir ("_baseline_regression\{0}_feature"  -f $ds.Name)

    if ($Clean) {
        foreach ($d in @($workDirBase, $workDirFeature)) {
            if (Test-Path $d) {
                Write-Host ("  -Clean: removing {0}" -f $d) -ForegroundColor DarkGray
                Remove-Item $d -Recurse -Force
            }
        }
    }

    # Stage both work dirs identically (mzML + library only; binaries
    # build their own spectra cache + calibration + Stage 4 parquet)
    foreach ($wd in @($workDirBase, $workDirFeature)) {
        $stagedMarker = Join-Path $wd ".staged"
        if (-not (Test-Path $stagedMarker)) {
            Write-Host ("  staging {0} mzML(s) + library into {1}" `
                -f $stems.Count, $wd) -ForegroundColor DarkGray
            Stage-EndToEndWorkDir -WorkDir $wd -Stems $stems -TestDir $testDir -Library $ds.Library
            Set-Content -Path $stagedMarker -Value (Get-Date -Format o)
        } else {
            Write-Host ("  reusing staged dir {0}" -f $wd) -ForegroundColor DarkGray
        }
    }

    $mzmlNames = $stems | ForEach-Object { "$_.mzML" }

    # Run baseline (osprey-mm @ main) end-to-end -----------------------
    Write-Host "  Baseline (osprey-mm @ main): end-to-end (-i mzML)..." -ForegroundColor Yellow
    $rBase = Invoke-OspreyEndToEnd -Binary $baselineBinary -WorkDir $workDirBase `
        -MzmlNames $mzmlNames -LibraryName $ds.Library `
        -Resolution $ds.Resolution -Threads $Threads -Tag "baseline"
    Write-Host ("    baseline: {0}s (exit {1})" -f $rBase.ElapsedSec, $rBase.ExitCode)
    if ($rBase.ExitCode -ne 0) {
        Write-Host "  Baseline binary failed; aborting comparison." -ForegroundColor Red
        exit 1
    }
    $hashesBase = Hash-ParquetFiles -WorkDir $workDirBase -Stems $stems

    # Run feature (stage6-worker) end-to-end ----------------------------
    Write-Host "  Feature  (stage6-worker):    end-to-end (-i mzML)..." -ForegroundColor Yellow
    $rFeat = Invoke-OspreyEndToEnd -Binary $featureBinary -WorkDir $workDirFeature `
        -MzmlNames $mzmlNames -LibraryName $ds.Library `
        -Resolution $ds.Resolution -Threads $Threads -Tag "feature"
    Write-Host ("    feature : {0}s (exit {1})" -f $rFeat.ElapsedSec, $rFeat.ExitCode)
    if ($rFeat.ExitCode -ne 0) {
        Write-Host "  Feature binary failed; aborting comparison." -ForegroundColor Red
        exit 1
    }
    $hashesFeat = Hash-ParquetFiles -WorkDir $workDirFeature -Stems $stems

    # Compare ----------------------------------------------------------
    Write-Host "  Comparing reconciled .scores.parquet (baseline vs feature)..." -ForegroundColor Yellow
    foreach ($stem in $stems) {
        $hB = if ($hashesBase.ContainsKey($stem)) { $hashesBase[$stem] } else { $null }
        $hF = if ($hashesFeat.ContainsKey($stem)) { $hashesFeat[$stem] } else { $null }
        if (-not $hB -or -not $hF) {
            $status = if (-not $hB -and -not $hF) { "BOTH MISSING" }
                      elseif (-not $hB)            { "BASELINE MISSING" }
                      else                          { "FEATURE MISSING" }
            $allResults += [PSCustomObject]@{
                Dataset = $ds.Name; Stem = $stem; Status = $status; Bytes = 0
            }
            continue
        }
        $status = if ($hB.Hash -eq $hF.Hash) { "PASS" } else { "FAIL" }
        $allResults += [PSCustomObject]@{
            Dataset = $ds.Name; Stem = $stem; Status = $status; Bytes = $hB.Bytes
        }
    }

    Write-Host ""
}

$totalStart.Stop()

Write-Host "--- Summary ---" -ForegroundColor Cyan
Write-Host ""
$allResults | Format-Table -AutoSize Dataset, Stem, Status, Bytes

$pass = ($allResults | Where-Object { $_.Status -eq "PASS" }).Count
$total = $allResults.Count
$timeStr = "{0:mm\:ss}" -f $totalStart.Elapsed
Write-Host ("{0}/{1} reconciled parquets byte-identical between baseline (osprey-mm @ main) and feature/stage6-worker.  Total: {2}" `
    -f $pass, $total, $timeStr) `
    -ForegroundColor $(if ($pass -eq $total) { "Green" } else { "Yellow" })

if ($pass -eq $total) {
    Write-Host ""
    Write-Host "feature/stage6-worker does not perturb in-process Stage 5-8 output." -ForegroundColor Green
    Write-Host "Safe to merge to main without an in-process behavior change." -ForegroundColor Green
    exit 0
} else {
    Write-Host ""
    Write-Host "feature/stage6-worker DIVERGES from baseline on in-process Stage 5-8." -ForegroundColor Yellow
    Write-Host "Investigate before merging. See FAIL rows above." -ForegroundColor Yellow
    exit 1
}
