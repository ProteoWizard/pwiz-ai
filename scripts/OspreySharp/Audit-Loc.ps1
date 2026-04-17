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
        OspreySharp.Test          <-> (inline #[cfg(test)] - see note)

    Report shows files, code, comments, blank, total per side plus a
    ratio column (C# LOC / Rust LOC, where < 1.0 means C# is more
    compact). Rust inline tests are not separable from production code
    without parsing the #[cfg(test)] attribute, so the Rust columns
    mix both; this caveat is noted in the output.

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

    $results += [pscustomobject]@{
        Module    = $m.Name
        CSFiles   = $cs.Files
        CSCode    = $cs.Code
        CSComment = $cs.Comment
        CSBlank   = $cs.Blank
        CSTotal   = $cs.Code + $cs.Comment + $cs.Blank
        RustFiles = $rust.Files
        RustCode  = $rust.Code
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
$rustTotalFiles = ($results | Measure-Object -Property RustFiles -Sum).Sum
$rustTotalComment = ($results | Measure-Object -Property RustComment -Sum).Sum
$rustTotalBlank = ($results | Measure-Object -Property RustBlank -Sum).Sum
$rustTotalAll = $rustTotalCode + $rustTotalComment + $rustTotalBlank

# Console table
$sepLine = ('=' * 96)
Write-Host $sepLine -ForegroundColor Cyan
Write-Host 'OSPREYSHARP vs OSPREY  -  lines of source code per matching module' -ForegroundColor Cyan
Write-Host $sepLine -ForegroundColor Cyan
Write-Host ''
$headerFmt = '{0,-18} {1,6} {2,10} {3,10} {4,6} {5,10} {6,10} {7,8}'
Write-Host ($headerFmt -f 'Module', 'C# fl', 'C# code', 'C# total', 'Rs fl', 'Rs code', 'Rs total', 'C#/Rs') -ForegroundColor Yellow
Write-Host ($headerFmt -f '------', '-----', '-------', '--------', '-----', '-------', '--------', '------')
foreach ($r in $results) {
    Write-Host ($headerFmt -f `
        $r.Module,
        (Format-Number $r.CSFiles),
        (Format-Number $r.CSCode),
        (Format-Number $r.CSTotal),
        (Format-Number $r.RustFiles),
        (Format-Number $r.RustCode),
        (Format-Number $r.RustTotal),
        (Get-Ratio $r.CSCode $r.RustCode))
}
Write-Host ($headerFmt -f '------', '-----', '-------', '--------', '-----', '-------', '--------', '------')
Write-Host ($headerFmt -f `
    'TOTAL (production)',
    (Format-Number $csTotalFiles),
    (Format-Number $csTotalCode),
    (Format-Number $csTotalAll),
    (Format-Number $rustTotalFiles),
    (Format-Number $rustTotalCode),
    (Format-Number $rustTotalAll),
    (Get-Ratio $csTotalCode $rustTotalCode)) -ForegroundColor Green
Write-Host ''
Write-Host ('OspreySharp production code: {0} ({1})' -f (Format-Number $csTotalCode), (Format-Kloc $csTotalCode)) -ForegroundColor Green
Write-Host ('osprey     production code: {0} ({1})' -f (Format-Number $rustTotalCode), (Format-Kloc $rustTotalCode)) -ForegroundColor Green
Write-Host ''
Write-Host 'Tests' -ForegroundColor Yellow
Write-Host ('  OspreySharp.Test: {0} files, {1} code lines ({2} total incl. comments+blanks)' -f `
    (Format-Number $testCs.Files), (Format-Number $testCs.Code),
    (Format-Number ($testCs.Code + $testCs.Comment + $testCs.Blank)))
Write-Host '  osprey (Rust):    inline #[cfg(test)] in each crate -- counted in Rust totals above'
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
$null = $sb.AppendLine('Executable code only (C# / Rust). `Total` includes comments and blank lines.')
$null = $sb.AppendLine('Ratio is `C# code / Rust code`; values under 1.00 mean C# is more compact.')
$null = $sb.AppendLine()
$null = $sb.AppendLine('| Module | C# Files | C# Code | C# Total | Rust Files | Rust Code | Rust Total | C# / Rust |')
$null = $sb.AppendLine('|---|---:|---:|---:|---:|---:|---:|---:|')
foreach ($r in $results) {
    $null = $sb.AppendLine(('| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} |' -f `
        $r.Module,
        (Format-Number $r.CSFiles),
        (Format-Number $r.CSCode),
        (Format-Number $r.CSTotal),
        (Format-Number $r.RustFiles),
        (Format-Number $r.RustCode),
        (Format-Number $r.RustTotal),
        (Get-Ratio $r.CSCode $r.RustCode)))
}
$null = $sb.AppendLine(('| **Production total** | **{0}** | **{1}** | **{2}** | **{3}** | **{4}** | **{5}** | **{6}** |' -f `
    (Format-Number $csTotalFiles),
    (Format-Number $csTotalCode),
    (Format-Number $csTotalAll),
    (Format-Number $rustTotalFiles),
    (Format-Number $rustTotalCode),
    (Format-Number $rustTotalAll),
    (Get-Ratio $csTotalCode $rustTotalCode)))
$null = $sb.AppendLine()
$null = $sb.AppendLine('### Summary')
$null = $sb.AppendLine()
$null = $sb.AppendLine('| Side | Files | Code | Comments | Blank | Total | KLOC (code) |')
$null = $sb.AppendLine('|---|---:|---:|---:|---:|---:|---:|')
$null = $sb.AppendLine(('| OspreySharp (C# production) | {0} | {1} | {2} | {3} | {4} | {5} |' -f `
    (Format-Number $csTotalFiles), (Format-Number $csTotalCode), (Format-Number $csTotalComment),
    (Format-Number $csTotalBlank), (Format-Number $csTotalAll), (Format-Kloc $csTotalCode)))
$null = $sb.AppendLine(('| osprey (Rust)              | {0} | {1} | {2} | {3} | {4} | {5} |' -f `
    (Format-Number $rustTotalFiles), (Format-Number $rustTotalCode), (Format-Number $rustTotalComment),
    (Format-Number $rustTotalBlank), (Format-Number $rustTotalAll), (Format-Kloc $rustTotalCode)))
$null = $sb.AppendLine()
$null = $sb.AppendLine('## Tests')
$null = $sb.AppendLine()
$null = $sb.AppendLine('OspreySharp isolates tests in their own project; Rust osprey uses inline ' +
    '`#[cfg(test)]` modules inside each crate (cloc cannot separate them without parsing attributes).')
$null = $sb.AppendLine()
$null = $sb.AppendLine('| Side | Files | Code | Comments | Blank | Total |')
$null = $sb.AppendLine('|---|---:|---:|---:|---:|---:|')
$null = $sb.AppendLine(('| OspreySharp.Test (C#) | {0} | {1} | {2} | {3} | {4} |' -f `
    (Format-Number $testCs.Files), (Format-Number $testCs.Code), (Format-Number $testCs.Comment),
    (Format-Number $testCs.Blank), (Format-Number ($testCs.Code + $testCs.Comment + $testCs.Blank))))
$null = $sb.AppendLine('| osprey (Rust inline tests) | (counted above) | (counted above) | | | |')
$null = $sb.AppendLine()
$null = $sb.AppendLine('## Notes')
$null = $sb.AppendLine()
$null = $sb.AppendLine('- Counts come from `cloc` (github.com/AlDanial/cloc), with `--include-lang` ' +
    'set to `C#` on the OspreySharp side and `Rust` on the osprey side. Build artifacts ' +
    '(`obj/`, `bin/`, `target/`) are excluded.')
$null = $sb.AppendLine('- "Production" totals exclude OspreySharp.Test; Rust inline tests are ' +
    'inseparable from their production crates without AST parsing, so they are included in the ' +
    'Rust Code column.')
$null = $sb.AppendLine('- Ratios below 1.00x indicate C# fewer lines than Rust; above 1.00x ' +
    'indicates the opposite. The gross ratio is driven mostly by the main-entry module, which ' +
    'has quite different shape on each side (CLI parsing + orchestration in Rust vs. Program.cs ' +
    '+ AnalysisPipeline.cs in C#).')
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
