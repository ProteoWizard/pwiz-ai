#Requires -Version 7.0

<#
.SYNOPSIS
    Selects the C# LSP workspace (PWIZ_LSP_DIR) and provides a launcher for
    starting Claude Code with the Roslyn LSP scoped to a chosen checkout.

.DESCRIPTION
    The csharp-lsp@pwiz-lsp plugin resolves its workspace from an environment
    variable:

        "workspaceFolder": "${PWIZ_LSP_DIR:-${CLAUDE_PROJECT_DIR}/pwiz/pwiz_tools}"

    PWIZ_LSP_DIR is the full pwiz_tools path. This function appends 'pwiz_tools'
    to the checkout you name, so you pass a checkout name, not the full path.

    - Single-clone layout (one 'pwiz/' clone beside 'ai/'): leave PWIZ_LSP_DIR
      unset. The workspace falls back to ${CLAUDE_PROJECT_DIR}/pwiz/pwiz_tools,
      i.e. the original zero-config behavior. You can ignore this script.

    - Multi-checkout layout (many named clones beside 'ai/' -- e.g. BugFix/,
      IMoffset/, master_clean/ -- and no 'pwiz/' folder): set PWIZ_LSP_DIR to the
      checkout you want indexed BEFORE launching Claude Code. The Roslyn server
      indexes one workspace, fixed at startup (set via LSP 'initialize', not a CLI
      arg), so it cannot switch mid-session -- but each session is typically
      dedicated to one checkout, so per-session scoping is the natural fit.

    Dot-source this from your PowerShell $PROFILE (use your own project root):

        . C:\Dev\ai\scripts\lsp\Enable-PwizLsp.ps1
        $PwizLspDefault = 'master_clean'   # optional: checkout for a no-arg launch

    Then start Claude Code with the 'skyclaude' launcher instead of 'claude':

        skyclaude IMoffset   # scope the C# LSP to <root>\IMoffset\pwiz_tools, then launch
        skyclaude            # use $PwizLspDefault (multi-checkout) or 'pwiz' (single-clone)

.NOTES
    The project root is derived from this script's own location
    (<root>/ai/scripts/lsp/Enable-PwizLsp.ps1), so no per-developer path edits
    are needed -- it works for C:\Dev, C:\proj, D:\repos, etc.
#>

# Project root = three levels up from ai/scripts/lsp. Captured at dot-source
# time because $PSScriptRoot is not available inside the function when it runs
# later.
$Global:PwizClaudeRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path

function Start-PwizClaude {
    [CmdletBinding()]
    param(
        # Name of the checkout directory under the project root to scope the C#
        # LSP to (e.g. 'IMoffset', 'master_clean'). Omit to use $PwizLspDefault,
        # or, in single-clone layouts, the built-in 'pwiz' fallback.
        [Parameter(Position = 0)]
        [string] $Checkout,

        # Anything after the checkout name is passed through to 'claude'.
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]] $ClaudeArgs
    )

    $root = $Global:PwizClaudeRoot

    # PWIZ_LSP_DIR holds the full pwiz_tools path, so append it to the checkout.
    if ($Checkout) {
        $env:PWIZ_LSP_DIR = Join-Path (Join-Path $root $Checkout) 'pwiz_tools'
        if (-not (Test-Path -LiteralPath $env:PWIZ_LSP_DIR)) {
            Write-Warning "$env:PWIZ_LSP_DIR not found -- starting anyway; the C# LSP will have no workspace."
        }
    }
    elseif (-not $env:PWIZ_LSP_DIR) {
        if ($Global:PwizLspDefault) {
            $env:PWIZ_LSP_DIR = Join-Path (Join-Path $root $Global:PwizLspDefault) 'pwiz_tools'
        }
        # else: leave PWIZ_LSP_DIR unset so the plugin's built-in default
        # (${CLAUDE_PROJECT_DIR}/pwiz/pwiz_tools) applies -- correct for single-clone.
    }

    if ($env:PWIZ_LSP_DIR) {
        Write-Host "C# LSP workspace: $env:PWIZ_LSP_DIR" -ForegroundColor DarkGray
    }
    else {
        Write-Host "C# LSP workspace: <root>\pwiz\pwiz_tools (PWIZ_LSP_DIR unset)" -ForegroundColor DarkGray
    }

    Set-Location -LiteralPath $root
    claude @ClaudeArgs
}

Set-Alias -Name skyclaude -Value Start-PwizClaude
