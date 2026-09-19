<#
.SYNOPSIS
    Inventory this machine's Claude Code auto-memory for /pw-cleanup-memory.

.DESCRIPTION
    Lists every memory file (date, type, size, name, description), the type breakdown,
    total and index sizes, and two consistency checks: MEMORY.md lines whose file is
    missing, and files missing from MEMORY.md. Read-only. See
    ai/docs/memory-cleanup-guide.md.

.PARAMETER MemoryDir
    The memory directory. Defaults to the Claude Code layout for the current project:
    %USERPROFILE%\.claude\projects\<project dir with ':' and '\' replaced by '-'>\memory.
    The session's system prompt names the exact path; pass it when the default is wrong.

.PARAMETER ProjectDir
    Project root used to derive the default MemoryDir. Defaults to $env:CLAUDE_PROJECT_DIR,
    then the current directory.
#>
param(
    [string]$MemoryDir,
    [string]$ProjectDir
)

$ErrorActionPreference = 'Stop'

if (-not $MemoryDir) {
    if (-not $ProjectDir) { $ProjectDir = $env:CLAUDE_PROJECT_DIR }
    if (-not $ProjectDir) { $ProjectDir = (Get-Location).Path }
    $encoded = ($ProjectDir.TrimEnd('\')) -replace '[:\\]', '-'
    $MemoryDir = Join-Path $env:USERPROFILE ".claude\projects\$encoded\memory"
}
if (-not (Test-Path $MemoryDir)) {
    Write-Host "No memory directory at $MemoryDir"
    exit 0
}

$indexPath = Join-Path $MemoryDir 'MEMORY.md'
$files = Get-ChildItem -Path $MemoryDir -Filter '*.md' | Where-Object { $_.Name -ne 'MEMORY.md' }

function Get-Frontmatter([System.IO.FileInfo]$f, [string]$key) {
    $line = Select-String -Path $f.FullName -Pattern "^\s*${key}:\s*(.+)$" | Select-Object -First 1
    if ($line) { return $line.Matches[0].Groups[1].Value.Trim().Trim('"') }
    return ''
}

$rows = foreach ($f in $files) {
    [pscustomobject]@{
        Date = $f.LastWriteTime.ToString('yyyy-MM-dd')
        Type = (Get-Frontmatter $f 'type')
        KB   = [math]::Round($f.Length / 1KB, 1)
        File = $f.Name
        Description = (Get-Frontmatter $f 'description')
    }
}

$totalKB = [math]::Round(($files | Measure-Object Length -Sum).Sum / 1KB, 1)
$indexKB = if (Test-Path $indexPath) { [math]::Round((Get-Item $indexPath).Length / 1KB, 1) } else { 0 }

Write-Host "Memory dir : $MemoryDir"
Write-Host "Files      : $($files.Count)  ($totalKB KB)"
Write-Host "MEMORY.md  : $indexKB KB (loaded into every session)"
Write-Host ''
Write-Host 'By type:'
$rows | Group-Object Type | Sort-Object Count -Descending |
    ForEach-Object { '  {0,-10} {1,4}' -f ($(if ($_.Name) { $_.Name } else { '(none)' }), $_.Count) }
Write-Host ''
$rows | Sort-Object Date | Format-Table Date, Type, KB, File, @{ n = 'Description'; e = { $_.Description.Substring(0, [math]::Min(90, $_.Description.Length)) } } -AutoSize -Wrap

# Consistency: index vs files
if (Test-Path $indexPath) {
    $indexed = Select-String -Path $indexPath -Pattern '\]\(([^)]+\.md)\)' -AllMatches |
        ForEach-Object { $_.Matches } | ForEach-Object { $_.Groups[1].Value }
    $missingFiles = $indexed | Where-Object { -not (Test-Path (Join-Path $MemoryDir $_)) }
    $unindexed = $files.Name | Where-Object { $_ -notin $indexed }
    Write-Host ''
    Write-Host "Index lines whose file is missing : $($missingFiles.Count)"
    $missingFiles | ForEach-Object { "  $_" }
    Write-Host "Files missing from MEMORY.md      : $($unindexed.Count)"
    $unindexed | ForEach-Object { "  $_" }
}

$big = $rows | Where-Object { $_.KB -gt 3 }
if ($big) {
    Write-Host ''
    Write-Host "Larger than 3 KB (a memory is one fact; these are probably session logs): $($big.Count)"
    $big | Sort-Object KB -Descending | ForEach-Object { '  {0,6} KB  {1}' -f $_.KB, $_.File }
}
