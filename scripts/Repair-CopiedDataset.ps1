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

    Copies run through robocopy /J (unbuffered I/O), which is the recommended mode for very
    large files: it bypasses the cache manager, so a copy cannot sit in RAM being counted as
    written. /R:2 /W:5 retries a transient network blip instead of failing the batch.

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
    [int]$Samples = 64,
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
        for ($i = 0; $i -lt $samples; $i++) {
            $off = [long]([double]$len * $i / $samples)
            if ($off -gt $len - $CHUNK) { $off = [Math]::Max([long]0, $len - $CHUNK) }
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
if (-not (Test-Path $Destination)) { New-Item -ItemType Directory -Force $Destination | Out-Null }

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
    $why = Get-Mismatch $f (Join-Path $Destination $f.Name)
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

if ($ReportCsv) {
    $rows | Export-Csv $ReportCsv -NoTypeInformation
    Write-Host "report: $ReportCsv"
}

if ($VerifyOnly -or $WhatIfOnly) {
    if ($bad.Count -eq 0) { Write-Host 'Everything matches.' }
    return
}
if ($bad.Count -eq 0) { Write-Host 'Nothing to copy.'; return }

Write-Host ''
Write-Host 'Copying with robocopy /J (unbuffered)...'
$copied = 0
$failed = @()
foreach ($f in $bad) {
    Write-Host ('  {0}' -f $f.Name)
    # /J unbuffered, /R:2 /W:5 retry, /NFL /NDL /NJH /NJS quiet. robocopy exit codes < 8 are
    # success variants; >= 8 is a real failure.
    & robocopy $Source $Destination $f.Name /J /R:2 /W:5 /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) {
        $failed += [pscustomobject]@{ Name = $f.Name; Why = "robocopy exit $LASTEXITCODE" }
        continue
    }
    $why = Get-Mismatch $f (Join-Path $Destination $f.Name)
    if ($why) {
        $failed += [pscustomobject]@{ Name = $f.Name; Why = "still bad after copy: $why" }
    } else {
        $copied++
    }
}

Write-Host ''
Write-Host ("re-copied and verified : {0}" -f $copied)
Write-Host ("still failing          : {0}" -f $failed.Count)
if ($failed.Count) {
    $failed | Format-Table -AutoSize | Out-String | Write-Host
    Write-Host 'A file that fails verification straight after an unbuffered copy points at the'
    Write-Host 'destination hardware rather than at the copy.'
}
Write-Host ''
Write-Host 'Re-run later with -VerifyOnly (ideally -Full) in a fresh session: a check made right'
Write-Host 'after writing can be satisfied from the OS cache, which is the layer under suspicion.'
