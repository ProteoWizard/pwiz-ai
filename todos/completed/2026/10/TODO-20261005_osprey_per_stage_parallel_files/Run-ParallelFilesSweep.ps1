# --parallel-files scaling sweep: SEA-AD PerFileScoring (calibration + first-pass scoring) from COLD .spectra.bin
# caches, one leg per P, each leg on its own 12 files. Written for TODO-osprey_parallel_files_scaling.md.
# Run detached (Start-Process pwsh -WindowStyle Hidden -ArgumentList '-NoProfile','-File',<this>,...).
param(
    [Parameter(Mandatory)] [string]$Exe,              # snapshot of a Release build (never the build tree)
    [Parameter(Mandatory)] [string]$LibraryDir,       # ...\sea-ad\lib\target+decoy+entrapment-20260817
    [Parameter(Mandatory)] [string]$RunsDir,          # where per-leg output dirs are created
    [string]$LogDir = (Join-Path $env:TEMP 'pfsweep'),
    [string]$Runner = 'C:/proj/ai/scripts/Osprey/SEA-AD/Run-SeaAd.ps1',
    [int]$FilesPerLeg = 12,
    [switch]$LogMemory                                 # OSPREY_LOG_MEMORY=1: post-GC probes (live memory)
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force $LogDir | Out-Null
# name, P (0 = sequential), skip (first position - 1), lock scope, serial reads. Each leg reads its own files; a
# file read in the last ~100 GB of reads is still in the file cache and would not be cold.
$legs = @(
    @('p1', 0, 24, 'file', '1'),
    @('p2', 2, 36, 'file', '1'),
    @('p3', 3, 48, 'file', '1'),
    @('p4', 4, 60, 'file', '1'),
    @('p4-process', 4, 0, 'process', '1'),
    @('p4-parallelreads', 4, 12, 'file', '0')
)
function Note($m) { "[{0:yyyy-MM-dd HH:mm:ss}] {1}" -f (Get-Date), $m | Out-File "$LogDir\pfsweep.log" -Append }

$env:OSPREY_LOG_MEMORY = if ($LogMemory) { '1' } else { $null }
foreach ($leg in $legs) {
    $name, $p, $skip, $scope, $serial = $leg
    $out = Join-Path $RunsDir "pfsweep-$name"
    if (Test-Path $out) { Remove-Item -Recurse -Force $out }
    $env:OSPREY_SERIAL_READ_SCOPE = if ($scope -eq 'process') { 'process' } else { $null }
    $env:OSPREY_SERIAL_WINDOW_READS = $serial
    $csv = "$LogDir\pfsweep-$name-perf.csv"
    if (Test-Path $csv) { Remove-Item $csv }
    $sampler = Start-Process typeperf -WindowStyle Hidden -PassThru -ArgumentList @(
        '"\Processor(_Total)\% Processor Time"', '"\PhysicalDisk(_Total)\Disk Read Bytes/sec"',
        '"\Memory\Available MBytes"', '-si', '5', '-o', "`"$csv`"", '-y')
    Note "$name start P=$p positions $($skip + 1)-$($skip + $FilesPerLeg) scope=$scope serial=$serial"
    $sw = [Diagnostics.Stopwatch]::StartNew()
    pwsh -NoProfile -File $Runner -DecoyMode libdecoy -Ratio 1.0 -LibraryDir $LibraryDir -Exe $Exe -Task PerFileScoring `
        -SkipFirstFiles $skip -NumFiles $FilesPerLeg -ParallelFiles $p -OutDir $out *> "$LogDir\pfsweep-$name.out"
    $code = $LASTEXITCODE
    Stop-Process -Id $sampler.Id -Force -ErrorAction SilentlyContinue
    Note ("$name exit=$code wall={0:hh\:mm\:ss}" -f $sw.Elapsed)
    python 'C:\proj\ai\scripts\perfviz.py' "$out\run.log" --files $FilesPerLeg *> "$LogDir\pfsweep-$name.perfviz.txt"
}
Note 'ALL DONE'
