<#
.SYNOPSIS
    Shared helper: register and run the Usage scheduled tasks.

.DESCRIPTION
    Dot-source this file. Three functions:

      Register-UsageDailyTask   install or refresh a per-user daily task (called by
                                Register-ClaudeUsageTask.ps1 and Register-ClaudeUsageGraphTask.ps1)
      Invoke-UsageTask          what the scheduled task runs: the named scripts in order, then
                                one result line appended to the run log
      Get-UsageTaskLogPath      where that log is (ai\.tmp\usage\<TaskName>.log)

    Two Task Scheduler behaviors shape this file.

    Time of day. New-ScheduledTaskTrigger -At stores the start time as a UTC instant
    (StartBoundary ends in "Z"), which Task Scheduler shows as "Synchronize across time
    zones". The task therefore runs at the same instant every day, and its local time moves
    an hour when the clocks change. That is wanted here: every machine snapshots at one
    instant, wherever it is, and the chart task on a single host follows half an hour later.
    For the same reason the register scripts default -At to a UTC time. A local value such as
    '06:00' means that time on the day of registration, which is a different instant in
    summer than in winter and in each time zone.

    No window. A task that runs only while the user is logged on shares the desktop, so
    pwsh.exe opens a console window for the length of the run, and with Windows Terminal as
    the default terminal -WindowStyle Hidden does not hide it. Launching through
    "conhost.exe --headless" creates no window. conhost then returns exit code 0 whatever
    the script did, so the task's Last Run Result always reads success. The run log
    replaces it: read the last line of the log, not the task result.

    Usage:
        . "$PSScriptRoot\UsageTask.ps1"
        Register-UsageDailyTask -TaskName ClaudeUsageSnapshot -At '13:00Z' `
            -Script 'Snapshot-ClaudeUsage.ps1', 'Combine-ClaudeUsage.ps1' -RunNow
#>

function Get-UsageTaskLogPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$TaskName)

    $aiRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    return Join-Path $aiRoot (Join-Path '.tmp\usage' "$TaskName.log")
}

function Invoke-UsageTask {
    <#
    .SYNOPSIS
        Run scripts from this folder in order and append one result line to the task's run log.
        Returns $true when every script ran without error.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TaskName,
        [Parameter(Mandatory)][string[]]$Script
    )

    $log = Get-UsageTaskLogPath $TaskName
    New-Item -ItemType Directory -Force -Path (Split-Path $log -Parent) | Out-Null

    $started = Get-Date
    $failure = ''
    $warnings = [System.Collections.Generic.List[string]]::new()
    $current = ''
    try {
        foreach ($name in $Script) {
            $current = $name
            $path = if ([System.IO.Path]::IsPathRooted($name)) { $name } else { Join-Path $PSScriptRoot $name }
            & $path *>&1 | ForEach-Object {
                if ($_ -is [System.Management.Automation.WarningRecord]) { $warnings.Add($_.Message) }
                elseif ($_ -is [System.Management.Automation.ErrorRecord]) { throw $_ }
            }
        }
    } catch {
        $where = ''
        if ($_.InvocationInfo -and $_.InvocationInfo.ScriptName) {
            $where = ' (at {0}:{1})' -f (Split-Path $_.InvocationInfo.ScriptName -Leaf), $_.InvocationInfo.ScriptLineNumber
        }
        $failure = '{0}: {1}{2}' -f $current, ($_.Exception.Message -replace '\s+', ' ').Trim(), $where
    }

    $status = if ($failure) { 'FAILED' } else { 'OK' }
    $text = if ($failure) { $failure } else { $Script -join ', ' }
    foreach ($w in $warnings) { $text += '  warning: ' + ($w -replace '\s+', ' ').Trim() }
    $line = '{0:yyyy-MM-dd HH:mm:ss}  {1,-6}  {2,6:N1} s  {3}' -f $started, $status, ((Get-Date) - $started).TotalSeconds, $text
    Add-Content -LiteralPath $log -Value $line -Encoding utf8

    return (-not $failure)
}

function Register-UsageDailyTask {
    <#
    .SYNOPSIS
        Install or refresh a per-user task that runs scripts from this folder once a day, at
        the instant -At names, with no window. Re-running updates the task in place.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TaskName,
        [Parameter(Mandatory)][datetime]$At,
        [Parameter(Mandatory)][string[]]$Script,
        [switch]$RunNow,
        [int]$RunNowTimeoutSeconds = 180
    )

    $pwsh = (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source
    if (-not $pwsh) { throw 'pwsh.exe (PowerShell 7) not found on PATH.' }
    foreach ($name in $Script) {
        $path = Join-Path $PSScriptRoot $name
        if (-not (Test-Path $path)) { throw "Missing script: $path" }
    }

    $helper = (Join-Path $PSScriptRoot 'UsageTask.ps1') -replace "'", "''"
    $scriptList = ($Script | ForEach-Object { "'$_'" }) -join ','
    $run = ". '{0}'; if (-not (Invoke-UsageTask -TaskName '{1}' -Script {2})) {{ exit 1 }}" -f $helper, $TaskName, $scriptList
    $pwshArgs = "-NoProfile -NonInteractive -Command `"$run`""

    # conhost --headless needs Windows 10 1809 (build 17763) or later. On anything older the
    # task still works, with a window.
    $conhost = Join-Path $env:SystemRoot 'System32\conhost.exe'
    $headless = (Test-Path $conhost) -and ([Environment]::OSVersion.Version.Build -ge 17763)
    if ($headless) {
        $action = New-ScheduledTaskAction -Execute $conhost -Argument "--headless `"$pwsh`" $pwshArgs"
    } else {
        $action = New-ScheduledTaskAction -Execute $pwsh -Argument $pwshArgs
    }

    $trigger   = New-ScheduledTaskTrigger -Daily -At $At   # stored as a UTC instant, see the file header
    $settings= New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopOnIdleEnd -ExecutionTimeLimit (New-TimeSpan -Minutes 30)
    $principal = New-ScheduledTaskPrincipal -UserId ("{0}\{1}" -f $env:USERDOMAIN, $env:USERNAME) -LogonType Interactive -RunLevel Limited

    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
        -Settings $settings -Principal $principal -Force | Out-Null

    $log = Get-UsageTaskLogPath $TaskName
    Write-Host ("Registered task '{0}' -> daily at {1:HH:mm} UTC ({2:HH:mm} local time today) on {3}" -f $TaskName, $At.ToUniversalTime(), $At.ToLocalTime(), $env:COMPUTERNAME)
    Write-Host ("Runs: {0}{1}" -f ($Script -join ', '), $(if ($headless) { ' (no window)' } else { '' }))
    Write-Host ("Run log: {0}" -f $log)

    if ($RunNow) {
        $before = if (Test-Path $log) { @(Get-Content -LiteralPath $log).Count } else { 0 }
        Write-Host 'Triggering once now to verify...'
        Start-ScheduledTask -TaskName $TaskName
        $result = $null
        $deadline = (Get-Date).AddSeconds($RunNowTimeoutSeconds)
        while (-not $result -and (Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 1
            if (Test-Path $log) {
                $lines = @(Get-Content -LiteralPath $log)
                if ($lines.Count -gt $before) { $result = $lines[-1] }
            }
        }
        if (-not $result) {
            Write-Warning ("No result after {0} s. The run may still be going; check {1}" -f $RunNowTimeoutSeconds, $log)
        } elseif ($result -match '\sFAILED\s') {
            Write-Warning "Result: $result"
        } else {
            Write-Host "Result: $result"
        }
    }
}
