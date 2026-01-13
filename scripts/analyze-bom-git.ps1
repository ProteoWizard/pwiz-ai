# Analyze UTF-8 BOM usage across Git-tracked files only
# Much faster than scanning entire directory tree
#
# Usage: .\analyze-bom-git.ps1 [-OutputFile <path>]
# Output: Console report + optional output file
# Scope: Processes both parent repo and ai/ clone (pwiz-ai)
#
# This script was created during the webclient_replacement work (Oct 2025)
# when LLM tools were inadvertently removing BOMs from source files.
# See todos/backlog/TODO-utf8_no_bom.md for the full standardization plan.

param(
    [string]$OutputFile = $null  # If not specified, no file will be written
)

$utf8Bom = @(0xEF, 0xBB, 0xBF)

# Function to get Git-tracked files from a directory
function Get-GitTrackedFiles {
    param([string]$workDir = ".")

    Push-Location $workDir
    try {
        $files = @(git ls-files 2>$null)
        return $files
    } finally {
        Pop-Location
    }
}

# Function to check BOM for a single file
function Test-FileBom {
    param(
        [string]$filePath,
        [string]$baseDir = "."
    )

    $fullPath = Join-Path $baseDir $filePath

    # Skip files that don't exist or can't be accessed
    if (-not [System.IO.File]::Exists($fullPath)) {
        return $null
    }

    try {
        # Read first 3 bytes
        $stream = [System.IO.File]::OpenRead($fullPath)
        $bytes = New-Object byte[] 3
        $bytesRead = $stream.Read($bytes, 0, 3)
        $stream.Close()

        if ($bytesRead -ge 3 -and
            $bytes[0] -eq $utf8Bom[0] -and
            $bytes[1] -eq $utf8Bom[1] -and
            $bytes[2] -eq $utf8Bom[2]) {
            return "bom"
        } else {
            return "no-bom"
        }
    } catch {
        # Skip files that can't be read (likely binary or locked)
        return "binary"
    }
}

Write-Host "Scanning Git-tracked files for UTF-8 BOM usage..." -ForegroundColor Cyan
Write-Host ""

# Collect files from parent repo and ai/ clone
$allFiles = @()

# Parent repo files
$parentFiles = Get-GitTrackedFiles -workDir "."
foreach ($f in $parentFiles) {
    $allFiles += @{ RelPath = $f; BaseDir = (Get-Location).Path }
}

# ai/ clone files (pwiz-ai)
$repoRoot = git rev-parse --show-toplevel 2>$null
if ($repoRoot) {
    $aiPath = Join-Path $repoRoot "ai"
    if (Test-Path $aiPath -PathType Container) {
        $aiFiles = Get-GitTrackedFiles -workDir $aiPath
        if ($aiFiles) {
            Write-Host "Including ai/ clone ($($aiFiles.Count) files)..." -ForegroundColor Cyan
            foreach ($f in $aiFiles) {
                $allFiles += @{ RelPath = "ai/$f"; BaseDir = $repoRoot }
            }
        }
    }
}

$totalFiles = $allFiles.Count
Write-Host "Found $totalFiles Git-tracked files to analyze" -ForegroundColor Cyan
Write-Host ""

$withBom = @()
$withoutBom = @()
$binary = @()
$processed = 0
$lastPercent = -1

foreach ($entry in $allFiles) {
    $processed++
    $file = $entry.RelPath
    $baseDir = $entry.BaseDir

    # Show progress every 5%
    $percent = [math]::Floor(($processed / $totalFiles) * 100)
    if ($percent -ne $lastPercent -and $percent % 5 -eq 0) {
        $currentDir = Split-Path -Parent $file
        if ($currentDir.Length -gt 60) {
            $currentDir = "..." + $currentDir.Substring($currentDir.Length - 57)
        }
        Write-Host ("{0,3}% complete - {1}" -f $percent, $currentDir) -ForegroundColor Gray
        $lastPercent = $percent
    }

    # Convert forward slashes to backslashes for Windows
    $filePath = $file.Replace('/', '\')
    $result = Test-FileBom -filePath $filePath -baseDir $baseDir

    switch ($result) {
        "bom" { $withBom += $file }
        "no-bom" { $withoutBom += $file }
        "binary" { $binary += $file }
    }
}

Write-Host ""
Write-Host "=== UTF-8 BOM Analysis (Git-tracked files) ===" -ForegroundColor Cyan
Write-Host ""
$analyzedCount = $withBom.Count + $withoutBom.Count + $binary.Count
Write-Host "Total files processed:   $totalFiles" -ForegroundColor White
Write-Host "Successfully analyzed:   $analyzedCount" -ForegroundColor White
Write-Host "Files WITH BOM:          $($withBom.Count)" -ForegroundColor Yellow
Write-Host "Files WITHOUT BOM:       $($withoutBom.Count)" -ForegroundColor Green
Write-Host "Binary/unreadable:       $($binary.Count)" -ForegroundColor Gray
Write-Host ""

# Calculate percentage (excluding binary)
$textFiles = $withBom.Count + $withoutBom.Count
if ($textFiles -gt 0) {
    $bomPercent = [math]::Round(($withBom.Count / $textFiles) * 100, 2)
    Write-Host "Percentage of text files with BOM: $bomPercent%" -ForegroundColor $(if ($bomPercent -lt 10) { "Green" } else { "Yellow" })
    Write-Host ""
}

# Show breakdown by extension for files WITH BOM
if ($withBom.Count -gt 0) {
    Write-Host "=== Files WITH BOM (by extension) ===" -ForegroundColor Yellow
    $withBom | ForEach-Object { [System.IO.Path]::GetExtension($_).ToLower() } | 
               Where-Object { $_ -ne '' } |
               Group-Object | 
               Sort-Object Count -Descending | 
               ForEach-Object { Write-Host "  $($_.Name): $($_.Count)" -ForegroundColor Yellow }
    Write-Host ""
    
    Write-Host "=== Sample files WITH BOM (first 30) ===" -ForegroundColor Yellow
    $withBom | Select-Object -First 30 | ForEach-Object {
        Write-Host "  $_" -ForegroundColor Yellow
    }
    if ($withBom.Count -gt 30) {
        Write-Host "  ... and $($withBom.Count - 30) more" -ForegroundColor Yellow
    }
    Write-Host ""

    # Export full list if output file specified
    if ($OutputFile) {
        $withBom | Out-File -FilePath $OutputFile -Encoding ASCII
        Write-Host "Full list written to: $OutputFile" -ForegroundColor Cyan
        Write-Host ""
    }
}

Write-Host "=== Recommendation ===" -ForegroundColor Cyan
if ($withBom.Count -eq 0) {
    Write-Host "Project is BOM-free! No action needed." -ForegroundColor Green
} elseif ($bomPercent -lt 5) {
    Write-Host "Less than 5% of files have BOM. Recommend converting to UTF-8 without BOM." -ForegroundColor Green
} elseif ($bomPercent -lt 25) {
    Write-Host "Small minority of files have BOM. Recommend converting to UTF-8 without BOM." -ForegroundColor Yellow
} else {
    Write-Host "Significant number of files have BOM ($bomPercent%). Review and standardize." -ForegroundColor Yellow
    Write-Host "Modern best practice: UTF-8 without BOM for source code." -ForegroundColor Yellow
}
Write-Host ""

