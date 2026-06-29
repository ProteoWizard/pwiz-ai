<#
.SYNOPSIS
    Summarize an Osprey dotCover JSON coverage report.

.DESCRIPTION
    Reads the JSON report produced by `Build-Osprey.ps1 -Coverage`
    (dotCover) and prints a whole-project picture aimed at a test-coverage
    review:
      - overall statement coverage across the Osprey.* assemblies
      - per-assembly coverage table
      - the types with the most uncovered statements (where new tests pay off)
      - types with zero coverage

    Unlike the Skyline Analyze-Coverage.ps1 (which is pattern-driven and
    selects a single project), this walks every Osprey.* assembly in the
    report, which is the right shape for a first, whole-project review.

.PARAMETER CoverageJsonPath
    Path to the dotCover JSON report (e.g. ai\.tmp\osprey-coverage-*.json).

.PARAMETER TopTypes
    Number of least-covered types to list (default 30).

.PARAMETER MinUncovered
    Only list types with at least this many uncovered statements in the
    "most uncovered" section, to suppress trivial noise (default 5).

.EXAMPLE
    .\Summarize-Coverage.ps1 -CoverageJsonPath ai\.tmp\osprey-coverage-20260608-153000.json
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$CoverageJsonPath,

    [Parameter(Mandatory=$false)]
    [int]$TopTypes = 30,

    [Parameter(Mandatory=$false)]
    [int]$MinUncovered = 5
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

if (-not (Test-Path $CoverageJsonPath)) {
    Write-Host "Coverage JSON not found: $CoverageJsonPath" -ForegroundColor Red
    exit 1
}

$coverage = Get-Content $CoverageJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json

function Format-Percent {
    param([int]$covered, [int]$total)
    if ($total -le 0) { return 0 }
    return [math]::Round(($covered / $total) * 100, 1)
}

function Get-PercentColor {
    param([double]$percent)
    if ($percent -ge 80) { return "Green" }
    elseif ($percent -ge 50) { return "Yellow" }
    else { return "Red" }
}

# Walk the tree collecting every Type node with its assembly and dotted path.
function Collect-Types {
    param(
        [object]$node,
        [string]$assembly = "",
        [string]$path = ""
    )

    $results = @()

    $currentAssembly = $assembly
    if ($node.Kind -eq "Assembly" -or $node.Kind -eq "Project") {
        $currentAssembly = $node.Name
    }

    if ($node.Kind -eq "Type") {
        $typeName = $node.Name -replace '<.*>$', ''
        $fullPath = if ($path) { "$path.$typeName" } else { $typeName }
        $results += [PSCustomObject]@{
            Assembly          = $currentAssembly
            Type              = $fullPath
            CoveredStatements = [int]$node.CoveredStatements
            TotalStatements   = [int]$node.TotalStatements
            Uncovered         = [int]$node.TotalStatements - [int]$node.CoveredStatements
        }
        # Do not recurse into a Type's members - statements are aggregated at the Type.
        return $results
    }

    if ($node.Children) {
        $newPath = if ($node.Kind -eq "Namespace") {
            if ($path) { "$path.$($node.Name)" } else { $node.Name }
        } else {
            $path
        }
        foreach ($child in $node.Children) {
            $results += Collect-Types -node $child -assembly $currentAssembly -path $newPath
        }
    }

    return $results
}

$separator = "=" * 80

# Per-assembly totals come straight from the top-level assembly nodes
$assemblies = $coverage.Children | Where-Object {
    ($_.Kind -eq "Assembly" -or $_.Kind -eq "Project") -and $_.Name -like "Osprey*"
}

if (-not $assemblies) {
    Write-Host "No Osprey* assemblies found in the coverage report." -ForegroundColor Red
    Write-Host "Top-level items:" -ForegroundColor Yellow
    $coverage.Children | ForEach-Object { Write-Host "  - $($_.Name) ($($_.Kind))" -ForegroundColor Gray }
    exit 1
}

$overallCovered = ($assemblies | Measure-Object -Property CoveredStatements -Sum).Sum
$overallTotal = ($assemblies | Measure-Object -Property TotalStatements -Sum).Sum
$overallPercent = Format-Percent $overallCovered $overallTotal

Write-Host $separator -ForegroundColor Cyan
Write-Host "OSPREY TEST COVERAGE SUMMARY" -ForegroundColor Cyan
Write-Host $separator -ForegroundColor Cyan
Write-Host ""
Write-Host "Overall: $overallPercent% ($overallCovered / $overallTotal statements, $($overallTotal - $overallCovered) uncovered)" -ForegroundColor (Get-PercentColor $overallPercent)
Write-Host ""

Write-Host "Coverage by assembly (sorted by uncovered count):" -ForegroundColor Cyan
$assemblyRows = $assemblies | ForEach-Object {
    [PSCustomObject]@{
        Assembly  = $_.Name
        Covered   = [int]$_.CoveredStatements
        Total     = [int]$_.TotalStatements
        Uncovered = [int]$_.TotalStatements - [int]$_.CoveredStatements
        Percent   = Format-Percent ([int]$_.CoveredStatements) ([int]$_.TotalStatements)
    }
} | Sort-Object Uncovered -Descending

foreach ($row in $assemblyRows) {
    $line = "  {0,-30} {1,6}% ({2} uncovered / {3} total)" -f $row.Assembly, $row.Percent, $row.Uncovered, $row.Total
    Write-Host $line -ForegroundColor (Get-PercentColor $row.Percent)
}
Write-Host ""

# Per-type detail for the "where to add tests" view
$allTypes = @()
foreach ($asm in $assemblies) {
    $allTypes += Collect-Types -node $asm -assembly $asm.Name
}

$worst = $allTypes |
    Where-Object { $_.Uncovered -ge $MinUncovered } |
    Sort-Object Uncovered -Descending |
    Select-Object -First $TopTypes

if ($worst.Count -gt 0) {
    Write-Host "Top $($worst.Count) types by uncovered statements (>= $MinUncovered uncovered):" -ForegroundColor Cyan
    foreach ($t in $worst) {
        $pct = Format-Percent $t.CoveredStatements $t.TotalStatements
        $line = "  {0,4} uncovered  {1,5}%  {2} [{3}]" -f $t.Uncovered, $pct, $t.Type, $t.Assembly
        Write-Host $line -ForegroundColor (Get-PercentColor $pct)
    }
    Write-Host ""
}

$zero = $allTypes |
    Where-Object { $_.CoveredStatements -eq 0 -and $_.TotalStatements -gt 0 } |
    Sort-Object TotalStatements -Descending

if ($zero.Count -gt 0) {
    Write-Host "Types with zero coverage ($($zero.Count) types):" -ForegroundColor Red
    foreach ($t in $zero) {
        Write-Host ("  {0,4} statements  {1} [{2}]" -f $t.TotalStatements, $t.Type, $t.Assembly) -ForegroundColor Red
    }
    Write-Host ""
}

Write-Host $separator -ForegroundColor Cyan
