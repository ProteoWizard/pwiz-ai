<#
.SYNOPSIS
    Search the Stellar or Astral test data with Osprey and DIA-NN against the same target +
    natural-entrapment peptides, for IDs at matched entrapment FDP (precursor and protein level).

.DESCRIPTION
    Four steps per dataset, run one at a time:

        osprey          Osprey's one command with the fine-tuned model Run-DiannComparison.ps1 saved
                        (--model, so tuning never sees entrapment), --entrapment 1.0 drawn mass-matched
                        from a foreign proteome (--entrapment-fasta), --protein-fdr, and the FDRBench
                        export (every scored target with its experiment q-value).
        peptides        The predicted library's targets and entrapment peptides (not its decoys) as a
                        peptide FASTA, one entry per peptide and protein accession, for DIA-NN.
        diann-library   DIA-NN predicts from that peptide FASTA with --cut "" (no digest), so both tools
                        search the same peptides: r = entrapment / target is the same.
        diann-search    DIA-NN searches with protein inference on (--pg-level 0, accessions) and
                        --qvalue 0.05, so the q-value range reaches past 1% for matched FDP. Stellar reads
                        the mzML with --no-ms1 --mass-acc-cal 900 (see TODO-20261021_osprey_diann_timing.md).

    Osprey names an entrapment peptide's protein after its paired target's, with FDRBench's _p_target
    suffix (sp|P55011_p_target|S12A2_HUMAN_p_target), whatever proteome the peptide was drawn from;
    -EntrapmentSuffix recognizes them. The peptide FASTA repeats an accession once per peptide, so
    DIA-NN needs --duplicate-proteins (without it, it keeps one peptide per accession). Analyze with
    plot_entrapment.py.

.EXAMPLE
    pwsh -File ./ai/scripts/Osprey/Benchmark/Run-DiannEntrapment.ps1 -Dataset Stellar `
        -OspreyExe D:\test\osprey-runs\_bin\osprey-4885-9719d88da2-vendor-cuda\Osprey.exe
#>
#requires -Version 7
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [ValidateSet('Stellar', 'Astral')] [string]$Dataset,
    [string]$Steps = 'osprey,peptides,diann-library,diann-search',
    [string]$WorkDir,
    [string]$DataDir,
    [Parameter(Mandatory = $true)] [string]$OspreyExe,
    [string]$DiannExe = 'C:\DIA-NN\2.6.1\diann.exe',
    # The fine-tuned model of the timing comparison: the entrapment library is predicted with it.
    [string]$Model,
    [string]$EntrapmentFasta = 'D:\UW\MacCoss Lab - Documents\Mike MacCoss\Fasta and Libraries\uniprot_arabidopsis_feb2023.fasta',
    [string]$EntrapmentSuffix = '_p_target',
    [double]$EntrapmentRatio = 1.0,
    [ValidateSet('cpu', 'gpu')] [string]$Device = 'gpu',
    [int]$Threads = 16,
    # Which FDRBench exports the Osprey steps write: 1 (pre-compaction first pass), 2 (second pass)
    # or both (FDRBench-Input.pass1.tsv and FDRBench-Input.pass2.tsv).
    [ValidateSet('1', '2', 'both')] [string]$FdrBenchPass = 'both',
    # The 'osprey-arm' step: Osprey again on the 'osprey' step's predicted library and spectra cache,
    # into <WorkDir>\<Arm>, with -OspreyExtraArgs added to the command line (whitespace-separated, e.g.
    # '--reconciliation-compaction-fdr 0.05') and -OspreyEnv set for the run ('NAME=value;NAME=value',
    # e.g. 'OSPREY_PASS2_QVALUE=transfer'). One arm per call, so a sweep is a loop over calls.
    [string]$Arm = 'osprey-arm',
    # The library an arm searches, when not the 'osprey' step's predicted one: e.g. a copy with the
    # entrapment rows filed under their paired targets' accessions, so protein-informed FDR can reach them.
    [string]$ArmLibrary,
    [string]$OspreyExtraArgs = '',
    [string]$OspreyEnv = '',
    # The 'osprey' step into another folder (<WorkDir>\<OspreyStepDir>), with -TopFragments library fragments per
    # precursor (Osprey's --lf-top-n-frag; DIA-NN keeps 12), and with -LibraryOnly stopped after PredictLibrary.
    # Every Osprey step reads and writes the one spectra cache, <WorkDir>\osprey\cache.
    [string]$OspreyStepDir = 'osprey',
    [int]$TopFragments = 20,
    [switch]$LibraryOnly,
    # The 'diann-search' step without --reanalyse (no MBR second pass), into diann-search-nombr.
    [switch]$DiannNoMbr,
    # The file type DIA-NN searches, when not the preset's (Stellar: mzML; Astral: raw). A search of the other
    # type goes into diann-search-<type>, so it sits beside the preset's diann-search.
    [ValidateSet('', 'raw', 'mzML')] [string]$DiannInput = ''
)

$ErrorActionPreference = 'Stop'

$presets = @{
    Stellar = @{
        Fasta = 'hela-filtered.fasta'
        Files = @('Ste-2024-12-02_HeLa_4mz_sDIA_400-900_20', 'Ste-2024-12-02_HeLa_4mz_sDIA_400-900_21',
                  'Ste-2024-12-02_HeLa_4mz_sDIA_400-900_22')
        Resolution = 'unit'; FragTol = '0.4'; FragUnit = 'mz'
        DiannSearch = @('--no-ms1', '--mass-acc-cal', '900'); DiannInput = 'mzML'
    }
    Astral = @{
        Fasta = 'uniprot_human_jan2025_yeastENO1_contam_ADpeps.fasta'
        Files = @('Ast-2024-12-05_HeLa_3mzDIA_6mIIT_400-900_49', 'Ast-2024-12-05_HeLa_3mzDIA_6mIIT_400-900_55',
                  'Ast-2024-12-05_HeLa_3mzDIA_6mIIT_400-900_60')
        Resolution = 'hram'; FragTol = '20'; FragUnit = 'ppm'
        DiannSearch = @(); DiannInput = 'raw'
    }
}
$preset = $presets[$Dataset]
$name = $Dataset.ToLowerInvariant()
if (-not $DataDir) {
    $root = if ($env:OSPREY_EXAMPLE_DATA_DIR) { $env:OSPREY_EXAMPLE_DATA_DIR } else { 'D:\GitHub-Repo\maccoss\osprey\example_test_data' }
    $DataDir = Join-Path $root $name
}
if (-not $WorkDir) { $WorkDir = Join-Path 'D:\test\osprey-runs\diann-entrapment' $name }
# Osprey writes the tuned model as <output stem>.model.zip (#4895; .carafemodel before it).
if (-not $Model) { $Model = "D:\test\osprey-runs\diann-compare\$name\osprey-library\osprey.model.zip" }
$fasta = Join-Path $DataDir $preset.Fasta
$runs = @($preset.Files | ForEach-Object { Join-Path $DataDir "$_.raw" })
$diannType = if ($DiannInput) { $DiannInput } else { $preset.DiannInput }
$diannRuns = @($preset.Files | ForEach-Object { Join-Path $DataDir "$_.$diannType" })
foreach ($path in @($fasta, $OspreyExe, $DiannExe, $Model, $EntrapmentFasta) + $runs + $diannRuns) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Not found: $path" }
}
if ($WorkDir -match '--') { throw "DIA-NN cuts a path at '--': choose a -WorkDir without it ($WorkDir)." }
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

$cacheDir = Join-Path $WorkDir 'osprey\cache'
# The arms, the gbdt step and the swap read the 'osprey' step's library; -OspreyStepDir moves only the osprey step.
$ospreyDir = Join-Path $WorkDir 'osprey'
$predicted = Join-Path $ospreyDir 'osprey.predicted.blib'
$stepDir = Join-Path $WorkDir $OspreyStepDir
$peptideFasta = Join-Path $WorkDir 'peptides\target_entrapment_peptides.fasta'
$diannLibDir = Join-Path $WorkDir 'diann-library'
$diannSearchName = if ($DiannNoMbr) { 'diann-search-nombr' } else { 'diann-search' }
if ($diannType -ne $preset.DiannInput) { $diannSearchName += '-' + $diannType.ToLowerInvariant() }
$diannSearchDir = Join-Path $WorkDir $diannSearchName

function Invoke-Step {
    param([string]$Name, [string]$Exe, [string[]]$Arguments, [string]$Dir)
    if (Test-Path $Dir) {
        $kept = '{0}-{1}' -f $Dir, (Get-Item $Dir).LastWriteTime.ToString('yyyyMMdd_HHmmss')
        Move-Item -LiteralPath $Dir -Destination $kept
        Write-Host "Moved the earlier $Name to $kept"
    }
    New-Item -ItemType Directory -Force -Path $Dir | Out-Null
    "$Exe $($Arguments -join ' ')" | Set-Content -Path (Join-Path $Dir 'command.txt') -Encoding utf8
    Write-Host "`n=== $Dataset $Name ===" -ForegroundColor Cyan
    $start = Get-Date
    & $Exe @Arguments *>&1 | Tee-Object -FilePath (Join-Path $Dir 'step.log') | Out-Null
    $code = $LASTEXITCODE
    Write-Host ("{0}: {1:F1} min, exit {2}" -f $Name, ((Get-Date) - $start).TotalMinutes, $code)
    if ($code -ne 0) { throw "$Name failed (exit $code); see $(Join-Path $Dir 'step.log')" }
}

$digest = @('--min-pr-mz', '400', '--max-pr-mz', '900', '--min-pr-charge', '2', '--max-pr-charge', '3',
    '--min-fr-mz', '200', '--max-fr-mz', '1960', '--min-pep-len', '7', '--max-pep-len', '35', '--unimod4',
    '--threads', "$Threads", '--verbose', '1')
$stepList = $Steps -split '\s*,\s*'

if ($stepList -contains 'osprey') {
    $exports = if ($LibraryOnly) { @() } else {
        @('--fdrbench', (Join-Path $stepDir 'FDRBench-Input.tsv'), '--fdrbench-pass', $FdrBenchPass, '--model-diagnostics') }
    # -LibraryOnly: the one command's first task is PredictLibrary when the model is given (--model).
    if ($LibraryOnly) { $env:OSPREY_STOP_AFTER_TASKS = '1' }
    try {
        Invoke-Step $OspreyStepDir $OspreyExe (@('-i') + $runs + @(
            '--fasta', $fasta, '--model', $Model,
            '--entrapment', "$EntrapmentRatio", '--entrapment-fasta', $EntrapmentFasta,
            # --output-dir: without it the per-run artifacts (calibration, scores parquet) land beside the
            # runs, in the shared test-data folder.
            '-o', (Join-Path $stepDir 'osprey.blib'), '--output-dir', $stepDir, '--cache-dir', $cacheDir) + $exports + @(
            '--log-file', (Join-Path $stepDir 'osprey.log'),
            '--enzyme', '2', '--miss-c', '1', '--minLength', '7', '--maxLength', '35', '--clip-n-m',
            '--fixMod', '1', '--varMod', '0', '--maxVar', '1',
            '--min-pep-mz', '400', '--max-pep-mz', '900', '--min-pep-charge', '2', '--max-pep-charge', '3',
            '--lf-frag-mz-min', '200', '--lf-frag-mz-max', '1960', '--lf-top-n-frag', "$TopFragments",
            '--lf-min-n-frag', '2', '--lf-frag-n-min', '2', '--rt-model', 'chronologer', '--device', $Device,
            '--resolution', $preset.Resolution, '--fragment-tolerance', $preset.FragTol, '--fragment-unit', $preset.FragUnit,
            '--run-fdr', '0.01', '--experiment-fdr', '0.01', '--protein-fdr', '0.01',
            '--threads', "$Threads", '--timestamp')) $stepDir
    } finally {
        if ($LibraryOnly) { Remove-Item Env:OSPREY_STOP_AFTER_TASKS -ErrorAction SilentlyContinue }
    }
}

# Osprey again on the 'osprey' step's predicted library (-l; its DecoyPairs pair the decoys), with
# gradient-boosted trees in place of the linear SVM (OSPREY_FDR_MODEL=gbdt): only the classifier differs.
if ($stepList -contains 'osprey-gbdt') {
    if (-not (Test-Path $predicted)) { throw "Run the 'osprey' step first: no $predicted" }
    $gbdtDir = Join-Path $WorkDir 'osprey-gbdt'
    $env:OSPREY_FDR_MODEL = 'gbdt'
    try {
        Invoke-Step 'osprey-gbdt' $OspreyExe (@('-i') + $runs + @(
            '-l', $predicted, '--decoys-in-library',
            '-o', (Join-Path $gbdtDir 'osprey.blib'), '--output-dir', $gbdtDir,
            '--cache-dir', $cacheDir,
            '--fdrbench', (Join-Path $gbdtDir 'FDRBench-Input.tsv'), '--log-file', (Join-Path $gbdtDir 'osprey.log'),
            '--resolution', $preset.Resolution, '--fragment-tolerance', $preset.FragTol, '--fragment-unit', $preset.FragUnit,
            '--run-fdr', '0.01', '--experiment-fdr', '0.01', '--protein-fdr', '0.01',
            '--threads', "$Threads", '--timestamp')) $gbdtDir
    } finally {
        Remove-Item Env:OSPREY_FDR_MODEL -ErrorAction SilentlyContinue
    }
}

# Osprey again on the 'osprey' step's predicted library and spectra cache, with one setting changed
# (-OspreyExtraArgs, -OspreyEnv): a compaction gate, a pass-2 q-value mode, a per-run export. The
# library is the same file, so the arms differ from the 'osprey' step only by what was changed and by
# reading the library with -l instead of predicting it.
if ($stepList -contains 'osprey-arm') {
    $armLib = if ($ArmLibrary) { $ArmLibrary } else { $predicted }
    if (-not (Test-Path $armLib)) { throw "No library for the arm: $armLib (run the 'osprey' step first)" }
    $armDir = Join-Path $WorkDir $Arm
    $extra = @($OspreyExtraArgs -split '\s+' | Where-Object { $_ })
    $envPairs = @($OspreyEnv -split ';' | Where-Object { $_ } | ForEach-Object {
        $kv = $_ -split '=', 2
        if ($kv.Count -ne 2) { throw "-OspreyEnv entry '$_' is not NAME=value" }
        , $kv
    })
    foreach ($kv in $envPairs) { Set-Item -Path "Env:$($kv[0])" -Value $kv[1] }
    try {
        Invoke-Step $Arm $OspreyExe (@('-i') + $runs + @(
            '-l', $armLib, '--decoys-in-library',
            '-o', (Join-Path $armDir 'osprey.blib'), '--output-dir', $armDir,
            '--cache-dir', $cacheDir,
            '--fdrbench', (Join-Path $armDir 'FDRBench-Input.tsv'), '--fdrbench-pass', $FdrBenchPass,
            '--log-file', (Join-Path $armDir 'osprey.log'),
            '--resolution', $preset.Resolution, '--fragment-tolerance', $preset.FragTol, '--fragment-unit', $preset.FragUnit,
            '--run-fdr', '0.01', '--experiment-fdr', '0.01', '--protein-fdr', '0.01',
            '--threads', "$Threads", '--timestamp') + $extra) $armDir
    } finally {
        foreach ($kv in $envPairs) { Remove-Item -Path "Env:$($kv[0])" -ErrorAction SilentlyContinue }
    }
    "Library: $armLib`nOspreyExtraArgs: $OspreyExtraArgs`nOspreyEnv: $OspreyEnv" | Set-Content -Path (Join-Path $armDir 'arm.txt') -Encoding utf8
}

if ($stepList -contains 'peptides') {
    $dir = Split-Path $peptideFasta
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $script = Join-Path $PSScriptRoot 'library_peptide_fasta.py'
    python $script $predicted $peptideFasta $EntrapmentSuffix
    if ($LASTEXITCODE -ne 0) { throw "library_peptide_fasta.py failed" }
}

if ($stepList -contains 'diann-library') {
    Invoke-Step 'diann-library' $DiannExe (@(
        '--fasta', $peptideFasta, '--cut', '', '--duplicate-proteins', '--fasta-search', '--predictor', '--gen-spec-lib',
        '--out-lib', (Join-Path $diannLibDir 'library.parquet')) + $digest) $diannLibDir
}

if ($stepList -contains 'diann-search') {
    $lib = Get-ChildItem $diannLibDir -Filter '*.predicted.speclib' | Select-Object -First 1
    if (-not $lib) { throw "No predicted .speclib in $diannLibDir" }
    $fileArgs = $diannRuns | ForEach-Object { @('--f', $_) }
    Invoke-Step 'diann-search' $DiannExe ($fileArgs + @(
        '--lib', $lib.FullName, '--temp', $diannSearchDir, '--out', (Join-Path $diannSearchDir 'report.parquet'),
        '--qvalue', '0.05', '--matrices', '--pg-level', '0', '--fasta', $peptideFasta, '--cut', '', '--duplicate-proteins',
        '--individual-mass-acc', '--individual-windows') + @(if (-not $DiannNoMbr) { '--reanalyse' }) + @('--rt-profiling') +
        $preset.DiannSearch + $digest) $diannSearchDir
}

# --- Library swap: Osprey searches DIA-NN's predictions for the same peptides --------------------
# Every peptide of Osprey's library - targets, entrapment and decoys - predicted by DIA-NN's predictor,
# exported, and searched by Osprey with the 'osprey' step's settings, spectra cache and pairing manifest.
# The decoys are predicted, as in Osprey's own library (DIA-NN's own searches derive decoys from their
# targets' spectra instead), so only the predictor differs - and DIA-NN keeps 12 fragments a precursor
# where Osprey's library keeps 20.
$swapPeptides = Join-Path $WorkDir 'swap-peptides'
$swapLibrary = Join-Path $WorkDir 'swap-library'
$swapExport = Join-Path $WorkDir 'swap-export'
$swapOsprey = Join-Path $WorkDir 'swap-osprey'
$swapTool = Join-Path $PSScriptRoot 'diann_library_swap.py'

if ($stepList -contains 'swap-fasta') {
    New-Item -ItemType Directory -Force -Path $swapPeptides | Out-Null
    python $swapTool fasta $predicted (Join-Path $swapPeptides 'all_peptides.fasta') (Join-Path $swapPeptides 'peptide_map.tsv')
    if ($LASTEXITCODE -ne 0) { throw 'diann_library_swap.py fasta failed' }
}

if ($stepList -contains 'swap-library') {
    Invoke-Step 'swap-library' $DiannExe (@(
        '--fasta', (Join-Path $swapPeptides 'all_peptides.fasta'), '--cut', '', '--fasta-search', '--predictor',
        '--gen-spec-lib', '--out-lib', (Join-Path $swapLibrary 'library.parquet')) + $digest) $swapLibrary
}

if ($stepList -contains 'swap-convert') {
    $lib = Get-ChildItem $swapLibrary -Filter '*.predicted.speclib' | Select-Object -First 1
    if (-not $lib) { throw "No predicted .speclib in $swapLibrary" }
    Invoke-Step 'swap-export' $DiannExe @('--lib', $lib.FullName, '--gen-spec-lib',
        '--out-lib', (Join-Path $swapExport 'library.parquet'), '--threads', "$Threads") $swapExport
    python $swapTool convert (Join-Path $swapExport 'library.parquet') (Join-Path $swapPeptides 'peptide_map.tsv') `
        (Join-Path $swapExport 'diann_predicted.tsv')
    if ($LASTEXITCODE -ne 0) { throw 'diann_library_swap.py convert failed' }
}

if ($stepList -contains 'swap-osprey') {
    Invoke-Step 'swap-osprey' $OspreyExe (@('-i') + $runs + @(
        '-l', (Join-Path $swapExport 'diann_predicted.tsv'), '--decoys-in-library',
        '--decoy-pairing-manifest', (Join-Path $ospreyDir 'osprey.predicted\pairing.tsv'),
        '-o', (Join-Path $swapOsprey 'osprey.blib'), '--output-dir', $swapOsprey,
        '--cache-dir', $cacheDir,
        '--fdrbench', (Join-Path $swapOsprey 'FDRBench-Input.tsv'), '--fdrbench-pass', $FdrBenchPass,
        '--log-file', (Join-Path $swapOsprey 'osprey.log'),
        '--resolution', $preset.Resolution, '--fragment-tolerance', $preset.FragTol, '--fragment-unit', $preset.FragUnit,
        '--run-fdr', '0.01', '--experiment-fdr', '0.01', '--protein-fdr', '0.01',
        '--threads', "$Threads", '--timestamp')) $swapOsprey
}
