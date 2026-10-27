<#
.SYNOPSIS
    Exports the UI text a branch adds or changes in .resx files to a CSV, for review in Excel.

.DESCRIPTION
    Compares every English .resx the branch touched against a base ref and lists the string
    entries that were added or changed: the file, the resource name, the base text, the branch
    text, and an empty Revised column to fill in. Designer metadata (>>name.Type, sizes,
    locations, tab indexes) is left out, so what remains is what a user reads.

    Reviewing a branch's text this way, as a translator would, catches wording that reads as
    implementation detail (a table name, a class name) before it ships. Hand the filled-in CSV
    back to the session, which applies the Revised column to the resx files.

.PARAMETER SourceRoot
    The pwiz checkout root (default: <project-root>\pwiz).

.PARAMETER BaseRef
    The git ref the branch is compared against (default: master).

.PARAMETER OutputPath
    The CSV to write (default: ai\.tmp\resx-changes-<branch>-<timestamp>.csv).

.EXAMPLE
    pwsh -File ./ai/scripts/Skyline/Export-ResxChanges.ps1 -SourceRoot C:/proj/pwiz
    Every string the current branch adds or changes relative to master, in ai\.tmp.

.EXAMPLE
    pwsh -File ./ai/scripts/Skyline/Export-ResxChanges.ps1 -BaseRef fb75aff35b -OutputPath C:/proj/ai/.tmp/wizard-text.csv
    Compared against a given base commit, written where asked.
#>
param(
    [Parameter(Mandatory=$false)]
    [string]$SourceRoot = '',

    [Parameter(Mandatory=$false)]
    [string]$BaseRef = 'master',

    [Parameter(Mandatory=$false)]
    [string]$OutputPath = ''
)

$ErrorActionPreference = 'Stop'

# ai/scripts/Skyline -> ai/scripts -> ai -> project root
$projectRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
if (-not $SourceRoot) {
    $SourceRoot = Join-Path $projectRoot 'pwiz'
}
$SourceRoot = (Resolve-Path $SourceRoot).Path

$branch = (git -C $SourceRoot rev-parse --abbrev-ref HEAD).Trim()
if (-not $OutputPath) {
    $safeBranch = ($branch -replace '[^A-Za-z0-9_.-]', '_')
    $OutputPath = Join-Path $projectRoot ('ai\.tmp\resx-changes-{0}-{1}.csv' -f $safeBranch, (Get-Date -Format 'yyyyMMdd_HHmmss'))
}

# The English resx files the branch touched: a culture suffix (.ja.resx, .zh-Hans.resx) is a translation
$changed = git -C $SourceRoot diff --name-only $BaseRef HEAD -- '*.resx' |
    Where-Object { $_ -and ($_ -notmatch '\.[a-z]{2}(-[A-Za-z]+)?\.resx$') }

function Get-ResxStrings([string]$ref, [string]$path) {
    # The string entries of one version of a resx, by name; an empty table when the file is not in that ref
    $strings = @{}
    $text = git -C $SourceRoot show "${ref}:${path}" 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $text) {
        return $strings
    }
    $xml = [xml]($text -join "`n")
    foreach ($data in $xml.root.data) {
        $name = $data.name
        # Designer metadata and typed values (sizes, points, booleans) are not text a user reads
        if ($name.StartsWith('>>') -or $data.type -or -not $data.GetAttribute('xml:space')) {
            continue
        }
        if ($name -match '\.(Name|Type|Parent|ZOrder|Filter|ImeMode)$') {
            continue
        }
        $strings[$name] = [string]$data.value
    }
    return $strings
}

$rows = New-Object System.Collections.Generic.List[object]
foreach ($path in $changed) {
    $before = Get-ResxStrings $BaseRef $path
    $after = Get-ResxStrings 'HEAD' $path
    foreach ($name in ($after.Keys | Sort-Object)) {
        $textAfter = $after[$name]
        if ($before.ContainsKey($name)) {
            if ($before[$name] -eq $textAfter) {
                continue
            }
            $status = 'changed'
            $textBefore = $before[$name]
        } else {
            $status = 'added'
            $textBefore = ''
        }
        $rows.Add([pscustomobject]@{
            File = $path
            Name = $name
            Status = $status
            BaseText = $textBefore
            Text = $textAfter
            Revised = ''
        })
    }
}

$outDir = Split-Path $OutputPath -Parent
if (-not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Force $outDir | Out-Null
}
# A UTF-8 BOM, so Excel reads the file as UTF-8 and the Japanese and accented text survives
$rows | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding utf8BOM

Write-Host ("{0} string entries ({1} added, {2} changed) in {3} resx files on {4} vs {5}" -f `
    $rows.Count, @($rows | Where-Object Status -eq 'added').Count, @($rows | Where-Object Status -eq 'changed').Count,
    @($changed).Count, $branch, $BaseRef)
Write-Host "CSV: $OutputPath"
