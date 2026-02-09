# Phase 1: Core Setup

**Goal**: Install Java, Git, and configure SSH.

## Prerequisites
Review state.json to see which components are already installed (marked [OK] in environment check).

## Step 1.1: Java

**Skip if**: Environment check showed correct Java version [OK]

**Determine version** from state.json (17 or 25 based on LabKey version).

**Before launching the installer, tell the user:**

> The Java installer will open a GUI. Here's what to watch for:
>
> 1. **UAC prompt** — Click **Yes** to allow changes
> 2. **Custom Setup screen** — This is the critical screen. Click the icons next to these features and select **"Will be installed on local hard drive"** (or ensure they are enabled):
>    - **Set JAVA_HOME variable** — Required for LabKey's Gradle build to find Java
>    - **Add to PATH** — Required so `java` works from the command line
> 3. Click **Next** through the remaining screens and **Install**
>
> Are you ready to start the installer?

**Wait for the user to confirm**, then run the appropriate installer.

**Install**:
```bash
# For Java 17:
powershell.exe -Command 'winget install EclipseAdoptium.Temurin.17.JDK --source winget --interactive'

# For Java 25:
powershell.exe -Command 'winget install EclipseAdoptium.Temurin.25.JDK --source winget --interactive'
```

**Important**: Tell user to enable "Set JAVA_HOME variable" in installer dialog.

**Do NOT verify yet** — JAVA_HOME and java are added to PATH at the Machine level
by the installer, but Git Bash will not pick them up until the terminal is restarted.

**Update state.json**:
```json
{"completed": ["phase-1-step-1.1"]}
```

## Step 1.2: Restart Terminal

Step 1.1 installs software that modifies PATH at the Machine level.
Git Bash will not see these changes until the terminal is restarted. Do NOT
skip this step or try to work around it with registry lookups.

**Have user close and reopen their terminal**, then run the resume command
shown in the checkpoint below.

**Before restart, output Resume Checkpoint** (substitute the actual setup_root)
from state.json for the `cd` path):
```
## Resume Checkpoint
**Current:** Phase 1, Step 1.2 (Restart Terminal)
**Next:** Phase 1, Step 1.3 (Git Configuration)
**Remaining:** Core Setup steps 1.3-1.4, Phases 2-9

**To resume:** `cd "<setup_root>"; claude --resume`
```

**After restart, verify Java is in PATH:**
```bash
java -version
echo $JAVA_HOME
```

**If JAVA_HOME is empty** (fallback — only if the above fails), read from registry
and set it in the current shell:
```bash
powershell.exe -Command '[System.Environment]::GetEnvironmentVariable("JAVA_HOME", "Machine")'
# Then export it for the current shell session:
export JAVA_HOME="<value from above>"
```

**If JAVA_HOME is not in the registry either**, set it manually:
```bash
# Find where java was installed
powershell.exe -Command '(Get-Command java).Source'

# Set JAVA_HOME at the Machine level (use parent of bin directory)
powershell.exe -Command '[System.Environment]::SetEnvironmentVariable("JAVA_HOME", "C:\Program Files\Eclipse Adoptium\jdk-17.0.x", "Machine")'
```

**Update state.json**:
```json
{"completed": ["phase-1-step-1.2"]}
```

## Step 1.3: Git Configuration

**Skip if**: Environment check showed [OK]

**Install Git** (if missing):
```bash
powershell.exe -Command 'winget install Git.Git --source winget --accept-source-agreements --accept-package-agreements'
```

**Restart terminal** after installation.

**Configure autocrlf**:
```bash
git config --global core.autocrlf true
```

**Verify**:
```bash
git config core.autocrlf
```

Should output: `true`

**Update state.json**:
```json
{"completed": ["phase-1-step-1.3"]}
```

## Step 1.4: SSH Key Setup

**Skip if**: Environment check showed SSH key exists [OK]

**Get user email** — try git config first:
```bash
git config user.email
```
- If it returns an email, use that value in the ssh-keygen command below.
- If it returns empty or errors, **ask the user to type their GitHub email
  directly in the chat** (do NOT use AskUserQuestion — it has no free-text
  input field). Wait for their reply before continuing.
- Once you have the email, also set git identity if not already configured:
```bash
git config --global user.email "THEIR_EMAIL"
git config --global user.name "Their Name"
```

**Generate key** (substitute the actual email). Use `-f` and `-N ""` to avoid
interactive prompts — default location, no passphrase:
```bash
ssh-keygen -t ed25519 -C "THEIR_EMAIL" -f ~/.ssh/id_ed25519 -N ""
```

**Display public key** for user to copy using the Read tool on `~/.ssh/id_ed25519.pub`.
Do NOT use `cat` — its output may not render for the user.

**Instruct user**:
1. Copy the key output
2. Go to https://github.com/settings/keys
3. Click "New SSH key"
4. Paste the key and save

**Test GitHub connection**:
```bash
ssh -T git@github.com
```

Expected output contains: "successfully authenticated"

**Update state.json**:
```json
{"completed": ["phase-1-step-1.4"]}
```

## Completion

All core components installed. Mark phase complete and show progress.

**Next**: Phase 2 - PostgreSQL
