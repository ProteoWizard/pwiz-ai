<#
.SYNOPSIS
    Cross-implementation .blib SQLite output comparison.

.DESCRIPTION
    Per-table SQL projection + stable-key join + numeric-tolerance
    column compare on the BiblioSpecLite output of Rust osprey vs C#
    Osprey. Mirrors the methodology of Compare-Percolator.ps1
    (Stage 5) and Compare-Stage7-Crossimpl.ps1 (Stage 7 protein FDR):
    numeric columns at 1e-9 absolute, string/integer columns at
    exact equality, row-set diff per table.

    Stable keys per table (RefSpectra.id is autoincrement and cannot
    be assumed equal cross-impl, so secondary tables JOIN through
    RefSpectra to (peptideModSeq, precursorCharge) and through
    SpectrumSourceFiles to fileName):

      RefSpectra              (peptideModSeq, precursorCharge)
      RetentionTimes          (peptideModSeq, precursorCharge, fileName)
      Modifications           (peptideModSeq, precursorCharge, position)
      RefSpectraProteins      (peptideModSeq, precursorCharge, accession)
      Proteins                (accession)
      OspreyPeakBoundaries    (peptideModSeq, precursorCharge, FileName)
      OspreyRunScores         (peptideModSeq, precursorCharge, FileName)
      OspreyExperimentScores  (peptideModSeq, precursorCharge)
      OspreyCoefficients      (peptideModSeq, precursorCharge, FileName, ScanNumber)
      OspreyMetadata          (Key)

.PARAMETER RustBlib
    Path to the Rust .blib.

.PARAMETER CsBlib
    Path to the C# .blib.

.PARAMETER MaxSampleRows
    Sample divergent rows printed per column when a column fails
    (default: 5).

.PARAMETER NumericTolerance
    Absolute tolerance for floating-point columns (default: 1e-9).
#>

param(
    [Parameter(Mandatory=$true)] [string]$RustBlib,
    [Parameter(Mandatory=$true)] [string]$CsBlib,
    [int]$MaxSampleRows = 5,
    [double]$NumericTolerance = 1e-9
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Dot-source the shared config from the Osprey scripts root, so
# this script works whether it lives at the top of ai/scripts/Osprey
# or in the Compare/ subfolder.
$configCandidates = @(
    (Join-Path $PSScriptRoot 'Dataset-Config.ps1'),
    (Join-Path $PSScriptRoot '..\Dataset-Config.ps1')
)
foreach ($c in $configCandidates) { if (Test-Path $c) { . $c; break } }

# Prefer the Osprey net8.0 build's copy: cross-platform (Linux/WSL
# bin includes runtimes/linux-x64/native/SQLite.Interop.dll alongside),
# always present when Osprey itself has been built, and decoupled
# from Skyline Debug build state. Fall back to the Skyline Debug path
# for environments where only Skyline is built.
$pwizRoot = Get-PwizRoot
$ospReleaseBin = Join-Path $pwizRoot 'pwiz_tools/Osprey/Osprey/bin/x64/Release/net8.0'
$candidates = @(
    (Join-Path $ospReleaseBin 'System.Data.SQLite.dll'),
    (Join-Path $pwizRoot 'pwiz_tools/Skyline/bin/x64/Debug/System.Data.SQLite.dll')
)
$dll = $null
foreach ($c in $candidates) {
    if (Test-Path $c) { $dll = $c; break }
}
if (-not $dll) {
    Write-Host "Missing System.Data.SQLite.dll. Tried:" -ForegroundColor Red
    foreach ($c in $candidates) { Write-Host "  $c" -ForegroundColor DarkRed }
    Write-Host "Build Osprey first: pwsh -File ./ai/scripts/Osprey/Build-Osprey.ps1 -TargetFramework net8.0" -ForegroundColor Yellow
    exit 2
}
# System.Data.SQLite uses P/Invoke to "SQLite.Interop.dll". It does NOT
# honor the runtimes/<rid>/native/ convention when loaded outside a
# composed .NET app (e.g. via Add-Type in pwsh) -- it probes the
# assembly directory directly. Ensure the native lib is alongside the
# managed dll. On either OS, the build deposits the native under
# runtimes/<rid>/native/ -- copy it up one level if missing so the
# P/Invoke load succeeds.
$dllDir = Split-Path $dll -Parent
$rid = if ($IsLinux) { 'linux-x64' } else { 'win-x64' }
$nativeSrc = Join-Path $dllDir "runtimes/$rid/native/SQLite.Interop.dll"
$nativeDst = Join-Path $dllDir 'SQLite.Interop.dll'
# Always overwrite: if a previous run on a different OS placed the
# wrong-architecture binary here, P/Invoke would fail with
# "incorrect format" (Windows trying to load an ELF, or vice versa).
# Force-copy from the current-OS runtimes/ source on every invocation.
if (Test-Path $nativeSrc) {
    Copy-Item $nativeSrc $nativeDst -Force
}
Add-Type -Path $dll

if (-not (Test-Path $RustBlib)) { Write-Host "Missing: $RustBlib" -ForegroundColor Red; exit 2 }
if (-not (Test-Path $CsBlib))   { Write-Host "Missing: $CsBlib"   -ForegroundColor Red; exit 2 }

function Invoke-Sqlite {
    param([string]$Db, [string]$Sql)
    $cs = "Data Source=$Db;Read Only=True"
    $conn = New-Object System.Data.SQLite.SQLiteConnection $cs
    $conn.Open()
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = $Sql
        $reader = $cmd.ExecuteReader()
        $cols = @()
        for ($i = 0; $i -lt $reader.FieldCount; $i++) { $cols += $reader.GetName($i) }
        $rows = [System.Collections.Generic.List[hashtable]]::new()
        while ($reader.Read()) {
            $row = @{}
            for ($i = 0; $i -lt $reader.FieldCount; $i++) {
                $v = $reader.GetValue($i)
                if ($v -is [System.DBNull]) { $v = $null }
                $row[$cols[$i]] = $v
            }
            $rows.Add($row)
        }
        $reader.Close()
        return [pscustomobject]@{ Cols = $cols; Rows = $rows }
    } finally {
        $conn.Close()
    }
}

function Compare-Table {
    param(
        [string]$TableName,
        [string]$Sql,
        [string[]]$KeyCols,
        [string[]]$NumericCols = @(),
        [string[]]$ExactCols = @(),
        [string[]]$BlobCols = @()
    )
    Write-Host ""
    Write-Host "=== $TableName ===" -ForegroundColor Cyan
    $rResult = Invoke-Sqlite -Db $RustBlib -Sql $Sql
    $cResult = Invoke-Sqlite -Db $CsBlib   -Sql $Sql

    function Make-Key($row, $cols) {
        ($cols | ForEach-Object {
            $v = $row[$_]
            if ($null -eq $v) { '<null>' } else { $v.ToString() }
        }) -join "`u{1F}"  # unit separator — unlikely in any data field
    }

    $rMap = [System.Collections.Generic.Dictionary[string,hashtable]]::new($rResult.Rows.Count)
    foreach ($row in $rResult.Rows) { $rMap[(Make-Key $row $KeyCols)] = $row }
    $cMap = [System.Collections.Generic.Dictionary[string,hashtable]]::new($cResult.Rows.Count)
    foreach ($row in $cResult.Rows) { $cMap[(Make-Key $row $KeyCols)] = $row }

    Write-Host ("  rows  rust={0,-8}  cs={1,-8}" -f $rResult.Rows.Count, $cResult.Rows.Count)
    $rOnly = [System.Collections.Generic.List[string]]::new()
    foreach ($k in $rMap.Keys) { if (-not $cMap.ContainsKey($k)) { $rOnly.Add($k) } }
    $cOnly = [System.Collections.Generic.List[string]]::new()
    foreach ($k in $cMap.Keys) { if (-not $rMap.ContainsKey($k)) { $cOnly.Add($k) } }
    $color = if ($rOnly.Count -eq 0 -and $cOnly.Count -eq 0) { 'Green' } else { 'Red' }
    Write-Host ("  keys  only-rust={0,-6}  only-cs={1,-6}" -f $rOnly.Count, $cOnly.Count) -ForegroundColor $color
    if ($rOnly.Count -gt 0) {
        Write-Host ("  sample only-rust:")
        $rOnly | Select-Object -First $MaxSampleRows | ForEach-Object { Write-Host "    $_" }
    }
    if ($cOnly.Count -gt 0) {
        Write-Host ("  sample only-cs:")
        $cOnly | Select-Object -First $MaxSampleRows | ForEach-Object { Write-Host "    $_" }
    }

    # Common keys
    $common = [System.Collections.Generic.List[string]]::new()
    foreach ($k in $rMap.Keys) { if ($cMap.ContainsKey($k)) { $common.Add($k) } }

    $tablePass = ($rOnly.Count -eq 0) -and ($cOnly.Count -eq 0)

    foreach ($col in $NumericCols) {
        $nDiverge = 0; $maxDiff = 0.0; $sampleKey = $null; $sampleR = $null; $sampleC = $null
        foreach ($k in $common) {
            $rv = $rMap[$k][$col]; $cv = $cMap[$k][$col]
            if ($null -eq $rv -and $null -eq $cv) { continue }
            if ($null -eq $rv -or $null -eq $cv) {
                # NULL/non-NULL mismatch is a divergence
                $nDiverge++
                if ($null -eq $sampleKey) { $sampleKey = $k; $sampleR = $rv; $sampleC = $cv }
                continue
            }
            $rd = [double]$rv; $cd = [double]$cv
            $d = [Math]::Abs($rd - $cd)
            if ($d -gt $maxDiff) { $maxDiff = $d; $sampleKey = $k; $sampleR = $rd; $sampleC = $cd }
            if ($d -gt $NumericTolerance) { $nDiverge++ }
        }
        $status = if ($nDiverge -eq 0) { 'PASS' } else { 'FAIL' }
        $clr = if ($nDiverge -eq 0) { 'Green' } else { 'Red' }
        Write-Host ("  {0,-26} {1,-4}  max_diff={2:e3}  n_diverg={3}/{4}" -f `
            $col, $status, $maxDiff, $nDiverge, $common.Count) -ForegroundColor $clr
        if ($nDiverge -gt 0 -and $sampleKey) {
            Write-Host ("    first-diverg: key={0}  rust={1}  cs={2}" -f `
                $sampleKey, $sampleR, $sampleC) -ForegroundColor DarkGray
            $tablePass = $false
        }
    }

    foreach ($col in $ExactCols) {
        $nDiverge = 0; $sampleKey = $null; $sampleR = $null; $sampleC = $null
        foreach ($k in $common) {
            $rv = $rMap[$k][$col]; $cv = $cMap[$k][$col]
            if (($null -eq $rv -and $null -eq $cv)) { continue }
            $rs = if ($null -eq $rv) { '<null>' } else { $rv.ToString() }
            $cs = if ($null -eq $cv) { '<null>' } else { $cv.ToString() }
            if ($rs -ne $cs) {
                $nDiverge++
                if ($null -eq $sampleKey) { $sampleKey = $k; $sampleR = $rs; $sampleC = $cs }
            }
        }
        $status = if ($nDiverge -eq 0) { 'PASS' } else { 'FAIL' }
        $clr = if ($nDiverge -eq 0) { 'Green' } else { 'Red' }
        Write-Host ("  {0,-26} {1,-4}  n_diverg={2}/{3}  (exact)" -f `
            $col, $status, $nDiverge, $common.Count) -ForegroundColor $clr
        if ($nDiverge -gt 0 -and $sampleKey) {
            Write-Host ("    first-diverg: key={0}  rust='{1}'  cs='{2}'" -f `
                $sampleKey, $sampleR, $sampleC) -ForegroundColor DarkGray
            $tablePass = $false
        }
    }

    foreach ($col in $BlobCols) {
        $nDiverge = 0; $sampleKey = $null
        foreach ($k in $common) {
            $rv = $rMap[$k][$col]; $cv = $cMap[$k][$col]
            $rb = if ($rv -is [byte[]]) { $rv } else { $null }
            $cb = if ($cv -is [byte[]]) { $cv } else { $null }
            $eq = $false
            if ($null -eq $rb -and $null -eq $cb) { $eq = $true }
            elseif ($null -ne $rb -and $null -ne $cb -and $rb.Length -eq $cb.Length) {
                $eq = $true
                for ($i = 0; $i -lt $rb.Length; $i++) {
                    if ($rb[$i] -ne $cb[$i]) { $eq = $false; break }
                }
            }
            if (-not $eq) {
                $nDiverge++
                if ($null -eq $sampleKey) { $sampleKey = $k }
            }
        }
        $status = if ($nDiverge -eq 0) { 'PASS' } else { 'FAIL' }
        $clr = if ($nDiverge -eq 0) { 'Green' } else { 'Red' }
        Write-Host ("  {0,-26} {1,-4}  n_diverg={2}/{3}  (binary)" -f `
            $col, $status, $nDiverge, $common.Count) -ForegroundColor $clr
        if ($nDiverge -gt 0 -and $sampleKey) {
            Write-Host ("    first-diverg: key={0}" -f $sampleKey) -ForegroundColor DarkGray
            $tablePass = $false
        }
    }

    return $tablePass
}

# ----------------------------------------------------------------------
# Per-table comparisons
# ----------------------------------------------------------------------

$allPass = $true

# RefSpectra — top-level. Skip 'id' (autoincrement) and 'fileID' (depends
# on SpectrumSourceFiles autoincrement order). retentionTime / startTime
# / endTime + precursorMZ + score are the comparable numerics.
$refSpectraSql = @"
SELECT peptideSeq, peptideModSeq, precursorCharge, prevAA, nextAA, copies,
       numPeaks, ionMobility, retentionTime, startTime, endTime,
       precursorMZ, score, scoreType
FROM RefSpectra
"@
$allPass = (Compare-Table `
    -TableName 'RefSpectra' `
    -Sql $refSpectraSql `
    -KeyCols @('peptideModSeq', 'precursorCharge') `
    -NumericCols @('precursorMZ', 'retentionTime', 'startTime', 'endTime', 'score', 'ionMobility') `
    -ExactCols @('peptideSeq', 'prevAA', 'nextAA', 'copies', 'numPeaks', 'scoreType')
) -and $allPass

# RefSpectraPeaks — blob columns. Join through RefSpectra for stable key.
$peaksSql = @"
SELECT r.peptideModSeq, r.precursorCharge, p.peakMZ, p.peakIntensity
FROM RefSpectraPeaks p
JOIN RefSpectra r ON p.RefSpectraID = r.id
"@
$allPass = (Compare-Table `
    -TableName 'RefSpectraPeaks' `
    -Sql $peaksSql `
    -KeyCols @('peptideModSeq', 'precursorCharge') `
    -BlobCols @('peakMZ', 'peakIntensity')
) -and $allPass

# Modifications — keyed by (RefSpectra key, position).
$modSql = @"
SELECT r.peptideModSeq, r.precursorCharge, m.position, m.mass
FROM Modifications m
JOIN RefSpectra r ON m.RefSpectraID = r.id
"@
$allPass = (Compare-Table `
    -TableName 'Modifications' `
    -Sql $modSql `
    -KeyCols @('peptideModSeq', 'precursorCharge', 'position') `
    -NumericCols @('mass')
) -and $allPass

# Proteins — keyed by accession.
$allPass = (Compare-Table `
    -TableName 'Proteins' `
    -Sql 'SELECT accession FROM Proteins' `
    -KeyCols @('accession')
) -and $allPass

# RefSpectraProteins — link table, key (RefSpectra key, accession).
$rspSql = @"
SELECT r.peptideModSeq, r.precursorCharge, p.accession
FROM RefSpectraProteins x
JOIN RefSpectra r ON x.RefSpectraID = r.id
JOIN Proteins p   ON x.ProteinID    = p.id
"@
$allPass = (Compare-Table `
    -TableName 'RefSpectraProteins' `
    -Sql $rspSql `
    -KeyCols @('peptideModSeq', 'precursorCharge', 'accession')
) -and $allPass

# RetentionTimes — key (RefSpectra key, fileName). Join through
# SpectrumSourceFiles for fileName.
$rtSql = @"
SELECT r.peptideModSeq, r.precursorCharge, sf.fileName,
       rt.retentionTime, rt.startTime, rt.endTime, rt.score, rt.bestSpectrum
FROM RetentionTimes rt
JOIN RefSpectra r           ON rt.RefSpectraID    = r.id
JOIN SpectrumSourceFiles sf ON rt.SpectrumSourceID = sf.id
"@
$allPass = (Compare-Table `
    -TableName 'RetentionTimes' `
    -Sql $rtSql `
    -KeyCols @('peptideModSeq', 'precursorCharge', 'fileName') `
    -NumericCols @('retentionTime', 'startTime', 'endTime', 'score') `
    -ExactCols @('bestSpectrum')
) -and $allPass

# OspreyExperimentScores — one row per RefSpectra.
$expSql = @"
SELECT r.peptideModSeq, r.precursorCharge,
       s.ExperimentQValue, s.NRunsDetected, s.NRunsSearched
FROM OspreyExperimentScores s
JOIN RefSpectra r ON s.RefSpectraID = r.id
"@
$allPass = (Compare-Table `
    -TableName 'OspreyExperimentScores' `
    -Sql $expSql `
    -KeyCols @('peptideModSeq', 'precursorCharge') `
    -NumericCols @('ExperimentQValue') `
    -ExactCols @('NRunsDetected', 'NRunsSearched')
) -and $allPass

# OspreyRunScores — key (RefSpectra key, FileName).
$runSql = @"
SELECT r.peptideModSeq, r.precursorCharge,
       s.FileName, s.RunQValue, s.DiscriminantScore, s.PosteriorErrorProb
FROM OspreyRunScores s
JOIN RefSpectra r ON s.RefSpectraID = r.id
"@
$allPass = (Compare-Table `
    -TableName 'OspreyRunScores' `
    -Sql $runSql `
    -KeyCols @('peptideModSeq', 'precursorCharge', 'FileName') `
    -NumericCols @('RunQValue', 'DiscriminantScore', 'PosteriorErrorProb')
) -and $allPass

# OspreyPeakBoundaries — key (RefSpectra key, FileName).
$pbSql = @"
SELECT r.peptideModSeq, r.precursorCharge,
       s.FileName, s.StartRT, s.EndRT, s.ApexRT, s.ApexIntensity, s.IntegratedArea
FROM OspreyPeakBoundaries s
JOIN RefSpectra r ON s.RefSpectraID = r.id
"@
$allPass = (Compare-Table `
    -TableName 'OspreyPeakBoundaries' `
    -Sql $pbSql `
    -KeyCols @('peptideModSeq', 'precursorCharge', 'FileName') `
    -NumericCols @('StartRT', 'EndRT', 'ApexRT', 'ApexIntensity', 'IntegratedArea')
) -and $allPass

# OspreyCoefficients — key (RefSpectra key, FileName, ScanNumber).
$coefSql = @"
SELECT r.peptideModSeq, r.precursorCharge,
       s.FileName, s.ScanNumber, s.RT, s.Coefficient
FROM OspreyCoefficients s
JOIN RefSpectra r ON s.RefSpectraID = r.id
"@
$allPass = (Compare-Table `
    -TableName 'OspreyCoefficients' `
    -Sql $coefSql `
    -KeyCols @('peptideModSeq', 'precursorCharge', 'FileName', 'ScanNumber') `
    -NumericCols @('RT', 'Coefficient')
) -and $allPass

# OspreyMetadata — exact key + value match, EXCLUDING osprey_version:
# Osprey is intentionally on the Skyline version scheme (e.g. 26.1.1.x)
# while Rust osprey uses its own (e.g. 26.6.1), so that one key is an expected
# cross-impl difference, not a divergence. All other metadata must still match.
$allPass = (Compare-Table `
    -TableName 'OspreyMetadata' `
    -Sql "SELECT Key, Value FROM OspreyMetadata WHERE Key <> 'osprey_version'" `
    -KeyCols @('Key') `
    -ExactCols @('Value')
) -and $allPass

# SpectrumSourceFiles — keyed by fileName.
$allPass = (Compare-Table `
    -TableName 'SpectrumSourceFiles' `
    -Sql 'SELECT fileName, idFileName, cutoffScore, workflowType FROM SpectrumSourceFiles' `
    -KeyCols @('fileName') `
    -NumericCols @('cutoffScore') `
    -ExactCols @('idFileName', 'workflowType')
) -and $allPass

Write-Host ""
if ($allPass) {
    Write-Host "OVERALL: PASS — .blib cross-impl row + content parity within tolerance." -ForegroundColor Green
    exit 0
} else {
    Write-Host "OVERALL: FAIL" -ForegroundColor Red
    exit 1
}
