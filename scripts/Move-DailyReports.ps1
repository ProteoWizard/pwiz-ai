<#
.SYNOPSIS
    Moves daily report files from ai/.tmp/ into per-date folders under ai/.tmp/daily/.

.DESCRIPTION
    MCP tools write reports to ai/.tmp/ with date-stamped filenames. This script
    moves them into ai/.tmp/daily/YYYY-MM-DD/ folders with the date suffix stripped.

    Can run in two modes:
    - Default: Move today's files only
    - MigrateAll: Move all historical dated files

.PARAMETER Date
    Date to process (YYYYMMDD format). Default: today.

.PARAMETER MigrateAll
    Scan for all historical dated files and move them all.

.PARAMETER WhatIf
    Preview what would be moved without actually moving.

.EXAMPLE
    .\Move-DailyReports.ps1
    Moves today's daily report files into the per-date folder.

.EXAMPLE
    .\Move-DailyReports.ps1 -MigrateAll -WhatIf
    Preview migration of all historical files.

.EXAMPLE
    .\Move-DailyReports.ps1 -MigrateAll
    Migrate all historical dated files into per-date folders.
#>

param(
    [string]$Date,
    [switch]$MigrateAll,
    [switch]$WhatIf
)

# Derive ai/ root from script location: ai/scripts/Move-DailyReports.ps1 -> ai/
$aiRoot = Split-Path -Parent $PSScriptRoot
$TmpDir = Join-Path $aiRoot '.tmp'
$DailyDir = Join-Path $TmpDir "daily"

# File patterns to move into daily/YYYY-MM-DD/ (date suffix stripped)
# Each entry: regex pattern, capture group 1 = YYYYMMDD, destination filename
$DailyPatterns = @(
    @{ Pattern = '^nightly-report-(\d{8})\.md$';       Dest = 'nightly-report.md' },
    @{ Pattern = '^exceptions-report-(\d{8})\.md$';     Dest = 'exceptions-report.md' },
    @{ Pattern = '^support-report-(\d{8})\.md$';        Dest = 'support-report.md' },
    @{ Pattern = '^failures-(\d{8})\.md$';              Dest = 'failures.md' },
    @{ Pattern = '^suggested-actions-(\d{8})\.md$';     Dest = 'suggested-actions.md' },
    @{ Pattern = '^daily-manifest-(\d{8})\.json$';      Dest = 'manifest.json' }
)

function Convert-DateToFolder([string]$yyyymmdd) {
    $y = $yyyymmdd.Substring(0, 4)
    $m = $yyyymmdd.Substring(4, 2)
    $d = $yyyymmdd.Substring(6, 2)
    return "$y-$m-$d"
}

# Collect files to move
$moves = @()

$topLevelFiles = Get-ChildItem -Path $TmpDir -File

foreach ($file in $topLevelFiles) {
    foreach ($pat in $DailyPatterns) {
        if ($file.Name -match $pat.Pattern) {
            $dateStr = $Matches[1]

            # If not MigrateAll, only process the specified date
            if (-not $MigrateAll) {
                $targetDate = if ($Date) { $Date } else { (Get-Date).ToString("yyyyMMdd") }
                if ($dateStr -ne $targetDate) { continue }
            }

            $folder = Convert-DateToFolder $dateStr
            $destDir = Join-Path $DailyDir $folder
            $destPath = Join-Path $destDir $pat.Dest

            $moves += @{
                Source   = $file.FullName
                DestDir  = $destDir
                DestPath = $destPath
                Date     = $dateStr
                Folder   = $folder
            }
            break  # matched this file, move on
        }
    }
}

if ($moves.Count -eq 0) {
    Write-Host "No files to move." -ForegroundColor Yellow
    exit 0
}

# Group by date for display
$byDate = $moves | Group-Object { $_.Folder } | Sort-Object Name

Write-Host "Files to move: $($moves.Count)" -ForegroundColor Cyan
Write-Host "Date folders: $($byDate.Count)" -ForegroundColor Cyan
Write-Host ""

foreach ($group in $byDate) {
    Write-Host "  $($group.Name)/" -ForegroundColor Green
    foreach ($m in $group.Group) {
        $srcName = Split-Path $m.Source -Leaf
        $dstName = Split-Path $m.DestPath -Leaf
        Write-Host "    $srcName -> $dstName"
    }
}

if ($WhatIf) {
    Write-Host ""
    Write-Host "WhatIf: No files moved." -ForegroundColor Yellow
    exit 0
}

Write-Host ""

# Execute moves
$moved = 0
$errors = 0

foreach ($m in $moves) {
    if (-not (Test-Path $m.DestDir)) {
        New-Item -ItemType Directory -Path $m.DestDir -Force | Out-Null
    }
    try {
        Move-Item -Path $m.Source -Destination $m.DestPath -Force
        $moved++
    }
    catch {
        Write-Host "  ERROR moving $($m.Source): $_" -ForegroundColor Red
        $errors++
    }
}

Write-Host "Moved $moved files into $($byDate.Count) date folders." -ForegroundColor Green
if ($errors -gt 0) {
    Write-Host "$errors errors." -ForegroundColor Red
}

# Update manifests to reflect new paths
foreach ($group in $byDate) {
    $manifestPath = Join-Path $DailyDir (Join-Path $group.Name "manifest.json")
    if (Test-Path $manifestPath) {
        try {
            $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
            $folder = $group.Name
            $changed = $false

            if ($manifest.files) {
                $dateCompact = $folder -replace '-', ''
                $fileMap = @{
                    nightly_report    = "ai/.tmp/daily/$folder/nightly-report.md"
                    exceptions_report = "ai/.tmp/daily/$folder/exceptions-report.md"
                    support_report    = "ai/.tmp/daily/$folder/support-report.md"
                    daily_failures    = "ai/.tmp/daily/$folder/failures.md"
                    suggested_actions = "ai/.tmp/daily/$folder/suggested-actions.md"
                    daily_summary     = "ai/.tmp/daily/summaries/daily-summary-$dateCompact.json"
                }

                foreach ($key in $fileMap.Keys) {
                    $prop = $manifest.files.PSObject.Properties[$key]
                    if ($prop -and $prop.Value -and $prop.Value -ne $fileMap[$key]) {
                        # Only update if the destination file actually exists
                        $fullDest = Join-Path (Split-Path -Parent $aiRoot) $fileMap[$key]
                        if (Test-Path $fullDest) {
                            $prop.Value = $fileMap[$key]
                            $changed = $true
                        }
                    }
                }
            }

            if ($changed) {
                $manifest | ConvertTo-Json -Depth 10 | Set-Content $manifestPath -Encoding UTF8
                Write-Host "Updated manifest: $folder/manifest.json" -ForegroundColor Cyan
            }
        }
        catch {
            Write-Host "  WARNING: Could not update manifest $manifestPath`: $_" -ForegroundColor Yellow
        }
    }
}
