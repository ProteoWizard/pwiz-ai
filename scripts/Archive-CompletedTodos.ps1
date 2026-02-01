<#
.SYNOPSIS
    Archive old completed TODO files into year/month subfolders.

.DESCRIPTION
    Moves TODO files from ai/todos/completed/ into ai/todos/completed/YYYY/MM/
    subfolders based on the date in their filename (TODO-YYYYMMDD_...).

    By default, keeps the most recent 2 months at the root level and archives
    everything older. Uses git mv so the moves are tracked in version control.

.PARAMETER KeepMonths
    Number of recent months to keep at root level. Default: 2.

.PARAMETER DryRun
    Show what would be moved without actually moving anything.

.EXAMPLE
    # Archive with defaults (keep 2 months)
    ./ai/scripts/Archive-CompletedTodos.ps1

    # Preview what would be archived
    ./ai/scripts/Archive-CompletedTodos.ps1 -DryRun

    # Keep only the current month at root
    ./ai/scripts/Archive-CompletedTodos.ps1 -KeepMonths 1
#>

param(
    [int]$KeepMonths = 2,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$completedDir = Join-Path $PSScriptRoot '..' 'todos' 'completed'
$completedDir = (Resolve-Path $completedDir).Path

# Calculate the cutoff: first day of (current month - KeepMonths + 1)
# Files with dates before this get archived
$now = Get-Date
$cutoffMonth = $now.AddMonths(-($KeepMonths - 1))
$cutoff = Get-Date -Year $cutoffMonth.Year -Month $cutoffMonth.Month -Day 1

Write-Host "Archive cutoff: files before $($cutoff.ToString('yyyy-MM-dd')) will be archived"
Write-Host "Scanning $completedDir ..."

# Find TODO files at root level (not in subdirectories)
$files = Get-ChildItem -Path $completedDir -File | Where-Object {
    $_.Name -match '^TODO-(\d{4})(\d{2})(\d{2})_'
}

$archived = 0
$skipped = 0

foreach ($file in $files) {
    if ($file.Name -match '^TODO-(\d{4})(\d{2})(\d{2})_') {
        $year = $Matches[1]
        $month = $Matches[2]
        $day = $Matches[3]
        $fileDate = Get-Date -Year $year -Month $month -Day $day

        if ($fileDate -lt $cutoff) {
            $targetDir = Join-Path $completedDir $year $month

            if ($DryRun) {
                Write-Host "  [DRY RUN] $($file.Name) -> $year/$month/"
            }
            else {
                if (-not (Test-Path $targetDir)) {
                    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
                }
                # Use git mv for tracked history
                $relativeSrc = "todos/completed/$($file.Name)"
                $relativeDst = "todos/completed/$year/$month/$($file.Name)"
                git -C (Join-Path $PSScriptRoot '..' '..') mv $relativeSrc $relativeDst
                if ($LASTEXITCODE -ne 0) {
                    Write-Warning "git mv failed for $($file.Name), trying filesystem move"
                    Move-Item $file.FullName (Join-Path $targetDir $file.Name)
                }
                Write-Host "  Archived: $($file.Name) -> $year/$month/"
            }
            $archived++
        }
        else {
            $skipped++
        }
    }
}

Write-Host ""
if ($DryRun) {
    Write-Host "Dry run complete: $archived would be archived, $skipped kept at root"
}
else {
    Write-Host "Done: $archived archived, $skipped kept at root"
    if ($archived -gt 0) {
        Write-Host "Run 'git status' to review, then commit the moves."
    }
}
