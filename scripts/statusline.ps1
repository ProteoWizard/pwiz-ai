<#
.SYNOPSIS
    Claude Code statusline script - displays project, git branch, model, and context usage.

.DESCRIPTION
    This script provides a dynamic status line for Claude Code showing:
    - Active project name and git branch (supports sibling mode multi-repo setups)
    - Model name (e.g., Opus, Sonnet)
    - Context window usage percentage

    Example outputs:
    - pwiz [Skyline/work/20260113_feature] | Opus | 49% left
    - pwiz-ai [master] | Opus | 73% left

    In sibling mode (multiple repos under a common root), Claude can set the
    active project via the StatusMcp's set_active_project tool. The statusline
    then shows that project's branch regardless of which directory Claude Code
    was started from.

.SETUP
    This is a personal preference setting, not a project-wide setting.
    To enable, add the following to your personal Claude Code settings:

    Windows: %USERPROFILE%\.claude\settings.json
    macOS/Linux: ~/.claude/settings.json

    Contents (adjust path to match your ai/ checkout location):
    {
      "statusLine": {
        "type": "command",
        "command": "pwsh -NoProfile -File <your-root>\\ai\\scripts\\statusline.ps1"
      }
    }

    Note: Reference the script directly from pwiz-ai checkout rather than
    copying it. This ensures you always have the latest version.

.NOTES
    The script receives JSON data from Claude Code via stdin containing:
    - workspace.project_dir: The project root directory
    - model.display_name: Current model name
    - context_window.current_usage: Token usage statistics
    - context_window.context_window_size: Total context window size

    Active project state file:
    - Per-session: ai/.tmp/active-project-<ppid>.json (preferred)
    - Legacy global: ai/.tmp/active-project.json (fallback)
    - The PPID is the Claude Code process that spawned both this statusline
      and the StatusMcp server, so they share an identity without needing a
      session_id channel that Claude Code does not expose to MCP servers.
    - Set by: StatusMcp's set_active_project tool
    - Falls back to workspace.project_dir if no active project is set

    Context calculation: "% left" models when Claude Code will begin
    its auto-compact warning. Calibrated for the 1M-context tier
    (the default for the MacCoss / Skyline team on Max 20x) -- the
    usable headroom hits 0% around ~97% consumed, matching Claude's
    warning point. On the smaller 200K tier the threshold is looser
    than Claude's actual warning, so rely on Claude's own warnings
    when running on a 200K plan; the statusline's "% left" remains
    a useful monotone indicator.
#>

$input_json = $input | Out-String | ConvertFrom-Json

# Check for active project state file (set by StatusMcp).
# Derive ai/ root from script location: ai/scripts/statusline.ps1 -> ai/
$aiRoot = Split-Path -Parent $PSScriptRoot
$tmpDir = Join-Path $aiRoot '.tmp'

# The Claude Code process that spawned us is also the parent of any StatusMcp
# server it launched, so the parent PID is a stable session identity shared
# between the two without needing a session_id channel.
$ppid = $null
try {
    $ppid = (Get-CimInstance Win32_Process -Filter "ProcessId = $PID" -ErrorAction Stop).ParentProcessId
} catch { }

$perSessionFile = if ($ppid) { Join-Path $tmpDir "active-project-$ppid.json" } else { $null }
$legacyFile = Join-Path $tmpDir 'active-project.json'

$project_dir = $null
$project_name = $null

foreach ($candidate in @($perSessionFile, $legacyFile)) {
    if ($candidate -and (Test-Path $candidate)) {
        try {
            $active = Get-Content $candidate -Raw | ConvertFrom-Json
            $project_dir = $active.path
            $project_name = $active.name
            break
        } catch { }
    }
}

# Fall back to workspace project directory if no active project set
if (-not $project_dir) {
    $project_dir = $input_json.workspace.project_dir
    $project_name = Split-Path $project_dir -Leaf
}

# Get model display name
$model = $input_json.model.display_name

# Get git branch for the active project
$git_info = ""
try {
    Push-Location $project_dir
    $branch = git branch --show-current 2>$null
    if ($branch) {
        $git_info = " [$branch]"
    }
    Pop-Location
} catch { }

# Calculate context remaining (modelling Claude Code's auto-compact
# warning threshold). Calibrated for the 1M-context tier that the
# MacCoss / Skyline team uses on Max 20x plans — Claude Code rides
# close to the full window before warning, so the statusline's "0%
# left" lines up with actual warning time around ~97% consumed.
#
# On the 200K tier (where the overhead fraction is larger) this
# threshold is looser than the actual warning point; the statusline
# will keep showing a couple of percent left while Claude itself
# starts warning. That's fine — Claude's own warning is authoritative.
$ctx = ""
if ($input_json.context_window.current_usage) {
    $usage = $input_json.context_window.current_usage
    $current = $usage.input_tokens + $usage.cache_creation_input_tokens + $usage.cache_read_input_tokens
    $size = $input_json.context_window.context_window_size
    if ($size -gt 0) {
        $usable_max_pct = 97
        $used_pct = ($current * 100) / $size
        $left = [math]::Max(0, [math]::Floor($usable_max_pct - $used_pct))
        $ctx = " | $left% left"
    }
}

Write-Host "$project_name$git_info | $model$ctx"
