#Requires -Version 7.0
<#
    PreToolUse(Grep|Glob|Bash) guard: keep searches scoped to the active checkout.

    C:\Dev holds many near-identical pwiz checkouts (one per branch). An unscoped
    search fans out across all of them and returns the same symbol duplicated
    across sibling copies. The Grep/Glob tools default their `path` to the project
    ROOT, so omitting it is the main fan-out vector.

    In a sibling-checkout session this guard denies a search whose target is NOT:
      - under the active checkout root (PWIZ_LSP_DIR minus pwiz_tools), or
      - under the project root's ai/ tree (shared tooling/docs), or
      - outside the project root entirely (no sibling fan-out risk).

    Relative tool paths resolve against the project root (the tools' base). For
    the Bash tool, only recursive search commands (rg/grep/find/...) are inspected,
    and only ABSOLUTE path arguments are classified -- a bare search relies on the
    shell cwd, which the cd-guard pins to the active checkout.

    Strict NO-OP outside sibling mode (mirrors Set-ActiveCheckout.ps1), so plain
    `claude` / single-clone layouts are completely unaffected. Any failure exits 0
    so a hook hiccup never blocks a tool.
#>

function Norm([string]$p) {
    if ([string]::IsNullOrWhiteSpace($p)) { return '' }
    $p = $p.Trim().Trim('"').Trim("'")
    if ($p -match '^/([A-Za-z])/') { $p = $p -replace '^/([A-Za-z])/', '$1:/' }   # /c/Dev -> c:/Dev
    $p = $p -replace '\\', '/'
    return $p.TrimEnd('/').ToLowerInvariant()
}

function Get-CheckoutRoot {
    $lsp = $env:PWIZ_LSP_DIR
    if ([string]::IsNullOrWhiteSpace($lsp)) { return $null }
    $root = $lsp -replace '[\\/]+pwiz_tools[\\/]*$', ''
    if ($root -eq $lsp) { return $null }
    if (-not (Test-Path -LiteralPath (Join-Path $root 'pwiz_tools'))) { return $null }
    $proj = $env:CLAUDE_PROJECT_DIR
    if (-not [string]::IsNullOrWhiteSpace($proj) -and ((Norm $proj) -eq (Norm $root))) { return $null }
    return (Norm $root)
}

function Test-Under([string]$abs, [string]$base) {
    return ($abs -eq $base) -or $abs.StartsWith($base + '/')
}

function Test-Allowed([string]$abs, [string]$active, [string]$proj, [string]$ai) {
    if ([string]::IsNullOrEmpty($abs)) { return $true }
    if (-not (Test-Under $abs $proj)) { return $true }   # outside the project tree
    if (Test-Under $abs $active) { return $true }        # inside the active checkout
    if (Test-Under $abs $ai) { return $true }            # shared ai/ tooling
    return $false                                        # project root / sibling / other subtree
}

function Resolve-ToNorm([string]$pathRaw, [string]$proj) {
    $p = $pathRaw.Trim().Trim('"').Trim("'")
    if ([string]::IsNullOrEmpty($p)) { return '' }
    $isAbs = ($p -match '^[A-Za-z]:[\\/]') -or ($p -match '^/[A-Za-z]/') -or $p.StartsWith('/') -or $p.StartsWith('\')
    if ($isAbs) { return (Norm $p) }
    return (Norm ($proj + '/' + $p))
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

    $active = Get-CheckoutRoot
    if ($null -eq $active) { exit 0 }                    # non-sibling: complete no-op
    $proj = Norm $env:CLAUDE_PROJECT_DIR
    if ([string]::IsNullOrEmpty($proj)) { exit 0 }
    $ai = $proj + '/ai'

    $tool = [string]$payload.tool_name
    $scope = "Scope it to the active checkout ($active), a subdir, or '$ai' for shared tooling."

    if ($tool -eq 'Grep' -or $tool -eq 'Glob') {
        $path = [string]$payload.tool_input.path
        if ([string]::IsNullOrWhiteSpace($path)) {
            Write-Deny ("$tool has no ``path``, so it defaults to the project root ($proj) and " +
                "would fan out across the sibling pwiz checkouts. $scope")
            exit 0
        }
        $abs = Resolve-ToNorm $path $proj
        if (-not (Test-Allowed $abs $active $proj $ai)) {
            Write-Deny ("$tool targets '$abs', outside the active checkout -- it would search the " +
                "wrong checkout or fan out across siblings. $scope")
        }
        exit 0
    }

    if ($tool -eq 'Bash') {
        $command = [string]$payload.tool_input.command
        if ([string]::IsNullOrEmpty($command)) { exit 0 }
        $searchRe = [regex]::new('(?<![\w-])(rg|grep|egrep|fgrep|ugrep|find|Select-String)(?![\w-])',
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if (-not $searchRe.IsMatch($command)) { exit 0 }
        # Absolute Windows (C:\..) or MSYS (/c/..) path arguments.
        $tokRe = [regex]'([A-Za-z]:[\\/][^\s"''<>|;&)]*|/[A-Za-z]/[^\s"''<>|;&)]*)'
        $bad = New-Object System.Collections.Generic.List[string]
        foreach ($m in $tokRe.Matches($command)) {
            $abs = Norm $m.Value
            if (-not (Test-Allowed $abs $active $proj $ai)) {
                if (-not $bad.Contains($abs)) { $bad.Add($abs) }
            }
        }
        if ($bad.Count -gt 0) {
            Write-Deny ("This search references " + ($bad -join ', ') + ", outside the active " +
                "checkout. Your Bash cwd is already the checkout, so '.' or a relative path works. " +
                "$scope")
        }
        exit 0
    }
}
catch { exit 0 }

exit 0
