#Requires -Version 7.0

# PreToolUse hook: when Claude is about to commit (git commit) or open/edit a PR
# (gh pr create / gh pr edit --body...) whose text closes a GitHub issue or links
# a skyline.ms support thread, but the text carries NO "Reported by <First>." /
# "Requested by <First>." credit line, inject a reminder to check the origin and
# credit the originator. See ai/docs/version-control-guide.md, "Crediting
# Reporters and Requesters".
#
# This is a NON-BLOCKING nudge: it cannot resolve the reporter name itself (that
# needs the LabKey core.Users lookup, which only Claude can run) — it only flags
# the gap so the credit isn't silently lost when a teammate filed the issue.
#
# Wired up by .claude/settings.json -> hooks -> PreToolUse -> matcher "Bash".
# Reads PreToolUse JSON on stdin, writes hook output JSON on stdout.
# Exits 0 on every path so a broken hook can never block git/gh operations.

$ErrorActionPreference = 'SilentlyContinue'

try {
    $stdin = [System.IO.StreamReader]::new([System.Console]::OpenStandardInput()).ReadToEnd()
    $payload = $stdin | ConvertFrom-Json
} catch {
    exit 0
}

$cmd = $payload.tool_input.command
if (-not $cmd) { exit 0 }

# Only consider commits and PR create/edit (with a body). Anything else: ignore.
$isCommit = $cmd -match '\bgit\s+commit\b'
$isPrBody = ($cmd -match '\bgh(\.exe)?\s+pr\s+(create|edit)\b') -and ($cmd -match '--body\b|--body-file\b|-F\b|-b\b')
if (-not ($isCommit -or $isPrBody)) { exit 0 }

# Gather the text to scan: the command itself (inline -m / heredoc bodies appear
# here) plus the contents of any --body-file / -F file argument.
$text = $cmd
try {
    $m = [regex]::Match($cmd, '(?:--body-file|--file|-F)\s+(?:"([^"]+)"|''([^'']+)''|(\S+))')
    if ($m.Success) {
        $path = @($m.Groups[1].Value, $m.Groups[2].Value, $m.Groups[3].Value | Where-Object { $_ })[0]
        if ($path -and (Test-Path -LiteralPath $path)) {
            $text += "`n" + (Get-Content -LiteralPath $path -Raw)
        }
    }
} catch { }

# Does the change claim to close an issue or come from support?
$closesIssue = $text -match '(?im)\b(fix(e[sd])?|close[sd]?|resolve[sd]?)\s+#\d+'
$linksSupport = $text -match '(?i)skyline\.ms[^\s]*(support|announcements-thread)'
if (-not ($closesIssue -or $linksSupport)) { exit 0 }

# Already credited? Then nothing to do.
if ($text -match '(?im)\b(reported|requested)\s+by\s+\S') { exit 0 }

$reminder = @"
[Check-ReporterCredit hook] This commit/PR closes an issue or links a support thread but has NO 'Reported by <First>.' / 'Requested by <First>.' line.

Before proceeding, confirm the origin:
- If the change came from a user report/request, CREDIT the originator (first name only) on its own line — 'Requested by <First>.' for a feature request, 'Reported by <First>.' for a bug — in BOTH the commit message and the PR description.
- The originator is often a support-board user even when a teammate filed the issue, so check the issue body for a support-thread link and resolve the name: mcp__labkey__get_support_thread on the rowId; if it shows only a numeric user id, resolve via core.Users (mcp__labkey__fetch_labkey_page query-executeQuery.view, schemaName=core, queryName=Users, query.UserId~eq=<id> -> Display Name).
- If the change was found internally (no user origin), no credit is needed — proceed.

Full rules: ai/docs/version-control-guide.md, 'Crediting Reporters and Requesters'.
"@

$output = @{
    hookSpecificOutput = @{
        hookEventName     = 'PreToolUse'
        additionalContext = $reminder
    }
}

$output | ConvertTo-Json -Depth 5 -Compress
exit 0
