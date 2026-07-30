<#
.SYNOPSIS
    Apply the v9 changes to a Windows AMI-creator instance launched from v8.

.DESCRIPTION
    Idempotent. Run it on an instance launched from
    "Windows Server 2019 VS2026/VS2022/JDK21/msparser/MSFileReader/ramdisk v8"
    (ami-0302a16b404d175d8) to produce the v9 content, then capture the image with
    Ec2Windows.ps1 -Action Capture.

    Run it remotely, not on your workstation:

        pwsh -File ai\scripts\AWS\Ec2Windows.ps1 -Action Run `
             -Instance <name-or-id> -ScriptFile ai\scripts\AWS\Setup-AmiV9.ps1

    What v9 adds over v8, and why:

      PowerShell 7   The Osprey and Skyline TeamCity configs invoke `pwsh` directly
                     (pwiz_tools/Osprey/tctest.bat line 31; the project standard is
                     "no powershell.exe fallback"). v8 has no pwsh, so those configs
                     died instantly with 'pwsh' is not recognized (exit 9009) -- see
                     ProteoWizard_OspreyWindowsNetPerfRegressionTests builds #138/#140.

      .NET 8 SDK     Also a documented prerequisite of tctest.bat. v8 ships the .NET 8
                     *runtime* and targeting pack (via Visual Studio) but only the 9.x
                     and 10.x SDKs, so an 8.0.x SDK had to be added explicitly.

    Deliberately NOT done here:

      * Do not delete C:\ProgramData\Microsoft\VisualStudio\Packages. It looks like a
        download cache but also holds _Instances\<id>\state.json, the VS installer's
        instance registry. Removing it leaves Visual Studio fully installed yet
        invisible to vswhere, which is how build.ps1 locates MSBuild -- and
        `vs_installer repair` cannot fix it (exit 87: no instance to repair).
      * Do not `git gc` the checkouts. Measured on the v8 content it reclaimed 0.29 GB
        across both repos while transiently consuming more than it freed.
      * Do not leave perf-test data on the image. The datasets are re-acquired per run
        and must not persist on agents.

.PARAMETER SkipGitPull
    Leave the C:\pwiz and C:\skyline_release checkouts at their current commits.
#>
[CmdletBinding()]
param(
    [switch]$SkipGitPull
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-Section { param([string]$T) "`n=== $T ===" }

Write-Section 'starting state'
"host      : $env:COMPUTERNAME"
"user      : $([Security.Principal.WindowsIdentity]::GetCurrent().Name)"
$c = Get-PSDrive C
"C:        : $([math]::Round($c.Used/1GB,2)) GB used / $([math]::Round($c.Free/1GB,2)) GB free"

# ---------------------------------------------------------------- PowerShell 7
Write-Section '1. PowerShell 7'
$pwshExe = 'C:\Program Files\PowerShell\7\pwsh.exe'
if (Test-Path $pwshExe) {
    "already installed: $(& $pwshExe -NoProfile -Command '$PSVersionTable.PSVersion.ToString()')"
}
else {
    $bootstrap = Join-Path 'C:\Windows\Temp' 'install-powershell.ps1'
    Invoke-WebRequest -Uri 'https://aka.ms/install-powershell.ps1' -OutFile $bootstrap -UseBasicParsing -TimeoutSec 600
    & $bootstrap -UseMSI -Quiet
    Remove-Item $bootstrap -Force -ErrorAction SilentlyContinue
    if (-not (Test-Path $pwshExe)) { throw "PowerShell 7 install failed: $pwshExe missing" }
    "installed: $(& $pwshExe -NoProfile -Command '$PSVersionTable.PSVersion.ToString()')"
}

# The MSI normally adds this itself; assert it, because the whole point of v9 is that
# `pwsh` resolves by bare name from a TeamCity build step.
$machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
if ($machinePath -notmatch [regex]::Escape('PowerShell\7')) {
    [Environment]::SetEnvironmentVariable('Path', ($machinePath.TrimEnd(';') + ';C:\Program Files\PowerShell\7\'), 'Machine')
    'appended PowerShell 7 to the machine PATH'
}
else { 'machine PATH already contains PowerShell 7' }

# ---------------------------------------------------------------- .NET 8 SDK
Write-Section '2. .NET 8 SDK'
$sdks = & dotnet --list-sdks 2>&1
if ($sdks -match '^8\.') {
    "already installed: $(($sdks | Where-Object { $_ -match '^8\.' }) -join ', ')"
}
else {
    $stage = 'C:\Windows\Temp\dotnet8'
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    $exe = Join-Path $stage 'dotnet-sdk-8.0-win-x64.exe'
    Invoke-WebRequest -Uri 'https://aka.ms/dotnet/8.0/dotnet-sdk-win-x64.exe' -OutFile $exe -UseBasicParsing -TimeoutSec 900
    $proc = Start-Process -FilePath $exe -ArgumentList '/install','/quiet','/norestart' -Wait -PassThru
    if ($proc.ExitCode -notin 0,3010,1638) { throw ".NET 8 SDK installer failed with exit $($proc.ExitCode)" }
    Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
    "installed; SDKs now: $((& dotnet --list-sdks) -join ' | ')"
}

# ---------------------------------------------------------------- checkouts
Write-Section '3. source checkouts'
if ($SkipGitPull) { 'skipped (-SkipGitPull)' }
else {
    foreach ($repo in 'C:\pwiz', 'C:\skyline_release') {
        if (-not (Test-Path (Join-Path $repo '.git'))) { "$repo is not a git repo; skipping"; continue }
        # safe.directory: the checkouts are owned by Administrator while remote execution
        # runs as SYSTEM, which trips git's dubious-ownership guard.
        $branch = & git -c safe.directory=* -C $repo rev-parse --abbrev-ref HEAD
        $before = & git -c safe.directory=* -C $repo rev-parse --short HEAD
        & git -c safe.directory=* -C $repo fetch origin 2>&1 | Out-Null
        & git -c safe.directory=* -C $repo pull --ff-only origin $branch 2>&1 | Select-Object -Last 3
        $after = & git -c safe.directory=* -C $repo rev-parse --short HEAD
        "$repo [$branch]: $before -> $after"
    }
}

# ---------------------------------------------------------------- cleanup
Write-Section '4. safe cleanup'
# Only genuinely disposable things. See the header for what is deliberately excluded.
$freedBefore = (Get-PSDrive C).Free
foreach ($t in @(
    'C:\Users\Administrator\AppData\Local\Temp'
    'C:\Windows\Temp'
    'C:\Windows\SoftwareDistribution\Download'
)) {
    if (Test-Path $t) {
        $gb = [math]::Round(((Get-ChildItem $t -Recurse -Force -File -EA SilentlyContinue)|Measure-Object Length -Sum).Sum/1GB,2)
        Get-ChildItem $t -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch 'dotnet8|install-powershell' } |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        "cleared $t (was $gb GB)"
    }
}

# Perf-test datasets must never ship in the image; they are re-acquired per run.
foreach ($dl in @(
    'C:\Windows\system32\config\systemprofile\Downloads\Perftests'
    'C:\Users\Administrator\Downloads\Perftests'
)) {
    if (Test-Path $dl) {
        $gb = [math]::Round(((Get-ChildItem $dl -Recurse -Force -File -EA SilentlyContinue)|Measure-Object Length -Sum).Sum/1GB,2)
        Remove-Item $dl -Recurse -Force -ErrorAction SilentlyContinue
        "removed perf-test data $dl ($gb GB)"
    }
}
"reclaimed $([math]::Round(((Get-PSDrive C).Free - $freedBefore)/1GB,2)) GB"

# ---------------------------------------------------------------- verify
Write-Section '5. verification'
$fail = @()

$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
$pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue
if ($pwshCmd) { "PASS pwsh on PATH        : $($pwshCmd.Source) ($(& pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'))" }
else { $fail += 'pwsh not resolvable by name'; 'FAIL pwsh on PATH' }

$sdks = & dotnet --list-sdks 2>&1
if ($sdks -match '^8\.') { "PASS .NET 8 SDK          : $(($sdks | Where-Object { $_ -match '^8\.' }) -join ', ')" }
else { $fail += 'no 8.x SDK'; 'FAIL .NET 8 SDK' }

$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vs = & $vswhere -latest -requires Microsoft.Component.MSBuild -property installationPath
if ($vs -and (Test-Path (Join-Path $vs 'MSBuild\Current\Bin\MSBuild.exe'))) { "PASS vswhere finds VS    : $vs" }
else { $fail += 'vswhere cannot find VS with MSBuild'; 'FAIL vswhere finds VS' }

$inst = 'C:\ProgramData\Microsoft\VisualStudio\Packages\_Instances'
if (Test-Path $inst) { "PASS VS _Instances       : $(@(Get-ChildItem $inst).Count) registered" }
else { $fail += 'VS instance registry missing'; 'FAIL VS _Instances' }

foreach ($d in 'C:\Windows\system32\config\systemprofile\Downloads\Perftests','C:\Users\Administrator\Downloads\Perftests') {
    if (Test-Path $d) { $fail += "perf data still present: $d"; "FAIL perf data absent    : $d still exists" }
}
if (-not ($fail | Where-Object { $_ -match 'perf data' })) { 'PASS perf data absent' }

$ram = Get-CimInstance Win32_ComputerSystem
$z = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='Z:'" -ErrorAction SilentlyContinue
"INFO RAM                 : $([math]::Round($ram.TotalPhysicalMemory/1GB,2)) GB"
if ($z) { "INFO RamDisk Z:          : $([math]::Round($z.Size/1GB,2)) GB provisioned, $([math]::Round(($z.Size-$z.FreeSpace)/1GB,2)) GB used" }

$c = Get-PSDrive C
"INFO C:                  : $([math]::Round($c.Used/1GB,2)) GB used / $([math]::Round($c.Free/1GB,2)) GB free"

Write-Section 'result'
if ($fail.Count) {
    "NOT READY TO CAPTURE - $($fail.Count) problem(s):"
    $fail | ForEach-Object { "  - $_" }
    exit 1
}
'READY TO CAPTURE'
exit 0
