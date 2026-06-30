<#
.SYNOPSIS
    Cleans up stale transient files and investigation directories from ai/.tmp/.

.DESCRIPTION
    MCP tools and Claude Code sessions write investigation artifacts, page fetches,
    diagnostic scripts, run outputs, and other one-off files to ai/.tmp/. This script
    removes items older than a retention period.

    By default it only cleans TOP-LEVEL FILES (the original behavior). Pass
    -IncludeSubdirs to ALSO sweep the investigation/run subdirectories, which is
    where the bulk of the disk usage accumulates (osprey run outputs, perf/profiling
    dumps, parity diagnostics, MCP downloads, etc.).

    Protected items (never deleted):
    - active-project.json and active-project-<ppid>.json (live MCP status state)
    - Managed/infra subdirectories: see $ProtectedDirs below (daily/, screenshots/,
      state/, pr-report/, history/, plots/, plots-outliers/, attachments/, icons/).
      These are owned by other tooling (daily report, pr-report, screenshots) and
      regenerated on a schedule.

.PARAMETER RetentionDays
    Delete top-level files older than this many days. Default: 14.

.PARAMETER IncludeSubdirs
    Also sweep top-level subdirectories. A subdirectory is deleted (recursively) when
    the newest file it contains is older than the subdir cutoff. Protected dirs are
    never deleted.

.PARAMETER SubdirRetentionDays
    Retention for the subdirectory sweep when -IncludeSubdirs is set. Defaults to
    RetentionDays. Use 0 to delete ALL non-protected subdirs regardless of age.

.PARAMETER WhatIf
    Preview what would be deleted without actually deleting.

.EXAMPLE
    .\Clean-TmpFiles.ps1
    Deletes top-level files older than 14 days (subdirectories untouched).

.EXAMPLE
    .\Clean-TmpFiles.ps1 -IncludeSubdirs -WhatIf
    Preview the full sweep, including investigation/run subdirectories.

.EXAMPLE
    .\Clean-TmpFiles.ps1 -IncludeSubdirs -SubdirRetentionDays 0
    Delete every non-protected subdirectory regardless of age, plus top-level files
    older than 14 days. (The "clean all regenerable scratch" sweep.)
#>

param(
    [int]$RetentionDays = 14,
    [switch]$IncludeSubdirs,
    [int]$SubdirRetentionDays = -1,
    [switch]$WhatIf
)

# Derive ai/ root from script location: ai/scripts/Clean-TmpFiles.ps1 -> ai/
$aiRoot = Split-Path -Parent $PSScriptRoot
$TmpDir = Join-Path $aiRoot '.tmp'

# Files that must never be deleted
$ProtectedFiles = @(
    "active-project.json"
)

# Subdirectories owned by other tooling — never swept by -IncludeSubdirs.
$ProtectedDirs = @(
    "screenshots",      # tutorial/screenshot tooling
    "state",            # live MCP/session state
    "daily",            # Move-DailyReports.ps1 / Invoke-DailyReport.ps1
    "pr-report",        # PR activity reporting
    "history",          # report history
    "attachments",      # downloaded support/issue attachments
    "icons",            # generated icon assets
    "plots",
    "plots-outliers"
)

$Cutoff = (Get-Date).AddDays(-$RetentionDays)
if ($SubdirRetentionDays -lt 0) { $SubdirRetentionDays = $RetentionDays }
$SubdirCutoff = (Get-Date).AddDays(-$SubdirRetentionDays)

# ---------------------------------------------------------------------------
# Top-level files
# ---------------------------------------------------------------------------
$allFiles = Get-ChildItem -Path $TmpDir -File

$toDelete = @()
$protected = @()
$kept = @()

foreach ($file in $allFiles) {
    if ($ProtectedFiles -contains $file.Name) {
        $protected += $file
        continue
    }

    # Per-session active-project files are protected only while their Claude
    # Code process is still alive; orphan files left over from killed sessions
    # age out under the normal retention rules.
    if ($file.Name -match '^active-project-(\d+)\.json$') {
        $sessionPid = [int]$Matches[1]
        if (Get-Process -Id $sessionPid -ErrorAction SilentlyContinue) {
            $protected += $file
            continue
        }
    }

    if ($file.LastWriteTime -lt $Cutoff) {
        $toDelete += $file
    } else {
        $kept += $file
    }
}

# Group file deletions by category for reporting
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

# ---------------------------------------------------------------------------
# Subdirectories (opt-in)
# ---------------------------------------------------------------------------
$dirsToDelete = @()
$dirsProtected = @()
$dirsKept = @()

if ($IncludeSubdirs) {
    $allDirs = Get-ChildItem -Path $TmpDir -Directory
    foreach ($dir in $allDirs) {
        if ($ProtectedDirs -contains $dir.Name) {
            $dirsProtected += $dir
            continue
        }

        $files = Get-ChildItem -Path $dir.FullName -Recurse -File -ErrorAction SilentlyContinue
        $size = ($files | Measure-Object -Property Length -Sum).Sum
        if (-not $size) { $size = 0 }
        $newest = ($files | Measure-Object -Property LastWriteTime -Maximum).Maximum
        if (-not $newest) { $newest = $dir.LastWriteTime }

        $info = [PSCustomObject]@{
            Dir    = $dir
            Size   = $size
            Newest = $newest
        }

        if ($newest -lt $SubdirCutoff) {
            $dirsToDelete += $info
        } else {
            $dirsKept += $info
        }
    }
}

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
$totalFileSize = ($toDelete | Measure-Object -Property Length -Sum).Sum
if (-not $totalFileSize) { $totalFileSize = 0 }
$totalDirSize = ($dirsToDelete | Measure-Object -Property Size -Sum).Sum
if (-not $totalDirSize) { $totalDirSize = 0 }

Write-Host "Clean-TmpFiles: file retention=$RetentionDays days (cutoff $($Cutoff.ToString('yyyy-MM-dd')))" -ForegroundColor Cyan
if ($IncludeSubdirs) {
    Write-Host "                subdir retention=$SubdirRetentionDays days (cutoff $($SubdirCutoff.ToString('yyyy-MM-dd')))" -ForegroundColor Cyan
}
Write-Host ""

# --- Top-level files ---
if ($toDelete.Count -gt 0) {
    Write-Host "Top-level files to delete: $($toDelete.Count) ($([math]::Round($totalFileSize / 1MB, 1)) MB)" -ForegroundColor Cyan
    foreach ($cat in ($categories.Keys | Sort-Object)) {
        $files = $categories[$cat]
        if ($files.Count -eq 0) { continue }
        $catSize = ($files | Measure-Object -Property Length -Sum).Sum
        Write-Host "  $cat ($($files.Count) files, $([math]::Round($catSize / 1KB, 0)) KB)" -ForegroundColor Green
    }
    Write-Host ""
} else {
    Write-Host "No top-level files to delete." -ForegroundColor Yellow
    Write-Host ""
}

# --- Subdirectories ---
if ($IncludeSubdirs) {
    if ($dirsToDelete.Count -gt 0) {
        Write-Host "Subdirectories to delete: $($dirsToDelete.Count) ($([math]::Round($totalDirSize / 1GB, 2)) GB)" -ForegroundColor Cyan
        foreach ($d in ($dirsToDelete | Sort-Object Size -Descending)) {
            $age = [math]::Round(((Get-Date) - $d.Newest).TotalDays)
            $sizeStr = if ($d.Size -ge 1GB) { "$([math]::Round($d.Size / 1GB, 1)) GB" } else { "$([math]::Round($d.Size / 1MB, 1)) MB" }
            Write-Host ("    {0,-42} {1,9}  (newest {2}d old)" -f $d.Dir.Name, $sizeStr, $age)
        }
        Write-Host ""
    } else {
        Write-Host "No subdirectories to delete." -ForegroundColor Yellow
        Write-Host ""
    }
}

Write-Host "  Protected files: $($protected.Count)" -ForegroundColor Yellow
Write-Host "  Files within retention: $($kept.Count) (< $RetentionDays days old)" -ForegroundColor Yellow
if ($IncludeSubdirs) {
    Write-Host "  Protected subdirs: $($dirsProtected.Count) ($($ProtectedDirs -join ', '))" -ForegroundColor Yellow
    Write-Host "  Subdirs within retention: $($dirsKept.Count)" -ForegroundColor Yellow
}

$grandTotal = $totalFileSize + $totalDirSize
if (($toDelete.Count + $dirsToDelete.Count) -eq 0) {
    Write-Host ""
    Write-Host "Nothing to delete." -ForegroundColor Yellow
    exit 0
}

if ($WhatIf) {
    Write-Host ""
    Write-Host "WhatIf: nothing deleted. Would free $([math]::Round($grandTotal / 1GB, 2)) GB." -ForegroundColor Yellow
    exit 0
}

# ---------------------------------------------------------------------------
# Execute deletions
# ---------------------------------------------------------------------------
Write-Host ""
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

$dirsDeleted = 0
foreach ($d in $dirsToDelete) {
    try {
        Remove-Item -Path $d.Dir.FullName -Recurse -Force
        $dirsDeleted++
    }
    catch {
        Write-Host "  ERROR deleting $($d.Dir.Name)/: $_" -ForegroundColor Red
        $errors++
    }
}

Write-Host "Deleted $deleted files and $dirsDeleted subdirs ($([math]::Round($grandTotal / 1GB, 2)) GB freed)." -ForegroundColor Green
if ($errors -gt 0) {
    Write-Host "$errors errors." -ForegroundColor Red
}
