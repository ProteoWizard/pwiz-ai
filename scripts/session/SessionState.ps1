#Requires -Version 7.0

<#
.SYNOPSIS
    Shared state that lets a session survive an unexpected restart (Windows
    Update reboot, power loss, hard crash).

.DESCRIPTION
    Two kinds of record live under ai/.tmp/ and are never committed:

      sessions/<session-id>.json   one per Claude Code session, written by the
                                   Set-ActiveCheckout SessionStart hook, deleted
                                   by the skyclaude launcher on a clean exit.

      runs/<name>-<pid>.json       one per build/test run, written by
                                   Build-Skyline.ps1 / Run-Tests.ps1 on entry
                                   and removed in their finally block.

    A record that is still present means its owner never exited cleanly. Every
    record carries the machine's boot ID (LastBootUpTime), so a survivor whose
    boot ID differs from the current one was killed by a RESTART rather than by
    a crash or a closed terminal -- that distinction is what makes the recovery
    message trustworthy enough to act on.

    All functions here are best-effort and swallow their own errors: this is
    bookkeeping, and it must never be the reason a build, a test run, or a
    session start fails.

.NOTES
    Dot-source by absolute path; the ai/ root is derived from this script's own
    location (<ai>/scripts/session/SessionState.ps1) so no path edits are needed.
#>

# ai/ root = two levels up from ai/scripts/session. Captured at dot-source time
# because $PSScriptRoot is not available inside the functions when they run later.
$Global:PwizSessionAiRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

# Records older than this are pruned opportunistically on each write.
$Global:PwizSessionRetentionDays = 14

function ConvertTo-PwizBootId {
    <#
        Normalizes a boot ID read back from a record.

        ConvertFrom-Json revives anything ISO-8601-shaped as a [DateTime], so a
        bare timestamp would come back typed differently than the live boot ID
        and never compare equal -- which would report every record as
        restart-killed and mask the live-process check behind it. The 'boot-'
        prefix keeps the value a string through the round trip; this also folds
        back a value that was revived as a DateTime anyway.
    #>
    param($Value)

    if ($null -eq $Value) { return '' }
    if ($Value -is [datetime]) { return 'boot-' + $Value.ToUniversalTime().ToString('o') }
    [string]$Value
}

function Get-PwizBootId {
    <#
        Identifies the current boot. Two records with different boot IDs did not
        live through the same uptime, which is how a restart is told apart from a
        crash. Cached per process -- it cannot change while we are running.
    #>
    if ($Global:PwizSessionBootId) { return $Global:PwizSessionBootId }
    try {
        $boot = (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime
        $Global:PwizSessionBootId = 'boot-' + $boot.ToUniversalTime().ToString('o')
    }
    catch {
        # No boot ID means we degrade to "unclean exit, cause unknown" rather than
        # claiming a restart we cannot prove.
        $Global:PwizSessionBootId = ''
    }
    $Global:PwizSessionBootId
}

function Format-PwizLocalTime {
    <#
        One timestamp format for everything a human or an agent reads. Records
        store UTC and ConvertFrom-Json may hand it back as a [DateTime]; a report
        that mixes UTC with local invites a wrong conclusion about when something
        happened, so everything is rendered local and labelled by the caller.
    #>
    param($Value)

    try {
        $dt = if ($Value -is [datetime]) { $Value } else { [datetime]::Parse($Value) }
        $dt.ToLocalTime().ToString('yyyy-MM-dd HH:mm')
    }
    catch { [string]$Value }
}

function Get-PwizStateDir {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('sessions', 'runs')]
        [string] $Kind
    )
    try {
        $dir = Join-Path (Join-Path $Global:PwizSessionAiRoot '.tmp') $Kind
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null
        }
        $dir
    }
    catch { $null }
}

function Get-PwizCheckoutName {
    <#
        Accepts either a checkout root or its pwiz_tools child (the form
        PWIZ_LSP_DIR holds) and returns the checkout's leaf name.
    #>
    param([string] $Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    try {
        $root = $Path -replace '[\\/]+pwiz_tools[\\/]*$', ''
        Split-Path $root -Leaf
    }
    catch { $null }
}

function Remove-PwizExpiredState {
    # Keeps ai/.tmp from growing without bound. Silent by design.
    try {
        $cutoff = (Get-Date).AddDays(-$Global:PwizSessionRetentionDays)
        foreach ($kind in @('sessions', 'runs')) {
            $dir = Get-PwizStateDir -Kind $kind
            if (-not $dir) { continue }
            Get-ChildItem -LiteralPath $dir -Filter '*.json' -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -lt $cutoff } |
                Remove-Item -Force -ErrorAction SilentlyContinue
        }
    }
    catch { }
}

#region Session records

function Write-PwizSessionRecord {
    <#
        Called from the SessionStart hook, which is the only place that knows the
        Claude Code session ID. LaunchId comes from the skyclaude launcher via
        SKYCLAUDE_LAUNCH_ID and is what the launcher matches on to delete this
        record when the session exits cleanly.
    #>
    param(
        [Parameter(Mandatory)] [string] $SessionId,
        [string] $Checkout,
        [string] $LspDir,
        [string] $Branch,
        [string] $TranscriptPath,
        [string] $Source,
        [string] $LaunchId
    )

    try {
        $dir = Get-PwizStateDir -Kind 'sessions'
        if (-not $dir) { return }

        $record = [ordered]@{
            schema         = 1
            sessionId      = $SessionId
            launchId       = $LaunchId
            checkout       = $Checkout
            lspDir         = $LspDir
            branch         = $Branch
            transcriptPath = $TranscriptPath
            source         = $Source
            bootId         = Get-PwizBootId
            startedUtc     = (Get-Date).ToUniversalTime().ToString('o')
        }

        $path = Join-Path $dir "$SessionId.json"
        $record | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $path -Encoding utf8 -ErrorAction Stop
        Remove-PwizExpiredState
    }
    catch { }
}

function Get-PwizSessionRecords {
    <#
        Surviving session records, newest first. Every record returned represents
        a session that never exited cleanly -- clean exits delete their own.
    #>
    param(
        [string] $Checkout,          # limit to one checkout
        [string] $ExcludeLaunchId,   # skip the caller's own live session
        [string] $ExcludeSessionId
    )

    try {
        $dir = Get-PwizStateDir -Kind 'sessions'
        if (-not $dir) { return @() }

        Get-ChildItem -LiteralPath $dir -Filter '*.json' -ErrorAction SilentlyContinue |
            ForEach-Object {
                try {
                    $r = Get-Content -LiteralPath $_.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                    $r | Add-Member -NotePropertyName 'path' -NotePropertyValue $_.FullName -Force
                    $r | Add-Member -NotePropertyName 'lastWrite' -NotePropertyValue $_.LastWriteTime -Force
                    $r
                }
                catch { }   # a truncated record (killed mid-write) is simply skipped
            } |
            Where-Object {
                $_ -and $_.sessionId -and
                (-not $Checkout -or $_.checkout -eq $Checkout) -and
                (-not $ExcludeLaunchId -or $_.launchId -ne $ExcludeLaunchId) -and
                (-not $ExcludeSessionId -or $_.sessionId -ne $ExcludeSessionId)
            } |
            Sort-Object lastWrite -Descending
    }
    catch { @() }
}

function Remove-PwizSessionRecord {
    # Called from the launcher's finally block: a clean exit leaves no survivor.
    param(
        [string] $LaunchId,
        [string] $SessionId
    )

    if (-not $LaunchId -and -not $SessionId) { return }
    try {
        Get-PwizSessionRecords |
            Where-Object {
                ($LaunchId -and $_.launchId -eq $LaunchId) -or
                ($SessionId -and $_.sessionId -eq $SessionId)
            } |
            ForEach-Object { Remove-Item -LiteralPath $_.path -Force -ErrorAction SilentlyContinue }
    }
    catch { }
}

#endregion

#region Run markers

function Write-PwizRunMarker {
    <#
        Records a build or test run that is in flight. Returns the marker path,
        which the caller passes to Remove-PwizRunMarker in its finally block.
        Returns $null on any failure so callers can ignore the result entirely.
    #>
    param(
        [Parameter(Mandatory)] [string] $Name,      # e.g. the test name or build target
        [Parameter(Mandatory)] [string] $Kind,      # 'test' or 'build'
        [string] $Checkout,
        [string] $CommandLine,
        [string] $LogPath
    )

    try {
        $dir = Get-PwizStateDir -Kind 'runs'
        if (-not $dir) { return $null }

        $record = [ordered]@{
            schema      = 1
            kind        = $Kind
            name        = $Name
            checkout    = $Checkout
            commandLine = $CommandLine
            logPath     = $LogPath
            processId   = $PID
            bootId      = Get-PwizBootId
            startedUtc  = (Get-Date).ToUniversalTime().ToString('o')
        }

        # PID in the name so concurrent runs of the same test never collide.
        $safeName = ($Name -replace '[^\w\.-]', '_')
        if ($safeName.Length -gt 60) { $safeName = $safeName.Substring(0, 60) }
        $path = Join-Path $dir "$Kind-$safeName-$PID.json"
        $record | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $path -Encoding utf8 -ErrorAction Stop
        Remove-PwizExpiredState
        $path
    }
    catch { $null }
}

function Remove-PwizRunMarker {
    param([string] $Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    try { Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue }
    catch { }
}

function Get-PwizRunMarkers {
    # Surviving run markers, newest first. Each one is a run that never finished.
    param([string] $Checkout)

    try {
        $dir = Get-PwizStateDir -Kind 'runs'
        if (-not $dir) { return @() }

        Get-ChildItem -LiteralPath $dir -Filter '*.json' -ErrorAction SilentlyContinue |
            ForEach-Object {
                try {
                    $r = Get-Content -LiteralPath $_.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                    $r | Add-Member -NotePropertyName 'path' -NotePropertyValue $_.FullName -Force
                    $r | Add-Member -NotePropertyName 'lastWrite' -NotePropertyValue $_.LastWriteTime -Force
                    $r
                }
                catch { }
            } |
            Where-Object { $_ -and (-not $Checkout -or $_.checkout -eq $Checkout) } |
            Sort-Object lastWrite -Descending
    }
    catch { @() }
}

#endregion

function Get-PwizInterruptedState {
    <#
        The one query both consumers (the skyclaude launcher and the SessionStart
        hook) ask: what did NOT finish, and was a restart to blame?

        Returns $null when there is nothing to report, otherwise an object with
        Sessions, Runs, RebootDetected, and BootId. A run or session whose boot ID
        differs from the current one was killed by a restart; matching boot IDs
        mean the owner died some other way (crash, closed terminal, Ctrl-C during
        a marker write) and we say so rather than blaming a reboot.
    #>
    param(
        [string] $Checkout,
        [string] $ExcludeLaunchId,
        [string] $ExcludeSessionId
    )

    try {
        $bootId = Get-PwizBootId
        $sessions = @(Get-PwizSessionRecords -Checkout $Checkout -ExcludeLaunchId $ExcludeLaunchId -ExcludeSessionId $ExcludeSessionId)
        $runs = @(Get-PwizRunMarkers -Checkout $Checkout)

        # A marker written by a still-running process is not an interruption --
        # it is a concurrent run. Drop those; only same-boot markers can be live.
        $runs = @($runs | Where-Object {
            if ((ConvertTo-PwizBootId $_.bootId) -ne $bootId) { return $true }   # pre-restart: definitely dead
            -not (Get-Process -Id $_.processId -ErrorAction SilentlyContinue)
        })

        if (-not $sessions -and -not $runs) { return $null }

        [pscustomobject]@{
            BootId         = $bootId
            Sessions       = $sessions
            Runs           = $runs
            RebootDetected = [bool]($bootId -and (
                ($sessions | Where-Object { $_.bootId -and (ConvertTo-PwizBootId $_.bootId) -ne $bootId }) -or
                ($runs     | Where-Object { $_.bootId -and (ConvertTo-PwizBootId $_.bootId) -ne $bootId })
            ))
        }
    }
    catch { $null }
}

function Get-PwizPendingReboot {
    <#
        Whether Windows is holding a reboot. Reported as two tiers because they
        are not equally meaningful: WindowsUpdate/ComponentBasedServicing are
        real pending-reboot signals, while PendingFileRenameOperations is set by
        all manner of ordinary installers and would cry wolf daily if treated the
        same way. Only Confirmed should drive a warning.
    #>
    try {
        $wu  = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
        $cbs = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
        $ren = [bool](Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' `
                        -Name PendingFileRenameOperations -ErrorAction SilentlyContinue)

        [pscustomobject]@{
            Confirmed = ($wu -or $cbs)
            Advisory  = $ren
            Reasons   = @(
                if ($wu)  { 'Windows Update' }
                if ($cbs) { 'servicing (CBS)' }
            )
        }
    }
    catch {
        [pscustomobject]@{ Confirmed = $false; Advisory = $false; Reasons = @() }
    }
}
