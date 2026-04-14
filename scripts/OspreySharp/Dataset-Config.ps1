<#
.SYNOPSIS
    Shared dataset configuration for OspreySharp test scripts.

.DESCRIPTION
    Dot-source this file to get the Get-DatasetConfig function, which returns
    a hashtable with all dataset-specific paths and settings.

    Supported datasets: Stellar, Astral

.EXAMPLE
    . "$PSScriptRoot\Dataset-Config.ps1"
    $ds = Get-DatasetConfig "Stellar"
    $ds.TestDir    # D:\test\osprey-runs\stellar
    $ds.Resolution # unit
#>

function Get-DatasetConfig {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet("Stellar", "Astral")]
        [string]$Dataset
    )

    $baseDir = "D:\test\osprey-runs"

    switch ($Dataset) {
        "Stellar" {
            @{
                Name       = "Stellar"
                TestDir    = Join-Path $baseDir "stellar"
                Library    = "hela-filtered-SkylineAI_spectral_library.tsv"
                Resolution = "unit"
                SingleFile = "Ste-2024-12-02_HeLa_4mz_sDIA_400-900_20.mzML"
                AllFiles   = @(
                    "Ste-2024-12-02_HeLa_4mz_sDIA_400-900_20.mzML",
                    "Ste-2024-12-02_HeLa_4mz_sDIA_400-900_21.mzML",
                    "Ste-2024-12-02_HeLa_4mz_sDIA_400-900_22.mzML"
                )
                FileLabel  = @{ Single = "file 20"; All = "files 20-22" }
            }
        }
        "Astral" {
            @{
                Name       = "Astral"
                TestDir    = Join-Path $baseDir "astral"
                Library    = "SkylineAI_spectral_library.tsv"
                Resolution = "hram"
                SingleFile = "Ast-2024-12-05_HeLa_3mzDIA_6mIIT_400-900_49.mzML"
                AllFiles   = @(
                    "Ast-2024-12-05_HeLa_3mzDIA_6mIIT_400-900_49.mzML",
                    "Ast-2024-12-05_HeLa_3mzDIA_6mIIT_400-900_55.mzML",
                    "Ast-2024-12-05_HeLa_3mzDIA_6mIIT_400-900_60.mzML"
                )
                FileLabel  = @{ Single = "file 49"; All = "files 49-60" }
            }
        }
    }
}
