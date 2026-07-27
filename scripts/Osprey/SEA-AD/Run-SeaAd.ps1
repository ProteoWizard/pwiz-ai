<#
.SYNOPSIS
    Run Osprey over the SEA-AD Pilot-MTG 82-file Astral DIA set.

.DESCRIPTION
    Resolves the data location instead of hardcoding it, so the same command works on any
    machine that has the set: -DataDir, else $env:OSPREY_SEAAD_DIR, else the lab share.
    Same for the library. Fails with the README pointer when nothing resolves, rather than
    running against a wrong or empty directory.

    See README.md in this folder for where the data lives and the facts worth knowing
    before starting a run (wall time, disk, the threads and --model-diagnostics traps).

.PARAMETER NumFiles
    How many mzML files to process, in sorted order. Default 82 (all). Use a small number
    to smoke-test the wiring before committing to a multi-hour run.

.PARAMETER WhatIf
    Print the resolved paths and the full command line, then stop. Do this first on a new
    machine - it is the cheap way to confirm the data resolved to what you expect.
#>
param(
    [int]$NumFiles = 82,
    [string]$DataDir,
    [string]$LibraryDir,
    [string]$Library,
    [string]$OutDir,
    [int]$Threads = 30,
    [ValidateSet('percolator', 'transfer')] [string]$Pass2Mode = 'percolator',
    # OFF by default and deliberately so: at 82 files it forces the resident first-pass
    # pool at FirstJoin and has OOM'd a 64 GB box. See README.
    [switch]$ModelDiagnostics,
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
$readme = Join-Path $PSScriptRoot 'README.md'

# The lab share, last in precedence. Named here once so the README and the code cannot
# drift apart on the path.
$LAB_SHARE_MZML = 'M:\home\brendanx\data\MacCoss\SEA-AD\Astral-DIA\mzml'

function Resolve-Location {
    param([string]$Explicit, [string]$EnvName, [string[]]$Fallbacks, [string]$What)
    foreach ($c in @($Explicit, [Environment]::GetEnvironmentVariable($EnvName)) + $Fallbacks) {
        if ($c -and (Test-Path $c)) { return (Resolve-Path $c).Path }
    }
    throw ("Could not locate the SEA-AD $What. Pass it explicitly, or set `$env:$EnvName. " +
           "See $readme for the source URLs and the lab-share path.")
}

$dataDir = Resolve-Location -Explicit $DataDir -EnvName 'OSPREY_SEAAD_DIR' `
                            -Fallbacks @($LAB_SHARE_MZML) -What 'mzML directory'
$libDir  = Resolve-Location -Explicit $LibraryDir -EnvName 'OSPREY_SEAAD_LIB' `
                            -Fallbacks @() -What 'library directory'

# Exactly-one-.tsv unless named: an entrapment library folder often also holds a pairing
# manifest and a FASTA, so guessing the first .tsv is how you silently search the wrong one.
if (-not $Library) {
    $tsv = @(Get-ChildItem -Path $libDir -Filter '*.tsv' -File)
    if ($tsv.Count -ne 1) {
        throw ("Expected exactly one .tsv in '$libDir' but found $($tsv.Count). " +
               "Pass -Library <name> to choose (manifests and FASTAs live here too).")
    }
    $libraryPath = $tsv[0].FullName
} else {
    $libraryPath = Join-Path $libDir $Library
    if (-not (Test-Path $libraryPath)) { throw "Library not found: $libraryPath" }
}

$mzmls = @(Get-ChildItem -Path $dataDir -Filter '*.mzML' -File | Sort-Object Name |
           Select-Object -First $NumFiles | ForEach-Object { $_.FullName })
if ($mzmls.Count -eq 0) { throw "No .mzML files found in '$dataDir'." }

# .spectra.bin beside the mzML is the difference between a ~7.5 h run and one that also
# pays ~4.5 min/file of HDD parsing. Worth saying out loud rather than discovering later.
$cached = @(Get-ChildItem -Path $dataDir -Filter '*.spectra.bin' -File).Count

if (-not $OutDir) {
    $stamp = (Get-Date).ToString('yyyyMMdd_HHmmss')
    $OutDir = Join-Path (Join-Path $PSScriptRoot '..\..\..\.tmp') "seaad-$($mzmls.Count)file-$Pass2Mode-$stamp"
}

$ospreyExe = Join-Path $PSScriptRoot '..\..\..\..\pwiz\pwiz_tools\Osprey\Osprey\bin\x64\Release\net8.0\Osprey.exe'
if (-not (Test-Path $ospreyExe)) {
    throw "Osprey.exe not found at $ospreyExe - build Release/net8.0 first (Build-Osprey.ps1)."
}
$ospreyExe = (Resolve-Path $ospreyExe).Path

$cliArgs = @()
foreach ($m in $mzmls) { $cliArgs += @('-i', $m) }
$cliArgs += @('-l', $libraryPath, '-o', 'out.blib', '--resolution', 'hram',
              '--protein-fdr', '0.01', '--threads', $Threads.ToString(),
              '--work-dir', $OutDir, '--timestamp', '--memstamp')
if ($ModelDiagnostics) { $cliArgs += '--model-diagnostics' }

Write-Host ""
Write-Host "=== SEA-AD Pilot-MTG run ===" -ForegroundColor Cyan
Write-Host ("  mzML dir : {0}" -f $dataDir)
Write-Host ("  files    : {0} of $NumFiles requested; {1} .spectra.bin cache(s) present" -f $mzmls.Count, $cached)
if ($cached -lt $mzmls.Count) {
    Write-Host "  NOTE: not every file has a spectra cache; expect ~4.5 min/file extra parse." -ForegroundColor Yellow
}
Write-Host ("  library  : {0}" -f $libraryPath)
Write-Host ("  out dir  : {0}" -f $OutDir)
Write-Host ("  pass 2   : {0}{1}" -f $Pass2Mode, $(if ($ModelDiagnostics) { '  +--model-diagnostics (OOM risk at 82 files)' } else { '' }))
Write-Host ""

if ($WhatIf) {
    Write-Host "-WhatIf: not running. Command would be:" -ForegroundColor Yellow
    Write-Host ("  {0} {1}" -f $ospreyExe, ($cliArgs -join ' '))
    return
}

New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$log = Join-Path $OutDir 'run.log'
if ($Pass2Mode -eq 'transfer') { $env:OSPREY_PASS2_QVALUE = 'transfer' }
else { Remove-Item Env:OSPREY_PASS2_QVALUE -ErrorAction SilentlyContinue }

Write-Host "Logging to $log" -ForegroundColor Cyan
$sw = [Diagnostics.Stopwatch]::StartNew()
& $ospreyExe @cliArgs 2>&1 | Tee-Object -FilePath $log
$exit = $LASTEXITCODE
$sw.Stop()
Write-Host ("Osprey exited {0} after {1:hh\:mm\:ss}" -f $exit, $sw.Elapsed) `
    -ForegroundColor $(if ($exit -eq 0) { 'Green' } else { 'Red' })
exit $exit
