# PreToolUse hook: block a commit that would introduce a UTF-8 BOM.
#
# Why this exists. The Skyline CodeInspection test already catches BOMs, but only under
# pwiz_tools/Skyline - it excludes NonSkylineDirectories() - so Osprey and pwiz-sharp work
# was never gated, and BOMs accumulated there undetected. It also only fires at test time,
# long after the commit, and only when someone is doing Skyline development. On 2026-09-10 a
# session working on build scripts wrote four SkylineTester files with utf-8-sig, committed
# them, pushed, and the BOMs reached a reviewer.
#
# Scope: only files STAGED for the commit in question. The whole-tree validator
# (ai/scripts/validate-bom-compliance.ps1) is the audit tool and currently reports
# pre-existing violations, so using it here would block every commit. Checking the staged
# set is also ~30ms rather than ~3s.
#
# Wired up by .claude/settings.json -> hooks -> PreToolUse -> matcher "Bash|PowerShell".
# PowerShell matters: commits issued through the PowerShell tool never reach a Bash-only hook.
#
# Exits 0 on every path except a confirmed BOM, so a broken hook can never block git.

$ErrorActionPreference = 'SilentlyContinue'

try {
    $stdin = [System.IO.StreamReader]::new([System.Console]::OpenStandardInput()).ReadToEnd()
    $payload = $stdin | ConvertFrom-Json
} catch {
    exit 0
}

$cmd = $payload.tool_input.command
if (-not $cmd) { exit 0 }
if ($cmd -notmatch '\bgit\s+commit\b') { exit 0 }

# The repo is wherever the command runs. A commit is usually preceded by a Set-Location or cd
# in the same command; otherwise fall back to the session's cwd.
$repo = $payload.cwd
$m = [regex]::Match($cmd, '(?im)^\s*(?:Set-Location|cd)\s+(?:-Path\s+)?["'']?([A-Za-z]:[\\/][^"''\r\n;|&]+)')
if ($m.Success) { $repo = $m.Groups[1].Value.Trim() }
if (-not $repo -or -not (Test-Path $repo)) { exit 0 }

$staged = & git -C $repo diff --cached --name-only --diff-filter=ACM 2>$null
if ($LASTEXITCODE -ne 0 -or -not $staged) { exit 0 }

# Approved BOMs come from the audit tool, so there is only one list to maintain. If it cannot
# be read, fall back to the extensions the remove tool itself always excludes.
$approved = @()
$validator = Join-Path $repo '..\ai\scripts\validate-bom-compliance.ps1'
if (-not (Test-Path $validator)) { $validator = "$env:CLAUDE_PROJECT_DIR\ai\scripts\validate-bom-compliance.ps1" }
if (Test-Path $validator) {
    $text = Get-Content $validator -Raw
    $block = [regex]::Match($text, '(?s)\$approvedBomFiles\s*=\s*@\{(.*?)\n\}')
    if ($block.Success) {
        $approved = [regex]::Matches($block.Groups[1].Value, '"([^"]+)"\s*=') | ForEach-Object { $_.Groups[1].Value }
    }
}

$offenders = @()
foreach ($rel in $staged) {
    if ($rel -match '\.(tli|tlh)$') { continue }
    if ($approved -contains $rel) { continue }
    $full = Join-Path $repo $rel
    if (-not (Test-Path $full)) { continue }
    try {
        $fs = [IO.File]::OpenRead($full)
        $b = [byte[]]::new(3)
        $n = $fs.Read($b, 0, 3)
        $fs.Close()
    } catch { continue }
    if ($n -eq 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) { $offenders += $rel }
}

if ($offenders.Count -eq 0) { exit 0 }

$list = ($offenders | ForEach-Object { "  - $_" }) -join "`n"
$reason = @"
Refusing to commit: $($offenders.Count) staged file(s) begin with a UTF-8 BOM.

$list

pwiz is UTF-8 WITHOUT BOM. A BOM most often gets in when an editing script writes
'utf-8-sig' instead of 'utf-8' - check any Python/PowerShell helper used on these files.

Strip them, then re-stage and commit:

  pwsh -File ./ai/scripts/remove-bom.ps1 -Execute     # dry-run without -Execute

Audit the whole tree (Skyline, Osprey, pwiz-sharp and ai alike):

  pwsh -File ./ai/scripts/validate-bom-compliance.ps1 -PwizRoot <checkout>

If one of these genuinely must keep its BOM (vendor data, a generated type library),
add it to `$approvedBomFiles in ai/scripts/validate-bom-compliance.ps1 with the reason,
rather than working around this hook.

Blocked by: .claude/hooks/Deny-BomInCommit.ps1
"@

Write-Host $reason
exit 2
