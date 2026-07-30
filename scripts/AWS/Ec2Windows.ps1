<#
.SYNOPSIS
    Manage the TeamCity Windows AMI-creator EC2 instances and run remote commands on them.

.DESCRIPTION
    Single entry point for the Windows AMI update workflow:
      - resolve an instance by friendly Name tag or instance id
      - start / stop / status
      - run remote PowerShell, over SSM if available, else WinRM

    Transports, in order of preference:

      SSM   - ssm:SendCommand. No inbound ports, no password, fully audited. This is
              the working path: the AMI creators already run the SSM agent and register
              without an instance profile, and the personal IAM account has SSM access.
              It does require -AwsProfile to name that account, not the default
              svc-teamcity-server credentials, which have no SSM permissions at all.

      WinRM - PowerShell remoting to the public IP over HTTPS (5986). Fallback only.
              Needs EnableWinRM to have been run once and the Administrator password;
              as of 2026-07-29 the user-data bootstrap does not take on this AMI.
              See ai/docs/aws-ami-updates.md.

    The security group (sg-0175b412cb58a33d6, "TeamCity Agents Peered") allows all
    traffic from a short allowlist of developer IPs, so the WinRM path only works
    from one of those addresses.

.PARAMETER Action
    Status      Show state, IPs and which remote-access ports are reachable.
    Start       Start the instance and wait until it accepts connections.
    Stop        Stop the instance and wait until fully stopped.
    Run         Run a PowerShell command remotely (-Command or -ScriptFile).
    Capture     Create an AMI from the stopped instance (-ImageName).
    EnableWinRM Stage a boot script that turns on WinRM over HTTPS, then reboot.
    Rdp         Open an RDP session (for the interactive parts of an AMI build).
    ClearBoot   Remove the staged boot script so it is not baked into a new AMI.

.PARAMETER Instance
    Friendly Name tag or instance id. Default: TeamCityAMICreator.

.PARAMETER Command
    PowerShell to execute remotely, for -Action Run.

.PARAMETER ScriptFile
    Local .ps1 whose contents are executed remotely, for -Action Run.

.PARAMETER Transport
    Auto (default), Ssm or WinRM.

.PARAMETER ImageName
    Name for the new AMI, for -Action Capture. Follow the existing convention, e.g.
    "Windows Server 2019 VS2026/VS2022/JDK21/msparser/MSFileReader/ramdisk v9".

.PARAMETER AwsProfile
    AWS CLI profile. Defaults to $env:AWS_PROFILE, else 'maccoss-chambm'. Must name a
    personal IAM account: the default svc-teamcity-server credentials cannot use SSM
    and cannot create images.

.PARAMETER Region
    AWS region. Default: us-west-2.

.EXAMPLE
    .\Ec2Windows.ps1 -Action Status

.EXAMPLE
    .\Ec2Windows.ps1 -Action Start
    .\Ec2Windows.ps1 -Action Run -Command 'choco upgrade all -y'
    .\Ec2Windows.ps1 -Action Stop

.EXAMPLE
    .\Ec2Windows.ps1 -Action Run -ScriptFile .\update-build-tools.ps1
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('Status','Start','Stop','Run','Capture','EnableWinRM','Rdp','ClearBoot')]
    [string]$Action,

    [string]$Instance = 'TeamCityAMICreator',
    [string]$Command,
    [string]$ScriptFile,

    [ValidateSet('Auto','Ssm','WinRM')]
    [string]$Transport = 'Auto',

    [string]$ImageName,

    # The default 'svc-teamcity-server' credentials have no SSM access and cannot create
    # images; the personal IAM account does. Override with -AwsProfile or $env:AWS_PROFILE.
    # Named AwsProfile rather than Profile so it does not shadow PowerShell's $PROFILE.
    [string]$AwsProfile = $(if ($env:AWS_PROFILE) { $env:AWS_PROFILE } else { 'maccoss-chambm' }),

    [string]$Region = 'us-west-2'
)

$ErrorActionPreference = 'Stop'

# The AWS CLI v2 is a Python program that encodes its output using the console codepage.
# Remote Windows output routinely carries characters that cp1252 cannot represent, and the
# CLI then dies with "'charmap' codec can't encode character" while fetching command
# output. Force UTF-8 on both ends so retrieving results never fails on the content.
$env:PYTHONIOENCODING = 'utf-8'
$env:PYTHONUTF8 = '1'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

# Private half of the EC2 key pair the AMI creators were launched with. Used only to
# decrypt the Administrator password blob that EC2 stores for the instance.
$script:LaunchKey = 'D:\Downloads\teamcity-chambm-maccoss.pem'

# Administrator password cache, encrypted at rest with DPAPI under the current user.
$script:CredCache = Join-Path $env:USERPROFILE '.claude-tools\ec2-windows'

function Write-Step { param([string]$Message) Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Message) Write-Host "    $Message" -ForegroundColor Green }
function Write-Warn { param([string]$Message) Write-Host "    $Message" -ForegroundColor Yellow }

function Invoke-Aws {
    # Wraps the AWS CLI so a non-zero exit becomes a terminating error carrying the real message.
    param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments)
    $output = & aws --region $Region --profile $AwsProfile @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "aws $($Arguments -join ' ') failed:`n$output" }
    return $output
}

function Resolve-Instance {
    param([string]$NameOrId)

    if ($NameOrId -match '^i-[0-9a-f]+$') {
        $filter = @('--instance-ids', $NameOrId)
    }
    else {
        $filter = @('--filters', "Name=tag:Name,Values=$NameOrId")
    }

    $json = Invoke-Aws ec2 describe-instances @filter `
        --query 'Reservations[].Instances[].{Id:InstanceId,Name:Tags[?Key==`Name`]|[0].Value,State:State.Name,PublicIp:PublicIpAddress,PrivateIp:PrivateIpAddress,Type:InstanceType,Image:ImageId,Profile:IamInstanceProfile.Arn}' `
        --output json

    $found = @($json | ConvertFrom-Json) | Where-Object { $_.State -ne 'terminated' }
    if ($found.Count -eq 0) { throw "No non-terminated instance matched '$NameOrId' in $Region." }
    if ($found.Count -gt 1) {
        throw "'$NameOrId' matched $($found.Count) instances: $(($found | ForEach-Object { "$($_.Name) ($($_.Id))" }) -join ', '). Pass an instance id."
    }
    return $found[0]
}

function Test-Port {
    param([string]$ComputerName, [int]$Port, [int]$TimeoutMs = 3000)

    # Test-NetConnection is slow and chatty; a raw async TCP connect keeps polling loops tight.
    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        $connect = $client.BeginConnect($ComputerName, $Port, $null, $null)
        if (-not $connect.AsyncWaitHandle.WaitOne($TimeoutMs)) { return $false }
        $client.EndConnect($connect)
        return $true
    }
    catch { return $false }
    finally { $client.Dispose() }
}

function Wait-Port {
    param([string]$ComputerName, [int]$Port, [int]$TimeoutSeconds = 600, [string]$Label)

    Write-Step "Waiting for $Label ($ComputerName`:$Port), up to $TimeoutSeconds s"
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-Port -ComputerName $ComputerName -Port $Port) {
            Write-Ok "$Label is reachable"
            return $true
        }
        Start-Sleep -Seconds 5
    }
    Write-Warn "$Label did not become reachable within $TimeoutSeconds s"
    return $false
}

function Get-AdminCredential {
    param([object]$Inst)

    $cacheFile = Join-Path $script:CredCache "$($Inst.Id).xml"

    # Import-Clixml transparently reverses the DPAPI protection applied on export.
    if (Test-Path $cacheFile) { return Import-Clixml $cacheFile }

    # svc-teamcity-server is denied ec2:GetPasswordData, and these hand-built AMIs were
    # never sysprepped with password randomization anyway, so this attempt is expected to
    # fail. It is still worth trying: it costs one call and succeeds immediately if either
    # the IAM policy or the AMI ever changes.
    $plain = $null
    if (Test-Path $script:LaunchKey) {
        Write-Step "Retrieving Administrator password for $($Inst.Id)"
        try {
            $plain = (Invoke-Aws ec2 get-password-data --instance-id $Inst.Id `
                --priv-launch-key $script:LaunchKey --query PasswordData --output text | Out-String).Trim()
        }
        catch { Write-Warn 'EC2 would not return password data (expected: ec2:GetPasswordData is denied)' }
    }

    if ([string]::IsNullOrWhiteSpace($plain) -or $plain -eq 'None') {
        throw @"
No Administrator password available for $($Inst.Id) from AWS.

ec2:GetPasswordData is denied to this IAM user, and the AMI was hand-built rather than
sysprepped, so EC2 holds no password blob for it. Supply the password the image was
built with once; it is then cached with DPAPI for the current user only:

    `$c = Get-Credential Administrator
    New-Item -ItemType Directory -Force -Path '$($script:CredCache)' | Out-Null
    `$c | Export-Clixml '$cacheFile'
"@
    }

    $cred = [pscredential]::new('Administrator', (ConvertTo-SecureString $plain -AsPlainText -Force))
    New-Item -ItemType Directory -Force -Path $script:CredCache | Out-Null
    $cred | Export-Clixml $cacheFile
    Write-Ok "Password cached (DPAPI, current user only) at $cacheFile"
    return $cred
}

function Test-SsmAvailable {
    param([object]$Inst)
    # Returns false rather than throwing when the profile in use lacks SSM access, so the
    # WinRM fallback still gets a chance.
    try {
        $ping = & aws --region $Region --profile $AwsProfile ssm describe-instance-information `
            --filters "Key=InstanceIds,Values=$($Inst.Id)" `
            --query 'InstanceInformationList[0].PingStatus' --output text 2>&1
        return ($LASTEXITCODE -eq 0 -and $ping -match 'Online')
    }
    catch { return $false }
}

function Invoke-RemoteSsm {
    param([object]$Inst, [string]$Script)

    Write-Step "Running via SSM on $($Inst.Id)"

    # Hand --parameters a file rather than inline JSON: the payload is arbitrary PowerShell
    # and would otherwise have to survive both PowerShell and the CLI's shorthand parser.
    $paramFile = Join-Path ([System.IO.Path]::GetTempPath()) "ssm-params-$($Inst.Id).json"
    @{ commands = @($Script) } | ConvertTo-Json -Compress | Set-Content -Path $paramFile -Encoding UTF8

    try {
        $commandId = (Invoke-Aws ssm send-command --instance-ids $Inst.Id `
            --document-name 'AWS-RunPowerShellScript' `
            --parameters "file://$paramFile" `
            --query 'Command.CommandId' --output text | Out-String).Trim()
    }
    finally { Remove-Item $paramFile -ErrorAction SilentlyContinue }

    Write-Ok "Command $commandId dispatched; waiting for completion"
    while ($true) {
        Start-Sleep -Seconds 3
        $status = (& aws --region $Region --profile $AwsProfile ssm get-command-invocation `
            --command-id $commandId --instance-id $Inst.Id `
            --query 'Status' --output text 2>&1 | Out-String).Trim()
        if ($status -notin 'Pending','InProgress','Delayed') { break }
    }

    $stdout = (Invoke-Aws ssm get-command-invocation --command-id $commandId --instance-id $Inst.Id `
        --query 'StandardOutputContent' --output text | Out-String)
    $stderr = (Invoke-Aws ssm get-command-invocation --command-id $commandId --instance-id $Inst.Id `
        --query 'StandardErrorContent' --output text | Out-String)

    if ($stdout.Trim()) { Write-Host $stdout.TrimEnd() }
    if ($stderr.Trim()) { Write-Warn $stderr.TrimEnd() }
    if ($status -ne 'Success') { throw "SSM command finished with status '$status'." }
}

function Invoke-RemoteWinRm {
    param([object]$Inst, [string]$Script)

    if (-not $Inst.PublicIp) { throw "$($Inst.Id) has no public IP; start it first." }

    $cred = Get-AdminCredential -Inst $Inst
    Write-Step "Running via WinRM on $($Inst.PublicIp)"

    # The instance presents a self-signed certificate and is not domain-joined, so
    # certificate identity checks cannot succeed; the security group allowlist is what
    # actually bounds who can reach port 5986.
    $so = New-PSSessionOption -SkipCACheck -SkipCNCheck
    $session = New-PSSession -ComputerName $Inst.PublicIp -Port 5986 -UseSSL `
        -Credential $cred -SessionOption $so -Authentication Negotiate

    try { Invoke-Command -Session $session -ScriptBlock ([scriptblock]::Create($Script)) }
    finally { Remove-PSSession $session }
}

function Invoke-Remote {
    param([object]$Inst, [string]$Script)

    $useSsm = switch ($Transport) {
        'Ssm'   { $true }
        'WinRM' { $false }
        default { Test-SsmAvailable -Inst $Inst }
    }

    if ($useSsm) { Invoke-RemoteSsm -Inst $Inst -Script $Script }
    else {
        if ($Transport -eq 'Auto') { Write-Warn 'SSM unavailable; falling back to WinRM' }
        Invoke-RemoteWinRm -Inst $Inst -Script $Script
    }
}

function Set-BootScript {
    param([object]$Inst, [string]$UserData)

    if ($Inst.State -ne 'stopped') {
        throw "User data can only be changed while the instance is stopped (current state: $($Inst.State))."
    }

    # modify-instance-attribute takes --user-data as a structure whose Value must already
    # be base64. Unlike run-instances, it will not encode a file:// payload for us, and a
    # raw <powershell> block trips the shorthand parser on the first '<'.
    # Clearing needs an explicit empty Value; '--attribute userData' on its own is rejected
    # with MissingParameter.
    $b64 = if ([string]::IsNullOrEmpty($UserData)) { '' }
           else { [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($UserData)) }
    Invoke-Aws ec2 modify-instance-attribute --instance-id $Inst.Id --user-data "Value=$b64" | Out-Null
}

# WinRM over HTTPS with a self-signed cert. Marked <persist>true</persist> because
# Windows will not re-run one-shot user data on an instance that has already booted
# once, and these instances are years old. Run -Action ClearBoot before capturing an
# AMI so the boot script does not ship inside the image.
$script:EnableWinRmUserData = @'
<powershell>
Enable-PSRemoting -Force -SkipNetworkProfileCheck

$cert = Get-ChildItem Cert:\LocalMachine\My |
    Where-Object { $_.Subject -eq "CN=$env:COMPUTERNAME" -and $_.NotAfter -gt (Get-Date) } |
    Select-Object -First 1
if (-not $cert) {
    $cert = New-SelfSignedCertificate -DnsName $env:COMPUTERNAME -CertStoreLocation Cert:\LocalMachine\My
}

$httpsListener = Get-ChildItem WSMan:\localhost\Listener |
    Where-Object { $_.Keys -contains 'Transport=HTTPS' }
if (-not $httpsListener) {
    New-Item -Path WSMan:\localhost\Listener -Transport HTTPS -Address * `
        -CertificateThumbPrint $cert.Thumbprint -Force
}

Set-Item WSMan:\localhost\Service\Auth\Negotiate -Value $true

if (-not (Get-NetFirewallRule -Name 'WinRM-HTTPS-In' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name 'WinRM-HTTPS-In' -DisplayName 'WinRM over HTTPS (5986)' `
        -Enabled True -Direction Inbound -Protocol TCP -LocalPort 5986 -Action Allow
}

Set-Service -Name WinRM -StartupType Automatic
Restart-Service WinRM
</powershell>
<persist>true</persist>
'@

# ---------------------------------------------------------------------------

$inst = Resolve-Instance -NameOrId $Instance
Write-Step "$($inst.Name) ($($inst.Id)), $($inst.Type), state=$($inst.State)"

switch ($Action) {

    'Status' {
        Write-Host ""
        Write-Host "  Instance   : $($inst.Id)  [$($inst.Name)]"
        Write-Host "  Type       : $($inst.Type)"
        Write-Host "  State      : $($inst.State)"
        Write-Host "  AMI        : $($inst.Image)"
        Write-Host "  Public IP  : $(if ($inst.PublicIp) { $inst.PublicIp } else { '(none)' })"
        Write-Host "  Private IP : $($inst.PrivateIp)"
        # An absent instance profile does not rule out SSM: this account registers nodes
        # through Default Host Management, so the agent gets credentials without one.
        Write-Host "  Profile    : $(if ($inst.Profile) { $inst.Profile } else { '(none)' })"

        if ($inst.State -eq 'running' -and $inst.PublicIp) {
            Write-Host ""
            foreach ($p in @{N='RDP';P=3389}, @{N='WinRM-HTTP';P=5985}, @{N='WinRM-HTTPS';P=5986}) {
                $open = Test-Port -ComputerName $inst.PublicIp -Port $p.P
                Write-Host ("  {0,-12} {1,-5} {2}" -f $p.N, $p.P, $(if ($open) { 'open' } else { 'closed' }))
            }
            Write-Host ""
            Write-Host "  SSM        : $(if (Test-SsmAvailable -Inst $inst) { 'online' } else { 'unavailable' })"
        }
        Write-Host ""
    }

    'Start' {
        if ($inst.State -eq 'running') { Write-Ok 'Already running' }
        else {
            Write-Step "Starting $($inst.Id)"
            Invoke-Aws ec2 start-instances --instance-ids $inst.Id | Out-Null
            Invoke-Aws ec2 wait instance-running --instance-ids $inst.Id | Out-Null
            $inst = Resolve-Instance -NameOrId $inst.Id
            Write-Ok "Running at $($inst.PublicIp)"
        }

        # RDP is the one port this AMI is known to expose, so it is the boot-complete signal.
        Wait-Port -ComputerName $inst.PublicIp -Port 3389 -Label 'RDP' | Out-Null
        if (Test-Port -ComputerName $inst.PublicIp -Port 5986) { Write-Ok 'WinRM over HTTPS is available' }
        else { Write-Warn 'WinRM not available; run -Action EnableWinRM to turn it on' }
    }

    'Stop' {
        if ($inst.State -eq 'stopped') { Write-Ok 'Already stopped' }
        else {
            Write-Step "Stopping $($inst.Id)"
            Invoke-Aws ec2 stop-instances --instance-ids $inst.Id | Out-Null
            Invoke-Aws ec2 wait instance-stopped --instance-ids $inst.Id | Out-Null
            Write-Ok 'Stopped'
        }
    }

    'Run' {
        if (-not $Command -and -not $ScriptFile) { throw 'Pass -Command or -ScriptFile.' }
        if ($Command -and $ScriptFile)           { throw 'Pass only one of -Command or -ScriptFile.' }
        if ($inst.State -ne 'running')           { throw "$($inst.Id) is $($inst.State); start it first." }

        $script = if ($ScriptFile) {
            if (-not (Test-Path $ScriptFile)) { throw "Script file not found: $ScriptFile" }
            Get-Content $ScriptFile -Raw
        } else { $Command }

        Invoke-Remote -Inst $inst -Script $script
    }

    'Capture' {
        if (-not $ImageName) { throw 'Pass -ImageName, e.g. "Windows Server 2019 VS2026/VS2022/JDK21/msparser/MSFileReader/ramdisk v9".' }

        # Capturing a stopped instance avoids the crash-consistency caveat that comes with
        # imaging a live one, and the workflow stops the box at the end anyway.
        if ($inst.State -ne 'stopped') {
            throw "$($inst.Id) is $($inst.State). Stop it first (-Action Stop) so the image is clean."
        }

        $existing = Invoke-Aws ec2 describe-images --owners self `
            --filters "Name=name,Values=$ImageName" --query 'Images[].ImageId' --output text
        if (($existing | Out-String).Trim()) {
            throw "An AMI named '$ImageName' already exists ($(($existing | Out-String).Trim())). Pick a new name."
        }

        Write-Step "Creating AMI '$ImageName' from $($inst.Id)"
        $imageId = (Invoke-Aws ec2 create-image --instance-id $inst.Id --name $ImageName `
            --query 'ImageId' --output text | Out-String).Trim()
        Write-Ok "Image $imageId requested"

        # 'aws ec2 wait image-available' gives up after 40 x 15s = 10 minutes, which a
        # multi-hundred-GB Windows image routinely exceeds. Poll on our own clock instead
        # so a slow snapshot is not reported as a failure.
        Write-Step 'Waiting for the image to become available (a large Windows image can take 30+ minutes)'
        $deadline = (Get-Date).AddMinutes(90)
        while ((Get-Date) -lt $deadline) {
            $state = (Invoke-Aws ec2 describe-images --image-ids $imageId `
                --query 'Images[0].State' --output text | Out-String).Trim()
            if ($state -eq 'available') { break }
            if ($state -in 'failed','error','invalid') { throw "Image $imageId entered state '$state'." }
            Write-Host "    state=$state" -ForegroundColor DarkGray
            Start-Sleep -Seconds 30
        }
        if ($state -ne 'available') { throw "Image $imageId still '$state' after 90 minutes." }
        Write-Ok "$imageId is available"
        Write-Warn 'Now point the TeamCity agent cloud image at it; this script does not touch TeamCity.'
    }

    'EnableWinRM' {
        if ($inst.State -ne 'stopped') {
            Write-Step 'Stopping instance so user data can be replaced'
            Invoke-Aws ec2 stop-instances --instance-ids $inst.Id | Out-Null
            Invoke-Aws ec2 wait instance-stopped --instance-ids $inst.Id | Out-Null
            $inst = Resolve-Instance -NameOrId $inst.Id
        }

        Write-Step 'Staging the WinRM boot script'
        Set-BootScript -Inst $inst -UserData $script:EnableWinRmUserData

        Write-Step 'Starting instance to apply it'
        Invoke-Aws ec2 start-instances --instance-ids $inst.Id | Out-Null
        Invoke-Aws ec2 wait instance-running --instance-ids $inst.Id | Out-Null
        $inst = Resolve-Instance -NameOrId $inst.Id
        Write-Ok "Running at $($inst.PublicIp)"

        if (Wait-Port -ComputerName $inst.PublicIp -Port 5986 -Label 'WinRM over HTTPS') {
            Write-Ok 'WinRM is enabled. Remember: -Action ClearBoot before capturing an AMI.'
        }
        else {
            Write-Warn 'WinRM still not reachable. Check whether user data ran, via RDP:'
            Write-Warn '  C:\ProgramData\Amazon\EC2Launch\log\agent.log                     (EC2Launch v2)'
            Write-Warn '  C:\ProgramData\Amazon\EC2-Windows\Launch\Log\UserdataExecution.log (v1)'
        }
    }

    'ClearBoot' {
        if ($inst.State -ne 'stopped') {
            Write-Step 'Stopping instance so user data can be cleared'
            Invoke-Aws ec2 stop-instances --instance-ids $inst.Id | Out-Null
            Invoke-Aws ec2 wait instance-stopped --instance-ids $inst.Id | Out-Null
            $inst = Resolve-Instance -NameOrId $inst.Id
        }
        Set-BootScript -Inst $inst -UserData ''
        Write-Ok 'Boot script cleared; nothing extra will run on the next boot.'
    }

    'Rdp' {
        if ($inst.State -ne 'running') { throw "$($inst.Id) is $($inst.State); start it first." }
        Write-Step "Opening RDP to $($inst.PublicIp)"
        Write-Warn 'Sign in as Administrator with the password this AMI was built with.'
        Write-Warn 'AWS cannot supply it: ec2:GetPasswordData is denied and the image was never sysprepped.'
        Start-Process mstsc.exe -ArgumentList "/v:$($inst.PublicIp)"
    }
}
