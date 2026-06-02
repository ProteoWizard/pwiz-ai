<#
.SYNOPSIS
    Shared dataset configuration + project-root path helpers for the
    OspreySharp script set.

.DESCRIPTION
    Dot-source this file to get the Get-DatasetConfig function (test data
    path resolution) and the Get-ProjectRoot / Get-PwizRoot / Get-OspreyRoot
    / Get-OspreySharpExe / Get-OspreyExe helpers (sibling-repo path
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
    The library-decoy fields are forwarded to OspreySharp / Rust osprey via
    --decoys-in-library and --decoy-pairing-manifest in Run-Osprey.ps1.

    The test data root is resolved in this order:
      1. -TestBaseDir parameter (explicit, highest priority)
      2. $env:OSPREY_TEST_BASE_DIR (persistent per-machine config)
      3. "D:\test\osprey-runs" (hardcoded fallback)

    Project root (the dir holding ai/, pwiz/, osprey/ siblings) is resolved
    in this order:
      1. $env:OSPREY_PROJECT_ROOT (explicit per-machine override)
      2. Walk up three levels from THIS file's $PSScriptRoot
         (.../ai/scripts/OspreySharp -> .../ai -> .../ -> project root)
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
    $exe = Get-OspreySharpExe                 # net8.0 by default
    $exe = Get-OspreySharpExe -Framework net472
    $rust = Get-OspreyExe                     # primary osprey checkout
    $rustUp = Get-OspreyExe -Upstream         # maccoss/osprey clone
#>

# Track Dataset-Config.ps1's own location so the project-root walk
# works no matter where the calling script lives.  Computed at
# dot-source time (PSCommandPath is the path to this file).
$script:OspreySharp_DatasetConfigDir = Split-Path -Parent $PSCommandPath

function Get-ProjectRoot {
    <#
    Returns the directory that contains the ai/, pwiz/, osprey/ sibling
    checkouts.  Honors $env:OSPREY_PROJECT_ROOT first, then walks up
    from this script's own directory, then falls back to C:\proj.
    #>
    if ($env:OSPREY_PROJECT_ROOT) {
        return $env:OSPREY_PROJECT_ROOT
    }
    # .../ai/scripts/OspreySharp -> .../ai -> .../ -> root
    $candidate = Resolve-Path (Join-Path $script:OspreySharp_DatasetConfigDir '..\..\..') -ErrorAction SilentlyContinue
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

function Get-OspreySharpExe {
    <#
    Path to the built OspreySharp executable.  -Framework picks
    net8.0 (default) or net472.  Adds .exe on Windows.
    #>
    param([ValidateSet('net8.0','net472')] [string]$Framework = 'net8.0')
    $exeSuffix = if ($IsWindows -or $null -eq $IsWindows) { '.exe' } else { '' }
    return Join-Path (Get-PwizRoot) `
        ("pwiz_tools/OspreySharp/OspreySharp/bin/x64/Release/$Framework/OspreySharp$exeSuffix")
}

function Get-OspreyExe {
    <#
    Path to the built Rust osprey executable.  -Upstream selects the
    maccoss/osprey clone (Get-OspreyUpstreamRoot); default is the
    primary checkout (Get-OspreyRoot).
    #>
    param([switch]$Upstream)
    $exeSuffix = if ($IsWindows -or $null -eq $IsWindows) { '.exe' } else { '' }
    $base = if ($Upstream) { Get-OspreyUpstreamRoot } else { Get-OspreyRoot }
    return Join-Path $base "target/release/osprey$exeSuffix"
}

function Get-OspreySharpScriptDir {
    <#
    Returns the directory containing Dataset-Config.ps1 (i.e. the
    top-level OspreySharp scripts dir).  Useful for scripts that live
    in subfolders like Compare/ and need to reference siblings of
    Dataset-Config like samply-to-csv.py.
    #>
    return $script:OspreySharp_DatasetConfigDir
}

function Get-DatasetConfig {
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateSet("Stellar", "Astral", "AstralLibraryDecoy")]
        [string]$Dataset,

        [Parameter(Mandatory=$false)]
        [string]$TestBaseDir = $null
    )

    # Precedence: explicit -TestBaseDir, then env var, then OS-aware default.
    # Linux/WSL default maps Windows D:\ to the drvfs mount /mnt/d so the
    # same OspreySharp test data layout works on either host.
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
        "AstralLibraryDecoy" {
            # Carafe-built Astral entrapment library with FDRBench pairing
            # manifest. Library + manifest filenames are placeholders until
            # Mike provides the final files; the existing Astral mzML files
            # are reused. Running before the files are staged produces a
            # clear "file not found" error in Run-Osprey.ps1. Used for
            # cross-impl Test-Regression on the library-decoy code path.
            @{
                Name             = "AstralLibraryDecoy"
                TestDir          = Join-Path $baseDir "astral-libdecoy"
                Library          = "SkylineAI_entrapment_carafe_spectral_library.tsv"
                Resolution       = "hram"
                SingleFile       = "Ast-2024-12-05_HeLa_3mzDIA_6mIIT_400-900_49.mzML"
                AllFiles         = @(
                    "Ast-2024-12-05_HeLa_3mzDIA_6mIIT_400-900_49.mzML",
                    "Ast-2024-12-05_HeLa_3mzDIA_6mIIT_400-900_55.mzML",
                    "Ast-2024-12-05_HeLa_3mzDIA_6mIIT_400-900_60.mzML"
                )
                FileLabel        = @{ Single = "file 49"; All = "files 49-60" }
                DecoysInLibrary  = $true
                Manifest         = "SkylineAI_entrapment_carafe_pairing_manifest_pep.txt"
            }
        }
    }
}
