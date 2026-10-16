#Requires -Version 7.0

# PreToolUse hook: when Claude is about to Edit/Write/MultiEdit a file under
# pwiz_tools/Skyline or pwiz_tools/Osprey (in any pwiz checkout), remind it to
# load the corresponding skill (skyline-development or osprey-development).
# Skill descriptions alone are advisory; this puts the reminder in front of
# Claude at the moment it is about to change code in the relevant tree.
#
# A one-line reminder, deliberately. This hook used to inject the whole
# SKILL.md (~20 KB of JSON) on every edit. That cost context on every edit when
# it got through, and near that size the harness truncates hook output and
# rejects it as invalid JSON, so it stopped getting through at all. Loading the
# skill once is cheaper than re-reading it on every edit.
#
# Wired up by .claude/settings.json -> PreToolUse -> matcher
# "Edit|Write|MultiEdit". Exits 0 on every path (including malformed input,
# missing skill, non-matching path) so a broken hook cannot block file ops.

$ErrorActionPreference = 'SilentlyContinue'

try {
    $stdin = [System.IO.StreamReader]::new([System.Console]::OpenStandardInput()).ReadToEnd()
    $payload = $stdin | ConvertFrom-Json
} catch {
    exit 0
}

$path = $payload.tool_input.file_path
if (-not $path) { exit 0 }

# Normalize separators for consistent matching regardless of which slash
# style the caller used.
$norm = $path -replace '\\', '/'

$skillSlug = $null
$treeLabel = $null
if ($norm -match '(?i)/pwiz_tools/Skyline/') {
    $skillSlug = 'skyline-development'
    $treeLabel = 'pwiz_tools/Skyline'
} elseif ($norm -match '(?i)/pwiz_tools/Osprey/') {
    $skillSlug = 'osprey-development'
    $treeLabel = 'pwiz_tools/Osprey'
}

if (-not $skillSlug) { exit 0 }

$skillPath = Join-Path $PSScriptRoot "..\skills\$skillSlug\SKILL.md"
if (-not (Test-Path -LiteralPath $skillPath)) { exit 0 }

$output = @{
    hookSpecificOutput = @{
        hookEventName     = 'PreToolUse'
        additionalContext = "Editing $treeLabel`: load the $skillSlug skill before making this change, if you have not already."
    }
}

$output | ConvertTo-Json -Depth 5 -Compress
exit 0
