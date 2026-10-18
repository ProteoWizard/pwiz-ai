<#
.SYNOPSIS
    Time Osprey's library load (the .tsv or .blib parse, or the .libcache read) in isolation.

.DESCRIPTION
    Runs `Osprey.exe -l <library> --export-library ... --perf-stats` once per rep, each rep in a
    fresh work directory so no library cache is hit, and prints the `[TIMING] Library parse:` (or
    `Library cache read:`) line of each rep. The export is the lightest command that loads a
    library and nothing else; its own write is after the measured line and is not reported.

    With -WarmCache, each rep's work directory is reused from a first unmeasured run, so the
    reported line is the cache read (`.libcache`, or the derived .blib once that replaces it).

    Use for an A/B of two builds on one library: pass each build's snapshot as -Exe (see
    "Snapshot the exe first" in osprey-development-guide.md) and the same -OutDir root with a
    different -Tag.

.PARAMETER Exe
    The Osprey.exe to time. Default: the Release build of <SourceRoot>.

.PARAMETER Library
    The library to load (.tsv or .blib).

.PARAMETER OutDir
    Root for the per-rep work directories and logs (<OutDir>\<Tag>\rep<N>\run.log).

.PARAMETER Tag
    Name of this measurement under -OutDir (a build tag: "base", "parallel-decode").

.PARAMETER Reps
    Repetitions. Default 3.

.PARAMETER Resolution
    --resolution for the load (unit or hram). Default unit.

.PARAMETER Threads
    --threads. Default 16.

.PARAMETER WarmCache
    Measure the cache read rather than the parse: run once unmeasured, then time -Reps reads.

.PARAMETER ExtraArgs
    Further Osprey arguments (for example --decoys-in-library, --decoy-pairing-manifest <path>).

.EXAMPLE
    pwsh -File C:/proj/ai/scripts/Osprey/Measure-LibraryLoad.ps1 -Exe D:\test\osprey-runs\_bin\20261018-base\Osprey.exe `
        -Library D:\test\osprey-runs\blib-as-cache\hela.blib -OutDir D:\test\osprey-runs\blib-as-cache -Tag base
#>
param(
    [string]$Exe,
    [Parameter(Mandatory = $true)][string]$Library,
    [Parameter(Mandatory = $true)][string]$OutDir,
    [string]$Tag = 'run',
    [int]$Reps = 3,
    [ValidateSet('unit', 'hram')][string]$Resolution = 'unit',
    [int]$Threads = 16,
    [switch]$WarmCache,
    [string[]]$ExtraArgs = @(),
    [string]$SourceRoot = 'C:\proj\pwiz'
)

$ErrorActionPreference = 'Stop'

if (-not $Exe) {
    $Exe = Join-Path $SourceRoot 'pwiz_tools\Osprey\Osprey\bin\x64\Release\net10.0\Osprey.exe'
}
if (-not (Test-Path $Exe)) { throw "Osprey.exe not found: $Exe" }
if (-not (Test-Path $Library)) { throw "Library not found: $Library" }

$tagDir = Join-Path $OutDir $Tag
New-Item -ItemType Directory -Force $tagDir | Out-Null

function Invoke-Load([string]$workDir, [string]$log) {
    $args = @('-l', $Library, '--export-library', (Join-Path $workDir 'export.blib'),
              '--resolution', $Resolution, '--threads', $Threads.ToString(),
              '--work-dir', $workDir, '--timestamp', '--perf-stats') + $ExtraArgs
    & $Exe @args > $log 2>&1
    if ($LASTEXITCODE -ne 0) {
        Get-Content $log -Tail 20 | Write-Host
        throw "Osprey exited $LASTEXITCODE (log: $log)"
    }
}

Write-Host "Timing $Reps load(s) of $(Split-Path $Library -Leaf) with $Exe"
$results = @()
for ($i = 1; $i -le $Reps; $i++) {
    $repDir = Join-Path $tagDir "rep$i"
    if (Test-Path $repDir) { Remove-Item $repDir -Recurse -Force }
    New-Item -ItemType Directory -Force $repDir | Out-Null
    if ($WarmCache) {
        Invoke-Load $repDir (Join-Path $repDir 'warm.log')
        Remove-Item (Join-Path $repDir 'export.blib') -Force -ErrorAction SilentlyContinue
    }
    $log = Join-Path $repDir 'run.log'
    Invoke-Load $repDir $log
    $lines = Select-String -Path $log -Pattern '\[TIMING\] Library (parse|cache read):|Loaded .* from cache|Typed ' |
        ForEach-Object { $_.Line -replace '^\[[^\]]+\]\s+', '' }
    foreach ($line in $lines) { Write-Host "  rep${i}: $line" }
    $timing = $lines | Where-Object { $_ -match '\[TIMING\] Library (parse|cache read): ([\d.]+)s' } | Select-Object -First 1
    if ($timing -match '([\d.]+)s') { $results += [double]$Matches[1] }
}
if ($results.Count -gt 0) {
    $sorted = $results | Sort-Object
    $median = $sorted[[int][math]::Floor(($sorted.Count - 1) / 2)]
    Write-Host ("{0}: median {1:F2}s (min {2:F2}s, max {3:F2}s) over {4} rep(s); logs under {5}" -f
        $Tag, $median, $sorted[0], $sorted[-1], $results.Count, $tagDir)
}
