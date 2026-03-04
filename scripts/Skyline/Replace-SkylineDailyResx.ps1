<#
.SYNOPSIS
    Replace "Skyline-daily" assembly references in RESX files with "Skyline"

.DESCRIPTION
    For major releases, RESX files contain assembly references like:
        pwiz.Skyline.Util.FormEx, Skyline-daily, Version=25.1.1.330, Culture=neutral, PublicKeyToken=null
    These need to become:
        pwiz.Skyline.Util.FormEx, Skyline, Version=1.0.0.0, Culture=neutral, PublicKeyToken=null

    This is Phase 1 of the release workflow (cherry-picked to both branches) to prevent
    sending "Skyline-daily" strings to translators.

    Excludes Executables/AutoQC and Executables/SharedBatch which have intentional
    user-facing "Skyline-daily" references.

.PARAMETER SkylineDir
    Path to the Skyline source directory (default: pwiz_tools/Skyline relative to repo root)

.PARAMETER DryRun
    Show what would be changed without modifying files

.EXAMPLE
    .\Replace-SkylineDailyResx.ps1 -DryRun
    Preview changes without modifying files

.EXAMPLE
    .\Replace-SkylineDailyResx.ps1
    Apply replacements to all RESX files

.NOTES
    To undo, revert the .resx files to HEAD: git checkout HEAD -- '*.resx'
#>
param(
    [string]$SkylineDir,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# Find repo root
if (-not $SkylineDir) {
    $repoRoot = git rev-parse --show-toplevel 2>$null
    if (-not $repoRoot) {
        Write-Error "Not in a git repository. Specify -SkylineDir explicitly."
        return
    }
    $SkylineDir = Join-Path $repoRoot 'pwiz_tools/Skyline'
}

if (-not (Test-Path $SkylineDir)) {
    Write-Error "Skyline directory not found: $SkylineDir"
    return
}

# Pattern and replacement
$findPattern = 'Skyline-daily, Version=[^,]+,'
$replaceWith = 'Skyline, Version=1.0.0.0,'
$description = "Skyline-daily -> Skyline"

Write-Host "Replace-SkylineDailyResx: $description" -ForegroundColor Cyan
Write-Host "  Directory: $SkylineDir"
Write-Host "  Find:      $findPattern"
Write-Host "  Replace:   $replaceWith"
if ($DryRun) { Write-Host "  Mode:      DRY RUN" -ForegroundColor Yellow }
Write-Host ""

# Find all .resx files, excluding AutoQC and SharedBatch
$resxFiles = Get-ChildItem -Path $SkylineDir -Filter '*.resx' -Recurse |
    Where-Object { $_.FullName -notmatch 'Executables[\\/](AutoQC|SharedBatch)' }

$totalReplacements = 0
$modifiedFiles = 0

foreach ($file in $resxFiles) {
    $content = Get-Content $file.FullName -Raw
    $matches = [regex]::Matches($content, $findPattern)

    if ($matches.Count -gt 0) {
        $relativePath = $file.FullName.Substring($SkylineDir.Length + 1)
        $totalReplacements += $matches.Count
        $modifiedFiles++

        if ($DryRun) {
            Write-Host "  $relativePath ($($matches.Count) replacements)" -ForegroundColor DarkGray
        } else {
            $newContent = $content -replace $findPattern, $replaceWith
            Set-Content -Path $file.FullName -Value $newContent -NoNewline
            Write-Host "  $relativePath ($($matches.Count) replacements)" -ForegroundColor Green
        }
    }
}

Write-Host ""
$verb = if ($DryRun) { "Would replace" } else { "Replaced" }
Write-Host "$verb $totalReplacements occurrences in $modifiedFiles files" -ForegroundColor Cyan
