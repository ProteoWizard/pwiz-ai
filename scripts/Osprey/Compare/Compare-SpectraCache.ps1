<#
Compare two Osprey .spectra.bin caches for byte parity, ignoring only the
source-file identity recorded in the header.

Purpose: verify that reading a vendor .raw directly produces exactly the same
spectra as reading the mzML msconvert wrote from that same .raw (issue #4496).
The two caches necessarily disagree about WHICH file they came from and about
nothing else, so a masked byte comparison is both the simplest and the
strictest possible check -- stronger than comparing decoded fields, because it
covers every byte the cache stores, including the index block and footer.

v4 header (little-endian, SpectraCache.cs:153-158):

    offset  size  field
    0       8     magic "OSPRSPC\0"
    8       4     version (u32)
    12      8     source_size (u64)     <-- differs by construction
    20      8     source_mtime_ms (i64) <-- differs by construction
    28      4     n_ms2 (u32)
    32      4     n_ms1 (u32)

Bytes 12..27 are the ONLY fields derived from the source file's identity
rather than its contents (ComputeSourceFingerprint, SpectraCache.cs:440-441),
so they are masked. n_ms2 / n_ms1 are deliberately NOT masked: a spectrum-count
difference is the single most likely real defect (a converter filter that drops
or reorders spectra shifts every subsequent record), and it should fail loudly.

Footer (last 16 bytes): [ms1_section_offset i64][index_offset i64] -- used here
only to name the section a mismatch falls in.

Exit code 0 = parity, 1 = differences found, 2 = unusable input.

Example:
    Compare-SpectraCache.ps1 -Reference raw\FILE.spectra.bin `
                             -Test      mzml\FILE.spectra.bin
#>
#requires -Version 7
param(
    # The cache to treat as expected, e.g. the mzML-sourced one.
    [Parameter(Mandatory=$true)][string]$Reference,
    # The cache under test, e.g. the raw-sourced one.
    [Parameter(Mandatory=$true)][string]$Test,
    # Suppress the header table; report only the verdict.
    [switch]$Quiet,
    # Do not stop at the first differing byte: scan the whole file and report HOW MANY
    # bytes differ, in what shape, and where. Slower - it cannot use the whole-chunk
    # SequenceEqual shortcut once a difference is found - so it is opt-in.
    #
    # Needed whenever the only available baseline is known to be WRONG, where "identical?"
    # is the wrong question and "the same difference as last time?" is the right one. The
    # case that motivated it: caches written before PR #4501 carry a retention-time error
    # of one ULP, so every reader change since is measured by reproducing that difference
    # exactly rather than by eliminating it. A single-ULP change to a little-endian double
    # touches only its low byte, which is why the run-length and 8-byte-straddle numbers
    # below are the ones that say "retention times only" rather than "peaks moved".
    [switch]$Census
)

$ErrorActionPreference = 'Stop'

$EXPECTED_VERSION = 4
$MAGIC            = [byte[]]@(79,83,80,82,83,80,67,0)   # OSPRSPC\0
$FINGERPRINT_OFF  = 12
$FINGERPRINT_LEN  = 16                                   # source_size + source_mtime_ms
$FOOTER_BYTES     = 16
$CHUNK            = 4MB

foreach ($p in @($Reference, $Test)) {
    if (-not (Test-Path -LiteralPath $p)) {
        Write-Host "Not found: $p" -ForegroundColor Red
        exit 2
    }
}

# Read the header and footer of one cache. Cheap - a few bytes at each end,
# never the multi-GB body.
function Read-CacheEnds([string]$path) {
    $fs = [System.IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
    try {
        $br = [System.IO.BinaryReader]::new($fs)
        $h = [pscustomobject]@{
            Path       = $path
            Length     = $fs.Length
            Magic      = $br.ReadBytes(8)
            Version    = $br.ReadUInt32()
            SourceSize = $br.ReadUInt64()
            SourceMs   = $br.ReadInt64()
            NMs2       = $br.ReadUInt32()
            NMs1       = $br.ReadUInt32()
            Ms1Offset  = [int64]0
            IndexOffset= [int64]0
        }
        if ($fs.Length -ge $FOOTER_BYTES) {
            $fs.Seek(-$FOOTER_BYTES, 'End') | Out-Null
            $h.Ms1Offset   = $br.ReadInt64()
            $h.IndexOffset = $br.ReadInt64()
        }
        return $h
    }
    finally { $fs.Dispose() }
}

$a = Read-CacheEnds $Reference
$b = Read-CacheEnds $Test

$fatal = @()
foreach ($h in @($a, $b)) {
    if (@(Compare-Object $h.Magic $MAGIC -SyncWindow 0).Count -ne 0) {
        $fatal += "$($h.Path): bad magic (not a .spectra.bin)"
    }
    elseif ($h.Version -ne $EXPECTED_VERSION) {
        $fatal += "$($h.Path): version $($h.Version), expected $EXPECTED_VERSION"
    }
}
if ($fatal) {
    $fatal | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    exit 2
}

function Format-Mtime([int64]$ms) {
    return ('{0:yyyy-MM-dd HH:mm:ss}Z' -f [DateTimeOffset]::FromUnixTimeMilliseconds($ms).UtcDateTime)
}

if (-not $Quiet) {
    "reference: $Reference"
    "test:      $Test"
    ''
    "{0,-18} {1,22} {2,22}" -f 'field', 'reference', 'test'
    "{0,-18} {1,22} {2,22}" -f 'version', $a.Version, $b.Version
    "{0,-18} {1,22:N0} {2,22:N0}" -f 'length (bytes)', $a.Length, $b.Length
    "{0,-18} {1,22:N0} {2,22:N0}" -f 'n_ms2', $a.NMs2, $b.NMs2
    "{0,-18} {1,22:N0} {2,22:N0}" -f 'n_ms1', $a.NMs1, $b.NMs1
    "{0,-18} {1,22:N0} {2,22:N0}" -f 'source size', $a.SourceSize, $b.SourceSize
    "{0,-18} {1,22} {2,22}" -f 'source mtime', (Format-Mtime $a.SourceMs), (Format-Mtime $b.SourceMs)
    ''
    '(source size/mtime differ by construction - masked in the byte comparison)'
    ''
}

# Counts first: they localize a spectrum-set difference far better than a byte
# offset does, and a count mismatch makes the offset meaningless anyway.
$countMismatch = @()
if ($a.NMs2 -ne $b.NMs2) { $countMismatch += "n_ms2 $($a.NMs2) vs $($b.NMs2) (difference $([math]::Abs([int64]$a.NMs2 - [int64]$b.NMs2)))" }
if ($a.NMs1 -ne $b.NMs1) { $countMismatch += "n_ms1 $($a.NMs1) vs $($b.NMs1) (difference $([math]::Abs([int64]$a.NMs1 - [int64]$b.NMs1)))" }
if ($countMismatch) {
    Write-Host 'DIFFERENT SPECTRUM COUNTS' -ForegroundColor Red
    $countMismatch | ForEach-Object { Write-Host "    $_" }
    Write-Host ''
    Write-Host 'The two readers did not see the same set of spectra. Check the converter'
    Write-Host 'filters before looking at the numeric content (a filter that drops or'
    Write-Host 'reorders spectra shifts every record after it).'
    exit 1
}

if ($a.Length -ne $b.Length) {
    Write-Host ('DIFFERENT LENGTHS: {0:N0} vs {1:N0} bytes (difference {2:N0})' -f `
        $a.Length, $b.Length, [math]::Abs($a.Length - $b.Length)) -ForegroundColor Red
    Write-Host 'Spectrum counts agree, so this is a per-record size difference'
    Write-Host '(peak counts within spectra, not the spectrum set).'
    # Fall through: the first differing offset still localizes it.
}

# Name the region an offset falls in, for a readable diagnosis.
function Get-Section([int64]$off, $h) {
    if ($off -lt 36)                { return 'header' }
    if ($off -ge $h.Length - $FOOTER_BYTES) { return 'footer' }
    if ($h.IndexOffset -gt 0 -and $off -ge $h.IndexOffset) {
        $rec = [math]::Floor(($off - $h.IndexOffset) / 40)
        return "MS2 index block, record $rec of $($h.NMs2)"
    }
    if ($h.Ms1Offset -gt 0 -and $off -ge $h.Ms1Offset) { return 'MS1 section' }
    return 'MS2 record body'
}

$fsA = [System.IO.File]::Open($Reference, 'Open', 'Read', 'ReadWrite')
$fsB = [System.IO.File]::Open($Test,      'Open', 'Read', 'ReadWrite')
try {
    $bufA = [byte[]]::new($CHUNK)
    $bufB = [byte[]]::new($CHUNK)
    [int64]$pos = 0
    $firstDiff = [int64]-1
    # Census state. Offsets arrive in ascending order, so runs and distinct 8-byte slots
    # are countable with O(1) memory - no offset list, which matters when the caller points
    # this at two genuinely unrelated files.
    [int64]$diffBytes = 0
    [int64]$runs = 0
    [int64]$straddling = 0
    [int64]$slots = 0
    [int64]$prevDiff = -2
    [int64]$runStart = -1
    [int64]$lastSlot = -1
    $sections = [ordered]@{}
    $common = [math]::Min($a.Length, $b.Length)

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $nextReport = 10
    while ($pos -lt $common -and ($Census -or $firstDiff -lt 0)) {
        $want = [int][math]::Min([int64]$CHUNK, $common - $pos)
        $gotA = $fsA.Read($bufA, 0, $want)
        $gotB = $fsB.Read($bufB, 0, $want)
        if ($gotA -ne $gotB) { throw "short read at $pos ($gotA vs $gotB)" }
        if ($gotA -le 0) { break }

        # Mask the source fingerprint, which lives entirely in the first chunk.
        if ($pos -eq 0) {
            for ($i = $FINGERPRINT_OFF; $i -lt $FINGERPRINT_OFF + $FINGERPRINT_LEN; $i++) {
                $bufA[$i] = 0
                $bufB[$i] = 0
            }
        }

        # Whole-chunk compare in .NET; only descend to a per-byte scan on the
        # one chunk that actually differs.
        $same = $true
        if ($gotA -eq $CHUNK) {
            $same = [System.Linq.Enumerable]::SequenceEqual($bufA, $bufB)
        }
        else {
            for ($i = 0; $i -lt $gotA; $i++) {
                if ($bufA[$i] -ne $bufB[$i]) { $same = $false; break }
            }
        }
        if (-not $same) {
            if (-not $Census) {
                for ($i = 0; $i -lt $gotA; $i++) {
                    if ($bufA[$i] -ne $bufB[$i]) { $firstDiff = $pos + $i; break }
                }
            }
            else {
                for ($i = 0; $i -lt $gotA; $i++) {
                    if ($bufA[$i] -eq $bufB[$i]) { continue }
                    $off = $pos + $i
                    if ($firstDiff -lt 0) { $firstDiff = $off }
                    $diffBytes++

                    # A run is a maximal span of consecutive differing bytes. Close the
                    # previous one before opening a new one, so the straddle test sees a
                    # complete span.
                    if ($off -ne $prevDiff + 1) {
                        if ($runStart -ge 0 -and [math]::Floor($runStart / 8) -ne [math]::Floor($prevDiff / 8)) {
                            $straddling++
                        }
                        $runs++
                        $runStart = $off
                        $sec = Get-Section $off $a
                        if ($sections.Contains($sec)) { $sections[$sec] = $sections[$sec] + 1 }
                        else { $sections[$sec] = 1 }
                    }
                    $prevDiff = $off

                    $slot = [math]::Floor($off / 8)
                    if ($slot -ne $lastSlot) { $slots++; $lastSlot = $slot }
                }
            }
        }

        $pos += $gotA
        if (-not $Quiet -and $sw.Elapsed.TotalSeconds -ge $nextReport) {
            Write-Host ('    compared {0:N0} of {1:N0} bytes ({2:P0})' -f $pos, $common, ($pos / $common))
            $nextReport += 10
        }
    }
    $sw.Stop()

    if ($Census -and $firstDiff -ge 0) {
        # Close the final run so its straddle is counted like every other.
        if ($runStart -ge 0 -and [math]::Floor($runStart / 8) -ne [math]::Floor($prevDiff / 8)) {
            $straddling++
        }
        Write-Host ('BYTE CENSUS: {0:N0} differing bytes of {1:N0} compared' -f $diffBytes, $common) -ForegroundColor Yellow
        Write-Host ('    runs of consecutive differing bytes : {0:N0}' -f $runs)
        Write-Host ('    runs straddling an 8-byte boundary  : {0:N0}' -f $straddling)
        Write-Host ('    distinct 8-byte slots affected      : {0:N0}' -f $slots)
        Write-Host ('    first differing offset              : {0:N0} (0x{0:X}), {1}' -f $firstDiff, (Get-Section $firstDiff $a))
        Write-Host '    differing runs by section:'
        foreach ($k in $sections.Keys) {
            Write-Host ('      {0,-40} {1,10:N0}' -f $k, $sections[$k])
        }
        Write-Host ''
        Write-Host '    Isolated single-byte runs that never straddle an 8-byte boundary mean'
        Write-Host '    one low byte per double changed, i.e. a one-ULP numeric difference and'
        Write-Host '    not a structural one. Reconcile the count against the fields you expect'
        Write-Host '    to differ before concluding anything - a retention time stored in both'
        Write-Host '    a record and the trailing index counts twice.'
        Write-Host ('    compared in {0:N1}s' -f $sw.Elapsed.TotalSeconds)
        exit 1
    }
    if ($firstDiff -ge 0) {
        Write-Host ('BYTE MISMATCH at offset {0:N0} (0x{0:X})' -f $firstDiff) -ForegroundColor Red
        Write-Host ('    reference: {0}' -f (Get-Section $firstDiff $a))
        Write-Host ('    test:      {0}' -f (Get-Section $firstDiff $b))
        exit 1
    }
    if ($a.Length -ne $b.Length) {
        Write-Host ('IDENTICAL for the first {0:N0} bytes, then one file ends' -f $common) -ForegroundColor Red
        exit 1
    }

    Write-Host ('PARITY: {0:N0} bytes identical (source fingerprint masked)' -f $a.Length) -ForegroundColor Green
    Write-Host ('    n_ms2={0:N0}  n_ms1={1:N0}  compared in {2:N1}s' -f $a.NMs2, $a.NMs1, $sw.Elapsed.TotalSeconds)
    exit 0
}
finally {
    $fsA.Dispose()
    $fsB.Dispose()
}
