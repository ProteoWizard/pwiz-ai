<#
.SYNOPSIS
    Build a library variant (entrapment ratio subset, or the gendecoy arm's
    decoy-stripped library) from a delivered 1:1 target+decoy+entrapment set.

.DESCRIPTION
    Only ONE library is downloaded: the r=1.0 target+decoy+entrapment set. Every other
    variant is derived from it, and this script owns the naming convention that the
    runners resolve (Run-SeaAd.ps1, TDP43\Run-Tdp43.ps1 via Common\OspreyDatasetRun.psm1),
    so -Ratio and -DecoyMode stay plain parameters on both sides instead of a path to
    remember:

        target+decoy+entrapment              r=1.0 libdecoy (the delivered source)
        target+decoy+entrapment-r<ratio>     fractional libdecoy
        target+entrapment-r<ratio>-gendecoy  gendecoy arm (decoy rows stripped)

    The work is done by the dataset-agnostic ..\Library\Build-EntrapmentVariant.py; this
    wrapper only maps the convention onto its --source-dir / --output-dir / --ratio /
    --salt / --gendecoy. Both arms are built straight from the r=1.0 source. Selection is
    a stable hash of each peptide_pair_index, so a gendecoy variant carries exactly the
    entrapment peptides of the libdecoy variant at the same ratio and salt - the two arms
    differ only in where the decoys come from - without the libdecoy variant having to
    exist on disk.

    Selection is deterministic and nested: the same ratio built on two machines picks the
    same pairs, and r=0.1 is a subset of r=0.25 is a subset of r=0.5.

.PARAMETER Ratio
    Target entrapment ratio. '1.0' is the delivered set; a fraction subsets it.

.PARAMETER DecoyMode
    libdecoy : keep the library's Carafe decoys (subset only).
    gendecoy : additionally strip the decoy rows so Osprey generates its own.

.PARAMETER LibraryRoot
    Directory holding the variants. Defaults to $env:OSPREY_SEAAD_LIB.

.PARAMETER Build
    Which delivered r=1.0 set to derive from: empty is 'target+decoy+entrapment', and a
    value such as '20260817' is 'target+decoy+entrapment-20260817'. The tag carries into
    every derived name, so variants of two builds never share a folder.

.PARAMETER Salt
    Selection salt (letters/digits). Empty (the default) is the series every run so far
    uses. A non-empty salt is an independent draw at the same ratio and is appended to the
    ratio in the folder name: -Ratio 0.5 -Salt b is 'target+decoy+entrapment-r0.5b'. The
    runners do not resolve salted names; pass the folder with -LibraryDir.

.PARAMETER Seed
    Obsolete. The seeded-shuffle selection it controlled was retired 2026-10-05 (it chose
    a different subset from the libraries actually in use). Passing it is an error.

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
    [string]$Build = '',
    [ValidatePattern('^[A-Za-z0-9]*$')] [string]$Salt = '',
    [Nullable[int]]$Seed,
    [string]$Python,
    [switch]$Force,
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
$readme = Join-Path $PSScriptRoot 'README.md'
$builder = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\Library\Build-EntrapmentVariant.py'))

if ($null -ne $Seed) {
    throw ("-Seed is obsolete: the seeded-shuffle selection was retired because it picks a " +
           "different subset from the libraries in use. Use -Salt for an independent draw. " +
           "See $readme.")
}
if ($Ratio -eq '1.0' -and $Salt) {
    Write-Warning "-Salt has no effect at -Ratio 1.0 (every pair is kept); ignoring it."
    $Salt = ''
}

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
    param([string]$Mode, [string]$R, [string]$S = '')
    $b = if ($Build) { "-$Build" } else { '' }
    $name = if ($Mode -eq 'gendecoy') {
        "target+entrapment-r$R$S$b-gendecoy"
    } elseif ($R -eq '1.0') {
        "target+decoy+entrapment$b"
    } else {
        "target+decoy+entrapment$b-r$R$S"
    }
    Join-Path $LibraryRoot $name
}

$source = Get-VariantPath -Mode 'libdecoy' -R '1.0'
if (-not (Test-Path (Join-Path $source 'carafe_spectral_library.tsv'))) {
    throw ("The delivered r=1.0 set is missing at '$source'. Every variant derives from " +
           "it; download it first. See $readme for the URL.")
}

$target = Get-VariantPath -Mode $DecoyMode -R $Ratio -S $Salt
if ($target -eq $source) {
    Write-Host "Nothing to build: r=1.0 libdecoy is the delivered set itself ('$source')." -ForegroundColor Green
    return
}
# PROVENANCE.txt is written last, so its presence is what marks a finished build. Older
# variants (built before 2026-10-05) have none; for those the library file stands in.
$done = (Test-Path (Join-Path $target 'PROVENANCE.txt')) -or
        (Test-Path (Join-Path $target 'carafe_spectral_library.tsv'))
if ($done -and -not $Force) {
    Write-Host "Nothing to build: '$target' already exists (use -Force to rebuild)." -ForegroundColor Green
    return
}

$pyArgs = @($builder, 'build', '--source-dir', $source, '--output-dir', $target, '--ratio', $Ratio)
if ($Salt) { $pyArgs += @('--salt', $Salt) }   # omitted when empty: the script defaults to ''
if ($DecoyMode -eq 'gendecoy') { $pyArgs += '--gendecoy' }

Write-Host ""
Write-Host "=== library variant build ===" -ForegroundColor Cyan
Write-Host ("  root   : {0}" -f $LibraryRoot)
Write-Host ("  source : {0}" -f (Split-Path $source -Leaf))
Write-Host ("  target : {0}  (r={1}, {2}, salt '{3}')" -f (Split-Path $target -Leaf), $Ratio, $DecoyMode, $Salt)
Write-Host ("  command: {0} {1}" -f $Python, ($pyArgs -join ' '))
Write-Host ""

if ($WhatIf) {
    Write-Host "-WhatIf: nothing built." -ForegroundColor Yellow
    return
}

$sw = [Diagnostics.Stopwatch]::StartNew()
& $Python @pyArgs
if ($LASTEXITCODE -ne 0) { throw "Build-EntrapmentVariant.py failed ($LASTEXITCODE)." }
$sw.Stop()

$sizeGb = [math]::Round((Get-Item (Join-Path $target 'carafe_spectral_library.tsv')).Length / 1GB, 2)
Write-Host ("Built: {0}  ({1:hh\:mm\:ss}, library {2} GB)" -f $target, $sw.Elapsed, $sizeGb) -ForegroundColor Green
Write-Host ("Run it with: .\Run-SeaAd.ps1 -DecoyMode {0} -Ratio {1}" -f $DecoyMode, $Ratio)
