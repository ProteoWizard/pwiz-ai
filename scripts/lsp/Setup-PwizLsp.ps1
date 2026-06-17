#Requires -Version 7.0

<#
.SYNOPSIS
    One-shot setup for the pwiz C# LSP (csharp-lsp@pwiz-lsp): checks
    prerequisites, wires PWIZ_LSP_DIR / skyclaude into your PowerShell $PROFILE,
    and prints the remaining in-Claude-Code steps.

.DESCRIPTION
    Run once per machine, in PowerShell 7 (pwsh):

        pwsh -File C:\Dev\ai\scripts\lsp\Setup-PwizLsp.ps1

    What it does (all idempotent):
      1. Verifies the VS Code C# extension (the Roslyn LSP host) is installed and
         that a compatible .NET runtime is present (the exit-code-150 trap).
      2. Adds a marked block to your $PROFILE that dot-sources Enable-PwizLsp.ps1
         and sets $PwizLspDefault. Re-running updates the block in place.
      3. Prints the /plugin commands to run inside Claude Code (a shell script
         cannot invoke Claude Code slash commands) and the relaunch instruction.

    The project root and the path to Enable-PwizLsp.ps1 are derived from this
    script's own location, so there is nothing machine-specific to edit.

.PARAMETER Default
    Checkout (directory under the project root) that a no-argument `skyclaude`
    should index. Defaults to 'master_clean'. Use 'pwiz' on a single-clone layout.

.PARAMETER WhatIfProfile
    Show the $PROFILE block that would be written, without modifying $PROFILE.

.PARAMETER Verify
    Skip setup; instead read the most recent Roslyn LSP log under
    ai/.tmp/state/roslyn-logs/ and print which workspace/solution it loaded, so
    you can confirm PWIZ_LSP_DIR resolved to the checkout you expected.

.EXAMPLE
    pwsh -File C:\Dev\ai\scripts\lsp\Setup-PwizLsp.ps1 -Default IMoffset

.EXAMPLE
    pwsh -File C:\Dev\ai\scripts\lsp\Setup-PwizLsp.ps1 -Verify
#>

[CmdletBinding()]
param(
    [string] $Default = 'master_clean',
    [switch] $WhatIfProfile,
    [switch] $Verify
)

$ErrorActionPreference = 'Stop'

# Project root = three levels up from ai/scripts/lsp.
$root          = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$enableScript  = Join-Path $PSScriptRoot 'Enable-PwizLsp.ps1'
$logDir        = Join-Path $root 'ai\.tmp\state\roslyn-logs'

function Write-Step { param($n, $msg) Write-Host "`n[$n] $msg" -ForegroundColor Cyan }
function Write-Ok   { param($msg) Write-Host "  OK   $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "  WARN $msg" -ForegroundColor Yellow }

# ---------------------------------------------------------------------------
# -Verify: inspect the Roslyn log and report the loaded workspace, then exit.
# ---------------------------------------------------------------------------
if ($Verify) {
    Write-Host "pwiz C# LSP - verify loaded workspace" -ForegroundColor Cyan
    Write-Host "PWIZ_LSP_DIR (this shell): $(if ($env:PWIZ_LSP_DIR) { $env:PWIZ_LSP_DIR } else { '<unset>' })"
    if (-not (Test-Path -LiteralPath $logDir)) {
        Write-Warn "No log directory yet ($logDir). Start a session and read a .cs file first."
        return
    }
    $log = Get-ChildItem -LiteralPath $logDir -Filter '*.log' -ErrorAction SilentlyContinue |
           Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $log) { Write-Warn "No *.log files under $logDir yet."; return }

    Write-Host "Latest log: $($log.FullName)  ($($log.LastWriteTime))"
    Write-Host "Workspace / solution lines:" -ForegroundColor Cyan
    $hits = Select-String -LiteralPath $log.FullName -Pattern 'pwiz_tools|\.sln\b|workspace|Loading project' -SimpleMatch:$false |
            Select-Object -First 25
    if ($hits) { $hits | ForEach-Object { "  $($_.Line.Trim())" } }
    else { Write-Warn "No workspace/solution lines found - the server may still be starting." }
    return
}

Write-Host "pwiz C# LSP setup" -ForegroundColor Cyan
Write-Host "Project root: $root"

# ---------------------------------------------------------------------------
# 1. Prerequisites: VS Code C# extension (Roslyn LSP host) + .NET runtime.
# ---------------------------------------------------------------------------
Write-Step 1 "Checking prerequisites"

$extRoot = Join-Path $env:USERPROFILE '.vscode\extensions'
$ext = Get-ChildItem -LiteralPath $extRoot -Directory -Filter 'ms-dotnettools.csharp-*' -ErrorAction SilentlyContinue |
       Sort-Object LastWriteTime -Descending | Select-Object -First 1

if (-not $ext) {
    Write-Warn "VS Code C# extension not found under $extRoot"
    Write-Warn "Install it (the Roslyn LSP binary ships inside it):"
    Write-Warn "    winget install Microsoft.VisualStudioCode   # if VS Code is missing"
    Write-Warn "    code --install-extension ms-dotnettools.csharp"
}
else {
    $serverExe = Join-Path $ext.FullName '.roslyn\Microsoft.CodeAnalysis.LanguageServer.exe'
    if (Test-Path -LiteralPath $serverExe) {
        Write-Ok "C# extension: $($ext.Name)"
    }
    else {
        Write-Warn "C# extension found but Roslyn server missing at $serverExe - reinstall the extension."
    }

    # .NET runtime vs the server's pinned major version (exit-code-150 trap).
    $rtConfig = Join-Path $ext.FullName '.roslyn\Microsoft.CodeAnalysis.LanguageServer.runtimeconfig.json'
    if (Test-Path -LiteralPath $rtConfig) {
        $required = $null
        try {
            $cfg = Get-Content -LiteralPath $rtConfig -Raw | ConvertFrom-Json
            $v = $cfg.runtimeOptions.framework.version
            if ($v -match '^(\d+)\.') { $required = [int]$Matches[1] }
        } catch { }

        if ($required) {
            $installed = @()
            if (Get-Command dotnet -ErrorAction SilentlyContinue) {
                $installed = dotnet --list-runtimes 2>$null |
                    Select-String 'Microsoft\.NETCore\.App (\d+)\.' |
                    ForEach-Object { [int]$_.Matches[0].Groups[1].Value } |
                    Sort-Object -Unique
            }
            $max = ($installed | Measure-Object -Maximum).Maximum
            if ($installed -and $max -ge $required) {
                Write-Ok ".NET runtime: net$required required, .NET $max installed"
            }
            else {
                $have = if ($installed) { ".NET $max found" } else { 'none detected' }
                Write-Warn ".NET $required runtime needed ($have). Without it the LSP host crashes (exit 150)."
                Write-Warn "    winget install Microsoft.DotNet.Runtime.$required   # VS 2026 also installs .NET 10"
            }
        }
    }
}

# ---------------------------------------------------------------------------
# 2. Validate the chosen default checkout.
# ---------------------------------------------------------------------------
Write-Step 2 "Validating default checkout '$Default'"
$defaultPwizTools = Join-Path (Join-Path $root $Default) 'pwiz_tools'
if (Test-Path -LiteralPath $defaultPwizTools) {
    Write-Ok "$defaultPwizTools exists"
}
else {
    Write-Warn "No pwiz_tools at $defaultPwizTools - 'skyclaude' with no argument will have no workspace."
    Write-Warn "Pick an existing checkout: pwsh -File '$PSCommandPath' -Default <name>"
}

# ---------------------------------------------------------------------------
# 3. Wire PWIZ_LSP_DIR / skyclaude into $PROFILE (idempotent, marked block).
# ---------------------------------------------------------------------------
Write-Step 3 "Updating PowerShell `$PROFILE"

if (-not (Test-Path -LiteralPath $enableScript)) {
    throw "Enable-PwizLsp.ps1 not found at $enableScript - is this script in ai/scripts/lsp?"
}

$blockLines = @(
    '# >>> pwiz-lsp (PWIZ_LSP_DIR / skyclaude) >>>',
    ". `"$enableScript`"",
    "`$PwizLspDefault = '$Default'",
    '# <<< pwiz-lsp <<<'
)
$block = $blockLines -join [Environment]::NewLine

$profilePath = $PROFILE   # CurrentUserCurrentHost (pwsh 7)
$profileDir  = Split-Path -Parent $profilePath
if (-not (Test-Path -LiteralPath $profileDir)) {
    New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
}

$existing = ''
if (Test-Path -LiteralPath $profilePath) {
    $existing = Get-Content -LiteralPath $profilePath -Raw
}

$pattern = '(?s)# >>> pwiz-lsp.*?# <<< pwiz-lsp <<<'
if ($existing -match $pattern) {
    # MatchEvaluator avoids $-substitution in the replacement text.
    $new    = [regex]::Replace($existing, $pattern, { param($m) $block })
    $action = "Updated existing pwiz-lsp block in"
}
else {
    $sep    = if ($existing -and -not $existing.EndsWith("`n")) { [Environment]::NewLine } else { '' }
    $new    = $existing + $sep + $block + [Environment]::NewLine
    $action = "Added pwiz-lsp block to"
}

if ($WhatIfProfile) {
    Write-Host "  (--WhatIfProfile) would write this block to $profilePath :" -ForegroundColor DarkGray
    $block -split "`n" | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
}
else {
    Set-Content -LiteralPath $profilePath -Value $new -Encoding utf8 -NoNewline
    Write-Ok "$action $profilePath"
    Write-Host "  Default checkout for a no-arg 'skyclaude': $Default" -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------------
# 4. Remaining manual steps (slash commands run inside Claude Code).
# ---------------------------------------------------------------------------
Write-Step 4 "Finish inside Claude Code (these are slash commands, not shell)"

@"
  Register and install the plugin (once):

      /plugin marketplace add $($root.Replace('\','/'))/ai/claude/plugins/pwiz-lsp
      /plugin install csharp-lsp@pwiz-lsp
      /reload-plugins

  Then open a NEW PowerShell window (so `$PROFILE reloads) and start Claude Code
  with the launcher so PWIZ_LSP_DIR is set before the LSP server starts:

      skyclaude $Default          # or: skyclaude <some-checkout>

  Verify it indexed the right tree:
      - In Claude Code, ask for find-references on 'SrmDocument'
        (a loaded workspace returns thousands of hits across hundreds of files).
      - Or from a shell:  pwsh -File '$PSCommandPath' -Verify
"@ | Write-Host -ForegroundColor Gray

Write-Host "`nDone." -ForegroundColor Cyan
