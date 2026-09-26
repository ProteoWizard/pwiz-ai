<#
.SYNOPSIS
    Regenerate the .Designer.cs beside every English .resx in Osprey.

.DESCRIPTION
    Osprey's projects are SDK-style and each carries one resource file named
    after its assembly (OspreyCoreResources.resx, OspreyTasksResources.resx,
    ...). Visual Studio regenerates the checked-in .Designer.cs when the .resx
    is saved in its editor; a .resx edited any other way (a script, a text
    editor, an LLM) needs this instead. It runs the .NET Framework SDK's
    ResGen with /str and /publicClass, which is the same
    StronglyTypedResourceBuilder VS uses (PublicResXFileCodeGenerator), so the
    output matches what VS writes: one property per string, sorted by name.

    The namespace is the project's RootNamespace plus any subfolder, and the
    class is the file name. Translated files (.ja.resx, .zh-Hans.resx) have no
    Designer and are skipped.

.PARAMETER SourceRoot
    pwiz checkout root (default: the pwiz sibling of the ai/ folder). Pass it
    in any worktree session.

.EXAMPLE
    pwsh -File ./ai/scripts/Osprey/Update-OspreyResxDesigners.ps1 -SourceRoot C:/proj/pwiz-work2
#>
param(
    [string]$SourceRoot = $null
)

$ErrorActionPreference = 'Stop'

if (-not $SourceRoot) {
    $aiRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $SourceRoot = Join-Path (Split-Path -Parent $aiRoot) 'pwiz'
}
$ospreyRoot = Join-Path $SourceRoot 'pwiz_tools\Osprey'

$resgen = Get-ChildItem 'C:\Program Files (x86)\Microsoft SDKs\Windows\*\bin\NETFX*Tools\ResGen.exe' -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending | Select-Object -First 1
if (-not $resgen) {
    Write-Host 'ResGen.exe not found (install the .NET Framework 4.8 developer pack / Windows SDK)' -ForegroundColor Red
    exit 1
}

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) 'osprey-resgen'
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

$files = Get-ChildItem $ospreyRoot -Recurse -Filter '*.resx' |
    Where-Object { $_.FullName -notmatch '\\(bin|obj)\\' -and $_.BaseName -notmatch '\.' }
foreach ($resx in $files) {
    # The owning project: the nearest parent folder holding a .csproj.
    $dir = $resx.Directory
    while ($dir -and -not (Get-ChildItem $dir.FullName -Filter '*.csproj')) {
        $dir = $dir.Parent
    }
    $csproj = Get-ChildItem $dir.FullName -Filter '*.csproj' | Select-Object -First 1
    [xml]$proj = Get-Content $csproj.FullName
    $rootNs = ($proj.Project.PropertyGroup | ForEach-Object { $_.RootNamespace } | Where-Object { $_ }) | Select-Object -First 1
    if (-not $rootNs) {
        $rootNs = [System.IO.Path]::GetFileNameWithoutExtension($csproj.Name)
    }
    $rel = [System.IO.Path]::GetRelativePath($dir.FullName, $resx.Directory.FullName)
    $ns = if ($rel -eq '.') { $rootNs } else { $rootNs + '.' + ($rel -replace '[\\/]', '.') }
    $class = $resx.BaseName
    $designer = Join-Path $resx.Directory.FullName ($class + '.Designer.cs')
    $resources = Join-Path $tmp ($ns + "." + $class + ".resources")

    & $resgen.FullName /useSourcePath /publicClass $resx.FullName $resources "/str:cs,$ns,$class,$designer" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ResGen failed for $($resx.FullName)" -ForegroundColor Red
        exit 1
    }
    # ResGen writes LF-only or mixed endings depending on version; pwiz source is CRLF.
    $text = [System.IO.File]::ReadAllText($designer) -replace "`r?`n", "`r`n"
    [System.IO.File]::WriteAllText($designer, $text, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "  $ns.$class -> $([System.IO.Path]::GetRelativePath($SourceRoot, $designer))"
}
