<#
.SYNOPSIS
    Build a SEA-AD library variant (entrapment ratio subset, or the gendecoy arm's
    decoy-stripped library) from the delivered 1:1 target+decoy+entrapment set.

.DESCRIPTION
    Only ONE library is downloaded: the r=1.0 target+decoy+entrapment set. Every other
    variant is derived from it, and this script owns the naming convention that
    Run-SeaAd.ps1 resolves, so -Ratio and -DecoyMode stay plain parameters on both sides
    instead of a path to remember:

        target+decoy+entrapment              r=1.0 libdecoy (the delivered source)
        target+decoy+entrapment-r<ratio>     fractional libdecoy  (subset-entrapment-ratio.py)
        target+entrapment-r<ratio>-gendecoy  gendecoy arm         (strip-decoys.py)

    A gendecoy variant is derived from the libdecoy variant at the SAME ratio, which is
    built first if it does not exist. That chaining is the point: the two arms then differ
    only in where the decoys come from, not in which entrapment peptides are present.

    Derivation is deterministic (seeded shuffle, default 2024), so the same ratio built on
    two machines selects the same quartets and the runs are comparable across boxes.

.PARAMETER Ratio
    Target entrapment ratio. '1.0' is the delivered set; a fraction subsets it.

.PARAMETER DecoyMode
    libdecoy : keep the library's Carafe decoys (subset only).
    gendecoy : additionally strip the decoy rows so Osprey generates its own.

.PARAMETER LibraryRoot
    Directory holding the variants. Defaults to -LibraryDir / $env:OSPREY_SEAAD_LIB.

.EXAMPLE
    # Both arms of a decoy A/B at r=0.1, from the delivered 1:1 set.
    .\New-SeaAdLibrary.ps1 -Ratio 0.1 -DecoyMode libdecoy
    .\New-SeaAdLibrary.ps1 -Ratio 0.1 -DecoyMode gendecoy

.NOTES
    Expect this to be slow and large: the source library is ~13 GB and each variant is a
    full copy, streamed. Check free space before building several.

    A freshly built variant has no .libcache beside it; Osprey builds one on first use,
    which makes that first run slower than later ones against the same variant.
#>
#requires -Version 7
param(
    [Parameter(Mandatory)][string]$Ratio,
    [ValidateSet('libdecoy', 'gendecoy')] [string]$DecoyMode = 'libdecoy',
    [string]$LibraryRoot,
    [int]$Seed = 2024,
    [string]$Python,
    [switch]$Force,
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
$readme = Join-Path $PSScriptRoot 'README.md'
$tools = Join-Path $PSScriptRoot 'tools'

if (-not $LibraryRoot) { $LibraryRoot = [Environment]::GetEnvironmentVariable('OSPREY_SEAAD_LIB') }
if (-not $LibraryRoot -or -not (Test-Path $LibraryRoot)) {
    throw ("Could not locate the SEA-AD library root. Pass -LibraryRoot, or set " +
           "`$env:OSPREY_SEAAD_LIB. See $readme.")
}
$LibraryRoot = (Resolve-Path $LibraryRoot).Path

if (-not $Python) {
    $Python = (Get-Command python -ErrorAction SilentlyContinue)?.Source
    if (-not $Python) { $Python = (Get-Command python3 -ErrorAction SilentlyContinue)?.Source }
}
if (-not $Python) { throw "Python not found on PATH. Pass -Python <path to python.exe>." }

function Get-VariantPath {
    param([string]$Mode, [string]$R)
    $name = if ($Mode -eq 'gendecoy') {
        "target+entrapment-r$R-gendecoy"
    } elseif ($R -eq '1.0') {
        'target+decoy+entrapment'
    } else {
        "target+decoy+entrapment-r$R"
    }
    Join-Path $LibraryRoot $name
}

$source = Get-VariantPath -Mode 'libdecoy' -R '1.0'
if (-not (Test-Path (Join-Path $source 'carafe_spectral_library.tsv'))) {
    throw ("The delivered r=1.0 set is missing at '$source'. Every variant derives from " +
           "it; download it first. See $readme for the URL.")
}

# A gendecoy variant strips the libdecoy variant at the same ratio, so build that first.
$steps = @()
$libdecoyDir = Get-VariantPath -Mode 'libdecoy' -R $Ratio
if ($Ratio -ne '1.0' -and -not (Test-Path (Join-Path $libdecoyDir 'carafe_spectral_library.tsv'))) {
    $steps += [pscustomobject]@{ Kind = 'subset'; From = $source; To = $libdecoyDir }
}
if ($DecoyMode -eq 'gendecoy') {
    $gendecoyDir = Get-VariantPath -Mode 'gendecoy' -R $Ratio
    $steps += [pscustomobject]@{ Kind = 'strip'; From = $libdecoyDir; To = $gendecoyDir }
}

$target = Get-VariantPath -Mode $DecoyMode -R $Ratio
if (-not $steps) {
    Write-Host "Nothing to build: '$target' already exists." -ForegroundColor Green
    return
}

Write-Host ""
Write-Host "=== SEA-AD library build ===" -ForegroundColor Cyan
Write-Host ("  root   : {0}" -f $LibraryRoot)
Write-Host ("  target : {0}  (r={1}, {2})" -f (Split-Path $target -Leaf), $Ratio, $DecoyMode)
foreach ($s in $steps) {
    Write-Host ("  step   : {0,-6} {1} -> {2}" -f $s.Kind, (Split-Path $s.From -Leaf), (Split-Path $s.To -Leaf))
}
Write-Host ""

if ($WhatIf) {
    Write-Host "-WhatIf: nothing built." -ForegroundColor Yellow
    return
}

foreach ($s in $steps) {
    if ((Test-Path (Join-Path $s.To 'carafe_spectral_library.tsv')) -and -not $Force) {
        Write-Host ("skip {0}: '{1}' already exists (use -Force to rebuild)" -f $s.Kind, $s.To) -ForegroundColor Yellow
        continue
    }
    New-Item -ItemType Directory -Force -Path $s.To | Out-Null
    $sw = [Diagnostics.Stopwatch]::StartNew()

    if ($s.Kind -eq 'subset') {
        Write-Host ("subsetting to r={0} (seed {1})..." -f $Ratio, $Seed) -ForegroundColor Cyan
        & $Python (Join-Path $tools 'subset-entrapment-ratio.py') `
            --src $s.From --out $s.To --ratio $Ratio --seed $Seed
        if ($LASTEXITCODE -ne 0) { throw "subset-entrapment-ratio.py failed ($LASTEXITCODE)." }
    } else {
        Write-Host "stripping decoy rows..." -ForegroundColor Cyan
        & $Python (Join-Path $tools 'strip-decoys.py') `
            (Join-Path $s.From 'carafe_spectral_library.tsv') `
            (Join-Path $s.To 'carafe_spectral_library.tsv')
        if ($LASTEXITCODE -ne 0) { throw "strip-decoys.py failed ($LASTEXITCODE)." }
        # The manifest travels with the stripped library: it still describes the
        # target/entrapment pairing the FDP oracle reads, and only the decoy arms of it
        # go unused. Copying it keeps the folder self-describing.
        $man = Join-Path $s.From 'osprey_library_db_pairing.tsv'
        if (Test-Path $man) { Copy-Item $man (Join-Path $s.To 'osprey_library_db_pairing.tsv') -Force }
    }

    $sw.Stop()
    $sizeGb = [math]::Round((Get-Item (Join-Path $s.To 'carafe_spectral_library.tsv')).Length / 1GB, 2)
    Write-Host ("  done in {0:hh\:mm\:ss}, library {1} GB" -f $sw.Elapsed, $sizeGb) -ForegroundColor Green
}

Write-Host ""
Write-Host ("Built: {0}" -f $target) -ForegroundColor Green
Write-Host ("Run it with: .\Run-SeaAd.ps1 -DecoyMode {0} -Ratio {1}" -f $DecoyMode, $Ratio)
