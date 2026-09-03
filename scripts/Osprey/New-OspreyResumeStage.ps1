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
    # WHICH artifact KeepFraction thins. Defaulted to the 1st-pass sidecar so every existing
    # caller is unaffected, but it must be a parameter: the partial-resume case that matters is
    # not always FirstPassFDR's. A rescore interrupted mid-cohort leaves the PerFileRescoring
    # set partial instead, and that is the state the 2026-09-03 `anyPass2Present` defect hid in -
    # a resume that read 141 of 446 as "done" and rescored nothing. Staging it needs
    # -PartialSuffixes '.scores-reconciled.parquet','.2nd-pass.fdr_scores.bin',... with the
    # PerFileRescoring markers alongside.
    [string[]]$PartialSuffixes = @('.1st-pass.fdr_scores.bin'),
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
        if (($PartialSuffixes -contains $suf) -and $sidecarStems -notcontains $stem) { continue }
        $src = Join-Path $Source ($stem + $suf)
        if (-not (Test-Path $src)) { continue }
        New-Item -ItemType HardLink -Path (Join-Path $dest ($stem + $suf)) -Target $src | Out-Null
        $linked++
        if ($StampKey -and ($PartialSuffixes -contains $suf)) {
            # Written fresh, not linked: a marker must belong to THIS directory, so that
            # deleting the staging copy can never reach back and invalidate the source.
            @{ task = 'FirstPassFDR'; version = $Version; validity_key = $StampKey; inputs = @() } |
                ConvertTo-Json | Set-Content -Path (Join-Path $dest ($stem + $suf + '.FirstPassFDR.osprey.task'))
            $stamped++
        }
    }
}
# Analysis-wide artifacts, not per stem. Matched by GLOB on the suffix rather than by literal
# name, the way OspreyDatasetRun.psm1's relay does: the stem is the SOURCE run's output blib name
# and need not be 'out', so a literal bound this to one naming convention.
#
# retained_base_ids was missing here and that was not cosmetic. The per-run rescore REFUSES to
# run without it - deliberately, because a silent fallback would rebuild the union from every
# envelope and restore the O(files) pre-pass the artifact exists to delete - so a directory
# staged by this script could not exercise the per-run path at all. The list stopped being
# complete the moment the artifact became required, which is the "one edit PER PRODUCER" trap:
# the producers of a relay obligation are not co-located with the relay.
$wideSuffixes = @('.1st-pass.fdr_experiment.bin', '.1st-pass.retained_base_ids.bin')
foreach ($suffix in $wideSuffixes) {
    $found = @(Get-ChildItem (Join-Path $Source ('*' + $suffix)) -File -ErrorAction SilentlyContinue |
               Where-Object { $_.Name -notlike '*.osprey.task' } | Select-Object -First 1)
    if ($found.Count -eq 0) {
        Write-Host ("  WARNING: no analysis-wide '{0}' in the source" -f $suffix) -ForegroundColor Yellow
        continue
    }
    $f = $found[0].Name
    $src = $found[0].FullName
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
