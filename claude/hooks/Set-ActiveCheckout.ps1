#Requires -Version 7.0
<#
    SessionStart hook: if PWIZ_LSP_DIR points at a sibling checkout's pwiz_tools,
    inject context telling Claude to cd into that checkout root once.

    Deliberately a NO-OP in non-sibling mode. It emits nothing when:
      - PWIZ_LSP_DIR is unset (plain `claude`, not `skyclaude`),
      - the value doesn't end in a pwiz_tools segment,
      - the derived checkout isn't real (no pwiz_tools under it),
      - the checkout IS the project root (single-clone / flat layout — no
        siblings to disambiguate against, and cd-ing there is pointless).
    Any failure exits 0 so a hook hiccup never disrupts session start.

    Pairs with Restrict-Cd.ps1 (permits exactly the sanctioned cd into this
    checkout root) and Restrict-SearchScope.ps1 (keeps searches scoped to it).
#>

$ErrorActionPreference = 'Stop'

try {
    $lspDir = $env:PWIZ_LSP_DIR
    if ([string]::IsNullOrWhiteSpace($lspDir)) { exit 0 }

    # Drop a trailing pwiz_tools segment to get the checkout root.
    $checkout = $lspDir -replace '[\\/]+pwiz_tools[\\/]*$', ''
    if ($checkout -eq $lspDir) { exit 0 }   # didn't end in pwiz_tools

    # Must be a real checkout (has pwiz_tools under it).
    if (-not (Test-Path -LiteralPath (Join-Path $checkout 'pwiz_tools'))) { exit 0 }

    $checkoutResolved = (Resolve-Path -LiteralPath $checkout -ErrorAction SilentlyContinue).Path
    if (-not $checkoutResolved) { exit 0 }

    # If the checkout IS the project root, this is a non-sibling layout: nothing to do.
    $proj = $env:CLAUDE_PROJECT_DIR
    if ($proj) {
        $projResolved = (Resolve-Path -LiteralPath $proj -ErrorAction SilentlyContinue).Path
        if ($projResolved -and ($projResolved -eq $checkoutResolved)) { exit 0 }
    }

    $msg = "Active checkout for this session: $checkoutResolved`n" +
           "As your FIRST action this session, cd into it -- ``cd $checkoutResolved`` -- " +
           "without asking. This is the sanctioned per-session cd from CLAUDE.md, and the " +
           "cd-guard permits this one target (it still blocks every other cd). Then use " +
           "checkout-relative paths so file and search work stays scoped to this checkout " +
           "and does not fan out across the sibling pwiz copies under the project root."

    $out = @{
        hookSpecificOutput = @{
            hookEventName     = 'SessionStart'
            additionalContext = $msg
        }
    } | ConvertTo-Json -Compress

    Write-Output $out
}
catch {
    exit 0
}
