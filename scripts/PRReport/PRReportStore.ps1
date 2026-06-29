<#
.SYNOPSIS
    Shared library for the team PR & TODO activity report: locate the shared roster
    store on Google Drive and read/write the opt-in roster.

.DESCRIPTION
    DOT-SOURCE this file; it defines functions and has no side effects on load.

    Tooling lives in pwiz-ai (ai\scripts\PRReport); the shared DATA (the opt-in roster)
    lives in a synced Google Drive folder "<drive>:\My Drive\Claude\PRReport", a sibling of
    the usage store "<drive>:\My Drive\Claude\Usage". Because the drive letter and the exact
    shortcut layout vary per machine, callers resolve the store at runtime rather than
    hardcoding a path (mirrors ai\scripts\Usage\Resolve-UsageStore.ps1).

    The roster is a single CSV (roster.csv) in that folder. The central report host
    (Invoke-PRReport.ps1 -FanOut) reads it to decide who to email and at what level;
    Manage-PRReportRoster.ps1 (and /pw-pr-reporting) write it.

    Usage:
        . "$PSScriptRoot\PRReportStore.ps1"
        $store = Resolve-PRReportStore                 # e.g. G:\My Drive\Claude\PRReport
        $roster = Get-PRReportRoster                   # array of subscriber rows
        Set-PRReportSubscriber -Email a@b.net -GitHubUser foo -Level individual
#>

# Marker file proving a folder is the real SHARED PRReport store, not a private duplicate
# the user accidentally created by hand (which would silently track only one person).
$script:PRReportStoreMarker   = 'TEAM-STORE-ID.txt'
$script:PRReportStoreMarkerId = 'SKYLINE-TEAM-PRREPORT-STORE'

# Canonical roster column order. 'email' is the unique key (lower-cased on write).
$script:PRReportRosterColumns = @(
    'email', 'github_login', 'level', 'active', 'added', 'updated', 'added_by', 'machine'
)

$script:PRReportLevels = @('individual', 'team')

function Resolve-ClaudeStore {
    <#
        Find the shared "Claude" root folder on Google Drive (the parent of both Usage and
        PRReport). Mirrors the drive-scan / shortcut-following logic of Resolve-UsageStore,
        but targets the Claude root so any sub-store (PRReport, Usage, ...) can hang off it.
        Pass -Override to force a specific path; or set $env:PRREPORT_STORE to the PRReport
        folder directly (its parent is treated as the Claude root) for testing.
    #>
    [CmdletBinding()]
    param([string]$Override)

    if ($Override) {
        if (Test-Path $Override) { return (Resolve-Path $Override).Path }
        throw "Claude store override path not found: $Override"
    }

    $drives = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue

    # 1. Personal My Drive: <root>\My Drive\Claude
    foreach ($d in $drives) {
        $p = Join-Path $d.Root 'My Drive\Claude'
        if (Test-Path $p) { return (Resolve-Path $p).Path }
    }

    # 1b. "Add shortcut to Drive" materializes the shared folder as Claude.lnk under My Drive.
    $shell = $null
    foreach ($d in $drives) {
        $myDrive = Join-Path $d.Root 'My Drive'
        if (-not (Test-Path $myDrive)) { continue }
        $lnk = Join-Path $myDrive 'Claude.lnk'
        if (-not (Test-Path $lnk)) { continue }
        if (-not $shell) { $shell = New-Object -ComObject WScript.Shell }
        $target = $shell.CreateShortcut($lnk).TargetPath
        if ($target -and (Test-Path $target)) { return (Resolve-Path $target).Path }
    }

    # 1c. Backstop: Drive stores shortcut targets under <root>\.shortcut-targets-by-id\<id>\Claude
    foreach ($d in $drives) {
        $byId = Join-Path $d.Root '.shortcut-targets-by-id'
        if (-not (Test-Path $byId)) { continue }
        foreach ($id in (Get-ChildItem $byId -Directory -Force -ErrorAction SilentlyContinue)) {
            $p = Join-Path $id.FullName 'Claude'
            if (Test-Path $p) { return (Resolve-Path $p).Path }
        }
    }

    # 2. Shared Drive fallback: <root>\Shared drives\<name>\Claude
    foreach ($d in $drives) {
        $sd = Join-Path $d.Root 'Shared drives'
        if (Test-Path $sd) {
            foreach ($team in (Get-ChildItem $sd -Directory -ErrorAction SilentlyContinue)) {
                $p = Join-Path $team.FullName 'Claude'
                if (Test-Path $p) { return (Resolve-Path $p).Path }
            }
        }
    }

    throw ("Could not find a shared 'Claude' folder (My Drive\Claude or a Shared-drive " +
           "equivalent) on any mounted drive. Add the shared folder to your My Drive, or " +
           "pass -Override / set `$env:PRREPORT_STORE.")
}

function Resolve-PRReportStore {
    <#
        Resolve "<Claude root>\PRReport". With -Override (or $env:PRREPORT_STORE) the path is
        used as-is. Does NOT create the folder — the owner seeds it once with the marker file.
    #>
    [CmdletBinding()]
    param([string]$Override)

    if (-not $Override -and $env:PRREPORT_STORE) { $Override = $env:PRREPORT_STORE }
    if ($Override) {
        if (Test-Path $Override) { return (Resolve-Path $Override).Path }
        throw "PRReport store override path not found: $Override"
    }
    return (Join-Path (Resolve-ClaudeStore) 'PRReport')
}

function Test-PRReportStore {
    <#
        Confirm a resolved store is the real SHARED store (has the marker), not a private
        duplicate. Returns [pscustomobject]@{ Ok; Path; Reason }. Never throws on a missing
        marker — only the resolver throws (when no Claude folder exists at all).
    #>
    [CmdletBinding()]
    param([string]$Override)

    try { $path = Resolve-PRReportStore -Override $Override }
    catch { return [pscustomobject]@{ Ok = $false; Path = $null; Reason = $_.Exception.Message } }

    $marker = Join-Path $path $script:PRReportStoreMarker
    if (-not (Test-Path $path)) {
        return [pscustomobject]@{ Ok = $false; Path = $path; Reason = "PRReport folder does not exist yet: $path" }
    }
    if ((Test-Path $marker) -and ((Get-Content $marker -TotalCount 1) -eq $script:PRReportStoreMarkerId)) {
        return [pscustomobject]@{ Ok = $true; Path = $path; Reason = 'OK shared store' }
    }
    return [pscustomobject]@{ Ok = $false; Path = $path; Reason = "Missing/!matching marker '$script:PRReportStoreMarker' (expected first line '$script:PRReportStoreMarkerId')" }
}

function Get-PRReportRosterPath {
    [CmdletBinding()]
    param([string]$Override)
    return (Join-Path (Resolve-PRReportStore -Override $Override) 'roster.csv')
}

function Get-PRReportRoster {
    <#
        Load the roster as an array of normalized rows (always the canonical columns).
        Missing file -> empty array. Pass -ActiveOnly to drop opted-out rows.
    #>
    [CmdletBinding()]
    param([string]$Override, [switch]$ActiveOnly)

    $path = Get-PRReportRosterPath -Override $Override
    if (-not (Test-Path $path)) { return @() }

    $rows = @(Import-Csv $path)
    $norm = foreach ($r in $rows) {
        $o = [ordered]@{}
        foreach ($c in $script:PRReportRosterColumns) {
            $o[$c] = if ($r.PSObject.Properties.Name -contains $c -and $null -ne $r.$c) { [string]$r.$c } else { '' }
        }
        [pscustomobject]$o
    }
    if ($ActiveOnly) { $norm = $norm | Where-Object { $_.active -eq 'true' } }
    return @($norm)
}

function Save-PRReportRoster {
    <# Atomically write rows (tmp + Move-Item), sorted by email, canonical columns. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]]$Rows, [string]$Override)

    $path = Get-PRReportRosterPath -Override $Override
    $dir = Split-Path -Parent $path
    if (-not (Test-Path $dir)) { throw "PRReport store folder not found: $dir (seed it with the marker first)" }

    $ordered = $Rows |
        Select-Object -Property $script:PRReportRosterColumns |
        Sort-Object email
    $tmp = "$path.tmp"
    # Select-Object on an empty set writes nothing; force a header so the file always parses.
    if (@($ordered).Count -eq 0) {
        ($script:PRReportRosterColumns -join ',') | Set-Content -Path $tmp -Encoding UTF8
    } else {
        $ordered | Export-Csv -Path $tmp -NoTypeInformation -Encoding UTF8
    }
    Move-Item -Path $tmp -Destination $path -Force
    return $path
}

function Resolve-DefaultUserEmail {
    <#
        Best-effort "<account>@proteinms.net" for the current machine, derived from the Drive
        store's Google account volume label (same trick as Snapshot-ClaudeUsage). Falls back
        to <USERNAME>@proteinms.net. Used so opt-in only has to ask for GitHub login + level.
    #>
    [CmdletBinding()]
    param([string]$Override)
    try {
        $store = Resolve-PRReportStore -Override $Override
        $q = Split-Path -Qualifier $store
        $vol = (Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$q'" -ErrorAction Stop).VolumeName
        if ($vol -match '([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,})') { return $matches[1] }
    } catch {}
    return "$env:USERNAME@proteinms.net"
}

function Set-PRReportSubscriber {
    <#
        Upsert an ACTIVE subscriber row keyed by email (case-insensitive). Updates
        github_login/level/updated if the email already exists; otherwise appends. Returns
        the saved row.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Email,
        [Parameter(Mandatory)][string]$GitHubUser,
        [ValidateSet('individual', 'team')][string]$Level = 'individual',
        [string]$Override
    )
    if ($Email -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') { throw "Not a valid email: '$Email'" }
    $Email = $Email.ToLowerInvariant()
    $now = (Get-Date).ToString('yyyy-MM-dd')

    $roster = @(Get-PRReportRoster -Override $Override)
    $existing = $roster | Where-Object { $_.email -eq $Email } | Select-Object -First 1
    if ($existing) {
        $existing.github_login = $GitHubUser
        $existing.level        = $Level
        $existing.active       = 'true'
        $existing.updated      = $now
        if (-not $existing.added) { $existing.added = $now }
        $saved = $existing
    } else {
        $saved = [pscustomobject][ordered]@{
            email = $Email; github_login = $GitHubUser; level = $Level; active = 'true'
            added = $now; updated = $now; added_by = "$env:USERNAME@proteinms.net"; machine = $env:COMPUTERNAME
        }
        $roster += $saved
    }
    [void](Save-PRReportRoster -Rows $roster -Override $Override)
    return $saved
}

function Disable-PRReportSubscriber {
    <# Mark a subscriber inactive (active=false), preserving the row. Returns $true if found. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Email, [string]$Override)
    $Email = $Email.ToLowerInvariant()
    $roster = @(Get-PRReportRoster -Override $Override)
    $existing = $roster | Where-Object { $_.email -eq $Email } | Select-Object -First 1
    if (-not $existing) { return $false }
    $existing.active  = 'false'
    $existing.updated = (Get-Date).ToString('yyyy-MM-dd')
    [void](Save-PRReportRoster -Rows $roster -Override $Override)
    return $true
}
