<#
.SYNOPSIS
    Manage the team PR & TODO report opt-in roster (add / remove / list / status).

.DESCRIPTION
    Thin CLI over PRReportStore.ps1. The roster (roster.csv) lives in the shared Google Drive
    store "<drive>:\My Drive\Claude\PRReport" and decides who the central report host
    (Invoke-PRReport.ps1 -FanOut) emails, and at what level. This is the script
    /pw-pr-reporting drives; it is also fine to run by hand.

    Preflight always confirms the resolved folder is the real SHARED store (marker
    TEAM-STORE-ID.txt) — never silently writes a private duplicate.

.PARAMETER Action
    add    : opt a person in (upsert an active row). Email auto-derives if omitted.
    remove : opt a person out (set active=false; the row is kept as history).
    list   : print the whole roster.
    status : print one person's row (by -Email, or the auto-derived self email).

.PARAMETER Email
    Subscriber email. For add/status it defaults to the machine's Google account
    (<account>@proteinms.net, same derivation as the usage snapshot).
.PARAMETER GitHubUser
    GitHub login whose review queue / authored PRs / assigned issues the report is built for.
    Required for add.
.PARAMETER Level
    individual (default) = personal slice + self pile-up warning; team = full cross-team report.
.PARAMETER Override
    Force the store path (else auto-resolved / $env:PRREPORT_STORE). For testing.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('add', 'remove', 'list', 'status')][string]$Action,
    [string]$Email = '',
    [string]$GitHubUser = '',
    [ValidateSet('individual', 'team')][string]$Level = 'individual',
    [string]$Override = ''
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'PRReportStore.ps1')

# --- Preflight: must be the shared store (skip the hard check for read-only list) -----------
$check = Test-PRReportStore -Override $Override
if ($Action -in @('add', 'remove') -and -not $check.Ok) {
    Write-Error ("Refusing to write the roster: {0}`n" -f $check.Reason +
        "The roster must live in the SHARED store. In Google Drive (web), right-click the " +
        "shared 'Claude' folder -> 'Add shortcut to Drive' under My Drive, then retry. " +
        "Do NOT create a Claude\PRReport folder by hand.")
    exit 1
}

function Write-Row($r) {
    "{0,-28} {1,-16} {2,-11} {3,-7} added {4} by {5}" -f `
        $r.email, $r.github_login, $r.level, ("active=" + $r.active), $r.added, $r.added_by
}

switch ($Action) {
    'list' {
        $roster = @(Get-PRReportRoster -Override $Override)
        if (-not $roster) { Write-Host "Roster is empty ($((Get-PRReportRosterPath -Override $Override)))."; break }
        Write-Host ("Roster: {0}" -f (Get-PRReportRosterPath -Override $Override))
        $roster | Sort-Object @{e={$_.active};desc=$true}, email | ForEach-Object { Write-Host (Write-Row $_) }
        $active = @($roster | Where-Object { $_.active -eq 'true' }).Count
        Write-Host ("--- {0} active of {1} total ---" -f $active, $roster.Count)
    }
    'status' {
        if (-not $Email) { $Email = Resolve-DefaultUserEmail -Override $Override }
        $row = @(Get-PRReportRoster -Override $Override) | Where-Object { $_.email -eq $Email.ToLowerInvariant() } | Select-Object -First 1
        if (-not $row) { Write-Host "Not subscribed: $Email"; break }
        Write-Host (Write-Row $row)
    }
    'add' {
        if (-not $GitHubUser) { Write-Error "-GitHubUser is required for 'add'."; exit 1 }
        if (-not $Email) { $Email = Resolve-DefaultUserEmail -Override $Override }
        $row = Set-PRReportSubscriber -Email $Email -GitHubUser $GitHubUser -Level $Level -Override $Override
        Write-Host "Subscribed (or updated):"
        Write-Host (Write-Row $row)
    }
    'remove' {
        if (-not $Email) { $Email = Resolve-DefaultUserEmail -Override $Override }
        if (Disable-PRReportSubscriber -Email $Email -Override $Override) {
            Write-Host "Opted out (row kept as history): $Email"
        } else {
            Write-Host "Nothing to remove — not on the roster: $Email"
        }
    }
}
