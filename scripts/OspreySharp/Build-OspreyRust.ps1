<#
.SYNOPSIS
    Build the Rust Osprey reference binary (our fork)

.DESCRIPTION
    Builds the Rust Osprey binary from C:\proj\osprey for use as the reference
    implementation in cross-implementation bisection work.

.PARAMETER Fmt
    Run cargo fmt before building

.PARAMETER Clippy
    Run cargo clippy after building

.EXAMPLE
    .\Build-OspreyRust.ps1
    Build Rust Osprey in release mode

.EXAMPLE
    .\Build-OspreyRust.ps1 -Fmt -Clippy
    Format, build, and lint
#>

param(
    [Parameter(Mandatory=$false)]
    [switch]$Fmt = $false,

    [Parameter(Mandatory=$false)]
    [switch]$Clippy = $false,

    [Parameter(Mandatory=$false)]
    [string]$OspreyRoot = "C:\proj\osprey"
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

if (-not (Test-Path $OspreyRoot)) {
    Write-Host "Osprey root not found at: $OspreyRoot" -ForegroundColor Red
    exit 1
}

$initialLocation = Get-Location

try {
    Set-Location $OspreyRoot

    # Set up environment for vcpkg + OpenBLAS
    $env:VCPKG_ROOT = "$env:USERPROFILE\vcpkg"
    $env:CMAKE_GENERATOR = "Ninja"

    if ($Fmt) {
        Write-Host "Running cargo fmt..." -ForegroundColor Cyan
        cargo fmt
        if ($LASTEXITCODE -ne 0) {
            Write-Host "cargo fmt failed" -ForegroundColor Red
            exit $LASTEXITCODE
        }
        Write-Host "Format check passed" -ForegroundColor Green
        Write-Host ""
    }

    Write-Host "Building Osprey (release)..." -ForegroundColor Cyan
    $buildStart = Get-Date

    cargo build --release -p osprey
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Build failed with exit code $LASTEXITCODE" -ForegroundColor Red
        exit $LASTEXITCODE
    }

    $buildDuration = (Get-Date) - $buildStart
    Write-Host "Build succeeded in $($buildDuration.TotalSeconds.ToString('F1'))s" -ForegroundColor Green

    if ($Clippy) {
        Write-Host ""
        Write-Host "Running cargo clippy..." -ForegroundColor Cyan
        cargo clippy --all-targets --all-features -- -D warnings
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Clippy found warnings/errors" -ForegroundColor Red
            exit $LASTEXITCODE
        }
        Write-Host "Clippy passed" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "Binary: $OspreyRoot\target\release\osprey.exe" -ForegroundColor Gray
    Write-Host "All operations completed successfully" -ForegroundColor Green
}
finally {
    Set-Location $initialLocation
}
