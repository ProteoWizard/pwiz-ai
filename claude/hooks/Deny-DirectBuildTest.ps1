#Requires -Version 7.0

# PreToolUse hook: deny direct invocations of native build/test executables
# (dotnet build/test/run/publish/pack/msbuild, MSBuild.exe, mstest, vstest,
# TestRunner.exe) in the Bash tool. The pwiz team's wrapper scripts under
# ai/scripts/ are the canonical entry point:
#
#   Skyline:     ai/scripts/Skyline/Build-Skyline.ps1
#                ai/scripts/Skyline/Run-Tests.ps1
#   OspreySharp: ai/scripts/OspreySharp/Build-OspreySharp.ps1
#
# The wrappers handle MSBuild toolset selection, -Summary mode (which avoids
# the compound-command permission trap from CRITICAL-RULES.md), test
# filtering, and the standard CI gates. Going direct rarely proves beneficial
# even when it works once.
#
# Exit 2 with a stderr message blocks the tool call and surfaces the reason
# to Claude. Exit 0 on any non-match or error so this hook cannot break the
# Bash tool itself.
#
# IMPORTANT: the regex anchors the tool name to a real command position
# (start-of-string or shell separator), so paths/strings containing these
# words as substrings (e.g. build-output/, msbuild-logs/, TestRunner.cs) do
# not falsely trigger.

$ErrorActionPreference = 'SilentlyContinue'

try {
    $stdin = [System.IO.StreamReader]::new([System.Console]::OpenStandardInput()).ReadToEnd()
    $payload = $stdin | ConvertFrom-Json
} catch {
    exit 0
}

$cmd = $payload.tool_input.command
if (-not $cmd) { exit 0 }

# Each alternative requires the tool name to be preceded by start-of-string
# or a shell separator (whitespace, ;, |, &) and (for the non-dotnet tools)
# followed by whitespace or end-of-string. This avoids matching substrings
# inside paths or filenames.
$pattern = '(?i)(?:^|[\s;|&])(?:' +
    'dotnet(?:\.exe)?\s+(?:build|test|run|publish|pack|msbuild)\b' + '|' +
    'msbuild(?:\.exe)?(?:\s|$)' + '|' +
    'mstest(?:\.exe)?(?:\s|$)' + '|' +
    'vstest\.console(?:\.exe)?(?:\s|$)' + '|' +
    'TestRunner(?:\.exe)?(?:\s|$)' +
    ')'

if ($cmd -notmatch $pattern) { exit 0 }

$reason = @'
Direct invocation of native build/test executables is blocked in pwiz.

Use the team's wrapper scripts under ai/scripts/ instead:

  Skyline:
    pwsh -File ./ai/scripts/Skyline/Build-Skyline.ps1
    pwsh -File ./ai/scripts/Skyline/Build-Skyline.ps1 -RunTests -TestName <Name> -Summary
    pwsh -File ./ai/scripts/Skyline/Run-Tests.ps1 -TestName <Name>

  OspreySharp:
    pwsh -File ./ai/scripts/OspreySharp/Build-OspreySharp.ps1
    pwsh -File ./ai/scripts/OspreySharp/Build-OspreySharp.ps1 -RunTests -Summary

The wrappers handle MSBuild toolset selection, -Summary output (which avoids
the compound-command permission trap documented in ai/CRITICAL-RULES.md),
test filtering, and the standard CI gates. Going direct rarely proves
beneficial even when it works once.

Blocked by: .claude/hooks/Deny-DirectBuildTest.ps1
'@

[Console]::Error.WriteLine($reason)
exit 2
