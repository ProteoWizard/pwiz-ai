<#
.SYNOPSIS
    Build the Rust Osprey reference binary (fork or upstream tree)

.DESCRIPTION
    Builds the Rust Osprey binary from the specified tree (default
    C:\proj\osprey = brendanx67 fork). Pass -OspreyRoot C:\proj\osprey-mm to
    build the maccoss/osprey upstream tree instead. Used for both the
    fork-as-reference bisection workflow and upstream PR development.

    Sets CMAKE_GENERATOR=Ninja and VCPKG_ROOT so the build works on any
    developer machine independent of which Visual Studio version is installed.

.PARAMETER OspreyRoot
    Path to the osprey Cargo workspace (default: C:\proj\osprey)

.PARAMETER Fmt
    Run `cargo fmt -- --check` before building. Fails fast (non-zero
    exit) if any file would be reformatted, matching the upstream CI
    gate. Use this to catch fmt drift before committing.

.PARAMETER FmtFix
    Run `cargo fmt` (in-place reformat) before building. Use this to
    apply fmt changes to the working tree. Mutually exclusive with
    -Fmt; if both are passed, -Fmt wins.

.PARAMETER Workspace
    Build the full workspace (cargo build --workspace) instead of just the
    osprey binary crate (cargo build -p osprey). Needed for a complete
    baseline sanity check.

.PARAMETER RunTests
    Run cargo test --workspace after building. Implies -Workspace.

.PARAMETER Clippy
    Run cargo clippy --all-targets --all-features -- -D warnings after
    building.

.EXAMPLE
    .\Build-OspreyRust.ps1
    Build Rust Osprey (fork) in release mode

.EXAMPLE
    .\Build-OspreyRust.ps1 -OspreyRoot C:\proj\osprey-mm
    Build the upstream-tracking tree in release mode

.EXAMPLE
    .\Build-OspreyRust.ps1 -OspreyRoot C:\proj\osprey-mm -Workspace -RunTests -Clippy
    Full baseline sanity check against upstream: workspace build, test, lint

.EXAMPLE
    .\Build-OspreyRust.ps1 -Fmt -Clippy
    Check formatting (fail-fast), build fork, and lint. Use this
    before committing.

.EXAMPLE
    .\Build-OspreyRust.ps1 -FmtFix
    Reformat working tree in place via `cargo fmt`. Use this to
    apply rustfmt changes after -Fmt fails.
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$OspreyRoot = "C:\proj\osprey",

    [Parameter(Mandatory=$false)]
    [switch]$Fmt = $false,

    [Parameter(Mandatory=$false)]
    [switch]$FmtFix = $false,

    [Parameter(Mandatory=$false)]
    [switch]$Workspace = $false,

    [Parameter(Mandatory=$false)]
    [switch]$RunTests = $false,

    [Parameter(Mandatory=$false)]
    [switch]$Clippy = $false
)

# -RunTests needs the workspace built
if ($RunTests) {
    $Workspace = $true
}

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
        Write-Host "Running cargo fmt -- --check..." -ForegroundColor Cyan
        cargo fmt -- --check
        if ($LASTEXITCODE -ne 0) {
            Write-Host "cargo fmt --check failed: working tree differs from rustfmt output." -ForegroundColor Red
            Write-Host "Run with -FmtFix to reformat in place, then re-run with -Fmt." -ForegroundColor Yellow
            exit $LASTEXITCODE
        }
        Write-Host "Format check passed" -ForegroundColor Green
        Write-Host ""
    } elseif ($FmtFix) {
        Write-Host "Running cargo fmt (in-place)..." -ForegroundColor Cyan
        cargo fmt
        if ($LASTEXITCODE -ne 0) {
            Write-Host "cargo fmt failed" -ForegroundColor Red
            exit $LASTEXITCODE
        }
        Write-Host "Reformatted working tree" -ForegroundColor Green
        Write-Host ""
    }

    $buildScope = if ($Workspace) { "workspace" } else { "osprey" }
    Write-Host "Building Osprey ($buildScope, release)..." -ForegroundColor Cyan
    $buildStart = Get-Date

    if ($Workspace) {
        cargo build --workspace --release
    } else {
        cargo build --release -p osprey
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Build failed with exit code $LASTEXITCODE" -ForegroundColor Red
        exit $LASTEXITCODE
    }

    $buildDuration = (Get-Date) - $buildStart
    Write-Host "Build succeeded in $($buildDuration.TotalSeconds.ToString('F1'))s" -ForegroundColor Green

    if ($RunTests) {
        Write-Host ""
        Write-Host "Running cargo test --workspace..." -ForegroundColor Cyan
        $testStart = Get-Date
        cargo test --workspace
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Tests failed with exit code $LASTEXITCODE" -ForegroundColor Red
            exit $LASTEXITCODE
        }
        $testDuration = (Get-Date) - $testStart
        Write-Host "Tests passed in $($testDuration.TotalSeconds.ToString('F1'))s" -ForegroundColor Green
    }

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
