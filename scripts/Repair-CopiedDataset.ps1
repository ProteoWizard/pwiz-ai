<#
.SYNOPSIS
    Find files whose local copy does not match the source by CONTENT, re-copy them, and verify.

.DESCRIPTION
    Written for a failure that ordinary copy tools cannot see. 48 of 82 SEA-AD mzML copied to a
    local disk ended up with the correct length, the correct timestamp and normal attributes,
    while most of their content was zeros - the first 52 bytes overwritten with NTFS metadata
    and everything past some offset nulled to the end. Sizes matched the source EXACTLY, so
    robocopy, xcopy and Explorer all consider those files up to date and copy nothing.

    So matching here is content-based:

      1. missing locally, or a different length          (instant)
      2. mzML structure: must start '<?xml' and end '</indexedmzML>'   (two small reads)
      3. sampled byte comparison at the same offsets on both sides     (a few MB per file)
      4. -Full: SHA256 of both sides                     (definitive, reads everything)

    Level 3 is the default because it catches whole-region loss - the observed failure - for a
    few MB of reads rather than 670 GB. Use -Full when you want proof rather than a strong
    indication.

    Copies run through robocopy /IM /IS /IT /J. /IM is essential and is the flag whose absence
    caused a full night's misdiagnosis: a file rewritten in place keeps its size and write time
    but gets a new NTFS CHANGE time, which robocopy classes "modified" and does NOT copy by
    default. /J keeps the copy unbuffered, so the verification that follows reads the platter
    rather than the page cache the copy just filled - a buffered copy makes the check verify
    RAM against RAM. /R:2 /W:5 retries a transient network blip instead of failing the batch.

.PARAMETER Source
    Source directory (the authoritative copy).

.PARAMETER Destination
    Local directory to check and repair.

.PARAMETER Include
    Filename patterns to consider. Defaults to the mzML and the Osprey spectra caches.

.PARAMETER Samples
    Chunks per file for the sampled comparison (default 64, 64 KB each).

.PARAMETER Full
    Compare by SHA256 over the whole file instead of sampling. Slow and definitive.

.PARAMETER WhatIfOnly
    Report what does not match and stop, copying nothing.

.PARAMETER VerifyOnly
    Re-check without copying. Run this LATER, in a separate session, for the strongest
    verification: a check immediately after a copy can be answered out of the OS file cache,
    which is exactly the layer suspected of losing the writes in the first place.

.EXAMPLE
    .\Repair-CopiedDataset.ps1 -Source M:\...\mzml -Destination D:\...\mzml -WhatIfOnly
    .\Repair-CopiedDataset.ps1 -Source M:\...\mzml -Destination D:\...\mzml
    .\Repair-CopiedDataset.ps1 -Source M:\...\mzml -Destination D:\...\mzml -VerifyOnly -Full
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Destination,
    [string[]]$Include = @('*.mzML', '*.bin'),
    # Guarded because 0 is a natural guess for "skip sampling" and an unset wrapper variable
    # binds to 0. Compare-Sampled's loop would then never execute, every file would compare
    # equal, and the script would print "Everything matches." over a corrupt dataset.
    [ValidateRange(1, 4096)][int]$Samples = 64,
    [switch]$Full,
    [switch]$WhatIfOnly,
    [switch]$VerifyOnly,
    [string]$ReportCsv
)

$ErrorActionPreference = 'Stop'
$CHUNK = 64KB

function Test-MzmlStructure([string]$path) {
    # A valid indexedmzML opens with the XML declaration and closes with </indexedmzML>.
    # Both ends matter: the observed damage destroyed the header AND nulled the trailing
    # index, so a head-only check would pass files whose offset index is gone.
    $fs = [IO.File]::OpenRead($path)
    try {
        $head = New-Object byte[] 5
        [void]$fs.Read($head, 0, 5)
        if ([Text.Encoding]::ASCII.GetString($head) -ne '<?xml') { return 'bad header' }
        $n = [int][Math]::Min([long]260, $fs.Length)   # [long]: these files exceed int range
        [void]$fs.Seek(-$n, 'End')
        $tail = New-Object byte[] $n
        [void]$fs.Read($tail, 0, $n)
        if ([Text.Encoding]::ASCII.GetString($tail) -notmatch 'indexedmzML>') { return 'bad trailer' }
    } finally {
        $fs.Dispose()
    }
    return $null
}

function Compare-Sampled([string]$a, [string]$b, [int]$samples) {
    # Same offsets on both sides, spread across the file, with the first and last chunk always
    # included. Whole-region loss cannot hide from this; a single flipped byte can.
    $fa = [IO.File]::OpenRead($a)
    $fb = [IO.File]::OpenRead($b)
    try {
        $len = $fa.Length
        $bufA = New-Object byte[] $CHUNK
        $bufB = New-Object byte[] $CHUNK
        # Spread across [0, len - CHUNK] INCLUSIVE so the last chunk really is sampled. The
        # previous form used i/samples, whose highest offset was len*(samples-1)/samples - it
        # left the final len/samples bytes unread (73.7 MB on a 4.61 GB file), which is exactly
        # where the damage this script hunts for lives. mzML survived that on the trailing-index
        # check, but *.bin is in the default -Include and gets no structure check at all, so a
        # spectra cache with a nulled tail passed as matching.
        $denom = [Math]::Max(1, $samples - 1)
        $last = [Math]::Max([long]0, $len - $CHUNK)
        for ($i = 0; $i -lt $samples; $i++) {
            $off = [long]([double]$last * $i / $denom)
            [void]$fa.Seek($off, 'Begin'); [void]$fb.Seek($off, 'Begin')
            $na = $fa.Read($bufA, 0, $CHUNK)
            $nb = $fb.Read($bufB, 0, $CHUNK)
            if ($na -ne $nb) { return "short read at $off" }
            for ($j = 0; $j -lt $na; $j++) {
                if ($bufA[$j] -ne $bufB[$j]) { return ("differs at byte {0:N0}" -f ($off + $j)) }
            }
        }
    } finally {
        $fa.Dispose(); $fb.Dispose()
    }
    return $null
}

function Get-Mismatch([IO.FileInfo]$src, [string]$dst) {
    if (-not (Test-Path -LiteralPath $dst)) { return 'missing' }
    $d = Get-Item -LiteralPath $dst
    if ($d.Length -ne $src.Length) {
        return ('size {0:N0} vs {1:N0}' -f $d.Length, $src.Length)
    }
    if ($src.Extension -eq '.mzML') {
        $s = Test-MzmlStructure $dst
        if ($s) { return $s }
    }
    if ($Full) {
        $ha = (Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash
        $hb = (Get-FileHash -LiteralPath $src.FullName -Algorithm SHA256).Hash
        if ($ha -ne $hb) { return 'sha256 differs' }
        return $null
    }
    return (Compare-Sampled $src.FullName $dst $Samples)
}

if (-not (Test-Path $Source)) { throw "Source not found: $Source" }
# Only when we are actually going to copy. Creating it up front meant a typo'd -Destination
# under -VerifyOnly/-WhatIfOnly silently made the empty directory, found nothing in it, and
# reported "82 of 82 do not match" - which reads as total data loss on the destination.
if (-not ($VerifyOnly -or $WhatIfOnly) -and -not (Test-Path $Destination)) {
    New-Item -ItemType Directory -Force $Destination | Out-Null
}
if (-not (Test-Path $Destination)) {
    throw "Destination does not exist: $Destination"
}

$files = @()
foreach ($pat in $Include) { $files += Get-ChildItem -LiteralPath $Source -Filter $pat -File }
$files = $files | Sort-Object Name

Write-Host ("Source      : {0}" -f $Source)
Write-Host ("Destination : {0}" -f $Destination)
Write-Host ("Files       : {0}   mode: {1}" -f $files.Count, $(if ($Full) { 'full SHA256' } else { "sampled x$Samples" }))
Write-Host ''

$rows = @()
$bad = @()
$i = 0
foreach ($f in $files) {
    $i++
    Write-Progress -Activity 'Checking' -Status $f.Name -PercentComplete (100 * $i / $files.Count)
    # $ErrorActionPreference is 'Stop', so without this one transiently locked file - an
    # indexer, AV, a -Full Get-FileHash failure - aborts the whole loop and throws away every
    # result gathered so far, including the CSV. An unreadable file IS a mismatch; record it.
    try {
        $why = Get-Mismatch $f (Join-Path $Destination $f.Name)
    } catch {
        $why = "check failed: $($_.Exception.Message)"
    }
    $rows += [pscustomobject]@{ Name = $f.Name; Bytes = $f.Length; Mismatch = $why }
    if ($why) {
        $bad += $f
        Write-Host ('  MISMATCH  {0,-62} {1}' -f $f.Name, $why)
    }
}
Write-Progress -Activity 'Checking' -Completed

Write-Host ''
Write-Host ("{0} of {1} do not match ({2:N1} GB to re-copy)" -f $bad.Count, $files.Count,
    (($bad | Measure-Object Length -Sum).Sum / 1GB))

# Outcome per file, filled in by the copy loop below. The CSV is written LAST so it records
# what actually happened: written before the copy it could only ever list the pre-copy
# mismatches, so a run that repaired 47 of 48 produced a report indistinguishable from one that
# repaired none - and the CSV is the only machine-readable output.
$outcome = @{}

function Write-ReportCsv {
    if (-not $ReportCsv) { return }
    $rows |
        Select-Object Name, Bytes, Mismatch,
            @{ Name = 'Outcome'; Expression = {
                if ($outcome.ContainsKey($_.Name)) { $outcome[$_.Name] }
                elseif ($_.Mismatch) { 'not attempted' }
                else { 'matched' } } } |
        Export-Csv $ReportCsv -NoTypeInformation
    Write-Host "report: $ReportCsv"
}

if ($VerifyOnly -or $WhatIfOnly) {
    Write-ReportCsv
    if ($bad.Count -eq 0) { Write-Host 'Everything matches.' }
    return
}
if ($bad.Count -eq 0) { Write-ReportCsv; Write-Host 'Nothing to copy.'; return }

Write-Host ''
Write-Host 'Copying with robocopy /IM /IS /IT /J (unbuffered; /IM is what copies a file whose'
Write-Host 'content changed under an unchanged size and write time)...'
$copied = 0
$failed = @()
foreach ($f in $bad) {
    Write-Host ('  {0}' -f $f.Name)
    # /IM IS THE FLAG THIS SCRIPT EXISTS FOR. A file rewritten in place keeps its length and
    # its LastWriteTime but gets a NEW NTFS change time, which is robocopy's "modified" class -
    # and "modified" is a SKIP class: robocopy /? says "otherwise the same. These files are not
    # copied by default; specify /IM". So the default invocation reports Copied 0 / Skipped 1 /
    # exit 0 and leaves the damage in place. Measured on a file damaged exactly that way:
    #
    #   /J            Copied 0  exit 0  destination unchanged
    #   /IS /IT /J    Copied 0  exit 0  destination unchanged   <- /IS is "Include Same", wrong class
    #   /IM /J        Copied 1  exit 1  destination repaired
    #
    # An earlier fix here mistook that documented behaviour for robocopy silently refusing to
    # work and swapped in Copy-Item. That was wrong twice: it enshrined a false rule, and
    # Copy-Item is BUFFERED, so the verification below reads the page cache the copy just
    # filled and stops being evidence that anything reached the platter. /J keeps the copy
    # unbuffered, which is the whole basis of the check. /R:2 /W:5 rides out a network blip
    # instead of failing the batch.
    & robocopy $Source $Destination $f.Name /IM /IS /IT /J /R:2 /W:5 /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) {
        $failed += [pscustomobject]@{ Name = $f.Name; Why = "robocopy exit $LASTEXITCODE" }
        $outcome[$f.Name] = "copy failed (robocopy exit $LASTEXITCODE)"
        continue
    }
    try {
        $why = Get-Mismatch $f (Join-Path $Destination $f.Name)
    } catch {
        $why = "check failed: $($_.Exception.Message)"
    }
    if ($why) {
        $failed += [pscustomobject]@{ Name = $f.Name; Why = "still bad after copy: $why" }
        $outcome[$f.Name] = "still bad after copy: $why"
    } else {
        $copied++
        $outcome[$f.Name] = 'repaired'
    }
}
Write-ReportCsv

Write-Host ''
Write-Host ("re-copied and verified : {0}" -f $copied)
Write-Host ("still failing          : {0}" -f $failed.Count)
if ($failed.Count) {
    # -Width: the default 120 truncates exactly the exception text this table exists to show.
    $failed | Format-Table -AutoSize | Out-String -Width 4096 | Write-Host
    $neverRan = @($failed | Where-Object { $_.Why -like 'still bad after copy:*' }).Count
    if ($copied -eq 0 -and $neverRan -eq $failed.Count -and $failed.Count -gt 1) {
        # Every file failing IDENTICALLY, with the copy engine reporting success each time, is
        # the signature of a copy that never ran - a failing disk loses some writes, not all of
        # them the same way. Distinguish it from a copy that ran and errored: those rows say
        # "robocopy exit N" instead, and are not counted here.
        Write-Host 'Every file failed the SAME way and the copy engine reported success each time.'
        Write-Host 'That is a copy that did not run, not failing hardware. Re-run one file with'
        Write-Host 'robocopy /L /V to see its class - "modified" means /IM is missing.'
    } else {
        Write-Host 'A file that fails verification straight after an unbuffered (/J) copy points at'
        Write-Host 'the destination hardware rather than at the copy.'
    }
}
Write-Host ''
Write-Host 'For the strongest check, evict the cache first and then re-verify:'
Write-Host '  pwsh -File ai/scripts/Osprey/SEA-AD/Clear-StandbyCache.ps1'
Write-Host '  ... -VerifyOnly -Full'
Write-Host 'A new SESSION is not enough - the Windows file cache is machine-wide and outlives the'
Write-Host 'process that filled it, so a fresh pwsh still reads the bytes the copy left in RAM.'

# Exit non-zero when anything is still broken, so a wrapper cannot start a multi-hour run on
# unrepaired input. Every path used to return 0, including "still failing: 48".
if ($failed.Count) { exit 1 }
