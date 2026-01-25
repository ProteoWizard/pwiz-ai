<#
.SYNOPSIS
    Install JetBrains dotMemory Console to ~/.claude-tools/

.DESCRIPTION
    Downloads and extracts JetBrains dotMemory Console CLI tool.

    Unlike dotCover and dotTrace, dotMemory is NOT available as a .NET global tool.
    This script downloads the NuGet package and extracts it to ~/.claude-tools/dotMemory/.

.PARAMETER Version
    Version to install (default: 2025.3.1)

.EXAMPLE
    .\Install-DotMemory.ps1
    Install the default version

.EXAMPLE
    .\Install-DotMemory.ps1 -Version 2025.2.0
    Install a specific version
#>
param(
    [Parameter(Mandatory=$false)]
    [string]$Version = '2025.3.1'
)

$destDir = Join-Path $env:USERPROFILE ".claude-tools\dotMemory\$Version"

# Check if already installed
$exe = Join-Path $destDir 'tools\dotMemory.exe'
if (Test-Path $exe) {
    Write-Host "dotMemory $Version is already installed at: $exe" -ForegroundColor Green
    Write-Host "To reinstall, delete the folder first: $destDir" -ForegroundColor Gray
    exit 0
}

New-Item -ItemType Directory -Force -Path $destDir | Out-Null
$nupkgUrl = "https://www.nuget.org/api/v2/package/JetBrains.dotMemory.Console.windows-x64/$Version"
$nupkgFile = Join-Path $destDir 'package.nupkg'

Write-Host "Downloading dotMemory Console $Version..." -ForegroundColor Cyan
Write-Host "  From: $nupkgUrl" -ForegroundColor Gray
Write-Host "  To:   $destDir" -ForegroundColor Gray

try {
    Invoke-WebRequest -Uri $nupkgUrl -OutFile $nupkgFile -ErrorAction Stop
} catch {
    Write-Host "ERROR: Failed to download dotMemory Console" -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "Extracting..." -ForegroundColor Cyan
Expand-Archive -Path $nupkgFile -DestinationPath $destDir -Force
Remove-Item $nupkgFile

if (Test-Path $exe) {
    Write-Host ""
    Write-Host "Successfully installed dotMemory Console $Version" -ForegroundColor Green
    Write-Host "  Location: $exe" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Usage with Run-Tests.ps1:" -ForegroundColor Cyan
    Write-Host "  .\Run-Tests.ps1 -TestName TestOlderProteomeDb -MemoryProfile -MemoryProfileWaitRuns 25" -ForegroundColor White
} else {
    Write-Host "ERROR: dotMemory.exe not found after extraction" -ForegroundColor Red
    exit 1
}
