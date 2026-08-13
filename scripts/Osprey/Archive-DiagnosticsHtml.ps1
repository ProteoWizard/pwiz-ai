<#
.SYNOPSIS
    Copy every *.model-diagnostics.html under a run root into a flat archive folder,
    named <dataset>-<leg>.html so the copies stay distinguishable.

.DESCRIPTION
    regression.ps1 prunes previous TestResults run directories on every invocation, so a
    diagnostics page is gone the moment the next gate starts. This preserves the interesting
    ones somewhere that is not pruned.

    Exists as a script rather than an inline one-liner because the inline version silently
    produced a single file: the destination path interpolated to empty and each copy
    overwrote the last, while the progress lines printed the correct names. A file cannot
    have that class of quoting bug.

.PARAMETER RunRoot
    Directory to search recursively. Defaults to the newest regression-* run.

.PARAMETER Destination
    Archive folder; created if absent.
#>
[CmdletBinding()]
param(
    [string]$RunRoot,
    [Parameter(Mandatory = $true)][string]$Destination
)

$ErrorActionPreference = 'Stop'

if (-not $RunRoot) {
    $testResults = Join-Path $PSScriptRoot '..\..\..\pwiz\pwiz_tools\Osprey\TestResults'
    $newest = Get-ChildItem $testResults -Directory -Filter 'regression-*' -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1
    if (-not $newest) { throw "No regression-* run directory found under $testResults" }
    $RunRoot = $newest.FullName
}

if (-not (Test-Path $Destination)) {
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
}

Write-Host "Run root:    $RunRoot"
Write-Host "Destination: $Destination"

# '*.model-diagnostics.html', not 'output.model-diagnostics.html': the report is named after
# the -o blib, so a run invoked with '-o out.blib' (which the SEA-AD and TDP43 runners do)
# writes out.model-diagnostics.html and was silently skipped - "No diagnostics pages found"
# on a run that had one.
$pages = Get-ChildItem $RunRoot -Recurse -Filter '*.model-diagnostics.html' -ErrorAction SilentlyContinue
if (-not $pages) {
    Write-Host 'No diagnostics pages found.'
    return
}

$n = 0
foreach ($page in $pages) {
    $leg = $page.Directory.Name
    $dataset = $page.Directory.Parent.Name
    $name = '{0}-{1}.html' -f $dataset, $leg
    $dest = Join-Path $Destination $name
    Copy-Item -LiteralPath $page.FullName -Destination $dest -Force
    $n++
    Write-Host ('  {0,-34} {1,12:N0} bytes' -f $name, $page.Length)
}
Write-Host "Archived $n page(s)."
