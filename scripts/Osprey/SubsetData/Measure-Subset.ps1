<#
.SYNOPSIS
    Cut a candidate Stellar subset and measure it through Osprey's one command on the CPU.

.DESCRIPTION
    One invocation per candidate. Builds the subset with build_subset.py (a band of -Windows
    isolation windows over -RtMin..-RtMax, synthetic or -RealProteins, a FASTA beside it, and the
    zip whose size is the cost of committing it), then runs the tuned one command the way the
    Skyline wizard and the functional tests do: predict from the subset FASTA on the CPU, tune on
    ONE run (-TrainingRun, --training-input), search all runs with the tuned model. With -Baseline
    it also runs the same command without --training-input, so the tuned model's precursors on
    the held-out runs can be compared with the pretrained model's.

    Everything lands under <RunRoot>\subset-<Name>\ (data\, candidate.zip, tuned\run.log,
    pretrained\run.log, summary.txt); summary.txt cites the log every number came from.

.EXAMPLE
    pwsh -File ./Measure-Subset.ps1 -Name w1-rt0-24 -Windows 1 -RtMin 0 -RtMax 24 -FullBlib <straight>\output.blib -Baseline
#>
param(
    [Parameter(Mandatory)] [string]$Name,
    [Parameter(Mandatory)] [string]$FullBlib,
    [int]$Windows = 1,
    [double]$RtMin = 7.0,
    [double]$RtMax = 13.0,
    [int]$UndetectedMax = 180,
    [switch]$RealProteins,
    [switch]$Baseline,
    [string]$TrainingRun = 'Ste-2024-12-02_HeLa_4mz_sDIA_400-900_21',
    [string]$DataRoot,
    [string]$RunRoot = 'E:\test\osprey-runs',
    [string]$Exe,
    [int]$Threads = [Environment]::ProcessorCount,
    [int]$Enzyme = 1,
    [switch]$Rebuild
)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
. (Join-Path $here '..\Dataset-Config.ps1')

# Stellar preset geometry (build_subset.py PRESETS['stellar']); the precursor m/z window of the
# prediction is the band's isolation range, as SubsetPipelineTest's WINDOW_MIN_MZ/MAX_MZ are.
$target = 594.5201; $step = 4.0018; $halfWidth = 2.0
$below = [math]::Floor(($Windows - 1) / 2); $above = $Windows - 1 - $below
$mzLo = $target - $below * $step - $halfWidth
$mzHi = $target + $above * $step + $halfWidth

if (-not $DataRoot) {
    $downloads = if ($env:SKYLINE_DOWNLOAD_PATH) { $env:SKYLINE_DOWNLOAD_PATH } else {
        (New-Object -ComObject Shell.Application).NameSpace('shell:Downloads').Self.Path }
    $DataRoot = Join-Path $downloads 'Perftests\osprey-testfiles-mzML-v2'
}
if (-not $Exe) { $Exe = Get-OspreyExe }
foreach ($p in @($DataRoot, $FullBlib, $Exe)) { if (-not (Test-Path $p)) { throw "Not found: $p" } }

$runDir = Join-Path $RunRoot "subset-$Name"
$dataDir = Join-Path $runDir 'data'
$zip = Join-Path $runDir 'candidate.zip'
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

# --- Build the candidate (skipped when already built, unless -Rebuild) ---
if ($Rebuild -or -not (Test-Path $zip)) {
    Remove-Item $dataDir -Recurse -Force -ErrorAction SilentlyContinue
    $buildArgs = @((Join-Path $here 'build_subset.py'), 'stellar', '--data-root', $DataRoot, '--full-blib', $FullBlib,
                   '--keep-dir', $dataDir, '--out-zip', $zip, '--fasta', '--no-libdecoy',
                   '--windows', $Windows, '--rt-min', $RtMin, '--rt-max', $RtMax, '--undetected-max', $UndetectedMax)
    if ($RealProteins) { $buildArgs += '--real-proteins' }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    python @buildArgs *>&1 | Tee-Object -FilePath (Join-Path $runDir 'build.log')
    if ($LASTEXITCODE -ne 0) { throw "build_subset.py failed (see $runDir\build.log)" }
    "build seconds: {0:F0}" -f $sw.Elapsed.TotalSeconds | Add-Content (Join-Path $runDir 'build.log')
}
$mzmls = @(Get-ChildItem $dataDir -Filter '*.mzML' | Sort-Object Name | ForEach-Object FullName)
$fasta = (Get-ChildItem $dataDir -Filter '*.fasta' | Select-Object -First 1).FullName
$trainingMzml = $mzmls | Where-Object { [IO.Path]::GetFileNameWithoutExtension($_) -eq $TrainingRun }
if (-not $trainingMzml) { throw "Training run $TrainingRun not among $($mzmls -join ', ')" }

function Invoke-OneCommand([string]$Leg, [bool]$Tune) {
    $legDir = Join-Path $runDir $Leg
    if (Test-Path $legDir) { Remove-Item $legDir -Recurse -Force }
    New-Item -ItemType Directory -Path $legDir | Out-Null
    $cliArgs = @()
    foreach ($m in $mzmls) { $cliArgs += @('-i', $m) }
    $cliArgs += @('--fasta', $fasta)
    if ($Tune) { $cliArgs += @('--training-input', $trainingMzml) }
    $cliArgs += @('-o', (Join-Path $legDir 'output.blib'), '--work-dir', $legDir,
                  '--device', 'cpu', '--resolution', 'unit', '--protein-fdr', '0.01', '--threads', $Threads,
                  # The test's digest (SubsetPipelineTest.LibraryBuildArgs), window = the band.
                  '--enzyme', $Enzyme, '--miss-c', '1', '--min-length', '7', '--max-length', '35',
                  '--fix-mod', '1', '--var-mod', '0', '--max-var', '1',
                  '--min-pep-charge', '2', '--max-pep-charge', '3',
                  '--min-pep-mz', ('{0:F1}' -f $mzLo), '--max-pep-mz', ('{0:F1}' -f $mzHi))
    $log = Join-Path $legDir 'run.log'
    "Osprey.exe $($cliArgs -join ' ')" | Set-Content $log
    $sw = [Diagnostics.Stopwatch]::StartNew()
    Push-Location $legDir
    try { & $Exe @cliArgs *>&1 | Add-Content $log; $exit = $LASTEXITCODE } finally { Pop-Location }
    $sw.Stop()
    "WALL {0:F1}s exit {1}" -f $sw.Elapsed.TotalSeconds, $exit | Add-Content $log
    return [pscustomobject]@{ Leg = $Leg; Log = $log; Exit = $exit; Wall = $sw.Elapsed.TotalSeconds; Dir = $legDir }
}

# Parse one leg's log: per-task seconds, per-run precursors at 1% grouped by the search they
# belong to (the tuning search comes before TrainModel), totals, and the held-out metrics block.
function Read-Leg($r) {
    $lines = Get-Content $r.Log
    $tasks = [ordered]@{}; $runs = @(); $totals = @(); $heldOut = @(); $search = 'search'
    $inHeld = $false
    foreach ($l in $lines) {
        if ($l -match '\[TASK\] (\w+):done \(([\d.]+)s\)') {
            $key = $Matches[1]; $n = 2
            while ($tasks.Contains($key)) { $key = '{0}#{1}' -f $Matches[1], $n; $n++ }
            $tasks[$key] = [double]$Matches[2]
            if ($Matches[1] -eq 'TrainModel') { $search = 'search' }
        }
        elseif ($l -match '\[TASK\] (\w+):starting' -and -not $tasks.Contains('TrainModel') -and $r.Leg -eq 'tuned') {
            $search = 'tuning'
        }
        if ($l -match '^\s*(?:\S+\s+)?(\S+): ([\d,]+) precursors at ([\d.]+)% run-level FDR') {
            $runs += [pscustomobject]@{ Search = $search; Run = $Matches[1]; Precursors = [int]($Matches[2] -replace ',', '') }
        }
        if ($l -match 'Total: ([\d,]+) precursors pass run-level FDR across (\d+) files') {
            $totals += [pscustomobject]@{ Search = $search; Precursors = [int]($Matches[1] -replace ',', ''); Files = [int]$Matches[2] }
        }
        if ($l -match 'Held-out metrics') { $inHeld = $true; $heldOut += $l.Trim(); continue }
        if ($inHeld) { if ($l -match '^\s+(MS2|RT):') { $heldOut += $l.Trim() } else { $inHeld = $false } }
    }
    $export = $lines | Where-Object { $_ -match '(?i)(export|training).*\d+ precursors|precursors.*(export|training)' } | Select-Object -First 3
    return [pscustomobject]@{ Tasks = $tasks; Runs = $runs; Totals = $totals; HeldOut = $heldOut; Export = $export }
}

$legs = @(Invoke-OneCommand 'tuned' $true)
if ($Baseline) { $legs += Invoke-OneCommand 'pretrained' $false }

$out = New-Object System.Collections.Generic.List[string]
$out.Add("Candidate $Name : $Windows window(s) (precursor m/z $('{0:F2}' -f $mzLo)-$('{0:F2}' -f $mzHi)), RT $RtMin-$RtMax min, " +
         "undetected max $UndetectedMax, $(if ($RealProteins) { 'real' } else { 'synthetic' }) proteins, $Threads threads")
$out.Add("  zip: {0:N1} MB  ({1})" -f ((Get-Item $zip).Length / 1MB), $zip)
$out.Add("  data: " + ((Get-ChildItem $dataDir | ForEach-Object { '{0} {1:N1} MB' -f $_.Name, ($_.Length / 1MB) }) -join '; '))
$out.Add("  build: " + ((Get-Content (Join-Path $runDir 'build.log') | Where-Object { $_ -match '^(library RT fit|detected|synthetic|proteins|concatenated|kept)' }) -join ' | '))
foreach ($r in $legs) {
    $p = Read-Leg $r
    $out.Add("")
    $out.Add("[$($r.Leg)] exit $($r.Exit), wall $('{0:F0}' -f $r.Wall)s  ($($r.Log))")
    $out.Add("  tasks: " + (($p.Tasks.GetEnumerator() | ForEach-Object { '{0} {1:F1}s' -f $_.Key, $_.Value }) -join ', '))
    foreach ($s in @('tuning', 'search')) {
        $rs = @($p.Runs | Where-Object Search -eq $s)
        if ($rs.Count) { $out.Add("  $s search, precursors at 1%: " + (($rs | ForEach-Object { '{0} {1}' -f ($_.Run -replace '^.*_(\d+)(\.mzML)?$', '_$1'), $_.Precursors }) -join ', ')) }
        $ts = @($p.Totals | Where-Object Search -eq $s)
        if ($ts.Count) { $out.Add("  $s total: " + (($ts | ForEach-Object { '{0} over {1} files' -f $_.Precursors, $_.Files }) -join '; ')) }
    }
    foreach ($e in $p.Export) { $out.Add("  export: " + $e.Trim()) }
    foreach ($h in $p.HeldOut) { $out.Add("  " + $h) }
    $blib = Join-Path $r.Dir 'output.blib'
    if (Test-Path $blib) { $out.Add("  output.blib {0:N1} MB" -f ((Get-Item $blib).Length / 1MB)) }
}
$summary = Join-Path $runDir 'summary.txt'
$out | Set-Content $summary
$out
"summary: $summary"
