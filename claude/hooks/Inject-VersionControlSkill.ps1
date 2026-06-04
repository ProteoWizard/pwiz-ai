#Requires -Version 7.0

# PreToolUse hook: when Claude is about to invoke gh or gh.exe (any subcommand)
# via the Bash tool, inject the version-control skill content into Claude's
# context. This makes skill loading deterministic for git/GitHub operations,
# where the skill description alone ("ALWAYS load before git commit, push, or
# PR") was observed to be unreliable.
#
# Wired up by .claude/settings.json -> hooks -> PreToolUse -> matcher "Bash".
# Reads PreToolUse JSON on stdin, writes hook output JSON on stdout.
#
# Exits 0 on every path (including malformed input, missing skill file, no
# match) so a broken hook cannot block Bash operations.

$ErrorActionPreference = 'SilentlyContinue'

try {
    $stdin = [System.IO.StreamReader]::new([System.Console]::OpenStandardInput()).ReadToEnd()
    $payload = $stdin | ConvertFrom-Json
} catch {
    exit 0
}

$cmd = $payload.tool_input.command
if (-not $cmd) { exit 0 }

# Match "gh" or "gh.exe" as a whole word followed by whitespace (i.e., a real
# command invocation, not a substring of github.com / ghost / etc.).
if ($cmd -notmatch '\bgh(\.exe)?\s+') {
    exit 0
}

$skillPath = Join-Path $PSScriptRoot '..\skills\version-control\SKILL.md'
if (-not (Test-Path -LiteralPath $skillPath)) { exit 0 }

$skill = Get-Content -LiteralPath $skillPath -Raw

$context = @"
[Auto-loaded by the Inject-VersionControlSkill PreToolUse hook because the upcoming Bash command invokes gh. Review these conventions BEFORE running the command. Source: .claude/hooks/Inject-VersionControlSkill.ps1]

$skill
"@

$output = @{
    hookSpecificOutput = @{
        hookEventName     = 'PreToolUse'
        additionalContext = $context
    }
}

$output | ConvertTo-Json -Depth 5 -Compress
exit 0
