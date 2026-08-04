<#
.SYNOPSIS
    Re-stamp the TDP-43 Stage 1-4 staging directory so -LinkFrom resumes again.

.DESCRIPTION
    The Stages1to4 staging directory exists so a Stage 5/6 measurement costs ~70 minutes
    instead of hours: -LinkFrom hard-links its .scores.parquet / .calibration.json (plus
    their .osprey.task stamps) into a fresh run, and Osprey skips PerFileScoring.

    pwiz cb9b68c60 made the peak-pick model participate in the resume validity key
    UNCONDITIONALLY (OspreyTask.ValidityKey -> OspreyEnvironment.PickValidityKeySuffix), so
    every stamp written before it lacks ';pick=lda;pickmodel=none' and is invalidated exactly
    once. The failure is SILENT - the run simply starts scoring file 1/N and takes hours - so
    it reads like a code bug rather than a stale cache.

    This builds a sibling directory with the term appended:
      * artifacts (.scores.parquet, .calibration.json) are HARD LINKS - no copy, no disk cost
      * .osprey.task stamps are patched COPIES

    Appending the term RECORDS WHAT IS TRUE rather than defeating the guard: the staged
    artifacts are byte-identical to the tdp43-163files-...-picklda run's, so they really were
    picked by the LDA model. Only run this when that is the case for your source.

    Patching the source directory IN PLACE would be wrong: its artifacts are hard links shared
    with that 163-file run, so an in-place edit rewrites that run's provenance too.

.EXAMPLE
    pwsh -File ./ai/scripts/Osprey/TDP43/Repair-Stages1to4Stamps.ps1
    # then: Run-Tdp43.ps1 -NumFiles 40 -PickLda -LinkFrom <the -picklda dir> ...
#>
param(
    [string]$Source = 'D:\test\osprey-runs\tdp43-plasma-ev\runs\Stages1to4',
    [string]$Destination = 'D:\test\osprey-runs\tdp43-plasma-ev\runs\Stages1to4-picklda',
    [string]$Suffix = ';pick=lda;pickmodel=none'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $Source)) {
    throw "Source staging directory not found: $Source"
}
if (Test-Path $Destination) {
    Remove-Item $Destination -Recurse -Force
}
New-Item -ItemType Directory -Path $Destination | Out-Null

$linked = 0
$patched = 0
$already = 0
foreach ($f in Get-ChildItem -File $Source) {
    $target = Join-Path $Destination $f.Name
    if ($f.Name -like '*.osprey.task') {
        $j = Get-Content $f.FullName -Raw | ConvertFrom-Json
        if ($j.validity_key -like "*$Suffix*") {
            $already++
        } else {
            $j.validity_key = $j.validity_key + $Suffix
            $patched++
        }
        $j | ConvertTo-Json -Depth 10 | Set-Content -Path $target -Encoding utf8
    } else {
        New-Item -ItemType HardLink -Path $target -Target $f.FullName | Out-Null
        $linked++
    }
}

Write-Host "Source      : $Source"
Write-Host "Destination : $Destination"
Write-Host "hard-linked artifacts : $linked"
Write-Host "patched stamps        : $patched"
Write-Host "already had suffix    : $already"
Write-Host ''
Write-Host "Now pass -LinkFrom '$Destination' to Run-Tdp43.ps1."
