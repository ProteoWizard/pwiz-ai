<!--
  LabKey Server Development Environment Setup Guide for LLM Assistants
  =====================================================================
  This document is designed to be fetched and followed by Claude Code or similar
  LLM assistants. It guides setup of a Windows machine for LabKey Server development.

  Target audience: LLM assistants helping a human set up their development environment.
  Human-readable version: https://www.labkey.org/Documentation/wiki-page.view?name=devMachine

  MacCoss Lab specific notes: https://skyline.ms/home/development/wiki-page.view?name=build_and_deploy
-->

# LabKey Server Development Environment Setup

You are helping a developer set up a Windows machine for LabKey Server development, specifically for working on MacCoss Lab modules (targetedms, MacCossLabModules, etc.). Follow these phases in order, verifying each step before proceeding.

## Important Notes for the LLM Assistant

- **Complete ALL phases**: Do not declare success until you have worked through every phase in this document. Phases marked "optional" should still be offered to the user.
- **Wait for user responses**: When you ask the user a question, STOP and wait for their answer before proceeding. Do NOT run commands or checks in parallel with questions. The conversation is sequential - ask, wait, then act based on their response.
- **Run commands directly**: Execute ALL commands yourself using the Bash tool. NEVER ask the user to run commands - run them yourself. Exceptions where the user runs commands:
  - **GUI interactions** - clicking through installer dialogs, IntelliJ configuration
  - **Interactive prompts** - commands that require user input (e.g., `gradlew setPassword`)
  - **Long-running tasks** - build (15-30 min) and tests (can be 30+ min) - user runs in separate terminal to see progress and minimize token usage
  - **Information gathering** - when you need their email, preferences, etc.
- **Verify each step**: Run verification commands to confirm success before moving on
- **Guide GUI steps**: For IntelliJ and other GUI installers, tell the user exactly what to click
- **UAC prompts**: Windows installers show a "User Account Control" dialog asking "Do you want to allow this app to make changes to your device?" - remind users to click **Yes** when this appears
- **Show progress tracker**: After each phase, display a progress summary showing ALL phases with their status. Use colored indicators:

```
## Progress
✅ Getting Started: Version selection + Environment check
🔄 Phase 1: Core Setup (PowerShell 7, Java, Git, SSH) ← in progress
⬜ Phase 2: PostgreSQL
⬜ Phase 3: Repository Setup
⬜ Phase 4: Gradle Configuration
⬜ Phase 5: Initial Build
⬜ Phase 6: IntelliJ Setup
⬜ Phase 7: Running LabKey Server
⬜ Phase 8: Test Setup
⬜ Phase 9: Developer Tools (optional)
⬜ Phase 10: AI Tooling (optional)
```

Legend: ✅ = completed, 🔄 = in progress, ⬜ = pending

- **Final report required**: At the end, produce a comprehensive report covering ALL items (completed, skipped, and deferred). See "Final Report" section at the end of this document.
- **Track improvements**: Keep notes on any issues, corrections, or friction points encountered during setup. After the final report, you will update this document with improvements. This is a self-improving document - when you fetch new version requirements from labkey.org (Step 1, option 4), update the cached requirements table immediately.
- **Track progress before terminal restarts**: When asking the user to restart their terminal, you MUST output a "Resume Checkpoint" block before they restart. This is NOT optional. Format:
  ```
  ## Resume Checkpoint
  **Current:** Phase X, Step X.X (Step Name)
  **Next:** Phase X, Step X.X (Step Name)
  **Remaining phases:** [list uncompleted phases]
  ```
  After the user runs `claude --resume`, your FIRST action must be to re-read this document and state: "Resuming from Phase X, Step X.X. Next step is..." before doing anything else.
- **Actively offer optional items**: Components marked optional (GitHub CLI, Claude Code, TortoiseGit, etc.) should be explicitly offered to the user with a brief explanation, not just listed as "not required". Present them as choices, not afterthoughts.

### Windows Command Execution

**CRITICAL:** This is a Windows environment. The Bash tool uses Git Bash, which doesn't understand PowerShell syntax.

**PowerShell availability:**
- **`powershell.exe`** - Windows PowerShell 5.1, always available on Windows 10/11
- **`pwsh`** - PowerShell 7+, only available after installation

On a pristine machine, `pwsh` won't exist. Use `powershell.exe` for the initial environment check and PowerShell 7 installation. After PowerShell 7 is installed, you can use either.

For PowerShell commands, use this pattern:
```bash
# Before PowerShell 7 is installed (use powershell.exe):
powershell.exe -Command "your-command-here"

# After PowerShell 7 is installed (can use pwsh):
pwsh -Command "your-command-here"
```

Examples:
```bash
# Check environment variable
powershell.exe -Command "$env:JAVA_HOME"

# Run winget
powershell.exe -Command "winget install Git.Git --source winget"

# Test path
powershell.exe -Command "Test-Path 'C:\some\path'"
```

Do NOT use bare PowerShell commands like `$env:JAVA_HOME` in the Bash tool - they will fail.

### Verifying Newly Set Environment Variables

**IMPORTANT:** When a system environment variable is set (e.g., JAVA_HOME), it won't be visible in the current shell session. The session must be restarted, OR you can read directly from the registry:

```bash
# Read system environment variable directly from registry (works immediately)
powershell.exe -Command "[System.Environment]::GetEnvironmentVariable('JAVA_HOME', 'Machine')"

# Read user environment variable directly from registry
powershell.exe -Command "[System.Environment]::GetEnvironmentVariable('SOME_VAR', 'User')"
```

Use this method to verify environment variables immediately after setting them, without requiring a shell restart.

---

## Prerequisites

Before starting this setup, you must have:
- **Claude Code** - Installed and authenticated
- **Git** - Required by Claude Code (provides Git Bash on Windows)

> **Why Git is required:** Claude Code's Bash tool uses Git Bash on Windows to provide a Unix-like shell environment. This ensures cross-platform consistency for commands and scripts.

If Claude Code or Git are not installed, they must be installed first before proceeding with this developer setup guide.

---

## Getting Started

### Step 1: Determine Target LabKey Version

**Ask the user which LabKey version they will be developing for:**

```
Which LabKey version will you be developing for?

1. LabKey 25.7.x and lower → Java 17 + PostgreSQL 17
2. LabKey 25.11.x → Java 17 + PostgreSQL 17 or 18
3. LabKey 26.x (release26.3 and later) → Java 25 + PostgreSQL 18
4. Other version (I will fetch requirements from labkey.org and update this document)

Enter 1, 2, 3, or 4:
```

**If they choose 1, 2, or 3**, use the cached requirements below.

**If they choose 4**, follow these steps to fetch and cache the requirements:

1. Ask them which specific LabKey version (e.g., "25.3", "26.1", "27.1")
2. Fetch the latest requirements from https://www.labkey.org/Documentation/wiki-page.view?name=supported
3. Extract the Java and PostgreSQL versions for that specific LabKey version
4. **Update this document** if the version is found:
   - Add a new row to the "Cached Version Requirements" table below with the version, Java requirement, and PostgreSQL support
   - Update the retrieval date in the table caption
   - Use the Edit tool to update this document - this makes the document self-improving
5. Proceed with setup using the fetched requirements

> **Why update the document?** This makes the setup guide self-improving. When new LabKey versions are released, the first person to use them will automatically update the cached requirements for everyone who uses the document afterward.

**Cached Version Requirements** (from [LabKey Supported Technologies](https://www.labkey.org/Documentation/wiki-page.view?name=supported), retrieved 2026-01-30):

| LabKey Version | Java Required | PostgreSQL Support |
|----------------|---------------|--------------------|
| 25.7.x and lower | Java 17 (Temurin 17) | PostgreSQL 17 only |
| 25.11.x | Java 17 (Temurin 17) | PostgreSQL 17 or 18 |
| 26.x | Java 25 (Temurin 25) | PostgreSQL 18 |

Record their choice - it determines component versions throughout setup.

### Step 2: Run Environment Check

**Run the verification script to see what's already installed.**

> **Important:** Use `powershell.exe` (not `pwsh`) since PowerShell 7 may not be installed yet on a pristine machine.

Look for `Verify-LabKeyEnvironment.ps1` in the user's directory, then run it with the appropriate LabKey version (25 or 26):

```bash
# For LabKey 25.x:
powershell.exe -ExecutionPolicy Bypass -File "Verify-LabKeyEnvironment.ps1" -LabKeyVersion 25

# For LabKey 26.x:
powershell.exe -ExecutionPolicy Bypass -File "Verify-LabKeyEnvironment.ps1" -LabKeyVersion 26
```

> **Note:** The `-ExecutionPolicy Bypass` flag allows running the script without changing system settings.

**Review the output** and note which components show:
- **[OK]** - Already installed and correct version, will skip
- **[UPDATE]** - Installed but newer version available
- **[MISSING]** - Not installed, will install
- **[WRONG]** - Wrong version installed, will install correct version
- **[WARN]** - Configuration issue that needs attention

### Step 3: Display Summary and Confirm

**Display the environment check results in a table format:**

```
| Component | Status | Notes |
|-----------|--------|-------|
| Git | ✅ OK | 2.x.x |
| PowerShell 7 | ❌ MISSING | Currently 5.1 |
| Java 17 | ❌ MISSING | Need to install |
| ... | ... | ... |
```

**If any components are missing**, tell the user:

> "Missing components were found. The following items need to be installed: [list items]. Would you like to proceed with the setup? (yes/no)"

**Wait for the user to confirm** before proceeding to Phase 1. Do NOT start installing anything until they say yes.

### Step 4: Show Setup Phases and Proceed

After the user confirms, display the progress tracker showing all phases:

```
## Setup Phases

⬜ Phase 1: Core Setup (PowerShell 7, Java, Git, SSH)
⬜ Phase 2: PostgreSQL
⬜ Phase 3: Repository Setup
⬜ Phase 4: Gradle Configuration
⬜ Phase 5: Initial Build
⬜ Phase 6: IntelliJ Setup
⬜ Phase 7: Running LabKey Server
⬜ Phase 8: Test Setup (optional)
⬜ Phase 9: Developer Tools (optional)
⬜ Phase 10: AI Tooling (optional)

Legend: ✅ = completed, 🔄 = in progress, ⬜ = pending
```

**Proceed with the phases**, skipping installation steps for components marked [OK] in the environment check.

---

## Phase 1: Core Setup (PowerShell 7, Java, Git, SSH)

**Install missing components identified by the environment check. Skip any marked [OK].**

### 1.1 Install PowerShell 7

> Skip if environment check showed PowerShell 7 as [OK]

```bash
powershell.exe -Command "winget install Microsoft.PowerShell --source winget --accept-source-agreements --accept-package-agreements"
```

### 1.2 Install Java

> Skip if environment check showed Java as [OK] with correct version

Install the JDK for the LabKey version selected in Getting Started (GUI installer - tell user to watch for UAC prompt):

```bash
# For LabKey 25.x - Java 17:
powershell.exe -Command "winget install EclipseAdoptium.Temurin.17.JDK --source winget --interactive --accept-source-agreements --accept-package-agreements"

# For LabKey 26.x - Java 25:
powershell.exe -Command "winget install EclipseAdoptium.Temurin.25.JDK --source winget --interactive --accept-source-agreements --accept-package-agreements"
```

**During installation:**
- **Enable "Set JAVA_HOME variable"** on the Custom Setup screen
- Enable "Add to PATH" option

### 1.3 Install Git

> Skip if environment check showed Git as [OK]

```bash
powershell.exe -Command "winget install Git.Git --source winget --accept-source-agreements --accept-package-agreements"
```

### 1.4 Restart Terminal (if PowerShell 7 or Java was installed)

**If PowerShell 7 or Java was installed, restart to pick up environment changes.**

**REQUIRED: Output a Resume Checkpoint block before the user restarts (see "Track progress before terminal restarts" in Important Notes).**

Guide the user:

1. **Close the terminal window completely** (Windows Terminal must restart to detect the newly installed PowerShell 7)

2. **Open a new terminal**

3. **Set PowerShell 7 as default terminal:**
   - Click the dropdown arrow in Windows Terminal → Settings (or press `Ctrl+,`)
   - Under "Default profile", select **"PowerShell"** (black icon, NOT "Windows PowerShell")
   - Click **Save**

4. **Close and reopen the terminal** (so it opens with PowerShell 7 as default)

5. **Resume this Claude Code session:**
   - Run `claude --resume` to continue where you left off

Once the user confirms they're back, verify:
```bash
pwsh --version
java -version
```

Expected: PowerShell 7.x.x and the Java version they installed

### 1.5 Configure Git Line Endings

> Skip if environment check showed Git core.autocrlf as [OK]

```bash
git config --global core.autocrlf true
git config --global pull.rebase false
```

Verify:
```bash
git config --global core.autocrlf
# Should output: true
```

### 1.6 SSH Key Setup

SSH keys enable non-interactive authentication with GitHub for Git operations.

> **What uses SSH keys:**
> - **Claude Code** - for `git push`, `git pull`, and other git operations without password prompts
> - **TortoiseGit** - for push/pull from Windows Explorer (when configured to use Git's SSH client)
> - **Command-line Git** - for any git operations with GitHub

**Step 1: Test if SSH is already working with GitHub:**
```bash
ssh -T git@github.com
```

- If this returns `Hi <username>! You've successfully authenticated...` → **Skip to section 1.8** (SSH is already configured)
- If this prompts for host key verification → User needs to type "yes" to accept GitHub's fingerprint, then check the result
- If this fails with "Permission denied" → Continue to Step 2

> **Why test first?** There may be existing SSH keys (id_rsa, id_ecdsa, or keys in non-standard locations) that already work. Testing first avoids unnecessary key generation.

**Step 2: If SSH test failed, check for existing key to add to GitHub:**
```bash
pwsh -Command "Test-Path ~/.ssh/id_ed25519.pub"
```

- If `True` → The key exists but isn't added to GitHub. Display the public key and have the user add it (see Step 4 below)
- If `False` → No ed25519 key exists, continue to Step 3 to generate one

**Step 3: Generate a new SSH key (if needed):**

Ask the user for their GitHub email address.

Then ask: **"Do you want a passphrase on your SSH key?"**
- **Yes** - More secure; you'll be prompted for it when using the key (or can use ssh-agent). User must run the command themselves to enter the passphrase securely.
- **No** - More convenient; no prompt when using the key. You can run the command directly.

**If user wants NO passphrase**, run this command yourself:
```bash
ssh-keygen -t ed25519 -C "their-github-email@example.com" -f ~/.ssh/id_ed25519 -N ""
```

**If user wants a passphrase**, have them run:
```bash
ssh-keygen -t ed25519 -C "their-github-email@example.com"
```
- Accept default location (`~/.ssh/id_ed25519`)
- Enter their desired passphrase

> **What is Ed25519?** A modern cryptographic algorithm for SSH keys. It's faster and more secure than older RSA keys, with shorter key lengths. Ed25519 is the recommended standard by GitHub and security experts.

**Step 4: Display the public key for the user to copy:**
```bash
pwsh -Command "Get-Content ~/.ssh/id_ed25519.pub"
```
**IMPORTANT:** You MUST output the actual key content (starts with `ssh-ed25519 AAAA...`) in your response so the user can copy it. Do not just say "Read 1 file" - show the key text.

Tell user: "Copy the key above and add it to GitHub at https://github.com/settings/keys"

**Wait for user to confirm** they've added the key before proceeding.

### 1.7 Test GitHub SSH Access

```bash
ssh -T git@github.com
```

Expected: "Hi username! You've successfully authenticated..."

If it fails with host key verification, the user needs to type "yes" to accept GitHub's fingerprint.

### 1.8 Configure Git Identity

After successful GitHub authentication, configure the Git identity for commits. **Ask the user for their GitHub username and email**, then run:

```bash
git config --global user.name "their-github-username"
git config --global user.email "their-github-email@example.com"
```

> **Tip:** The username shown in the SSH test output ("Hi username!") is their GitHub username.

> **Why is this required?** Git doesn't retrieve this from GitHub automatically. Git is distributed—commits are created locally before pushing, and every commit embeds author name and email in its metadata. Use the same email as your GitHub account so commits are linked to your profile.

### 1.9 GitHub Personal Access Token

> **What uses GIT_ACCESS_TOKEN:**
> - **LabKey's Gradle build** - for downloading dependencies and running commands like `gradlew gitCheckout`
> - **NOT used by:** Git command-line, TortoiseGit, or Claude Code (these use SSH keys)

1. Go to: https://github.com/settings/tokens
2. Click "Generate new token (classic)"
3. Give it a descriptive name (e.g., "LabKey Development")
4. Select scopes: `repo` (full control of private repositories)
5. Generate and copy the token

Set the environment variable:
```powershell
[System.Environment]::SetEnvironmentVariable('GIT_ACCESS_TOKEN', 'ghp_your_token_here', 'User')
```

Verify the token is set:
```bash
powershell.exe -Command "[System.Environment]::GetEnvironmentVariable('GIT_ACCESS_TOKEN', 'User')"
# Should show your token
```

---

## Phase 2: PostgreSQL Database

**Install the PostgreSQL version based on the LabKey choice from Step 1:**
- LabKey 25.7.x and lower → PostgreSQL 17 only
- LabKey 25.11.x → PostgreSQL 17 or 18 (either works)
- LabKey 26.x → PostgreSQL 18

### 2.1 Check for PostgreSQL

> **Existing mode**: Check if PostgreSQL is already installed.

```bash
pwsh -Command "Get-Service -Name 'postgresql*' -ErrorAction SilentlyContinue"
```

If not found, install the appropriate version based on your LabKey version from Step 1:

```bash
# For LabKey 25.7.x and lower - install PostgreSQL 17:
pwsh -Command "winget install PostgreSQL.PostgreSQL.17 --source winget --interactive --accept-source-agreements --accept-package-agreements"

# For LabKey 25.11.x - install PostgreSQL 18 (recommended) or 17:
pwsh -Command "winget install PostgreSQL.PostgreSQL.18 --source winget --interactive --accept-source-agreements --accept-package-agreements"
# OR
pwsh -Command "winget install PostgreSQL.PostgreSQL.17 --source winget --interactive --accept-source-agreements --accept-package-agreements"

# For LabKey 26.x - install PostgreSQL 18:
pwsh -Command "winget install PostgreSQL.PostgreSQL.18 --source winget --interactive --accept-source-agreements --accept-package-agreements"
```

**Option B: Download and launch installer**
```bash
# Ask user for version (e.g., "18.2-1"), then download and launch
pwsh -Command "\$version = '18.2-1'; \$url = \"https://get.enterprisedb.com/postgresql/postgresql-\$version-windows-x64.exe\"; \$installer = \"\$env:TEMP\\postgresql-installer.exe\"; Invoke-WebRequest -Uri \$url -OutFile \$installer; Start-Process \$installer -Wait"
```

**During installation:**
- Select all components (PostgreSQL Server, pgAdmin, Command Line Tools)
- **Set and remember the password** for the `postgres` user
- Port: **5432** (keep default unless there's a conflict)
- Locale: **Default locale** (keep default)
- **Uncheck "Launch Stack Builder"** at the end - Stack Builder downloads additional extensions (PostGIS, etc.) which are not required for LabKey development. It can be run later from the Start menu if needed.

### 2.2 Verify PostgreSQL Installation

```bash
# Check service is running
pwsh -Command "Get-Service -Name 'postgresql*'"

# Test connection (will prompt for password - tell user to enter their postgres password)
pwsh -Command "& 'C:\\Program Files\\PostgreSQL\\18\\bin\\psql.exe' -U postgres -c 'SELECT version();'"
```

> **Note:** The psql path includes the PostgreSQL version number (e.g., 18). Adjust if a different version was installed.

### 2.3 Using pgAdmin (Optional)

pgAdmin is a web-based GUI for managing PostgreSQL, installed with PostgreSQL.

**To launch:**
1. Open Start menu and search for "pgAdmin"
2. It opens in your default browser (may take a moment on first launch)
3. Set a master password when prompted (this is for pgAdmin, not PostgreSQL)

**To connect to your local server:**
1. In the left panel, expand "Servers"
2. Click "PostgreSQL" - enter your postgres password when prompted
3. You can now browse databases, run queries, and manage the server

> **Tip:** pgAdmin is useful for viewing LabKey's database tables, running SQL queries, and troubleshooting data issues.

### 2.4 Create Development Database (Optional)

You can create a dedicated database for LabKey development:

```powershell
psql -U postgres -c "CREATE DATABASE labkey;"
```

> **Note:** LabKey can also create databases automatically during first run if configured appropriately.

---

## Phase 3: Directory Structure and Repository Setup

### 3.1 Create Enlistment Directory

**First, check if an enlistment already exists at the default location:**

```bash
# Check if directory exists and contains a git repo with LabKey remote
pwsh -Command "Test-Path 'C:\\labkey\\labkeyEnlistment\\server\\build.gradle'"
```

If the path exists, verify it's the LabKey server repository:

```bash
cd /c/labkey/labkeyEnlistment/server && git remote -v
```

- If the remote shows `github.com/LabKey/server` (or similar LabKey URL) → An existing LabKey enlistment was found. Ask the user: "An existing LabKey enlistment was found at `C:\labkey\labkeyEnlistment`. Would you like to use this existing enlistment? (yes/no)" If yes, **skip to Phase 3.5 (Verify Repository Structure)**. If no, ask where they want to create a new one.
- If the remote shows a different repository → Warn the user that the directory contains a different project and ask for an alternative location.
- If the path doesn't exist → Continue with directory creation below.

**Ask the user where they want to create the LabKey enlistment directory:**

```
Where would you like to create the LabKey enlistment directory?

1. C:\labkey\labkeyEnlistment (recommended - short path, avoids path length issues)
2. Other location (please specify)

Enter 1 or 2:
```

If they choose 1, use `C:\labkey\labkeyEnlistment`. If they choose 2, ask them for the full path.

**Check if the directory already exists before creating:**

```bash
pwsh -Command "if (-not (Test-Path 'C:\\labkey\\labkeyEnlistment')) { New-Item -ItemType Directory -Path 'C:\\labkey\\labkeyEnlistment' -Force } else { Write-Host 'Directory already exists' }"
```

> **Note:** Shorter paths avoid potential Windows path length issues with deeply nested files.

### 3.2 Clone the Server Repository

```bash
cd /c/labkey/labkeyEnlistment && git clone https://github.com/LabKey/server.git .
```

> **Important:** The dot (`.`) at the end clones the repo contents directly into the current directory. Without it, Git creates a nested `server/server/modules` structure.

### 3.3 Clone Module Repositories

Clone all required modules into the `server/modules` directory:

```bash
cd /c/labkey/labkeyEnlistment/server/modules

# Platform modules (required)
git clone https://github.com/LabKey/platform.git

# Common assays (required for MacCoss Lab modules)
git clone https://github.com/LabKey/commonAssays.git

# TargetedMS / Panorama module (MacCoss Lab)
git clone https://github.com/LabKey/targetedms.git

# MacCoss Lab custom modules
git clone https://github.com/LabKey/MacCossLabModules.git
```

### 3.4 Clone Test Automation (Optional)

**Ask the user if they want to run automated tests.** If yes, clone testAutomation as a sibling to the modules directory:

```powershell
cd $enlistmentPath\server
git clone https://github.com/LabKey/testAutomation.git
```

### 3.5 Verify Repository Structure

```powershell
# Verify structure (replace $enlistmentPath with actual path)
Test-Path $enlistmentPath\server\build.gradle                  # Should be True
Test-Path $enlistmentPath\server\modules\platform              # Should be True
Test-Path $enlistmentPath\server\modules\commonAssays          # Should be True
Test-Path $enlistmentPath\server\modules\targetedms            # Should be True
Test-Path $enlistmentPath\server\modules\MacCossLabModules     # Should be True
Test-Path $enlistmentPath\server\testAutomation                # Should be True (if cloned)
```

### 3.6 Switch to Appropriate Branch (If Needed)

**Ask the user which branch they need to work on:**

```
Which branch do you need to work on?

1. develop (default - active development)
2. release25.11-SNAPSHOT (features staging before release)
3. release25.11 (stable release branch)
4. Other branch (please specify)

Enter 1, 2, 3, or 4:
```

If they choose `develop`, skip this section (that's the default). Otherwise, proceed with the branch switch.

> **Branch naming:** SNAPSHOT branches (e.g., `release25.11-SNAPSHOT`) are used for faster feature deployment before changes are merged to the stable release branch (e.g., `release25.11`).

**Step 1: Checkout each repository individually to the desired branch:**

```bash
cd /c/labkey/labkeyEnlistment/server && git checkout <branch-name>
cd /c/labkey/labkeyEnlistment/server/modules/platform && git checkout <branch-name>
cd /c/labkey/labkeyEnlistment/server/modules/commonAssays && git checkout <branch-name>
cd /c/labkey/labkeyEnlistment/server/modules/targetedms && git checkout <branch-name>
cd /c/labkey/labkeyEnlistment/server/modules/MacCossLabModules && git checkout <branch-name>

# If testAutomation was cloned
cd /c/labkey/labkeyEnlistment/server/testAutomation && git checkout <branch-name>
```

Replace `<branch-name>` with the actual branch name (e.g., `release25.11-SNAPSHOT`).

---

## Phase 4: Gradle Configuration

### 4.1 About Gradle Wrapper

LabKey uses the Gradle wrapper (`gradlew.bat` on Windows) which automatically downloads the correct Gradle version. **Do not install Gradle separately.**

Verify the wrapper exists:
```powershell
Test-Path $enlistmentPath\gradlew.bat  # Should be True
```

> **PowerShell vs Command Prompt:** The LabKey documentation shows `gradlew deployApp`, which works in Command Prompt (cmd). In PowerShell, you must prefix with `.\` to run executables in the current directory:
>
> | Shell | Command |
> |-------|---------|
> | Command Prompt (cmd) | `gradlew deployApp` |
> | PowerShell | `.\gradlew deployApp` |

### 4.2 Create Global Gradle Properties

**First, check if gradle.properties already exists:**

```powershell
Test-Path "$env:USERPROFILE\.gradle\gradle.properties"
```

- If `True` → Skip to "Verify Artifactory properties" below
- If `False` → Continue with creating the file

**Create the global Gradle properties file from the template:**

```powershell
# Check and create .gradle directory if needed
if (-not (Test-Path "$env:USERPROFILE\.gradle")) {
    New-Item -ItemType Directory -Path "$env:USERPROFILE\.gradle" -Force
}

# Copy template (if it exists)
$templatePath = "$enlistmentPath\gradle\global_gradle.properties_template"
$targetPath = "$env:USERPROFILE\.gradle\gradle.properties"

if (Test-Path $templatePath) {
    Copy-Item $templatePath $targetPath
    Write-Host "Copied template to $targetPath"
} else {
    Write-Host "Template not found at $templatePath - creating minimal file"
}
```

**Verify the file was copied:**
```powershell
Test-Path "$env:USERPROFILE\.gradle\gradle.properties"  # Should be True
```

**Important:** After copying the template, uncomment and set the Artifactory properties (even if empty):

```powershell
notepad "$env:USERPROFILE\.gradle\gradle.properties"
```

Find these lines and uncomment them:
```properties
artifactory_user=
artifactory_password=
```

> **Why?** The Gradle build requires these properties to be *defined*, even if empty. Empty values work for public modules (anonymous Artifactory access). Valid credentials are only needed for premium/private modules or publishing artifacts.

Edit `~/.gradle/gradle.properties` and configure:
- Set `systemProp.labkey.server=<build directory>` if you want builds outside the enlistment
- Configure any proxy settings if behind a corporate firewall

### 4.3 Configure Database Connection

**Ask the user for their PostgreSQL password** (the one they set during PostgreSQL installation).

Read the existing `pg.properties` file and update the password:

```powershell
# Path to pg.properties
$pgPropertiesPath = "$enlistmentPath\server\configs\pg.properties"
```

The file should contain these settings (update `jdbcPassword` with the user's password):
```properties
jdbcURL=jdbc:postgresql://localhost/labkey
jdbcUser=postgres
jdbcPassword=<user-provided-password>
```

Use the Edit tool to update the `jdbcPassword` line with the user's actual password.

Then run the Gradle task to copy settings:
```bash
pwsh -Command "cd $enlistmentPath; .\\gradlew pickPg"
```

> **Note:** The `gradlew.bat` file is at the enlistment root (where you cloned the server repository), not in the `server` subdirectory.

> **Note:** MacCossLabModules only support PostgreSQL, not MSSQL.

---

## Phase 5: Initial Build

> **Note:** You do not need to install Tomcat or IntelliJ IDEA before building. LabKey uses an **embedded Tomcat** server (included in the build), and Gradle handles the build from the command line. IntelliJ is installed in Phase 6 for development convenience.

### 5.1 Run the Build

**Important:** The first build takes 15-30+ minutes as it downloads dependencies.

**To minimize token usage:** Have the user run the build in a separate terminal so they can watch the output. Tell them:

> "Please open a new PowerShell window and run:
> ```powershell
> cd $enlistmentPath
> .\gradlew deployApp
> ```
> Watch for 'BUILD SUCCESSFUL' at the end. Let me know when it completes."

Replace `$enlistmentPath` with the actual path the user chose (e.g., `C:\labkey\labkeyEnlistment`).

Wait for the user to confirm the build is done before proceeding.

### 5.2 Verify Build Success and Check IntelliJ

After the build completes, verify the build artifacts AND check if IntelliJ is installed:

```bash
# Check if IntelliJ is installed
pwsh -Command "Get-ChildItem 'C:\Program Files\JetBrains' -Directory -ErrorAction SilentlyContinue | Select-Object Name"
```

If IntelliJ is not installed, proceed immediately to **Phase 6: IntelliJ IDEA Setup** before continuing with artifact verification. The user will need IntelliJ to run the server.

**Verify build artifacts:**
```powershell
# Check for embedded server jar (version number may vary)
Get-ChildItem $enlistmentPath\build\deploy\embedded\*.jar

# Check for targetedms module (version number may vary)
Get-ChildItem $enlistmentPath\build\deploy\modules\*targetedms*

# Check for MacCoss Lab modules
Get-ChildItem $enlistmentPath\build\deploy\modules\*MacCoss*
```

### 5.3 Common Build Issues

**Dependency download failures:**
- Check internet connection
- Verify `GIT_ACCESS_TOKEN` is set correctly
- Check if behind a proxy (configure in gradle.properties)

**Java version errors:**
- Verify `JAVA_HOME` points to correct JDK
- Ensure JDK version matches LabKey requirements

**Out of memory:**
- Edit `~/.gradle/gradle.properties` and add:
  ```properties
  org.gradle.jvmargs=-Xmx4g
  ```

---

## Phase 6: IntelliJ IDEA Setup

### 6.1 Install IntelliJ IDEA

Check if IntelliJ is already installed:
```bash
pwsh -Command "Get-ChildItem 'C:\\Program Files\\JetBrains' -Directory -ErrorAction SilentlyContinue | Select-Object Name"
```

If not found, ask the user which edition they want:

```
Which IntelliJ IDEA edition do you want to install?

1. Community Edition (free, sufficient for LabKey development)
2. Ultimate Edition (paid, additional features for web/enterprise development)

Enter 1 or 2:
```

Install the selected edition:
```bash
# For Community Edition (option 1):
pwsh -Command "winget install JetBrains.IntelliJIDEA.Community --source winget --accept-source-agreements --accept-package-agreements"

# For Ultimate Edition (option 2):
pwsh -Command "winget install JetBrains.IntelliJIDEA.Ultimate --source winget --accept-source-agreements --accept-package-agreements"
```

### 6.2 Run IntelliJ Configuration Tasks

Before opening in IntelliJ, run the setup tasks:

```bash
pwsh -Command "cd $enlistmentPath; .\\gradlew ijWorkspaceSetup"
```

```bash
pwsh -Command "cd $enlistmentPath; .\\gradlew ijConfigure"
```

### 6.3 Open Project in IntelliJ

Tell the user to launch IntelliJ and open the project:

> "Please launch IntelliJ IDEA from the Start menu, then:
> 1. On the Welcome screen, click **Open** (or if already in a project: File > Open)
> 2. Navigate to: `C:\labkey\labkeyEnlistment\server`
> 3. Click **OK**
> 4. On the Trust dialog:
>    - Check **'Trust all projects in the labkey folder'** (convenient for future projects)
>    - Re-check **'Add to Microsoft Defender exclusion list'** (it gets unchecked - check it again for build performance)
>    - Click **Trust 'labkey' Folder**
> 5. Wait for IntelliJ to finish indexing (progress bar in the status bar at bottom)
>
> **While indexing, you can ignore these messages:**
> - "Invalid Gradle JDK configuration found" in the console - we'll configure the JDK next
> - "NODE_PATH undefined" pop-up - not needed for LabKey development
> - "Configure Kotlin language settings" - dismiss or ignore
>
> Let me know when IntelliJ is ready."

Wait for the user to confirm before proceeding to JDK configuration.

### 6.4 Configure JDK in IntelliJ

The run configuration expects a JDK named **"labkey"**. Create and assign it:

1. **File > Project Structure** (Ctrl+Alt+Shift+S)
2. Select **SDKs** in the left panel
3. Click **+** → **Add JDK**
4. Browse to your JDK (e.g., `C:\Program Files\Eclipse Adoptium\jdk-25...`)
5. **Rename it to "labkey"** (click the name to edit)
6. Now select **Project** in the left panel
7. Set the **SDK** dropdown to **"labkey"**
8. Click **OK**

> **Important:** You must both create the SDK named "labkey" AND assign it as the Project SDK. The run configuration won't find it otherwise.

### 6.5 Refresh Gradle Project

After setting the Project SDK, refresh the Gradle project to sync the run configurations:

1. Open the Gradle tool window (View > Tool Windows > Gradle)
2. Click the refresh button (circular arrow icon)
3. Wait for Gradle sync to complete

> **Note:** The run configuration ("LabKey Embedded Tomcat Dev") should automatically configure correctly after the Gradle refresh. Manual configuration is typically not needed.

---

## Phase 7: Running LabKey Server

### 7.1 Start the Server

Tell the user:
1. In IntelliJ, select the "LabKey Embedded Tomcat Dev" run configuration
2. Click the Run button (green play icon) or Debug button (bug icon)
3. **Windows Security prompt:** If you see "Do you want to allow public and private network access to this app?" for OpenJDK Platform binary, click **Allow** (the server needs to accept connections on port 8080)
4. Wait for the server to start (watch the console output for module initialization)
5. The server is ready when you can access http://localhost:8080/ in a browser

> **Note:** There may not be an explicit "Server started" message. Log warnings about missing schema metadata or skipped foreign keys are normal during module initialization.

### 7.2 Access LabKey Server

Once the server is running:
1. Open a browser to: http://localhost:8080/
2. Follow the initial setup wizard if this is a fresh installation
3. Create an admin account when prompted

### 7.3 Verify Module Deployment

After logging in:
1. Go to Admin > Site > Admin Console
2. Click on "Module Information"
3. Verify these modules are listed:
   - targetedms
   - MacCossLabModules (SkylineToolsStore, signup, testresults, etc.)

---

## Phase 8: Test Setup (Optional)

If the user cloned `testAutomation` in Phase 3, configure the test environment.

> **Reference:** [LabKey Running Tests Documentation](https://www.labkey.org/Documentation/wiki-page.view?name=runningTests)

### 8.1 Configure Test Credentials

This command requires interactive input, so have the user run it themselves:

> "Please open a PowerShell window and run:
> ```powershell
> cd $enlistmentPath
> .\gradlew :server:test:setPassword
> ```
> When prompted, enter the same username and password you created during LabKey setup.
> Let me know when it's done."

Replace `$enlistmentPath` with the actual path the user chose.

Wait for the user to confirm before proceeding.

> **Why separate credentials?** The admin account you created is stored in the database. The `setPassword` command appends credentials to your `.netrc` file so automated Selenium tests can authenticate to the test server programmatically.

### 8.2 Browser Setup

LabKey tests use Selenium with Firefox or Chrome. **Ask the user which browser they prefer.**

**Option A: Firefox ESR (recommended by LabKey for stability)**
```bash
pwsh -Command "winget install Mozilla.Firefox.ESR --source winget --accept-source-agreements --accept-package-agreements"
```
The default `test.properties` is already configured for Firefox (`selenium.browser=firefox`).

**Option B: Chrome**

If the user prefers Chrome, first check if it's installed:
```bash
pwsh -Command "Test-Path 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe'"
```

If not installed:
```bash
pwsh -Command "winget install Google.Chrome --source winget --accept-source-agreements --accept-package-agreements"
```

Then edit the test properties file to change the browser setting:
```powershell
notepad $enlistmentPath\server\testAutomation\test.properties
```
Find and change:
```properties
selenium.browser=chrome
```

### 8.3 Configure Test Properties (Optional)

Review the test properties file if needed:

```powershell
notepad $enlistmentPath\server\testAutomation\test.properties
```

Key settings:
```properties
selenium.browser=firefox
# Or for Chrome:
# selenium.browser=chrome
```

### 8.4 Running Tests

**Display test runner GUI:**
```powershell
.\gradlew :server:test:uiTests
```

**Run specific test class:**
```powershell
.\gradlew :server:test:uiTests "-Ptest=BasicTest"
```

Expected output on success:
```
INFO  Runner : =============== Completed BasicTest (1 of 1) =================
INFO  Runner : ======================= Time Report ========================
INFO  Runner : BasicTest                                 passed - 0:16 100%
INFO  Runner : ------------------------------------------------------------
INFO  Runner : Total duration:                                         0:16
```

**Run test suite (e.g., DRT - Daily Regression Tests):**
```powershell
.\gradlew :server:test:uiTests "-Psuite=DRT"
```

**Run module-specific tests:**
```powershell
.\gradlew -PenableUiTests :server:modules:targetedms:moduleUiTests
```

**Run module test suites:**

Many modules define a test suite that can be run using the suite parameter. The MacCoss Lab modules with test suites:
```powershell
# TargetedMS / Panorama tests
.\gradlew :server:test:uiTests "-Psuite=targetedms"

# Panorama Public tests
.\gradlew :server:test:uiTests "-Psuite=panoramapublic"
```

### 8.5 Run Tests

Ask the user which tests they want to run:

```
Which tests would you like to run? (LabKey Server must be running in IntelliJ)

1. BasicTest (~1-2 min) - Quick smoke test to verify setup (recommended)
2. DRT suite (~15-30 min) - Core LabKey functionality
3. TargetedMS tests (~30+ min) - Panorama module tests
4. Panorama Public tests (~30+ min) - Panorama Public module tests
5. Skip - I'll run tests later

Enter 1, 2, 3, 4, or 5:
```

Based on their choice, tell them to run the command in a PowerShell window:

| Choice | Command |
|--------|---------|
| 1. BasicTest | `.\gradlew :server:test:uiTests "-Ptest=BasicTest"` |
| 2. DRT | `.\gradlew :server:test:uiTests "-Psuite=DRT"` |
| 3. TargetedMS | `.\gradlew :server:test:uiTests "-Psuite=targetedms"` |
| 4. Panorama Public | `.\gradlew :server:test:uiTests "-Psuite=panoramapublic"` |

Tell the user:
> "Please open a PowerShell window and run:
> ```powershell
> cd $enlistmentPath
> <command from table above>
> ```
> Let me know when it completes."

Replace `$enlistmentPath` with the actual path the user chose.

For BasicTest, expected success output:
```
INFO  Runner : =============== Completed BasicTest (1 of 1) =================
INFO  Runner : BasicTest                                 passed
```

### 8.6 IntelliJ Test Configuration

For running tests from IntelliJ:
1. Go to **File > Settings > Build, Execution, Deployment > Build Tools > Gradle**
2. Set **"Run tests using"** to **"IntelliJ IDEA"**

> **More information:** See [LabKey Running Tests Documentation](https://www.labkey.org/Documentation/wiki-page.view?name=runningTests) for additional test options, debugging, and troubleshooting.

---

## Phase 9: Additional Developer Tools (Optional)

**Check which tools are already installed before offering to install:**

```powershell
# Notepad++
Test-Path 'C:\Program Files\Notepad++\notepad++.exe'

# WinMerge (check both install locations)
(Test-Path 'C:\Program Files\WinMerge\WinMergeU.exe') -or (Test-Path "$env:LOCALAPPDATA\Programs\WinMerge\WinMergeU.exe")

# TortoiseGit
Test-Path 'C:\Program Files\TortoiseGit\bin\TortoiseGitProc.exe'
```

Skip installation for any tool that returns `True`.

### 9.1 Notepad++

Lightweight text editor with syntax highlighting:

```powershell
# Check first
if (-not (Test-Path 'C:\Program Files\Notepad++\notepad++.exe')) {
    winget install Notepad++.Notepad++ --source winget --accept-source-agreements --accept-package-agreements
}
```

### 9.2 WinMerge

File and folder comparison tool, useful for diffs:

```powershell
# Check first
if (-not ((Test-Path 'C:\Program Files\WinMerge\WinMergeU.exe') -or (Test-Path "$env:LOCALAPPDATA\Programs\WinMerge\WinMergeU.exe"))) {
    winget install WinMerge.WinMerge --source winget --accept-source-agreements --accept-package-agreements
}
```

**Configure as TortoiseGit diff tool:**

TortoiseGit usually auto-detects WinMerge after installation. To verify or configure manually:
1. Right-click → **TortoiseGit** → **Settings**
2. Go to **Diff Viewer** in the left panel
3. Verify WinMerge is selected (or select **External** and browse to `C:\Program Files\WinMerge\WinMergeU.exe`)
4. Go to **Merge Tool** and verify WinMerge is selected there as well
5. Click **OK**

### 9.3 TortoiseGit

**What it is:** A Windows Explorer extension that adds Git features directly to File Explorer:
- **Right-click menus** - Commit, Push, Pull, Diff, Log, Blame, etc. without opening a terminal
- **Icon overlays** - Visual badges on files/folders showing Git status (✓ committed, ! modified, + added)

**Who needs it:** Developers who prefer visual Git tools over command line. Skip if you use IntelliJ's built-in Git or command line exclusively.

```powershell
# Check first
if (-not (Test-Path 'C:\Program Files\TortoiseGit\bin\TortoiseGitProc.exe')) {
    winget install TortoiseGit.TortoiseGit --source winget --accept-source-agreements --accept-package-agreements
}
```

**Configure SSH client** (important):
1. Right-click on `$enlistmentPath` → **Show more options** → **TortoiseGit** → **Settings**
2. Select **Network** in the left panel
3. Set **SSH client** to: `C:\Program Files\Git\usr\bin\ssh.exe`
4. Click **OK**

> **Why?** TortoiseGit by default uses PuTTY's SSH client which expects keys in `.ppk` format. We set up SSH keys using OpenSSH (`id_ed25519`). By pointing TortoiseGit to Git's SSH client, it uses the same keys you already configured for GitHub. Without this, TortoiseGit push/pull will fail authentication.

> **Windows 11 tip:** The context menu shows limited TortoiseGit options by default. To add more options: Right-click → **TortoiseGit** → **Settings** → **General** → **Windows 11 Context Menu** and select the commands you want visible.

---

## Phase 10: AI Tooling (For Claude Code)

These tools support AI-assisted development workflows with Claude Code.

### 10.1 GitHub CLI

Required for Claude Code to create pull requests, manage issues, and interact with GitHub:

```powershell
# Check if installed
gh --version

# Install if missing
winget install GitHub.cli --source winget --accept-source-agreements --accept-package-agreements
```

**Restart the terminal** after installation to update PATH.

Then authenticate:
```powershell
gh auth status    # Check if already authenticated
gh auth login     # If not authenticated
```

### 10.2 Claude Code

> **Prerequisite:** Git must be installed first (Claude Code requires Git Bash on Windows).

**Install Claude Code:**
```powershell
irm https://claude.ai/install.ps1 | iex
```

**Add Claude to PATH permanently:**
```powershell
$claudePath = "$env:USERPROFILE\.local\bin"
[Environment]::SetEnvironmentVariable("Path", [Environment]::GetEnvironmentVariable("Path", "User") + ";$claudePath", "User")
```

**Restart the terminal**, then verify and authenticate:
```powershell
claude --version
claude  # Launch and follow authentication prompts
```

---

## Commonly Used Gradle Commands

Reference these commands for daily development:

| Command | Description |
|---------|-------------|
| `.\gradlew pickPg` | Copy PostgreSQL settings to application.properties |
| `.\gradlew deployApp` | Full development build |
| `.\gradlew deployApp -PdeployMode=prod` | Production build (run `cleanBuild` first) |
| `.\gradlew cleanBuild` | Clean all build artifacts |
| `.\gradlew :server:modules:targetedms:deployModule` | Build and deploy targetedms module only |
| `.\gradlew :server:modules:MacCossLabModules:testresults:deployModule` | Build and deploy testresults module |
| `.\gradlew :server:modules:targetedms:clean` | Clean targetedms module |
| `.\gradlew :server:test:uiTest` | Run Selenium test suites |

> **Note:** For production deployments of Panorama and Skyline-specific builds, use the builds generated on TeamCity rather than local production builds.

---

## MacCoss Lab Module Reference

### Modules in MacCossLabModules Repository

**Deployed on skyline.ms:**
- **SkylineToolsStore** - Skyline External Tool Store management
- **signup** - Custom user self sign-up for skyline.ms
- **testresults** - Skyline nightly test statistics

**Deployed on panoramaweb.org:**
- **targetedms** - Panorama module (main repository)
- **panoramapublic** - Panorama Public functionality
- **pwebdashboard** - Dashboard charts and queries
- **lincs** - LINCS project features

### CPTAC Assay Portal Module (External)

Separate repository for the CPTAC Assay Portal:
- Repository: https://github.com/CPTAC/panorama.git
- Managed by CPTAC developers
- Includes custom SQL scripts, queries, and R Scripts

---

## Troubleshooting

### Gradle Daemon Issues

If builds fail with daemon errors:
```powershell
.\gradlew --stop
.\gradlew deployApp
```

### Port Already in Use

If port 8080 is in use:
1. Find the process: `netstat -ano | findstr :8080`
2. Kill the process or configure LabKey to use a different port

### IntelliJ Not Recognizing Modules

If IntelliJ doesn't see all modules:
1. Refresh Gradle project (Gradle tool window > Refresh)
2. File > Invalidate Caches > Invalidate and Restart

### Database Connection Failures

If LabKey can't connect to PostgreSQL:
1. Verify PostgreSQL service is running
2. Check credentials in `pg.properties`
3. Run `.\gradlew pickPg` again
4. Verify firewall isn't blocking port 5432

### Memory Issues During Build

Add to `~/.gradle/gradle.properties`:
```properties
org.gradle.jvmargs=-Xmx4g -XX:MaxMetaspaceSize=512m
```

---

## Final Report

**Before declaring setup complete, you MUST produce a comprehensive final report.**

The report should be:
1. Written to a markdown file (e.g., `labkey-setup-report-<date>.md`)
2. Displayed to the user in a summary format

### Report Requirements

The report must cover EVERY item in this document, organized by phase:

| Status | Meaning |
|--------|---------|
| DONE | Completed and verified |
| SKIPPED | Not offered or intentionally bypassed by assistant |
| DEFERRED | User chose to skip, should return to later |
| NOT VERIFIED | Completed but verification step was missed |

**Include these sections:**
- Phase-by-phase breakdown with status for each step
- List of deferred items (things the user may want to return to)
- Any issues encountered during setup
- Process notes (what went well, what could be improved)

---

## Success Criteria

The setup is complete when:
1. `java -version` shows the correct JDK version
2. `$env:JAVA_HOME` is set correctly
3. PostgreSQL is running and accessible
4. All required repositories are cloned with correct structure
5. `.\gradlew deployApp` completes successfully
6. IntelliJ can open the project and resolve dependencies
7. LabKey Server starts and is accessible at http://localhost:8080/
8. MacCoss Lab modules are visible in the Module Information page

Congratulate the user and let them know they're ready to develop LabKey Server modules!

---

## Additional Resources

- [LabKey Developer Documentation](https://www.labkey.org/Documentation/wiki-page.view?name=devMachine)
- [Build LabKey from Source](https://www.labkey.org/Documentation/wiki-page.view?name=buildLabKey)
- [Gradle Cleaning](https://www.labkey.org/Documentation/wiki-page.view?name=gradleClean)
- [Production Builds](https://www.labkey.org/Documentation/wiki-page.view?name=productionBuilds)
- [MacCoss Lab Build and Deploy Notes](https://skyline.ms/home/development/wiki-page.view?name=build_and_deploy)
