#Requires -Version 7.0

# PreToolUse hook: deny /code-review when the working directory is the pwiz-ai
# repo (ai/), because the review silently reviews the WRONG CODE rather than
# failing.
#
# Observed 2026-08-25: `/code-review max` was launched to review pwiz PR #4610,
# whose branch lives in a pwiz checkout. The cwd happened to be C:\proj\ai from
# an earlier TODO commit. The review found no diff in pwiz-ai, fell back to
# whatever was UNTRACKED there, and spent 27 minutes and 157k tokens producing
# 15 detailed findings about another session's work-in-progress script - none of
# them about the PR. Nothing in the output announced the mismatch except one
# line at the very end.
#
# That failure is expensive and quiet, which is what earns a hook: the cost is
# paid in full before the mistake is visible.
#
# Escape hatch: pass "pwiz-ai" in the skill arguments to review ai/ changes on
# purpose (e.g. `/code-review max pwiz-ai`). Reviewing real committed changes in
# this repo is legitimate - doing it BY ACCIDENT while aiming at a pwiz PR is
# what this blocks.
#
# Exit 2 with a stderr message blocks the tool call and surfaces the reason to
# Claude. Exit 0 on any non-match or error so this hook cannot break the Skill
# tool itself.

$ErrorActionPreference = 'SilentlyContinue'

try {
    $stdin = [System.IO.StreamReader]::new([System.Console]::OpenStandardInput()).ReadToEnd()
    $payload = $stdin | ConvertFrom-Json
} catch {
    exit 0
}

# The Skill tool names the skill in tool_input.skill; tolerate .name as well.
$skill = $payload.tool_input.skill
if (-not $skill) { $skill = $payload.tool_input.name }
if (-not $skill) { exit 0 }

if ($skill -notmatch '^\s*/?code-review\s*$') { exit 0 }

# Deliberate ai/ review - let it through.
$skillArgs = [string]$payload.tool_input.args
if ($skillArgs -match 'pwiz-ai') { exit 0 }

$cwd = $payload.cwd
if (-not $cwd) { $cwd = (Get-Location).Path }
if (-not $cwd) { exit 0 }

# The ai repo sits at <project root>/ai. Fall back to asking git which remote
# this directory belongs to when the layout is not the standard one.
$inAiRepo = $false
if ($env:CLAUDE_PROJECT_DIR) {
    $aiRoot = Join-Path $env:CLAUDE_PROJECT_DIR 'ai'
    try {
        $cwdFull = [System.IO.Path]::GetFullPath($cwd)
        $aiFull = [System.IO.Path]::GetFullPath($aiRoot)
        if ($cwdFull -eq $aiFull -or $cwdFull.StartsWith($aiFull + [System.IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            $inAiRepo = $true
        }
    } catch { }
}
if (-not $inAiRepo) {
    $remote = & git -C $cwd remote get-url origin 2>$null
    if ($LASTEXITCODE -eq 0 -and $remote -match 'pwiz-ai') { $inAiRepo = $true }
}

if (-not $inAiRepo) { exit 0 }

$message = @"
BLOCKED: /code-review from inside the pwiz-ai (ai/) repo.

Current directory: $cwd

A code review started here does NOT fail when it cannot find the code you meant.
It finds no diff in pwiz-ai, falls back to reviewing whatever is UNTRACKED in
this repo, and reports confident findings about the wrong files. Measured once:
27 minutes and 157k tokens spent reviewing an unrelated work-in-progress script
while a pwiz PR went unreviewed.

CRITICAL: cd to the checkout that holds the PR branch FIRST, then review.

    cd <the pwiz checkout for this PR>     # e.g. C:/proj/daily, C:/proj/pwiz
    /code-review max

Use mcp__status__get_project_status() to see which checkout holds which branch -
sibling checkouts differ, and the branch under review is often NOT in C:/proj/pwiz.

To review changes in THIS repo on purpose, say so in the arguments:

    /code-review max pwiz-ai
"@

[Console]::Error.WriteLine($message)
exit 2
