<#
.SYNOPSIS
    Shared dataset configuration for OspreySharp test scripts.

.DESCRIPTION
    Dot-source this file to get the Get-DatasetConfig function, which returns
    a hashtable with all dataset-specific paths and settings.

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

.EXAMPLE
    . "$PSScriptRoot\Dataset-Config.ps1"
    $ds = Get-DatasetConfig "Stellar"
    $ds.TestDir    # D:\test\osprey-runs\stellar (or override)
    $ds.Resolution # unit

.EXAMPLE
    $ds = Get-DatasetConfig "Stellar" -TestBaseDir "C:\test\osprey-runs"
    $ds.TestDir    # C:\test\osprey-runs\stellar
#>

function Get-DatasetConfig {
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateSet("Stellar", "Astral", "AstralLibraryDecoy")]
        [string]$Dataset,

        [Parameter(Mandatory=$false)]
        [string]$TestBaseDir = $null
    )

    # Precedence: explicit -TestBaseDir, then env var, then hardcoded default.
    if ([string]::IsNullOrEmpty($TestBaseDir)) {
        if ($env:OSPREY_TEST_BASE_DIR) {
            $baseDir = $env:OSPREY_TEST_BASE_DIR
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
