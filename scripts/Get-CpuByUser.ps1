<#
.SYNOPSIS
    Report CPU use per logged-in user on a shared Windows machine (MACS2), without elevation.

.DESCRIPTION
    Answers "is anyone else competing with my run?" on a shared machine. The obvious tools
    get it wrong:

      Get-Process .CPU / Task Manager (non-admin) - other users' processes report no CPU
                    time, so only your own session is visible and the box looks idle.
      \Processor(_Total) - on a machine with more than 64 logical processors Windows splits
                    them into processor groups, and this counter covers ONE group. On MACS2
                    (2 groups x 36) it read 45% while the machine was at 71.5%.
      Win32_Processor LoadPercentage - per socket, and read 100% on both sockets at the same
                    moment.

    This script reads the per-process performance counters, which cover every user, maps
    each process ID to its session (Win32_Process, readable for all users) and each session
    to a user name (quser). Session 0 is reported as "(services)". Box CPU comes from
    \Processor Information(_Total), which covers all processor groups.

    Cores are logical processors: a process at 1.0 keeps one logical processor busy.

.PARAMETER SampleSeconds
    Length of the per-process sample. Default 5.

.PARAMETER Top
    Number of individual processes to list. Default 12.

.EXAMPLE
    pwsh -File './ai/scripts/Get-CpuByUser.ps1'
#>
param(
    [int]$SampleSeconds = 5,
    [int]$Top = 12
)

$ErrorActionPreference = 'SilentlyContinue'

$userOfSession = @{}
quser 2>$null | Select-Object -Skip 1 | ForEach-Object {
    $fields = $_.Trim().TrimStart('>').Trim() -split '\s+'
    $id = $fields | Where-Object { $_ -match '^\d+$' } | Select-Object -First 1
    if ($id) { $userOfSession[[int]$id] = $fields[0] }
}
$sessionOfPid = @{}
Get-CimInstance Win32_Process -Property ProcessId, SessionId | ForEach-Object { $sessionOfPid[[int]$_.ProcessId] = [int]$_.SessionId }
$cores = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors

$box = (Get-Counter '\Processor Information(_Total)\% Processor Time' -SampleInterval 2 -MaxSamples 5).CounterSamples |
    Measure-Object CookedValue -Average -Maximum
"Box CPU over 10 s (all processor groups): mean {0:N1}%, max {1:N1}% of {2} logical processors" -f $box.Average, $box.Maximum, $cores

$samples = (Get-Counter '\Process(*)\% Processor Time', '\Process(*)\ID Process' -SampleInterval $SampleSeconds -MaxSamples 1).CounterSamples
# InstanceName drops the '#n' that tells same-named processes apart; the counter path keeps it
function Get-InstanceKey($sample) { $sample.Path -replace '.*\\process\(([^)]*)\)\\.*', '$1' }
$pidOfInstance = @{}
foreach ($c in $samples) {
    if ($c.Path -like '*\id process') { $pidOfInstance[(Get-InstanceKey $c)] = [int]$c.CookedValue }
}
$rows = foreach ($c in $samples) {
    if ($c.Path -notlike '*% processor time' -or $c.InstanceName -in '_total', 'idle') { continue }
    $p = $pidOfInstance[(Get-InstanceKey $c)]
    $session = if ($null -ne $p -and $sessionOfPid.ContainsKey($p)) { $sessionOfPid[$p] } else { -1 }
    $user = if ($userOfSession.ContainsKey($session)) { $userOfSession[$session] }
            elseif ($session -eq 0) { '(services)' }
            else { '(unknown)' }
    [pscustomobject]@{ User = $user; Process = $c.InstanceName; Pid = $p; Cores = $c.CookedValue / 100 }
}

""
"By user (logical processors busy, $SampleSeconds s sample):"
$rows | Group-Object User | ForEach-Object {
    [pscustomobject]@{ User = $_.Name; Cores = [math]::Round(($_.Group | Measure-Object Cores -Sum).Sum, 1) }
} | Sort-Object Cores -Descending | Format-Table -AutoSize | Out-String

"Top processes:"
$rows | Sort-Object Cores -Descending | Select-Object -First $Top User, Process, Pid,
    @{ n = 'Cores'; e = { [math]::Round($_.Cores, 1) } } | Format-Table -AutoSize | Out-String
