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

    Contents (adjust path to match your ai/ checkout location). Use FORWARD
    slashes in the path: on Windows, Claude Code runs this command through Git
    Bash, which silently strips backslashes and leaves the status line blank.
    {
      "statusLine": {
        "type": "command",
        "command": "pwsh -NoProfile -File <your-root>/ai/scripts/statusline.ps1"
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

# Find the Claude Code process by walking up the parent chain. The
# direct parent on Windows is often a bash.exe / pwsh.exe wrapper that
# Claude Code spawns per-tick — its PID is transient and doesn't
# correlate to the StatusMcp server (which has Claude Code as its own
# direct parent). Walking up to the first process named claude.exe
# gives a stable per-session identity both sides can compute. Capped
# at 16 levels to bound runtime if the chain is somehow corrupted.
function Find-ClaudeCodePid {
    $cur = $PID
    $d = 0
    while ($cur -and $cur -ne 0 -and $d -lt 16) {
        $proc = Get-CimInstance Win32_Process -Filter "ProcessId = $cur" -ErrorAction SilentlyContinue
        if (-not $proc) { return $null }
        if ($proc.Name -match '^claude') { return [int]$proc.ProcessId }
        $cur = $proc.ParentProcessId
        $d++
    }
    return $null
}

$ppid = $null
try { $ppid = Find-ClaudeCodePid } catch { }

$perSessionFile = if ($ppid) { Join-Path $tmpDir "active-project-$ppid.json" } else { $null }
$legacyFile = Join-Path $tmpDir 'active-project.json'

$project_dir = $null
$project_name = $null

# 1. Per-session active project: an explicit set_active_project for THIS session
#    (keyed by the Claude Code PID), which deliberately overrides the launch dir.
if ($perSessionFile -and (Test-Path $perSessionFile)) {
    try {
        $active = Get-Content $perSessionFile -Raw | ConvertFrom-Json
        $project_dir = $active.path
        $project_name = $active.name
    } catch { }
}

# 2. The directory Claude Code was actually launched in (this session's real
#    workspace). This must outrank the legacy global below -- otherwise a
#    weeks-old global set_active_project shadows the live session.
if (-not $project_dir -and $input_json.workspace.project_dir) {
    $project_dir = $input_json.workspace.project_dir
    $project_name = Split-Path $project_dir -Leaf
}

# 3. Legacy global active project (cross-session, no PID): final fallback only,
#    used when the payload carried no workspace dir.
if (-not $project_dir -and (Test-Path $legacyFile)) {
    try {
        $active = Get-Content $legacyFile -Raw | ConvertFrom-Json
        $project_dir = $active.path
        $project_name = $active.name
    } catch { }
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

        # Cache the snapshot so the StatusMcp's get_context_usage tool
        # can serve Claude the same number the user sees here. Keyed by
        # the Claude Code PID found above; the StatusMcp does the same
        # walk so both sides land on the same file.
        if ($ppid) {
            try {
                if (-not (Test-Path $tmpDir)) {
                    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
                }
                $snapshot = [ordered]@{
                    model                       = $model
                    context_window_size         = [int]$size
                    input_tokens                = [int]$usage.input_tokens
                    cache_creation_input_tokens = [int]$usage.cache_creation_input_tokens
                    cache_read_input_tokens     = [int]$usage.cache_read_input_tokens
                    used_tokens                 = [int]$current
                    used_pct                    = [math]::Round($used_pct, 2)
                    left_pct                    = [int]$left
                    usable_max_pct              = $usable_max_pct
                    calibrated_at               = (Get-Date).ToUniversalTime().ToString('o')
                }
                $statePath = Join-Path $tmpDir "context-state-$ppid.json"
                $snapshot | ConvertTo-Json | Set-Content -Path $statePath -Encoding UTF8
            } catch {
                # State file is best-effort. Statusline display must not
                # break if the cache write fails (read-only filesystem,
                # etc.); the user-visible % is the primary deliverable.
            }
        }
    }
}

# Sweep orphan context-state files: any whose PID is no longer running
# is from a Claude Code session that has exited. Cheap (a few file stat
# calls per tick); keeps ai/.tmp/ tidy without a separate cron / cleanup
# script. The matching active-project files get the same treatment.
try {
    Get-ChildItem (Join-Path $tmpDir 'context-state-*.json') -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.Name -match 'context-state-(\d+)\.json') {
            $orphanPid = [int]$Matches[1]
            if (-not (Get-Process -Id $orphanPid -ErrorAction SilentlyContinue)) {
                Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
            }
        }
    }
    Get-ChildItem (Join-Path $tmpDir 'active-project-*.json') -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.Name -match 'active-project-(\d+)\.json') {
            $orphanPid = [int]$Matches[1]
            if (-not (Get-Process -Id $orphanPid -ErrorAction SilentlyContinue)) {
                Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
            }
        }
    }
} catch { }

Write-Host "$project_name$git_info | $model$ctx"
