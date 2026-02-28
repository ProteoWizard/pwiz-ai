<#
.SYNOPSIS
    Deploy SkylineMcpServer build output to the installed location.

.DESCRIPTION
    Copies the built SkylineMcpServer files from the build output directory
    to ~/.skyline-mcp/. Run this after building the SkylineMcpServer project
    to update the installed MCP server without reinstalling through Skyline.

    Typical workflow:
    1. Edit code in SkylineMcpServer/
    2. Build: dotnet build SkylineMcpServer/SkylineMcpServer.csproj
    3. Deploy: pwsh ai/scripts/Skyline/Deploy-SkylineMcp.ps1
    4. Restart Claude Code to pick up the new server

.PARAMETER All
    Copy all files including dependencies. By default, only copies
    SkylineMcpServer.* files (dll, exe, pdb, deps.json, runtimeconfig.json).
#>
param(
    [switch]$All
)

$ErrorActionPreference = 'Stop'

$buildDir = Join-Path $PSScriptRoot '..\..\..\pwiz\pwiz_tools\Skyline\Executables\Tools\SkylineMcp\SkylineMcpServer\bin\Debug\net8.0-windows\win-x64'
$buildDir = (Resolve-Path $buildDir).Path
$deployDir = Join-Path $HOME '.skyline-mcp'

if (-not (Test-Path $buildDir)) {
    Write-Error "Build output not found at: $buildDir`nRun 'dotnet build' first."
}

if (-not (Test-Path $deployDir)) {
    Write-Error "Deploy target not found at: $deployDir`nInstall the MCP server through Skyline first."
}

# Check that build output exists
$dll = Join-Path $buildDir 'SkylineMcpServer.dll'
if (-not (Test-Path $dll)) {
    Write-Error "SkylineMcpServer.dll not found in build output. Run 'dotnet build' first."
}

if ($All) {
    $files = Get-ChildItem $buildDir -File
} else {
    $files = Get-ChildItem $buildDir -Filter 'SkylineMcpServer.*'
}

$copied = 0
foreach ($file in $files) {
    $dest = Join-Path $deployDir $file.Name
    Copy-Item $file.FullName $dest -Force
    $copied++
}

Write-Host "`u{2705} Deployed $copied file(s) to $deployDir" -ForegroundColor Green
foreach ($file in $files) {
    Write-Host "   $($file.Name)" -ForegroundColor DarkGray
}
