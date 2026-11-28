<#
.SYNOPSIS
    Waits on a long-running process and returns as soon as there is something to act on:
    it finished, it died, or the predicted time arrived.

.DESCRIPTION
    A waiter that only greps a log for a success marker waits forever when the marker can
    never be written: the process died, was killed, or its log redirect was cut (the stopped
    parent owned the pipe). The process exiting is the one signal that always arrives, so it
    is the trigger here, and the log only classifies how the run ended.

    Prints exactly one verdict line, then the last lines of the log:

      DONE   the process exited and the log carries -Marker
      DIED   the process exited and the log has no -Marker (crashed, killed, aborted)
      CHECK  the process is still alive at -PredictMinutes: compare the progress line with
             the prediction, re-predict, and run this again with the new estimate
      GONE   the process was not running when the wait started

    Checking at the prediction (1x), not at a padded multiple of it, is deliberate: a padded
    deadline wastes its padding every time the run is stuck. At CHECK, re-predict from the
    progress so far rather than extending blindly.

    The process is identified by its ID AND its start time, because Windows reuses process
    IDs and an hours-long wait can otherwise latch onto an unrelated new process.

    Watch the driver process (the runner script's pwsh, or the chain script), not the
    executable by name: a multi-phase driver has gaps between child processes.

.EXAMPLE
    pwsh -File ai/scripts/Wait-Run.ps1 -ProcessId 25224 -Log D:\runs\x\run.log -Marker 'Analysis complete' -PredictMinutes 20
#>
param(
    [Parameter(Mandatory)] [int] $ProcessId,
    [Parameter(Mandatory)] [string] $Log,
    [Parameter(Mandatory)] [string] $Marker,
    [Parameter(Mandatory)] [double] $PredictMinutes,
    # A regex for the line that shows how far the run is; the last match is printed with CHECK.
    [string] $ProgressPattern = '\b\d+/\d+:',
    [int] $PollSeconds = 30,
    [int] $TailLines = 5
)

function Get-StartTime([int] $id) {
    $p = Get-Process -Id $id -ErrorAction SilentlyContinue
    if ($p) {
        try {
            return $p.StartTime
        } catch {
            return [datetime]::MinValue
        }
    }
    return $null
}

function Write-LogTail {
    if (Test-Path $Log) {
        Get-Content $Log -Tail $TailLines
    } else {
        "(no log at $Log)"
    }
}

function Test-Marker {
    (Test-Path $Log) -and (Select-String -Path $Log -Pattern $Marker -Quiet)
}

$start = Get-StartTime $ProcessId
if ($null -eq $start) {
    $verdict = if (Test-Marker) { 'DONE' } else { 'GONE' }
    "$verdict $(Get-Date -Format s) process $ProcessId was not running when the wait started"
    Write-LogTail
    exit
}

$deadline = (Get-Date).AddMinutes($PredictMinutes)
while ($true) {
    $now = Get-StartTime $ProcessId
    if ($null -eq $now -or $now -ne $start) {
        $verdict = if (Test-Marker) { 'DONE' } else { 'DIED' }
        "$verdict $(Get-Date -Format s) process $ProcessId exited"
        Write-LogTail
        exit
    }
    if ((Get-Date) -ge $deadline) {
        "CHECK $(Get-Date -Format s) process $ProcessId still running at the $PredictMinutes-minute prediction"
        if (Test-Path $Log) {
            $progress = Select-String -Path $Log -Pattern $ProgressPattern | Select-Object -Last 1
            if ($progress) {
                "progress: $($progress.Line)"
            }
        }
        Write-LogTail
        exit
    }
    Start-Sleep -Seconds $PollSeconds
}
