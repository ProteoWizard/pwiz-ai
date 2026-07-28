<#
.SYNOPSIS
    Download a Panorama (LabKey) WebDAV folder to a local directory, resumably.

.DESCRIPTION
    The shared fetcher for large Osprey test datasets. Every dataset in
    ai/docs/osprey-large-datasets.md lives behind the same WebDAV interface, so this is
    written once rather than per dataset.

    * **Resumable.** `curl -C -` continues a partial file, so an interrupted multi-hundred-GB
      pull picks up where it stopped instead of restarting.
    * **Skip-if-complete.** A local file whose size already matches the server's is skipped,
      which makes re-running the safe way to finish a partial download.
    * **Verifies size after each file** and reports any mismatch at the end. A truncated
      file that is silently accepted becomes a corrupt run hours later.
    * **Preserves nothing about timestamps** - deliberately. Osprey's `.spectra.bin` cache
      fingerprints the mzML by size AND last-write-time, but that applies to mzML you
      CONVERT locally (msconvert stamps them), not to .raw you download. See
      ai/scripts/Osprey/SEA-AD/README.md if you are copying mzML+caches between machines.

    Credentials come from netrc (`curl --netrc`); the account needs read on the container.
    A 403 means the container has not been shared - see osprey-large-datasets.md.

.PARAMETER Url
    WebDAV folder URL, e.g.
    https://panoramaweb.org/_webdav/MacCoss/.../%40files/RawFiles/
    URL-encode spaces as %20.

.PARAMETER Dest
    Local directory. Created if absent.

.PARAMETER Filter
    Only download files whose name matches this wildcard (e.g. '*.raw').

.PARAMETER Parallel
    Concurrent downloads (default 4). The bottleneck is usually the server or the link,
    not the disk; going much wider rarely helps and can trip rate limits.

.PARAMETER WhatIf
    List what would be downloaded, with total size, and stop.

.EXAMPLE
    # See the inventory and the total before committing to it
    .\Get-PanoramaFiles.ps1 -Url '<webdav>/RawFiles/' -Dest 'D:\test\osprey-runs\tdp43\raw' -Filter *.raw -WhatIf

.EXAMPLE
    # Run it; re-run the same line after an interruption to finish
    .\Get-PanoramaFiles.ps1 -Url '<webdav>/RawFiles/' -Dest 'D:\test\osprey-runs\tdp43\raw' -Filter *.raw
#>
#requires -Version 7
param(
    [Parameter(Mandatory = $true)][string]$Url,
    [Parameter(Mandatory = $true)][string]$Dest,
    [string]$Filter = '*',
    [int]$Parallel = 4,
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
if (-not $Url.EndsWith('/')) { $Url += '/' }

# --- inventory the folder (PROPFIND Depth:1) --------------------------------
$tmp = [IO.Path]::GetTempFileName()
$code = curl.exe -s --netrc -o $tmp -w '%{http_code}' -X PROPFIND -H 'Depth: 1' -A 'Mozilla/5.0' $Url
if ($code -ne '207') {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    $hint = switch ($code) {
        '403' { 'the account authenticates but the container is not shared - ask for the Agents group to be granted read on it' }
        '401' { 'no usable credentials - check the netrc entry for this host' }
        default { 'unexpected status' }
    }
    throw "PROPFIND returned $code ($hint): $Url"
}
[xml]$xml = Get-Content $tmp
Remove-Item $tmp -Force -ErrorAction SilentlyContinue

$base = [uri]::UnescapeDataString(([uri]$Url).AbsolutePath.TrimEnd('/'))
$items = New-Object System.Collections.ArrayList
foreach ($r in (Select-Xml -Xml $xml -XPath '//d:response' -Namespace @{ d = 'DAV:' })) {
    $href = [uri]::UnescapeDataString($r.Node.href)
    if ($href.TrimEnd('/') -eq $base) { continue }
    if ($null -ne $r.Node.propstat.prop.resourcetype.collection) { continue }
    $name = ($href.TrimEnd('/') -split '/')[-1]
    if ($name -notlike $Filter) { continue }
    [void]$items.Add([pscustomobject]@{
        Name = $name
        Size = [int64]($r.Node.propstat.prop.getcontentlength | Select-Object -First 1)
    })
}
if ($items.Count -eq 0) { throw "No files matching '$Filter' at $Url" }

$total = ($items | Measure-Object Size -Sum).Sum
Write-Host ("=== {0}" -f $Url)
Write-Host ("  {0} file(s) matching '{1}', {2:N1} GB total" -f $items.Count, $Filter, ($total / 1GB))

if (-not (Test-Path $Dest)) {
    if (-not $WhatIf) { New-Item -ItemType Directory -Path $Dest -Force | Out-Null }
}

# Already-complete files (size matches) are skipped, which is what makes a re-run finish
# a partial pull rather than start over.
$todo = New-Object System.Collections.ArrayList
foreach ($i in $items) {
    $local = Join-Path $Dest $i.Name
    if ((Test-Path $local) -and ((Get-Item $local).Length -eq $i.Size)) { continue }
    [void]$todo.Add($i)
}
$have = $items.Count - $todo.Count
$todoBytes = ($todo | Measure-Object Size -Sum).Sum
Write-Host ("  already complete: {0}   to fetch: {1}  ({2:N1} GB)" -f $have, $todo.Count, ($todoBytes / 1GB))
$free = (Get-PSDrive ($Dest[0])).Free
Write-Host ("  free on {0}: {1:N0} GB" -f $Dest[0], ($free / 1GB))
if ($todoBytes -gt $free) { throw ("Not enough space: need {0:N0} GB, have {1:N0} GB." -f ($todoBytes/1GB), ($free/1GB)) }

if ($WhatIf) {
    Write-Host '-WhatIf: not downloading. First few:'
    $todo | Select-Object -First 5 | ForEach-Object { Write-Host ("    {0,-64} {1,7:N2} GB" -f $_.Name, ($_.Size / 1GB)) }
    return
}
if ($todo.Count -eq 0) { Write-Host '  nothing to do.' -ForegroundColor Green; return }

$sw = [Diagnostics.Stopwatch]::StartNew()
$todo | ForEach-Object -ThrottleLimit $Parallel -Parallel {
    $local = Join-Path $using:Dest $_.Name
    # -C - resumes a partial file; the surrounding skip-if-complete means a re-run only
    # ever touches files that are missing or short.
    curl.exe -s -L --netrc -C - -A 'Mozilla/5.0' --retry 5 --retry-delay 10 --retry-all-errors `
        -o $local ($using:Url + [uri]::EscapeDataString($_.Name))
}
$sw.Stop()

# Verify. A short file here is a truncated transfer, and finding it now is far cheaper
# than finding it as a corrupt run several hours into processing.
$bad = New-Object System.Collections.ArrayList
foreach ($i in $items) {
    $local = Join-Path $Dest $i.Name
    if (-not (Test-Path $local)) { [void]$bad.Add("MISSING  $($i.Name)"); continue }
    $len = (Get-Item $local).Length
    if ($len -ne $i.Size) { [void]$bad.Add(("SHORT    {0}  local {1:N0} vs server {2:N0}" -f $i.Name, $len, $i.Size)) }
}
$mb = if ($sw.Elapsed.TotalSeconds -gt 0) { $todoBytes / 1MB / $sw.Elapsed.TotalSeconds } else { 0 }
Write-Host ("  fetched {0:N1} GB in {1:hh\:mm\:ss}  ({2:N0} MB/s)" -f ($todoBytes / 1GB), $sw.Elapsed, $mb)
if ($bad.Count) {
    Write-Host ("  INCOMPLETE: {0} file(s) - re-run this same command to finish" -f $bad.Count) -ForegroundColor Red
    $bad | Select-Object -First 10 | ForEach-Object { Write-Host "    $_" }
    exit 1
}
Write-Host ("  all {0} file(s) present and size-verified" -f $items.Count) -ForegroundColor Green
