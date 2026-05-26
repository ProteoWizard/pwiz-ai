<#
.SYNOPSIS
    Hardest cross-impl comparison: Rust vs C# straight-through
    in-memory pipelines, no HPC chain, no rehydration, no stage
    isolation. ULP errors can compound stage-to-stage.

.DESCRIPTION
    All other cross-impl gates have either constrained Rust-vs-C# to
    the same boundary (Test-Regression's per-stage isolation feeds
    frozen Rust outputs to both sides for stages > 1to4) or kept the
    comparison within one implementation (the strict-rehydration
    in-memory-vs-HPC tests we built today). This script does neither:
    it runs Rust osprey end-to-end and C# OspreySharp end-to-end on
    the same dataset with the same library and resolution, and
    compares the final outputs at 1e-9 tolerance.

    Any cross-impl drift that exists at Stage N flows into Stage N+1,
    accumulating until the blib. If the two outputs are close, we
    have empirical evidence that cross-impl drift through the whole
    pipeline stays sub-tolerance even when ULP errors compound. If
    they're far apart, the script has flushed out an integration
    bug that per-stage gates missed.

    Pipeline shape:
      Rust:  osprey -i mzML(s) -l lib -o output.blib --protein-fdr 0.01
      C#:    OspreySharp -i mzML(s) -l lib -o output.blib --protein-fdr 0.01

    Comparisons:
      Stage 7 protein FDR dump (Compare-Stage7-Crossimpl.ps1, 1e-9)
      Blib content (Compare-Blib-Crossimpl.ps1, SQL row+col 1e-9)
      Precursor counts from per-side log lines

.PARAMETER Dataset
    Stellar (default) or Astral.

.PARAMETER TestBaseDir
    Override dataset root (defaults to OSPREY_TEST_BASE_DIR or
    D:\test\osprey-runs).

.PARAMETER Force
    Wipe any existing workdirs before running.

.PARAMETER SkipRust
    Reuse the existing Rust output if its log + blib + dump are on
    disk. Useful when iterating on C# while Rust is the reference.

.PARAMETER SkipCs
    Symmetric to SkipRust for the C# side.

.PARAMETER Threads
    --threads CLI flag. Default 16.
#>

param(
    [ValidateSet('Stellar','Astral')]
    [string]$Dataset = 'Stellar',
    [string]$TestBaseDir,
    [switch]$Force,
    [switch]$SkipRust,
    [switch]$SkipCs,
    [int]$Threads = 16,
    [ValidateSet('net472','net8.0')]
    [string]$Framework = 'net8.0',
    [string]$Files = 'All'
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $PSCommandPath
. (Join-Path $scriptDir 'Dataset-Config.ps1')

$projRoot = (Resolve-Path (Join-Path $scriptDir '..\..\..')).Path
$ospreyExe = Join-Path $projRoot 'osprey\target\release\osprey.exe'
if (-not (Test-Path $ospreyExe)) {
    Write-Host "osprey.exe not found at $ospreyExe -- build first." -ForegroundColor Red
    exit 2
}
$ospreyShExe = Join-Path $projRoot ("pwiz\pwiz_tools\OspreySharp\OspreySharp\bin\x64\Release\$Framework\OspreySharp.exe")
if (-not (Test-Path $ospreyShExe)) {
    Write-Host "OspreySharp.exe not found at $ospreyShExe -- build first." -ForegroundColor Red
    exit 2
}

$ds = Get-DatasetConfig $Dataset -TestBaseDir $TestBaseDir
$allFiles = @($ds.AllFiles)
$mzmls = switch ($Files) {
    'Single' { ,@($allFiles[0]) }
    'All'    { $allFiles }
    default  {
        $stems = $Files -split ','
        $resolved = @()
        foreach ($s in $stems) {
            $s = $s.Trim()
            if (-not $s) { continue }
            $match = $allFiles | Where-Object {
                $_ -eq $s -or
                ([System.IO.Path]::GetFileNameWithoutExtension($_)) -eq $s
            } | Select-Object -First 1
            if (-not $match) { throw "File '$s' not in dataset $Dataset" }
            $resolved += $match
        }
        ,$resolved
    }
}
$libraryName = $ds.Library
$resolution = $ds.Resolution
$datasetRoot = $ds.TestDir

$rootDir  = Join-Path $datasetRoot "_endtoend_crossimpl"
$rustDir  = Join-Path $rootDir "rust"
$csDir    = Join-Path $rootDir "cs"

if ($Force -and (Test-Path $rootDir)) {
    Write-Host "[EndToEnd] -Force: removing $rootDir" -ForegroundColor DarkYellow
    Remove-Item $rootDir -Recurse -Force
}
New-Item -ItemType Directory -Path $rootDir -Force | Out-Null

function Stage-DatasetFiles {
    param([string]$Dir)
    foreach ($f in $mzmls) {
        Copy-Item (Join-Path $datasetRoot $f) (Join-Path $Dir $f)
    }
    Copy-Item (Join-Path $datasetRoot $libraryName) (Join-Path $Dir $libraryName)
    $cache = Join-Path $datasetRoot ($libraryName + '.libcache')
    if (Test-Path $cache) {
        Copy-Item $cache (Join-Path $Dir ($libraryName + '.libcache'))
    }
}

function Invoke-Tool {
    param([string]$Exe, [string]$WorkDir, [string[]]$CliArgs, [string]$LogName)
    $logPath = Join-Path $WorkDir $LogName
    Push-Location $WorkDir
    try {
        $sw = [Diagnostics.Stopwatch]::StartNew()
        & $Exe @CliArgs 2>&1 | Tee-Object -FilePath $logPath | Out-Null
        $exit = $LASTEXITCODE
        $sw.Stop()
        if ($exit -ne 0) {
            throw "Tool exited $exit; see $logPath."
        }
        return @{ wall = $sw.Elapsed; logPath = $logPath }
    } finally {
        Pop-Location
    }
}

function Get-PrecursorCount {
    param([string]$LogPath)
    # Rust logs "Wrote N precursors"; C# logs "Wrote N spectra to output.blib".
    # Both forms refer to the same blib RefSpectra row count.
    $m = Select-String -Path $LogPath -Pattern 'Wrote\s+(\d+)\s+(?:precursors|spectra)' -AllMatches | Select-Object -Last 1
    if ($m -and $m.Matches.Count -gt 0) { return [int]$m.Matches[0].Groups[1].Value }
    return -1
}

function Format-Duration { param([TimeSpan]$T) ('{0:mm\:ss}' -f $T) }

Write-Host ""
Write-Host "=== Compare-EndToEnd-Crossimpl ===" -ForegroundColor Cyan
Write-Host ("Dataset: {0} ({1} files)" -f $Dataset, $mzmls.Count)
Write-Host ("Workdir: {0}" -f $rootDir)
Write-Host ""

$rustBlib = Join-Path $rustDir 'output.blib'
$rustDump = Join-Path $rustDir 'rust_stage7_protein_fdr.tsv'
$rustLog  = Join-Path $rustDir 'osprey.log'

if ($SkipRust -and (Test-Path $rustBlib) -and (Test-Path $rustDump)) {
    Write-Host "[Rust] -SkipRust: reusing $rustBlib" -ForegroundColor DarkGray
    $rustWall = [TimeSpan]::Zero
} else {
    if (Test-Path $rustDir) { Remove-Item $rustDir -Recurse -Force }
    New-Item -ItemType Directory -Path $rustDir -Force | Out-Null
    Stage-DatasetFiles -Dir $rustDir
    Write-Host "[Rust] osprey -i mzMLs ... (in-memory straight-through) ..." -ForegroundColor Cyan
    $args1 = @()
    foreach ($f in $mzmls) { $args1 += @('-i', $f) }
    $args1 += @('-l', $libraryName, '-o', 'output.blib',
                '--resolution', $resolution,
                '--protein-fdr', '0.01', '--threads', $Threads.ToString())
    $env:OSPREY_DUMP_STAGE7_PROTEIN_FDR = '1'
    try {
        $r = Invoke-Tool -Exe $ospreyExe -WorkDir $rustDir -CliArgs $args1 -LogName 'osprey.log'
    } finally {
        Remove-Item Env:OSPREY_DUMP_STAGE7_PROTEIN_FDR -ErrorAction SilentlyContinue
    }
    $rustWall = $r.wall
    $rustPrec = Get-PrecursorCount -LogPath $r.logPath
    Write-Host ("  Rust wall: {0}; precursors: {1}; blib: {2}" -f `
        (Format-Duration $r.wall), $rustPrec, (Get-Item $rustBlib).Length) -ForegroundColor Green
}

$csBlib = Join-Path $csDir 'output.blib'
$csDump = Join-Path $csDir 'cs_stage7_protein_fdr.tsv'
$csLog  = Join-Path $csDir 'ospreysharp.log'

if ($SkipCs -and (Test-Path $csBlib) -and (Test-Path $csDump)) {
    Write-Host "[C#] -SkipCs: reusing $csBlib" -ForegroundColor DarkGray
    $csWall = [TimeSpan]::Zero
} else {
    if (Test-Path $csDir) { Remove-Item $csDir -Recurse -Force }
    New-Item -ItemType Directory -Path $csDir -Force | Out-Null
    Stage-DatasetFiles -Dir $csDir
    Write-Host "[C#] OspreySharp -i mzMLs ... (in-memory straight-through) ..." -ForegroundColor Cyan
    $args2 = @()
    foreach ($f in $mzmls) { $args2 += @('-i', $f) }
    $args2 += @('-l', $libraryName, '-o', 'output.blib',
                '--resolution', $resolution,
                '--protein-fdr', '0.01', '--threads', $Threads.ToString())
    $env:OSPREY_DUMP_STAGE7_PROTEIN_FDR = '1'
    try {
        $r = Invoke-Tool -Exe $ospreyShExe -WorkDir $csDir -CliArgs $args2 -LogName 'ospreysharp.log'
    } finally {
        Remove-Item Env:OSPREY_DUMP_STAGE7_PROTEIN_FDR -ErrorAction SilentlyContinue
    }
    $csWall = $r.wall
    $csPrec = Get-PrecursorCount -LogPath $r.logPath
    Write-Host ("  C# wall: {0}; precursors: {1}; blib: {2}" -f `
        (Format-Duration $r.wall), $csPrec, (Get-Item $csBlib).Length) -ForegroundColor Green
}

# ----- COMPARE -----
Write-Host ""
Write-Host "=== Cross-impl comparison (Rust in-memory vs C# in-memory) ===" -ForegroundColor Cyan

$rustPrec = if (Test-Path $rustLog) { Get-PrecursorCount -LogPath $rustLog } else { -1 }
$csPrec   = if (Test-Path $csLog)   { Get-PrecursorCount -LogPath $csLog }   else { -1 }
$precDelta = $csPrec - $rustPrec
$precOk = ($rustPrec -ge 0 -and $csPrec -ge 0 -and [Math]::Abs($precDelta) -le 0)
Write-Host ("    precursors: rust={0}  cs={1}  delta={2}" -f $rustPrec, $csPrec, $precDelta) `
    -ForegroundColor $(if ($precOk) { 'Green' } else { 'Yellow' })

$rustBlibLen = (Get-Item $rustBlib).Length
$csBlibLen   = (Get-Item $csBlib).Length
$blibSizeDelta = $csBlibLen - $rustBlibLen
Write-Host ("    blib size: rust={0}b  cs={1}b  delta={2}b" -f $rustBlibLen, $csBlibLen, $blibSizeDelta) `
    -ForegroundColor $(if ($blibSizeDelta -eq 0) { 'Green' } else { 'Yellow' })

# Stage 7 protein FDR dump (per-column 1e-9)
$stage7Cmp = Join-Path $scriptDir 'Compare-Stage7-Crossimpl.ps1'
$stage7Log = Join-Path $rootDir 'stage7_compare.log'
Write-Host "    Comparing Stage 7 protein FDR dumps (Compare-Stage7-Crossimpl.ps1)..." -ForegroundColor DarkGray
& pwsh -File $stage7Cmp -RustTsv $rustDump -CsTsv $csDump *>&1 |
    Tee-Object -FilePath $stage7Log | Out-Null
$stage7Ok = ($LASTEXITCODE -eq 0)
Write-Host ("    Stage 7 protein FDR (per-col 1e-9): {0}  ({1})" -f `
    $(if ($stage7Ok) { 'PASS' } else { 'FAIL' }), $stage7Log) `
    -ForegroundColor $(if ($stage7Ok) { 'Green' } else { 'Red' })

# Blib content (SQL row+col 1e-9)
$blibCmp = Join-Path $scriptDir 'Compare-Blib-Crossimpl.ps1'
$blibLog = Join-Path $rootDir 'blib_compare.log'
Write-Host "    Comparing blibs (Compare-Blib-Crossimpl.ps1)..." -ForegroundColor DarkGray
& pwsh -File $blibCmp -RustBlib $rustBlib -CsBlib $csBlib *>&1 |
    Tee-Object -FilePath $blibLog | Out-Null
$blibOk = ($LASTEXITCODE -eq 0)
Write-Host ("    Blib content (SQL row+col 1e-9): {0}  ({1})" -f `
    $(if ($blibOk) { 'PASS' } else { 'FAIL' }), $blibLog) `
    -ForegroundColor $(if ($blibOk) { 'Green' } else { 'Red' })

Write-Host ""
if ($precOk -and $stage7Ok -and $blibOk) {
    Write-Host "OVERALL: PASS  -- Rust and C# end-to-end in-memory bit-parity at 1e-9 on $Dataset $($mzmls.Count)-file" -ForegroundColor Green
    Write-Host ("  Walls: Rust {0}, C# {1}" -f (Format-Duration $rustWall), (Format-Duration $csWall))
    exit 0
} else {
    Write-Host "OVERALL: FAIL  -- Rust and C# end-to-end in-memory diverge on $Dataset $($mzmls.Count)-file" -ForegroundColor Red
    Write-Host "  This is the hardest cross-impl gate; failure means cross-impl drift compounds"
    Write-Host "  beyond 1e-9 by end of pipeline. Use the per-stage gates (Test-Regression.ps1)"
    Write-Host "  to localize where drift first exceeds tolerance."
    exit 1
}
