<#
.SYNOPSIS
    Time Osprey against DIA-NN on the Stellar or Astral test data, each tool building its own
    library from the FASTA, with library generation and search timed as separate processes.

.DESCRIPTION
    Four steps per dataset, run one at a time so no two compete for the machine:

        osprey-library   Osprey's one command (--fasta --training-input <middle run>) stopped after
                         PredictLibrary by OSPREY_STOP_AFTER_TASKS: predict a training library with
                         the pretrained models (AlphaPeptDeep MS2, Chronologer RT), search the middle
                         run with the training export, fine-tune both models on it, predict the final
                         library. Writes <step>\osprey.predicted.blib.
        osprey-search    Osprey searches every run with that library (-l), with a cache of its own,
                         so every run is read from the vendor file inside the timed search.
        diann-library    DIA-NN predicts a library from the same FASTA (--fasta-search --predictor
                         --gen-spec-lib, no runs).
        diann-search     DIA-NN searches every run with that library, with the flags of the March
                         2026 DIA-NN 2.3.2 timing run (example_test_data/astral/DIANN-Output),
                         plus on Stellar --no-ms1 --mass-acc-cal 900 for the
                         unit-resolution ion trap (Fields et al. 2026), reading the mzML: DIA-NN
                         cannot calibrate the Stellar .raw (see TODO-20261021_osprey_diann_timing.md).

    The digest is the same for both tools: trypsin without the P rule (CarafeSharp enzyme 2,
    DIA-NN K*,R*), 1 missed cleavage, length 7-35, N-terminal Met excision, carbamidomethyl C and
    no variable modifications, charge 2-3, precursor m/z 400-900, fragment m/z 200-1960. The
    tuning options are those of ai/scripts/CarafeSharp/Run-CarafeSharpWorkflow.ps1.

    Each step writes <WorkDir>\<step>\step.log (the tool's own output, timestamped by Osprey or
    DIA-NN) and appends its wall time to <WorkDir>\timing.tsv. Plot with plot_diann_comparison.py.

.PARAMETER Steps
    Comma-separated subset of osprey-library, osprey-search, diann-library, diann-search
    (default: all four, in that order). osprey-search needs osprey-library's output, diann-search
    diann-library's.

.PARAMETER LibraryMode
    tuned (default): osprey-library is the one command with --training-input <middle run>, as above.
    pretrained: the one command without --training-input, so the library is predicted once with the
    pretrained models (no tuning search, no fine-tune) and -LibraryTasks defaults to 1 (PredictLibrary).

.PARAMETER DataDir
    The dataset's folder of vendor files and FASTA. Default: $env:OSPREY_EXAMPLE_DATA_DIR\<dataset>,
    else D:\GitHub-Repo\maccoss\osprey\example_test_data\<dataset>.

.EXAMPLE
    pwsh -File ./ai/scripts/Osprey/Benchmark/Run-DiannComparison.ps1 -Dataset Stellar `
        -OspreyExe D:\test\osprey-runs\_bin\osprey-4885-9719d88da2-vendor\Osprey.exe

.NOTES
    Osprey must read Thermo .raw (Build-Osprey.ps1 -VendorReader) and have the one command with
    --training-input (#4885). Snapshot the exe first: the runs lock it for hours.
#>
#requires -Version 7
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [ValidateSet('Stellar', 'Astral')] [string]$Dataset,
    [string]$Steps = 'osprey-library,osprey-search,diann-library,diann-search',
    [string]$WorkDir,
    [string]$DataDir,
    [Parameter(Mandatory = $true)] [string]$OspreyExe,
    [string]$DiannExe = 'C:\DIA-NN\2.6.1\diann.exe',
    [int]$Threads = 16,
    # Where Osprey's one command predicts and tunes. gpu needs an Osprey built with
    # Build-Osprey.ps1 -Torch cuda; a CPU build falls back to the CPU with a warning.
    [ValidateSet('cpu', 'gpu')] [string]$Device = 'gpu',
    # Tasks the tuned one command runs through PredictLibrary: PredictTrainingLibrary, the tuning
    # search's four stages, TrainModel, PredictLibrary. The step checks the log's stop line.
    [int]$LibraryTasks = 7,
    # tuned: --training-input <middle run> (fine-tune, then predict). pretrained: predict with the
    # pretrained models only; -LibraryTasks then defaults to 1 (PredictLibrary).
    [ValidateSet('tuned', 'pretrained')] [string]$LibraryMode = 'tuned',
    # Steps that wait for a quiet machine before they start: total CPU below -QuietCpuPercent for
    # -QuietMinutes in a row. Between steps nothing of ours runs, so the total is everyone else's.
    # An idle i9-9900K reads 8-12% on this counter (system overhead the per-process times miss).
    [string]$QuietSteps = 'osprey-library,osprey-search,diann-library,diann-search',
    [double]$QuietCpuPercent = 15,
    [double]$QuietMinutes = 2
)

$ErrorActionPreference = 'Stop'

$presets = @{
    Stellar = @{
        Fasta      = 'hela-filtered.fasta'
        Files      = @('Ste-2024-12-02_HeLa_4mz_sDIA_400-900_20', 'Ste-2024-12-02_HeLa_4mz_sDIA_400-900_21',
                       'Ste-2024-12-02_HeLa_4mz_sDIA_400-900_22')
        Resolution = 'unit'
        FragTol    = '0.4'
        FragUnit   = 'mz'
        # Unit-resolution linear ion trap, per Fields et al. 2026 (Stellar DIA-NN design of
        # experiments): no MS1 scoring, and calibration starting from 900 ppm instead of DIA-NN's
        # 100 ppm. The MS2 accuracy itself is left automatic, so DIA-NN calibrates it per run.
        DiannSearch = @('--no-ms1', '--mass-acc-cal', '900')
        # DIA-NN reads the Stellar .raw without error but cannot calibrate it (20 ppm, 0 IDs, in
        # 2.2.0 and 2.3.2); the msconvert mzML calibrates to ~350 ppm. Osprey still reads the .raw.
        DiannInput  = 'mzML'
    }
    Astral = @{
        Fasta      = 'uniprot_human_jan2025_yeastENO1_contam_ADpeps.fasta'
        Files      = @('Ast-2024-12-05_HeLa_3mzDIA_6mIIT_400-900_49', 'Ast-2024-12-05_HeLa_3mzDIA_6mIIT_400-900_55',
                       'Ast-2024-12-05_HeLa_3mzDIA_6mIIT_400-900_60')
        Resolution = 'hram'
        FragTol    = '20'
        FragUnit   = 'ppm'
        DiannSearch = @()
        DiannInput  = 'raw'
    }
}
$preset = $presets[$Dataset]

if (-not $DataDir) {
    $root = if ($env:OSPREY_EXAMPLE_DATA_DIR) { $env:OSPREY_EXAMPLE_DATA_DIR }
            else { 'D:\GitHub-Repo\maccoss\osprey\example_test_data' }
    $DataDir = Join-Path $root $Dataset.ToLowerInvariant()
}
if (-not $WorkDir) {
    $WorkDir = Join-Path 'D:\test\osprey-runs\diann-compare' $Dataset.ToLowerInvariant()
}
$fasta = Join-Path $DataDir $preset.Fasta
$runs = @($preset.Files | ForEach-Object { Join-Path $DataDir "$_.raw" })
$diannRuns = @($preset.Files | ForEach-Object { Join-Path $DataDir "$_.$($preset.DiannInput)" })
$middleRun = $runs[1]
# DIA-NN and its inputs are required only when a diann step is requested.
$required = @($fasta, $OspreyExe) + $runs
if ($Steps -match 'diann') { $required += @($DiannExe) + $diannRuns }
foreach ($path in $required) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Not found: $path" }
}

$stepList = $Steps -split '\s*,\s*' | Where-Object { $_ }
$validSteps = @('osprey-library', 'osprey-search', 'diann-library', 'diann-search')
foreach ($s in $stepList) {
    if ($validSteps -notcontains $s) { throw "Unknown step '$s' (valid: $($validSteps -join ', '))." }
}
$quietList = $QuietSteps -split '\s*,\s*' | Where-Object { $_ }
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
$timingFile = Join-Path $WorkDir 'timing.tsv'
if (-not (Test-Path $timingFile)) {
    "step`tstart`tend`twall_s`texit_code`texe`tother_cpu_mean`tother_cpu_max" | Set-Content -Path $timingFile -Encoding utf8
}

# The digest, as CarafeSharp's options (Osprey's Library Digest and Library Prediction sections)
# and as DIA-NN's.
$ospreyDigest = @(
    '--enzyme', '2', '--miss-c', '1', '--minLength', '7', '--maxLength', '35', '--clip-n-m',
    '--fixMod', '1', '--varMod', '0', '--maxVar', '1',
    '--min-pep-mz', '400', '--max-pep-mz', '900', '--min-pep-charge', '2', '--max-pep-charge', '3',
    '--lf-frag-mz-min', '200', '--lf-frag-mz-max', '1960', '--lf-top-n-frag', '20',
    '--lf-min-n-frag', '2', '--lf-frag-n-min', '2', '--rt-model', 'chronologer', '--device', $Device)
$ospreyTuning = @('--tf', 'all', '--cor', '0.8', '--n-ion-min', '2', '--c-ion-min', '2',
    '--nf', '4', '--min-n', '4', '--valid')
$ospreySearch = @(
    '--resolution', $preset.Resolution,
    '--fragment-tolerance', $preset.FragTol, '--fragment-unit', $preset.FragUnit,
    '--run-fdr', '0.01', '--experiment-fdr', '0.01', '--threads', "$Threads", '--timestamp')
$diannDigest = @(
    '--fasta', $fasta, '--met-excision', '--cut', 'K*,R*', '--missed-cleavages', '1',
    '--min-pep-len', '7', '--max-pep-len', '35', '--unimod4',
    '--min-pr-mz', '400', '--max-pr-mz', '900', '--min-pr-charge', '2', '--max-pr-charge', '3',
    '--min-fr-mz', '200', '--max-fr-mz', '1960', '--threads', "$Threads", '--verbose', '1')

function Wait-QuietMachine {
    param([string]$Name)
    $needed = [int][math]::Ceiling($QuietMinutes * 60 / 15)
    $quiet = 0
    $waitStart = Get-Date
    $lastReport = $waitStart
    Write-Host ("Waiting for a quiet machine before {0}: total CPU under {1}% for {2} min" -f $Name, $QuietCpuPercent, $QuietMinutes)
    while ($quiet -lt $needed) {
        $cpu = (Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 15 -MaxSamples 1).CounterSamples[0].CookedValue
        $quiet = if ($cpu -lt $QuietCpuPercent) { $quiet + 1 } else { 0 }
        if (((Get-Date) - $lastReport).TotalMinutes -ge 5) {
            $busy = Get-BusyProcesses 5 | ForEach-Object { '{0} {1:F0}%' -f $_.Name, $_.Pct }
            Write-Host ("  {0:HH:mm} still busy: CPU {1:F0}% ({2})" -f (Get-Date), $cpu, ($busy -join ', '))
            $lastReport = Get-Date
        }
    }
    Write-Host ("Quiet after {0:F1} min" -f ((Get-Date) - $waitStart).TotalMinutes)
}

function Get-BusyProcesses {
    param([int]$Seconds)
    $before = @{}
    Get-Process | Where-Object { $_.CPU } | ForEach-Object { $before[$_.Id] = $_.CPU }
    Start-Sleep -Seconds $Seconds
    $cores = [Environment]::ProcessorCount
    Get-Process | Where-Object { $_.CPU -and $before.ContainsKey($_.Id) } | ForEach-Object {
        [pscustomobject]@{ Name = $_.Name; Id = $_.Id; Pct = 100 * ($_.CPU - $before[$_.Id]) / $Seconds / $cores }
    } | Where-Object { $_.Pct -ge 1 } | Sort-Object Pct -Descending
}

# Samples, every 30 s while a step runs, the CPU of every process other than the tool's, so a timing
# can be checked for contention afterwards (<step>\contention.tsv).
$contentionSampler = {
    param([string]$Path, [string]$ToolName)
    "time`tother_cpu_pct`ttop" | Set-Content -Path $Path -Encoding utf8
    $cores = [Environment]::ProcessorCount
    while ($true) {
        $before = @{}
        Get-Process | Where-Object { $_.CPU } | ForEach-Object { $before[$_.Id] = $_.CPU }
        Start-Sleep -Seconds 30
        $others = Get-Process | Where-Object { $_.CPU -and $before.ContainsKey($_.Id) -and $_.Name -ne $ToolName } |
            ForEach-Object { [pscustomobject]@{ Name = $_.Name; Pct = 100 * ($_.CPU - $before[$_.Id]) / 30 / $cores } } |
            Sort-Object Pct -Descending
        $total = ($others | Measure-Object Pct -Sum).Sum
        $top = ($others | Select-Object -First 3 | ForEach-Object { '{0}:{1:F0}' -f $_.Name, $_.Pct }) -join ' '
        "{0:HH:mm:ss}`t{1:F1}`t{2}" -f (Get-Date), $total, $top | Add-Content -Path $Path -Encoding utf8
    }
}

function Invoke-TimedStep {
    param([string]$Name, [string]$Exe, [string[]]$Arguments, [hashtable]$Environment = @{})
    if ($quietList -contains $Name) { Wait-QuietMachine $Name }
    $stepDir = Join-Path $WorkDir $Name
    if (Test-Path $stepDir) {
        # Never reuse a step's folder: a re-run must time a cold step, not skip current outputs.
        $kept = '{0}-{1}' -f $stepDir, (Get-Item $stepDir).LastWriteTime.ToString('yyyyMMdd_HHmmss')
        Move-Item -LiteralPath $stepDir -Destination $kept
        Write-Host "Moved the earlier $Name to $kept"
    }
    New-Item -ItemType Directory -Force -Path $stepDir | Out-Null
    $log = Join-Path $stepDir 'step.log'
    $resolved = $Arguments | ForEach-Object { $_.Replace('{step}', $stepDir) }
    "$Exe $($resolved -join ' ')" | Set-Content -Path (Join-Path $stepDir 'command.txt') -Encoding utf8
    Write-Host "`n=== $Dataset $Name ===" -ForegroundColor Cyan
    Write-Host "$Exe $($resolved -join ' ')"
    foreach ($key in $Environment.Keys) { Set-Item -Path "Env:$key" -Value $Environment[$key] }
    $contention = Join-Path $stepDir 'contention.tsv'
    $sampler = Start-Job -ScriptBlock $contentionSampler -ArgumentList $contention, ([IO.Path]::GetFileNameWithoutExtension($Exe))
    $start = Get-Date
    try {
        & $Exe @resolved *>&1 | Tee-Object -FilePath $log | Out-Null
        $code = $LASTEXITCODE
    } finally {
        $end = Get-Date
        Stop-Job $sampler
        Remove-Job $sampler -Force
        foreach ($key in $Environment.Keys) { Remove-Item -Path "Env:$key" -ErrorAction SilentlyContinue }
    }
    $wall = ($end - $start).TotalSeconds
    $samples = @(Import-Csv -Path $contention -Delimiter "`t" -ErrorAction SilentlyContinue)
    $otherCpu = if ($samples.Count) { ($samples | Measure-Object { [double]$_.other_cpu_pct } -Average).Average } else { [double]::NaN }
    $otherMax = if ($samples.Count) { ($samples | Measure-Object { [double]$_.other_cpu_pct } -Maximum).Maximum } else { [double]::NaN }
    "{0}`t{1:o}`t{2:o}`t{3:F1}`t{4}`t{5}`t{6:F1}`t{7:F1}" -f $Name, $start, $end, $wall, $code, $Exe, $otherCpu, $otherMax |
        Add-Content -Path $timingFile -Encoding utf8
    Write-Host ("{0}: {1:F1} min, exit {2}; other processes' CPU mean {3:F1}%, max {4:F1}%" -f $Name, ($wall / 60), $code, $otherCpu, $otherMax)
    if ($code -ne 0) { throw "$Name failed (exit $code); see $log" }
    return $stepDir
}

$ospreyLibrary = Join-Path $WorkDir 'osprey-library\osprey.predicted.blib'
$diannLibrary = Join-Path $WorkDir 'diann-library\library.predicted.speclib'

foreach ($step in $validSteps | Where-Object { $stepList -contains $_ }) {
    switch ($step) {
        'osprey-library' {
            $tuneArgs = if ($LibraryMode -eq 'tuned') { @('--training-input', $middleRun) + $ospreyTuning } else { @() }
            $tasks = if ($LibraryMode -eq 'pretrained' -and -not $PSBoundParameters.ContainsKey('LibraryTasks')) { 1 } else { $LibraryTasks }
            $dir = Invoke-TimedStep $step $OspreyExe (@('-i') + $runs + @(
                '--fasta', $fasta,
                '-o', '{step}\osprey.blib', '--cache-dir', '{step}\cache',
                '--log-file', '{step}\osprey.log') + $ospreyDigest + $tuneArgs + $ospreySearch) `
                -Environment @{ OSPREY_STOP_AFTER_TASKS = "$tasks" }
            $stop = Select-String -Path (Join-Path $dir 'osprey.log') -Pattern '\[TASK\] stop:after' |
                Select-Object -Last 1
            if (-not $stop -or $stop.Line -notmatch 'PredictLibrary') {
                throw "The library step did not stop after PredictLibrary ($($stop.Line)); adjust -LibraryTasks."
            }
            if (-not (Test-Path $ospreyLibrary)) { throw "No library at $ospreyLibrary" }
        }
        'osprey-search' {
            if (-not (Test-Path $ospreyLibrary)) { throw "Run osprey-library first: no $ospreyLibrary" }
            Invoke-TimedStep $step $OspreyExe (@('-i') + $runs + @(
                '-l', $ospreyLibrary, '--decoys-in-library',
                '-o', '{step}\osprey.blib', '--output-dir', '{step}', '--cache-dir', '{step}\cache',
                '--log-file', '{step}\osprey.log') + $ospreySearch) | Out-Null
        }
        'diann-library' {
            Invoke-TimedStep $step $DiannExe (@(
                '--fasta-search', '--predictor', '--gen-spec-lib',
                '--out-lib', '{step}\library.parquet') + $diannDigest) | Out-Null
            if (-not (Test-Path $diannLibrary)) {
                $found = Get-ChildItem (Join-Path $WorkDir 'diann-library') -Filter '*.speclib' | Select-Object -First 1
                if (-not $found) { throw "DIA-NN wrote no .speclib in $(Join-Path $WorkDir 'diann-library')" }
                $script:diannLibrary = $found.FullName
            }
        }
        'diann-search' {
            if (-not (Test-Path $diannLibrary)) {
                $found = Get-ChildItem (Join-Path $WorkDir 'diann-library') -Filter '*.speclib' -ErrorAction SilentlyContinue |
                    Select-Object -First 1
                if (-not $found) { throw 'Run diann-library first: no predicted .speclib' }
                $diannLibrary = $found.FullName
            }
            $fileArgs = $diannRuns | ForEach-Object { @('--f', $_) }
            Invoke-TimedStep $step $DiannExe ($fileArgs + @(
                # --temp: DIA-NN writes its .quant files beside the runs otherwise, into the data folder.
                '--lib', $diannLibrary, '--temp', '{step}', '--out', '{step}\report.parquet', '--qvalue', '0.01', '--matrices',
                '--out-lib', '{step}\report-lib.parquet', '--gen-spec-lib', '--reannotate',
                '--individual-mass-acc', '--individual-windows', '--no-prot-inf', '--reanalyse',
                '--rt-profiling') + $preset.DiannSearch + $diannDigest) | Out-Null
        }
    }
}
Write-Host "`nTimes: $timingFile"
