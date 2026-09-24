<#
.SYNOPSIS
    Build an Osprey spectral library end to end with CarafeSharp: digest a protein FASTA,
    predict a generic library, search a training run with Osprey, fine-tune on Osprey's
    training export, predict the final library, and search every run with it. Every library
    is a .blib.

.DESCRIPTION
    The CarafeSharp counterpart of ai/scripts/Osprey/Carafe/Run-CarafeOspreyWorkflow.ps1 (Mike
    MacCoss's Carafe "Workflow 5"). It has the same stages, the same Carafe parameters and the
    same presets, and differs in four ways:

      * CarafeSharp replaces Java Carafe and its Python venv; there is no JDK or peptdeep to
        install.
      * Libraries are .blib (with peak annotations and DecoyPairs), not DIA-NN TSV.
      * CarafeSharp reads no spectra. Stage 3 runs Osprey with --training-export, and stage 4-5
        trains on the <stem>.training.parquet it writes. Osprey's median polish and
        shared-peak evidence feed Carafe's masking rules (pwiz_tools/CarafeSharp/docs/02-masking.md).
      * Osprey writes its artifacts to per-stage folders and its spectra cache to one shared
        folder (--output-dir / --cache-dir), so the mzML are read in place and never copied.

    Stages (run a subset with -Stages):

        1a    digest FASTA -> target+decoy training peptides   (entrapment-free)
        1b    digest FASTA -> target+decoy+entrapment peptides (quartets)
        2     CarafeSharp predicts a GENERIC library from the 1a peptides
        3     Osprey searches ONE training run with it, writing the training export
        4-5   CarafeSharp fine-tunes RT+MS2 on the export, then predicts the FINAL library
              from the 1b entrapment peptides
        6     Osprey searches ALL runs with the final library (+ FDRBench input)

    Osprey must be a build with --training-export (the osprey_carafe_export branch until it
    merges); -Preflight checks.

.PARAMETER Dataset
    Stellar or Astral; selects the FASTA, runs, training run and tolerances (see the Carafe
    workflow script; the Astral prediction tolerance is unvalidated there too).

.PARAMETER Device
    gpu (default; a CPU-only CarafeSharp build falls back to the CPU) or cpu.

.EXAMPLE
    pwsh -File ./ai/scripts/CarafeSharp/Run-CarafeSharpWorkflow.ps1 -Preflight `
        -MzmlSourceDir D:\GitHub-Repo\maccoss\osprey\example_test_data\stellar -OspreyExe <exe>

.EXAMPLE
    # Reuse stages 1-3 of an earlier run and redo only the fine-tune, library and search.
    pwsh -File ./ai/scripts/CarafeSharp/Run-CarafeSharpWorkflow.ps1 -Stages 4-5,6 -WorkDir D:\test\carafesharp-runs\stellar

.NOTES
    Long runs lock both executables. Snapshot the build output first if you intend to keep
    building (Osprey: D:\test\osprey-runs\_bin\<tag>; the same applies to CarafeSharp).
#>
#requires -Version 7
[CmdletBinding()]
param(
    [ValidateSet('Stellar', 'Astral')] [string]$Dataset = 'Stellar',
    [string]$Stages = '1a,1b,2,3,4-5,6',
    [string]$WorkDir,

    [ValidateSet('shuffle', 'natural')] [string]$EntrapmentSource = 'shuffle',
    [switch]$NoSimilarityGate,
    [string]$ForeignFasta,
    [double]$EntrapmentRatio = 1.0,

    [string]$InputFasta,
    [string]$MzmlSourceDir,
    [string[]]$MzmlNames,
    [int]$TrainFileIndex = -1,

    [string]$CarafeSharpExe,
    [string]$OspreyExe,
    [ValidateSet('gpu', 'cpu')] [string]$Device = 'gpu',

    [int]$Threads = 16,
    [string]$ProteinFdr = '0.01',
    [switch]$ModelDiagnostics,
    [switch]$Preflight
)

$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Osprey/Dataset-Config.ps1')

$guide = 'pwiz_tools/CarafeSharp/docs/02-masking.md'

# ---------------------------------------------------------------------------
# Dataset presets (as Run-CarafeOspreyWorkflow.ps1)
# ---------------------------------------------------------------------------
$testFilesRoot = if ($env:OSPREY_TESTFILES_DIR) { $env:OSPREY_TESTFILES_DIR }
                 elseif ($IsLinux) { '/mnt/d/test/osprey-testfiles-mzML' }
                 else { 'D:\test\osprey-testfiles-mzML' }

$presets = @{
    Stellar = @{
        SourceDir   = Join-Path $testFilesRoot 'stellar'
        Fasta       = 'hela-filtered.fasta'
        Files       = @(
            'Ste-2024-12-02_HeLa_4mz_sDIA_400-900_20.mzML',
            'Ste-2024-12-02_HeLa_4mz_sDIA_400-900_21.mzML',
            'Ste-2024-12-02_HeLa_4mz_sDIA_400-900_22.mzML')
        TrainIndex  = 1
        Resolution  = 'unit'
        FragTol     = '0.4'
        FragUnit    = 'mz'
        CarafeItol  = '0.4'
        CarafeItolU = 'Da'
        MinPepMz    = '400'
        MaxPepMz    = '900'
    }
    Astral = @{
        SourceDir   = Join-Path $testFilesRoot 'astral'
        Fasta       = 'uniprot_human_jan2025_yeastENO1_contam_ADpeps.fasta'
        Files       = @(
            'Ast-2024-12-05_HeLa_3mzDIA_6mIIT_400-900_49.mzML',
            'Ast-2024-12-05_HeLa_3mzDIA_6mIIT_400-900_55.mzML',
            'Ast-2024-12-05_HeLa_3mzDIA_6mIIT_400-900_60.mzML')
        TrainIndex  = 1
        Resolution  = 'hram'
        # Both 20 ppm as Mike's June Astral Workflow 5 ran them: carafe_settings.json frag_tol 20 ppm,
        # and the Osprey command in osprey_train/osprey.blib.carafe.sig (example_test_data/astral/
        # Carafe-Osprey-entrapment). The Carafe workflow script's preset keeps Osprey's 10 ppm default.
        FragTol     = '20'
        FragUnit    = 'ppm'
        CarafeItol  = '20'
        CarafeItolU = 'ppm'
        MinPepMz    = '400'
        MaxPepMz    = '900'
    }
}
$preset = $presets[$Dataset]

if (-not $MzmlSourceDir) { $MzmlSourceDir = $preset.SourceDir }
if (-not $InputFasta)    { $InputFasta = Join-Path $MzmlSourceDir $preset.Fasta }
if (-not $MzmlNames)     { $MzmlNames = $preset.Files }
if ($TrainFileIndex -lt 0) { $TrainFileIndex = $preset.TrainIndex }
if (-not $WorkDir) {
    $base = if ($env:CARAFESHARP_WORKDIR) { $env:CARAFESHARP_WORKDIR }
            elseif ($IsLinux) { '/mnt/d/test/carafesharp-runs' }
            else { 'D:\test\carafesharp-runs' }
    $WorkDir = Join-Path $base $Dataset.ToLowerInvariant()
}

# ---------------------------------------------------------------------------
# Tools
# ---------------------------------------------------------------------------
$projectRoot = Get-ProjectRoot
if (-not $CarafeSharpExe) {
    $CarafeSharpExe = if ($env:CARAFESHARP_EXE) { $env:CARAFESHARP_EXE }
                      else { Join-Path $projectRoot 'pwiz\pwiz_tools\CarafeSharp\CarafeSharp\bin\x64\Release\net10.0\CarafeSharp.exe' }
}
if (-not (Test-Path $CarafeSharpExe)) {
    throw ("CarafeSharp.exe not found at '$CarafeSharpExe'. Build it: " +
           'pwsh -File ./ai/scripts/CarafeSharp/Build-CarafeSharp.ps1 (add -Torch cuda for the GPU)')
}
if (-not $OspreyExe) { $OspreyExe = if ($env:OSPREY_EXE) { $env:OSPREY_EXE } else { Get-OspreyExe } }
if (-not (Test-Path $OspreyExe)) {
    throw "Osprey.exe not found at '$OspreyExe'. Pass -OspreyExe or set `$env:OSPREY_EXE."
}
$ospreyHelp = (& $OspreyExe --help 2>&1) -join "`n"
if ($ospreyHelp -notmatch '--training-export') {
    throw ("$OspreyExe has no --training-export. CarafeSharp trains on Osprey's training export; " +
           'build Osprey from the osprey_carafe_export branch (or a later master) and pass -OspreyExe.')
}
$cudaBuild = Test-Path (Join-Path (Split-Path -Parent $CarafeSharpExe) 'runtimes\win-x64\native\torch_cuda.dll')

# ---------------------------------------------------------------------------
# Stages
# ---------------------------------------------------------------------------
$StageList = $Stages -split '\s*,\s*' | Where-Object { $_ }
$validStages = @('1a', '1b', '2', '3', '4-5', '6')
foreach ($s in $StageList) {
    if ($validStages -notcontains $s) { throw "Unknown stage '$s' (valid: $($validStages -join ', '))." }
}
if ($EntrapmentSource -eq 'natural') {
    if (-not $ForeignFasta) { throw '-EntrapmentSource natural needs -ForeignFasta (the foreign-species proteome).' }
    if (-not (Test-Path $ForeignFasta)) { throw "ForeignFasta not found: $ForeignFasta" }
}
$needMzml = @('3', '6') | Where-Object { $StageList -contains $_ }
$mzml = $MzmlNames | ForEach-Object { Join-Path $MzmlSourceDir $_ }
if ($needMzml) {
    foreach ($m in $mzml) { if (-not (Test-Path $m)) { throw "mzML not found: $m (pass -MzmlSourceDir)" } }
}
if (($StageList -contains '1a' -or $StageList -contains '1b') -and -not (Test-Path $InputFasta)) {
    throw "Input FASTA not found: $InputFasta"
}
$trainMzml = $mzml[$TrainFileIndex]

Write-Host "`n--- CarafeSharp/Osprey library workflow ---" -ForegroundColor Cyan
[PSCustomObject][ordered]@{
    Dataset          = $Dataset
    Stages           = ($StageList -join ',')
    EntrapmentSource = $EntrapmentSource
    WorkDir          = $WorkDir
    InputFasta       = $InputFasta
    MzmlSourceDir    = $MzmlSourceDir
    TrainingRun      = $MzmlNames[$TrainFileIndex]
    CarafeSharp      = "$CarafeSharpExe  ($(if ($cudaBuild) { 'CUDA build' } else { 'CPU build' }), -device $Device)"
    Osprey           = $OspreyExe
    Resolution       = "$($preset.Resolution) / $($preset.FragTol) $($preset.FragUnit)"
} | Format-List
if ($Device -eq 'gpu' -and -not $cudaBuild) {
    Write-Warning 'CarafeSharp is a CPU build; -device gpu falls back to the CPU (fine-tuning takes hours). Build with -Torch cuda for the GPU.'
}
if ($Preflight) {
    Write-Host 'Preflight only - stopping before any work.' -ForegroundColor Yellow
    return
}

function Invoke-Step([string]$Name, [string]$Exe, [string[]]$CliArgs) {
    Write-Host "`n=== [START] $Name ===" -ForegroundColor Cyan
    Write-Host "$Exe $($CliArgs -join ' ')" -ForegroundColor DarkGray
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    & $Exe @CliArgs
    if ($LASTEXITCODE -ne 0) { throw "$Name FAILED (exit $LASTEXITCODE)" }
    $sw.Stop()
    Write-Host "=== [DONE] $Name ($([math]::Round($sw.Elapsed.TotalMinutes, 2)) min) ===" -ForegroundColor Green
}

New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

# Carafe's library-generation parameters, identical for stage 2 and stage 4-5, with .blib output.
# CarafeSharp reports the XIC options (-itol, -rf, ...) as Osprey's to decide when training.
$libGen = @(
    '-fdr', '0.01', '-itol', $preset.CarafeItol, '-itolu', $preset.CarafeItolU,
    '-rf', '-rf_rt_win', 'auto', '-cor', '0.8', '-min_mz', '200',
    '-n_ion_min', '2', '-c_ion_min', '2', '-mode', 'general', '-device', $Device,
    '-enzyme', 'NoCut', '-miss_c', '1', '-fixMod', '1', '-varMod', '0', '-maxVar', '1', '-clip_n_m',
    '-minLength', '7', '-maxLength', '35',
    '-min_pep_mz', $preset.MinPepMz, '-max_pep_mz', $preset.MaxPepMz,
    '-min_pep_charge', '2', '-max_pep_charge', '3',
    '-lf_frag_mz_min', '200', '-lf_frag_mz_max', '1960', '-lf_top_n_frag', '20',
    '-lf_min_n_frag', '2', '-lf_frag_n_min', '2', '-lf_type', 'blib',
    '-se', 'Osprey', '-decoy_prefix', 'decoy_', '-nm', '-nf', '4', '-min_n', '4',
    '-valid', '-na', '0', '-fast')

$cacheDir = Join-Path $WorkDir 'spectra-cache'
$ospreyCommon = @(
    '--decoys-in-library',
    '--resolution', $preset.Resolution,
    '--fragment-tolerance', $preset.FragTol, '--fragment-unit', $preset.FragUnit,
    '--run-fdr', '0.01', '--experiment-fdr', '0.01',
    '--fdr-method', 'percolator', '--fdr-level', 'precursor',
    '--shared-peptides', 'all', '--threads', "$Threads",
    '--cache-dir', $cacheDir)
if ($ProteinFdr) { $ospreyCommon += @('--protein-fdr', $ProteinFdr) }

$trainFasta   = Join-Path $WorkDir 'osprey_train_db_peptides.fasta'
$trainPairing = Join-Path $WorkDir 'osprey_train_db_pairing.tsv'
$libFasta     = Join-Path $WorkDir 'osprey_library_db_peptides.fasta'
$libPairing   = Join-Path $WorkDir 'osprey_library_db_pairing.tsv'
$initialLib   = Join-Path $WorkDir 'osprey_initial_library'
$trainDir     = Join-Path $WorkDir 'osprey_train'
$trainBlib    = Join-Path $trainDir 'osprey.blib'
$newLib       = Join-Path $WorkDir 'osprey_new_library'
$projectDir   = Join-Path $WorkDir 'osprey_project'
$libraryBlib  = 'carafe_spectral_library.blib'

$digestCommon = @(
    '-enzyme', '2', '-miss_c', '1', '-minLength', '7', '-maxLength', '35',
    '-min_pep_charge', '2', '-max_pep_charge', '3')

if ($StageList -contains '1a') {
    Invoke-Step 'Stage 1a: train FASTA (target+decoy)' $CarafeSharpExe (@(
        '-build_entrapment_fasta', $trainFasta, '-db', $InputFasta, '-manifest', $trainPairing) + $digestCommon)
}

if ($StageList -contains '1b') {
    $entrapArgs = @('-entrapment')
    if ($EntrapmentSource -eq 'natural') { $entrapArgs += @('-entrapment_db', $ForeignFasta) }
    if ($EntrapmentRatio -ne 1.0) { $entrapArgs += @('-entrapment_ratio', "$EntrapmentRatio") }
    if ($NoSimilarityGate) { $entrapArgs += '-no_similarity_gate' }
    Invoke-Step "Stage 1b: library FASTA ($EntrapmentSource entrapment)" $CarafeSharpExe (@(
        '-build_entrapment_fasta', $libFasta, '-db', $InputFasta, '-manifest', $libPairing) + $digestCommon + $entrapArgs)
}

if ($StageList -contains '2') {
    Invoke-Step 'Stage 2: initial library' $CarafeSharpExe (@(
        '-db', $trainFasta, '-o', $initialLib, '-pairing_manifest', $trainPairing) + $libGen)
}

if ($StageList -contains '3') {
    New-Item -ItemType Directory -Force -Path $trainDir | Out-Null
    Invoke-Step 'Stage 3: Osprey search training run (+ training export)' $OspreyExe (@(
        '-i', $trainMzml, '-l', (Join-Path $initialLib $libraryBlib),
        '-o', $trainBlib, '--output-dir', $trainDir,
        '--decoy-pairing-manifest', $trainPairing, '--training-export') + $ospreyCommon)
}

if ($StageList -contains '4-5') {
    Invoke-Step 'Stage 4/5: fine-tune + final library' $CarafeSharpExe (@(
        '-db', $libFasta, '-i', $trainBlib, '-ms', $trainMzml, '-o', $newLib,
        '-pairing_manifest', $libPairing) + $libGen + @('-tf', 'all'))
}

if ($StageList -contains '6') {
    New-Item -ItemType Directory -Force -Path (Join-Path $projectDir 'FDRBench') | Out-Null
    $osArgs = @('-i') + $mzml + @(
        '-l', (Join-Path $newLib $libraryBlib),
        '-o', (Join-Path $projectDir 'osprey.blib'), '--output-dir', $projectDir,
        '--fdrbench', (Join-Path $projectDir 'FDRBench\FDRBench-Input.tsv'),
        '--decoy-pairing-manifest', $libPairing) + $ospreyCommon
    if ($ModelDiagnostics) { $osArgs += '--model-diagnostics' }
    Invoke-Step 'Stage 6: Osprey project search' $OspreyExe $osArgs
}

Write-Host "`n[SUCCESS] Requested stages complete. Work dir: $WorkDir" -ForegroundColor Green
