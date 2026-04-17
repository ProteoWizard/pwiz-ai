<#
.SYNOPSIS
    Side-by-side lines-of-code audit: OspreySharp (C#) vs osprey (Rust fork).

.DESCRIPTION
    Counts executable source lines in each matching module of the two
    implementations and produces a module-by-module comparison.

    C# modules (pwiz_tools/OspreySharp/OspreySharp.*) pair with Rust
    crates (osprey/crates/osprey-*) by name:

        OspreySharp.Core          <-> osprey-core
        OspreySharp.IO            <-> osprey-io
        OspreySharp.Chromatography <-> osprey-chromatography
        OspreySharp.Scoring       <-> osprey-scoring
        OspreySharp.FDR           <-> osprey-fdr
        OspreySharp.ML            <-> osprey-ml
        OspreySharp               <-> osprey (main exe)
        OspreySharp.Test          <-> inline #[cfg(test)] in each crate

    cloc gives accurate total code per module. To split Rust test code
    from production, each .rs file is scanned for its first line
    matching `^\s*#\[cfg\(test\)\]`; lines from that point to EOF are
    treated as tests. This matches the standard Rust convention of
    placing `mod tests { ... }` at the bottom of each file. The
    resulting test/prod ratio is applied to cloc's accurate code
    total to split it.

    Report shows per-module files, code, total for each side, plus
    separate "Production" and "Production + Tests" grand totals with
    a C#/Rust ratio column.

.PARAMETER CSharpRoot
    Path to the OspreySharp solution directory
    (default: C:\proj\pwiz\pwiz_tools\OspreySharp).

.PARAMETER RustRoot
    Path to the osprey Rust fork directory
    (default: C:\proj\osprey).

.PARAMETER OutputPath
    Where to write the Markdown report. Default:
    C:\proj\ai\.tmp\osprey-loc-audit-YYYYMMDD-HHMM.md.

.EXAMPLE
    pwsh -File C:/proj/ai/scripts/OspreySharp/Audit-Loc.ps1

.EXAMPLE
    pwsh -File C:/proj/ai/scripts/OspreySharp/Audit-Loc.ps1 -CSharpRoot D:/other/OspreySharp

.NOTES
    Requires cloc: winget install AlDanial.Cloc
#>

[CmdletBinding()]
param(
    [string]$CSharpRoot = 'C:\proj\pwiz\pwiz_tools\OspreySharp',
    [string]$RustRoot = 'C:\proj\osprey',
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

# Verify cloc is available
$clocCmd = Get-Command cloc -ErrorAction SilentlyContinue
if (-not $clocCmd) {
    Write-Error @'
cloc is not installed. Install with:
    winget install AlDanial.Cloc
Then restart your shell.
'@
    exit 1
}

if (-not (Test-Path $CSharpRoot)) {
    Write-Error "CSharpRoot not found: $CSharpRoot"
    exit 1
}
if (-not (Test-Path $RustRoot)) {
    Write-Error "RustRoot not found: $RustRoot"
    exit 1
}

function Format-Number { param([int]$n) return $n.ToString('N0') }

function Format-Kloc {
    param([int]$n)
    return ('{0:N1} KLOC' -f ($n / 1000.0))
}

# Run cloc on a directory, excluding build artifacts, and return the
# aggregate row as a hashtable: @{ Files; Code; Comment; Blank }.
function Invoke-Cloc {
    param(
        [string]$Path,
        [string]$Language  # "C#" or "Rust"
    )
    if (-not (Test-Path $Path)) {
        return @{ Files = 0; Code = 0; Comment = 0; Blank = 0 }
    }

    $excludeDir = 'obj,bin,target,TestResults'
    $csv = & cloc $Path --csv --quiet --include-lang="$Language" --exclude-dir=$excludeDir 2>$null

    $result = @{ Files = 0; Code = 0; Comment = 0; Blank = 0 }
    foreach ($line in $csv) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -match '^files,') { continue }                 # header
        if ($line -match '^http://') { continue }                # url/banner
        if ($line -match 'github\.com/AlDanial/cloc') { continue }

        $parts = $line -split ','
        # cloc CSV summary row: files,language,blank,comment,code
        if ($parts.Count -lt 5) { continue }
        $files = $parts[0]
        $lang  = $parts[1]
        $blank = $parts[2]
        $comment = $parts[3]
        $code = $parts[4]

        # Only accept the language we asked for
        if ($lang -ne $Language) { continue }

        # files is an integer; if not, skip
        [int]$f = 0
        if (-not [int]::TryParse($files, [ref]$f)) { continue }

        $result.Files = $f
        $result.Blank = [int]$blank
        $result.Comment = [int]$comment
        $result.Code = [int]$code
    }
    return $result
}

# Scan every .rs file under $Directory for the first `#[cfg(test)]` line;
# everything from that line to EOF is considered test code. Returns the
# ratio of test-bucket "code" lines (non-blank, non-line-comment) to
# total such lines. Used to split cloc's accurate Rust code total into
# production vs test estimates.
function Get-RustTestSplitRatio {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        return @{ ProdFraction = 1.0; TestFraction = 0.0; ProdCode = 0; TestCode = 0 }
    }

    $prodCode = 0
    $testCode = 0
    $files = Get-ChildItem -Path $Path -Filter '*.rs' -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notlike '*\target\*' }

    foreach ($f in $files) {
        $lines = [IO.File]::ReadAllLines($f.FullName)
        $testStart = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^\s*#\[cfg\(test\)\]') {
                $testStart = $i
                break
            }
        }

        for ($i = 0; $i -lt $lines.Count; $i++) {
            $trim = $lines[$i].Trim()
            if ($trim -eq '') { continue }
            if ($trim.StartsWith('//')) { continue }
            # Rough "code line" - ignores block comments and strings, but good
            # enough to compute a test/prod ratio that we then apply to the
            # accurate cloc totals.
            if ($testStart -ge 0 -and $i -ge $testStart) {
                $testCode++
            }
            else {
                $prodCode++
            }
        }
    }

    $total = $prodCode + $testCode
    if ($total -eq 0) {
        return @{ ProdFraction = 1.0; TestFraction = 0.0; ProdCode = 0; TestCode = 0 }
    }
    return @{
        ProdFraction = [double]$prodCode / $total
        TestFraction = [double]$testCode / $total
        ProdCode = $prodCode
        TestCode = $testCode
    }
}

# Module pairings. Order matters -- tests section comes last.
$modules = @(
    @{ Name = 'Core';            CS = 'OspreySharp.Core';           Rust = 'crates\osprey-core' },
    @{ Name = 'IO';              CS = 'OspreySharp.IO';             Rust = 'crates\osprey-io' },
    @{ Name = 'Chromatography';  CS = 'OspreySharp.Chromatography'; Rust = 'crates\osprey-chromatography' },
    @{ Name = 'Scoring';         CS = 'OspreySharp.Scoring';        Rust = 'crates\osprey-scoring' },
    @{ Name = 'FDR';             CS = 'OspreySharp.FDR';            Rust = 'crates\osprey-fdr' },
    @{ Name = 'ML';              CS = 'OspreySharp.ML';             Rust = 'crates\osprey-ml' },
    @{ Name = 'Main (entry)';    CS = 'OspreySharp';                Rust = 'crates\osprey' }
)

Write-Host 'Counting OspreySharp (C#) and osprey (Rust) source lines...' -ForegroundColor Cyan
Write-Host "C# root:   $CSharpRoot" -ForegroundColor Gray
Write-Host "Rust root: $RustRoot" -ForegroundColor Gray
Write-Host ''

# Per-module results
$results = @()
foreach ($m in $modules) {
    # C# project folder (note: OspreySharp main is a nested folder, same name as module)
    $csPath = Join-Path $CSharpRoot $m.CS
    $rustPath = Join-Path $RustRoot $m.Rust

    $cs = Invoke-Cloc -Path $csPath -Language 'C#'
    $rust = Invoke-Cloc -Path $rustPath -Language 'Rust'

    # Split Rust code into production vs inline-test buckets using the
    # `#[cfg(test)]` scanner, then apply the ratio to cloc's accurate total.
    $split = Get-RustTestSplitRatio -Path $rustPath
    $rustProdCode = [int][math]::Round($rust.Code * $split.ProdFraction)
    $rustTestCode = $rust.Code - $rustProdCode

    $results += [pscustomobject]@{
        Module    = $m.Name
        CSFiles   = $cs.Files
        CSCode    = $cs.Code
        CSComment = $cs.Comment
        CSBlank   = $cs.Blank
        CSTotal   = $cs.Code + $cs.Comment + $cs.Blank
        RustFiles = $rust.Files
        RustCode  = $rust.Code
        RustProdCode = $rustProdCode
        RustTestCode = $rustTestCode
        RustComment = $rust.Comment
        RustBlank = $rust.Blank
        RustTotal = $rust.Code + $rust.Comment + $rust.Blank
    }
}

# Tests: OspreySharp.Test is a separate project; Rust tests are inline
# in each crate's src (cannot cleanly split).
$testCs = Invoke-Cloc -Path (Join-Path $CSharpRoot 'OspreySharp.Test') -Language 'C#'

# Ratio helper: returns a string like "0.76x" or "n/a" when Rust side is 0
function Get-Ratio {
    param([int]$CsCode, [int]$RustCode)
    if ($RustCode -eq 0) { return 'n/a' }
    $r = $CsCode / $RustCode
    return ('{0:N2}x' -f $r)
}

# Totals
$csTotalCode = ($results | Measure-Object -Property CSCode -Sum).Sum
$csTotalFiles = ($results | Measure-Object -Property CSFiles -Sum).Sum
$csTotalComment = ($results | Measure-Object -Property CSComment -Sum).Sum
$csTotalBlank = ($results | Measure-Object -Property CSBlank -Sum).Sum
$csTotalAll = $csTotalCode + $csTotalComment + $csTotalBlank

$rustTotalCode = ($results | Measure-Object -Property RustCode -Sum).Sum
$rustProdCodeTotal = ($results | Measure-Object -Property RustProdCode -Sum).Sum
$rustTestCodeTotal = ($results | Measure-Object -Property RustTestCode -Sum).Sum
$rustTotalFiles = ($results | Measure-Object -Property RustFiles -Sum).Sum
$rustTotalComment = ($results | Measure-Object -Property RustComment -Sum).Sum
$rustTotalBlank = ($results | Measure-Object -Property RustBlank -Sum).Sum
$rustTotalAll = $rustTotalCode + $rustTotalComment + $rustTotalBlank

# C# + Test combined (apples-to-apples with Rust's inline tests)
$csPlusTests = $csTotalCode + $testCs.Code

# Console table
$sepLine = ('=' * 108)
Write-Host $sepLine -ForegroundColor Cyan
Write-Host 'OSPREYSHARP vs OSPREY  -  lines of source code per matching module' -ForegroundColor Cyan
Write-Host $sepLine -ForegroundColor Cyan
Write-Host ''
$headerFmt = '{0,-16} {1,6} {2,10} {3,6} {4,10} {5,10} {6,10} {7,9} {8,9}'
Write-Host ($headerFmt -f 'Module', 'C# fl', 'C# code', 'Rs fl', 'Rs code', 'Rs prod', 'Rs test', 'C#/Rs', 'C#/RsPrd') -ForegroundColor Yellow
Write-Host ($headerFmt -f '------', '-----', '-------', '-----', '-------', '-------', '-------', '-----', '--------')
foreach ($r in $results) {
    Write-Host ($headerFmt -f `
        $r.Module,
        (Format-Number $r.CSFiles),
        (Format-Number $r.CSCode),
        (Format-Number $r.RustFiles),
        (Format-Number $r.RustCode),
        (Format-Number $r.RustProdCode),
        (Format-Number $r.RustTestCode),
        (Get-Ratio $r.CSCode $r.RustCode),
        (Get-Ratio $r.CSCode $r.RustProdCode))
}
Write-Host ($headerFmt -f '------', '-----', '-------', '-----', '-------', '-------', '-------', '-----', '--------')
Write-Host ($headerFmt -f `
    'TOTAL',
    (Format-Number $csTotalFiles),
    (Format-Number $csTotalCode),
    (Format-Number $rustTotalFiles),
    (Format-Number $rustTotalCode),
    (Format-Number $rustProdCodeTotal),
    (Format-Number $rustTestCodeTotal),
    (Get-Ratio $csTotalCode $rustTotalCode),
    (Get-Ratio $csTotalCode $rustProdCodeTotal)) -ForegroundColor Green
Write-Host ''
Write-Host ('OspreySharp code (production):     {0,8}  ({1})' -f (Format-Number $csTotalCode), (Format-Kloc $csTotalCode)) -ForegroundColor Green
Write-Host ('OspreySharp code + OspreySharp.Test: {0,6}  ({1})' -f (Format-Number $csPlusTests), (Format-Kloc $csPlusTests)) -ForegroundColor Green
Write-Host ('osprey code (total, mixed tests):  {0,8}  ({1})' -f (Format-Number $rustTotalCode), (Format-Kloc $rustTotalCode)) -ForegroundColor Green
Write-Host ('  est. production only:            {0,8}  ({1})' -f (Format-Number $rustProdCodeTotal), (Format-Kloc $rustProdCodeTotal))
Write-Host ('  est. inline tests:               {0,8}  ({1})' -f (Format-Number $rustTestCodeTotal), (Format-Kloc $rustTestCodeTotal))
Write-Host ''
Write-Host 'Apples-to-apples ratios:' -ForegroundColor Yellow
Write-Host ('  C# prod  / Rust prod (est):   {0}' -f (Get-Ratio $csTotalCode $rustProdCodeTotal))
Write-Host ('  C#+tests / Rust all:          {0}' -f (Get-Ratio $csPlusTests $rustTotalCode))
Write-Host ''
Write-Host 'Tests' -ForegroundColor Yellow
Write-Host ('  OspreySharp.Test (separate project): {0} files, {1} code lines ({2} total)' -f `
    (Format-Number $testCs.Files), (Format-Number $testCs.Code),
    (Format-Number ($testCs.Code + $testCs.Comment + $testCs.Blank)))
Write-Host ('  osprey inline #[cfg(test)] (est.):   {0} code lines' -f (Format-Number $rustTestCodeTotal))
Write-Host ''

# Build Markdown report
$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$sb = [System.Text.StringBuilder]::new()
$null = $sb.AppendLine('# OspreySharp vs Osprey (Rust) -- Lines of Code Audit')
$null = $sb.AppendLine()
$null = $sb.AppendLine("Generated: $timestamp")
$null = $sb.AppendLine()
$null = $sb.AppendLine("C# root:   ``$CSharpRoot``")
$null = $sb.AppendLine("Rust root: ``$RustRoot``")
$null = $sb.AppendLine()
$null = $sb.AppendLine('## Per-module comparison')
$null = $sb.AppendLine()
$null = $sb.AppendLine('Executable code only (C# / Rust). The Rust side is split into production')
$null = $sb.AppendLine('vs inline-test buckets by scanning each `.rs` file for its first')
$null = $sb.AppendLine('`#[cfg(test)]` line and treating everything from there to EOF as test.')
$null = $sb.AppendLine('`C#/Rust` compares against ALL Rust code (incl. inline tests);')
$null = $sb.AppendLine('`C#/RustProd` compares against the Rust production estimate only.')
$null = $sb.AppendLine()
$null = $sb.AppendLine('| Module | C# Files | C# Code | Rust Files | Rust Code | Rust Prod (est) | Rust Test (est) | C# / Rust | C# / RustProd |')
$null = $sb.AppendLine('|---|---:|---:|---:|---:|---:|---:|---:|---:|')
foreach ($r in $results) {
    $null = $sb.AppendLine(('| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} |' -f `
        $r.Module,
        (Format-Number $r.CSFiles),
        (Format-Number $r.CSCode),
        (Format-Number $r.RustFiles),
        (Format-Number $r.RustCode),
        (Format-Number $r.RustProdCode),
        (Format-Number $r.RustTestCode),
        (Get-Ratio $r.CSCode $r.RustCode),
        (Get-Ratio $r.CSCode $r.RustProdCode)))
}
$null = $sb.AppendLine(('| **TOTAL** | **{0}** | **{1}** | **{2}** | **{3}** | **{4}** | **{5}** | **{6}** | **{7}** |' -f `
    (Format-Number $csTotalFiles),
    (Format-Number $csTotalCode),
    (Format-Number $rustTotalFiles),
    (Format-Number $rustTotalCode),
    (Format-Number $rustProdCodeTotal),
    (Format-Number $rustTestCodeTotal),
    (Get-Ratio $csTotalCode $rustTotalCode),
    (Get-Ratio $csTotalCode $rustProdCodeTotal)))
$null = $sb.AppendLine()
$null = $sb.AppendLine('## Grand totals')
$null = $sb.AppendLine()
$null = $sb.AppendLine('| Scope | Files | Code | KLOC |')
$null = $sb.AppendLine('|---|---:|---:|---:|')
$null = $sb.AppendLine(('| OspreySharp production (7 library + main projects) | {0} | {1} | {2} |' -f `
    (Format-Number $csTotalFiles), (Format-Number $csTotalCode), (Format-Kloc $csTotalCode)))
$null = $sb.AppendLine(('| OspreySharp.Test (separate project) | {0} | {1} | {2} |' -f `
    (Format-Number $testCs.Files), (Format-Number $testCs.Code), (Format-Kloc $testCs.Code)))
$null = $sb.AppendLine(('| **OspreySharp production + tests** | **{0}** | **{1}** | **{2}** |' -f `
    (Format-Number ($csTotalFiles + $testCs.Files)),
    (Format-Number $csPlusTests),
    (Format-Kloc $csPlusTests)))
$null = $sb.AppendLine(('| osprey production (est) | | {0} | {1} |' -f `
    (Format-Number $rustProdCodeTotal), (Format-Kloc $rustProdCodeTotal)))
$null = $sb.AppendLine(('| osprey inline tests (est) | | {0} | {1} |' -f `
    (Format-Number $rustTestCodeTotal), (Format-Kloc $rustTestCodeTotal)))
$null = $sb.AppendLine(('| **osprey all code** | **{0}** | **{1}** | **{2}** |' -f `
    (Format-Number $rustTotalFiles), (Format-Number $rustTotalCode), (Format-Kloc $rustTotalCode)))
$null = $sb.AppendLine()
$null = $sb.AppendLine('### Apples-to-apples ratios')
$null = $sb.AppendLine()
$null = $sb.AppendLine('| Comparison | C# | Rust | Ratio (C# / Rust) |')
$null = $sb.AppendLine('|---|---:|---:|---:|')
$null = $sb.AppendLine(('| Production only | {0} | {1} | {2} |' -f `
    (Format-Kloc $csTotalCode), (Format-Kloc $rustProdCodeTotal), (Get-Ratio $csTotalCode $rustProdCodeTotal)))
$null = $sb.AppendLine(('| Production + tests | {0} | {1} | {2} |' -f `
    (Format-Kloc $csPlusTests), (Format-Kloc $rustTotalCode), (Get-Ratio $csPlusTests $rustTotalCode)))
$null = $sb.AppendLine()
$null = $sb.AppendLine('## Tests-by-module concentration (where is the test effort?)')
$null = $sb.AppendLine()
$null = $sb.AppendLine('Rust: estimated inline-test code per module. C#: tests live in a single')
$null = $sb.AppendLine('`OspreySharp.Test` project, so we show whether that project''s total aligns')
$null = $sb.AppendLine('with the Rust inline-test distribution.')
$null = $sb.AppendLine()
$null = $sb.AppendLine('| Module | Rust Test (est) | % of Rust tests |')
$null = $sb.AppendLine('|---|---:|---:|')
$sortedByTest = $results | Sort-Object -Property RustTestCode -Descending
foreach ($r in $sortedByTest) {
    $pct = if ($rustTestCodeTotal -gt 0) { [math]::Round(100.0 * $r.RustTestCode / $rustTestCodeTotal, 1) } else { 0 }
    $null = $sb.AppendLine(('| {0} | {1} | {2}% |' -f `
        $r.Module, (Format-Number $r.RustTestCode), $pct))
}
$null = $sb.AppendLine()
$null = $sb.AppendLine('## Notes')
$null = $sb.AppendLine()
$null = $sb.AppendLine('- Accurate code counts come from `cloc` (github.com/AlDanial/cloc), with')
$null = $sb.AppendLine('  `--include-lang` set to `C#` for OspreySharp and `Rust` for osprey.')
$null = $sb.AppendLine('  Build artifacts (`obj/`, `bin/`, `target/`) are excluded.')
$null = $sb.AppendLine('- Rust prod/test split is a HEURISTIC: per-file scan for the first')
$null = $sb.AppendLine('  `^\s*#[cfg(test)]` line; everything from that line to EOF is treated')
$null = $sb.AppendLine('  as test. Matches the standard Rust convention of `mod tests { ... }` at')
$null = $sb.AppendLine('  the bottom of the file but will be inaccurate if a crate mixes production')
$null = $sb.AppendLine('  and test code in non-trailing positions.')
$null = $sb.AppendLine('- `C# / Rust` ratios < 1.00 indicate C# is more compact per module.')
$null = $sb.AppendLine('- Regenerate with: `pwsh -File C:/proj/ai/scripts/OspreySharp/Audit-Loc.ps1`')

# Resolve output path
if (-not $OutputPath) {
    # Default: ai/.tmp beside this script
    $scriptRoot = Split-Path -Parent $PSCommandPath
    $aiRoot = Split-Path -Parent (Split-Path -Parent $scriptRoot)
    $tmpDir = Join-Path $aiRoot '.tmp'
    if (-not (Test-Path $tmpDir)) {
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
    }
    $dateStamp = Get-Date -Format 'yyyyMMdd-HHmm'
    $OutputPath = Join-Path $tmpDir "osprey-loc-audit-$dateStamp.md"
}

$sb.ToString() | Set-Content -Path $OutputPath -Encoding UTF8
Write-Host "Report saved: $OutputPath" -ForegroundColor Green
