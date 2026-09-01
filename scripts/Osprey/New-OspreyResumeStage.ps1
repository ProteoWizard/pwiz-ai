<#
.SYNOPSIS
    Build a DISPOSABLE Osprey run directory from an existing one, using hard links.

.DESCRIPTION
    Never iterate in the directory that took hours to produce. A coding error in the code
    under test - and there has already been one, a blanket marker wipe that destroyed a
    44-minute plate run's resume state - then costs a fresh staging directory instead of a
    fresh run.

    Hard links are safe here for the same reason the resume design works at all: every Osprey
    artifact is committed through FileSaver, i.e. written to a temp name and RENAMED over the
    target. A rename replaces the directory entry, so a task writing "over" a hard link leaves
    the source inode untouched and simply breaks the link. Nothing the run does can reach back
    into the source directory.

.PARAMETER Source
    The completed run directory to stage from.

.PARAMETER Name
    Directory name to create under the same runs root.

.PARAMETER Include
    Artifact suffixes to link. Defaults to everything FirstPassFDR needs as INPUT: the Stage 1-4
    parquets and calibrations with their PerFileScoring markers, the 1st-pass sidecars, the
    per-file .1st-pass.model.json (without which a fully-resumable run retrains a model it has
    already persisted), and the analysis-wide experiment sidecar.

.PARAMETER KeepFraction
    Fraction of the per-file 1st-pass sidecars to carry across (1.0 = all). Use e.g. 0.9 to stage
    the partial-resume case: the missing tenth must be re-scored and the rest adopted.

.PARAMETER StampKey
    Validity key to write into a `<file>.FirstPassFDR.osprey.task` marker beside each staged
    1st-pass sidecar. Osprey normally writes these itself as each sidecar lands; supply one here
    to make a directory written by an older build resumable. The key must be the one THIS cohort
    produces - the reconciliation term is hashed over the sorted input file stems, so a key
    borrowed from a different file set is the one mistake that matters.

.EXAMPLE
    New-OspreyResumeStage.ps1 -Source <plate-dir> -Name guard-test-100 -StampKey 'search=...'
#>
#requires -Version 7
param(
    [Parameter(Mandatory)] [string]$Source,
    [Parameter(Mandatory)] [string]$Name,
    [string[]]$Include = @('.scores.parquet', '.scores.parquet.PerFileScoring.osprey.task',
                           '.calibration.json', '.calibration.json.PerFileScoring.osprey.task',
                           '.1st-pass.fdr_scores.bin',
                           '.1st-pass.model.json'),
    [double]$KeepFraction = 1.0,
    [string]$StampKey,
    [string]$Version = '26.1.1.243'
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $Source)) { throw "Source not found: $Source" }
$dest = Join-Path (Split-Path $Source -Parent) $Name
if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
New-Item -ItemType Directory -Path $dest -Force | Out-Null

$stems = Get-ChildItem $Source -Filter '*.scores.parquet' -File |
         Where-Object { $_.Name -notlike '*.osprey.task' } |
         ForEach-Object { $_.Name -replace '\.scores\.parquet$', '' } | Sort-Object
$keep = [Math]::Max(1, [int][Math]::Round($stems.Count * $KeepFraction))
$sidecarStems = @($stems | Select-Object -First $keep)

$linked = 0; $stamped = 0
foreach ($stem in $stems) {
    foreach ($suf in $Include) {
        # The per-file sidecar is the one artifact the KeepFraction applies to; everything else
        # is FirstPassFDR input and must be complete or the run is not comparable.
        if ($suf -eq '.1st-pass.fdr_scores.bin' -and $sidecarStems -notcontains $stem) { continue }
        $src = Join-Path $Source ($stem + $suf)
        if (-not (Test-Path $src)) { continue }
        New-Item -ItemType HardLink -Path (Join-Path $dest ($stem + $suf)) -Target $src | Out-Null
        $linked++
        if ($StampKey -and $suf -eq '.1st-pass.fdr_scores.bin') {
            # Written fresh, not linked: a marker must belong to THIS directory, so that
            # deleting the staging copy can never reach back and invalidate the source.
            @{ task = 'FirstPassFDR'; version = $Version; validity_key = $StampKey; inputs = @() } |
                ConvertTo-Json | Set-Content -Path (Join-Path $dest ($stem + $suf + '.FirstPassFDR.osprey.task'))
            $stamped++
        }
    }
}
# Analysis-wide artifacts, not per stem.
foreach ($f in 'out.1st-pass.fdr_experiment.bin') {
    $src = Join-Path $Source $f
    if (Test-Path $src) {
        New-Item -ItemType HardLink -Path (Join-Path $dest $f) -Target $src | Out-Null
        $linked++
        if ($StampKey) {
            @{ task = 'FirstPassFDR'; version = $Version; validity_key = $StampKey; inputs = @() } |
                ConvertTo-Json | Set-Content -Path (Join-Path $dest ($f + '.FirstPassFDR.osprey.task'))
            $stamped++
        }
    }
}

'staged   : {0}' -f $dest
'stems    : {0}  (sidecars for {1})' -f $stems.Count, $sidecarStems.Count
'links    : {0}   markers stamped: {1}' -f $linked, $stamped
'disk     : {0:N2} GB of hard links (costs nothing)' -f `
    ((Get-ChildItem $dest -File | Measure-Object Length -Sum).Sum / 1GB)
