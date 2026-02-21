<#
.SYNOPSIS
    Archives daily report data to a network drive for long-term preservation.

.DESCRIPTION
    Syncs all daily report data from ai/.tmp/daily/ to a configurable archive
    location. Uses robocopy for efficient incremental copying.

    Archives:
    - Date folders (YYYY-MM-DD/) with nightly reports, manifests, logs
    - history/*.json with test failure fingerprints and fix records
    - summaries/*.json with daily pattern detection data

    Designed to run automatically as part of Invoke-DailyReport.ps1, before
    the 30-day cleanup removes old date folders.

.PARAMETER ArchiveRoot
    Destination root for archived data.
    Default: M:\home\brendanx\tools\claude\daily

.PARAMETER SourceRoot
    Source daily data directory.
    Default: ai\.tmp\daily (relative to project root)

.PARAMETER DryRun
    Show what would be copied without actually copying.

.EXAMPLE
    .\Archive-DailyReports.ps1
    Archives all daily data to the default M: drive location.

.EXAMPLE
    .\Archive-DailyReports.ps1 -DryRun
    Shows what would be archived without copying.
#>

param(
    [string]$ArchiveRoot = "M:\home\brendanx\tools\claude\daily",
    [string]$SourceRoot,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

# Derive project root from script location: ai/scripts/Archive-DailyReports.ps1 -> ai/ -> root
$aiRoot = Split-Path -Parent $PSScriptRoot
$WorkDir = Split-Path -Parent $aiRoot

if (-not $SourceRoot) {
    $SourceRoot = Join-Path $WorkDir "ai\.tmp\daily"
}

# Validate source exists
if (-not (Test-Path $SourceRoot)) {
    Write-Warning "Source directory not found: $SourceRoot"
    exit 0
}

# Check archive drive is accessible
$ArchiveDrive = Split-Path -Qualifier $ArchiveRoot
if (-not (Test-Path $ArchiveDrive)) {
    Write-Warning "Archive drive not accessible: $ArchiveDrive - skipping archive"
    exit 0
}

# Create archive root if needed
if (-not (Test-Path $ArchiveRoot)) {
    if ($DryRun) {
        Write-Host "[DRY RUN] Would create: $ArchiveRoot"
    } else {
        New-Item -ItemType Directory -Path $ArchiveRoot -Force | Out-Null
        Write-Host "Created archive root: $ArchiveRoot"
    }
}

$Stats = @{ Copied = 0; Skipped = 0; Errors = 0 }

# ─────────────────────────────────────────────────────────────
# Archive history files (most valuable - always copy)
# ─────────────────────────────────────────────────────────────

$HistorySource = Join-Path $SourceRoot "history"
$HistoryDest = Join-Path $ArchiveRoot "history"

if (Test-Path $HistorySource) {
    if (-not (Test-Path $HistoryDest) -and -not $DryRun) {
        New-Item -ItemType Directory -Path $HistoryDest -Force | Out-Null
    }

    Get-ChildItem -Path $HistorySource -File | ForEach-Object {
        $DestFile = Join-Path $HistoryDest $_.Name
        $ShouldCopy = $true

        if (Test-Path $DestFile) {
            # Only copy if source is newer or different size
            $DestInfo = Get-Item $DestFile
            if ($_.Length -eq $DestInfo.Length -and $_.LastWriteTime -le $DestInfo.LastWriteTime) {
                $ShouldCopy = $false
                $Stats.Skipped++
            }
        }

        if ($ShouldCopy) {
            if ($DryRun) {
                Write-Host "[DRY RUN] Would copy: history/$($_.Name) ($([math]::Round($_.Length / 1KB))KB)"
            } else {
                Copy-Item -Path $_.FullName -Destination $DestFile -Force
                $Stats.Copied++
                Write-Host "  Archived: history/$($_.Name) ($([math]::Round($_.Length / 1KB))KB)"
            }
        }
    }
}

# ─────────────────────────────────────────────────────────────
# Archive summaries (incremental - only new files)
# ─────────────────────────────────────────────────────────────

$SummariesSource = Join-Path $SourceRoot "summaries"
$SummariesDest = Join-Path $ArchiveRoot "summaries"

if (Test-Path $SummariesSource) {
    if (-not (Test-Path $SummariesDest) -and -not $DryRun) {
        New-Item -ItemType Directory -Path $SummariesDest -Force | Out-Null
    }

    Get-ChildItem -Path $SummariesSource -File | ForEach-Object {
        $DestFile = Join-Path $SummariesDest $_.Name
        if (-not (Test-Path $DestFile)) {
            if ($DryRun) {
                Write-Host "[DRY RUN] Would copy: summaries/$($_.Name)"
            } else {
                Copy-Item -Path $_.FullName -Destination $DestFile -Force
                $Stats.Copied++
            }
        } else {
            $Stats.Skipped++
        }
    }

    $SummaryCount = (Get-ChildItem -Path $SummariesSource -File).Count
    if (-not $DryRun -and $SummaryCount -gt 0) {
        Write-Host "  Archived: summaries/ ($SummaryCount files synced)"
    }
}

# ─────────────────────────────────────────────────────────────
# Archive date folders (incremental - copy new/updated folders)
# ─────────────────────────────────────────────────────────────

$DateFolders = Get-ChildItem -Path $SourceRoot -Directory |
    Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}$' }

$NewFolders = 0
$UpdatedFolders = 0

foreach ($Folder in $DateFolders) {
    $DestFolder = Join-Path $ArchiveRoot $Folder.Name

    if (-not (Test-Path $DestFolder)) {
        # New folder - copy entirely
        if ($DryRun) {
            Write-Host "[DRY RUN] Would copy: $($Folder.Name)/"
        } else {
            Copy-Item -Path $Folder.FullName -Destination $DestFolder -Recurse -Force
            $NewFolders++
            $Stats.Copied++
        }
    } else {
        # Existing folder - copy any new or updated files
        $SourceFiles = Get-ChildItem -Path $Folder.FullName -File
        $Updated = $false

        foreach ($File in $SourceFiles) {
            $DestFile = Join-Path $DestFolder $File.Name
            $ShouldCopy = $false

            if (-not (Test-Path $DestFile)) {
                $ShouldCopy = $true
            } else {
                $DestInfo = Get-Item $DestFile
                if ($File.Length -ne $DestInfo.Length -or $File.LastWriteTime -gt $DestInfo.LastWriteTime) {
                    $ShouldCopy = $true
                }
            }

            if ($ShouldCopy) {
                if (-not $DryRun) {
                    Copy-Item -Path $File.FullName -Destination $DestFile -Force
                    $Updated = $true
                    $Stats.Copied++
                } else {
                    Write-Host "[DRY RUN] Would update: $($Folder.Name)/$($File.Name)"
                }
            } else {
                $Stats.Skipped++
            }
        }

        if ($Updated) { $UpdatedFolders++ }
    }
}

if (-not $DryRun) {
    $TotalDates = $DateFolders.Count
    Write-Host "  Archived: $TotalDates date folders ($NewFolders new, $UpdatedFolders updated)"
}

# ─────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────

if ($DryRun) {
    Write-Host ""
    Write-Host "[DRY RUN] No files were copied."
} else {
    Write-Host "Archive complete: $($Stats.Copied) items copied, $($Stats.Skipped) unchanged"
}
