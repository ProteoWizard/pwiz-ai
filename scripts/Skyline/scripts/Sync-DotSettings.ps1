<#!
.SYNOPSIS
    Synchronize ReSharper .DotSettings across Skyline, SkylineBatch, and AutoQC.

.DESCRIPTION
    Copies Skyline.sln.DotSettings as the canonical baseline to SkylineBatch.sln.DotSettings and AutoQC.sln.DotSettings
    applying intentional severity overrides (currently LocalizableElement: WARNING -> HINT) for batch tools.
    Skips rewrite if target already matches intended content to avoid unnecessary Git diffs.

.NOTES
    Run early in each build script to keep inspection configuration aligned.
    Extend $overrides map for future tool-specific severity adjustments.
    Safe for repeated invocation.

#>
param(
    [switch]$VerboseOutput = $false,
    [string]$SourceRoot = $null  # Path to pwiz root (auto-detected if not specified)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Info($msg) { Write-Host $msg -ForegroundColor Cyan }
function Write-Change($msg) { Write-Host $msg -ForegroundColor Green }
function Write-Skip($msg) { Write-Host $msg -ForegroundColor Yellow }
function Write-ErrorLine($msg) { Write-Host $msg -ForegroundColor Red }

# Script location: ai/scripts/Skyline/scripts/
$scriptRoot = Split-Path -Parent $PSCommandPath
$aiRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $scriptRoot))  # ai/

# Auto-detect pwiz root location
if ($SourceRoot) {
    # Resolve to absolute path (relative paths break after Set-Location)
    $pwizRoot = (Resolve-Path $SourceRoot).Path
} else {
    # Try sibling mode first: ai/ and pwiz/ are siblings under common parent
    $siblingPath = Join-Path (Split-Path -Parent $aiRoot) 'pwiz'
    # Then try child mode: ai/ is inside pwiz/
    $childPath = Split-Path -Parent $aiRoot

    if (Test-Path (Join-Path $siblingPath 'pwiz_tools')) {
        $pwizRoot = $siblingPath
    } elseif (Test-Path (Join-Path $childPath 'pwiz_tools')) {
        $pwizRoot = $childPath
    } else {
        Write-ErrorLine "Cannot find pwiz_tools. Tried:`n  Sibling mode: $siblingPath`n  Child mode: $childPath`nUse -SourceRoot to specify the pwiz root directory."
        exit 1
    }
}

$skylineRoot = Join-Path $pwizRoot 'pwiz_tools/Skyline'
$baselinePath = Join-Path $skylineRoot 'Skyline.sln.DotSettings'

if (-not (Test-Path $baselinePath)) {
    Write-ErrorLine "Baseline DotSettings not found: $baselinePath"
    exit 1
}

$targets = @(
    @{ Name = 'SkylineBatch'; Path = Join-Path $skylineRoot 'Executables/SkylineBatch/SkylineBatch.sln.DotSettings'; ApplyOverrides = $true },
    @{ Name = 'AutoQC';       Path = Join-Path $skylineRoot 'Executables/AutoQC/AutoQC.sln.DotSettings';             ApplyOverrides = $true }
)

# Map of overrides (regex pattern => replacement) applied only when ApplyOverrides = $true
# Intent: Lower localization noise for batch tools (treat as HINT rather than WARNING)
$overrides = @(
    @{ Pattern = '(?m)(<s:String x:Key="/Default/CodeInspection/Highlighting/InspectionSeverities/=LocalizableElement/@EntryIndexedValue">)WARNING(<[/]s:String>)'; Replacement = '$1HINT$2' }
)

$baselineContent = Get-Content -LiteralPath $baselinePath -Raw

foreach ($t in $targets) {
    $targetPath = $t.Path
    $name = $t.Name
    if (-not (Test-Path $targetPath)) {
        Write-Skip "Target missing ($name) - creating from baseline"
        $newContent = $baselineContent
        if ($t.ApplyOverrides) {
            foreach ($ov in $overrides) { $newContent = [Regex]::Replace($newContent, $ov.Pattern, $ov.Replacement) }
        }
        $newContent | Set-Content -LiteralPath $targetPath -Encoding UTF8
        Write-Change "Created $name DotSettings"
        continue
    }

    $current = Get-Content -LiteralPath $targetPath -Raw
    $desired = $baselineContent
    if ($t.ApplyOverrides) {
        foreach ($ov in $overrides) { $desired = [Regex]::Replace($desired, $ov.Pattern, $ov.Replacement) }
    }

    if ($current -eq $desired) {
        if ($VerboseOutput) { Write-Skip "No change needed for $name" }
        continue
    }

    $backupPath = "$targetPath.bak"
    $current | Set-Content -LiteralPath $backupPath -Encoding UTF8
    $desired | Set-Content -LiteralPath $targetPath -Encoding UTF8
    Write-Change "Updated $name DotSettings (backup saved: $backupPath)"

    if ($VerboseOutput) {
        # Simple diff summary: count differing lines
        $currentLines = $current -split "`r?`n"
        $desiredLines = $desired -split "`r?`n"
        $diffCount = 0
        for ($i=0; $i -lt [Math]::Max($currentLines.Length, $desiredLines.Length); $i++) {
            if ($currentLines[$i] -ne $desiredLines[$i]) { $diffCount++ }
        }
        Write-Info "Changed lines (approx): $diffCount"
    }
}

Write-Info 'DotSettings synchronization complete.'
