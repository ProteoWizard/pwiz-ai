<#
.SYNOPSIS
    Samples a run directory's size and its drive's free space into a CSV, for
    perfviz.py --disk (and perfviz.html's disk box), until no Osprey process is left.

.DESCRIPTION
    For an Osprey build WITHOUT --diskstamp. A build that has it writes [DISK] lines into
    the log itself (the dataset runners pass it whenever the exe's --help lists it), and
    perfviz.py / perfviz.html read those - prefer them; a log with [DISK] lines wins over
    this CSV. On an older build, a long run's disk curve has to be sampled beside it.
    Start this detached when the run starts; it waits for an Osprey process to appear, samples every -IntervalSec, and
    exits after the last Osprey exits (one final sample included).

    Columns: time (yyyy-MM-dd HH:mm:ss), dir_gb (run directory, recursive), drive_free_gb.
    dir_gb counts hard-linked files at full size, so a -LinkFrom run reads larger than
    the disk it actually consumed; drive_free_gb is the honest number there.

    The two measure different things: dir_gb is the run directory's size; [DISK] is the
    change in used space on the output drive since Osprey started.

.EXAMPLE
    Start-Process pwsh -WindowStyle Hidden -ArgumentList '-NoProfile','-File',
      'C:\proj\ai\scripts\Sample-RunDisk.ps1','-RunDir','D:\test\osprey-runs\...\<run>',
      '-OutCsv','D:\test\osprey-runs\...\<run>.disk.csv','-IntervalSec','300'
    python ai/scripts/perfviz.py <run>\run.log --png run.png --disk <run>.disk.csv
#>
param(
    [Parameter(Mandatory)] [string]$RunDir,
    [Parameter(Mandatory)] [string]$OutCsv,
    [int]$IntervalSec = 60
)

"time,dir_gb,drive_free_gb" | Set-Content $OutCsv
$drive = (Split-Path -Qualifier $RunDir).TrimEnd(':')
$seen = $false
while ($true) {
    $running = [bool](Get-Process Osprey -ErrorAction SilentlyContinue)
    if ($running) { $seen = $true }
    $bytes = 0
    if (Test-Path $RunDir) {
        $bytes = (Get-ChildItem $RunDir -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    }
    $free = (Get-PSDrive $drive).Free
    "{0},{1:F2},{2:F1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), ($bytes / 1GB), ($free / 1GB) | Add-Content $OutCsv
    if ($seen -and -not $running) { break }
    Start-Sleep -Seconds $IntervalSec
}
