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
