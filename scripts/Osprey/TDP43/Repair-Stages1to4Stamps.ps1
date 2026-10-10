#requires -Version 7
<#
.SYNOPSIS
    Re-stamp the TDP-43 Stage 1-4 staging directory so -LinkFrom resumes again.

.DESCRIPTION
    LEGACY DIRECTORIES ONLY. This applies only to staging directories written by Osprey builds
    from BEFORE embedded validity stamps - directories that still hold
    <artifact>.<Task>.osprey.task sidecar files. Current builds write no such files: each
    artifact carries its stamp INSIDE itself (the .calibration.json first property, the
    .scores.parquet 'osprey.validity' footer entry), and changing it would mean rewriting the
    artifact rather than patching a copy of a small JSON file. For those newer directories the
    supported route for reuse across builds is OSPREY_VERSION_OVERRIDE; a validity-key change
    (like the one below) means the artifacts must be recomputed. A -Source with no .osprey.task
    files is reported and left alone (exit 0, no destination written). A current build reads
    legacy directories as stale regardless, so this is useful only with a build that still
    reads .osprey.task files.

    The Stages1to4 staging directory exists so a Stage 5/6 measurement costs ~70 minutes
    instead of hours: -LinkFrom hard-links its .scores.parquet / .calibration.json (plus
    their .osprey.task stamps) into a fresh run, and Osprey skips PerFileScoring. NOTE: the
    current OspreyDatasetRun.psm1 -LinkFrom no longer links .osprey.task files at all, so the
    patched stamps this writes travel only with an older copy of that module or a manual link.

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

# Checked BEFORE the destination is touched: a source with embedded stamps has nothing this
# script can patch, and deleting/recreating -Destination for it would only destroy work.
if (-not (Get-ChildItem -LiteralPath $Source -File -Filter '*.osprey.task' -ErrorAction SilentlyContinue |
          Select-Object -First 1)) {
    Write-Host ("No .osprey.task files in $Source - nothing to re-stamp. This script applies only " +
                "to directories written before embedded validity stamps; for newer directories " +
                "use OSPREY_VERSION_OVERRIDE (version) or recompute (validity-key change).")
    return
}

# REFUSE to write into the source. The next statement deletes $Destination recursively, so
# -Destination $Source would destroy the very staging directory this script exists to
# preserve - and then report "hard-linked artifacts : 0 / patched stamps : 0" and exit 0,
# because the loop below would find an empty directory. That is not hypothetical: the
# .DESCRIPTION above spends a paragraph on why in-place patching is wrong, which makes
# passing the source path here a plausible mis-keying rather than an absurd one.
#
# Compared by resolved path, not by string: a trailing separator, a case difference, a
# short (8.3) name, or an NTFS junction all reach the same directory while comparing
# unequal as text.
$sourceResolved = (Resolve-Path -LiteralPath $Source).ProviderPath.TrimEnd('\', '/')
if (Test-Path -LiteralPath $Destination) {
    $destResolved = (Resolve-Path -LiteralPath $Destination).ProviderPath.TrimEnd('\', '/')
    if ($sourceResolved -eq $destResolved) {
        throw ("-Destination resolves to the same directory as -Source ($sourceResolved). " +
               "This script builds a SEPARATE re-stamped directory; writing into the source " +
               "would delete the staging artifacts it is meant to preserve.")
    }
    Remove-Item -LiteralPath $Destination -Recurse -Force
}
New-Item -ItemType Directory -Path $Destination | Out-Null

# The four suffixes -LinkFrom actually adopts (OspreyDatasetRun.psm1). Without an allowlist a
# stray run.log / out.blib / model-diagnostics sidecar from the source gets linked in too, and
# a model-diagnostics sidecar is what the arm-completeness checks test for.
$adoptedSuffixes = @('.scores.parquet', '.calibration.json')

$linked = 0
$patched = 0
$already = 0
$skipped = 0
foreach ($f in Get-ChildItem -File $Source) {
    $target = Join-Path $Destination $f.Name
    if ($f.Name -like '*.osprey.task') {
        $j = Get-Content $f.FullName -Raw | ConvertFrom-Json
        # A truncated or empty stamp yields $null here, and $null.validity_key would throw
        # naming neither the file nor the directory - mid-loop, leaving a half-built
        # destination that -LinkFrom accepts and then silently re-scores for hours.
        if ($null -eq $j -or -not $j.PSObject.Properties['validity_key']) {
            throw "Stamp has no validity_key (empty or truncated?): $($f.FullName)"
        }
        if ($j.validity_key -like "*$Suffix*") {
            $already++
        } else {
            $j.validity_key = $j.validity_key + $Suffix
            $patched++
        }
        $j | ConvertTo-Json -Depth 10 | Set-Content -Path $target -Encoding utf8
    } elseif ($adoptedSuffixes | Where-Object { $f.Name.EndsWith($_) }) {
        New-Item -ItemType HardLink -Path $target -Target $f.FullName | Out-Null
        $linked++
    } else {
        $skipped++
    }
}

Write-Host "Source      : $Source"
Write-Host "Destination : $Destination"
Write-Host "hard-linked artifacts : $linked"
Write-Host "patched stamps        : $patched"
Write-Host "already had suffix    : $already"
Write-Host "skipped (not adopted) : $skipped"
if ($linked -eq 0 -or $patched + $already -eq 0) {
    throw ("Produced $linked artifact(s) and $($patched + $already) stamp(s) - that is not a " +
           "usable staging directory. Check that -Source really holds the Stage 1-4 outputs.")
}
Write-Host ''
Write-Host "Now pass -LinkFrom '$Destination' to Run-Tdp43.ps1."
