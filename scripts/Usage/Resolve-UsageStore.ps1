<#
.SYNOPSIS
    Shared helper: locate the Claude usage DATA store on Google Drive.

.DESCRIPTION
    The tooling lives in the pwiz-ai repo (ai\scripts\Usage); the DATA lives in a synced
    Google Drive folder "<drive>:\My Drive\Claude\Usage". Because the drive letter varies
    per machine, dot-source this file and call Resolve-UsageStore to find the store root.

    Looks for "My Drive\Claude\Usage" on every mounted filesystem drive. On Windows, Google
    Drive's "Add shortcut to Drive" renders a shared folder as a "Claude.lnk" shortcut file
    (the real folder lives under ".shortcut-targets-by-id\<id>\Claude"), so we also follow
    those shortcuts and, as a backstop, scan ".shortcut-targets-by-id" directly. Finally falls
    back to "Shared drives\<name>\Claude\Usage" (so a future move to a Google Shared Drive
    needs no code change). Pass -Override to force a specific path.

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

    # 1b. "Add shortcut to Drive" on Windows: <root>\My Drive\Claude.lnk -> "...\Claude" (then
    #     \Usage); or a shortcut taken on the Usage folder itself -> "...\Usage". Drive for
    #     Desktop materializes these as .lnk files, which step 1's directory probe walks past.
    $shell = $null
    foreach ($d in $drives) {
        $myDrive = Join-Path $d.Root 'My Drive'
        if (-not (Test-Path $myDrive)) { continue }
        foreach ($cand in @(
            @{ lnk = (Join-Path $myDrive 'Claude.lnk'); sub = 'Usage' },
            @{ lnk = (Join-Path $myDrive 'Usage.lnk');  sub = ''      }
        )) {
            if (-not (Test-Path $cand.lnk)) { continue }
            if (-not $shell) { $shell = New-Object -ComObject WScript.Shell }
            $target = $shell.CreateShortcut($cand.lnk).TargetPath
            if (-not $target) { continue }
            $p = if ($cand.sub) { Join-Path $target $cand.sub } else { $target }
            if (Test-Path $p) { return (Resolve-Path $p).Path }
        }
    }

    # 1c. Backstop: Drive stores shortcut targets under <root>\.shortcut-targets-by-id\<id>\...
    #     Scan those for a Claude\Usage (or bare Usage) folder in case the .lnk is elsewhere.
    foreach ($d in $drives) {
        $byId = Join-Path $d.Root '.shortcut-targets-by-id'
        if (-not (Test-Path $byId)) { continue }
        foreach ($id in (Get-ChildItem $byId -Directory -Force -ErrorAction SilentlyContinue)) {
            foreach ($rel in @('Claude\Usage', 'Usage')) {
                $p = Join-Path $id.FullName $rel
                if (Test-Path $p) { return (Resolve-Path $p).Path }
            }
        }
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
