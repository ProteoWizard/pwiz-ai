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

    Also records this session under ai/.tmp/sessions so it can be resumed after
    an unexpected restart, and reports any session or build/test run in this
    checkout that a restart interrupted. See ai/scripts/session/SessionState.ps1.

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

    # Restart recovery. Best-effort throughout: this hook's job is the cd
    # instruction, and nothing here may keep that from being emitted.
    $recovery = ''
    try {
        $stateScript = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'scripts\session\SessionState.ps1'
        if (Test-Path -LiteralPath $stateScript) {
            . $stateScript

            # Claude Code passes the session payload as JSON on stdin. Guard on
            # IsInputRedirected so a manual invocation can never block on a read.
            $sessionId = $null; $transcript = $null; $source = $null
            if ([Console]::IsInputRedirected) {
                $payload = [Console]::In.ReadToEnd() | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($payload) {
                    $sessionId  = $payload.session_id
                    $transcript = $payload.transcript_path
                    $source     = $payload.source
                }
            }

            $checkoutName = Get-PwizCheckoutName $checkoutResolved
            $branch = git -C $checkoutResolved rev-parse --abbrev-ref HEAD 2>$null

            # Anything still on record for this checkout never exited cleanly.
            # Ask before writing our own record, so we don't find ourselves.
            $interrupted = Get-PwizInterruptedState -Checkout $checkoutName -ExcludeSessionId $sessionId

            if ($sessionId) {
                Write-PwizSessionRecord -SessionId $sessionId -Checkout $checkoutName `
                    -LspDir $lspDir -Branch $branch -TranscriptPath $transcript -Source $source `
                    -LaunchId $env:SKYCLAUDE_LAUNCH_ID
            }

            if ($interrupted) {
                $cause = if ($interrupted.RebootDetected) { 'a machine restart' } else { 'an unclean exit (crash or closed terminal)' }
                $lines = @("`nInterrupted work in this checkout, from $cause" +
                           ' -- surfaced because the records below outlived their owners:')
                foreach ($s in ($interrupted.Sessions | Select-Object -First 3)) {
                    $lines += "  - session $($s.sessionId) on branch $($s.branch), last active $(Format-PwizLocalTime $s.lastWrite) local."
                }
                if ($interrupted.Sessions) {
                    $lines += "    Its transcript survived; the user can reopen it with 'skyclaude $checkoutName -Resume'."
                }
                foreach ($r in ($interrupted.Runs | Select-Object -First 5)) {
                    $lines += "  - $($r.kind) run '$($r.name)' started $(Format-PwizLocalTime $r.startedUtc) local, never finished: $($r.commandLine)"
                    if ($r.logPath) { $lines += "    partial log: $($r.logPath)" }
                }
                if ($interrupted.Runs) {
                    $lines += '    A killed run can leave orphaned Skyline/TestRunner processes and stale .skyd caches beside its input documents; check before rerunning.'
                }
                $lines += 'Mention this to the user early rather than acting on it unprompted.'
                $recovery = ($lines -join "`n")
            }
        }
    }
    catch { $recovery = '' }

    $msg = "Active checkout for this session: $checkoutResolved`n" +
           "As your FIRST action this session, cd into it -- ``cd $checkoutResolved`` -- " +
           "without asking. This is the sanctioned per-session cd from CLAUDE.md, and the " +
           "cd-guard permits this one target (it still blocks every other cd). Then use " +
           "checkout-relative paths so file and search work stays scoped to this checkout " +
           "and does not fan out across the sibling pwiz copies under the project root." +
           $recovery

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
