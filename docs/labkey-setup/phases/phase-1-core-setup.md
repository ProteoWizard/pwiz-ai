# Phase 1: Core Setup

**Goal**: Install PowerShell 7, Java, Git, and configure SSH.

## Prerequisites
Review state.json to see which components are already installed (marked [OK] in environment check).

## Step 1.1: PowerShell 7

**Skip if**: Environment check showed [OK]

**Install**:
```bash
powershell.exe -Command "winget install Microsoft.PowerShell --source winget --accept-source-agreements --accept-package-agreements"
```

**Restart terminal** - Have user close and reopen their terminal, then run `claude --resume`.

**Before restart, output Resume Checkpoint:**
```
## Resume Checkpoint
**Current:** Phase 1, Step 1.1 (PowerShell 7)
**Next:** Phase 1, Step 1.2 (Java)
**Remaining:** Core Setup steps 1.2-1.4, Phases 2-10
```

**Update state.json** after restart verification:
```json
{"completed": ["phase-1-step-1.1"]}
```

## Step 1.2: Java

**Skip if**: Environment check showed correct Java version [OK]

**Determine version** from state.json (17 or 25 based on LabKey version).

**Install**:
```bash
# For Java 17:
powershell.exe -Command "winget install EclipseAdoptium.Temurin.17.JDK --source winget --interactive"

# For Java 25:
powershell.exe -Command "winget install EclipseAdoptium.Temurin.25.JDK --source winget --interactive"
```

**Important**: Tell user to enable "Set JAVA_HOME variable" in installer dialog.

**Verify JAVA_HOME** (read from registry immediately):
```bash
powershell.exe -Command "[System.Environment]::GetEnvironmentVariable('JAVA_HOME', 'Machine')"
```

**Verify Java version**:
```bash
powershell.exe -Command "java -version"
```

**If JAVA_HOME not set**, set it manually:
```bash
# Get Java path
powershell.exe -Command "(Get-Command java).Source"

# Set JAVA_HOME (use parent of bin directory)
powershell.exe -Command "[System.Environment]::SetEnvironmentVariable('JAVA_HOME', 'C:\Program Files\Eclipse Adoptium\jdk-17.0.x', 'Machine')"
```

**Update state.json**:
```json
{"completed": ["phase-1-step-1.2"]}
```

## Step 1.3: Git Configuration

**Skip if**: Environment check showed [OK]

**Install Git** (if missing):
```bash
powershell.exe -Command "winget install Git.Git --source winget --accept-source-agreements --accept-package-agreements"
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

**Generate key**:
```bash
ssh-keygen -t ed25519 -C "user-email@example.com"
```

Note: This requires user interaction - they'll press Enter for default location and optionally set a passphrase.

**Display public key** for user to copy:
```bash
cat ~/.ssh/id_ed25519.pub
```

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
