<#
.SYNOPSIS
    Claude Code statusline script - displays project, git branch, model, and context usage.

.DESCRIPTION
    This script provides a dynamic status line for Claude Code showing:
    - Active project name and git branch (supports sibling mode multi-repo setups)
    - Model name (e.g., Opus, Sonnet)
    - Context window usage percentage

    Example outputs:
    - pwiz [Skyline/work/20260113_feature] | Opus | 36% used
    - pwiz-ai [master] | Opus | 12% used

    In sibling mode (multiple repos under C:\proj), Claude can set the active
    project via the StatusMcp's set_active_project tool. The statusline then
    shows that project's branch regardless of which directory Claude Code
    was started from.

.SETUP
    This is a personal preference setting, not a project-wide setting.
    To enable, add the following to your personal Claude Code settings:

    Windows: %USERPROFILE%\.claude\settings.json
    macOS/Linux: ~/.claude/settings.json

    Contents:
    {
      "statusLine": {
        "type": "command",
        "command": "pwsh -NoProfile -File C:\\proj\\ai\\scripts\\statusline.ps1"
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
    - Location: C:\proj\ai\.tmp\active-project.json
    - Set by: StatusMcp's set_active_project tool
    - Falls back to workspace.project_dir if not set

    Context warning: Claude Code warns at ~10% remaining, so watching
    "% used" helps you know when you're approaching that threshold.
#>

$input_json = $input | Out-String | ConvertFrom-Json

# Check for active project state file (set by StatusMcp)
$activeProjectFile = "C:\proj\ai\.tmp\active-project.json"
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

# Calculate context percentage
$ctx = ""
if ($input_json.context_window.current_usage) {
    $usage = $input_json.context_window.current_usage
    $current = $usage.input_tokens + $usage.cache_creation_input_tokens + $usage.cache_read_input_tokens
    $size = $input_json.context_window.context_window_size
    if ($size -gt 0) {
        $pct = [math]::Floor(($current * 100) / $size)
        $ctx = " | $pct% used"
    }
}

Write-Host "$project_name$git_info | $model$ctx"
