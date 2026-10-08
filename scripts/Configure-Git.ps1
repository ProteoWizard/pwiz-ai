<#
.SYNOPSIS
    Applies the git settings the pwiz repositories need on a Windows development machine.

.DESCRIPTION
    Idempotent: run it on a new machine, or again whenever the settings change. Each setting
    is reported as OK (already right), SET (changed now) or LEFT (differs, kept on purpose).

    Global settings:
      core.autocrlf=true      CRLF working copy for Visual Studio; git stores LF
      merge.renormalize=true  merges, cherry-picks and rebases normalize line endings first,
                              so they work across branches still stored CRLF (anything cut
                              before the 2026-10-08 normalization, and the .NET 4.7.2 branches)
      pull.rebase=false       set only when unset; a deliberate other value is left alone
      blame.ignoreRevsFile    an absolute path to a per-user copy of pwiz's
                              .git-blame-ignore-revs, refreshed from origin on every run

    Why blame is global and absolute, not per clone: git blame fails outright ("could not open
    object name list") when the configured file is missing, and pwiz's file exists only on the
    .NET 10 line. A per-clone relative setting breaks blame as soon as that clone checks out a
    .NET 4.7.2 branch. A file outside every repository always exists, and SHAs a repository
    does not contain are ignored, so one global setting works in every checkout and branch.
    Any per-clone setting of the relative path is removed for that reason.

.PARAMETER Check
    Report only; change nothing.

.EXAMPLE
    pwsh -File ./ai/scripts/Configure-Git.ps1
    pwsh -File ./ai/scripts/Configure-Git.ps1 -Check
#>
param(
    [switch]$Check
)

$ErrorActionPreference = 'Stop'
$aiRoot = Split-Path -Parent $PSScriptRoot
$projRoot = Split-Path -Parent $aiRoot
$results = @()

function Add-Row([string]$Setting, [string]$State, [string]$Detail) {
    $script:results += [PSCustomObject]@{ Setting = $Setting; State = $State; Detail = $Detail }
}

function Set-Global([string]$Name, [string]$Value, [switch]$OnlyIfUnset) {
    # The effective value from any scope (system, global): a value set system-wide counts.
    $current = (& git config --get $Name 2>$null)
    if ($current -eq $Value) {
        Add-Row $Name 'OK' $Value
    } elseif ($current -and $OnlyIfUnset) {
        Add-Row $Name 'LEFT' "$current (project default is $Value; kept because it was set deliberately)"
    } elseif ($Check) {
        Add-Row $Name 'NEEDED' "is '$current', should be $Value"
    } else {
        & git config --global $Name $Value
        Add-Row $Name 'SET' ($(if ($current) { "$current -> $Value" } else { $Value }))
    }
}

Set-Global 'core.autocrlf' 'true'
Set-Global 'merge.renormalize' 'true'
Set-Global 'pull.rebase' 'false' -OnlyIfUnset

# --- blame.ignoreRevsFile ---------------------------------------------------------------------

# The pwiz checkouts under the project root, by their origin remote.
$pwizCheckouts = @(Get-ChildItem $projRoot -Directory -ErrorAction SilentlyContinue | Where-Object {
    (Test-Path (Join-Path $_.FullName '.git')) -and
    ((& git -C $_.FullName remote get-url origin 2>$null) -match 'ProteoWizard/pwiz(\.git)?$')
})

# The newest list from origin: master once it carries the file, else the port branch.
$sourceLines = $null
foreach ($checkout in $pwizCheckouts) {
    foreach ($ref in 'origin/master', 'origin/Skyline/work/20260612_net8_port') {
        $text = & git -C $checkout.FullName show "${ref}:.git-blame-ignore-revs" 2>$null
        if ($LASTEXITCODE -eq 0 -and $text) { $sourceLines = $text; break }
    }
    if ($sourceLines) { break }
}

$userFile = Join-Path $HOME '.config/git/pwiz-blame-ignore-revs'
$userFileGit = $userFile -replace '\\', '/'
$shaPattern = '^[0-9a-f]{40}$'
$existing = if (Test-Path $userFile) { @(Get-Content $userFile | Where-Object { $_ -match $shaPattern }) } else { @() }
$fromRepo = if ($sourceLines) { @($sourceLines | ForEach-Object { $_.Trim() } | Where-Object { $_ -match $shaPattern }) } else { @() }
$merged = @($existing + $fromRepo | Select-Object -Unique)
$added = @($merged | Where-Object { $existing -notcontains $_ })

if (-not $sourceLines -and $existing.Count -eq 0) {
    Add-Row 'blame.ignoreRevsFile' 'SKIPPED' 'no pwiz checkout under the project root has .git-blame-ignore-revs on origin yet'
} else {
    if ($added.Count -gt 0) {
        if ($Check) {
            Add-Row 'blame ignore list' 'NEEDED' "$($added.Count) new commit(s) to add to $userFile"
        } else {
            New-Item -ItemType Directory -Force -Path (Split-Path $userFile) | Out-Null
            $header = @(
                '# Commits git blame skips in the pwiz repositories: tree-wide formatting passes.'
                "# Written by ai/scripts/Configure-Git.ps1 from pwiz's .git-blame-ignore-revs; rerun it to refresh."
            )
            Set-Content -Path $userFile -Value ($header + $merged) -Encoding utf8NoBOM
            Add-Row 'blame ignore list' 'SET' "$($merged.Count) commit(s) in $userFile"
        }
    } else {
        Add-Row 'blame ignore list' 'OK' "$($merged.Count) commit(s) in $userFile"
    }
    Set-Global 'blame.ignoreRevsFile' $userFileGit
}

# Remove per-clone relative settings: they break blame on any branch without the file.
foreach ($checkout in $pwizCheckouts) {
    $local = & git -C $checkout.FullName config --local --get blame.ignoreRevsFile 2>$null
    if ($local -and -not [System.IO.Path]::IsPathRooted($local)) {
        if ($Check) {
            Add-Row "blame.ignoreRevsFile ($($checkout.Name))" 'NEEDED' "per-clone '$local' should be removed"
        } else {
            & git -C $checkout.FullName config --local --unset blame.ignoreRevsFile
            Add-Row "blame.ignoreRevsFile ($($checkout.Name))" 'SET' "removed per-clone '$local' (the global setting covers it)"
        }
    }
}

$results | Format-Table -AutoSize | Out-String -Width 200 | Write-Host
$needed = @($results | Where-Object { $_.State -eq 'NEEDED' })
if ($Check -and $needed.Count -gt 0) {
    Write-Host "Run without -Check to apply." -ForegroundColor Yellow
    exit 1
}
