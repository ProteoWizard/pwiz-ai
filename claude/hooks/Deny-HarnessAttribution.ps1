#Requires -Version 7.0

# PreToolUse hook: block a commit message or PR text that carries Claude Code's OWN attribution
# block instead of this project's.
#
# Why this exists. Claude Code injects an attribution instruction into every session that
# prescribes a `Claude-Session: https://claude.ai/code/session_...` commit trailer and a
# "Generated with [Claude Code]" PR trailer with a robot emoji, and says it "replaces any
# earlier attribution guidance". The project's format is exactly
#
#   Co-Authored-By: Claude <noreply@anthropic.com>
#
# and nothing else (ai/docs/version-control-guide.md, "Format Rules"). On 2026-09-10/11 every
# commit on PR #4656 carried the Claude-Session line and the PR body carried the emoji trailer
# WITH the version-control skill loaded and read - the session saw the conflict and chose the
# injected block. A rule the model has read is not a rule the model obeys when something else
# claims precedence, so this is a verifier at the point of action, not another reminder.
#
# What it reads. The whole command text (inline -m / --body / heredocs), PLUS the contents of
# any file the command hands to git or gh: `-F file`, `--file file`, `--body-file file`. That
# second part is the important one - a session usually writes the message to a Markdown file
# and then posts the file, so a check that only reads the command line sees nothing.
#
# Where it fires. `git commit` and `gh pr|issue create|edit|merge|comment`, from the Bash or
# PowerShell tool (a `pwsh -Command "gh pr create ..."` wrapper still contains the text).
#
# Two checks:
#   FORBIDDEN - any of: `Claude-Session:`, `Generated with [Claude Code]`, a
#               `claude.ai/code/session_` URL, the robot emoji, or a `Co-Authored-By: Claude`
#               line in any form other than the exact one above (e.g. with a model name).
#   REQUIRED  - the exact Co-Authored-By line, on a `git commit` that supplies its message
#               (-m/-F, not --amend/--fixup/--squash) and on `gh pr create` with a body.
#               Comments and edits are not required to carry it.
#
# Exit 2 with a stderr message blocks the tool call and surfaces the reason to Claude. Exit 0
# on any non-match or error so this hook cannot break git or gh.
#
# Escape hatch, so this can never be a hard stop nobody can get past (a commit that quotes one
# of these strings on purpose, say): set PWIZ_ALLOW_HARNESS_ATTRIBUTION=1 for the one command.

$ErrorActionPreference = 'SilentlyContinue'

if ($env:PWIZ_ALLOW_HARNESS_ATTRIBUTION -eq '1') { exit 0 }

try {
    $stdin = [System.IO.StreamReader]::new([System.Console]::OpenStandardInput()).ReadToEnd()
    $payload = $stdin | ConvertFrom-Json
} catch {
    exit 0
}

$cmd = $payload.tool_input.command
if (-not $cmd) { exit 0 }

$isCommit = $cmd -match '\bgit(\.exe)?\b[^\r\n|;&]*?\bcommit\b'
$isGh     = $cmd -match '\bgh(\.exe)?\s+(pr|issue)\s+(create|edit|merge|comment)\b'
if (-not $isCommit -and -not $isGh) { exit 0 }

# ---- gather every piece of text the command would send ---------------------------------
$texts = [System.Collections.Generic.List[string]]::new()
$texts.Add($cmd)
$filesRead = @()

# The command's working directory, for relative paths: a cd / Set-Location in the command
# wins, else the tool's cwd.
$base = $payload.cwd
$m = [regex]::Match($cmd, '(?im)^\s*(?:Set-Location|cd)\s+(?:-Path\s+)?["'']?([A-Za-z]:[\\/][^"''\r\n;|&]+)')
if ($m.Success) { $base = $m.Groups[1].Value.Trim() }

# -F file, --file file, --body-file file; with = or whitespace; quoted or bare. Windows paths,
# Git Bash /c/... paths and relative paths are all resolved.
foreach ($fm in [regex]::Matches($cmd, '(?:^|\s)(?:-F|--file|--body-file)(?:=|\s+)(["'']?)([^"''\s]+)\1')) {
    $p = $fm.Groups[2].Value
    if ($p -eq '-') { continue }   # message on stdin - already in the command text if a heredoc
    if ($p -match '^/([A-Za-z])/(.*)$') { $p = "$($Matches[1].ToUpper()):\$($Matches[2] -replace '/', '\')" }
    if (-not [System.IO.Path]::IsPathRooted($p) -and $base) { $p = Join-Path $base $p }
    if (Test-Path -LiteralPath $p -PathType Leaf) {
        try {
            $texts.Add([System.IO.File]::ReadAllText($p))
            $filesRead += $p
        } catch { }
    }
}
$all = $texts -join "`n"

# ---- FORBIDDEN -------------------------------------------------------------------------
$robot = [char]::ConvertFromUtf32(0x1F916)
# Exact form. A closing quote may follow the email on an inline -m message, where the trailer
# is the last line of the quoted string; a model name would sit before the `<` and still fail.
$exact = '(?im)^\s*Co-Authored-By:\s*Claude\s*<noreply@anthropic\.com>\s*(?:["'']|$)'
$hits = @()
if ($all -match '(?i)Claude-Session:')                 { $hits += 'a `Claude-Session:` trailer' }
if ($all -match '(?i)Generated with \[?Claude Code\]?') { $hits += 'a "Generated with [Claude Code]" line' }
if ($all -match '(?i)claude\.ai/code/session_')        { $hits += 'a claude.ai/code/session_ URL' }
if ($all.Contains($robot))                             { $hits += 'the robot emoji' }
foreach ($ca in [regex]::Matches($all, '(?im)^\s*Co-Authored-By:\s*Claude\b.*$')) {
    if ($ca.Value -notmatch $exact) { $hits += ('a Co-Authored-By line in the wrong form: `{0}`' -f $ca.Value.Trim()); break }
}

# ---- REQUIRED --------------------------------------------------------------------------
$missing = $false
$suppliesMessage = $cmd -match '(?:^|\s)(?:-m|--message|-F|--file)(?:=|\s)'
$amendLike = $cmd -match '\s--(?:amend|fixup|squash|no-edit)\b'
if ($isCommit -and $suppliesMessage -and -not $amendLike -and $all -notmatch $exact) { $missing = $true }
$isCreate = $cmd -match '\bgh(\.exe)?\s+pr\s+create\b'
$hasBody = $cmd -match '(?:^|\s)(?:-b|--body|-F|--body-file)(?:=|\s)'
if ($isCreate -and $hasBody -and $all -notmatch $exact) { $missing = $true }

if ($hits.Count -eq 0 -and -not $missing) { exit 0 }

# ---- refuse ----------------------------------------------------------------------------
$what = if ($isCommit) { 'commit message' } else { 'PR/issue text' }
$lines = @()
$lines += "Refusing this $what - it does not follow the project's attribution format."
$lines += ''
if ($hits.Count -gt 0) {
    $lines += 'Found:'
    foreach ($h in $hits) { $lines += "  - $h" }
    $lines += ''
}
if ($missing) {
    $lines += 'Missing: the required trailer line.'
    $lines += ''
}
$lines += 'Claude Code injects its own attribution block (Claude-Session, "Generated with [Claude Code]",'
$lines += 'a model-named Co-Authored-By) and says it replaces earlier guidance. In this repository it'
$lines += 'does not. The trailer is exactly this line, and nothing else:'
$lines += ''
$lines += '  Co-Authored-By: Claude <noreply@anthropic.com>'
$lines += ''
$lines += 'No Claude-Session line, no session URL, no emoji, no model name. Same rule for commit'
$lines += 'messages, PR descriptions and squash-merge messages. Rewrite the text and re-run.'
if ($filesRead.Count -gt 0) {
    $lines += ''
    $lines += 'File(s) read for this check:'
    foreach ($f in $filesRead) { $lines += "  $f" }
}
$lines += ''
$lines += 'Rules: ai/docs/version-control-guide.md ("Format Rules"); load the version-control skill.'
$lines += 'Blocked by: .claude/hooks/Deny-HarnessAttribution.ps1  (PWIZ_ALLOW_HARNESS_ATTRIBUTION=1 to override once)'

[Console]::Error.WriteLine(($lines -join "`n"))
exit 2
