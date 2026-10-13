<#
.SYNOPSIS
    Lines-of-code audit: CarafeSharp (C#) vs Carafe (Java + Python reference).

.DESCRIPTION
    The CarafeSharp counterpart of ai/scripts/Osprey/Audit-Loc.ps1. Counts code, comment and
    blank lines with cloc for each CarafeSharp project (production vs CarafeSharp.Test), the
    non-C# files in the folder (scripts, docs, resources), and the Carafe reference at a tag:
    its Java (production, GUI and tests apart) and its Python.

    With -CoverageJson (a dotCover JSON report, e.g. from Measure-CumulativeCoverage.ps1), it
    adds dotCover's statement count beside cloc's code lines for each assembly, which is how a
    line count is reconciled with a coverage report's statement count.

    Prints the tables and saves a Markdown report under ai/.tmp/.

.PARAMETER SourceRoot
    The pwiz checkout (default <projRoot>\pwiz).

.PARAMETER CarafeRoot
    The Carafe git checkout (default <projRoot>\Carafe-mm, the maccoss fork CarafeSharp ports).

.PARAMETER CarafeTag
    The Carafe tag to count (default v2.2.0, the version CarafeSharp ports). Extracted with
    git archive (zip), so the checkout's own branch does not matter.

.PARAMETER CoverageJson
    Optional dotCover JSON report for the statement-count column.

.PARAMETER OutputPath
    Default <projRoot>\ai\.tmp\carafesharp-loc-audit-YYYYMMDD-HHMM.md.

.EXAMPLE
    pwsh -File ./ai/scripts/CarafeSharp/Audit-Loc.ps1 -SourceRoot C:/proj/pwiz-work1

.NOTES
    Requires cloc: winget install AlDanial.Cloc
#>
[CmdletBinding()]
param(
    [string]$SourceRoot,
    [string]$CarafeRoot,
    [string]$CarafeTag = 'v2.2.0',
    [string]$CoverageJson,
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$aiRoot   = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$projRoot = Split-Path -Parent $aiRoot
if (-not $SourceRoot) { $SourceRoot = Join-Path $projRoot 'pwiz' }
if (-not $CarafeRoot) { $CarafeRoot = Join-Path $projRoot 'Carafe-mm' }
$carafeSharp = Join-Path $SourceRoot 'pwiz_tools\CarafeSharp'
if (-not (Get-Command cloc -ErrorAction SilentlyContinue)) { throw 'cloc is not installed. Install with: winget install AlDanial.Cloc' }
if (-not (Test-Path $carafeSharp)) { throw "CarafeSharp not found: $carafeSharp" }
if (-not $OutputPath) { $OutputPath = Join-Path $aiRoot ('.tmp\carafesharp-loc-audit-{0}.md' -f (Get-Date -Format 'yyyyMMdd-HHmm')) }

$excludeDirs = 'bin,obj,bin-cuda,obj-cuda,TestResults'

# cloc CSV rows (files,language,blank,comment,code) for a path, optionally limited to languages.
function Get-Cloc([string]$path, [string]$langs, [string]$extraArgs) {
    $args = @('--quiet', '--csv', "--exclude-dir=$excludeDirs")
    if ($langs) { $args += "--include-lang=$langs" }
    if ($extraArgs) { $args += $extraArgs }
    $rows = & cloc @args $path | Where-Object { $_ -match '^\d+,' -and $_ -notmatch ',SUM,' }
    foreach ($row in $rows) {
        $f = $row -split ','
        [pscustomobject]@{ Language = $f[1]; Files = [int]$f[0]; Blank = [int]$f[2]; Comment = [int]$f[3]; Code = [int]$f[4] }
    }
}
function Sum($rows, $prop) { ($rows | Measure-Object -Property $prop -Sum).Sum }
function N($n) { if ($null -eq $n) { '' } else { ([long]$n).ToString('N0') } }
function Pct($a, $b) { if (-not $b) { 'n/a' } else { '{0:N0}%' -f (100.0 * $a / $b) } }

$md = [System.Collections.Generic.List[string]]::new()
$md.Add('# CarafeSharp vs Carafe -- Lines of Code Audit'); $md.Add('')
$md.Add("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"); $md.Add('')
$md.Add("CarafeSharp: ``$carafeSharp`` ($(git -C $SourceRoot rev-parse --short HEAD))")
$md.Add("Carafe: ``$CarafeRoot`` at ``$CarafeTag``"); $md.Add('')

# ---- CarafeSharp by project ----
$statements = @{}
if ($CoverageJson) {
    $report = Get-Content -Raw $CoverageJson | ConvertFrom-Json
    foreach ($a in $report.Children) { $statements[$a.Name] = [pscustomobject]@{ Total = [int]$a.TotalStatements; Covered = [int]$a.CoveredStatements } }
}
$projects = Get-ChildItem $carafeSharp -Directory | Where-Object { Get-ChildItem $_.FullName -Filter *.csproj -File } | Sort-Object Name
$rows = foreach ($p in $projects) {
    $c = Get-Cloc $p.FullName 'C#'
    $st = $statements[$p.Name]
    [pscustomobject]@{
        Project = $p.Name; Test = ($p.Name -like '*.Test'); Files = Sum $c Files; Code = Sum $c Code; Comment = Sum $c Comment; Blank = Sum $c Blank
        Statements = $st.Total; Covered = $st.Covered
    }
}
$md.Add('## CarafeSharp C# by project'); $md.Add('')
$md.Add('| Project | Files | Code | Comment | Blank | Comment/Code | dotCover statements | Statements/Code | Covered |')
$md.Add('|---|---:|---:|---:|---:|---:|---:|---:|---:|')
foreach ($r in $rows) {
    $md.Add(('| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} |' -f $r.Project, $r.Files, (N $r.Code), (N $r.Comment), (N $r.Blank),
        (Pct $r.Comment $r.Code), (N $r.Statements), $(if ($r.Statements) { '{0:N2}' -f ($r.Statements / $r.Code) } else { '' }),
        $(if ($r.Statements) { Pct $r.Covered $r.Statements } else { '' })))
}
$prod = @($rows | Where-Object { -not $_.Test }); $test = @($rows | Where-Object Test)
foreach ($g in @(@('**Production**', $prod), @('**Tests**', $test), @('**All C#**', $rows))) {
    # dotCover leaves the test assembly out, so statement columns apply to production rows only.
    $set = $g[1]; $code = Sum $set Code; $st = if (@($set | Where-Object Test).Count) { $null } else { Sum $set Statements }; $cov = Sum $set Covered
    $md.Add(('| {0} | {1} | **{2}** | {3} | {4} | {5} | {6} | {7} | {8} |' -f $g[0], (Sum $set Files), (N $code), (N (Sum $set Comment)), (N (Sum $set Blank)),
        (Pct (Sum $set Comment) $code), (N $st), $(if ($st) { '{0:N2}' -f ($st / $code) } else { '' }), $(if ($st) { Pct $cov $st } else { '' })))
}
$md.Add('')

# ---- Non-C# files in the CarafeSharp folder ----
$other = Get-Cloc $carafeSharp '' '--exclude-lang=C#'
$md.Add('## CarafeSharp non-C# (scripts, docs, data, project files)'); $md.Add('')
$md.Add('| Language | Files | Code | Comment | Blank |'); $md.Add('|---|---:|---:|---:|---:|')
foreach ($o in $other | Sort-Object Code -Descending) { $md.Add(('| {0} | {1} | {2} | {3} | {4} |' -f $o.Language, $o.Files, (N $o.Code), (N $o.Comment), (N $o.Blank))) }
$md.Add('')

# ---- Carafe reference ----
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("carafe-$CarafeTag-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory $tmp | Out-Null
try {
    $zip = Join-Path $tmp 'src.zip'
    git -C $CarafeRoot archive --format=zip -o $zip $CarafeTag
    if ($LASTEXITCODE -ne 0) { throw "git archive $CarafeTag failed in $CarafeRoot" }
    Expand-Archive -LiteralPath $zip -DestinationPath $tmp
    $javaMain = Join-Path $tmp 'src\main\java'
    $gui = Get-Cloc (Join-Path $javaMain 'gui') 'Java'
    $javaAll = Get-Cloc $javaMain 'Java'
    $javaTest = Get-Cloc (Join-Path $tmp 'src\test') 'Java'
    $python = Get-Cloc (Join-Path $tmp 'src') 'Python'
    $ref = @(
        [pscustomobject]@{ Part = 'Java production, without the GUI'; Code = (Sum $javaAll Code) - (Sum $gui Code); Comment = (Sum $javaAll Comment) - (Sum $gui Comment) }
        [pscustomobject]@{ Part = 'Java GUI (src/main/java/gui, not ported)'; Code = Sum $gui Code; Comment = Sum $gui Comment }
        [pscustomobject]@{ Part = 'Python (model training and prediction)'; Code = Sum $python Code; Comment = Sum $python Comment }
        [pscustomobject]@{ Part = 'Java tests'; Code = Sum $javaTest Code; Comment = Sum $javaTest Comment }
    )
} finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
$refProd = ($ref[0].Code + $ref[2].Code)
$md.Add("## Carafe $CarafeTag reference"); $md.Add('')
$md.Add('| Part | Code | Comment |'); $md.Add('|---|---:|---:|')
foreach ($r in $ref) { $md.Add(('| {0} | {1} | {2} |' -f $r.Part, (N $r.Code), (N $r.Comment))) }
$md.Add('')
$md.Add('Carafe''s Python calls AlphaPeptDeep and alphabase, and CarafeSharp also ports Chronologer, so the')
$md.Add('model code CarafeSharp re-implements lives outside Carafe and is not in these counts. Carafe reads raw')
$md.Add('data itself; CarafeSharp takes it from Osprey''s training export.'); $md.Add('')

$prodCode = Sum $prod Code; $testCode = Sum $test Code
$md.Add('## Ratios'); $md.Add('')
$md.Add('| Comparison | CarafeSharp | Carafe | Ratio |'); $md.Add('|---|---:|---:|---:|')
$md.Add(('| Production (Carafe: Java without GUI + Python) | {0} | {1} | {2:N2}x |' -f (N $prodCode), (N $refProd), ($prodCode / $refProd)))
$md.Add(('| Tests | {0} | {1} | {2:N1}x |' -f (N $testCode), (N $ref[3].Code), ($testCode / [math]::Max(1, $ref[3].Code))))
$md.Add(('| Test code per production line | {0:N2} | {1:N2} | |' -f ($testCode / $prodCode), ($ref[3].Code / $refProd)))
$md.Add('')

New-Item -ItemType Directory -Force (Split-Path -Parent $OutputPath) | Out-Null
$md | Set-Content -Path $OutputPath -Encoding utf8
$md | ForEach-Object { Write-Host $_ }
Write-Host ''
Write-Host "Report: $OutputPath" -ForegroundColor Green
