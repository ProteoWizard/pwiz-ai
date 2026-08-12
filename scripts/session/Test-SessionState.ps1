#Requires -Version 7.0

<#
.SYNOPSIS
    Regression tests for restart recovery (SessionState.ps1, the skyclaude
    launcher's -Resume, and the SessionStart hook's recovery brief).

.DESCRIPTION
    Simulates a Windows Update reboot without needing one: records are written
    with a back-dated boot ID, which is exactly what a genuine restart leaves
    behind.

    Run it as a script, not dot-sourced -- it stubs 'claude' and dot-sources the
    launcher, which would otherwise leak into an interactive session:

        pwsh -File ai/scripts/session/Test-SessionState.ps1

.NOTES
    Paths are derived from this script's location, so no per-machine edits.
#>

$aiRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$projectRoot = Split-Path -Parent $aiRoot

. (Join-Path $PSScriptRoot 'SessionState.ps1')

$PriorBoot = 'boot-2000-01-01T00:00:00.0000000Z'   # any boot before this one
$fail = 0

function Check($label, $cond) {
    if ($cond) { Write-Host "  PASS  $label" -ForegroundColor Green }
    else { Write-Host "  FAIL  $label" -ForegroundColor Red; $script:fail++ }
}

function Set-SimulatedPriorBoot { $Global:PwizSessionBootId = $PriorBoot }
function Reset-Boot { Remove-Variable -Name PwizSessionBootId -Scope Global -ErrorAction SilentlyContinue }

Reset-Boot
$realBoot = Get-PwizBootId
Write-Host "Current boot id: $realBoot`n"

# --------------------------------------------------------------------------
Write-Host '=== Records: restart vs. unclean exit ===' -ForegroundColor Cyan

Set-SimulatedPriorBoot
Write-PwizSessionRecord -SessionId 'test-restart-victim' -Checkout 'TestCheckout' `
    -LspDir 'X:\TestCheckout\pwiz_tools' -Branch 'test-branch' -LaunchId 'launch-A'
Reset-Boot

$state = Get-PwizInterruptedState -Checkout 'TestCheckout'
Check 'interrupted session found'       ($state -and $state.Sessions.Count -eq 1)
Check 'restart detected'                ($state.RebootDetected -eq $true)
Check 'resume id is the killed session' ($state.Sessions[0].sessionId -eq 'test-restart-victim')
Check 'other checkouts unaffected'      ($null -eq (Get-PwizInterruptedState -Checkout 'NoSuchCheckout'))

# Same boot = crash or closed terminal. Reporting this as a restart would make
# the message untrustworthy, so it must not.
Write-PwizSessionRecord -SessionId 'test-crash-victim' -Checkout 'CrashCheckout' -LaunchId 'launch-B'
$crash = Get-PwizInterruptedState -Checkout 'CrashCheckout'
Check 'crash reported as interrupted'   ($crash -and $crash.Sessions.Count -eq 1)
Check 'crash NOT blamed on a restart'   ($crash.RebootDetected -eq $false)

Remove-PwizSessionRecord -LaunchId 'launch-A'
Remove-PwizSessionRecord -LaunchId 'launch-B'
Check 'clean exit leaves no survivor'   ($null -eq (Get-PwizInterruptedState -Checkout 'TestCheckout') -and
                                         $null -eq (Get-PwizInterruptedState -Checkout 'CrashCheckout'))

# --------------------------------------------------------------------------
Write-Host "`n=== Run markers ===" -ForegroundColor Cyan

$live = Write-PwizRunMarker -Kind 'test' -Name 'TestLiveRun' -Checkout 'TestCheckout' `
    -CommandLine 'Run-Tests.ps1 -TestName TestLiveRun'
Check 'live run marker written'         ($live -and (Test-Path $live))
Check 'live run NOT an interruption'    ($null -eq (Get-PwizInterruptedState -Checkout 'TestCheckout'))

Set-SimulatedPriorBoot
$dead = Write-PwizRunMarker -Kind 'test' -Name 'TestPerfKilled' -Checkout 'TestCheckout' `
    -CommandLine 'Run-Tests.ps1 -TestName TestPerfKilled' -LogPath 'X:\logs\TestPerfKilled.log'
Reset-Boot

$runState = Get-PwizInterruptedState -Checkout 'TestCheckout'
Check 'killed run reported (only it)'   ($runState -and $runState.Runs.Count -eq 1)
Check 'killed run named correctly'      ($runState.Runs[0].name -eq 'TestPerfKilled')
Check 'killed run keeps command line'   ($runState.Runs[0].commandLine -match 'TestPerfKilled')
Check 'killed run keeps log path'       ($runState.Runs[0].logPath -eq 'X:\logs\TestPerfKilled.log')

Remove-PwizRunMarker -Path $live
Remove-PwizRunMarker -Path $dead
Check 'markers cleaned up'              ($null -eq (Get-PwizInterruptedState -Checkout 'TestCheckout'))

# --------------------------------------------------------------------------
Write-Host "`n=== Launcher: -Resume picks the right CHECKOUT's session ===" -ForegroundColor Cyan
# The regression that motivates all of this: several skyclaude windows die
# together, and 'claude --continue' would reopen whichever died LAST.

. (Join-Path $aiRoot 'scripts\lsp\Enable-PwizLsp.ps1')
$Global:CapturedArgs = $null
function claude { $Global:CapturedArgs = $args }

Set-SimulatedPriorBoot
Write-PwizSessionRecord -SessionId 'alpha-session-aaa' -Checkout 'AlphaCheckout' -Branch 'alpha' -LaunchId 'old-1'
Start-Sleep -Milliseconds 1100     # ensure a distinct, later mtime
Write-PwizSessionRecord -SessionId 'beta-session-bbb' -Checkout 'BetaCheckout' -Branch 'beta' -LaunchId 'old-2'
Reset-Boot

Start-PwizClaude -Checkout 'AlphaCheckout' -Resume | Out-Null
$argv = @($Global:CapturedArgs)
Check 'resumes by explicit session id'  ($argv -contains '--resume')
Check 'picks Alpha, not the newer Beta' ($argv -contains 'alpha-session-aaa')
Check 'does not cross checkouts'        ($argv -notcontains 'beta-session-bbb')

Start-PwizClaude -Checkout 'BetaCheckout' --continue | Out-Null
$argv = @($Global:CapturedArgs)
Check '--continue retargeted'           (($argv -notcontains '--continue') -and ($argv -contains 'beta-session-bbb'))

Start-PwizClaude -Checkout 'AlphaCheckout' | Out-Null
$argv = @($Global:CapturedArgs)
Check 'plain launch stays fresh'        ($argv -notcontains '--resume')

Start-PwizClaude -Checkout 'AlphaCheckout' -Resume --dangerously-skip-permissions | Out-Null
$argv = @($Global:CapturedArgs)
Check 'pass-through args preserved'     ($argv -contains '--dangerously-skip-permissions')

Start-PwizClaude -Checkout 'NoSuchCheckout' -Resume | Out-Null
$argv = @($Global:CapturedArgs)
Check 'no phantom resume'               ($argv -notcontains '--resume')

Remove-PwizSessionRecord -SessionId 'alpha-session-aaa'
Remove-PwizSessionRecord -SessionId 'beta-session-bbb'

# --------------------------------------------------------------------------
Write-Host "`n=== SessionStart hook: recovery brief ===" -ForegroundColor Cyan

$checkoutDir = Get-ChildItem $projectRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object { Test-Path (Join-Path $_.FullName 'pwiz_tools') } |
    Select-Object -First 1

if (-not $checkoutDir) {
    Write-Host '  SKIP  no checkout with pwiz_tools found under the project root' -ForegroundColor Yellow
}
else {
    $hook = Join-Path $aiRoot 'claude\hooks\Set-ActiveCheckout.ps1'
    $env:CLAUDE_PROJECT_DIR = $projectRoot
    $env:PWIZ_LSP_DIR = Join-Path $checkoutDir.FullName 'pwiz_tools'
    $ckName = $checkoutDir.Name

    function Invoke-Hook($sessionId) {
        $payload = @{ session_id = $sessionId; transcript_path = "X:\fake\$sessionId.jsonl"; source = 'startup' } |
            ConvertTo-Json -Compress
        $out = $payload | pwsh -NoProfile -File $hook
        ($out | ConvertFrom-Json).hookSpecificOutput.additionalContext
    }

    # A clean first start must be byte-for-byte the old behavior.
    $ctx1 = Invoke-Hook 'hooktest-victim-001'
    Check 'cd instruction still emitted'  ($ctx1 -match [regex]::Escape("cd $($checkoutDir.FullName)"))
    Check 'clean start reports nothing'   ($ctx1 -notmatch 'Interrupted work')

    # Simulate the reboot: back-date the record and add a killed run.
    $sessDir = Get-PwizStateDir -Kind sessions
    $rec = Get-Content (Join-Path $sessDir 'hooktest-victim-001.json') -Raw | ConvertFrom-Json
    $rec.bootId = $PriorBoot
    $rec | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $sessDir 'hooktest-victim-001.json') -Encoding utf8

    Set-SimulatedPriorBoot
    $marker = Write-PwizRunMarker -Kind 'test' -Name 'TestPerfHookCheck' -Checkout $ckName `
        -CommandLine 'Run-Tests.ps1 -TestName TestPerfHookCheck' -LogPath 'X:\logs\TestPerfHookCheck.log'
    Reset-Boot

    $ctx2 = Invoke-Hook 'hooktest-recovered-002'
    Check 'cd instruction survives'       ($ctx2 -match [regex]::Escape("cd $($checkoutDir.FullName)"))
    Check 'restart named as the cause'    ($ctx2 -match 'machine restart')
    Check 'killed session identified'     ($ctx2 -match 'hooktest-victim-001')
    Check 'resume command offered'        ($ctx2 -match "skyclaude $ckName -Resume")
    Check 'killed run reported'           ($ctx2 -match 'TestPerfHookCheck')
    Check 'partial log offered'           ($ctx2 -match 'partial log')
    Check 'does not report itself'        ($ctx2 -notmatch 'hooktest-recovered-002')

    Remove-PwizSessionRecord -SessionId 'hooktest-victim-001'
    Remove-PwizSessionRecord -SessionId 'hooktest-recovered-002'
    Remove-PwizRunMarker -Path $marker
}

# --------------------------------------------------------------------------
Write-Host "`n=== Pending reboot ===" -ForegroundColor Cyan
$pending = Get-PwizPendingReboot
Check 'pending-reboot check returns'    ($null -ne $pending -and $pending.Confirmed -is [bool])
Write-Host "  Confirmed=$($pending.Confirmed) Advisory=$($pending.Advisory) Reasons=$($pending.Reasons -join ', ')"

Write-Host ''
if ($fail) { Write-Host "$fail CHECK(S) FAILED" -ForegroundColor Red; exit 1 }
Write-Host 'ALL CHECKS PASSED' -ForegroundColor Green
