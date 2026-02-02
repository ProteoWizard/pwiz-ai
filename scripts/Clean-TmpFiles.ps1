<#
.SYNOPSIS
    Cleans up stale transient files from ai/.tmp/.

.DESCRIPTION
    MCP tools and Claude Code sessions write investigation artifacts, page fetches,
    diagnostic scripts, and other one-off files to ai/.tmp/. This script removes
    files older than a retention period.

    Protected items (never deleted):
    - active-project.json (live MCP status tool state)
    - daily/ directory tree (managed by Move-DailyReports.ps1 and Invoke-DailyReport.ps1)
    - plots/, plots-outliers/, screenshots/ directories

    Only cleans TOP-LEVEL files in ai/.tmp/ — subdirectories are left to their
    own management scripts.

.PARAMETER RetentionDays
    Delete files older than this many days. Default: 14.

.PARAMETER WhatIf
    Preview what would be deleted without actually deleting.

.EXAMPLE
    .\Clean-TmpFiles.ps1
    Deletes top-level files older than 14 days.

.EXAMPLE
    .\Clean-TmpFiles.ps1 -RetentionDays 7
    Deletes top-level files older than 7 days.

.EXAMPLE
    .\Clean-TmpFiles.ps1 -WhatIf
    Preview what would be deleted.
#>

param(
    [int]$RetentionDays = 14,
    [switch]$WhatIf
)

# Derive ai/ root from script location: ai/scripts/Clean-TmpFiles.ps1 -> ai/
$aiRoot = Split-Path -Parent $PSScriptRoot
$TmpDir = Join-Path $aiRoot '.tmp'

# Files that must never be deleted
$ProtectedFiles = @(
    "active-project.json"
)

$Cutoff = (Get-Date).AddDays(-$RetentionDays)

# Get all top-level files (not directories)
$allFiles = Get-ChildItem -Path $TmpDir -File

$toDelete = @()
$protected = @()
$kept = @()

foreach ($file in $allFiles) {
    if ($ProtectedFiles -contains $file.Name) {
        $protected += $file
        continue
    }

    if ($file.LastWriteTime -lt $Cutoff) {
        $toDelete += $file
    } else {
        $kept += $file
    }
}

# Group deletions by category for reporting
$categories = @{
    "MCP investigation" = @()
    "MCP page fetches"  = @()
    "MCP wiki downloads" = @()
    "Diagnostic scripts" = @()
    "Python scripts"    = @()
    "Handoff files"     = @()
    "Installer binaries" = @()
    "Localization"      = @()
    "Other"             = @()
}

foreach ($file in $toDelete) {
    $name = $file.Name
    if ($name -match '^(run-comparison-|testrun-log-|testrun-xml-|test-failures-|run-metrics-)') {
        $categories["MCP investigation"] += $file
    } elseif ($name -match '^page-.*\.html$') {
        $categories["MCP page fetches"] += $file
    } elseif ($name -match '^wiki-') {
        $categories["MCP wiki downloads"] += $file
    } elseif ($name -match '\.ps1$') {
        $categories["Diagnostic scripts"] += $file
    } elseif ($name -match '\.py$') {
        $categories["Python scripts"] += $file
    } elseif ($name -match '^handoff-') {
        $categories["Handoff files"] += $file
    } elseif ($name -match '\.(zip|msi|exe)$') {
        $categories["Installer binaries"] += $file
    } elseif ($name -match '^localization') {
        $categories["Localization"] += $file
    } else {
        $categories["Other"] += $file
    }
}

# Report
$totalSize = ($toDelete | Measure-Object -Property Length -Sum).Sum
if (-not $totalSize) { $totalSize = 0 }

Write-Host "Clean-TmpFiles: retention=$RetentionDays days, cutoff=$($Cutoff.ToString('yyyy-MM-dd'))" -ForegroundColor Cyan
Write-Host ""

if ($toDelete.Count -eq 0) {
    Write-Host "No files to delete." -ForegroundColor Yellow
    Write-Host "  Protected: $($protected.Count)"
    Write-Host "  Within retention: $($kept.Count)"
    exit 0
}

Write-Host "Files to delete: $($toDelete.Count) ($([math]::Round($totalSize / 1MB, 1)) MB)" -ForegroundColor Cyan
Write-Host ""

foreach ($cat in ($categories.Keys | Sort-Object)) {
    $files = $categories[$cat]
    if ($files.Count -eq 0) { continue }
    $catSize = ($files | Measure-Object -Property Length -Sum).Sum
    Write-Host "  $cat ($($files.Count) files, $([math]::Round($catSize / 1KB, 0)) KB)" -ForegroundColor Green
    foreach ($f in ($files | Sort-Object Name)) {
        $age = [math]::Round(((Get-Date) - $f.LastWriteTime).TotalDays)
        Write-Host "    $($f.Name) (${age}d old)"
    }
}

Write-Host ""
Write-Host "  Protected: $($protected.Count) (never deleted)" -ForegroundColor Yellow
Write-Host "  Within retention: $($kept.Count) (< $RetentionDays days old)" -ForegroundColor Yellow

if ($WhatIf) {
    Write-Host ""
    Write-Host "WhatIf: No files deleted." -ForegroundColor Yellow
    exit 0
}

Write-Host ""

# Execute deletions
$deleted = 0
$errors = 0

foreach ($file in $toDelete) {
    try {
        Remove-Item -Path $file.FullName -Force
        $deleted++
    }
    catch {
        Write-Host "  ERROR deleting $($file.Name): $_" -ForegroundColor Red
        $errors++
    }
}

Write-Host "Deleted $deleted files ($([math]::Round($totalSize / 1MB, 1)) MB freed)." -ForegroundColor Green
if ($errors -gt 0) {
    Write-Host "$errors errors." -ForegroundColor Red
}
