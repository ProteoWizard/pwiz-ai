<#
.SYNOPSIS
    Runs the entrapment-design FDP series: the same 40-file TDP-43 cohort against each
    entrapment-library variant, Stage 1-5 only.

.DESCRIPTION
    Each arm is two invocations of Run-Tdp43.ps1 against ONE library variant:

      -Task PerFileScoring      stages 1-4 (~2.5 h)
      -Task FirstPassFDR -Resume  stage 5, and writes out.model-diagnostics.data.json

    Stopping at FirstPassFDR is what preserves that sidecar: MergeNode consumes and deletes
    it, and it is where every metric in the analysis comes from. Stages 6-7 cost ~8 h and
    answer nothing in this series.

    Arms run STRICTLY SERIALLY and in the order given, baseline first, so a truncated night
    still yields a comparison rather than three half-finished runs.

    Idempotent: an arm whose FirstPassFDR sidecar already exists is skipped, so relaunching
    after an interruption resumes at the first incomplete arm.

.PARAMETER Arms
    Library variant suffixes, in run order. NOTE: pwsh -File passes arguments as literal
    strings - '-Arms a b c' binds only 'a' and sends 'b','c' to the next positional
    parameters. Prefer launching with no arguments and editing the default.
#>
#requires -Version 7
param(
    [string[]]$Arms = @('ungated', 'gated', 'arabidopsis'),
    [string]$Exe = 'D:\test\osprey-runs\_bin\libseries-20260801\Osprey.exe',
    [string]$LibRoot = 'D:\test\osprey-runs\sea-ad\lib',
    [string]$RunRoot = 'D:\test\osprey-runs\tdp43-plasma-ev\runs',
    [int]$NumFiles = 40
)

$ErrorActionPreference = 'Stop'
$runner = Join-Path $PSScriptRoot 'Run-Tdp43.ps1'
$log = Join-Path $PSScriptRoot '..\..\..\.tmp\libseries-driver.log'
$log = [IO.Path]::GetFullPath($log)

function Write-Log([string]$msg) {
    $line = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    Add-Content -Path $log -Value $line
    Write-Host $line
}

Write-Log ('DRIVER START  arms={0}  files={1}  exe={2}' -f ($Arms -join ','), $NumFiles, $Exe)

foreach ($arm in $Arms) {
    $lib = Join-Path $LibRoot "target+decoy+entrapment-$arm"
    # ${NumFiles} braces are required: "$NumFiles`files" makes PowerShell read `f as a
    # FORM FEED escape, silently yielding 'tdp43-40<FF>iles-<arm>' as the directory name.
    $out = Join-Path $RunRoot "tdp43-${NumFiles}files-$arm"
    $sidecar = Join-Path $out 'out.model-diagnostics.data.json'

    if (-not (Test-Path (Join-Path $lib 'carafe_spectral_library.tsv'))) {
        Write-Log ('ARM {0} SKIPPED - no carafe_spectral_library.tsv in {1}' -f $arm, $lib)
        continue
    }
    if (Test-Path $sidecar) {
        Write-Log ('ARM {0} SKIPPED - already complete ({1})' -f $arm, $sidecar)
        continue
    }

    $armStart = Get-Date
    Write-Log ('ARM {0} START  lib={1}  out={2}' -f $arm, $lib, $out)

    & $runner -PickLda -Pass2Mode protein-compact -NumFiles $NumFiles `
        -LibraryDir $lib -Task PerFileScoring -OutDir $out -Exe $Exe
    $rc = $LASTEXITCODE
    Write-Log ('ARM {0} PerFileScoring exit={1} elapsed={2}' -f $arm, $rc, ((Get-Date) - $armStart))
    if ($rc -ne 0) { Write-Log ('ARM {0} ABORTED - scoring failed, moving to next arm' -f $arm); continue }

    & $runner -PickLda -Pass2Mode protein-compact -NumFiles $NumFiles `
        -LibraryDir $lib -Task FirstPassFDR -Resume -OutDir $out -Exe $Exe
    $rc = $LASTEXITCODE
    $elapsed = (Get-Date) - $armStart

    if ((Test-Path $sidecar) -and $rc -eq 0) {
        Write-Log ('ARM {0} DONE  exit=0  elapsed={1}  sidecar OK' -f $arm, $elapsed)
    }
    else {
        Write-Log ('ARM {0} FAILED  exit={1}  elapsed={2}  sidecar present={3}' -f `
            $arm, $rc, $elapsed, (Test-Path $sidecar))
    }
}

Write-Log 'DRIVER DONE'
