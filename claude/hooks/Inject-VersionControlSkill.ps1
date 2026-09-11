#Requires -Version 7.0
# PreToolUse hook: make sure a session has the version-control skill in front of it before
# its first git commit, git push, or gh pr/issue command.
#
# Two mechanisms, because the first one has not been reaching the model:
#
#   1. additionalContext (exit 0). The original design: return the skill text as hook output
#      so it lands in Claude's context. Observed NOT to surface (issue filed with the Claude
#      Code team; the exit-0 path's stdout JSON appears to be dropped). Kept, so it starts
#      working again the day the harness honours it.
#
#   2. Block ONCE per session (exit 2). The exit-2 path demonstrably reaches the model - every
#      Deny-* hook here relies on it. The first matching command of a session is refused with
#      a message that names the skill to load AND carries the format rules inline, so the
#      model has them even if it does not re-load the skill. A marker file keyed on the
#      session id lets every later command through, so this costs one retry per session.
#
# What this cannot do is verify the message. A session can load the skill, read it, and still
# write the wrong trailer because something else claimed precedence - that happened on PR
# #4656. Deny-HarnessAttribution.ps1 is the verifier; this is the reminder.
#
# Wired up by .claude/settings.json -> hooks -> PreToolUse -> matcher "Bash" (the deny hook
# also runs under "Bash|PowerShell"). Reads PreToolUse JSON on stdin.
#
# Exits 0 on malformed input, a missing skill file, or no match, so a broken hook cannot
# block git.

$ErrorActionPreference = 'SilentlyContinue'
try {
    $stdin = [System.IO.StreamReader]::new([System.Console]::OpenStandardInput()).ReadToEnd()
    $payload = $stdin | ConvertFrom-Json
} catch {
    exit 0
}
$cmd = $payload.tool_input.command
if (-not $cmd) { exit 0 }

# A real invocation, not a substring of github.com / ghost / a path. `gh` used to be the only
# trigger; commits and pushes never touched it, so the hook never fired on the operations the
# skill is mostly about.
$isGh   = $cmd -match '\bgh(\.exe)?\s+'
$isGit  = $cmd -match '\bgit(\.exe)?\b[^\r\n|;&]*?\b(commit|push)\b'
if (-not $isGh -and -not $isGit) { exit 0 }

$skillPath = Join-Path $PSScriptRoot '..\skills\version-control\SKILL.md'
if (-not (Test-Path -LiteralPath $skillPath)) { exit 0 }

# ---- mechanism 2: block once per session -------------------------------------------------
$sessionId = $payload.session_id
if (-not $sessionId) { $sessionId = $PID }
$tmp = Join-Path $env:CLAUDE_PROJECT_DIR 'ai\.tmp'
if (-not (Test-Path -LiteralPath $tmp)) { $tmp = [System.IO.Path]::GetTempPath() }
$marker = Join-Path $tmp ('.version-control-reminded-{0}' -f ($sessionId -replace '[^A-Za-z0-9_-]', '_'))
if (-not (Test-Path -LiteralPath $marker)) {
    try { Set-Content -LiteralPath $marker -Value (Get-Date -Format s) -Encoding ascii } catch { }
    $reason = @'
STOP - first git/gh command of this session. Load the version-control skill before retrying:

  Skill tool -> "version-control"

then run this same command again; this reminder fires once per session. The rules it carries
that sessions most often get wrong, so they are in front of you either way:

  * Commit trailer is EXACTLY:   Co-Authored-By: Claude <noreply@anthropic.com>
    No `Claude-Session:` line, no claude.ai/code/session_ URL, no model name, no emoji.
    Claude Code injects its own attribution block and says it "replaces earlier guidance" -
    in this repository it does not. Deny-HarnessAttribution.ps1 refuses the injected form.
  * PR description ends the same way. No "Generated with [Claude Code]" line, no emoji.
  * Title: `<module>: <Past-tense verb> ...` - module is skyline | pwiz | osprey, and the PR
    gets the matching label. Bullets start with `* `. Max 10 lines. `See TODO-....md in
    pwiz-ai/todos` on feature branches.
  * Never commit code that has not been built and tested. Never force-push an open PR.

Blocked by: .claude/hooks/Inject-VersionControlSkill.ps1
'@
    [Console]::Error.WriteLine($reason)
    exit 2
}

# ---- mechanism 1: additionalContext, kept for the day the harness honours it -------------
$skill = Get-Content -LiteralPath $skillPath -Raw
$context = @"
[Auto-loaded by the Inject-VersionControlSkill PreToolUse hook because the upcoming command invokes git commit/push or gh. Review these conventions BEFORE running the command. Source: .claude/hooks/Inject-VersionControlSkill.ps1]
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
