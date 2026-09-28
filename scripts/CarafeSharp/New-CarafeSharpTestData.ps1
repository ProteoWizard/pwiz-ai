<#
.SYNOPSIS
    Assemble and zip the CarafeSharp test-data packages for the Panorama perftests folder.
.DESCRIPTION
    Builds the packages that pwiz_tools/CarafeSharp/testdata.json describes, from the developer's
    local Carafe reference runs and the durable staging copy of the stage-1 and library references:

      carafesharp-testfiles-v1         Stellar Carafe 2.2 references, stage-1 builds, library references
      carafesharp-testfiles-astral-v1  Astral Carafe 2.2 references (optional; TestCategory=Astral)
      carafesharp-export-v1            the Stellar _21 Osprey training export

    testdata.json is the one definition of what a package holds: its "contents" entries (files, or
    folders ending in '/'), each folder's "include" and "exclude" name patterns, and the package's
    own "exclude". CarafeSharp.Test reads the same file, so the tests and the zips cannot disagree.

    Each package is one top folder named like its zip, because pwiz_tools/Osprey/Regression/
    RegressionData.ps1 extracts <zip> to <Downloads>/Perftests/<zip base name>. Large inputs are
    hardlinked into the staging tree on the same volume, so assembling needs no extra disk. Only our
    own stage-1 command.txt files are rewritten (to {DATA}/ paths). Carafe's own .carafe.sig,
    parameter.txt and logs are packaged byte for byte, because the sig carries a hash.

    MANIFEST.sha256 lists every file with its SHA-256 and is the zip's LAST entry. Extraction writes
    entries in order, so an extraction that stopped part way has no marker, and the tests refuse the
    folder instead of reading a truncated file.

    A package is never republished under the same name: extraction never overwrites, so a changed
    package needs a new version suffix.
.PARAMETER Package
    A package id from testdata.json (testfiles, astral, export), or All (default).
.PARAMETER PackageList
    testdata.json. Default: the sibling pwiz checkout's pwiz_tools/CarafeSharp/testdata.json.
.PARAMETER StagingRoot
    Where the package trees are assembled. Default D:\test\carafesharp-testdata-pkg.
.PARAMETER OutputDir
    Where the zips are written. Default D:\test\carafesharp-testdata-zips.
.PARAMETER ExampleData
    The Osprey example_test_data folder holding the Carafe reference runs.
.PARAMETER ReferenceStaging
    The durable copy of the stage-1 builds, fixtures and library references.
.PARAMETER TrainingExport
    The Stellar _21 training export parquet for carafesharp-export-v1 (regenerate it from .raw
    with the landed Osprey before publishing).
.PARAMETER ExportSource
    What Osprey read to write the training export: raw (the default, and the only kind to publish)
    or mzML (the June export, for dry runs).
.PARAMETER StageOnly
    Assemble and verify the trees, but do not zip.
#>
param(
    [string]$Package = 'All',
    [string]$PackageList,
    [string]$StagingRoot = 'D:\test\carafesharp-testdata-pkg',
    [string]$OutputDir = 'D:\test\carafesharp-testdata-zips',
    [string]$ExampleData = 'D:\GitHub-Repo\maccoss\osprey\example_test_data',
    [string]$ReferenceStaging = 'D:\test\carafesharp-testdata-staging',
    [string]$TrainingExport = 'D:\test\osprey-runs\carafe-june-train\Ste-2024-12-02_HeLa_4mz_sDIA_400-900_21.training.parquet',
    # What Osprey read to write the export. Publish only a .raw export; mzML is for dry runs.
    [ValidateSet('raw', 'mzML')] [string]$ExportSource = 'raw',
    [switch]$StageOnly
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$aiRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
if (-not $PackageList) {
    $PackageList = Join-Path (Split-Path -Parent $aiRoot) 'pwiz/pwiz_tools/CarafeSharp/testdata.json'
}
if (-not (Test-Path -LiteralPath $PackageList)) { throw "testdata.json not found: $PackageList (pass -PackageList)" }
$packageDefinitions = Get-Content -Raw -LiteralPath $PackageList | ConvertFrom-Json

# Where each package-relative prefix comes from on this machine, longest prefix first.
$sources = @{
    testfiles = [ordered]@{
        'stellar/'            = Join-Path $ExampleData 'stellar'
        'stage1/'             = Join-Path $ReferenceStaging 'stage1'
        'library-references/' = Join-Path $ReferenceStaging 'library-references'
    }
    astral = [ordered]@{
        'astral/' = Join-Path $ExampleData 'astral'
    }
    export = [ordered]@{
        "stellar/$(Split-Path -Leaf $TrainingExport)" = $TrainingExport
    }
}

# Carafe-written files where an absolute path is expected and relocated by the tests.
$pathTolerantFiles = @('*.carafe.sig', 'parameter.txt', 'carafe_log.txt', 'carafe_settings.json', 'meta.json', 'log.txt')

# Our stage-1 command.txt files name inputs by absolute path on the developer's machine; make them
# package-relative. Copied, not linked, because they are rewritten.
$stage1PathMap = [ordered]@{
    'D:/GitHub-Repo/maccoss/osprey/example_test_data/stellar/' = '{DATA}/stellar/'
    'D:/GitHub-Repo/maccoss/misc_scripts/files-for-testing/' = '{DATA}/stage1/'
    'D:/Dev/ai/.tmp/sessions/20260923-carafesharp/fixtures/' = '{DATA}/stage1/fixtures/'
}

$readmes = @{
    testfiles = @"
Unpack into <Downloads>\Perftests\ (or set CARAFESHARP_TESTDATA to the folder that holds it); the
CarafeSharp.Test parity tests find it there. See pwiz_tools/CarafeSharp/docs/04-testing.md.

stellar/carafe-osprey-entrapment   Carafe 2.2.0 Workflow 5 on Stellar HeLa (Osprey search engine), with
                                   shuffle entrapment, 2026-06-30, before the fork's similarity gate. The
                                   oracle for stage-1 (digest), prediction, library and fine-tune parity.
stellar/carafe-osprey              The same workflow without entrapment: its training files and
                                   predictions, a second fine-tune reference.
stage1/builds                      12 stage-1 reference builds (javac build of Carafe origin/main); their
                                   command.txt files use {DATA}/ for paths inside this package.
stage1/fixtures, *.fasta           Their inputs (the mouse FASTA is UniProt, CC BY 4.0).
library-references                 Carafe origin/main library references (m3: NoCut every-50 peptides and
                                   300 trypsin proteins; carafe_main_varmod: variable modifications).

Carafe's own files (.carafe.sig, parameter.txt, logs) are unmodified, so they name paths on the
machine that made them; the tests relocate those. The spectra came from mzML, because Carafe cannot
read .raw. MANIFEST.sha256 lists every file and is the zip's last entry.
"@
    astral = @"
Optional. Carafe 2.2.0 Workflow 5 on Astral HeLa (Osprey search engine) with shuffle entrapment:
the digests and pairing manifests, the initial and fine-tuned libraries and the files that produced
them (parquet predictions, parameter.txt, training files, fine-tuned models, metrics). It backs the
CarafeSharp.Test tests in TestCategory=Astral. The human FASTA is UniProt (CC BY 4.0). Unpack into
<Downloads>\Perftests\. MANIFEST.sha256 lists every file and is the zip's last entry.
"@
    export = @"
The Osprey training export (--training-export) of Stellar HeLa run _21, read from $ExportSource, that the
masking and isolated fine-tune tests start from. Kept apart from the Carafe references because it
changes whenever Osprey's export does. Unpack into <Downloads>\Perftests\. MANIFEST.sha256 lists
every file and is the zip's last entry.
"@
}

function Get-Source([string]$id, [string]$relative) {
    foreach ($prefix in $sources[$id].Keys) {
        if ($relative -eq $prefix -or ($prefix.EndsWith('/') -and $relative.StartsWith($prefix))) {
            $rest = $relative.Substring($prefix.Length).Replace('/', [IO.Path]::DirectorySeparatorChar)
            return $(if ($rest) { Join-Path $sources[$id][$prefix] $rest } else { $sources[$id][$prefix] })
        }
    }
    throw "No source on this machine for $id/$relative"
}

function Test-Wildcards([string]$name, $patterns) {
    foreach ($p in @($patterns)) { if ($p -and $name -like $p) { return $true } }
    return $false
}

function Add-File([string]$source, [string]$dest) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
    if (Test-Path -LiteralPath $dest) { return }
    if ((Split-Path -Leaf $dest) -eq 'command.txt') {
        $text = [IO.File]::ReadAllText($source).Replace('\', '/')
        foreach ($key in $stage1PathMap.Keys) { $text = $text.Replace($key, $stage1PathMap[$key]) }
        if ($text -match '(?m)^[A-Za-z]:/') { throw "Unmapped absolute path left in $source" }
        [IO.File]::WriteAllText($dest, $text)
    } elseif ((Split-Path -Qualifier $source) -eq (Split-Path -Qualifier $dest)) {
        New-Item -ItemType HardLink -Path $dest -Target $source | Out-Null
    } else {
        Copy-Item -LiteralPath $source $dest
    }
}

function Add-Contents($definition, [string]$root) {
    foreach ($entry in $definition.contents) {
        $source = Get-Source $definition.id $entry.path
        $dest = Join-Path $root ($entry.path.Replace('/', [IO.Path]::DirectorySeparatorChar))
        if ($entry.path.EndsWith('/')) {
            if (-not (Test-Path -LiteralPath $source -PathType Container)) { throw "Missing package input folder: $source" }
            $kept = 0
            foreach ($file in Get-ChildItem -LiteralPath $source -File -Recurse) {
                if (Test-Wildcards $file.Name $definition.exclude) { continue }
                if ($entry.exclude -and (Test-Wildcards $file.Name $entry.exclude)) { continue }
                if ($entry.include -and -not (Test-Wildcards $file.Name $entry.include)) { continue }
                Add-File $file.FullName (Join-Path $dest $file.FullName.Substring($source.Length).TrimStart('\', '/'))
                $kept++
            }
            if ($kept -eq 0) { throw "No files kept from $source for $($entry.path)" }
        } else {
            if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Missing package input: $source" }
            Add-File $source $dest
        }
    }
}

function Test-AbsolutePaths([string]$root) {
    $hits = Get-ChildItem -LiteralPath $root -Recurse -File |
        Where-Object { $_.Length -lt 50MB -and $_.Extension -in @('.txt', '.json', '.tsv', '.sig', '.csv') } |
        Where-Object { $name = $_.Name; -not ($pathTolerantFiles | Where-Object { $name -like $_ }) } |
        Select-String -Pattern '[A-Za-z]:[\\/](GitHub-Repo|Dev|test|Users)' -List
    foreach ($hit in $hits) { Write-Host "  absolute path: $($hit.Path):$($hit.LineNumber)" -ForegroundColor Yellow }
    return @($hits).Count
}

function Get-PackageFiles([string]$root) {
    # Ordinal order, so the manifest and the zip list files the same way on every machine.
    $files = @(Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object { $_.Name -ne 'MANIFEST.sha256' -or $_.DirectoryName -ne $root })
    [Array]::Sort($files, [Comparison[IO.FileInfo]] { param($a, $b) [string]::CompareOrdinal($a.FullName, $b.FullName) })
    return $files
}

function Get-RelativePath([string]$root, [string]$path) {
    return $path.Substring($root.Length).TrimStart('\', '/').Replace('\', '/')
}

function Write-Manifest([string]$root) {
    $manifest = Join-Path $root 'MANIFEST.sha256'
    if (Test-Path -LiteralPath $manifest) { Remove-Item -LiteralPath $manifest }
    $lines = Get-PackageFiles $root | ForEach-Object {
        '{0}  {1}' -f (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToLowerInvariant(), (Get-RelativePath $root $_.FullName)
    }
    [IO.File]::WriteAllLines($manifest, [string[]]$lines)
    return @($lines).Count
}

function New-PackageZip([string]$root, [string]$zip) {
    # Every file under the top folder, then MANIFEST.sha256 last (ZipFile.CreateFromDirectory would
    # put the top folder's own files, the marker among them, first).
    $top = Split-Path -Leaf $root
    $level = [IO.Compression.CompressionLevel]::Optimal
    $archive = [IO.Compression.ZipFile]::Open($zip, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($file in Get-PackageFiles $root) {
            [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $file.FullName, "$top/$(Get-RelativePath $root $file.FullName)", $level)
        }
        [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, (Join-Path $root 'MANIFEST.sha256'), "$top/MANIFEST.sha256", $level)
    } finally {
        $archive.Dispose()
    }
    $check = [IO.Compression.ZipFile]::OpenRead($zip)
    try {
        $last = $check.Entries[$check.Entries.Count - 1].FullName
    } finally {
        $check.Dispose()
    }
    if ($last -ne "$top/MANIFEST.sha256") { throw "$zip ends with $last, not the manifest" }
}

function Complete-Package([string]$name, [string]$root) {
    $absolute = Test-AbsolutePaths $root
    if ($absolute -gt 0) { throw "$name has $absolute file(s) with absolute paths outside Carafe's own files" }
    $count = Write-Manifest $root
    $bytes = (Get-ChildItem -LiteralPath $root -Recurse -File | Measure-Object Length -Sum).Sum
    Write-Host ("{0}: {1} files, {2:N2} GB staged" -f $name, $count, ($bytes / 1GB)) -ForegroundColor Green
    if ($StageOnly) { return }
    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
    $zip = Join-Path $OutputDir "$name.zip"
    if (Test-Path -LiteralPath $zip) { throw "$zip exists; a published package is never overwritten (bump the version)" }
    $start = Get-Date
    New-PackageZip $root $zip
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $zip).Hash.ToLowerInvariant()
    $size = (Get-Item -LiteralPath $zip).Length
    Write-Host ("{0}.zip: {1:N0} bytes, SHA-256 {2}, {3:F1} min" -f $name, $size, $hash, ((Get-Date) - $start).TotalMinutes) -ForegroundColor Green
    [ordered]@{ name = $name; file = "$name.zip"; size = $size; sha256 = $hash } | ConvertTo-Json |
        Set-Content (Join-Path $OutputDir "$name.json")
}

$stamp = Get-Date -Format 'yyyy-MM-dd'
$selected = @($packageDefinitions.packages | Where-Object { $Package -eq 'All' -or $_.id -eq $Package })
if ($selected.Count -eq 0) { throw "testdata.json lists no package '$Package' (ids: $(($packageDefinitions.packages | ForEach-Object id) -join ', '))" }
# Not $package: PowerShell names ignore case, and $Package is the [string] parameter.
foreach ($definition in $selected) {
    $name = $definition.folder
    if ("$name.zip" -ne $definition.zip) { throw "$($definition.id): the folder $name does not match the zip $($definition.zip)" }
    $root = Join-Path $StagingRoot $name
    Add-Contents $definition $root
    $text = "CarafeSharp test data: $name (assembled $stamp)`n`n" + $readmes[$definition.id]
    [IO.File]::WriteAllText((Join-Path $root 'README.txt'), $text.Replace("`r`n", "`n").Replace("`n", "`r`n"))
    Complete-Package $name $root
}
