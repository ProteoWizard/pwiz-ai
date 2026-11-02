# Stage 5 profile post-processor.
# Reads a C# .dtp + Rust samply .json, extracts per-function CSV,
# emits a 3-column markdown table sorted by C# OWN time descending.

[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$CsharpDtp,
    [Parameter(Mandatory)] [string]$RustJson,
    [Parameter(Mandatory)] [string]$OutDir,
    [string]$RustBinary = '/mnt/c/proj/osprey/target/release/osprey',
    [int]$TopN = 30
)

$ErrorActionPreference = 'Stop'
$ScriptRoot = Split-Path -Parent $PSCommandPath

if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }

# ---- C#: dtp -> XML via Windows Reporter.exe, then parse ----
$reporterExe = 'C:\Users\brendanx\AppData\Local\JetBrains\Installations\dotTrace261\Reporter.exe'
if (-not (Test-Path $reporterExe)) { throw "Reporter.exe not found at $reporterExe" }

$patternFile = Join-Path $OutDir 'csharp-pattern.xml'
@'
<Patterns>
  <Pattern PrintCallstacks="Full">pwiz\.Osprey\..*</Pattern>
  <Pattern PrintCallstacks="Full">System\..*</Pattern>
</Patterns>
'@ | Out-File -FilePath $patternFile -Encoding UTF8

$csharpXml = Join-Path $OutDir 'csharp-stage5-report.xml'
Write-Host "Running Reporter on $CsharpDtp ..." -ForegroundColor Cyan
& $reporterExe report $CsharpDtp --pattern=$patternFile --save-to=$csharpXml --overwrite 2>&1 | Out-Null
if (-not (Test-Path $csharpXml)) { throw "Reporter did not produce $csharpXml" }

$csharpXmlDoc = [xml](Get-Content -Raw -Path $csharpXml)
$csharpRows = @($csharpXmlDoc.Report.Function |
    Where-Object { $_.FQN -like 'pwiz.Osprey*' } |
    ForEach-Object {
        [pscustomobject]@{
            Function = $_.FQN
            OwnMs    = [double]$_.OwnTime
            TotalMs  = [double]$_.TotalTime
        }
    } |
    Sort-Object OwnMs -Descending)

$csharpCsv = Join-Path $OutDir 'csharp-stage5.csv'
$csharpRows | Select-Object Function, @{N='own_ms';E={$_.OwnMs}}, @{N='total_ms';E={$_.TotalMs}} |
    Export-Csv -Path $csharpCsv -NoTypeInformation -Encoding UTF8
Write-Host "C#: $($csharpRows.Count) functions, top=$($csharpRows[0].Function) own=$($csharpRows[0].OwnMs)ms" -ForegroundColor Gray

# ---- Rust: samply JSON -> CSV via python (with addr2line resolution) ----
$rustCsv = Join-Path $OutDir 'rust-stage5.csv'
$py = Join-Path $ScriptRoot 'samply-to-csv.py'
Write-Host "Parsing samply JSON $RustJson via python (addr2line on $RustBinary) ..." -ForegroundColor Cyan
# Run via WSL because addr2line + binary are Linux-side
$wslPyArgs = @(
    'python3',
    ($py -replace '^C:', '/mnt/c' -replace '\\', '/'),
    ($RustJson -replace '^C:', '/mnt/c' -replace '\\', '/'),
    ($rustCsv -replace '^C:', '/mnt/c' -replace '\\', '/'),
    '--binary', $RustBinary
)
& wsl.exe -- @wslPyArgs
if (-not (Test-Path $rustCsv)) { throw "samply-to-csv did not produce $rustCsv" }

$rustRows = @(Import-Csv -Path $rustCsv | ForEach-Object {
    [pscustomobject]@{
        Function = $_.function
        OwnMs    = [double]$_.own_ms
        TotalMs  = [double]$_.total_ms
    }
} | Sort-Object OwnMs -Descending)

Write-Host "Rust: $($rustRows.Count) functions, top=$($rustRows[0].Function) own=$($rustRows[0].OwnMs)ms" -ForegroundColor Gray

# ---- Hand-curated name pairs (Rust function name lookup keyed by C# leaf word) ----
# Each entry: short tag -> [C# substring match, Rust substring match].
# Top entries cover the obvious SVM / Percolator pairs; the rest are
# best-effort by leaf-name normalization (see Normalize-Name below).
$pairs = @(
    @{ csMatch='LinearSvmClassifier.Train';            rustMatch='svm::LinearSvm::fit' },
    @{ csMatch='LinearSvmClassifier.FisherYatesShuffle'; rustMatch='shuffle' },
    @{ csMatch='Matrix.DotVector';                     rustMatch='dot' },
    @{ csMatch='PercolatorFdr.CompeteFromIndicesInto'; rustMatch='compete_from_indices' },
    @{ csMatch='PercolatorFdr+<>c__DisplayClass16_0.<GridSearchC>b__0'; rustMatch='svm::LinearSvm::fit' },
    @{ csMatch='DecoyGenerator.RecalculateFragments';  rustMatch='DecoyGenerator::recalc' },
    @{ csMatch='DecoyGenerator.CalculateFragmentMz';   rustMatch='DecoyGenerator::calculate_fragment_mz' },
    @{ csMatch='PepEstimator+Kde.Pdf';                 rustMatch='pep::PepEstimator::pdf' },
    @{ csMatch='PepEstimator';                         rustMatch='pep::PepEstimator::fit' },
    @{ csMatch='PercolatorFdr.RunPercolator';          rustMatch='run_percolator' }
)

function Match-RustRow($csFunction, $rustRows, $pairs) {
    foreach ($p in $pairs) {
        if ($csFunction -like "*$($p.csMatch)*") {
            $r = $rustRows | Where-Object { $_.Function -like "*$($p.rustMatch)*" } | Select-Object -First 1
            if ($r) { return $r }
        }
    }
    # Fallback: normalize last word and try
    $last = ($csFunction -split '\.')[-1]
    $last = $last -replace '<.*?>', '' -replace '[+_].*$', ''
    $norm = ($last -replace '[^A-Za-z0-9]', '').ToLowerInvariant()
    foreach ($r in $rustRows) {
        $rlast = ($r.Function -split '::')[-1]
        $rnorm = ($rlast -replace '[^A-Za-z0-9]', '').ToLowerInvariant()
        if ($rnorm -eq $norm) { return $r }
    }
    return $null
}

# ---- Build the 3-col table ----
$top = $csharpRows | Select-Object -First $TopN
$mdLines = @()
$mdLines += '| # | C# function | C# own (ms) | Rust own (ms) | Rust function |'
$mdLines += '|---:|---|---:|---:|---|'
$i = 0
$matched = 0
foreach ($cs in $top) {
    $i++
    $shortCs = $cs.Function -replace '^pwiz\.Osprey\.', ''
    if ($shortCs.Length -gt 80) { $shortCs = $shortCs.Substring(0, 77) + '...' }
    $rust = Match-RustRow -csFunction $cs.Function -rustRows $rustRows -pairs $pairs
    if ($rust) {
        $matched++
        $rustOwn = '{0:N0}' -f $rust.OwnMs
        $rustFn = $rust.Function
        if ($rustFn.Length -gt 60) { $rustFn = $rustFn.Substring(0, 57) + '...' }
    } else {
        $rustOwn = '—'
        $rustFn = ''
    }
    $mdLines += ('| {0} | `{1}` | {2:N0} | {3} | `{4}` |' -f `
        $i, $shortCs, $cs.OwnMs, $rustOwn, $rustFn)
}

$mdPath = Join-Path $OutDir 'stage5-csharp-vs-rust.md'
$mdLines | Out-File -FilePath $mdPath -Encoding UTF8
Write-Host ""
Write-Host "Matched $matched of $($top.Count) C# rows to Rust counterparts." -ForegroundColor Yellow
Write-Host "Wrote $mdPath" -ForegroundColor Green
Write-Host ""
$mdLines | ForEach-Object { Write-Host $_ }
