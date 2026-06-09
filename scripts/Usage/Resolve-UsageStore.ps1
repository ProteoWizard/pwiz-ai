<#
.SYNOPSIS
    Shared helper: locate the Claude usage DATA store on Google Drive.

.DESCRIPTION
    The tooling lives in the pwiz-ai repo (ai\scripts\Usage); the DATA lives in a synced
    Google Drive folder "<drive>:\My Drive\Claude\Usage". Because the drive letter varies
    per machine, dot-source this file and call Resolve-UsageStore to find the store root.

    Looks for "My Drive\Claude\Usage" on every mounted filesystem drive, then falls back
    to "Shared drives\<name>\Claude\Usage" (so a future move to a Google Shared Drive needs
    no code change). Pass -Override to force a specific path.

    Usage:
        . "$PSScriptRoot\Resolve-UsageStore.ps1"
        $store = Resolve-UsageStore          # e.g. G:\My Drive\Claude\Usage
        $data  = Join-Path $store 'data'
#>
function Resolve-UsageStore {
    [CmdletBinding()]
    param([string]$Override)

    if ($Override) {
        if (Test-Path $Override) { return (Resolve-Path $Override).Path }
        throw "Usage store override path not found: $Override"
    }

    $drives = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue

    # 1. Personal My Drive: <root>\My Drive\Claude\Usage
    foreach ($d in $drives) {
        $p = Join-Path $d.Root 'My Drive\Claude\Usage'
        if (Test-Path $p) { return (Resolve-Path $p).Path }
    }

    # 2. Shared Drive fallback: <root>\Shared drives\<name>\Claude\Usage
    foreach ($d in $drives) {
        $sd = Join-Path $d.Root 'Shared drives'
        if (Test-Path $sd) {
            foreach ($team in (Get-ChildItem $sd -Directory -ErrorAction SilentlyContinue)) {
                $p = Join-Path $team.FullName 'Claude\Usage'
                if (Test-Path $p) { return (Resolve-Path $p).Path }
            }
        }
    }

    throw ("Could not find 'My Drive\Claude\Usage' (or a Shared-drive equivalent) on any " +
           "mounted drive. Add the shared folder to your My Drive, or pass -DataDir explicitly.")
}
