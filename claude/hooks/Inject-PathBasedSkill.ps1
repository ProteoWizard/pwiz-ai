#Requires -Version 7.0

# PreToolUse hook: when Claude is about to Edit/Write/MultiEdit a file under
# pwiz/pwiz_tools/Skyline or pwiz/pwiz_tools/Osprey, inject the
# corresponding skill (skyline-development or osprey-development) SKILL.md
# content into Claude's context. Skill descriptions alone are advisory; this
# hook makes the load deterministic at the moment Claude is about to change
# code in the relevant tree.
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
if ($norm -match '(?i)/pwiz/pwiz_tools/Skyline/') {
    $skillSlug = 'skyline-development'
    $treeLabel = 'pwiz/pwiz_tools/Skyline'
} elseif ($norm -match '(?i)/pwiz/pwiz_tools/Osprey/') {
    $skillSlug = 'osprey-development'
    $treeLabel = 'pwiz/pwiz_tools/Osprey'
}

if (-not $skillSlug) { exit 0 }

$skillPath = Join-Path $PSScriptRoot "..\skills\$skillSlug\SKILL.md"
if (-not (Test-Path -LiteralPath $skillPath)) { exit 0 }

$skill = Get-Content -LiteralPath $skillPath -Raw

$context = @"
[Auto-loaded by Inject-PathBasedSkill PreToolUse hook because the upcoming Edit/Write touches a file under $treeLabel. Apply these conventions to the change. Source: .claude/hooks/Inject-PathBasedSkill.ps1]

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
