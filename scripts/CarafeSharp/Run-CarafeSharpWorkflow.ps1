<#
.SYNOPSIS
    Build an Osprey spectral library from a protein FASTA and search every run with it, as ONE
    Osprey command (--fasta): predict a library with CarafeSharp's models, search the training run
    with it, fine-tune on Osprey's training export, predict the final library (with entrapment) and
    search all runs. Every library is a .blib.

.DESCRIPTION
    The harness that names the dataset presets and the lab's validation arm (entrapment in the
    final library, FDRBench input out) for Osprey's one command. The library build used to be six
    stages of separate CarafeSharp and Osprey invocations; it is now the phases of one Osprey run
    (pwiz_tools/Osprey/Osprey-workflow.html, part 1), so this script makes one invocation per
    preset. The CarafeSharp counterpart of ai/scripts/Osprey/Carafe/Run-CarafeOspreyWorkflow.ps1
    (Mike MacCoss's Carafe "Workflow 5"): the same presets and Carafe parameters, but

      * CarafeSharp runs inside Osprey; there is no JDK, Python venv or CarafeSharp.exe step.
      * Libraries are .blib (with peak annotations and DecoyPairs), not DIA-NN TSV, and the digest,
        decoys and entrapment are made in memory: no peptide FASTA or pairing manifest between
        phases (the FDRBench pairing manifest is still written, as <out>.predicted/pairing.tsv).
      * CarafeSharp reads no spectra. The training run's search writes the training export and the
        tuning reads it (pwiz_tools/CarafeSharp/docs/02-masking.md).
      * No mzML is needed. Osprey reads Thermo .raw directly, with vendor centroiding; that takes an
        Osprey built with ai/scripts/Osprey/Build-Osprey.ps1 -VendorReader. Preflight checks for it.

    Every phase checkpoints in the file it writes, so a re-run resumes at the first phase whose
    inputs or settings changed. To run one phase (or one stage of either search), pass -Task, as a
    cluster node would: PredictTrainingLibrary, TrainModel, PredictLibrary, or a stage
    (PerFileScoring, FirstPassFDR, PerFileRescoring, SecondPassFDR) with -TrainingSearch for the
    training run's search. -Stages is gone: --task is the stage selector.

.PARAMETER Dataset
    Stellar, Astral or ZTScan; selects the FASTA, runs, training run and tolerances.

.PARAMETER Mode
    Tuned (default; the lab's workflow: --training-input <training run>) or Pretrained (predict with
    the pretrained models, no tuning).

.PARAMETER Task
    Run one task of the one command (Osprey --task) instead of all of them.

.PARAMETER TrainingSearch
    With a stage -Task: the stage of the training run's search (Osprey --training-search).

.PARAMETER Device
    gpu (default; a CPU-libtorch Osprey falls back to the CPU with a warning) or cpu.

.PARAMETER RtModel
    chronologer (default, as CarafeSharp's) or alphapeptdeep (Carafe's).

.EXAMPLE
    pwsh -File ./ai/scripts/CarafeSharp/Run-CarafeSharpWorkflow.ps1 -Preflight `
        -MzmlSourceDir D:\GitHub-Repo\maccoss\osprey\example_test_data\stellar -OspreyExe <exe>

.EXAMPLE
    # The tuning again with another seed: the training library and its search are current and skip.
    pwsh -File ./ai/scripts/CarafeSharp/Run-CarafeSharpWorkflow.ps1 -ExtraArgs '--seed','7'

.NOTES
    Long runs lock the executable. Snapshot the build output first if you intend to keep building
    (D:\test\osprey-runs\_bin\<tag>). For the GPU, build Osprey with Build-Osprey.ps1 -Torch cuda.
#>
#requires -Version 7
[CmdletBinding()]
param(
    [ValidateSet('Stellar', 'Astral', 'ZTScan')] [string]$Dataset = 'Stellar',
    [ValidateSet('Tuned', 'Pretrained')] [string]$Mode = 'Tuned',
    [string]$Task,
    [switch]$TrainingSearch,
    [string]$WorkDir,

    [ValidateSet('shuffle', 'natural', 'none')] [string]$EntrapmentSource = 'shuffle',
    [string]$ForeignFasta,
    [double]$EntrapmentRatio = 1.0,

    [string]$InputFasta,
    [string]$MzmlSourceDir,
    [string[]]$MzmlNames,
    [ValidateSet('raw', 'mzML')] [string]$InputFormat = 'raw',
    [int]$TrainFileIndex = -1,

    [string]$OspreyExe,
    [ValidateSet('gpu', 'cpu')] [string]$Device = 'gpu',

    [int]$Threads = 16,
    [string]$ProteinFdr = '0.01',
    [switch]$ModelDiagnostics,
    # Osprey's spectra cache, default <WorkDir>\spectra-cache. A .spectra.bin depends only on its input
    # file, so a second run over the same runs can share the first one's.
    [string]$CacheDir,
    [ValidateSet('alphapeptdeep', 'chronologer')] [string]$RtModel = 'chronologer',
    # More Osprey arguments, appended as given (e.g. '--seed','7' or '--entrapment-fasta',...).
    [string[]]$ExtraArgs,
    [switch]$Preflight
)

$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Osprey/Dataset-Config.ps1')

# ---------------------------------------------------------------------------
# Dataset presets (as Run-CarafeOspreyWorkflow.ps1)
# ---------------------------------------------------------------------------
$testFilesRoot = if ($env:OSPREYDEV_TESTFILES_DIR) { $env:OSPREYDEV_TESTFILES_DIR }
                 elseif ($IsLinux) { '/mnt/d/test/osprey-testfiles-mzML' }
                 else { 'D:\test\osprey-testfiles-mzML' }

$presets = @{
    Stellar = @{
        SourceDir   = [IO.Path]::Combine($testFilesRoot, 'stellar')
        Fasta       = 'hela-filtered.fasta'
        Files       = @(
            'Ste-2024-12-02_HeLa_4mz_sDIA_400-900_20',
            'Ste-2024-12-02_HeLa_4mz_sDIA_400-900_21',
            'Ste-2024-12-02_HeLa_4mz_sDIA_400-900_22')
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
        SourceDir   = [IO.Path]::Combine($testFilesRoot, 'astral')
        Fasta       = 'uniprot_human_jan2025_yeastENO1_contam_ADpeps.fasta'
        Files       = @(
            'Ast-2024-12-05_HeLa_3mzDIA_6mIIT_400-900_49',
            'Ast-2024-12-05_HeLa_3mzDIA_6mIIT_400-900_55',
            'Ast-2024-12-05_HeLa_3mzDIA_6mIIT_400-900_60')
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
    # SCIEX ZenoTOF 8600 ZT Scan DIA, as Osprey.DemuxTool's joint solve writes it (the scanning
    # quadrupole demultiplexed; each spectrum a 1.18 Th bin): the vendor files cannot be searched
    # until --demux reads ZT Scan, so the data is the tool's mzML (-InputFormat mzML). Charge 2-4 and
    # the sweep's 392-900 m/z, as the DIA-NN ZT Scan library. SCIEX's beam-type CID reads as CID, which
    # CarafeSharp would train in its resonance CID slot, so the instrument is given; the NCE is the
    # pretrained library's (training takes the run's own collision energy).
    ZTScan = @{
        SourceDir   = 'C:\temp\osprey-runs\ztscan\full\joint_m2_ms1'
        Fasta       = 'Z:\demux-test-data\ZenoTOF8600-ZTScan\uniprot_human_march2026_yeastENO1_contam_ADpeps.fasta'
        Files       = @(
            '250814_ZTScan_100spd_A_1_A1',
            '250814_ZTScan_100spd_A_2_D1',
            '250814_ZTScan_100spd_A_3_G1')
        TrainIndex  = 1
        Resolution  = 'hram'
        FragTol     = '20'
        FragUnit    = 'ppm'
        CarafeItol  = '20'
        CarafeItolU = 'ppm'
        MinPepMz    = '392'
        MaxPepMz    = '900'
        MaxCharge   = '4'
        CarafeExtra = @('--ms-instrument', 'SciexTOF', '--nce', '27')
    }
}
$preset = $presets[$Dataset]
$maxCharge = if ($preset.MaxCharge) { $preset.MaxCharge } else { '3' }

if (-not $MzmlSourceDir) { $MzmlSourceDir = $preset.SourceDir }
if (-not $InputFasta)    { $InputFasta = if ([IO.Path]::IsPathRooted($preset.Fasta)) { $preset.Fasta } else { Join-Path $MzmlSourceDir $preset.Fasta } }
if (-not $MzmlNames)     { $MzmlNames = $preset.Files | ForEach-Object { "$_.$InputFormat" } }
if ($TrainFileIndex -lt 0) { $TrainFileIndex = $preset.TrainIndex }
if (-not $WorkDir) {
    $base = if ($env:CARAFESHARP_WORKDIR) { $env:CARAFESHARP_WORKDIR }
            elseif ($IsLinux) { '/mnt/d/test/carafesharp-runs' }
            else { 'D:\test\carafesharp-runs' }
    $WorkDir = Join-Path $base "$($Dataset.ToLowerInvariant())-$($Mode.ToLowerInvariant())"
}

# ---------------------------------------------------------------------------
# Osprey
# ---------------------------------------------------------------------------
if (-not $OspreyExe) { $OspreyExe = if ($env:OSPREYDEV_EXE) { $env:OSPREYDEV_EXE } else { Get-OspreyExe } }
if (-not (Test-Path $OspreyExe)) {
    throw "Osprey.exe not found at '$OspreyExe'. Pass -OspreyExe or set `$env:OSPREYDEV_EXE."
}
$ospreyHelp = (& $OspreyExe --help 2>&1) -join "`n"
if ($ospreyHelp -notmatch '--training-search') {
    throw ("$OspreyExe has no --training-search: this script runs the one command task by task with " +
           '--task, which needs an Osprey from master after PR 4c. Pass -OspreyExe.')
}
# Osprey reads Thermo .raw only when built with the vendor readers; without them the first search
# fails minutes in with "Thermo .raw reading requires the vendor SDK".
if (($MzmlNames | Where-Object { $_ -match '\.raw$' }) -and
    -not (Test-Path (Join-Path (Split-Path -Parent $OspreyExe) 'ThermoFisher.CommonCore.RawFileReader.dll'))) {
    throw ("$OspreyExe cannot read Thermo .raw: it was built without the vendor readers. Build Osprey with " +
           'ai/scripts/Osprey/Build-Osprey.ps1 -VendorReader, or pass -InputFormat mzML.')
}
$cudaLibrary = if ($IsWindows) { 'runtimes/win-x64/native/torch_cuda.dll' } else { 'runtimes/linux-x64/native/libtorch_cuda.so' }
$cudaBuild = Test-Path -LiteralPath (Join-Path (Split-Path -Parent $OspreyExe) $cudaLibrary)

if ($EntrapmentSource -eq 'natural') {
    if (-not $ForeignFasta) { throw '-EntrapmentSource natural needs -ForeignFasta (the foreign-species proteome).' }
    if (-not (Test-Path $ForeignFasta)) { throw "ForeignFasta not found: $ForeignFasta" }
}
if ($TrainingSearch -and $Mode -ne 'Tuned') { throw '-TrainingSearch needs -Mode Tuned (there is no training run to search).' }
# @() keeps a single run an array: indexing a lone string would take its first character.
$mzml = @($MzmlNames | ForEach-Object { Join-Path $MzmlSourceDir $_ })
$cacheDir = if ($CacheDir) { $CacheDir } else { Join-Path $WorkDir 'spectra-cache' }
# A run whose source is gone may be read from its spectra cache, as Osprey itself allows.
foreach ($m in $mzml) {
    $cached = Join-Path $cacheDir ([IO.Path]::GetFileNameWithoutExtension($m) + '.spectra.bin')
    if (-not (Test-Path $m) -and -not (Test-Path $cached)) { throw "Data file not found: $m (pass -MzmlSourceDir)" }
}
if (-not (Test-Path $InputFasta)) { throw "Input FASTA not found: $InputFasta" }
$trainMzml = $mzml[$TrainFileIndex]

Write-Host "`n--- Osprey one command: library from the FASTA, then the search ---" -ForegroundColor Cyan
[PSCustomObject][ordered]@{
    Dataset          = $Dataset
    Mode             = $Mode
    Task             = if ($Task) { "$Task$(if ($TrainingSearch) { ' (training search)' })" } else { '(all)' }
    EntrapmentSource = $EntrapmentSource
    WorkDir          = $WorkDir
    InputFasta       = $InputFasta
    MzmlSourceDir    = $MzmlSourceDir
    TrainingRun      = if ($Mode -eq 'Tuned') { $trainMzml } else { '(none)' }
    Osprey           = "$OspreyExe  ($(if ($cudaBuild) { 'CUDA libtorch' } else { 'CPU libtorch' }), --device $Device)"
    Resolution       = "$($preset.Resolution) / $($preset.FragTol) $($preset.FragUnit)"
} | Format-List
if ($Device -eq 'gpu' -and -not $cudaBuild) {
    Write-Warning 'Osprey is a CPU-libtorch build; --device gpu falls back to the CPU (fine-tuning takes hours). Build with Build-Osprey.ps1 -Torch cuda for the GPU.'
}
if ($Preflight) {
    Write-Host 'Preflight only - stopping before any work.' -ForegroundColor Yellow
    return
}

# ---------------------------------------------------------------------------
# The one command
# ---------------------------------------------------------------------------
# Carafe's library parameters as CarafeSharp's sections of Osprey's help name them. The ones Osprey
# decides are not given: the export's q-value (Carafe's --fdr), the XIC tolerances and refinement
# (--itol, --rf, ...), the format (blib) and the search engine.
$library = @(
    '--enzyme', '2', '--miss-c', '1', '--fix-mod', '1', '--var-mod', '0', '--max-var', '1', '--clip-n-m',
    '--min-length', '7', '--max-length', '35',
    '--min-pep-mz', $preset.MinPepMz, '--max-pep-mz', $preset.MaxPepMz,
    '--min-pep-charge', '2', '--max-pep-charge', $maxCharge,
    '--lf-frag-mz-min', '200', '--lf-frag-mz-max', '1960', '--lf-top-n-frag', '20',
    '--lf-min-n-frag', '2', '--lf-frag-n-min', '2',
    '--rt-model', $RtModel)
if ($preset.CarafeExtra) { $library += $preset.CarafeExtra }
$tuning = @('--cor', '0.8', '--n-ion-min', '2', '--c-ion-min', '2', '--nf', '4', '--min-n', '4', '--valid', '--tf', 'all')

New-Item -ItemType Directory -Force -Path (Join-Path $WorkDir 'FDRBench') | Out-Null
$osArgs = @('-i') + $mzml + @(
    '--fasta', $InputFasta,
    '-o', (Join-Path $WorkDir 'osprey.blib'), '--output-dir', $WorkDir, '--cache-dir', $cacheDir,
    '--device', $Device,
    '--resolution', $preset.Resolution,
    '--fragment-tolerance', $preset.FragTol, '--fragment-unit', $preset.FragUnit,
    '--run-fdr', '0.01', '--experiment-fdr', '0.01',
    '--fdr-level', 'precursor',
    '--shared-peptides', 'all', '--threads', "$Threads",
    '--fdrbench', (Join-Path $WorkDir 'FDRBench\FDRBench-Input.tsv')) + $library
if ($ProteinFdr) { $osArgs += @('--protein-fdr', $ProteinFdr) }
if ($Mode -eq 'Tuned') { $osArgs += @('--training-input', $trainMzml) + $tuning }
if ($EntrapmentSource -ne 'none') {
    $osArgs += '--entrapment'
    if ($EntrapmentRatio -ne 1.0) { $osArgs += "$EntrapmentRatio" }
    if ($EntrapmentSource -eq 'natural') { $osArgs += @('--entrapment-fasta', $ForeignFasta) }
}
if ($ModelDiagnostics) { $osArgs += '--model-diagnostics' }
if ($Task) { $osArgs = @('--task', $Task) + $osArgs }
if ($TrainingSearch) { $osArgs += '--training-search' }
if ($ExtraArgs) { $osArgs += $ExtraArgs }

Write-Host "`n=== [START] Osprey ===" -ForegroundColor Cyan
Write-Host "$OspreyExe $($osArgs -join ' ')" -ForegroundColor DarkGray
$sw = [System.Diagnostics.Stopwatch]::StartNew()
& $OspreyExe @osArgs
if ($LASTEXITCODE -ne 0) { throw "Osprey FAILED (exit $LASTEXITCODE)" }
$sw.Stop()
Write-Host "=== [DONE] Osprey ($([math]::Round($sw.Elapsed.TotalMinutes, 2)) min) ===" -ForegroundColor Green
Write-Host "`n[SUCCESS] Work dir: $WorkDir" -ForegroundColor Green
