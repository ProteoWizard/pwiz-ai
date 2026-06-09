<#
.SYNOPSIS
    Snapshot this machine's Claude Code token usage into the shared team data store.

.DESCRIPTION
    Tooling lives in the pwiz-ai repo (ai\scripts\Usage); DATA lives on Google Drive at
    "<drive>:\My Drive\Claude\Usage\data" (located via Resolve-UsageStore).

    Parses the local Claude Code JSONL transcripts (~/.claude/projects) and writes a
    daily x model aggregate to data\usage_<MACHINE>.csv. Machine name is the unique key
    (matches the nightly-test convention); a 'user' column (<account>@proteinms.net) is
    derived from the store drive's Google account label.

    IDEMPOTENT and SELF-HEALING against the 30-day transcript reaper: dates still in the
    transcripts are recomputed and replace their rows (today's partial total self-corrects);
    aged-out dates are preserved, so the CSV outlives the raw transcripts.

    est_cost_usd is MODELED from the public per-token rates below — a relative-trend signal,
    not a bill on a Max subscription. Edit $Rates if prices change.

.PARAMETER TranscriptRoot
    Folder of per-project transcript subfolders. Default: ~/.claude/projects
.PARAMETER DataDir
    Output folder. Default: <resolved Google Drive store>\data
.PARAMETER Machine
    Machine tag. Default: $env:COMPUTERNAME
.PARAMETER User
    Person tag. Default: derived from the store drive's Google account email.
#>
[CmdletBinding()]
param(
    [string]$TranscriptRoot = (Join-Path $env:USERPROFILE '.claude\projects'),
    [string]$DataDir        = '',
    [string]$Machine        = $env:COMPUTERNAME,
    [string]$User           = ''
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Resolve-UsageStore.ps1')

# --- Modeled pricing (USD per 1,000,000 tokens). EDIT if published prices change. ---
$Rates = @{
    'claude-opus-4-8'   = @{ input = 15.0; output = 75.0 }
    'claude-opus-4-7'   = @{ input = 15.0; output = 75.0 }
    'claude-sonnet-4-6' = @{ input =  3.0; output = 15.0 }
    'claude-haiku-4-5'  = @{ input =  1.0; output =  5.0 }
    '<synthetic>'       = @{ input =  0.0; output =  0.0 }   # injected placeholders, not real calls
    'default'           = @{ input = 15.0; output = 75.0 }   # unknown model -> Opus rates
}
$CacheWrite5mMult = 1.25
$CacheWrite1hMult = 2.00
$CacheReadMult    = 0.10

function Get-EstCost {
    param($Model, [double]$In, [double]$CwTotal, [double]$Cw1h, [double]$Cw5m, [double]$Cr, [double]$Out)
    $r = $Rates[$Model]; if (-not $r) { $r = $Rates['default'] }
    $base = $r.input / 1e6
    if (($Cw1h + $Cw5m) -gt 0) {
        $cacheWriteCost = ($Cw1h * $base * $CacheWrite1hMult) + ($Cw5m * $base * $CacheWrite5mMult)
    } else {
        $cacheWriteCost = $CwTotal * $base * $CacheWrite5mMult
    }
    return [math]::Round(($In * $base) + ($Out * ($r.output / 1e6)) + $cacheWriteCost + ($Cr * $base * $CacheReadMult), 4)
}

if (-not (Test-Path $TranscriptRoot)) { throw "Transcript root not found: $TranscriptRoot" }
if (-not $DataDir) { $DataDir = Join-Path (Resolve-UsageStore) 'data' }
if (-not (Test-Path $DataDir)) { New-Item -ItemType Directory -Path $DataDir | Out-Null }
$DataDir = (Resolve-Path $DataDir).Path
$csvPath = Join-Path $DataDir ("usage_{0}.csv" -f $Machine)

# --- Team identity: <account>@proteinms.net from the store drive's volume label ---
if (-not $User) {
    try {
        $q = Split-Path -Qualifier $DataDir
        $vol = (Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$q'" -ErrorAction Stop).VolumeName
        if ($vol -match '([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,})') { $User = $matches[1] }
    } catch {}
    if (-not $User) { $User = "$env:USERNAME@proteinms.net" }
}

# --- Aggregate current transcripts: key = "date|model" ---
$agg = @{}
$files = Get-ChildItem -Path $TranscriptRoot -Recurse -Filter *.jsonl -ErrorAction SilentlyContinue
foreach ($f in $files) {
    foreach ($line in [System.IO.File]::ReadLines($f.FullName)) {
        if ($line -notmatch '"output_tokens"') { continue }
        if ($line -notmatch '"timestamp":"([^"]+)"') { continue }
        $localDate = ([datetimeoffset]::Parse($matches[1])).ToLocalTime().ToString('yyyy-MM-dd')

        try { $o = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
        $u = $o.message.usage
        if (-not $u -or $null -eq $u.output_tokens) { continue }

        $model = if ($o.message.model) { [string]$o.message.model } else { 'unknown' }
        $model = $model -replace '-\d{8}$', ''   # collapse dated variants (…-20251001) to base
        $key = "$localDate|$model"
        if (-not $agg.ContainsKey($key)) {
            $agg[$key] = [ordered]@{
                date = $localDate; model = $model; messages = 0
                input = 0L; cache_create = 0L; cache_read = 0L; output = 0L
                cw1h = 0L; cw5m = 0L; web_search = 0L; web_fetch = 0L
                sessions = (New-Object System.Collections.Generic.HashSet[string])
            }
        }
        $a = $agg[$key]
        $a.messages++
        $a.input        += [int64]($u.input_tokens                ?? 0)
        $a.cache_create += [int64]($u.cache_creation_input_tokens ?? 0)
        $a.cache_read   += [int64]($u.cache_read_input_tokens     ?? 0)
        $a.output       += [int64]($u.output_tokens               ?? 0)
        if ($u.cache_creation) {
            $a.cw1h += [int64]($u.cache_creation.ephemeral_1h_input_tokens ?? 0)
            $a.cw5m += [int64]($u.cache_creation.ephemeral_5m_input_tokens ?? 0)
        }
        if ($u.server_tool_use) {
            $a.web_search += [int64]($u.server_tool_use.web_search_requests ?? 0)
            $a.web_fetch  += [int64]($u.server_tool_use.web_fetch_requests  ?? 0)
        }
        if ($o.sessionId) { [void]$a.sessions.Add([string]$o.sessionId) }
    }
}

# --- Build fresh rows for the dates we just recomputed ---
$freshDates = @{}
$freshRows = foreach ($key in $agg.Keys) {
    $a = $agg[$key]
    $freshDates[$a.date] = $true
    [pscustomobject][ordered]@{
        date                  = $a.date
        user                  = $User
        machine               = $Machine
        model                 = $a.model
        sessions              = $a.sessions.Count
        messages              = $a.messages
        input_tokens          = $a.input
        cache_creation_tokens = $a.cache_create
        cache_read_tokens     = $a.cache_read
        output_tokens         = $a.output
        total_tokens          = ($a.input + $a.cache_create + $a.cache_read + $a.output)
        web_search            = $a.web_search
        web_fetch             = $a.web_fetch
        est_cost_usd          = (Get-EstCost -Model $a.model -In $a.input -CwTotal $a.cache_create -Cw1h $a.cw1h -Cw5m $a.cw5m -Cr $a.cache_read -Out $a.output)
    }
}

# --- Merge: keep archived rows for aged-out dates, replace rows for recomputed dates ---
$preserved = @()
if (Test-Path $csvPath) {
    $preserved = Import-Csv $csvPath | Where-Object { -not $freshDates.ContainsKey($_.date) }
}
$all = @($preserved) + @($freshRows) | Sort-Object date, model

$tmp = "$csvPath.tmp"
$all | Export-Csv -Path $tmp -NoTypeInformation -Encoding UTF8
Move-Item -Path $tmp -Destination $csvPath -Force

$days = ($all | Select-Object -ExpandProperty date -Unique).Count
$tok  = ($freshRows | Measure-Object total_tokens -Sum).Sum
$cost = ($freshRows | Measure-Object est_cost_usd -Sum).Sum
Write-Host ("[{0} @ {1}] {2} rows / {3} days  |  window: {4} days, {5:n0} tokens, ~`${6:n2} modeled" -f `
    $Machine, $User, $all.Count, $days, $freshDates.Count, $tok, [math]::Round($cost,2))
Write-Host ("CSV: {0}" -f $csvPath)
