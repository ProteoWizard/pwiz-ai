<#
Pre-flight for cross-system .spectra.bin reuse.

Two independent checks, both cheap (reads only header + footer + index tail,
never the multi-GB body):

  1. STRUCTURE / COMPLETENESS -- magic, version, and the exact v4 size identity
         fileLength == indexOffset + nMs2*40 + 16
     (index block is 40 bytes per MS2 record; footer is 16 bytes at EOF).
     A file still uploading, or truncated in transit, fails this. Safe to run
     against the SOURCE share before copying, so partials are never pulled.

  2. FINGERPRINT -- SpectraCache.TryReadHeader rejects a cache whose recorded
     (source_size, source_mtime_ms) does not match the mzML Osprey will read.
     Checked against -MzmlDir, i.e. the mzML at RUNTIME, not the one beside it.

A rejected cache fails SILENTLY at runtime: Osprey just re-parses the mzML,
which is indistinguishable from "no cache" except by wall time. Hence this.

Header: [magic 8 "OSPRSPC\0"][version u32][source_size u64][source_mtime_ms i64]
        [n_ms2 u32][n_ms1 u32]
Footer (last 16 bytes): [ms1_section_offset i64][index_offset i64]
#>
#requires -Version 7
param(
    # Where the .spectra.bin live. Point this at the SHARE to vet caches BEFORE copying
    # them: the check reads only a few KB per file, so a partial or still-uploading cache
    # is caught without moving GBs.
    [string]$CacheDir,
    # The mzML Osprey will actually read at run time - the fingerprint is checked against
    # THESE, not against whatever sits beside the cache.
    [string]$MzmlDir,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$readme = Join-Path $PSScriptRoot 'README.md'
if (-not $MzmlDir) {
    $MzmlDir = [Environment]::GetEnvironmentVariable('OSPREY_SEAAD_DIR')
    if (-not $MzmlDir) { throw "Set `$env:OSPREY_SEAAD_DIR or pass -MzmlDir; see $readme." }
}
if (-not $CacheDir) { $CacheDir = $MzmlDir }
foreach ($d in @($CacheDir, $MzmlDir)) {
    if (-not (Test-Path $d)) { throw "Directory does not exist: '$d'. See $readme." }
}

$EXPECTED_VERSION = 4
$MAGIC = [byte[]]@(79,83,80,82,83,80,67,0)   # OSPRSPC\0
$INDEX_ENTRY_BYTES = 40
$FOOTER_BYTES = 16

$caches = @(Get-ChildItem $CacheDir -Filter '*.spectra.bin' -File -ErrorAction SilentlyContinue)
if (-not $caches) { "No .spectra.bin found in $CacheDir"; return }

$accept = 0; $incomplete = 0; $reject = 0; $pending = 0; $lockedCount = 0
foreach ($c in ($caches | Sort-Object Name)) {
    $stem = $c.Name -replace '\.spectra\.bin$', ''
    $mzml = Join-Path $MzmlDir "$stem.mzML"
    $issues = @(); $structOk = $true

    # A file still being copied is LOCKED, not corrupt -- the two must not share a
    # verdict, or an in-flight copy reads as a truncated cache.
    $fs = $null; $locked = $false
    try { $fs = [System.IO.File]::Open($c.FullName, 'Open', 'Read', 'ReadWrite') }
    catch { $locked = $true }
    if ($locked) {
        "{0,-56} {1}" -f $stem, 'LOCKED (copy in progress) -- recheck later'
        "    {0:N2} GB" -f ($c.Length/1GB)
        $lockedCount++
        continue
    }
    try {
        $br = [System.IO.BinaryReader]::new($fs)
        $magic       = $br.ReadBytes(8)
        $version     = $br.ReadUInt32()
        $storedSize  = $br.ReadUInt64()
        $storedMtime = $br.ReadInt64()
        $nMs2        = $br.ReadUInt32()
        $nMs1        = $br.ReadUInt32()

        if (@(Compare-Object $magic $MAGIC -SyncWindow 0).Count -ne 0) { $issues += 'BAD MAGIC'; $structOk = $false }
        if ($version -ne $EXPECTED_VERSION) { $issues += "VERSION $version (need $EXPECTED_VERSION)"; $structOk = $false }

        if ($structOk -and $fs.Length -ge $FOOTER_BYTES) {
            $fs.Seek(-$FOOTER_BYTES, 'End') | Out-Null
            $ms1Off = $br.ReadInt64(); $idxOff = $br.ReadInt64()
            $expect = $idxOff + [int64]$nMs2 * $INDEX_ENTRY_BYTES + $FOOTER_BYTES
            if ($idxOff -le 0 -or $idxOff -ge $fs.Length -or $ms1Off -le 0 -or $ms1Off -ge $fs.Length) {
                $issues += "footer offsets out of range (ms1=$ms1Off idx=$idxOff len=$($fs.Length))"; $structOk = $false
            } elseif ($expect -ne $fs.Length) {
                $short = $expect - $fs.Length
                $issues += ("TRUNCATED/INCOMPLETE: expected {0:N0} bytes, have {1:N0} (short {2:N0})" -f $expect, $fs.Length, $short)
                $structOk = $false
            }
        }
    } catch {
        $issues += "unreadable: $($_.Exception.Message)"; $structOk = $false
    } finally { if ($fs) { $fs.Dispose() } }

    $unverified = $false
    if ($structOk) {
        if (Test-Path $mzml) {
            $fi = Get-Item $mzml
            $actMs = [DateTimeOffset]::new($fi.LastWriteTimeUtc).ToUnixTimeMilliseconds()
            if ($storedSize -ne 0) {
                if ([uint64]$fi.Length -ne $storedSize) { $issues += "SIZE mismatch (cache expects $storedSize, mzML is $($fi.Length))" }
                if ($actMs -ne $storedMtime) {
                    $cd=[DateTimeOffset]::FromUnixTimeMilliseconds($storedMtime).UtcDateTime
                    $ad=[DateTimeOffset]::FromUnixTimeMilliseconds($actMs).UtcDateTime
                    $issues += ("MTIME mismatch (cache expects {0:yyyy-MM-dd HH:mm:ss}Z, mzML is {1:yyyy-MM-dd HH:mm:ss}Z)" -f $cd,$ad)
                }
            } else { $issues += 'cache records no fingerprint (trusted unconditionally)' }
        } else { $issues += "mzML not local yet -- fingerprint not checked"; $unverified = $true }
    }

    # PENDING is NOT a failure: the cache is structurally sound, we just cannot
    # check its fingerprint until its mzML is local. Kept distinct from REJECT so
    # a summary line is not read as N real failures.
    if (-not $structOk) { $verdict='INCOMPLETE'; $incomplete++ }
    elseif ($unverified) { $verdict='PENDING (mzML not local)'; $pending++ }
    elseif ($issues.Count -eq 0) { $verdict='ACCEPT'; $accept++ }
    else { $verdict='REJECT -> silent re-parse'; $reject++ }

    if (-not $Quiet -or $verdict -ne 'ACCEPT') {
        "{0,-56} {1}" -f $stem, $verdict
        "    v$version ms2=$nMs2 ms1=$nMs1  {0:N2} GB" -f ($c.Length/1GB)
        $issues | ForEach-Object { "    - $_" }
    }
}
""
"ACCEPT $accept   PENDING $pending   LOCKED $lockedCount   REJECT $reject   INCOMPLETE $incomplete   (of $($caches.Count))"
