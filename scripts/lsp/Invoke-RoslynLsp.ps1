#Requires -Version 7.0

# Invoke-RoslynLsp.ps1 -- launcher for Microsoft.CodeAnalysis.LanguageServer
# (the Roslyn-based C# language server bundled with the VS Code C# extension).
#
# Finds the most recently installed ms-dotnettools.csharp-* extension and
# execs its bundled .roslyn/Microsoft.CodeAnalysis.LanguageServer.exe.
# The server inherits stdio directly, so the LSP JSON-RPC stream passes
# through unchanged. Errors surface in Claude Code's /plugin Errors tab.
#
# Path discovery is dynamic to survive VS Code C# extension version bumps
# (the previous static path embedded version 2.130.5 and would have broken
# on every C# extension update).
#
# See ai/claude/plugins/pwiz-lsp/csharp-lsp/README.md.

$ErrorActionPreference = 'Stop'

$extRoot = Join-Path $env:USERPROFILE '.vscode\extensions'

if (-not (Test-Path -LiteralPath $extRoot)) {
    [Console]::Error.WriteLine("pwiz csharp-lsp: VS Code extensions dir not found: $extRoot")
    [Console]::Error.WriteLine("Install VS Code, then install the C# extension (ms-dotnettools.csharp).")
    exit 1
}

# Pick the most recently written ms-dotnettools.csharp-* directory.
# LastWriteTime tracks installs/updates more reliably than parsing the
# version suffix (which varies between -win32-x64, -linux-x64, etc.).
$extDir = Get-ChildItem -LiteralPath $extRoot -Directory -Filter 'ms-dotnettools.csharp-*' -ErrorAction SilentlyContinue |
          Sort-Object LastWriteTime -Descending |
          Select-Object -First 1

if (-not $extDir) {
    [Console]::Error.WriteLine("pwiz csharp-lsp: VS Code C# extension (ms-dotnettools.csharp) not found under $extRoot")
    [Console]::Error.WriteLine("Install via: code --install-extension ms-dotnettools.csharp")
    exit 1
}

$serverExe = Join-Path $extDir.FullName '.roslyn\Microsoft.CodeAnalysis.LanguageServer.exe'

if (-not (Test-Path -LiteralPath $serverExe)) {
    [Console]::Error.WriteLine("pwiz csharp-lsp: Roslyn LSP server not found at $serverExe")
    [Console]::Error.WriteLine("The C# extension at $($extDir.FullName) appears incomplete; reinstall it.")
    exit 1
}

# The server is an apphost pinned to a .NET major version (see its
# runtimeconfig.json). Without a matching machine-wide runtime it exits 150.
# Installing one under C:\Program Files\dotnet needs admin, so on locked-down
# machines the runtime lives in a per-user install at %USERPROFILE%\.dotnet -
# which the apphost does not search unless DOTNET_ROOT points at it. Set that
# for this process only, and only when the machine-wide install falls short.
if (-not $env:DOTNET_ROOT) {
    $rtConfig = Join-Path $extDir.FullName '.roslyn\Microsoft.CodeAnalysis.LanguageServer.runtimeconfig.json'
    $required = $null
    if (Test-Path -LiteralPath $rtConfig) {
        try {
            $v = (Get-Content -LiteralPath $rtConfig -Raw | ConvertFrom-Json).runtimeOptions.framework.version
            if ($v -match '^(\d+)\.') { $required = $Matches[1] }
        } catch { }
    }

    if ($required) {
        $userRoot   = Join-Path $env:USERPROFILE '.dotnet'
        $frameworks = Join-Path $userRoot "shared\Microsoft.NETCore.App\$required.*"
        $machine    = Join-Path $env:ProgramFiles "dotnet\shared\Microsoft.NETCore.App\$required.*"
        if (-not (Test-Path -Path $machine) -and (Test-Path -Path $frameworks)) {
            $env:DOTNET_ROOT = $userRoot
        }
    }
}

# $PSScriptRoot is ai/scripts/lsp; ai root is two levels up.
$aiRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$logDir = Join-Path $aiRoot '.tmp\state\roslyn-logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

& $serverExe `
    --stdio `
    --logLevel Information `
    --telemetryLevel off `
    --extensionLogDirectory $logDir `
    --autoLoadProjects

exit $LASTEXITCODE
