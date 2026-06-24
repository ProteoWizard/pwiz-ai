#Requires -Version 7.0
<#
    PreToolUse(Bash) guard: restrict `cd` to the one sanctioned per-session move.

    The Bash tool's shell persists its working directory across calls, so a stray
    `cd` silently changes cwd for every later command and breaks relative paths.

    The ONE exception (sanctioned by CLAUDE.md) is the per-session move into the
    active checkout root at session start. That root is derived from PWIZ_LSP_DIR
    (the full pwiz_tools path) by dropping the trailing pwiz_tools segment -- the
    same derivation Set-ActiveCheckout.ps1 uses to emit the SessionStart hint.

    Policy:
      - No `cd` in the command            -> allow (silent).
      - Every `cd` targets the checkout    -> allow (the sanctioned move).
      - Any other `cd` (different dir, a    -> deny, with guidance.
        subdir, `cd` to home, `cd ..`, ...)
      - Not a sibling-checkout session      -> deny ALL `cd` (no sanctioned target
        (plain claude / single-clone)          exists; original guard behavior).

    Reads the PreToolUse hook payload (JSON) on stdin. Emits a "deny" decision
    when a `cd` is not permitted; otherwise stays silent. Any failure exits 0 so
    a hook hiccup never blocks the Bash tool.
#>

function Norm([string]$p) {
    if ([string]::IsNullOrWhiteSpace($p)) { return '' }
    $p = $p.Trim().Trim('"').Trim("'")
    # Git-Bash/MSYS drive form: /c/Dev -> c:/Dev
    if ($p -match '^/([A-Za-z])/') { $p = $p -replace '^/([A-Za-z])/', '$1:/' }
    $p = $p -replace '\\', '/'
    return $p.TrimEnd('/').ToLowerInvariant()
}

function Get-CheckoutRoot {
    # Active checkout root (norm key) when -- and ONLY when -- this is a
    # sibling-checkout session, else $null. Mirrors Set-ActiveCheckout.ps1's
    # exact conditions, so outside sibling mode this guard stays deny-all.
    $lsp = $env:PWIZ_LSP_DIR
    if ([string]::IsNullOrWhiteSpace($lsp)) { return $null }
    $root = $lsp -replace '[\\/]+pwiz_tools[\\/]*$', ''
    if ($root -eq $lsp) { return $null }                                  # didn't end in pwiz_tools
    if (-not (Test-Path -LiteralPath (Join-Path $root 'pwiz_tools'))) { return $null }  # not a real checkout
    $proj = $env:CLAUDE_PROJECT_DIR
    if (-not [string]::IsNullOrWhiteSpace($proj) -and ((Norm $proj) -eq (Norm $root))) { return $null }  # flat layout
    return (Norm $root)
}

function Get-CdTarget([string]$rest) {
    $rest = $rest.Trim()
    if ($rest.Length -eq 0) { return '' }
    $c = $rest[0]
    if ($c -eq '"' -or $c -eq "'") {
        $end = $rest.IndexOf($c, 1)
        if ($end -ge 0) { return $rest.Substring(1, $end - 1) }
        return $rest.Substring(1)
    }
    return ($rest -split '\s+')[0]
}

function Write-Deny([string]$reason) {
    $out = @{ hookSpecificOutput = @{
        hookEventName            = 'PreToolUse'
        permissionDecision       = 'deny'
        permissionDecisionReason = $reason
    } } | ConvertTo-Json -Compress -Depth 5
    Write-Output $out
}

try {
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }
    $payload = $raw | ConvertFrom-Json
    $command = [string]$payload.tool_input.command
    if ([string]::IsNullOrEmpty($command)) { exit 0 }

    # `cd` as a command word (start, or right after a ; && || | separator),
    # capturing the rest of that segment up to the next separator/newline.
    # Does NOT match substrings like "abcd", "cmd", "cdiff".
    $cdRe = [regex]'(?:^|[;&|])\s*cd\b([^;&|>\n]*)'
    $cds = $cdRe.Matches($command)
    if ($cds.Count -eq 0) { exit 0 }

    $root = Get-CheckoutRoot
    $targets = foreach ($m in $cds) { Get-CdTarget $m.Groups[1].Value }
    $bad = @($targets | Where-Object { [string]::IsNullOrWhiteSpace($_) -or ((Norm $_) -ne $root) })
    $allowed = ($null -ne $root) -and ($bad.Count -eq 0)

    if (-not $allowed) {
        if ($null -ne $root) {
            Write-Deny ("``cd`` is restricted. The only permitted ``cd`` is the sanctioned " +
                "per-session move to the active checkout root ($root). For anything else, " +
                "don't ``cd`` -- the Bash shell persists its working directory, so a stray " +
                "``cd`` breaks later relative-path commands. Use ``git -C <path> ...`` for git, " +
                "absolute paths for other commands, and the Grep/Glob tools (with an explicit " +
                "path) for searching.")
        }
        else {
            Write-Deny ("``cd`` is disabled this session (no active checkout configured). The " +
                "Bash shell persists its working directory, so a stray ``cd`` breaks later " +
                "relative-path commands. Use ``git -C <path> ...`` for git, absolute paths for " +
                "other commands, and the Grep/Glob tools for searching.")
        }
    }
}
catch { exit 0 }

exit 0
