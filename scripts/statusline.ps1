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
    - Location: ai/.tmp/active-project.json (relative to project root)
    - Set by: StatusMcp's set_active_project tool
    - Falls back to workspace.project_dir if not set

    Context calculation: Claude Code reserves ~15% for system overhead,
    so "% left" shows remaining usable context (matches Claude's warnings).
#>

$input_json = $input | Out-String | ConvertFrom-Json

# Check for active project state file (set by StatusMcp)
# Derive ai/ root from script location: ai/scripts/statusline.ps1 -> ai/
$aiRoot = Split-Path -Parent $PSScriptRoot
$activeProjectFile = Join-Path $aiRoot '.tmp\active-project.json'
$project_dir = $null
$project_name = $null

if (Test-Path $activeProjectFile) {
    try {
        $active = Get-Content $activeProjectFile -Raw | ConvertFrom-Json
        $project_dir = $active.path
        $project_name = $active.name
    } catch { }
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

# Calculate context remaining (matching Claude Code's warnings)
# Claude Code reserves ~15% for system overhead, so usable max is ~85%
$ctx = ""
if ($input_json.context_window.current_usage) {
    $usage = $input_json.context_window.current_usage
    $current = $usage.input_tokens + $usage.cache_creation_input_tokens + $usage.cache_read_input_tokens
    $size = $input_json.context_window.context_window_size
    if ($size -gt 0) {
        $usable_max_pct = 85
        $used_pct = ($current * 100) / $size
        $left = [math]::Max(0, [math]::Floor($usable_max_pct - $used_pct))
        $ctx = " | $left% left"
    }
}

Write-Host "$project_name$git_info | $model$ctx"
