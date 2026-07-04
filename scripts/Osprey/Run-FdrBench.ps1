<#
.SYNOPSIS
    Osprey FDRBench entrapment-calibration driver: run Osprey to emit an
    FDRBench input TSV, run the FDRBench jar to measure true FDP, and report
    the calibration metrics.

.DESCRIPTION
    FDRBench (https://github.com/Noble-Lab/FDRBench) is the independent
    correctness oracle for Osprey's FDR. It measures the *true* false-discovery
    proportion (FDP) of a run by the entrapment method: the search library is
    spiked with entrapment sequences known to be absent from the sample, so any
    entrapment peptide reported at a given q-value is a known-false discovery.
    A perfectly calibrated search tracks the y=x line (reported q == true FDP);
    a curve above it is anti-conservative. See the "FDRBench entrapment
    validation" section of ai/docs/osprey-development-guide.md for the doctrine
    (the oracle wins over cross-impl parity when they disagree).

    This is the committed replacement for the per-session bash scripts that used
    to live under ai/.tmp/ (run-cell.sh, run-fdrbench.sh, drive-all.sh,
    strip-decoys.sh). It runs three stages:

      1. Osprey  -- emits the FDRBench input TSV via --fdrbench (every reported
                    target, raw SVM discriminant as 'score', entrapment marked
                    by _p_target, decoys excluded).
      2. FDRBench jar -- java -jar ... -level <lvl> -score 'score:1'
                    -entrapment_label _p_target  ->  fdp.csv
      3. Metrics -- parses fdp.csv natively (no Python) and reports
                    disc@1%q, combined/paired FDP@1%q, and disc@1% true FDP.

    DecoySource selects the comparison Mike's May-2026 work established:
      * Library    -- trust the library-supplied (Carafe) decoys
                      (--decoys-in-library + pairing manifest). Near-calibrated.
      * Generated  -- strip the library's decoys and let Osprey generate its own
                      reverse decoys. Severely anti-conservative on entrapment
                      data -- this is the cell that demonstrates *why* library
                      decoys are preferred.

    Requires an entrapment dataset (a *LibraryDecoy config, which carries the
    pairing Manifest); FDRBench cannot measure FDP without entrapment sequences.

.PARAMETER Dataset
    StellarLibraryDecoy (default) or AstralLibraryDecoy. Plain Stellar/Astral
    have no entrapment sequences and are rejected.

.PARAMETER DecoySource
    Library (default) = library-supplied decoys; Generated = Osprey-generated
    reverse decoys over a decoy-stripped copy of the library.

.PARAMETER Files
    All (default, 3-file) or Single.

.PARAMETER Pass
    2 (default) = the post-compaction reported set (what the user sees).
    1 = the full pre-compaction first-pass pool. Pass 1 requires the
    --fdrbench-pass CLI flag, which as of 2026-07-03 lives on branch
    Skyline/work/20260630_osprey_libdecoy_reconciliation_baseid and is not yet
    on master; -Pass 1 against a master build will fail at the Osprey stage.

.PARAMETER ProteinFdr
    Value for --protein-fdr (default 0.01). Note --protein-fdr triggers the
    2nd-pass Percolator recalibration; pass an empty string to omit it (the
    calibrated baseline, cell A of the pass-2 oracle).

.PARAMETER Level
    precursor (default) or peptide. Maps to BOTH Osprey --fdr-level and
    FDRBench -level. Peptide level has historically errored in FDRBench
    ("entrapment hits > k=1") on these libraries; precursor is the trusted path.

.PARAMETER FragmentTolerance
    Optional --fragment-tolerance value (e.g. 0.4 for Stellar's controlled
    tolerance). Omitted => Osprey's calibrated tolerance.

.PARAMETER SkipOsprey
    Reuse an existing fdrbench TSV in the output directory instead of re-running
    Osprey (the heavy step). Fails if the TSV is absent.

.PARAMETER SkipFdrBench
    Run only the Osprey stage (emit the TSV), skip the jar + metrics.

.EXAMPLE
    # The calibrated reference cell (library decoys, reported level):
    pwsh -File ./ai/scripts/Osprey/Run-FdrBench.ps1 -Dataset StellarLibraryDecoy

.EXAMPLE
    # The anti-conservative demonstration (generated decoys):
    pwsh -File ./ai/scripts/Osprey/Run-FdrBench.ps1 -DecoySource Generated

.EXAMPLE
    # The pass-2 --protein-fdr A/B (cell A = off, cell B = on), controlled tol:
    pwsh -File ./ai/scripts/Osprey/Run-FdrBench.ps1 -ProteinFdr '' -FragmentTolerance 0.4 -OutName A_noprotein
    pwsh -File ./ai/scripts/Osprey/Run-FdrBench.ps1 -ProteinFdr 0.01 -FragmentTolerance 0.4 -OutName B_proteinfdr

.NOTES
    Java (for the FDRBench jar) and a built Release net8.0 Osprey.exe must be on
    the machine. FDRBench jar is resolved from -FdrBenchJar, then
    $env:FDRBENCH_JAR, then D:\test\fdrbench\fdrbench-*\fdrbench-*.jar.
#>
[CmdletBinding()]
param(
    [ValidateSet('StellarLibraryDecoy', 'AstralLibraryDecoy')]
    [string]$Dataset = 'StellarLibraryDecoy',

    [ValidateSet('Library', 'Generated')]
    [string]$DecoySource = 'Library',

    [ValidateSet('Single', 'All')]
    [string]$Files = 'All',

    [ValidateSet(1, 2)]
    [int]$Pass = 2,

    [string]$ProteinFdr = '0.01',

    [ValidateSet('precursor', 'peptide')]
    [string]$Level = 'precursor',

    [string]$FragmentTolerance = $null,
    [string]$FragmentUnit = 'mz',
    [int]$Threads = 30,

    [string]$OutName = $null,
    [string]$OutDir = $null,
    [string]$FdrBenchJar = $null,
    [string]$TestBaseDir = $null,
    [ValidateSet('net8.0', 'net472')]
    [string]$Framework = 'net8.0',

    [switch]$SkipOsprey,
    [switch]$SkipFdrBench
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\Dataset-Config.ps1"

# ============================================================================
# Helpers.  Unlike C# (ai/CRITICAL-RULES.md "helpers LAST"), a PowerShell
# script executes top-to-bottom, so a function must be DEFINED before the
# mainline line that calls it. Helpers therefore come first here.
# ============================================================================

function Resolve-FdrBenchJar {
    <#
    Resolve the FDRBench jar: explicit -FdrBenchJar, then $env:FDRBENCH_JAR,
    then a glob under the conventional D:\test\fdrbench\ (or the Linux mount).
    Picks the highest version if several are present.
    #>
    param([string]$Explicit)

    if ($Explicit) {
        if (-not (Test-Path $Explicit)) { throw "FDRBench jar not found: $Explicit" }
        return (Resolve-Path $Explicit).Path
    }
    if ($env:FDRBENCH_JAR -and (Test-Path $env:FDRBENCH_JAR)) {
        return (Resolve-Path $env:FDRBENCH_JAR).Path
    }
    $root = if ($IsLinux) { '/mnt/d/test/fdrbench' } else { 'D:\test\fdrbench' }
    $found = Get-ChildItem -Path $root -Recurse -Filter 'fdrbench-*.jar' -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1
    if (-not $found) {
        throw "No FDRBench jar found. Set -FdrBenchJar or `$env:FDRBENCH_JAR, or place fdrbench-*.jar under $root."
    }
    return $found.FullName
}

function Build-GenDecoyLibrary {
    <#
    Write a decoy-stripped copy of a Carafe spectral library: keep the header
    plus target + entrapment (p_target) rows, drop library-supplied decoys
    (ProteinID column carries a decoy_/rev_/DECOY_ prefix). Streams line by
    line so it is safe on multi-GB Astral libraries. Idempotent -- reuses an
    existing non-empty destination. Port of the ai/.tmp strip-decoys.sh awk.
    #>
    param(
        [Parameter(Mandatory)] [string]$SourceLibrary,
        [Parameter(Mandatory)] [string]$DestLibrary
    )
    if (-not (Test-Path $SourceLibrary)) { throw "Source library not found: $SourceLibrary" }
    if ((Test-Path $DestLibrary) -and (Get-Item $DestLibrary).Length -gt 0) {
        Write-Host "  [gendecoy] reusing $DestLibrary" -ForegroundColor Yellow
        return $DestLibrary
    }

    Write-Host "  [gendecoy] stripping decoys: $SourceLibrary -> $DestLibrary ..."
    $reader = [System.IO.StreamReader]::new($SourceLibrary)
    $writer = [System.IO.StreamWriter]::new($DestLibrary, $false)
    try {
        $kept = 0; $dropped = 0; $first = $true
        while (($line = $reader.ReadLine()) -ne $null) {
            if ($first) { $writer.WriteLine($line); $first = $false; continue }
            $cols = $line.Split("`t")
            # ProteinID is column 6 (1-based) in the Carafe TSV layout.
            $protein = if ($cols.Length -ge 6) { $cols[5] } else { '' }
            if ($protein -match '^(decoy_|rev_|DECOY_)') { $dropped++ }
            else { $writer.WriteLine($line); $kept++ }
        }
        Write-Host ("  [gendecoy] kept {0} rows, dropped {1} decoy rows" -f $kept, $dropped) -ForegroundColor Green
    }
    finally {
        $reader.Dispose(); $writer.Dispose()
    }
    return $DestLibrary
}

function Get-FdrBenchCalibration {
    <#
    Parse an FDRBench fdp.csv and return the standard calibration metrics.
    fdp.csv rows are per-precursor, ranked by score; q_value / combined_fdp /
    paired_fdp are the estimated values at that threshold, n_t is the running
    target count. Returns a PSCustomObject.

      DiscAt1PctQ        -- reported discoveries at Osprey q <= 0.01
      CombinedFdpAt1PctQ -- true combined FDP at the q=1% threshold (want <=0.01)
      PairedFdpAt1PctQ   -- true paired FDP at the q=1% threshold
      DiscAt1PctTrueFdp  -- discoveries at true 1% combined FDP (method yardstick)
    #>
    param([Parameter(Mandatory)] [string]$FdpCsv)

    $ci = [System.Globalization.CultureInfo]::InvariantCulture
    $rows = Import-Csv $FdpCsv | ForEach-Object {
        [pscustomobject]@{
            Q        = [double]::Parse($_.q_value, $ci)
            Combined = [double]::Parse($_.combined_fdp, $ci)
            Paired   = [double]::Parse($_.paired_fdp, $ci)
            Nt       = [double]::Parse($_.n_t, $ci)
        }
    } | Sort-Object Q

    $atQ = $rows | Where-Object { $_.Q -le 0.01 }
    $combAtQ = if ($atQ) { ($atQ | Select-Object -Last 1).Combined } else { [double]::NaN }
    $pairAtQ = if ($atQ) { ($atQ | Select-Object -Last 1).Paired } else { [double]::NaN }

    $trueOk = $rows | Where-Object { $_.Combined -le 0.01 }
    $discTrue = if ($trueOk) { [int](($trueOk | Measure-Object Nt -Maximum).Maximum) } else { 0 }

    [pscustomobject]@{
        NRows              = $rows.Count
        DiscAt1PctQ        = ($atQ | Measure-Object).Count
        CombinedFdpAt1PctQ = $combAtQ
        PairedFdpAt1PctQ   = $pairAtQ
        DiscAt1PctTrueFdp  = $discTrue
    }
}

# ============================================================================
# Mainline
# ============================================================================

$ds = Get-DatasetConfig $Dataset -TestBaseDir $TestBaseDir
if (-not $ds.Manifest) {
    throw "Dataset '$Dataset' has no entrapment pairing manifest; FDRBench cannot measure FDP. Use a *LibraryDecoy dataset."
}

$exe = Get-OspreyExe -Framework $Framework
if (-not (Test-Path $exe)) {
    throw "Osprey.exe not found at $exe. Build Release ($Framework) first (Build-Osprey.ps1 -Configuration Release)."
}

# The pairing manifest doubles as FDRBench's -pep file (it classifies
# target / decoy / p_target / p_decoy). It lives in the library-decoy TestDir
# regardless of which DecoySource we run.
$manifest = Join-Path $ds.TestDir $ds.Manifest
if (-not (Test-Path $manifest)) {
    throw "Pairing manifest not found: $manifest"
}

$mzmlNames = if ($Files -eq 'Single') { , $ds.SingleFile } else { $ds.AllFiles }
$mzml = $mzmlNames | ForEach-Object {
    $p = Join-Path $ds.TestDir $_
    if (-not (Test-Path $p)) { throw "Input mzML not found: $p" }
    $p
}

# DecoySource -> library + Osprey decoy flags.
$decoyFlags = @()
if ($DecoySource -eq 'Library') {
    $library = Join-Path $ds.TestDir $ds.Library
    $decoyFlags = @('--decoys-in-library', '--decoy-pairing-manifest', $manifest)
}
else {
    # Generated: strip the library-supplied decoys (keep target + entrapment),
    # let Osprey build its own reverse decoys. Cached beside the dataset.
    $library = Build-GenDecoyLibrary -SourceLibrary (Join-Path $ds.TestDir $ds.Library) `
        -DestLibrary (Join-Path $ds.TestDir 'carafe_spectral_library.gendecoy.tsv')
}
if (-not (Test-Path $library)) { throw "Spectral library not found: $library" }

# Output directory: <baseDir>/_fdrbench/<name>
if (-not $OutName) {
    $tol = if ($FragmentTolerance) { "_tol$FragmentTolerance" } else { '' }
    $prot = if ($ProteinFdr) { '_prot' } else { '_noprot' }
    $OutName = "{0}_{1}_{2}_pass{3}{4}{5}" -f `
        $ds.Name, $DecoySource.ToLower(), $Level, $Pass, $prot, $tol
}
if (-not $OutDir) {
    $OutDir = Join-Path (Split-Path -Parent $ds.TestDir) (Join-Path '_fdrbench' $OutName)
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$fdrbenchTsv = Join-Path $OutDir 'fdrbench.tsv'
$fdpCsv = Join-Path $OutDir 'fdp.csv'

Write-Host "=== FDRBench cell: $OutName ===" -ForegroundColor Cyan
Write-Host "  Dataset      : $($ds.Name) ($Files, $($mzml.Count) file(s))"
Write-Host "  Decoy source : $DecoySource"
Write-Host "  Library      : $library"
Write-Host "  Level / pass : $Level / pass $Pass"
Write-Host "  Protein FDR  : $(if ($ProteinFdr) { $ProteinFdr } else { '(off)' })"
Write-Host "  Output dir   : $OutDir"

# ----------------------------------------------------------------------------
# Stage 1: Osprey -> FDRBench input TSV
# ----------------------------------------------------------------------------
if ($SkipOsprey) {
    if (-not (Test-Path $fdrbenchTsv)) {
        throw "-SkipOsprey set but no existing TSV at $fdrbenchTsv"
    }
    Write-Host "  [skip] reusing existing $fdrbenchTsv" -ForegroundColor Yellow
}
else {
    $ospreyArgs = @('-i') + $mzml + @(
        '-l', $library,
        '-o', (Join-Path $OutDir 'out.blib'),
        '--resolution', $ds.Resolution,
        '--fdr-level', $Level,
        '--threads', $Threads
    )
    if ($ProteinFdr) { $ospreyArgs += @('--protein-fdr', $ProteinFdr) }
    if ($FragmentTolerance) {
        $ospreyArgs += @('--fragment-tolerance', $FragmentTolerance, '--fragment-unit', $FragmentUnit)
    }
    $ospreyArgs += $decoyFlags
    $ospreyArgs += @('--fdrbench', $fdrbenchTsv)
    if ($Pass -ne 2) { $ospreyArgs += @('--fdrbench-pass', "$Pass") }
    $ospreyArgs += @('--output-dir', $OutDir)

    $runLog = Join-Path $OutDir 'run.log'
    Write-Host "  [osprey] running (log: $runLog) ..."
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    & $exe @ospreyArgs *>&1 | Tee-Object -FilePath $runLog | Out-Null
    $sw.Stop()
    if ($LASTEXITCODE -ne 0) {
        throw "Osprey exited $LASTEXITCODE (see $runLog). If -Pass 1, note --fdrbench-pass is not on master."
    }
    if (-not (Test-Path $fdrbenchTsv)) { throw "Osprey did not emit $fdrbenchTsv (see $runLog)" }
    $rows = (Get-Content $fdrbenchTsv -ReadCount 0).Count - 1
    Write-Host ("  [osprey] done in {0:n1}s; TSV rows = {1}" -f $sw.Elapsed.TotalSeconds, $rows) -ForegroundColor Green
}

if ($SkipFdrBench) {
    Write-Host "  [skip] FDRBench stage (-SkipFdrBench). TSV: $fdrbenchTsv" -ForegroundColor Yellow
    return
}

# ----------------------------------------------------------------------------
# Stage 2: FDRBench jar -> fdp.csv
# ----------------------------------------------------------------------------
$jar = Resolve-FdrBenchJar -Explicit $FdrBenchJar
Write-Host "  [fdrbench] jar: $jar"
if (-not (Get-Command java -ErrorAction SilentlyContinue)) {
    throw "java not found on PATH; the FDRBench jar needs a JRE."
}

$fdrLog = Join-Path $OutDir 'fdrbench.log'
# -score 'score:1' => the 'score' column is higher-is-better (raw SVM discriminant).
& java '-Xmx8G' '-jar' $jar '-i' $fdrbenchTsv '-level' $Level '-score' 'score:1' `
    '-pep' $manifest '-entrapment_label' '_p_target' '-o' $fdpCsv *>&1 |
    Tee-Object -FilePath $fdrLog | Out-Null
if ($LASTEXITCODE -ne 0) { throw "FDRBench exited $LASTEXITCODE (see $fdrLog)" }
if (-not (Test-Path $fdpCsv)) { throw "FDRBench did not emit $fdpCsv (see $fdrLog)" }

# ----------------------------------------------------------------------------
# Stage 3: calibration metrics
# ----------------------------------------------------------------------------
$m = Get-FdrBenchCalibration -FdpCsv $fdpCsv
$metricsCsv = Join-Path $OutDir 'metrics.csv'
[pscustomobject]@{
    dataset            = $ds.Name
    decoy_source       = $DecoySource
    level              = $Level
    pass               = $Pass
    protein_fdr        = if ($ProteinFdr) { $ProteinFdr } else { 'off' }
    n_rows             = $m.NRows
    'disc@1%q'         = $m.DiscAt1PctQ
    'combined_fdp@1%q' = ('{0:n4}' -f $m.CombinedFdpAt1PctQ)
    'paired_fdp@1%q'   = ('{0:n4}' -f $m.PairedFdpAt1PctQ)
    'disc@1%_true_fdp' = $m.DiscAt1PctTrueFdp
} | Export-Csv -Path $metricsCsv -NoTypeInformation

$verdict = if ($m.CombinedFdpAt1PctQ -gt 0.012) { '(ABOVE the line -- anti-conservative)' }
    elseif ($m.CombinedFdpAt1PctQ -le 0.011) { '(at/below the line -- controlled)' } else { '' }

Write-Host ""
Write-Host "=== Calibration ($OutName) ===" -ForegroundColor Cyan
Write-Host ("  disc @ 1% q            : {0}" -f $m.DiscAt1PctQ)
Write-Host ("  combined FDP @ 1% q    : {0:n2}%   {1}" -f (100 * $m.CombinedFdpAt1PctQ), $verdict)
Write-Host ("  paired FDP @ 1% q      : {0:n2}%" -f (100 * $m.PairedFdpAt1PctQ))
Write-Host ("  disc @ 1% TRUE FDP     : {0}   (honest yardstick for comparing methods)" -f $m.DiscAt1PctTrueFdp)
Write-Host ("  metrics.csv            : {0}" -f $metricsCsv)
Write-Host ("  fdp.csv                : {0}" -f $fdpCsv)
