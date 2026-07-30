# Windows AMI updates on AWS

How to update the Windows AMI that the TeamCity build agents launch from, driven from a
local checkout (including by Claude).

Scripts:
[`ai/scripts/AWS/Ec2Windows.ps1`](../scripts/AWS/Ec2Windows.ps1) (instance control + remote
execution + capture) and
[`ai/scripts/AWS/Setup-AmiV9.ps1`](../scripts/AWS/Setup-AmiV9.ps1) (the content changes for
the current image).

## Inventory

Account `999145429263`, region `us-west-2`. Key pair `teamcity-chambm-maccoss`, security
group `sg-0175b412cb58a33d6`, subnet `subnet-0d6974ea88c0b50ec`.

| Instance | Id | Type | Purpose |
|---|---|---|---|
| TeamCityAMICreator | `i-08a7c32d788fa3c3e` | m6i.2xlarge | Normal AMI build box (~$0.38/hr) |
| TeamCityAMICreatorHuge | `i-08e51abfea038d4cc` | m7i.16xlarge | Same AMI, heavy builds (~$3.40/hr) |
| TeamCity Linux AMI creator | `i-007636c18cb6234c2` | m8i.2xlarge | Linux equivalent |

Published Windows AMIs, newest first:

- `ami-0b85c36a722bd2b75` — ...ramdisk **v9** (2026-07-30) — adds PowerShell 7 + .NET 8 SDK
- `ami-0302a16b404d175d8` — ...ramdisk **v8** (2026-03-11)
- `ami-0fe0196a10efa2d56` — ...ramdisk v7 - patched (2024-12-18)

Every image through v8 was captured from `TeamCityAMICreator` itself (verify with the
snapshot description: `Created by CreateImage(i-...)`). v9 broke that pattern deliberately —
see "Building a new image" below.

## Access model

**Use the `maccoss-chambm` profile, not the default.** Two identities are configured and
the difference decides whether anything works. Probed 2026-07-29:

| Action | `default` (`svc-teamcity-server`) | `maccoss-chambm` (`chambm`) |
|---|---|---|
| `ec2:Describe*` | yes | yes |
| `ec2:StartInstances` / `StopInstances` / `RebootInstances` | yes | yes |
| `ec2:CreateTags`, `ec2:ModifyInstanceAttribute` | yes | yes |
| `ec2:RunInstances`, `ec2:TerminateInstances`, `ec2:ModifyVolume` | not probed | yes |
| `ssm:SendCommand` / `GetCommandInvocation` / `DescribeInstanceInformation` | **no** | **yes** |
| `ec2:CreateImage` | **no** | **yes** |
| `ec2:GetPasswordData`, `ec2:GetConsoleOutput` | no | not probed |
| `iam:GetInstanceProfile` | no | no |

`Ec2Windows.ps1` defaults to `maccoss-chambm`; override with `-AwsProfile` or
`$env:AWS_PROFILE`. Everything the AMI workflow needs works under it.

The history is worth knowing so nobody re-investigates: in December 2024 Brian Connolly
granted Matt's **personal** IAM account SSM admin and installed the SSM agent on
`i-08a7c32d788fa3c3e`. Apparent "SSM is denied" findings are only ever the service account
being used by mistake. Brian's closing note on that thread: *"You need to submit that CLI
command as your IAM account and not the service IAM account."*

### Network

`sg-0175b412cb58a33d6` ("TeamCity Agents Peered") allows **all** protocols from a short
allowlist of individual developer IPs. Remote access works only from one of those
addresses. The subnet auto-assigns a public IP, so the address changes on every start —
never hardcode it.

## Remote command execution

**SSM Run Command is the path.** Verified end to end 2026-07-29/30: the agent reports
`Online` (v3.3.1345.0) and `AWS-RunPowerShellScript` returns stdout normally.

```powershell
pwsh -File ai\scripts\AWS\Ec2Windows.ps1 -Action Run -Command 'choco upgrade all -y'
pwsh -File ai\scripts\AWS\Ec2Windows.ps1 -Action Run -ScriptFile .\update-build-tools.ps1
```

Instances register **without an IAM instance profile** —
`describe-iam-instance-profile-associations` returns empty while
`describe-instance-information` shows `Online`, because the account uses SSM Default Host
Management. Do not "fix" the missing profile; nothing is broken.

### What running as SYSTEM does and does not prove

SSM executes as `NT AUTHORITY\SYSTEM`, but the TeamCity agents run as **Administrator**.
That difference produced several dead ends worth recognising on sight, none of which were
defects in the image:

| Symptom under SSM/SYSTEM | Cause | Why the agents are unaffected |
|---|---|---|
| `CSC error CS0006` — NuGet metadata files "could not be found" under `system32\config\systemprofile\.nuget` | 32-bit MSBuild's writes are WOW64-redirected to `SysWOW64`, while 64-bit `csc` is handed the literal `System32` path | Administrator has a real profile; no redirection |
| `NU1101` — "no packages exist in source(s): Microsoft Visual Studio Offline Packages" | SYSTEM's `NuGet.Config` has an empty `<packageSources>` | Administrator's config has nuget.org |
| `InvalidOperationException: Showing a modal dialog box ... not in UserInteractive mode` | Session 0 isolation; no desktop | The TC agents have an interactive desktop |

The last one is a hard ceiling: **Skyline perf/tutorial tests are functional UI tests and
cannot be run over SSM at all.** Remote execution can prove they build, stage and launch;
only a real agent (or an RDP session) can run them.

## Building a new image

v9 was **not** built by mutating `TeamCityAMICreator`. It was built by launching a fresh
instance from the previous image, applying a script, and capturing that. Prefer this: the
golden-master approach has no rollback, serialises everyone onto one box, and silently
accumulates undocumented drift.

```powershell
$ec2 = 'C:\dev\pwiz\ai\scripts\AWS\Ec2Windows.ps1'
$p   = 'maccoss-chambm'

# 1. launch from the previous image with the root size you want
aws ec2 run-instances --profile $p --image-id <previous-ami> --count 1 `
    --instance-type m6i.2xlarge --key-name teamcity-chambm-maccoss `
    --security-group-ids sg-0175b412cb58a33d6 --subnet-id subnet-0d6974ea88c0b50ec `
    --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":150,"VolumeType":"gp3","DeleteOnTermination":true}}]' `
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=TeamCityAMICreator-vNbuild}]'

# 2. apply the content changes (idempotent; ends with a PASS/FAIL verification block)
pwsh -File $ec2 -Action Run -Instance <id> -ScriptFile ai\scripts\AWS\Setup-AmiV9.ps1

# 3. the partition inherits the SNAPSHOT's size, so extend it to the new volume size
#    (rescan + Resize-Partition; see the script in step 2's sibling scratch or do it inline)

# 4. capture, then throw the instance away
pwsh -File $ec2 -Action Stop    -Instance <id>
pwsh -File $ec2 -Action Capture -Instance <id> -ImageName '...ramdisk v10'
aws ec2 terminate-instances --profile $p --instance-ids <id>
```

`Capture` refuses a non-stopped instance and refuses to reuse an existing image name, then
polls until the image is `available` (a large Windows image takes well over the AWS CLI
waiter's 10-minute limit, so the script polls on its own clock).

Terminating the build instance is safe: the AMI and its snapshot are independent objects
and survive.

Afterwards, point the TeamCity agent cloud image at the new AMI in TeamCity's own
configuration — none of this touches TeamCity.

### Sizing

**Root volume size in an AMI is a floor, not a ceiling.** A cloud profile can launch agents
with a *larger* root than the image specifies (verified: a 150 GB v9 launched at 200 GB),
but never smaller — EBS requires a volume created from a snapshot to be at least the
snapshot's original size, and volumes cannot shrink. So keep the captured image modest and
size the agents at launch.

Measured requirements for the Osprey perf/regression config on a v9-derived box:

| Item | Size |
|---|---|
| Base image content | ~79 GB |
| `osprey-testfiles-mzML-v2` extracted + derived | ~41 GB (14 GB zip + 27 GB extracted) |
| Astral mode-3 scratch (stages inputs **by copy**) | ~37 GB peak |

`pwiz_tools/Osprey/Regression/TEAMCITY-CONFIG.md` quotes "~55 GB free"; that is optimistic
for the Astral HPC-chain leg. 100 GB cannot finish the run at all; 150 GB is marginal;
200 GB is comfortable.

**RAM is the tighter constraint.** m6i.2xlarge has 31.5 GB and only 8 vCPUs, and the image
carries a **20 GB ImDisk RAM disk on `Z:`** (dynamically allocated, so it consumes RAM as
used). `TEMP` is `Z:\Temp`, and the Skyline perf harness downloads test data to
`z:\download` — i.e. into RAM. Observed during an Osprey Astral run: a single Osprey
process at 15.85 GB working set and commit at 38.54 of 42.83 GB (90%), with straight-through
wall time swinging 8:39 / 51:42 / 53:26 across runs on identical data with byte-identical
output. Anything memory- or timing-sensitive wants a larger instance type, not a bigger
disk.

## Perf-test data must not persist on agents

The datasets are re-acquired per run and are deliberately not baked into the image.
`scripts/misc/tc-perftests.bat` (master) enforces this:

```bat
IF "%USERNAME%" neq "maccoss-teamcity" set SKYLINE_DOWNLOAD_PATH=z:\download
IF "%USERNAME%" equ "maccoss-teamcity" set SKYLINE_DOWNLOAD_FROM_S3=0
```

So S3 download is the default and is disabled only for the persistent TCA1 agent; AWS
agents pull from the S3 mirror into the RAM disk, and the script wipes
`%SKYLINE_DOWNLOAD_PATH%` and `z:\Temp` after **every** test.

`SKYLINE_DOWNLOAD_PATH` is the override for where data lands
(`PathEx.GetDownloadsPath()` / `Regression\RegressionData.ps1:35`); it does not control the
source. If you run a perf harness by hand without setting it, data lands in the invoking
account's Downloads folder — under SSM that is the SYSTEM profile — and must be deleted
before any capture.

## net8 Skyline

The `ProteoWizard_SkylineWindowsNetPerfTutorialTests` config is the **net8** port
(branch `Skyline/work/20260612_net8_port`), which is why it needs exactly what v9 adds:

- `pwsh` — `Stage-Net8Tests.ps1`, and `tctest.bat` invokes `pwsh` directly (project standard,
  no `powershell.exe` fallback)
- .NET 8 SDK — `dotnet build -f net8.0-windows`

Entry points on that branch are `pwiz_tools/Skyline/build.bat` and
`pwiz_tools/Skyline/tc-perftests.bat` (master's perf entry point is
`scripts/misc/tc-perftests.bat` — different file, different suite). `tc-perftests.bat`
honours `SKYLINE_TEST_ARGS` to run a single test instead of the two full suites.

Verified on v9 (2026-07-30): the net8 tree builds with **0 errors** including the vendor
readers under `--i-agree-to-the-vendor-licenses`, stages all four projects, and launches
`TestRunner.exe`. Test execution itself needs an interactive desktop (see above).

## WinRM fallback — currently not working

Only relevant if SSM becomes unavailable. The stock image exposes **RDP only**; 5985/5986
and 22 are closed.

`-Action EnableWinRM` stages an EC2 user-data boot script that enables WinRM over HTTPS
with a self-signed cert and opens 5986. It is marked `<persist>true</persist>` because
Windows will not re-run one-shot user data on an instance that has already booted, and
these instances are years old.

**It does not work on this image.** `describe-instance-attribute` confirms the payload is
stored and the instance boots with RDP reachable, but 5986 never opens — the user data
appears never to execute, plausible for a hand-built AMI whose EC2Launch state was never
reset. `GetConsoleOutput` is denied, so there is no remote way to confirm.

To resolve, RDP in and either read
`C:\ProgramData\Amazon\EC2Launch\log\agent.log` (v2) /
`C:\ProgramData\Amazon\EC2-Windows\Launch\Log\UserdataExecution.log` (v1), or skip user data
entirely and enable WinRM from an elevated prompt (the config persists in the OS):

```powershell
Enable-PSRemoting -Force -SkipNetworkProfileCheck
$cert = New-SelfSignedCertificate -DnsName $env:COMPUTERNAME -CertStoreLocation Cert:\LocalMachine\My
New-Item -Path WSMan:\localhost\Listener -Transport HTTPS -Address * `
    -CertificateThumbPrint $cert.Thumbprint -Force
New-NetFirewallRule -Name 'WinRM-HTTPS-In' -DisplayName 'WinRM over HTTPS (5986)' `
    -Enabled True -Direction Inbound -Protocol TCP -LocalPort 5986 -Action Allow
Set-Service -Name WinRM -StartupType Automatic
Restart-Service WinRM
```

Then run `-Action ClearBoot` to drop the staged user data. Note that enabling WinRM changes
OS state that **does** survive into a later capture; `ClearBoot` removes the user data, not
the listener.

Authentication needs the Administrator password. `ec2:GetPasswordData` is denied and these
AMIs were never sysprepped, so EC2 holds no password blob — supply the image's own password
once and it is cached with DPAPI for the current user:

```powershell
$c = Get-Credential Administrator
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.claude-tools\ec2-windows" | Out-Null
$c | Export-Clixml "$env:USERPROFILE\.claude-tools\ec2-windows\<instance-id>.xml"
```

## Prior art: the AWS-UpdateWindowsAmi dead end

Brian evaluated AWS's turnkey patching runbook in December 2024:

```bash
aws ssm start-automation-execution \
    --document-name="AWS-UpdateWindowsAmi" \
    --parameters SourceAmiId='ami-07f64fe1ae8677a7d',IamInstanceProfileName='mc-SSMInstanceProfile',\
AutomationAssumeRole='arn:aws:iam::999145429263:role/mc-AmazonSSMAutomationRole',\
TargetAmiName='...',InstanceType='m6i.2xlarge',SubnetId='subnet-0d6974ea88c0b50ec',\
SecurityGroupIds='sg-0175b412cb58a33d6'
```

It fails at the second step because `%TEMP%` is on the ramdisk, as do several nested
runbooks. `TEMP`/`TMP` cannot be overridden for a runbook execution.

Probed 2026-07-29: `TEMP` is `Z:\Temp`, the drive exists and is writable, so a ramdisk
`TEMP` is fine *within* one command. What defeats the runbook is that it **reboots between
steps** and ramdisk contents do not survive, so anything staged by step 1 is gone by step 2.
Single-shot Run Command never hits this.

A failed execution also leaves its instance running — check for strays. More to the point,
the runbook builds an image end to end with no opportunity to install anything else, which
is not what this workflow needs. Treat it as investigated and rejected.

## Gotchas

- **`modify-instance-attribute --user-data` needs base64**, and clearing it needs an
  explicit `Value=` (a bare `--attribute userData` is rejected with `MissingParameter`).
  Unlike `run-instances` it will not encode a `file://` payload, and a raw `<powershell>`
  block trips the shorthand parser on the first `<`.
- **User data can only be changed while stopped.**
- **A resized volume stays `optimizing` for a while** and I/O is degraded meanwhile — do not
  trust perf numbers taken during that window (`describe-volumes-modifications`).
- **Extending a volume does not extend the partition.** Rescan the disk and
  `Resize-Partition`, or the extra space is invisible to Windows.
- **Deleting `C:\ProgramData\Microsoft\VisualStudio\Packages` breaks Visual Studio
  discovery.** It looks like a download cache but also holds `_Instances\<id>\state.json`,
  the installer's instance registry. Without it VS still runs but `vswhere` finds nothing,
  so any build that locates MSBuild that way fails — and `vs_installer repair` cannot fix
  it (exit 87: no instance to repair). Recover by copying `_Instances` back from a snapshot
  of a known-good volume.
- **`git gc` on the checkouts is not worth it** — measured 0.29 GB across both repos while
  transiently using more than it freed.
- **The AWS CLI dies with a `charmap` codec error** on output containing non-cp1252
  characters; set `PYTHONIOENCODING=utf-8` (`Ec2Windows.ps1` does).
- **Cost.** m6i.2xlarge ~$0.38/hr; gp3 storage $0.08/GB-month applies to stopped instances
  too. Stop when finished and terminate throwaway build instances.
