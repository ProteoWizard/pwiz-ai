<#
.SYNOPSIS
    Stage 6 per-file rescore worker portability gate.

.DESCRIPTION
    Proves that the `--join-at-pass=1 --no-join` worker produces
    byte-identical reconciled `.scores.parquet` files versus an
    end-to-end in-process Stage 6 run on the same inputs, AND that
    the boundary files + Stage 4 parquet are portable across
    filesystem locations (the worker can finish on a different
    machine / under a different absolute path than where the
    boundary was persisted).

    Three phases per dataset:

      Phase A — Baseline (in-process)
        Stage 4 parquets in /work/A/  →  osprey --input-scores --join-at-pass=1
        runs Stages 5-8 in one process and writes reconciled
        `.scores.parquet` files in place. Snapshot the SHA-256 of
        each reconciled parquet.

      Phase B — Persist Stage 5 boundary (in-process)
        Restore Stage 4 parquets in /work/A/ → osprey --input-scores
        --join-at-pass=1 --join-only writes the boundary file pair
        (`.1st-pass.fdr_scores.bin` + `.reconciliation.json`)
        sibling to each parquet, then exits before Stage 6.

      Phase C — Worker on RENAMED folder
        Restore Stage 4 parquets in /work/A/. Move the entire work
        dir from /work/A/ to /work/B/ (different absolute path).
        Run osprey --input-scores --join-at-pass=1 --no-join from
        /work/B/. Worker reads the relocated boundary files +
        parquet + sibling mzML / calibration JSON / spectra cache,
        runs Stage 6, writes reconciled `.scores.parquet` in place
        at /work/B/. Snapshot the SHA-256 of each reconciled
        parquet.

    Pass ≡ Phase A reconciled parquets are byte-identical to
    Phase C reconciled parquets. Failure modes the gate catches:

      - Absolute paths leaked into a boundary file (would break on
        rename)
      - Spectra cache paths not derived from the new working dir
      - Worker accidentally falls back to original-folder defaults
      - Any non-determinism between in-memory Stage 6 and
        rehydrate-then-Stage-6

    Dataset inputs come from Get-DatasetConfig (mzML + library +
    spectra cache + Stage 4 parquet snapshots produced by
    Generate-AllScoresParquet.ps1, same staging as
    Compare-Stage5-Boundary.ps1).

.PARAMETER Dataset
    Stellar | Astral | Both (default Stellar).

.PARAMETER TestBaseDir
    Override test data root (defaults to OSPREY_TEST_BASE_DIR or
    D:\test\osprey-runs).

.PARAMETER Clean
    Force a fresh staged work dir (re-stage parquets + mzML + cal
    JSON + spectra cache + library, discard any artifacts from
    prior runs). Use this on the first run after rebuilding the
    Rust binary.

.PARAMETER Threads
    --threads value passed to osprey (default 16). Holding this
    constant matters: search_hash includes thread-affecting
    parameters, and Phase A vs Phase C must use the same value or
    the parquet metadata sanity check trips.

.EXAMPLE
    # Stellar portability gate (~7 minutes wall-clock).
    .\Compare-Stage6-Worker.ps1 -Dataset Stellar -Clean
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

$rustBinary = Join-Path $projRoot "osprey\target\release\osprey.exe"
if (-not (Test-Path $rustBinary)) { Write-Error "Rust binary not found: $rustBinary"; exit 1 }

Write-Host "Rust binary: $rustBinary" -ForegroundColor DarkGray
Write-Host "Threads:     $Threads" -ForegroundColor DarkGray
Write-Host ""

$datasets = if ($Dataset -eq "Both") { @("Stellar","Astral") } else { @($Dataset) }
$totalStart = [Diagnostics.Stopwatch]::StartNew()
$allResults = @()

# Helpers ----------------------------------------------------------------

function Invoke-Osprey {
    param(
        [string]$Mode,
        [string]$WorkDir,
        [string[]]$ParquetNames,
        [string]$LibraryName,
        [string]$Resolution,
        [int]$Threads,
        [string]$Tag
    )
    $outBlib = Join-Path $WorkDir "_discard_$Tag.blib"
    $args = @("--join-at-pass=1")
    if ($Mode -eq "join-only") { $args += "--join-only" }
    elseif ($Mode -eq "no-join") { $args += "--no-join" }
    foreach ($p in $ParquetNames) { $args += "--input-scores"; $args += $p }
    $args += @("-l", $LibraryName, "--output", $outBlib,
               "--resolution", $Resolution, "--protein-fdr", "0.01",
               "--threads", $Threads.ToString())
    $sw = [Diagnostics.Stopwatch]::StartNew()
    Push-Location $WorkDir
    try {
        & $rustBinary @args 2>&1 | Out-Null
        $exit = $LASTEXITCODE
    } finally { Pop-Location }
    $sw.Stop()
    return [PSCustomObject]@{
        Mode = $Mode; ExitCode = $exit; Tag = $Tag
        ElapsedSec = [math]::Round($sw.Elapsed.TotalSeconds, 2)
    }
}

function Snapshot-Stage4Parquets {
    param([string]$WorkDir, [string[]]$Stems)
    $snapDir = Join-Path $WorkDir ".stage4_snapshot"
    if (Test-Path $snapDir) { Remove-Item $snapDir -Recurse -Force }
    New-Item -ItemType Directory -Path $snapDir -Force | Out-Null
    foreach ($stem in $Stems) {
        $src = Join-Path $WorkDir "$stem.scores.parquet"
        $dst = Join-Path $snapDir "$stem.scores.parquet"
        Copy-Item -Path $src -Destination $dst -Force
    }
    return $snapDir
}

function Restore-Stage4Parquets {
    param([string]$SnapDir, [string]$WorkDir, [string[]]$Stems)
    foreach ($stem in $Stems) {
        $src = Join-Path $SnapDir "$stem.scores.parquet"
        $dst = Join-Path $WorkDir "$stem.scores.parquet"
        Copy-Item -Path $src -Destination $dst -Force
    }
    # Boundary sidecars + reconciled parquet metadata from prior
    # phases must be cleared before the next phase runs. Otherwise a
    # `--join-only` run that's already been done would skip work, and
    # `--no-join` would pick up stale boundary files from a different
    # config.
    foreach ($stem in $Stems) {
        foreach ($ext in @("1st-pass.fdr_scores.bin", "reconciliation.json")) {
            $stale = Join-Path $WorkDir "$stem.$ext"
            if (Test-Path $stale) { Remove-Item $stale -Force }
        }
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

# Phases -----------------------------------------------------------------

foreach ($dsName in $datasets) {
    $ds = Get-DatasetConfig $dsName -TestBaseDir $TestBaseDir
    $testDir = $ds.TestDir
    $libraryPath = Join-Path $testDir $ds.Library
    $stems = $ds.AllFiles | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_) }

    Write-Host ("=== {0} (TestDir: {1}) ===" -f $ds.Name, $testDir) -ForegroundColor Cyan

    # Sanity-check the parquet snapshots produced by Generate-AllScoresParquet.ps1
    $rustParquets = @()
    foreach ($stem in $stems) {
        $rustParquet = Join-Path $testDir "$stem.scores.rust.parquet"
        if (-not (Test-Path $rustParquet)) {
            Write-Host ("  missing rust parquet for {0} -- run Generate-AllScoresParquet.ps1 first" -f $stem) -ForegroundColor Red
            continue
        }
        $rustParquets += $rustParquet
    }
    if ($rustParquets.Count -ne $stems.Count) {
        Write-Host "  skipping dataset (incomplete parquet inputs)" -ForegroundColor Red
        continue
    }

    # Stage everything into work-dir A. Files staged: parquet (named
    # canonically as <stem>.scores.parquet), calibration JSON, mzML,
    # spectra cache, library. Library has to live in the work dir so
    # the rename test in Phase C still resolves it.
    $workDirA = Join-Path $testDir ("_stage6_worker\{0}_A" -f $ds.Name)
    $workDirB = Join-Path $testDir ("_stage6_worker\{0}_B" -f $ds.Name)
    if ($Clean) {
        foreach ($d in @($workDirA, $workDirB)) {
            if (Test-Path $d) {
                Write-Host ("  -Clean: removing {0}" -f $d) -ForegroundColor DarkGray
                Remove-Item $d -Recurse -Force
            }
        }
    }
    if (Test-Path $workDirB) {
        Write-Host ("  removing prior renamed dir {0}" -f $workDirB) -ForegroundColor DarkGray
        Remove-Item $workDirB -Recurse -Force
    }
    New-Item -ItemType Directory -Path $workDirA -Force | Out-Null

    $stagedMarker = Join-Path $workDirA ".staged"
    if (-not (Test-Path $stagedMarker)) {
        Write-Host ("  staging {0} parquet(s) + mzML + cal JSON + spectra cache + library into {1}" `
            -f $rustParquets.Count, $workDirA) -ForegroundColor DarkGray
        foreach ($srcParquet in $rustParquets) {
            $stem = ([IO.Path]::GetFileNameWithoutExtension($srcParquet)) -replace '\.scores\.rust$', ''
            Copy-Item -Path $srcParquet -Destination (Join-Path $workDirA "$stem.scores.parquet")
            foreach ($ext in @("mzML", "calibration.json", "spectra.bin")) {
                $src = Join-Path $testDir "$stem.$ext"
                if (Test-Path $src) {
                    Copy-Item -Path $src -Destination (Join-Path $workDirA "$stem.$ext")
                }
            }
        }
        Copy-Item -Path $libraryPath -Destination (Join-Path $workDirA $ds.Library)
        $libcache = Join-Path $testDir ($ds.Library + ".libcache")
        if (Test-Path $libcache) {
            Copy-Item -Path $libcache -Destination (Join-Path $workDirA ($ds.Library + ".libcache"))
        }
        Set-Content -Path $stagedMarker -Value (Get-Date -Format o)
    } else {
        Write-Host ("  reusing staged dir {0}" -f $workDirA) -ForegroundColor DarkGray
    }

    $parquetNames = $stems | ForEach-Object { "$_.scores.parquet" }
    $stage4Snap = Snapshot-Stage4Parquets -WorkDir $workDirA -Stems $stems

    # Phase A — in-process baseline ------------------------------------
    Write-Host "  Phase A: in-process Stages 5-8 (--join-at-pass=1, no modifier)..." -ForegroundColor Yellow
    $phaseA = Invoke-Osprey -Mode "in-process" -WorkDir $workDirA `
        -ParquetNames $parquetNames -LibraryName $ds.Library `
        -Resolution $ds.Resolution -Threads $Threads -Tag "phaseA"
    Write-Host ("    Phase A: {0}s (exit {1})" -f $phaseA.ElapsedSec, $phaseA.ExitCode)
    $hashesA = Hash-ParquetFiles -WorkDir $workDirA -Stems $stems

    # Phase B — restore Stage 4, persist boundary ----------------------
    # Restore-Stage4Parquets also wipes any stale boundary files from
    # a prior run so this Phase B run produces fresh sidecars sibling
    # to the just-restored parquets.
    Restore-Stage4Parquets -SnapDir $stage4Snap -WorkDir $workDirA -Stems $stems
    Write-Host "  Phase B: restore Stage 4 parquets, write boundary (--join-at-pass=1 --join-only)..." `
        -ForegroundColor Yellow
    $phaseB = Invoke-Osprey -Mode "join-only" -WorkDir $workDirA `
        -ParquetNames $parquetNames -LibraryName $ds.Library `
        -Resolution $ds.Resolution -Threads $Threads -Tag "phaseB"
    Write-Host ("    Phase B: {0}s (exit {1})" -f $phaseB.ElapsedSec, $phaseB.ExitCode)

    # PORTABILITY TWIST: rename A -> B before the worker runs.
    Write-Host ("  Phase C: rename {0} -> {1} (HPC portability check)" -f $workDirA, $workDirB) -ForegroundColor Magenta
    Rename-Item -Path $workDirA -NewName (Split-Path -Leaf $workDirB)

    Write-Host "  Phase C: --join-at-pass=1 --no-join from renamed dir..." -ForegroundColor Yellow
    $phaseC = Invoke-Osprey -Mode "no-join" -WorkDir $workDirB `
        -ParquetNames $parquetNames -LibraryName $ds.Library `
        -Resolution $ds.Resolution -Threads $Threads -Tag "phaseC"
    Write-Host ("    Phase C: {0}s (exit {1})" -f $phaseC.ElapsedSec, $phaseC.ExitCode)
    $hashesC = Hash-ParquetFiles -WorkDir $workDirB -Stems $stems

    # Compare A vs C ----------------------------------------------------
    Write-Host "  Comparing reconciled .scores.parquet (A vs C)..." -ForegroundColor Yellow
    foreach ($stem in $stems) {
        $hA = if ($hashesA.ContainsKey($stem)) { $hashesA[$stem] } else { $null }
        $hC = if ($hashesC.ContainsKey($stem)) { $hashesC[$stem] } else { $null }
        if (-not $hA -or -not $hC) {
            $status = if (-not $hA -and -not $hC) { "BOTH MISSING" }
                      elseif (-not $hA)            { "A MISSING" }
                      else                          { "C MISSING" }
            $allResults += [PSCustomObject]@{
                Dataset = $ds.Name; Stem = $stem; Status = $status; Bytes = 0
            }
            continue
        }
        $status = if ($hA.Hash -eq $hC.Hash) { "PASS" } else { "FAIL" }
        $allResults += [PSCustomObject]@{
            Dataset = $ds.Name; Stem = $stem; Status = $status; Bytes = $hA.Bytes
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
Write-Host ("{0}/{1} reconciled parquets byte-identical between in-process and worker (post-rename).  Total: {2}" `
    -f $pass, $total, $timeStr) `
    -ForegroundColor $(if ($pass -eq $total) { "Green" } else { "Yellow" })

if ($pass -eq $total) {
    Write-Host ""
    Write-Host "Stage 6 worker output is portable: hydrate-from-disk after a folder rename produces" -ForegroundColor Green
    Write-Host "byte-identical reconciled parquets to an in-process Stage 6. HPC fan-out unblocked." -ForegroundColor Green
    exit 0
} else {
    Write-Host ""
    Write-Host "Stage 6 worker output diverges from in-process Stage 6 OR the rename broke portability." -ForegroundColor Yellow
    Write-Host "See FAIL rows above. Diagnose by running osprey directly on the staged work dir." -ForegroundColor Yellow
    exit 1
}
