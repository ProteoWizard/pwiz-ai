<#!
.SYNOPSIS
    Synchronize ReSharper .DotSettings from Skyline to SkylineBatch, AutoQC, SkylineMcp and Pwiz.sln.

.DESCRIPTION
    Copies Skyline.sln.DotSettings as the canonical baseline to each target's .sln.DotSettings,
    applying that target's intentional overrides: LocalizableElement WARNING -> HINT for the batch
    tools, and localization off by default for Pwiz.sln.
    Skips rewrite if target already matches intended content to avoid unnecessary Git diffs.

.NOTES
    Run early in each build script to keep inspection configuration aligned.
    Give a target its own Overrides list for tool-specific adjustments.
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

# Overrides (regex pattern => replacement) applied to the baseline for a target.
# Batch tools: lower localization noise (treat as HINT rather than WARNING).
$batchToolOverrides = @(
    @{ Pattern = '(?m)(<s:String x:Key="/Default/CodeInspection/Highlighting/InspectionSeverities/=LocalizableElement/@EntryIndexedValue">)WARNING(<[/]s:String>)'; Replacement = '$1HINT$2' }
)
# Pwiz.sln: projects are not localizable unless they opt in with their own *.csproj.DotSettings
# Localizable=Yes (CommonUtil, CommonMsData and MSGraph do). Inserted after the opening element,
# reusing the file's own line ending.
$pwizOverrides = @(
    @{ Pattern = '^(<wpf:ResourceDictionary[^\r\n]*(\r?\n))'; Replacement = "`$1`t<s:String x:Key=`"/Default/CodeEditing/Localization/Localizable/@EntryValue`">No</s:String>`$2" }
)

# Requires: a file that must exist for the target to apply; checkouts older than Pwiz.sln skip it.
$targets = @(
    @{ Name = 'SkylineBatch'; Path = Join-Path $skylineRoot 'Executables/SkylineBatch/SkylineBatch.sln.DotSettings'; Overrides = $batchToolOverrides },
    @{ Name = 'AutoQC';       Path = Join-Path $skylineRoot 'Executables/AutoQC/AutoQC.sln.DotSettings';             Overrides = $batchToolOverrides },
    @{ Name = 'SkylineMcp';   Path = Join-Path $skylineRoot 'Executables/Tools/SkylineMcp/SkylineMcp.sln.DotSettings'; Overrides = $batchToolOverrides },
    @{ Name = 'Pwiz';         Path = Join-Path $pwizRoot 'Pwiz.sln.DotSettings'; Overrides = $pwizOverrides; Requires = Join-Path $pwizRoot 'Pwiz.sln' }
)

$baselineContent = Get-Content -LiteralPath $baselinePath -Raw

foreach ($t in $targets) {
    $targetPath = $t.Path
    $name = $t.Name
    $desired = $baselineContent
    foreach ($ov in $t.Overrides) { $desired = [Regex]::Replace($desired, $ov.Pattern, $ov.Replacement) }
    if ($t.ContainsKey('Requires') -and -not (Test-Path $t.Requires)) {
        Write-Skip "$(Split-Path -Leaf $t.Requires) absent ($name) - skipping"
        continue
    }
    if (-not (Test-Path $targetPath)) {
        # A release branch predates some tools; without the project directory there is nothing to configure.
        $targetDir = Split-Path -Parent $targetPath
        if (-not (Test-Path $targetDir)) {
            Write-Skip "Project absent ($name) - skipping"
            continue
        }
        Write-Skip "Target missing ($name) - creating from baseline"
        [System.IO.File]::WriteAllText($targetPath, $desired)
        Write-Change "Created $name DotSettings"
        continue
    }

    $current = Get-Content -LiteralPath $targetPath -Raw

    if ($current -eq $desired) {
        if ($VerboseOutput) { Write-Skip "No change needed for $name" }
        continue
    }

    [System.IO.File]::WriteAllText($targetPath, $desired)
    Write-Change "Updated $name DotSettings"

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
