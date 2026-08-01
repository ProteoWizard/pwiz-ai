<#
.SYNOPSIS
    Build an Osprey spectral library end to end with Carafe: digest a protein
    FASTA, predict a generic library, search a training run, fine-tune on the
    result, and predict the final library. Optionally replace the shuffle
    entrapment with matched foreign-species (natural) peptides.

.DESCRIPTION
    This is the machine-portable form of Mike MacCoss's Carafe "Workflow 5",
    transcribed from his carafe_log.txt and validated by our own end-to-end
    reproduction on Stellar (Stage 1 byte-identical; Stages 2-6 a faithful
    functional match). See ai/docs/osprey-library-generation-guide.md for the
    full recipe, the validation numbers, and the prerequisites.

    Stages (run a subset with -Stages):

        1a    digest FASTA -> target+decoy training peptides   (entrapment-free)
        1b    digest FASTA -> target+decoy+entrapment peptides (quartets)
        2     Carafe predict a GENERIC library from the 1a training peptides
        3     Osprey search ONE training run with the generic library -> blib
        4-5   Carafe fine-tune RT+MS2 on that blib, predict the FINAL library
              from the 1b entrapment peptides
        6     Osprey search ALL runs with the final library (+ FDRBench input)

    Stages 1a, 2 and 3 are entrapment-free, so several entrapment variants can share them:
    build the first variant fully, then run later ones with -Stages 1b,4-5 -Variant <name>.

    Fine-tuning trains on the entrapment-FREE database on purpose, so the RT
    and MS2 models never see entrapment sequences; the entrapment database is
    used only to PREDICT the final library.

    Nothing here hard-codes this machine. Tools resolve from -parameters, then
    environment variables, then conventional locations; run -Preflight to see
    what resolved and stop before doing any work.

.PARAMETER Dataset
    Stellar (verified) or Astral (UNVALIDATED preset - see the guide). Selects
    input FASTA, mzML names, training file, and the resolution / tolerance
    flags for both Carafe and Osprey.

.PARAMETER EntrapmentSource
    shuffle : Carafe's deterministic C-term-preserving anagram (the default).
    natural : real peptides from a foreign proteome, mass-matched 1:1 to the
              targets so they co-locate in the same isolation window. Requires
              -ForeignFasta. A shuffled entrapment is an anagram of its own
              target and shares its fragment masses, so it is over-identified
              and over-estimates FDP; a foreign peptide is not.

.PARAMETER EntrapmentRatio
    Fraction of targets carrying an entrapment peptide (natural source only).
    1.0 pairs every target; smaller values perturb the target search less.

.EXAMPLE
    # Full Stellar rebuild with the stock shuffle entrapment.
    pwsh -File ./ai/scripts/Osprey/Carafe/Run-CarafeOspreyWorkflow.ps1 -Dataset Stellar

.EXAMPLE
    # Check tools and resolved paths without running anything.
    pwsh -File ./ai/scripts/Osprey/Carafe/Run-CarafeOspreyWorkflow.ps1 -Preflight

.EXAMPLE
    # Arabidopsis entrapment, reusing an already-built stage 1a/2/3 in the same work dir.
    pwsh -File ./ai/scripts/Osprey/Carafe/Run-CarafeOspreyWorkflow.ps1 `
        -Dataset Astral -Stages 1b,4-5 -Variant arab -EntrapmentSource natural `
        -ForeignFasta D:\test\entrapment\arabidopsis\UP000006548.fasta

.NOTES
    Osprey writes per-file caches (.spectra.bin / .scores.parquet / ...) NEXT TO
    its mzML inputs, so this script copies the mzML into -WorkDir first and never
    touches the read-only test-data directory.

    Long runs lock Osprey.exe. Snapshot the build output first if you intend to
    keep building while this runs - see the osprey-development skill.
#>
#requires -Version 7
[CmdletBinding()]
param(
    [ValidateSet('Stellar', 'Astral')] [string]$Dataset = 'Stellar',
    [string]$Stages = '1a,1b,2,3,4-5,6',
    [string]$WorkDir,

    [ValidateSet('shuffle', 'natural')] [string]$EntrapmentSource = 'shuffle',
    [string]$ForeignFasta,
    [double]$EntrapmentRatio = 1.0,
    # Names the per-variant artifacts so several entrapment variants can share one work dir's
    # stages 1a/2/3. Empty keeps the canonical unsuffixed names.
    [string]$Variant = '',

    # Dataset overrides - each defaults from the -Dataset preset.
    [string]$InputFasta,
    [string]$MzmlSourceDir,
    [string[]]$MzmlNames,
    [int]$TrainFileIndex = -1,

    # Tools - each falls back to an env var, then a conventional location.
    [string]$Java,
    [string]$CarafeJar,
    [string]$VenvPython,
    [string]$OspreyExe,

    [int]$Threads = 16,
    [string]$ProteinFdr = '0.01',
    [switch]$ModelDiagnostics,
    [switch]$Preflight
)

$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Dataset-Config.ps1')

$guide = 'ai/docs/osprey-library-generation-guide.md'

# ---------------------------------------------------------------------------
# Dataset presets
# ---------------------------------------------------------------------------
# TestFiles is the read-only mzML/FASTA drop; override with -MzmlSourceDir or
# $env:OSPREY_TESTFILES_DIR when a machine stores it elsewhere.
$testFilesRoot = if ($env:OSPREY_TESTFILES_DIR) { $env:OSPREY_TESTFILES_DIR }
                 elseif ($IsLinux) { '/mnt/d/test/osprey-testfiles-mzML' }
                 else { 'D:\test\osprey-testfiles-mzML' }

$presets = @{
    Stellar = @{
        SourceDir    = Join-Path $testFilesRoot 'stellar'
        Fasta        = 'hela-filtered.fasta'
        Files        = @(
            'Ste-2024-12-02_HeLa_4mz_sDIA_400-900_20.mzML',
            'Ste-2024-12-02_HeLa_4mz_sDIA_400-900_21.mzML',
            'Ste-2024-12-02_HeLa_4mz_sDIA_400-900_22.mzML')
        TrainIndex   = 1          # file _21, the run Mike fine-tuned on
        Resolution   = 'unit'
        FragTol      = '0.4'      # Osprey --fragment-tolerance
        FragUnit     = 'mz'
        CarafeItol   = '0.4'      # Carafe -itol
        CarafeItolU  = 'Da'
        MinPepMz     = '400'
        MaxPepMz     = '900'
        Validated    = $true
    }
    Astral = @{
        SourceDir    = Join-Path $testFilesRoot 'astral'
        Fasta        = 'uniprot_human_jan2025_yeastENO1_contam_ADpeps.fasta'
        Files        = @(
            'Ast-2024-12-05_HeLa_3mzDIA_6mIIT_400-900_49.mzML',
            'Ast-2024-12-05_HeLa_3mzDIA_6mIIT_400-900_55.mzML',
            'Ast-2024-12-05_HeLa_3mzDIA_6mIIT_400-900_60.mzML')
        TrainIndex   = 1
        Resolution   = 'hram'
        FragTol      = '10'       # Osprey's own default (CoreTypesTest.cs:394)
        FragUnit     = 'ppm'
        CarafeItol   = '20'       # UNVERIFIED - no Astral Carafe log exists
        CarafeItolU  = 'ppm'
        MinPepMz     = '400'
        MaxPepMz     = '900'
        # Digest params ARE verified: an ungated rebuild reproduced the delivered
        # osprey_library_db_peptides.fasta byte for byte (SHA256, 349 MB) and all 1,390,979
        # manifest quartets. Only the Carafe PREDICTION tolerance above is assumed.
        Validated    = $false
    }
}
$preset = $presets[$Dataset]

if (-not $InputFasta)    { $InputFasta = Join-Path $preset.SourceDir $preset.Fasta }
if (-not $MzmlSourceDir) { $MzmlSourceDir = $preset.SourceDir }
if (-not $MzmlNames)     { $MzmlNames = $preset.Files }
if ($TrainFileIndex -lt 0) { $TrainFileIndex = $preset.TrainIndex }
if (-not $WorkDir) {
    $base = if ($env:OSPREY_CARAFE_WORKDIR) { $env:OSPREY_CARAFE_WORKDIR }
            elseif ($IsLinux) { '/mnt/d/test/carafe-repro' }
            else { 'D:\test\carafe-repro' }
    $WorkDir = Join-Path $base $Dataset.ToLowerInvariant()
}

# ---------------------------------------------------------------------------
# Tool resolution
# ---------------------------------------------------------------------------
function Resolve-Tool {
    <#
    Returns the first of: explicit value, env var, or the first candidate path
    that exists. Throws a message naming every place it looked when none hit.
    #>
    param(
        [string]$Name,
        [string]$Explicit,
        [string]$EnvVar,
        [string[]]$Candidates = @(),
        [string]$Hint
    )
    if ($Explicit) {
        if (-not (Test-Path $Explicit)) { throw "$Name not found at -$Name value '$Explicit'." }
        return (Resolve-Path $Explicit).Path
    }
    $fromEnv = [Environment]::GetEnvironmentVariable($EnvVar)
    if ($fromEnv) {
        if (-not (Test-Path $fromEnv)) { throw "$Name not found at `$env:$EnvVar = '$fromEnv'." }
        return (Resolve-Path $fromEnv).Path
    }
    foreach ($c in $Candidates) {
        if (-not $c) { continue }
        # Candidates may be globs (Carafe versions its jar directory).
        $hit = Get-Item $c -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    throw ("Could not locate $Name. Set `$env:$EnvVar or pass -$Name. " +
           "Looked in: $($Candidates -join '; '). $Hint See $guide.")
}

$projectRoot = Get-ProjectRoot
$carafeRoot = if ($env:OSPREY_CARAFE_ROOT) { $env:OSPREY_CARAFE_ROOT }
              else { Join-Path $projectRoot 'Carafe-mm' }

function Get-JavaMajorVersion {
    <#
    Major version of a java.exe, or 0 if it cannot be determined. Handles both
    the modern "21.0.1" and the legacy "1.8.0_402" version strings.
    #>
    param([string]$Exe)
    try {
        $line = (& $Exe -version 2>&1 | Select-Object -First 1)
        if ($line -match '"(\d+)(?:\.(\d+))?') {
            $major = [int]$Matches[1]
            if ($major -eq 1 -and $Matches[2]) { return [int]$Matches[2] }
            return $major
        }
    } catch { }
    return 0
}

function Resolve-Java {
    <#
    Carafe's pom targets release 21, so a JDK 17 on JAVA_HOME (common, and the
    case on the machine this recipe was developed on) fails deep inside stage 1
    with an UnsupportedClassVersionError. Walk the candidates and take the first
    that is actually 21+, rather than the first that merely exists.
    #>
    param([string]$Explicit, [int]$MinVersion = 21)

    $explicitSource = $null
    if ($Explicit) { $explicitSource = "-Java '$Explicit'" }
    elseif ($env:OSPREY_CARAFE_JAVA) {
        $Explicit = $env:OSPREY_CARAFE_JAVA
        $explicitSource = "`$env:OSPREY_CARAFE_JAVA = '$Explicit'"
    }
    if ($Explicit) {
        if (-not (Test-Path $Explicit)) { throw "Java not found at $explicitSource." }
        $v = Get-JavaMajorVersion $Explicit
        if ($v -lt $MinVersion) {
            throw ("$explicitSource is Java $v; Carafe needs $MinVersion or newer. " +
                   "See $guide.")
        }
        return (Resolve-Path $Explicit).Path
    }

    $candidates = @(
        $(if ($env:JAVA_HOME) { Join-Path $env:JAVA_HOME 'bin\java.exe' }),
        $(if ($env:JAVA_HOME) { Join-Path $env:JAVA_HOME 'bin/java' }),
        (Get-Command java -ErrorAction SilentlyContinue)?.Source,
        'C:\Program Files\JetBrains\*\jbr\bin\java.exe',
        'C:\Program Files\Eclipse Adoptium\jdk-*\bin\java.exe',
        'C:\Program Files\Java\jdk-*\bin\java.exe',
        '/usr/lib/jvm/*/bin/java')

    $rejected = @()
    foreach ($c in $candidates) {
        if (-not $c) { continue }
        foreach ($hit in (Get-Item $c -ErrorAction SilentlyContinue)) {
            $v = Get-JavaMajorVersion $hit.FullName
            if ($v -ge $MinVersion) { return $hit.FullName }
            if ($v -gt 0) { $rejected += "$($hit.FullName) (Java $v)" }
        }
    }
    $detail = if ($rejected) { " Found but too old: $($rejected -join '; ')." } else { '' }
    throw ("No Java $MinVersion or newer found.$detail Set `$env:OSPREY_CARAFE_JAVA " +
           "or pass -Java. A JetBrains-bundled JBR 21+ works. See $guide.")
}

$Java = Resolve-Java -Explicit $Java

$CarafeJar = Resolve-Tool -Name 'CarafeJar' -Explicit $CarafeJar -EnvVar 'OSPREY_CARAFE_JAR' -Candidates @(
    (Join-Path $carafeRoot 'target\carafe-*\carafe-*.jar'),
    (Join-Path $carafeRoot 'target/carafe-*/carafe-*.jar')
) -Hint "Build it: mvn -f $carafeRoot package."

$VenvPython = Resolve-Tool -Name 'VenvPython' -Explicit $VenvPython -EnvVar 'OSPREY_CARAFE_VENV_PYTHON' -Candidates @(
    (Join-Path $HOME '.carafe\.venv\Scripts\python.exe'),
    (Join-Path $HOME '.carafe/.venv/bin/python')
) -Hint 'This is the AlphaPeptDeep (peptdeep) venv Carafe bootstraps on first run.'

if (-not $OspreyExe) { $OspreyExe = Get-OspreyExe }
if (-not (Test-Path $OspreyExe)) {
    throw ("Osprey.exe not found at '$OspreyExe'. Build it: " +
           'pwsh -File ./ai/scripts/Osprey/Build-Osprey.ps1')
}

$env:JAVA_HOME = Split-Path -Parent (Split-Path -Parent $Java)

# ---------------------------------------------------------------------------
# Stage list
# ---------------------------------------------------------------------------
$StageList = $Stages -split '\s*,\s*' | Where-Object { $_ }
$validStages = @('1a', '1b', '2', '3', '4-5', '6')
foreach ($s in $StageList) {
    if ($validStages -notcontains $s) {
        throw "Unknown stage '$s' (valid: $($validStages -join ', '))."
    }
}
if ($EntrapmentSource -eq 'natural') {
    if (-not $ForeignFasta) {
        throw ("-EntrapmentSource natural needs -ForeignFasta (the foreign-species proteome, " +
               "e.g. the Arabidopsis UP000006548 FASTA). See $guide.")
    }
    if (-not (Test-Path $ForeignFasta)) { throw "ForeignFasta not found: $ForeignFasta" }
}

# ---------------------------------------------------------------------------
# Preflight report
# ---------------------------------------------------------------------------
$javaVersion = (& $Java -version 2>&1 | Select-Object -First 1)

Write-Host "`n--- Carafe/Osprey library workflow ---" -ForegroundColor Cyan
[PSCustomObject][ordered]@{
    Dataset          = $Dataset
    Stages           = ($StageList -join ',')
    EntrapmentSource = $EntrapmentSource
    WorkDir          = $WorkDir
    InputFasta       = $InputFasta
    MzmlSourceDir    = $MzmlSourceDir
    TrainingRun      = $MzmlNames[$TrainFileIndex]
    Java             = "$Java  ($javaVersion)"
    CarafeJar        = $CarafeJar
    VenvPython       = $VenvPython
    Osprey           = $OspreyExe
    Resolution       = "$($preset.Resolution) / $($preset.FragTol) $($preset.FragUnit)"
} | Format-List

if (-not $preset.Validated) {
    Write-Warning (
        "$Dataset PREDICTION parameters are unvalidated. The digest (stage 1a/1b) IS verified - " +
        "an ungated rebuild reproduces the delivered osprey_library_db_peptides.fasta byte for " +
        "byte - but no Astral Carafe log exists, so -itol $($preset.CarafeItol) " +
        "$($preset.CarafeItolU) for stages 2 and 4-5 is an instrument-appropriate assumption, " +
        "NOT a transcribed value. Predicted spectra are therefore ours, not a reproduction of " +
        "Mike's. See $guide.")
}
if ($Preflight) {
    Write-Host 'Preflight only - stopping before any work.' -ForegroundColor Yellow
    return
}

# ---------------------------------------------------------------------------
# Paths and shared argument sets
# ---------------------------------------------------------------------------
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

# Copy mzML into the work dir only for the stages that read them; a 1a/1b/2
# smoke test should not pay for a multi-GB copy.
$needMzml = @('3', '4-5', '6') | Where-Object { $StageList -contains $_ }
$mzml = @()
foreach ($n in $MzmlNames) {
    $dst = Join-Path $WorkDir $n
    if ($needMzml -and -not (Test-Path $dst)) {
        Write-Host "Copying $n -> $WorkDir" -ForegroundColor DarkGray
        Copy-Item (Join-Path $MzmlSourceDir $n) $dst
    }
    $mzml += $dst
}
$trainMzml = $mzml[$TrainFileIndex]

# Carafe library-generation params, identical for Stage 2 and Stage 4/5.
$libGen = @(
    '-fdr', '0.01', '-ptm_site_prob', '0.75', '-ptm_site_qvalue', '0.01',
    '-itol', $preset.CarafeItol, '-itolu', $preset.CarafeItolU,
    '-rf', '-rf_rt_win', 'auto', '-cor', '0.8', '-min_mz', '200',
    '-n_ion_min', '2', '-c_ion_min', '2', '-mode', 'general', '-device', 'gpu',
    '-enzyme', 'NoCut', '-miss_c', '1', '-fixMod', '1', '-varMod', '0', '-maxVar', '1', '-clip_n_m',
    '-minLength', '7', '-maxLength', '35',
    '-min_pep_mz', $preset.MinPepMz, '-max_pep_mz', $preset.MaxPepMz,
    '-min_pep_charge', '2', '-max_pep_charge', '3',
    '-lf_frag_mz_min', '200', '-lf_frag_mz_max', '1960', '-lf_top_n_frag', '20',
    '-lf_min_n_frag', '2', '-lf_frag_n_min', '2', '-lf_type', 'DIA-NN',
    '-se', 'Osprey', '-decoy_prefix', 'decoy_', '-nm', '-nf', '4', '-min_n', '4',
    '-valid', '-na', '0', '-ez', '-fast')

$ospreyCommon = @(
    '--decoys-in-library',
    '--resolution', $preset.Resolution,
    '--fragment-tolerance', $preset.FragTol, '--fragment-unit', $preset.FragUnit,
    '--run-fdr', '0.01', '--experiment-fdr', '0.01',
    '--fdr-method', 'percolator', '--fdr-level', 'precursor',
    '--shared-peptides', 'all', '--threads', "$Threads")
if ($ProteinFdr) { $ospreyCommon += @('--protein-fdr', $ProteinFdr) }

# Stages 1a / 2 / 3 are entrapment-FREE and therefore shared by every variant built in this
# work dir; only the entrapment DB and the final library are per-variant. That is what makes
# an A/B affordable - the expensive training search runs once, not once per variant.
$suffix = if ($Variant) { "_$Variant" } else { '' }
$trainFasta   = Join-Path $WorkDir 'osprey_train_db_peptides.fasta'
$trainPairing = Join-Path $WorkDir 'osprey_train_db_pairing.tsv'
$libFasta     = Join-Path $WorkDir "osprey_library_db_peptides$suffix.fasta"
$libPairing   = Join-Path $WorkDir "osprey_library_db_pairing$suffix.tsv"
$initialLib   = Join-Path $WorkDir 'osprey_initial_library'
$trainBlib    = Join-Path $WorkDir 'osprey_train\osprey.blib'
$newLib       = Join-Path $WorkDir "osprey_new_library$suffix"
$projectDir   = Join-Path $WorkDir "osprey_project$suffix"

$digestCommon = @(
    '-enzyme', '2', '-miss_c', '1', '-minLength', '7', '-maxLength', '35',
    '-min_pep_charge', '2', '-max_pep_charge', '3')

# --- Stage 1a: digest -> target+decoy training FASTA (entrapment-free) ---
if ($StageList -contains '1a') {
    Invoke-Step 'Stage 1a: train FASTA (target+decoy)' $Java (@(
        '-jar', $CarafeJar, '-build_entrapment_fasta', $trainFasta, '-db', $InputFasta,
        '-manifest', $trainPairing) + $digestCommon)
}

# --- Stage 1b: digest -> target+decoy+entrapment library FASTA ---
# Carafe generates the entrapment itself, including the foreign-species variant
# (-entrapment_db), so there is no post-processing step: the manifest and FASTA it
# writes are already final. Both paths apply the fragment-overlap similarity gate.
if ($StageList -contains '1b') {
    $entrapArgs = @('-entrapment')
    if ($EntrapmentSource -eq 'natural') {
        $entrapArgs += @('-entrapment_db', $ForeignFasta)
    }
    if ($EntrapmentRatio -ne 1.0) {
        $entrapArgs += @('-entrapment_ratio', "$EntrapmentRatio")
    }
    Invoke-Step "Stage 1b: library FASTA ($EntrapmentSource entrapment)" $Java (@(
        '-Xmx48g', '-jar', $CarafeJar, '-build_entrapment_fasta', $libFasta, '-db', $InputFasta,
        '-manifest', $libPairing) + $digestCommon + $entrapArgs)
}

# --- Stage 2: Carafe initial (generic) library from the TRAIN FASTA ---
if ($StageList -contains '2') {
    Invoke-Step 'Stage 2: initial library' $Java (@(
        '-jar', $CarafeJar, '-python', $VenvPython, '-db', $trainFasta, '-o', $initialLib) + $libGen)
}

# --- Stage 3: Osprey search the ONE training run with the initial library ---
if ($StageList -contains '3') {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $trainBlib) | Out-Null
    Invoke-Step 'Stage 3: Osprey search training run' $OspreyExe (@(
        '-i', $trainMzml, '-l', (Join-Path $initialLib 'carafe_spectral_library.tsv'),
        '-o', $trainBlib, '--decoy-pairing-manifest', $trainPairing) + $ospreyCommon)
}

# --- Stage 4/5: fine-tune on the blib, predict the FINAL library ---
if ($StageList -contains '4-5') {
    Invoke-Step 'Stage 4/5: finetune + final library' $Java (@(
        '-jar', $CarafeJar, '-python', $VenvPython, '-db', $libFasta,
        '-i', $trainBlib, '-ms', $trainMzml, '-o', $newLib) + $libGen + @('-tf', 'all'))
}

# --- Stage 6: Osprey search ALL runs with the final library (+ FDRBench) ---
if ($StageList -contains '6') {
    New-Item -ItemType Directory -Force -Path (Join-Path $projectDir 'FDRBench') | Out-Null
    $osArgs = @('-i') + $mzml + @(
        '-l', (Join-Path $newLib 'carafe_spectral_library.tsv'),
        '-o', (Join-Path $projectDir 'osprey.blib'),
        '--fdrbench', (Join-Path $projectDir 'FDRBench\FDRBench-Input.tsv'),
        '--decoy-pairing-manifest', $libPairing) + $ospreyCommon
    if ($ModelDiagnostics) { $osArgs += '--model-diagnostics' }
    Invoke-Step 'Stage 6: Osprey project search' $OspreyExe $osArgs
}

Write-Host "`n[SUCCESS] Requested stages complete. Work dir: $WorkDir" -ForegroundColor Green
