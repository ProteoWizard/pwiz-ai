<#
.SYNOPSIS
    Regenerate Skyline's per-DPI icon PNGs with IconBuilder.

.DESCRIPTION
    IconBuilder (pwiz_tools/Skyline/Executables/DevTools/IconBuilder) renders each icon in
    icons.manifest (Skyline) and every other *.manifest beside it (common.manifest for
    pwiz.Common) to <Name>.<Size>.png in the output folder that manifest names. The tool's
    README describes the manifests and the vector and raster sources.

    The tool finds its manifests by walking up from the current directory, so this script
    runs it from the IconBuilder folder of the given checkout.

.PARAMETER SourceRoot
    pwiz checkout. Defaults to pwiz under the project root.

.PARAMETER Icons
    Icon names to build (as listed in a manifest). Default: every icon.

.EXAMPLE
    .\Run-IconBuilder.ps1 -Icons Skyline_FilesTree
    Rebuild one icon's 20/24/32 px files in the default checkout.

.EXAMPLE
    .\Run-IconBuilder.ps1 -SourceRoot C:\proj\pwiz-work1
    Rebuild every icon in that checkout.
#>
param(
    [string]$SourceRoot,

    [string[]]$Icons = @()
)

$ErrorActionPreference = 'Stop'

if (-not $SourceRoot) {
    # ai/scripts/Skyline/IconBuilder -> project root
    $SourceRoot = Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path 'pwiz'
}
$toolDir = Join-Path $SourceRoot 'pwiz_tools\Skyline\Executables\DevTools\IconBuilder'
if (-not (Test-Path (Join-Path $toolDir 'IconBuilder.csproj'))) { throw "IconBuilder not found in $toolDir" }

Write-Host "IconBuilder: $toolDir" -ForegroundColor Gray
Push-Location $toolDir
try {
    dotnet run -c Release -- @Icons
    if ($LASTEXITCODE -ne 0) { throw "IconBuilder failed (exit $LASTEXITCODE)" }
}
finally {
    Pop-Location
}
