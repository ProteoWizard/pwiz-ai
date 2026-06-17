<#
.SYNOPSIS
    Occasional cross-impl gate: run OspreySharp straight-through and compare its
    per-stage outputs against the FROZEN Rust reference set (no live Rust build).

.DESCRIPTION
    The day-to-day correctness gate is regression.ps1 (C#-only golden + resume,
    which has proven sufficient to catch internal drift). THIS is the broader,
    occasional double-check that OspreySharp still matches Rust osprey at every
    stage boundary -- run against a frozen reference produced once by
    Build-CrossImplReference.ps1 (see that set's README.md for provenance).

    Comparators (each at the parity level actually achieved during the port):
      scores.parquet (Stage 4) -> reference .scores.stage4.parquet   parquet 1e-9
      reconciliation.json                                            byte (SHA) equality
      1st/2nd-pass.fdr_scores.bin                                    bin_tol_diff value 1e-9
      stage7 protein-FDR dump                                        Compare-Stage7-Crossimpl 1e-9
      output.blib                                                    Compare-Blib-Crossimpl 1e-9 (osprey_version whitelisted)

    Stage-correct mapping: OspreySharp's scores.parquet is the STAGE-4 output
    (it does not overwrite at Stage 6; commit #4261), so it maps to the
    reference's .scores.stage4.parquet, NOT the reconciled .scores.parquet.

    calibration.json is intentionally NOT gated -- a Stage-3 bisection-debugging
    artifact whose values are bit-exact but whose file carries a run timestamp +
    Rust-only diagnostic keys (byte-equality never achievable or required).

.PARAMETER Dataset      Stellar (default) or Astral.
.PARAMETER TestBaseDir  Override dataset root.
.PARAMETER Framework    net8.0 (default, canonical) or net472.
.PARAMETER Threads      --threads (default 16).
.PARAMETER CsExe        Explicit OspreySharp.exe (else resolved for -Framework).
.PARAMETER SkipCs       Reuse an existing C# workdir.
#>
param(
    [ValidateSet('Stellar','Astral')]
    [string]$Dataset = 'Stellar',
    [string]$TestBaseDir,
    [ValidateSet('net472','net8.0')]
    [string]$Framework = 'net8.0',
    [int]$Threads = 16,
    [string]$CsExe,
    [switch]$SkipCs
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $PSCommandPath
foreach ($c in @((Join-Path $scriptDir 'Dataset-Config.ps1'),
                 (Join-Path $scriptDir '..\Dataset-Config.ps1'))) {
    if (Test-Path $c) { . $c; break }
}

$ospreyShExe = if ($CsExe) { $CsExe } else { Get-OspreySharpExe -Framework $Framework }
if (-not (Test-Path $ospreyShExe)) {
    Write-Host "OspreySharp.exe not found at $ospreyShExe -- build first." -ForegroundColor Red
    exit 2
}

$ds          = Get-DatasetConfig $Dataset -TestBaseDir $TestBaseDir
$mzmls       = @($ds.AllFiles)
$libraryName = $ds.Library
$resolution  = $ds.Resolution
$datasetRoot = $ds.TestDir
$stems       = @($mzmls | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_) })

$refRoot = Join-Path $datasetRoot ("_crossimpl_reference\" + $Dataset.ToLower())
$refDir  = Join-Path $refRoot 'rust'
if (-not (Test-Path (Join-Path $refDir 'output.blib'))) {
    Write-Host "No reference set at $refDir." -ForegroundColor Red
    Write-Host "Generate it first: Build-CrossImplReference.ps1 -Dataset $Dataset -Force" -ForegroundColor Red
    exit 2
}

$csDir  = Join-Path $refRoot 'cs'
$cmpDir = Join-Path $refRoot 'compare_logs'
New-Item -ItemType Directory -Path $cmpDir -Force | Out-Null

$parquetDiff = Join-Path $scriptDir 'parquet_diff.py'
$binDiff     = Join-Path $scriptDir 'bin_tol_diff.py'
$stage7Cmp   = Join-Path $scriptDir 'Compare-Stage7-Crossimpl.ps1'
$blibCmp     = Join-Path $scriptDir 'Compare-Blib-Crossimpl.ps1'

# ---- run OspreySharp straight-through ----
if ($SkipCs -and (Test-Path (Join-Path $csDir 'output.blib'))) {
    Write-Host "[C#] -SkipCs: reusing $csDir" -ForegroundColor DarkGray
} else {
    if (Test-Path $csDir) { Remove-Item $csDir -Recurse -Force }
    New-Item -ItemType Directory -Path $csDir -Force | Out-Null
    foreach ($f in $mzmls) { Copy-Item (Join-Path $datasetRoot $f) (Join-Path $csDir $f) }
    Copy-Item (Join-Path $datasetRoot $libraryName) (Join-Path $csDir $libraryName)
    $cache = Join-Path $datasetRoot ($libraryName + '.libcache')
    if (Test-Path $cache) { Copy-Item $cache (Join-Path $csDir ($libraryName + '.libcache')) }

    $cliArgs = @()
    foreach ($f in $mzmls) { $cliArgs += @('-i', $f) }
    $cliArgs += @('-l', $libraryName, '-o', 'output.blib', '--resolution', $resolution,
                  '--protein-fdr', '0.01', '--threads', $Threads.ToString())
    Write-Host "[C#] OspreySharp straight-through ($Framework) ..." -ForegroundColor Cyan
    Push-Location $csDir
    try {
        $env:OSPREY_DUMP_STAGE7_PROTEIN_FDR = '1'
        # Serialize per-file scoring. With diagnostics on (needed for the Stage 7
        # dump), the parallel per-file tasks otherwise collide writing the shared
        # cs_cal_summary.txt (OspreyFileDiagnostics writes a hardcoded filename,
        # not per-stem). Output is per-file, so serializing does not change it.
        $env:OSPREY_MAX_PARALLEL_FILES = '1'
        & $ospreyShExe @cliArgs 2>&1 | Tee-Object -FilePath (Join-Path $csDir 'ospreysharp.log') | Out-Null
        $code = $LASTEXITCODE
    } finally {
        Remove-Item Env:OSPREY_DUMP_STAGE7_PROTEIN_FDR -ErrorAction SilentlyContinue
        Remove-Item Env:OSPREY_MAX_PARALLEL_FILES -ErrorAction SilentlyContinue
        Pop-Location
    }
    if ($code -ne 0) { Write-Host "OspreySharp exited $code" -ForegroundColor Red; exit 1 }
}

# ---- compare ----
$results = New-Object System.Collections.Generic.List[object]
function Record {
    param([string]$Stage, [string]$Boundary, [bool]$Pass, [string]$Detail)
    $script:results.Add([pscustomobject]@{ Stage=$Stage; Boundary=$Boundary; Pass=$Pass; Detail=$Detail }) | Out-Null
    $m = if ($Pass) { 'PASS' } else { 'FAIL' }
    Write-Host ("  [{0}] {1,-34} {2}  {3}" -f $m, $Boundary, $Stage, $Detail) -ForegroundColor $(if ($Pass) {'Green'} else {'Red'})
}
function Sha { param($p) if (Test-Path $p) { (Get-FileHash $p -Algorithm SHA256).Hash } else { $null } }
function Tool {
    param([string]$Stage, [string]$Boundary, [string]$Ref, [string]$Cs, [string]$Py, [string]$Log)
    if (-not ((Test-Path $Ref) -and (Test-Path $Cs))) { Record $Stage $Boundary $false 'missing on one side'; return }
    python $Py $Ref $Cs --tolerance 1e-9 *>&1 | Tee-Object -FilePath (Join-Path $cmpDir $Log) | Out-Null
    Record $Stage $Boundary ($LASTEXITCODE -eq 0) ("see {0}" -f $Log)
}

Write-Host ""
Write-Host "=== Cross-impl gate vs frozen Rust reference ($Dataset) ===" -ForegroundColor Cyan

foreach ($stem in $stems) {
    # Stage 4: OspreySharp scores.parquet (Stage-4) vs reference .scores.stage4.parquet
    Tool 'stage4' ("scores.parquet[{0}]" -f $stem) `
        (Join-Path $refDir ($stem + '.scores.stage4.parquet')) `
        (Join-Path $csDir  ($stem + '.scores.parquet')) `
        $parquetDiff ("stage4_parquet_{0}.log" -f $stem)

    # Stage 5: reconciliation.json (byte equality -- achieved bit-identical)
    $rj = Join-Path $refDir ($stem + '.reconciliation.json'); $cj = Join-Path $csDir ($stem + '.reconciliation.json')
    if ((Test-Path $rj) -and (Test-Path $cj)) {
        Record 'stage5' ("reconciliation.json[{0}]" -f $stem) ((Sha $rj) -eq (Sha $cj)) 'sha equality'
    } else { Record 'stage5' ("reconciliation.json[{0}]" -f $stem) $false 'missing on one side' }

    # Stage 5/6b: fdr_scores.bin sidecars (value-level)
    Tool 'stage5'  ("1st-pass.fdr_scores.bin[{0}]" -f $stem) `
        (Join-Path $refDir ($stem + '.1st-pass.fdr_scores.bin')) `
        (Join-Path $csDir  ($stem + '.1st-pass.fdr_scores.bin')) $binDiff ("stage5_1stbin_{0}.log" -f $stem)
    Tool 'stage6b' ("2nd-pass.fdr_scores.bin[{0}]" -f $stem) `
        (Join-Path $refDir ($stem + '.2nd-pass.fdr_scores.bin')) `
        (Join-Path $csDir  ($stem + '.2nd-pass.fdr_scores.bin')) $binDiff ("stage6b_2ndbin_{0}.log" -f $stem)
}

# Stage 7 protein-FDR dump (per-column 1e-9)
$s7log = Join-Path $cmpDir 'stage7_compare.log'
& pwsh -File $stage7Cmp -RustTsv (Join-Path $refDir 'rust_stage7_protein_fdr.tsv') `
    -CsTsv (Join-Path $csDir 'cs_stage7_protein_fdr.tsv') *>&1 | Tee-Object -FilePath $s7log | Out-Null
Record 'stage7' 'stage7_protein_fdr.tsv' ($LASTEXITCODE -eq 0) 'see stage7_compare.log'

# Blib (SQL row+col 1e-9; osprey_version whitelisted in the comparator)
$blog = Join-Path $cmpDir 'blib_compare.log'
& pwsh -File $blibCmp -RustBlib (Join-Path $refDir 'output.blib') `
    -CsBlib (Join-Path $csDir 'output.blib') *>&1 | Tee-Object -FilePath $blog | Out-Null
Record 'blib' 'output.blib' ($LASTEXITCODE -eq 0) 'see blib_compare.log'

Write-Host ""
$nFail = ($results | Where-Object { -not $_.Pass }).Count
if ($nFail -eq 0) {
    Write-Host "OVERALL: PASS -- OspreySharp matches the frozen Rust reference at every gated boundary." -ForegroundColor Green
    exit 0
} else {
    Write-Host ("OVERALL: FAIL -- {0} boundary/boundaries diverged." -f $nFail) -ForegroundColor Red
    exit 1
}
