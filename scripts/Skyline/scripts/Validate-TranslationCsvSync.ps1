<#
.SYNOPSIS
    Validates that string names in translation CSV files exist in localized RESX files.

.DESCRIPTION
    This script reads localization CSV files and verifies that each string name
    exists in the corresponding .ja.resx or .zh-CHS.resx file. This catches bugs
    where the RESX sync process failed to add entries to localized files.

    The script should PASS after FinalizeResxFiles runs correctly, and FAIL if
    localized RESX files are missing entries.

.PARAMETER CsvPath
    Path to the localization CSV file (e.g., localization.ja.csv)

.PARAMETER Language
    Language code: 'ja' or 'zh-CHS'

.PARAMETER PwizRoot
    Path to pwiz repository root (auto-detected from script location if not specified)

.EXAMPLE
    .\Validate-TranslationCsvSync.ps1 -CsvPath "ai\.tmp\localization.ja.csv" -Language ja

.EXAMPLE
    .\Validate-TranslationCsvSync.ps1 -CsvPath "ai\.tmp\localization.zh-CHS.csv" -Language zh-CHS
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$CsvPath,

    [Parameter(Mandatory=$true)]
    [ValidateSet('ja', 'zh-CHS')]
    [string]$Language,

    [string]$PwizRoot = $null
)

$ErrorActionPreference = "Stop"

# Auto-detect pwiz root if not specified
# Script location: ai/scripts/Skyline/scripts/ -> ai/ -> project root
if (-not $PwizRoot) {
    $aiRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    $projectRoot = Split-Path -Parent $aiRoot
    # Try sibling mode: look for pwiz/ next to ai/
    $siblingPath = Join-Path $projectRoot 'pwiz'
    if (Test-Path (Join-Path $siblingPath 'pwiz_tools')) {
        $PwizRoot = $siblingPath
    } else {
        Write-Error "Cannot auto-detect pwiz root. Use -PwizRoot to specify the path."
        exit 1
    }
}

Write-Host "Validating translation CSV sync for $Language..." -ForegroundColor Cyan
Write-Host "CSV: $CsvPath"
Write-Host "Pwiz root: $PwizRoot"
Write-Host ""

# Step 1: Find all localized RESX files and build a lookup of Name -> Files
Write-Host "Loading all .$Language.resx files..." -ForegroundColor Yellow

$resxFiles = Get-ChildItem -Path $PwizRoot -Recurse -Filter "*.$Language.resx" -File |
    Where-Object { $_.FullName -notmatch '\\(obj|bin)\\' }

Write-Host "Found $($resxFiles.Count) .$Language.resx files"

# Build a dictionary: Name -> List of files containing it
$nameToFiles = @{}
$totalEntries = 0

foreach ($resxFile in $resxFiles) {
    try {
        [xml]$xml = Get-Content -Path $resxFile.FullName -Encoding UTF8
        $dataElements = $xml.SelectNodes("//data[@name]")

        foreach ($data in $dataElements) {
            $name = $data.GetAttribute("name")
            if (-not $nameToFiles.ContainsKey($name)) {
                $nameToFiles[$name] = [System.Collections.Generic.List[string]]::new()
            }
            $nameToFiles[$name].Add($resxFile.FullName)
            $totalEntries++
        }
    }
    catch {
        Write-Warning "Failed to parse $($resxFile.FullName): $_"
    }
}

Write-Host "Indexed $totalEntries entries across $($nameToFiles.Count) unique names"
Write-Host ""

# Step 2: Parse CSV and check each name
Write-Host "Reading CSV file..." -ForegroundColor Yellow

# Read CSV - handle multiline values by reading raw and parsing carefully
$csvContent = Get-Content -Path $CsvPath -Raw -Encoding UTF8

# Use .NET CSV parser for robustness with quoted multiline values
Add-Type -AssemblyName Microsoft.VisualBasic
$textReader = [System.IO.StringReader]::new($csvContent)
$parser = [Microsoft.VisualBasic.FileIO.TextFieldParser]::new($textReader)
$parser.TextFieldType = [Microsoft.VisualBasic.FileIO.FieldType]::Delimited
$parser.SetDelimiters(",")
$parser.HasFieldsEnclosedInQuotes = $true

# Read header
$header = $parser.ReadFields()
$nameIndex = [Array]::IndexOf($header, "Name")
$fileIndex = [Array]::IndexOf($header, "File")
$issueIndex = [Array]::IndexOf($header, "Issue")

if ($nameIndex -lt 0) {
    throw "CSV does not have a 'Name' column"
}

$missingEntries = [System.Collections.Generic.List[PSCustomObject]]::new()
$foundCount = 0
$rowCount = 0

while (-not $parser.EndOfData) {
    try {
        $fields = $parser.ReadFields()
        $rowCount++

        $name = $fields[$nameIndex]
        $file = if ($fileIndex -ge 0 -and $fileIndex -lt $fields.Count) { $fields[$fileIndex] } else { "" }
        $issue = if ($issueIndex -ge 0 -and $issueIndex -lt $fields.Count) { $fields[$issueIndex] } else { "" }

        if ([string]::IsNullOrWhiteSpace($name)) {
            continue
        }

        # Check if name exists in any localized RESX file
        if ($nameToFiles.ContainsKey($name)) {
            $foundCount++
        }
        else {
            $missingEntries.Add([PSCustomObject]@{
                Name = $name
                File = $file
                Issue = $issue
            })
        }
    }
    catch {
        Write-Warning "Error parsing row $rowCount`: $_"
    }
}

$parser.Close()
$textReader.Close()

Write-Host "Processed $rowCount CSV rows"
Write-Host ""

# Step 3: Report results
Write-Host "=== VALIDATION RESULTS ===" -ForegroundColor Cyan
Write-Host "Found in RESX files: $foundCount"
Write-Host "Missing from RESX files: $($missingEntries.Count)"
Write-Host ""

if ($missingEntries.Count -eq 0) {
    Write-Host "SUCCESS: All CSV entries exist in .$Language.resx files" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "FAILURE: $($missingEntries.Count) entries missing from .$Language.resx files" -ForegroundColor Red
    Write-Host ""
    Write-Host "Missing entries (first 20):" -ForegroundColor Yellow

    $missingEntries | Select-Object -First 20 | ForEach-Object {
        $fileInfo = if ($_.File) { " (expected in: $($_.File))" } else { "" }
        Write-Host "  - $($_.Name)$fileInfo"
    }

    if ($missingEntries.Count -gt 20) {
        Write-Host "  ... and $($missingEntries.Count - 20) more"
    }

    Write-Host ""
    Write-Host "This indicates the RESX sync process did not add these entries to localized files." -ForegroundColor Yellow
    Write-Host "Check that FinalizeResxFiles ran correctly and --overrideAll was passed." -ForegroundColor Yellow

    exit 1
}
