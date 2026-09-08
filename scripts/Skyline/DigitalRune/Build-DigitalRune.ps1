<#
.SYNOPSIS
    Build DigitalRune.Windows.Docking from source, optionally for .NET 10, and install it into
    pwiz_tools/Shared/Lib.

.DESCRIPTION
    Skyline references DigitalRune.Windows.Docking as a PREBUILT binary in
    pwiz_tools/Shared/Lib (HintPath, no NuGet equivalent). The shipped binary targets
    .NETFramework 4.7.2 and is loaded unchanged on .NET 10 through WinForms compat.

    The source is not in the pwiz repo. It lives in the internal repo
    uw-maccosslab/developers under skylinedev/DigitalRune-Docking-Windows/Source. A previous
    session already rebuilt this DLL from that source - see
    ai/todos/completed/2026/01/TODO-20260128_DockPaneStrip_race_condition.md.

    This script exists so that rebuilding it is repeatable rather than a pile of ad-hoc commands,
    and so it goes through ai/scripts/ like every other build here.

    Two things the legacy project needs to build under the SDK:

    1. DockPanelBrushes.cs and DockPanelPens.cs are on disk but are NOT among the legacy
       project's 89 Compile items, and they reference a DockPanelColors type that exists nowhere
       in the source. They are dead files; only default SDK globbing picks them up, and they must
       be excluded or the build fails with CS0246.
    2. Properties/AssemblyInfo.cs is checked in, so GenerateAssemblyInfo must be off.

    Both are handled by the generated SDK-style project, which compiles exactly the same sources
    as the legacy one.

.PARAMETER SourceRepo
    Checkout of uw-maccosslab/developers. Cloned (sparse, depth 1) if missing.

.PARAMETER TargetFramework
    net10.0-windows (default) or net472. net472 reproduces the shipped binary.

.PARAMETER Install
    Copy the built DLL/PDB over pwiz_tools/Shared/Lib, keeping a .net472-backup of what was
    there. Without this the build output is left in place and nothing in pwiz is touched.

.PARAMETER Restore
    Put the .net472-backup files back and exit. Undoes -Install.

.PARAMETER PwizRoot
    Checkout to install into. Defaults to C:\proj\pwiz-work1.

.EXAMPLE
    .\Build-DigitalRune.ps1
    Build for net10.0-windows, leave the output in the source tree.

.EXAMPLE
    .\Build-DigitalRune.ps1 -Install -PwizRoot C:\proj\pwiz-work1
    Build for net10 and swap it into that checkout, backing up the existing binary.

.EXAMPLE
    .\Build-DigitalRune.ps1 -Restore
    Put the original net472 binary back.

.NOTES
    Cloning needs gh auth (the org enforces SAML SSO, so a bare `git clone` over HTTPS is
    rejected while gh's token works). The script uses gh's credential helper for that reason.
#>
param(
    [string]$SourceRepo = 'C:\proj\developers',

    [ValidateSet('net10.0-windows', 'net472')]
    [string]$TargetFramework = 'net10.0-windows',

    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release',

    [switch]$Install,
    [switch]$Restore,

    [string]$PwizRoot = 'C:\proj\pwiz-work1'
)

$ErrorActionPreference = 'Stop'

$libDir = Join-Path $PwizRoot 'pwiz_tools\Shared\Lib'
$installedDll = Join-Path $libDir 'DigitalRune.Windows.Docking.dll'
$installedPdb = Join-Path $libDir 'DigitalRune.Windows.Docking.pdb'
$backupDll = "$installedDll.net472-backup"
$backupPdb = "$installedPdb.net472-backup"

if ($Restore) {
    if (-not (Test-Path $backupDll)) {
        Write-Host "No backup at $backupDll - nothing to restore." -ForegroundColor Yellow
        exit 0
    }
    Copy-Item $backupDll $installedDll -Force
    if (Test-Path $backupPdb) { Copy-Item $backupPdb $installedPdb -Force }
    Remove-Item $backupDll, $backupPdb -Force -ErrorAction SilentlyContinue
    Write-Host "Restored the original DigitalRune binary in $libDir" -ForegroundColor Green
    Write-Host "Rebuild Skyline for it to take effect." -ForegroundColor Yellow
    exit 0
}

# --- Source ---------------------------------------------------------------

$sourceRel = 'skylinedev\DigitalRune-Docking-Windows\Source'
$projDir = Join-Path $SourceRepo "$sourceRel\DigitalRune.Windows.Docking"

if (-not (Test-Path $projDir)) {
    Write-Host "Cloning uw-maccosslab/developers into $SourceRepo ..." -ForegroundColor Yellow
    $parent = Split-Path $SourceRepo -Parent
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    # The org enforces SAML SSO; gh's token is authorized where the ambient git credential is not.
    git -c credential.helper= -c credential.helper='!gh auth git-credential' `
        clone --depth 1 --sparse https://github.com/uw-maccosslab/developers.git $SourceRepo
    if ($LASTEXITCODE -ne 0) { throw "clone failed - check 'gh auth status'" }
    git -C $SourceRepo sparse-checkout set ($sourceRel -replace '\\', '/')
    if (-not (Test-Path $projDir)) { throw "sparse checkout did not produce $projDir" }
}

Write-Host "Source: $projDir" -ForegroundColor Gray

# --- Generated SDK-style project -----------------------------------------

$sdkProj = Join-Path $projDir 'DigitalRune.Windows.Docking.Generated.csproj'
$useWinForms = 'true'
$projectXml = @"
<Project Sdk="Microsoft.NET.Sdk">

  <!-- GENERATED by ai/scripts/Skyline/DigitalRune/Build-DigitalRune.ps1 - do not edit by hand
       and do not commit to the DigitalRune repo. The legacy
       DigitalRune.Windows.Docking.csproj beside this file remains the reference for which
       sources belong to the assembly. -->

  <PropertyGroup>
    <TargetFramework>$TargetFramework</TargetFramework>
    <UseWindowsForms>$useWinForms</UseWindowsForms>
    <AssemblyName>DigitalRune.Windows.Docking</AssemblyName>
    <RootNamespace>DigitalRune.Windows.Docking</RootNamespace>
    <GenerateAssemblyInfo>false</GenerateAssemblyInfo>
    <GenerateDocumentationFile>false</GenerateDocumentationFile>
    <EnableDefaultNoneItems>false</EnableDefaultNoneItems>
    <SatelliteResourceLanguages>en</SatelliteResourceLanguages>
    <Platforms>AnyCPU</Platforms>
    <!-- Third-party source that predates these analyzers. This build compares behaviour against
         the shipped binary; it is not a cleanup of someone else's library. -->
    <NoWarn>`$(NoWarn);CS0618;CS0414;CS0169;CS1591;WFO1000;WFO5001;SYSLIB0003;SYSLIB0011;CA1416</NoWarn>
  </PropertyGroup>

  <ItemGroup>
    <!-- Dead files: not among the legacy project's Compile items, and they reference a
         DockPanelColors type that does not exist in the source. Only SDK globbing finds them. -->
    <Compile Remove="DockPanelBrushes.cs" />
    <Compile Remove="DockPanelPens.cs" />
  </ItemGroup>

  <ItemGroup>
    <!-- **/*.resx is picked up by default; the embedded images are not. -->
    <EmbeddedResource Include="Resources\*.png" />
    <EmbeddedResource Include="Resources\*.cur" />
    <None Remove="Resources\Thumbs.db" />
  </ItemGroup>

</Project>
"@
Set-Content -Path $sdkProj -Value $projectXml -Encoding UTF8

# Guard the assumption above rather than trusting it: if the dead-file set ever changes, the
# generated project silently stops matching the shipped assembly.
$legacyProj = Join-Path $projDir 'DigitalRune.Windows.Docking.csproj'
if (Test-Path $legacyProj) {
    $inProject = ([regex]::Matches((Get-Content $legacyProj -Raw), '<Compile Include="([^"]+)"') |
        ForEach-Object { $_.Groups[1].Value -replace '/', '\' }) | Sort-Object -Unique
    $onDisk = Get-ChildItem $projDir -Recurse -Filter *.cs |
        Where-Object { $_.FullName -notmatch '\\(obj|bin)\\' } |
        ForEach-Object { $_.FullName.Substring($projDir.Length + 1) } | Sort-Object -Unique
    $orphans = $onDisk | Where-Object { $inProject -notcontains $_ }
    $expected = @('DockPanelBrushes.cs', 'DockPanelPens.cs')
    $unexpected = $orphans | Where-Object { $expected -notcontains $_ }
    if ($unexpected) {
        Write-Host "WARNING: source files on disk that the legacy project does not compile and this script does not exclude:" -ForegroundColor Yellow
        $unexpected | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
        Write-Host "  Update the Compile Remove list in this script if they are also dead." -ForegroundColor Yellow
    }
}

# --- Build ----------------------------------------------------------------

Write-Host "`nBuilding DigitalRune.Windows.Docking ($TargetFramework | $Configuration)" -ForegroundColor Yellow
dotnet build $sdkProj -c $Configuration -nologo
if ($LASTEXITCODE -ne 0) { throw 'dotnet build failed' }

$outDir = Join-Path $projDir "bin\$Configuration\$TargetFramework"
$builtDll = Join-Path $outDir 'DigitalRune.Windows.Docking.dll'
if (-not (Test-Path $builtDll)) { throw "expected output missing: $builtDll" }

$name = [System.Reflection.AssemblyName]::GetAssemblyName($builtDll)
Write-Host "`nBuilt: $builtDll" -ForegroundColor Green
Write-Host "       $($name.FullName)" -ForegroundColor Gray

# --- Install --------------------------------------------------------------

if ($Install) {
    if (-not (Test-Path $libDir)) { throw "not a pwiz checkout: $libDir" }
    # Identity must match or Skyline's other references (and the ja/zh-CHS satellites) stop
    # resolving. Compare before overwriting rather than discovering it at run time.
    if (Test-Path $installedDll) {
        $existing = [System.Reflection.AssemblyName]::GetAssemblyName($installedDll)
        if ($existing.FullName -ne $name.FullName) {
            Write-Host "WARNING: assembly identity differs from the installed binary" -ForegroundColor Yellow
            Write-Host "  installed: $($existing.FullName)" -ForegroundColor Yellow
            Write-Host "  new      : $($name.FullName)" -ForegroundColor Yellow
        }
        if (-not (Test-Path $backupDll)) {
            Copy-Item $installedDll $backupDll -Force
            if (Test-Path $installedPdb) { Copy-Item $installedPdb $backupPdb -Force }
            Write-Host "Backed up the existing binary to *.net472-backup" -ForegroundColor Gray
        }
        else {
            Write-Host "Backup already exists; leaving it alone." -ForegroundColor Gray
        }
    }
    Copy-Item $builtDll $installedDll -Force
    $builtPdb = Join-Path $outDir 'DigitalRune.Windows.Docking.pdb'
    if (Test-Path $builtPdb) { Copy-Item $builtPdb $installedPdb -Force }
    Write-Host "Installed into $libDir" -ForegroundColor Green
    Write-Host "Rebuild Skyline for it to take effect; -Restore puts the original back." -ForegroundColor Yellow
}
