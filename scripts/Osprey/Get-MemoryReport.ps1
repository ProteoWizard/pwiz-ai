<#
.SYNOPSIS
    Extract Osprey memory + stage-timing anchors from one or more run.log files
    and emit a comparison table (markdown).

.DESCRIPTION
    Parses the [MEM ...] probes emitted under OSPREY_LOG_MEMORY=1 and the
    [STAGE-WALL] timings, then prints one column per log so successive runs can
    be compared directly (e.g. before a memory fix vs after).

    Anchors parsed:
      [MEM library-resident] managed_heap=..
      [MEM scored file N/M]  working_set=.. (peak=..), managed_heap=..
      [MEM Stage 5 start: ..] working_set=.. (peak=..), managed_heap=.., peak_paged=..
      [MEM projection built: ..]
      [MEM after first-pass Percolator FDR]
      [MEM after Stage-5 CompactFirstPass]
      [MEM reconciliation-floor]     managed_heap=.. (post-GC ..)
      [MEM reconciliation-resident]  managed_heap=.. (files=..)
      [STAGE-WALL] <stage>: <sec>s
      Coelution analysis complete. <N> total scored entries across <M> files
      [TIMING] Total pipeline: <sec>s

    Scoring is reported as the MAX peak working set across all per-file probes
    (the plateau), not the last one.

.PARAMETER LogPath
    One or more run.log paths. One output column per log.

.PARAMETER Label
    Optional column labels, positionally matched to -LogPath. Defaults to file name.

.EXAMPLE
    # Single run
    pwsh -File ./ai/scripts/Osprey/Get-MemoryReport.ps1 -LogPath C:\temp\osprey-82\run.log

.EXAMPLE
    # Compare two runs side by side
    pwsh -File ./ai/scripts/Osprey/Get-MemoryReport.ps1 `
        -LogPath ai/.tmp/osprey-82-run-logs/run-20260708-allthree-16830934e.log, C:\temp\osprey-82\run.log `
        -Label 'all-three (#4378+#4381+#4376)', 'lean stub (#4397)'
#>
param(
    [Parameter(Mandatory = $true)]
    [string[]]$LogPath,

    [string[]]$Label
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-Gb {
    param([string]$Line, [string]$Key)
    # e.g. "managed_heap=53.13 GB" / "working_set=52.72 GB" / "peak=53.75 GB"
    if ($Line -match "$Key=([0-9]+(?:\.[0-9]+)?)\s*GB") { return [double]$Matches[1] }
    return $null
}

function Read-RunLog {
    param([string]$Path)

    if (-not (Test-Path $Path)) { throw "Log not found: $Path" }

    $r = [ordered]@{
        LibraryResident   = $null
        ScoringPeakWs     = $null   # max peak= across per-file probes
        ScoringMaxHeap    = $null
        Stage5Heap        = $null
        Stage5Ws          = $null
        Stage5PeakPaged   = $null
        Stage5LiveHeap    = $null   # post-forced-GC: the only "will it fit" number
        ProjectionHeap    = $null
        AfterFdrHeap      = $null
        FirstPassLiveHeap = $null   # post-forced-GC
        AfterCompactHeap  = $null
        ReconFloorHeap    = $null
        ReconResidentHeap = $null
        OverallPeakWs     = $null
        OverallPeakPaged  = $null
        ScoredEntries     = $null
        NFiles            = $null
        Stages            = [ordered]@{}
        TotalSec          = $null
    }

    foreach ($line in [System.IO.File]::ReadLines((Resolve-Path $Path))) {

        if ($line -like '*[[]MEM *') {
            $ws   = Get-Gb $line 'working_set'
            $pk   = Get-Gb $line 'peak'
            $heap = Get-Gb $line 'managed_heap'
            $pgd  = Get-Gb $line 'peak_paged'

            if ($null -ne $pk)  { if ($null -eq $r.OverallPeakWs    -or $pk  -gt $r.OverallPeakWs)    { $r.OverallPeakWs    = $pk } }
            if ($null -ne $pgd) { if ($null -eq $r.OverallPeakPaged -or $pgd -gt $r.OverallPeakPaged) { $r.OverallPeakPaged = $pgd } }

            switch -Regex ($line) {
                '\[MEM library-resident\]'            { $r.LibraryResident = $heap }
                '\[MEM scored file \d+/\d+\]'         {
                    if ($null -ne $pk   -and ($null -eq $r.ScoringPeakWs  -or $pk   -gt $r.ScoringPeakWs))  { $r.ScoringPeakWs  = $pk }
                    if ($null -ne $heap -and ($null -eq $r.ScoringMaxHeap -or $heap -gt $r.ScoringMaxHeap)) { $r.ScoringMaxHeap = $heap }
                }
                '\[MEM Stage 5 start'                 { $r.Stage5Heap = $heap; $r.Stage5Ws = $ws; $r.Stage5PeakPaged = $pgd }
                '\[MEM stage5-start-live\]'           { $r.Stage5LiveHeap = $heap }
                '\[MEM projection built'              { $r.ProjectionHeap = $heap }
                '\[MEM after first-pass Percolator'   { $r.AfterFdrHeap = $heap }
                '\[MEM first-pass-fdr-live\]'         { $r.FirstPassLiveHeap = $heap }
                '\[MEM after Stage-5 CompactFirstPass'{ $r.AfterCompactHeap = $heap }
                '\[MEM reconciliation-floor\]'        { $r.ReconFloorHeap = $heap }
                '\[MEM reconciliation-resident\]'     { $r.ReconResidentHeap = $heap }
            }
            continue
        }

        if ($line -match '\[STAGE-WALL\]\s+([A-Za-z0-9\-]+):\s*([0-9.]+)s') {
            $r.Stages[$Matches[1]] = [double]$Matches[2]
            continue
        }

        if ($line -match 'Coelution analysis complete\.\s+(\d+) total scored entries across (\d+) files') {
            $r.ScoredEntries = [long]$Matches[1]
            $r.NFiles = [int]$Matches[2]
            continue
        }

        if ($line -match 'Total pipeline:\s*([0-9.]+)s') {
            $r.TotalSec = [double]$Matches[1]
            continue
        }
    }

    return $r
}

function Format-Gb { param($v) if ($null -eq $v) { '--' } else { '{0:N2} GB' -f $v } }
function Format-Dur {
    param($sec)
    if ($null -eq $sec) { return '--' }
    $ts = [TimeSpan]::FromSeconds($sec)
    # Floor, never [int]: PowerShell's [int] cast ROUNDS (banker's), so [int]4.55 -> 5
    # and a 4h32m stage would print as "5h 32m".
    if ($ts.TotalHours -ge 1)   { return '{0}h {1:00}m' -f [Math]::Floor($ts.TotalHours),   $ts.Minutes }
    if ($ts.TotalMinutes -ge 1) { return '{0}m {1:00}s' -f [Math]::Floor($ts.TotalMinutes), $ts.Seconds }
    return '{0:N1}s' -f $sec
}

# ---- gather -----------------------------------------------------------------
$reports = @()
for ($i = 0; $i -lt $LogPath.Count; $i++) {
    $lbl = if ($Label -and $i -lt $Label.Count) { $Label[$i] } else { Split-Path $LogPath[$i] -Leaf }
    $reports += [pscustomobject]@{ Label = $lbl; Data = (Read-RunLog $LogPath[$i]) }
}

# ---- emit -------------------------------------------------------------------
# @() forces an array: with a single log, $reports.Label collapses to a bare string
# and Set-StrictMode rejects .Count on it.
$cols = @($reports.Label)
$sep  = ('|---' * ($cols.Count + 1)) + '|'

Write-Output ''
Write-Output '## Osprey memory anchors'
Write-Output ''
Write-Output ('| Stage / anchor | ' + ($cols -join ' | ') + ' |')
Write-Output $sep

# LIVE rows (post-forced-GC) are the sizing numbers. The rest include uncollected
# garbage (GC.GetTotalMemory(false)) or reflect the GC expanding into available RAM;
# in particular **peak working set is NOT a measure of demand** -- Server GC grows
# heaps toward the high-memory-load threshold (~90% of physical) before collecting,
# so on a 64 GB box it lands near ~55 GB almost regardless of the live set.
$rows = [ordered]@{
    'Library resident (LIVE, post-GC)'    = { param($d) Format-Gb $d.LibraryResident }
    '**Stage 5 start (LIVE, post-GC)**'   = { param($d) Format-Gb $d.Stage5LiveHeap }
    '**1st-pass FDR (LIVE, post-GC)**'    = { param($d) Format-Gb $d.FirstPassLiveHeap }
    '**Reconciliation floor (LIVE)**'     = { param($d) Format-Gb $d.ReconFloorHeap }
    'Reconciliation resident (LIVE)'      = { param($d) Format-Gb $d.ReconResidentHeap }
    '-- below: not live, read with care --' = { param($d) '' }
    'Scoring plateau (peak WS)'           = { param($d) Format-Gb $d.ScoringPeakWs }
    'Scoring (max managed heap)'          = { param($d) Format-Gb $d.ScoringMaxHeap }
    'Stage 5 stub load (managed)'         = { param($d) Format-Gb $d.Stage5Heap }
    'Stage 5 stub load (peak_paged)'      = { param($d) Format-Gb $d.Stage5PeakPaged }
    'Stage 5 projection built (managed)'  = { param($d) Format-Gb $d.ProjectionHeap }
    'After 1st-pass Percolator (managed)' = { param($d) Format-Gb $d.AfterFdrHeap }
    'After Stage-5 compaction (managed)'  = { param($d) Format-Gb $d.AfterCompactHeap }
    'Overall peak WS (GC-expanded, NOT demand)' = { param($d) Format-Gb $d.OverallPeakWs }
    '**Overall peak_paged**'              = { param($d) Format-Gb $d.OverallPeakPaged }
}
foreach ($name in $rows.Keys) {
    $cells = $reports | ForEach-Object { & $rows[$name] $_.Data }
    Write-Output ('| ' + $name + ' | ' + ($cells -join ' | ') + ' |')
}

Write-Output ''
Write-Output '## Stage wall times'
Write-Output ''
Write-Output ('| Stage | ' + ($cols -join ' | ') + ' |')
Write-Output $sep

$allStages = @()
foreach ($rep in $reports) { $allStages += @($rep.Data.Stages.Keys) }
$allStages = @($allStages | Select-Object -Unique)
foreach ($s in $allStages) {
    $cells = $reports | ForEach-Object {
        if ($_.Data.Stages.Contains($s)) { Format-Dur $_.Data.Stages[$s] } else { '--' }
    }
    Write-Output ('| ' + $s + ' | ' + ($cells -join ' | ') + ' |')
}
$cells = $reports | ForEach-Object { Format-Dur $_.Data.TotalSec }
Write-Output ('| **total pipeline** | ' + ($cells -join ' | ') + ' |')

Write-Output ''
Write-Output '## Run scale'
Write-Output ''
Write-Output ('| Metric | ' + ($cols -join ' | ') + ' |')
Write-Output $sep
$cells = $reports | ForEach-Object { if ($null -eq $_.Data.NFiles) { '--' } else { '{0}' -f $_.Data.NFiles } }
Write-Output ('| Files | ' + ($cells -join ' | ') + ' |')
$cells = $reports | ForEach-Object { if ($null -eq $_.Data.ScoredEntries) { '--' } else { '{0:N0}' -f $_.Data.ScoredEntries } }
Write-Output ('| Scored entries | ' + ($cells -join ' | ') + ' |')
Write-Output ''
