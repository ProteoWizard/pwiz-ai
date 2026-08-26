<#
.SYNOPSIS
    Validate .spectra.bin caches the way Osprey does, and say whether their sources are
    safe to delete.

.DESCRIPTION
    Osprey can search a cohort whose sources are gone as long as every `.spectra.bin` is
    present and readable (pwiz #4616). That makes the sources deletable - roughly halving
    the disk a large cohort needs - but it moves a check that used to be automatic onto
    the operator.

    **The check that only works BEFORE the delete.** A cache header carries the source's
    size and last-write time. While the source exists, Osprey compares them and re-parses
    on a mismatch. Once the source is gone there is nothing to compare against, so a
    stale or mismatched cache is trusted silently and the run produces a wrong answer with
    no error. This script does that comparison while it can still be done, which is the
    gate a "delete the sources" decision needs.

    It reads only the 32-byte header and the 16-byte EOF footer per file, so a 1 TB cohort
    checks in seconds rather than by reading the bodies.

    Validated per cache, in Osprey's own order (SpectraCache.TryReadHeader / ReadIndex):

    * magic `OSPRSPC\0` and VERSION (4) - a version bump invalidates every cache, and
      re-population is exactly what a deleted source makes impossible;
    * the `FINGERPRINT_UNMEASURABLE` sentinel, which Osprey rejects outright;
    * source size + mtime against the source file, when the source is still present;
    * geometry: `index_offset + 40 * n_ms2 == length - 16`, and the MS1 section inside the
      body. This catches a truncated or still-being-written cache, which is the failure
      the staging pipeline actually produced.

.PARAMETER Path
    Directory holding the `.spectra.bin` files. Sources are expected beside them unless
    -SourceDir says otherwise.

.PARAMETER SourceDir
    Where the source files live, if not beside the caches.

.PARAMETER Extension
    Source extension without the dot (default 'raw'). Only used to locate sources and to
    report caches that have none.

.PARAMETER IncludePattern
    Regex over the cache file name, e.g. 'us(0062)' for one CHS plate.

.PARAMETER ShowAll
    List every file, not only the problems.

.EXAMPLE
    # The gate before deleting a staged cohort's sources
    .\Test-SpectraCaches.ps1 -Path D:\test\osprey-runs\chs-seer\raw

.EXAMPLE
    # One plate
    .\Test-SpectraCaches.ps1 -Path D:\test\osprey-runs\chs-seer\raw -IncludePattern 'us0062'

.NOTES
    Exit code 0 only when every cache is readable AND every cache that still has a source
    matches it. Anything else exits 1 - a partial pass is not a delete authorization.

    Written with Claude Code assistance.
#>
#requires -Version 7
param(
    [Parameter(Mandatory)][string]$Path,
    [string]$SourceDir,
    [string]$Extension = 'raw',
    [string]$IncludePattern,
    [switch]$ShowAll
)

$ErrorActionPreference = 'Stop'

# Mirrors SpectraCache.cs. A bump here without a bump there would report every cache bad,
# so these are stated once and named after their C# counterparts.
$MAGIC = [byte[]]@(0x4F, 0x53, 0x50, 0x52, 0x53, 0x50, 0x43, 0x00)   # "OSPRSPC\0"
$VERSION = 4
$FINGERPRINT_UNMEASURABLE = [uint64]::MaxValue
$HEADER_BYTES = 32
$FOOTER_BYTES = 16
$INDEX_ENTRY_BYTES = 40

if (-not (Test-Path -LiteralPath $Path)) { throw "Cache directory not found: '$Path'." }
if (-not $SourceDir) { $SourceDir = $Path }

function Test-OneCache {
    param([System.IO.FileInfo]$Cache, [string]$SourcePath)

    $result = [ordered]@{
        Name       = $Cache.Name
        Status     = 'ok'
        SourceSeen = $false
        Detail     = ''
        Ms2        = 0
        Ms1        = 0
    }

    $fs = [System.IO.File]::Open($Cache.FullName, 'Open', 'Read', 'ReadWrite')
    try {
        if ($fs.Length -lt ($HEADER_BYTES + $FOOTER_BYTES)) {
            $result.Status = 'bad'
            $result.Detail = "too small ($($fs.Length) bytes)"
            return [pscustomobject]$result
        }
        $r = [System.IO.BinaryReader]::new($fs)

        $magic = $r.ReadBytes(8)
        for ($i = 0; $i -lt 8; $i++) {
            if ($magic[$i] -ne $MAGIC[$i]) {
                $result.Status = 'bad'
                $result.Detail = 'bad magic - not a spectra cache'
                return [pscustomobject]$result
            }
        }
        $version = $r.ReadUInt32()
        if ($version -ne $VERSION) {
            $result.Status = 'bad'
            $result.Detail = "version $version, this build reads $VERSION"
            return [pscustomobject]$result
        }
        $storedSize = $r.ReadUInt64()
        $storedMtimeMs = $r.ReadInt64()
        if ($storedSize -eq $FINGERPRINT_UNMEASURABLE) {
            $result.Status = 'bad'
            $result.Detail = 'source was unmeasurable when cached - Osprey rejects this cache'
            return [pscustomobject]$result
        }
        $result.Ms2 = $r.ReadUInt32()
        $result.Ms1 = $r.ReadUInt32()
        if ($result.Ms2 -eq 0) {
            $result.Status = 'bad'
            $result.Detail = 'no MS2 records'
            return [pscustomobject]$result
        }

        # Geometry, from the EOF footer. The index is fixed-width and sits immediately
        # before the footer, so its start is completely determined by n_ms2 - which makes
        # this a truncation check that costs one seek.
        $fs.Seek(-$FOOTER_BYTES, [System.IO.SeekOrigin]::End) | Out-Null
        $ms1SectionOffset = $r.ReadInt64()
        $indexOffset = $r.ReadInt64()
        $expectedIndexOffset = $fs.Length - $FOOTER_BYTES - ($INDEX_ENTRY_BYTES * [int64]$result.Ms2)
        if ($indexOffset -ne $expectedIndexOffset) {
            $result.Status = 'bad'
            $result.Detail = ("index at $indexOffset, geometry says $expectedIndexOffset " +
                              "(truncated or n_ms2 wrong)")
            return [pscustomobject]$result
        }
        if ($ms1SectionOffset -lt $HEADER_BYTES -or $ms1SectionOffset -gt $indexOffset) {
            $result.Status = 'bad'
            $result.Detail = "MS1 section offset $ms1SectionOffset outside the body"
            return [pscustomobject]$result
        }

        # The fingerprint comparison, which is only possible while the source is here.
        $src = [System.IO.FileInfo]::new($SourcePath)
        if ($src.Exists) {
            $result.SourceSeen = $true
            if ($storedSize -ne 0) {
                $actualMtimeMs = [System.DateTimeOffset]::new($src.LastWriteTimeUtc).ToUnixTimeMilliseconds()
                if ([uint64]$src.Length -ne $storedSize -or $actualMtimeMs -ne $storedMtimeMs) {
                    $result.Status = 'stale'
                    $result.Detail = ("cache says size=$storedSize mtime=$storedMtimeMs, " +
                                      "source is size=$($src.Length) mtime=$actualMtimeMs")
                    return [pscustomobject]$result
                }
            } else {
                # Written with no fingerprint: Osprey trusts it unconditionally, here and
                # forever. Worth naming, because deleting the source freezes that choice.
                $result.Status = 'unfingerprinted'
                $result.Detail = 'cache carries no source fingerprint; it can never be checked'
            }
        } else {
            $result.Status = 'source-gone'
            $result.Detail = if ($storedSize -eq 0) { 'no fingerprint recorded' }
                             else { 'header and geometry good; fingerprint unverifiable' }
        }
        return [pscustomobject]$result
    } finally {
        $fs.Dispose()
    }
}

$caches = @(Get-ChildItem -LiteralPath $Path -Filter '*.spectra.bin' -File | Sort-Object Name)
if ($IncludePattern) {
    $before = $caches.Count
    $caches = @($caches | Where-Object { $_.Name -match $IncludePattern })
    Write-Host "  included : $($caches.Count) of $before cache(s) matching '$IncludePattern'"
}
if ($caches.Count -eq 0) { throw "No .spectra.bin found in '$Path'$(if ($IncludePattern) { " matching '$IncludePattern'" })." }

Write-Host ""
Write-Host "Validating $($caches.Count) spectra cache(s) in $Path"
if ($SourceDir -ne $Path) { Write-Host "  sources  : $SourceDir" }

$results = foreach ($c in $caches) {
    # "{stem}.spectra.bin" - strip the whole compound suffix, not one extension.
    $stem = $c.Name.Substring(0, $c.Name.Length - '.spectra.bin'.Length)
    Test-OneCache -Cache $c -SourcePath (Join-Path $SourceDir "$stem.$Extension")
}
$results = @($results)

# A source with no cache at all is the other half of "is this cohort safe to strip", and it
# is invisible from the cache side, so enumerate the sources too.
$orphanSources = @()
if (Test-Path -LiteralPath $SourceDir) {
    $srcFiles = @(Get-ChildItem -LiteralPath $SourceDir -Filter "*.$Extension" -File)
    if ($IncludePattern) { $srcFiles = @($srcFiles | Where-Object { $_.Name -match $IncludePattern }) }
    $cacheStems = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@($caches | ForEach-Object { $_.Name.Substring(0, $_.Name.Length - '.spectra.bin'.Length) }),
        [StringComparer]::OrdinalIgnoreCase)
    $orphanSources = @($srcFiles | Where-Object {
        -not $cacheStems.Contains([IO.Path]::GetFileNameWithoutExtension($_.Name))
    })
}

$byStatus = $results | Group-Object Status | Sort-Object Name
Write-Host ""
foreach ($g in $byStatus) {
    Write-Host ("  {0,-16} {1,5}" -f $g.Name, $g.Count)
}
if ($orphanSources.Count -gt 0) {
    Write-Host ("  {0,-16} {1,5}" -f 'NO CACHE', $orphanSources.Count)
}

$problems = @($results | Where-Object { $_.Status -in @('bad', 'stale') })
if ($problems.Count -gt 0 -or $ShowAll) {
    Write-Host ""
    foreach ($p in ($(if ($ShowAll) { $results } else { $problems }))) {
        Write-Host ("  [{0}] {1}{2}" -f $p.Status, $p.Name, $(if ($p.Detail) { " - $($p.Detail)" } else { '' }))
    }
}
foreach ($o in $orphanSources) {
    Write-Host ("  [NO CACHE] {0}" -f $o.Name)
}

$verified = @($results | Where-Object { $_.Status -eq 'ok' }).Count
$unverifiable = @($results | Where-Object { $_.Status -in @('source-gone', 'unfingerprinted') }).Count
$totalMs2 = ($results | Measure-Object Ms2 -Sum).Sum

Write-Host ""
Write-Host ("Total MS2 records across readable caches: {0:N0}" -f $totalMs2)

if ($problems.Count -gt 0 -or $orphanSources.Count -gt 0) {
    Write-Host ""
    Write-Host "FAILED - do NOT delete sources on this cohort." -ForegroundColor Red
    Write-Host ("  $($problems.Count) unreadable/stale cache(s), $($orphanSources.Count) source(s) with no cache.")
    exit 1
}

Write-Host ""
if ($unverifiable -gt 0) {
    Write-Host ("PASSED with $unverifiable cache(s) whose source is already gone or " +
                "unfingerprinted - those were checked structurally only.") -ForegroundColor Yellow
} else {
    Write-Host "PASSED - $verified cache(s) verified against their sources." -ForegroundColor Green
}
Write-Host "Sources whose cache verified here are safe to delete for search purposes."
Write-Host "The caches themselves are then IRREPLACEABLE - see ai/docs/osprey-large-datasets.md."
exit 0
