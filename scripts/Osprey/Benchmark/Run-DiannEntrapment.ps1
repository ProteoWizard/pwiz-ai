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
    [int]$Threads = 16
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
if (-not $Model) { $Model = "D:\test\osprey-runs\diann-compare\$name\osprey-library\osprey.carafemodel" }
$fasta = Join-Path $DataDir $preset.Fasta
$runs = @($preset.Files | ForEach-Object { Join-Path $DataDir "$_.raw" })
$diannRuns = @($preset.Files | ForEach-Object { Join-Path $DataDir "$_.$($preset.DiannInput)" })
foreach ($path in @($fasta, $OspreyExe, $DiannExe, $Model, $EntrapmentFasta) + $runs + $diannRuns) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Not found: $path" }
}
if ($WorkDir -match '--') { throw "DIA-NN cuts a path at '--': choose a -WorkDir without it ($WorkDir)." }
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

$ospreyDir = Join-Path $WorkDir 'osprey'
$predicted = Join-Path $ospreyDir 'osprey.predicted.blib'
$peptideFasta = Join-Path $WorkDir 'peptides\target_entrapment_peptides.fasta'
$diannLibDir = Join-Path $WorkDir 'diann-library'
$diannSearchDir = Join-Path $WorkDir 'diann-search'

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
    Invoke-Step 'osprey' $OspreyExe (@('-i') + $runs + @(
        '--fasta', $fasta, '--model', $Model,
        '--entrapment', "$EntrapmentRatio", '--entrapment-fasta', $EntrapmentFasta,
        '-o', (Join-Path $ospreyDir 'osprey.blib'), '--cache-dir', (Join-Path $ospreyDir 'cache'),
        '--fdrbench', (Join-Path $ospreyDir 'FDRBench-Input.tsv'),
        '--log-file', (Join-Path $ospreyDir 'osprey.log'),
        '--enzyme', '2', '--miss-c', '1', '--minLength', '7', '--maxLength', '35', '--clip-n-m',
        '--fixMod', '1', '--varMod', '0', '--maxVar', '1',
        '--min-pep-mz', '400', '--max-pep-mz', '900', '--min-pep-charge', '2', '--max-pep-charge', '3',
        '--lf-frag-mz-min', '200', '--lf-frag-mz-max', '1960', '--lf-top-n-frag', '20',
        '--lf-min-n-frag', '2', '--lf-frag-n-min', '2', '--rt-model', 'chronologer', '--device', $Device,
        '--resolution', $preset.Resolution, '--fragment-tolerance', $preset.FragTol, '--fragment-unit', $preset.FragUnit,
        '--run-fdr', '0.01', '--experiment-fdr', '0.01', '--protein-fdr', '0.01',
        '--threads', "$Threads", '--timestamp')) $ospreyDir
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
        '--individual-mass-acc', '--individual-windows', '--reanalyse', '--rt-profiling') +
        $preset.DiannSearch + $digest) $diannSearchDir
}
