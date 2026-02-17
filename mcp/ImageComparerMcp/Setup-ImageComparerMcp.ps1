<#
.SYNOPSIS
    Build and register the ImageComparer MCP server for Claude Code.

.DESCRIPTION
    Builds the ImageComparer.Mcp project from the pwiz repository and registers
    it as an MCP server with Claude Code. The exe stays in the build output
    directory — this script just handles building and registration.

    Source: pwiz_tools/Skyline/Executables/DevTools/ImageComparer.Mcp

.PARAMETER PwizRoot
    Path to the pwiz repository root. Default: C:/proj/pwiz

.PARAMETER Unregister
    Remove the MCP server registration from Claude Code.

.EXAMPLE
    .\Setup-ImageComparerMcp.ps1
    Build and register the server.

.EXAMPLE
    .\Setup-ImageComparerMcp.ps1 -PwizRoot D:/dev/pwiz
    Build from a different pwiz checkout.

.EXAMPLE
    .\Setup-ImageComparerMcp.ps1 -Unregister
    Remove the server registration.
#>

param(
    [string]$PwizRoot = "C:/proj/pwiz",
    [switch]$Unregister
)

$ErrorActionPreference = "Stop"

$serverName = "imagecomparer"
$projectDir = Join-Path $PwizRoot "pwiz_tools/Skyline/Executables/DevTools/ImageComparer.Mcp"
$outputDir = Join-Path $projectDir "bin/Debug/net8.0-windows/win-x64"
$exePath = Join-Path $outputDir "ImageComparer.Mcp.exe"

if ($Unregister) {
    Write-Host "Removing MCP server registration: $serverName" -ForegroundColor Yellow
    & claude mcp remove $serverName
    Write-Host "Done. Restart Claude Code to take effect." -ForegroundColor Green
    return
}

# Verify pwiz repo exists
if (-not (Test-Path (Join-Path $PwizRoot ".git"))) {
    Write-Host "Error: pwiz repository not found at $PwizRoot" -ForegroundColor Red
    Write-Host "Use -PwizRoot to specify the correct path." -ForegroundColor Yellow
    return
}

# Verify project exists
if (-not (Test-Path (Join-Path $projectDir "ImageComparer.Mcp.csproj"))) {
    Write-Host "Error: ImageComparer.Mcp project not found at $projectDir" -ForegroundColor Red
    Write-Host "Make sure the ImageComparer.Mcp project exists in the pwiz repo." -ForegroundColor Yellow
    return
}

# Check .NET SDK
$dotnetVersion = & dotnet --version 2>$null
if (-not $dotnetVersion) {
    Write-Host "Error: .NET SDK not found. Install .NET 8.0+ SDK from https://dotnet.microsoft.com/download" -ForegroundColor Red
    return
}
Write-Host "Using .NET SDK: $dotnetVersion" -ForegroundColor Gray

# Build
Write-Host "Building ImageComparer.Mcp..." -ForegroundColor Cyan
Push-Location $projectDir
try {
    & dotnet build
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Build failed." -ForegroundColor Red
        return
    }
} finally {
    Pop-Location
}

# Verify exe
if (-not (Test-Path $exePath)) {
    Write-Host "Error: Build output not found at $exePath" -ForegroundColor Red
    return
}

Write-Host "Build succeeded: $exePath" -ForegroundColor Green

# Register with Claude Code
# Use forward slashes — the exe path goes into JSON config
$exePathForward = $exePath.Replace('\', '/')

# Register with Claude Code (must be run outside Claude Code)
Write-Host "Registering MCP server: $serverName" -ForegroundColor Cyan
if ($env:CLAUDECODE) {
    Write-Host ""
    Write-Host "Cannot register from inside Claude Code. Run this manually:" -ForegroundColor Yellow
    Write-Host "  claude mcp add $serverName -- $exePathForward" -ForegroundColor White
} else {
    & claude mcp add $serverName -- $exePathForward
}

Write-Host ""
Write-Host "Done! Restart Claude Code to use the imagecomparer tools." -ForegroundColor Green
Write-Host ""
Write-Host "Tools available:" -ForegroundColor Gray
Write-Host "  list_changed_screenshots  - Scan for changed tutorial screenshots" -ForegroundColor Gray
Write-Host "  generate_diff_image       - Generate diff visualization for one screenshot" -ForegroundColor Gray
Write-Host "  generate_diff_report      - Generate diffs for all changed screenshots" -ForegroundColor Gray
Write-Host "  revert_screenshot         - Revert a screenshot to git HEAD" -ForegroundColor Gray
Write-Host ""
Write-Host "IMPORTANT: Always use forward slashes in paths (C:/proj/pwiz/...)" -ForegroundColor Yellow
