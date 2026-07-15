<#
.SYNOPSIS
    Shared dataset configuration + project-root path helpers for the
    Osprey script set.

.DESCRIPTION
    Dot-source this file to get the Get-DatasetConfig function (test data
    path resolution) and the Get-ProjectRoot / Get-PwizRoot / Get-OspreyRoot
    / Get-OspreyExe (C#) / Get-OspreyRustExe helpers (sibling-repo path
    resolution).  Centralising these here means no script needs to
    hard-code `C:\proj\...` paths -- developers who keep their checkouts
    under `D:\dev` or `~/src` get correct paths without per-script edits.

    Supported datasets: Stellar, Astral, AstralLibraryDecoy

    Each dataset hashtable carries:
      * Name, TestDir, Library, Resolution, SingleFile, AllFiles, FileLabel
        (always present)
      * DecoysInLibrary  -- when $true, run-osprey passes --decoys-in-library
                            (default: $false; reverse-decoy mode)
      * Manifest         -- optional FDRBench pairing manifest filename
                            (default: $null; composition pairing only)
    The library-decoy fields are forwarded to Osprey / Rust osprey via
    --decoys-in-library and --decoy-pairing-manifest in Run-Osprey.ps1.

    The test data root is resolved in this order:
      1. -TestBaseDir parameter (explicit, highest priority)
      2. $env:OSPREY_TEST_BASE_DIR (persistent per-machine config)
      3. "D:\test\osprey-runs" (hardcoded fallback)

    Project root (the dir holding ai/, pwiz/, osprey/ siblings) is resolved
    in this order:
      1. $env:OSPREY_PROJECT_ROOT (explicit per-machine override)
      2. Walk up three levels from THIS file's $PSScriptRoot
         (.../ai/scripts/Osprey -> .../ai -> .../ -> project root)
      3. C:\proj (legacy hard fallback)
    Sibling repo paths can also be overridden directly via
    $env:PWIZ_ROOT, $env:OSPREY_ROOT, $env:OSPREY_MM_ROOT for developers
    whose layouts don't match the convention.

.EXAMPLE
    . "$PSScriptRoot\Dataset-Config.ps1"
    $ds = Get-DatasetConfig "Stellar"
    $ds.TestDir    # D:\test\osprey-runs\stellar (or override)
    $ds.Resolution # unit

.EXAMPLE
    $ds = Get-DatasetConfig "Stellar" -TestBaseDir "C:\test\osprey-runs"
    $ds.TestDir    # C:\test\osprey-runs\stellar

.EXAMPLE
    . "$PSScriptRoot\Dataset-Config.ps1"
    $exe = Get-OspreyExe                 # C# Osprey, net8.0 by default
    $exe = Get-OspreyExe -Framework net472
    $rust = Get-OspreyRustExe                 # primary Rust osprey checkout
    $rustUp = Get-OspreyRustExe -Upstream     # maccoss/osprey clone
#>

# Track Dataset-Config.ps1's own location so the project-root walk
# works no matter where the calling script lives.  Computed at
# dot-source time (PSCommandPath is the path to this file).
$script:Osprey_DatasetConfigDir = Split-Path -Parent $PSCommandPath

function Get-ProjectRoot {
    <#
    Returns the directory that contains the ai/, pwiz/, osprey/ sibling
    checkouts.  Honors $env:OSPREY_PROJECT_ROOT first, then walks up
    from this script's own directory, then falls back to C:\proj.
    #>
    if ($env:OSPREY_PROJECT_ROOT) {
        return $env:OSPREY_PROJECT_ROOT
    }
    # .../ai/scripts/Osprey -> .../ai -> .../ -> root
    $candidate = Resolve-Path (Join-Path $script:Osprey_DatasetConfigDir '..\..\..') -ErrorAction SilentlyContinue
    if ($candidate -and (Test-Path (Join-Path $candidate 'ai'))) {
        return $candidate.Path
    }
    return 'C:\proj'
}

function Get-PwizRoot {
    if ($env:PWIZ_ROOT) { return $env:PWIZ_ROOT }
    return Join-Path (Get-ProjectRoot) 'pwiz'
}

function Get-OspreyRoot {
    <#
    Primary osprey checkout (the one the developer is iterating on).
    Override via $env:OSPREY_ROOT.
    #>
    if ($env:OSPREY_ROOT) { return $env:OSPREY_ROOT }
    return Join-Path (Get-ProjectRoot) 'osprey'
}

function Get-OspreyUpstreamRoot {
    <#
    maccoss/osprey reference clone, used by cross-impl baseline
    comparisons.  Default sibling is osprey-mm; override via
    $env:OSPREY_MM_ROOT.
    #>
    if ($env:OSPREY_MM_ROOT) { return $env:OSPREY_MM_ROOT }
    return Join-Path (Get-ProjectRoot) 'osprey-mm'
}

function Get-OspreyExe {
    <#
    Path to the built C# Osprey executable.  -Framework picks
    net8.0 (default) or net472.  Adds .exe on Windows.
    For the Rust osprey exe use Get-OspreyRustExe.
    #>
    param([ValidateSet('net8.0','net472')] [string]$Framework = 'net8.0')
    $exeSuffix = if ($IsWindows -or $null -eq $IsWindows) { '.exe' } else { '' }
    return Join-Path (Get-PwizRoot) `
        ("pwiz_tools/Osprey/Osprey/bin/x64/Release/$Framework/Osprey$exeSuffix")
}

function Get-OspreyRustExe {
    <#
    Path to the built Rust osprey executable.  -Upstream selects the
    maccoss/osprey clone (Get-OspreyUpstreamRoot); default is the
    primary checkout (Get-OspreyRoot).

    NOTE: Distinct from Get-OspreyExe (the C# Osprey accessor). Before
    the 2026-06-27 OspreySharp->Osprey rename the C# accessor was
    Get-OspreySharpExe; the rename collapsed it onto Get-OspreyExe,
    which had collided with this Rust accessor (both were named
    Get-OspreyExe, so the Rust one silently shadowed the C# one and
    every "-Framework" call returned the Rust exe). Keep the names
    distinct.
    #>
    param([switch]$Upstream)
    $exeSuffix = if ($IsWindows -or $null -eq $IsWindows) { '.exe' } else { '' }
    $base = if ($Upstream) { Get-OspreyUpstreamRoot } else { Get-OspreyRoot }
    return Join-Path $base "target/release/osprey$exeSuffix"
}

function Get-OspreyScriptDir {
    <#
    Returns the directory containing Dataset-Config.ps1 (i.e. the
    top-level Osprey scripts dir).  Useful for scripts that live
    in subfolders like Compare/ and need to reference siblings of
    Dataset-Config like samply-to-csv.py.
    #>
    return $script:Osprey_DatasetConfigDir
}

function Get-DotMemoryExe {
    <#
    Resolves the JetBrains dotMemory Console CLI (dotMemory.exe), or $null if
    it is not installed.  Mirrors the search order in
    ai/scripts/Skyline/Run-Tests.ps1: prefer the ~/.claude-tools/dotMemory
    install (laid down by ai/scripts/Install-DotMemory.ps1), then the NuGet
    global-packages cache.  Unlike dotCover / dotTrace, dotMemory is NOT a
    .NET global tool, so it is not on PATH; the installer only lays it down on
    Windows, so this returns $null off Windows.  Callers decide whether a
    missing dotMemory is fatal -- use Get-DotMemoryInstallHint for the message.
    #>
    if (-not ($IsWindows -or $null -eq $IsWindows)) {
        return $null
    }
    $claudeToolsRoot = Join-Path $env:USERPROFILE ".claude-tools\dotMemory"
    if (Test-Path $claudeToolsRoot) {
        $latest = Get-ChildItem $claudeToolsRoot -Directory |
            Sort-Object Name -Descending | Select-Object -First 1
        if ($latest) {
            $cand = Join-Path $latest.FullName "tools\dotMemory.exe"
            if (Test-Path $cand) { return $cand }
        }
    }
    $nugetCache = Join-Path $env:USERPROFILE ".nuget\packages\jetbrains.dotmemory.console.windows-x64"
    if (Test-Path $nugetCache) {
        $latest = Get-ChildItem $nugetCache -Directory |
            Sort-Object Name -Descending | Select-Object -First 1
        if ($latest) {
            $cand = Join-Path $latest.FullName "tools\dotMemory.exe"
            if (Test-Path $cand) { return $cand }
        }
    }
    return $null
}

function Get-DotMemoryInstallHint {
    <#
    One-line install hint printed when Get-DotMemoryExe returns $null.
    #>
    return "dotMemory.exe not found. Install: pwsh -File ./ai/scripts/Install-DotMemory.ps1"
}

function Get-DatasetConfig {
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateSet("Stellar", "Astral", "StellarLibraryDecoy", "AstralLibraryDecoy")]
        [string]$Dataset,

        [Parameter(Mandatory=$false)]
        [string]$TestBaseDir = $null
    )

    # Precedence: explicit -TestBaseDir, then env var, then OS-aware default.
    # Linux/WSL default maps Windows D:\ to the drvfs mount /mnt/d so the
    # same Osprey test data layout works on either host.
    if ([string]::IsNullOrEmpty($TestBaseDir)) {
        if ($env:OSPREY_TEST_BASE_DIR) {
            $baseDir = $env:OSPREY_TEST_BASE_DIR
        } elseif ($IsLinux) {
            $baseDir = "/mnt/d/test/osprey-runs"
        } else {
            $baseDir = "D:\test\osprey-runs"
        }
    } else {
        $baseDir = $TestBaseDir
    }

    switch ($Dataset) {
        "Stellar" {
            @{
                Name             = "Stellar"
                TestDir          = Join-Path $baseDir "stellar"
                Library          = "hela-filtered-SkylineAI_spectral_library.tsv"
                Resolution       = "unit"
                SingleFile       = "Ste-2024-12-02_HeLa_4mz_sDIA_400-900_20.mzML"
                AllFiles         = @(
                    "Ste-2024-12-02_HeLa_4mz_sDIA_400-900_20.mzML",
                    "Ste-2024-12-02_HeLa_4mz_sDIA_400-900_21.mzML",
                    "Ste-2024-12-02_HeLa_4mz_sDIA_400-900_22.mzML"
                )
                FileLabel        = @{ Single = "file 20"; All = "files 20-22" }
                DecoysInLibrary  = $false
                Manifest         = $null
            }
        }
        "Astral" {
            @{
                Name             = "Astral"
                TestDir          = Join-Path $baseDir "astral"
                Library          = "SkylineAI_spectral_library.tsv"
                Resolution       = "hram"
                SingleFile       = "Ast-2024-12-05_HeLa_3mzDIA_6mIIT_400-900_49.mzML"
                AllFiles         = @(
                    "Ast-2024-12-05_HeLa_3mzDIA_6mIIT_400-900_49.mzML",
                    "Ast-2024-12-05_HeLa_3mzDIA_6mIIT_400-900_55.mzML",
                    "Ast-2024-12-05_HeLa_3mzDIA_6mIIT_400-900_60.mzML"
                )
                FileLabel        = @{ Single = "file 49"; All = "files 49-60" }
                DecoysInLibrary  = $false
                Manifest         = $null
            }
        }
        "StellarLibraryDecoy" {
            # Mike's Carafe-built Stellar target+decoy+entrapment library with
            # FDRBench pairing manifest (delivered 2026-06-30 via Panorama:
            # StellarTest-TargetDecoyLibraries/target+decoy+entrapment/). Reuses
            # the existing Stellar mzML (files 20-22). Entrapment sequences are
            # included so FDRBench can measure true FDP -- see the --fdrbench
            # path. Used for cross-impl bit-parity on the library-decoy code
            # path and for reproducing Mike's FDRBench FDP plots.
            @{
                Name             = "StellarLibraryDecoy"
                TestDir          = Join-Path $baseDir "stellar-libdecoy"
                Library          = "carafe_spectral_library.tsv"
                Resolution       = "unit"
                SingleFile       = "Ste-2024-12-02_HeLa_4mz_sDIA_400-900_20.mzML"
                AllFiles         = @(
                    "Ste-2024-12-02_HeLa_4mz_sDIA_400-900_20.mzML",
                    "Ste-2024-12-02_HeLa_4mz_sDIA_400-900_21.mzML",
                    "Ste-2024-12-02_HeLa_4mz_sDIA_400-900_22.mzML"
                )
                FileLabel        = @{ Single = "file 20"; All = "files 20-22" }
                DecoysInLibrary  = $true
                Manifest         = "osprey_library_db_pairing.tsv"
            }
        }
        "AstralLibraryDecoy" {
            # Mike's Carafe-built Astral target+decoy+entrapment library with
            # FDRBench pairing manifest (delivered 2026-06-30 via Panorama:
            # AstralTest-TargetDecoyLibraries/target+decoy+entrapment/). Reuses
            # the existing Astral mzML (files 49/55/60). Used for cross-impl
            # bit-parity on the library-decoy code path and for reproducing
            # Mike's FDRBench FDP plots.
            @{
                Name             = "AstralLibraryDecoy"
                TestDir          = Join-Path $baseDir "astral-libdecoy"
                Library          = "carafe_spectral_library.tsv"
                Resolution       = "hram"
                SingleFile       = "Ast-2024-12-05_HeLa_3mzDIA_6mIIT_400-900_49.mzML"
                AllFiles         = @(
                    "Ast-2024-12-05_HeLa_3mzDIA_6mIIT_400-900_49.mzML",
                    "Ast-2024-12-05_HeLa_3mzDIA_6mIIT_400-900_55.mzML",
                    "Ast-2024-12-05_HeLa_3mzDIA_6mIIT_400-900_60.mzML"
                )
                FileLabel        = @{ Single = "file 49"; All = "files 49-60" }
                DecoysInLibrary  = $true
                Manifest         = "osprey_library_db_pairing.tsv"
            }
        }
    }
}
