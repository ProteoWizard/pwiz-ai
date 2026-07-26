<#
.SYNOPSIS
    Lines-of-code audit: Osprey (C#) vs osprey (Rust reference).

.DESCRIPTION
    Counts executable source lines with cloc and reports, side by side,
    the size of the C# implementation (pwiz_tools/Osprey) and the Rust
    reference (osprey). Totals come from whole-tree cloc runs, so the
    numbers stay correct as projects are added or renamed -- nothing is
    hardcoded. The Rust side ships tests inline (`#[cfg(test)]`); the C#
    side keeps them in a separate Osprey.Test project, so both are split
    into production vs test for an apples-to-apples comparison.

    Prints a summary and a "C# vs Rust on every measure" comparison to
    the console, and saves a Markdown report under ai/.tmp/.

    Use -ByModule to add an auto-discovered per-project / per-crate table.

.PARAMETER CSharpRoot
    Path to the Osprey C# solution directory.
    Default: $env:PWIZ_LSP_DIR\Osprey if set (the active checkout),
    else <projRoot>\pwiz\pwiz_tools\Osprey.

.PARAMETER RustRoot
    Path to the osprey Rust reference directory.
    Default: <projRoot>\osprey.

.PARAMETER OutputPath
    Where to write the Markdown report.
    Default: <projRoot>\ai\.tmp\osprey-loc-audit-YYYYMMDD-HHMM.md.

.PARAMETER ByModule
    Also emit a per-project (C#) / per-crate (Rust) breakdown, paired by
    name. Projects with no counterpart (e.g. Osprey.Tasks,
    Osprey.Diagnostics) are shown as C#-only.

.EXAMPLE
    pwsh -File ./ai/scripts/Osprey/Audit-Loc.ps1

.EXAMPLE
    pwsh -File ./ai/scripts/Osprey/Audit-Loc.ps1 -ByModule

.NOTES
    Requires cloc: winget install AlDanial.Cloc
#>

[CmdletBinding()]
param(
    [string]$CSharpRoot,
    [string]$RustRoot,
    [string]$OutputPath,
    [switch]$ByModule
)

$ErrorActionPreference = 'Stop'

# --- Resolve roots ---------------------------------------------------------
# Script lives at ai/scripts/Osprey -> parents: scripts, ai, projRoot.
$aiRoot   = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$projRoot = Split-Path -Parent $aiRoot

if (-not $CSharpRoot) {
    if ($env:PWIZ_LSP_DIR) { $CSharpRoot = Join-Path $env:PWIZ_LSP_DIR 'Osprey' }
    else                   { $CSharpRoot = Join-Path $projRoot 'pwiz\pwiz_tools\Osprey' }
}
if (-not $RustRoot) { $RustRoot = Join-Path $projRoot 'osprey' }

# --- Preconditions ---------------------------------------------------------
if (-not (Get-Command cloc -ErrorAction SilentlyContinue)) {
    Write-Error "cloc is not installed. Install with: winget install AlDanial.Cloc"
    exit 1
}
if (-not (Test-Path $CSharpRoot)) { Write-Error "CSharpRoot not found: $CSharpRoot"; exit 1 }
if (-not (Test-Path $RustRoot))   { Write-Error "RustRoot not found: $RustRoot";   exit 1 }

function Format-Number { param([int]$n) return $n.ToString('N0') }
function Format-Kloc   { param([int]$n) return ('{0:N1}K' -f ($n / 1000.0)) }
function Get-Ratio     { param([double]$Cs, [double]$Rust) if ($Rust -eq 0) { return 'n/a' } return ('{0:N2}x' -f ($Cs / $Rust)) }

# Run cloc on a directory for one language; return the aggregate summary row.
function Invoke-ClocSummary {
    param([string]$Path, [string]$Language)

    $empty = @{ Files = 0; Code = 0; Comment = 0; Blank = 0 }
    if (-not (Test-Path $Path)) { return $empty }

    $csv = & cloc $Path --csv --quiet --include-lang="$Language" --exclude-dir=obj,bin,TestResults,target 2>$null

    $result = $empty.Clone()
    foreach ($line in $csv) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = $line -split ','
        if ($parts.Count -lt 5) { continue }
        # cloc summary CSV row: files,language,blank,comment,code
        if ($parts[1] -ne $Language) { continue }
        [int]$f = 0
        if (-not [int]::TryParse($parts[0], [ref]$f)) { continue }
        $result.Files   = $f
        $result.Blank   = [int]$parts[2]
        $result.Comment = [int]$parts[3]
        $result.Code    = [int]$parts[4]
    }
    return $result
}

# Estimate Rust production vs inline-test split by scanning each .rs file for
# its first `#[cfg(test)]` line; everything from there to EOF counts as test.
# Returns the production fraction of non-blank, non-line-comment lines.
function Get-RustProdFraction {
    param([string]$Path)

    $prod = 0; $test = 0
    $files = Get-ChildItem -Path $Path -Filter '*.rs' -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notlike '*\target\*' }
    foreach ($f in $files) {
        $lines = [IO.File]::ReadAllLines($f.FullName)
        $testStart = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^\s*#\[cfg\(test\)\]') { $testStart = $i; break }
        }
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $t = $lines[$i].Trim()
            if ($t -eq '' -or $t.StartsWith('//')) { continue }
            if ($testStart -ge 0 -and $i -ge $testStart) { $test++ } else { $prod++ }
        }
    }
    $total = $prod + $test
    if ($total -eq 0) { return 1.0 }
    return [double]$prod / $total
}

Write-Host 'Osprey lines-of-code audit' -ForegroundColor Cyan
Write-Host "  C# root:   $CSharpRoot" -ForegroundColor Gray
Write-Host "  Rust root: $RustRoot"  -ForegroundColor Gray
Write-Host '  Running cloc...' -ForegroundColor Gray

# --- Authoritative whole-tree totals --------------------------------------
$csAll  = Invoke-ClocSummary -Path $CSharpRoot -Language 'C#'
$csTest = Invoke-ClocSummary -Path (Join-Path $CSharpRoot 'Osprey.Test') -Language 'C#'
$csProd = @{
    Files   = $csAll.Files   - $csTest.Files
    Code    = $csAll.Code    - $csTest.Code
    Comment = $csAll.Comment - $csTest.Comment
    Blank   = $csAll.Blank   - $csTest.Blank
}

$rustAll = Invoke-ClocSummary -Path $RustRoot -Language 'Rust'
$prodFraction = Get-RustProdFraction -Path $RustRoot
$rustProdCode = [int][math]::Round($rustAll.Code * $prodFraction)
$rustTestCode = $rustAll.Code - $rustProdCode

# Derived totals (code + comment + blank = all physical lines)
$csAllTotal   = $csAll.Code   + $csAll.Comment   + $csAll.Blank
$rustAllTotal = $rustAll.Code + $rustAll.Comment + $rustAll.Blank

# --- Per-module (optional) -------------------------------------------------
$moduleRows = @()
if ($ByModule) {
    # Normalize a project/crate name to a pairing key: "Osprey.Core" -> "core",
    # "osprey-core" -> "core", main exe "Osprey"/"osprey" -> "main".
    function Get-ModuleKey {
        param([string]$Name)
        $n = $Name.ToLower() -replace '^osprey[.\-]?', ''
        if ($n -eq '') { return 'main' }
        return $n
    }

    $csProjects = Get-ChildItem -Path $CSharpRoot -Directory |
        Where-Object { (Get-ChildItem $_.FullName -Filter *.csproj -File) -and $_.Name -ne 'Osprey.Test' }
    $rustCrates = @()
    $cratesDir = Join-Path $RustRoot 'crates'
    if (Test-Path $cratesDir) { $rustCrates = Get-ChildItem -Path $cratesDir -Directory }

    $csByKey   = @{}; foreach ($p in $csProjects) { $csByKey[(Get-ModuleKey $p.Name)]   = $p }
    $rustByKey = @{}; foreach ($c in $rustCrates) { $rustByKey[(Get-ModuleKey $c.Name)] = $c }

    foreach ($key in @($csByKey.Keys + $rustByKey.Keys | Sort-Object -Unique)) {
        $csName = if ($csByKey.ContainsKey($key))   { $csByKey[$key].Name }   else { '-' }
        $rsName = if ($rustByKey.ContainsKey($key)) { $rustByKey[$key].Name } else { '-' }
        $csM = if ($csByKey.ContainsKey($key))   { Invoke-ClocSummary $csByKey[$key].FullName   'C#'   } else { @{ Files = 0; Code = 0 } }
        $rsM = if ($rustByKey.ContainsKey($key)) { Invoke-ClocSummary $rustByKey[$key].FullName 'Rust' } else { @{ Files = 0; Code = 0 } }
        $moduleRows += [pscustomobject]@{
            Module   = $key
            CSName   = $csName
            CSFiles  = $csM.Files
            CSCode   = $csM.Code
            RustName = $rsName
            RustCode = $rsM.Code
            Ratio    = (Get-Ratio $csM.Code $rsM.Code)
        }
    }
}

# --- Comparison table (every measure) -------------------------------------
$measures = @(
    @{ Label = 'Production code'; Cs = $csProd.Code;  Rust = $rustProdCode },
    @{ Label = 'Test code';       Cs = $csTest.Code;  Rust = $rustTestCode },
    @{ Label = 'All code';        Cs = $csAll.Code;   Rust = $rustAll.Code },
    @{ Label = 'Comment lines';   Cs = $csAll.Comment; Rust = $rustAll.Comment },
    @{ Label = 'Files';           Cs = $csAll.Files;  Rust = $rustAll.Files },
    @{ Label = 'All lines';       Cs = $csAllTotal;   Rust = $rustAllTotal }
)

# --- Console output --------------------------------------------------------
Write-Host ''
Write-Host ('=' * 68) -ForegroundColor Cyan
Write-Host 'OSPREY LINES OF CODE  (executable code via cloc)' -ForegroundColor Cyan
Write-Host ('=' * 68) -ForegroundColor Cyan
$fmt = '{0,-18} {1,12} {2,12} {3,10}'
Write-Host ($fmt -f 'Measure', 'C#', 'Rust', 'C#/Rust') -ForegroundColor Yellow
Write-Host ($fmt -f '-------', '--', '----', '-------')
foreach ($m in $measures) {
    Write-Host ($fmt -f $m.Label, (Format-Number $m.Cs), (Format-Number $m.Rust), (Get-Ratio $m.Cs $m.Rust))
}
Write-Host ''
Write-Host ('C# production: {0} code / {1} tests = {2} total code across {3} files' -f `
    (Format-Number $csProd.Code), (Format-Number $csTest.Code), (Format-Number $csAll.Code), (Format-Number $csAll.Files)) -ForegroundColor Green
Write-Host ('Rust (est):    {0} production + {1} inline tests = {2} total code across {3} files' -f `
    (Format-Number $rustProdCode), (Format-Number $rustTestCode), (Format-Number $rustAll.Code), (Format-Number $rustAll.Files)) -ForegroundColor Green
Write-Host ''

if ($ByModule) {
    Write-Host 'Per-module (C# code / Rust code):' -ForegroundColor Yellow
    $mfmt = '  {0,-16} {1,-22} {2,9}  {3,-18} {4,9}  {5,8}'
    Write-Host ($mfmt -f 'Key', 'C# project', 'C# code', 'Rust crate', 'Rust code', 'C#/Rust')
    foreach ($r in ($moduleRows | Sort-Object { -$_.CSCode })) {
        Write-Host ($mfmt -f $r.Module, $r.CSName, (Format-Number $r.CSCode), $r.RustName, (Format-Number $r.RustCode), $r.Ratio)
    }
    Write-Host ''
}

# --- Markdown report -------------------------------------------------------
$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$larger = ($measures | Where-Object { $_.Cs -gt $_.Rust }).Count
$everyMeasure = if ($larger -eq $measures.Count) { 'C# is larger than Rust on every measure below.' }
                else { "C# is larger than Rust on $larger of $($measures.Count) measures below." }

$sb = [System.Text.StringBuilder]::new()
$null = $sb.AppendLine('# Osprey (C#) vs osprey (Rust) -- Lines of Code Audit')
$null = $sb.AppendLine()
$null = $sb.AppendLine("Generated: $timestamp")
$null = $sb.AppendLine("C# root:   ``$CSharpRoot``")
$null = $sb.AppendLine("Rust root: ``$RustRoot``")
$null = $sb.AppendLine()
$null = $sb.AppendLine('Counts are executable code from `cloc` (build artifacts excluded). The Rust')
$null = $sb.AppendLine('production/test split is a heuristic: per `.rs` file, the first `#[cfg(test)]`')
$null = $sb.AppendLine('line marks the boundary and everything to EOF is treated as test.')
$null = $sb.AppendLine()
$null = $sb.AppendLine("**$everyMeasure**")
$null = $sb.AppendLine()
$null = $sb.AppendLine('| Measure | C# | Rust | C# / Rust |')
$null = $sb.AppendLine('|---|---:|---:|---:|')
foreach ($m in $measures) {
    $null = $sb.AppendLine(('| {0} | {1} | {2} | {3} |' -f $m.Label, (Format-Number $m.Cs), (Format-Number $m.Rust), (Get-Ratio $m.Cs $m.Rust)))
}
$null = $sb.AppendLine()
$null = $sb.AppendLine('## Grand totals')
$null = $sb.AppendLine()
$null = $sb.AppendLine('| Scope | Files | Code | KLOC |')
$null = $sb.AppendLine('|---|---:|---:|---:|')
$null = $sb.AppendLine(('| C# production | {0} | {1} | {2} |' -f (Format-Number $csProd.Files), (Format-Number $csProd.Code), (Format-Kloc $csProd.Code)))
$null = $sb.AppendLine(('| C# tests (Osprey.Test) | {0} | {1} | {2} |' -f (Format-Number $csTest.Files), (Format-Number $csTest.Code), (Format-Kloc $csTest.Code)))
$null = $sb.AppendLine(('| **C# all code** | **{0}** | **{1}** | **{2}** |' -f (Format-Number $csAll.Files), (Format-Number $csAll.Code), (Format-Kloc $csAll.Code)))
$null = $sb.AppendLine(('| Rust production (est) | | {0} | {1} |' -f (Format-Number $rustProdCode), (Format-Kloc $rustProdCode)))
$null = $sb.AppendLine(('| Rust inline tests (est) | | {0} | {1} |' -f (Format-Number $rustTestCode), (Format-Kloc $rustTestCode)))
$null = $sb.AppendLine(('| **Rust all code** | **{0}** | **{1}** | **{2}** |' -f (Format-Number $rustAll.Files), (Format-Number $rustAll.Code), (Format-Kloc $rustAll.Code)))

if ($ByModule) {
    $null = $sb.AppendLine()
    $null = $sb.AppendLine('## Per-module (auto-discovered)')
    $null = $sb.AppendLine()
    $null = $sb.AppendLine('C# projects paired to Rust crates by name; `-` means no counterpart.')
    $null = $sb.AppendLine()
    $null = $sb.AppendLine('| Key | C# project | C# code | Rust crate | Rust code | C# / Rust |')
    $null = $sb.AppendLine('|---|---|---:|---|---:|---:|')
    foreach ($r in ($moduleRows | Sort-Object { -$_.CSCode })) {
        $null = $sb.AppendLine(('| {0} | {1} | {2} | {3} | {4} | {5} |' -f $r.Module, $r.CSName, (Format-Number $r.CSCode), $r.RustName, (Format-Number $r.RustCode), $r.Ratio))
    }
}
$null = $sb.AppendLine()
$null = $sb.AppendLine('---')
$null = $sb.AppendLine('Regenerate: `pwsh -File ./ai/scripts/Osprey/Audit-Loc.ps1 [-ByModule]`')

# --- Save ------------------------------------------------------------------
if (-not $OutputPath) {
    $tmpDir = Join-Path $aiRoot '.tmp'
    if (-not (Test-Path $tmpDir)) { New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null }
    $OutputPath = Join-Path $tmpDir ('osprey-loc-audit-{0}.md' -f (Get-Date -Format 'yyyyMMdd-HHmm'))
}
$sb.ToString() | Set-Content -Path $OutputPath -Encoding UTF8
Write-Host "Report saved: $OutputPath" -ForegroundColor Green
