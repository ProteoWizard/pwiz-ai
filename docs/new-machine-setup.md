<!--
  New Machine Setup Guide for LLM Assistants
  ===========================================
  This document is designed to be fetched and followed by Claude Code or similar
  LLM assistants. It guides setup of a pristine Windows machine for Skyline development.

  Target audience: LLM assistants helping a human set up their development environment.
  Human-readable version: https://skyline.ms/wiki-page.view?name=HowToBuildSkylineTip

  FETCHED FROM: https://raw.githubusercontent.com/ProteoWizard/pwiz-ai/master/docs/new-machine-setup.md

  IMPORTANT: This document must be downloaded with curl (Bash tool), not WebFetch.
  WebFetch processes content through a summarization model and returns a summary
  instead of the full document, which loses critical details like exact commands.

  Changes committed to this file are immediately available to new setup sessions.
-->

# Skyline Development Environment Setup

You are helping a developer set up a Windows machine for Skyline development. Follow these phases in order, verifying each step before proceeding.

## Important Notes for the LLM Assistant

- **Complete ALL phases**: Do not declare success until you have worked through every phase in this document. Phases marked "optional" should still be offered to the user.
- **Ask before installing**: Always confirm with the user before running installers
- **Verify each step**: Run verification commands to confirm success before moving on
- **Guide GUI steps**: For Visual Studio and other GUI installers, tell the user exactly what to click
- **Track progress**: Keep the user informed of what's done and what's next
- **Final report required**: At the end, produce a comprehensive report covering ALL items (completed, skipped, and deferred). See "Final Report" section at the end of this document.
- **Track improvements**: Keep notes on any issues, corrections, or friction points encountered during setup. After the final report, you will update this document with improvements.

---

## How This Guide Improves

**For the developer:** As we work through this guide, simply mention any issues or confusion you encounter - things like unclear instructions, missing steps, commands that didn't work as expected, or anything that caused friction.

You don't need to do anything special to record these. I'll take notes as we go and update the documentation at the end of the session. This is how the guide stays current: each setup session makes it a little better for the next person.

---

## Determine Setup Mode

**Before starting, ask the developer which scenario applies:**

> "What type of machine are we setting up?
> 1. **Pristine machine** - Just completed new-machine-bootstrap.md (Git and Claude Code installed)
> 2. **Existing development machine** - Already has Visual Studio, build environment, and other tools"

**Based on their answer:**

- **Pristine mode**: The developer followed `new-machine-bootstrap.md`, so Git and Claude Code are already installed and working. Proceed through each phase without checking for existing installations—install commands will run directly. Start at Phase 1.1 (Node.js).

- **Existing mode**: The machine has a working Skyline development environment (via HowToBuildSkylineTip or prior setup).

  > **For LLM assistants — CRITICAL: Clone pwiz-ai FIRST.**
  > The `ai/` repository is your highest priority. It provides:
  > - `Verify-Environment.ps1` — comprehensive status check for all prerequisites
  > - `CLAUDE.md`, `CRITICAL-RULES.md`, `MEMORY.md` — full project context for Claude Code
  > - `.claude/` junction target — skills, commands, and settings
  > - Build and test scripts, MCP servers, and all AI tooling
  >
  > **Without `ai/`, you have none of these tools** and will waste time checking components individually. Jump to Phase 1.10 first to clone pwiz-ai and set up the junction. Then come back here to run the verification script.
  >
  > Do NOT fall back to checking tools one by one. Clone `ai/` first.

  **Once `ai/` is cloned**, run the verification script to get a comprehensive status report:

  ```powershell
  pwsh -Command "& './ai/scripts/Verify-Environment.ps1'"
  ```

  This script checks all prerequisites and reports what's OK, missing, or needs attention. Use the output to:
  - Skip phases where all components show OK
  - Focus on phases with MISSING or ERROR items
  - Note WARN items that may need user decision

  > **For LLM assistants:** The verification script is your primary tool for existing machines. Share the summary with the user, then propose which phases to work through based on the results. This is much faster than checking each component individually.
  >
  > **Actively offer optional items:** Items showing `[INFO]` status are optional but should still be explicitly offered to the user with a brief explanation of what they're for. Don't just list them as "not required"—ask if the user wants to install them. For example:
  > - **Pillow** (Python package): Enables clipboard image capture in StatusMcp. Critical on Windows 10 where screenshots aren't auto-saved. Less necessary on Windows 11 which saves Win+Shift+S screenshots to `~/Pictures/Screenshots`, but still useful for capturing images from other sources.
  > - **dotMemory/dotTrace**: JetBrains profiling tools for investigating memory leaks and performance issues.
  >
  > Present these as choices, not afterthoughts.

Record their choice and reference it throughout setup.

---

## Phase 1: Prerequisites

### 1.1 Check for Node.js

Node.js provides npm, used for installing Claude Code and other development tools.

```powershell
node --version
npm --version
```

If not found, install Node.js LTS:
```powershell
winget install OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements
```

After installation, **restart the terminal** (type `exit`, then <kbd>Win</kbd>+<kbd>X</kbd>, <kbd>I</kbd>) to get node/npm in PATH.

### 1.2 Check for Git

> **Pristine mode**: Skip this step—Git was installed during new-machine-bootstrap.md.

```powershell
git --version
```

If not found, install Git for Windows:
```powershell
winget install Git.Git --accept-source-agreements --accept-package-agreements
```

After installation, **restart the terminal** (type `exit`, then <kbd>Win</kbd>+<kbd>X</kbd>, <kbd>I</kbd>) to get git in PATH.

### 1.3 PowerShell 7

PowerShell 7 (`pwsh`) is required for build scripts and AI tooling. Windows PowerShell 5.1 is not sufficient.

```powershell
pwsh --version
```

If not found or version is below 7.0, install:
```powershell
winget install Microsoft.PowerShell --accept-source-agreements --accept-package-agreements
```

> **For LLM assistants:** After installing PowerShell 7, you MUST guide the user through configuring Windows Terminal to use it as the default. Do not skip these steps - they are required, not optional.

**Configure Windows Terminal to use PowerShell 7 as default:**

1. **Exit and restart Terminal** (close the window completely, then reopen)
2. Click the **dropdown arrow (∨)** next to the tab bar → **Settings**
3. Under "Startup", change **Default profile** to **PowerShell** (the PowerShell 7 profile, not "Windows PowerShell")
4. Click **Save**
5. Close and reopen Terminal

The new terminal should show PowerShell 7 as the default:
```
PowerShell 7.5.0
PS C:\Users\username>
```

**Wait for the user to confirm** they see the PowerShell 7 prompt before proceeding.

### 1.4 Python

Python is required for AI tooling (MCP servers, LabKey integration).

```powershell
python --version
```

If not found, install Python 3.12:
```powershell
winget install Python.Python.3.12 --accept-source-agreements --accept-package-agreements
```

After installation, **restart the terminal** (type `exit`, then <kbd>Win</kbd>+<kbd>X</kbd>, <kbd>I</kbd>) and verify `python --version` works.

### 1.5 Configure Git Line Endings

```powershell
git config --global core.autocrlf true
git config --global pull.rebase false
```

Verify:
```powershell
git config --global core.autocrlf
# Should output: true

git config --global pull.rebase
# Should output: false
```

### 1.6 SSH Key Setup

Check for existing SSH key:
```powershell
Test-Path ~/.ssh/id_rsa.pub
# or
Test-Path ~/.ssh/id_ed25519.pub
```

If no key exists, guide the user:
1. Generate a key: `ssh-keygen -t ed25519 -C "their-email@example.com"`
2. Accept default location, set a passphrase
3. Display the public key: `Get-Content ~/.ssh/id_ed25519.pub`
4. Tell user: "Copy this key and add it to GitHub at https://github.com/settings/keys"
5. **Wait for user to confirm** they've added the key before proceeding

### 1.7 Test GitHub SSH Access

```powershell
ssh -T git@github.com
```

Expected: "Hi username! You've successfully authenticated..."

If it fails with host key verification, the user needs to type "yes" to accept GitHub's fingerprint.

### 1.8 Configure Git Identity

After successful GitHub authentication, configure the Git identity for commits. Ask the user for their GitHub username and email, then run:

```powershell
git config --global user.name "their-github-username"
git config --global user.email "their-email@example.com"
```

> **Tip:** The username shown in the SSH test output ("Hi username!") is their GitHub username.

### 1.9 Choose Project Location

**Ask the developer where they want to put their development folder.**

Examples below use `C:\proj` as the project root. This is just an example -- any short path works. If the developer prefers a different location (e.g., `C:\Dev`, `D:\proj`, `E:\repos`), substitute it throughout. Record their choice and use it consistently.

**Why short paths are recommended:**

| Factor | `C:\proj` | `C:\Users\brendanx\Documents\projects` |
|--------|-----------|----------------------------------------|
| Path length | 6 chars | 40 chars |
| Windows indexing | Not indexed | Indexed by default |
| OneDrive sync | Not synced | May be synced |

**Non-C: drives are fine.** Examples: `D:\proj`, `E:\projects`, `E:\repos`. On many machines, C: is SSD and D:/E: are HDD - developing from an HDD works fine. The nightly test machines run 9-12 hours of stress testing from HDD drives without issues.

**Path length matters** because some build tools and tests create deeply nested temporary paths. Windows has a 260-character path limit that can be exceeded with long root paths.

**Spaces in usernames** (e.g., `C:\Users\Kaipo Tamura\...`) can break scripts that don't properly quote arguments. If the username contains spaces, a short root path like `C:\proj` or `D:\proj` avoids this entirely.

**Windows indexing** is important for nightly testing. Windows Search indexes `Documents` by default, and this indexing competes with nightly tests for disk I/O. If the developer chooses a location under `Documents`, they must add an exclusion:
1. Open **Indexing Options** (search for it in Start menu)
2. Click **Modify**
3. Uncheck the project folder or add it to excluded locations

**OneDrive sync** can cause issues with large repositories and build artifacts. Ensure the project folder is not in a OneDrive-synced location.

> **For LLM assistants:** If the developer chooses a different project root, note this in the final report. Remind them to substitute their chosen path wherever the guide shows example paths.

### 1.10 Clone the Repositories

> **Existing mode**: Check what's already present before cloning (substitute your project root):
> ```powershell
> Test-Path ai\.git           # pwiz-ai already cloned?
> Test-Path pwiz\.git         # pwiz already cloned?
> Test-Path .claude           # .claude junction exists?
> ```
> Skip any steps for components that already exist.

```powershell
# Create project directory (if needed) - substitute your preferred location
New-Item -ItemType Directory -Path C:\proj -Force
cd C:\proj

# Clone the AI tooling repository
git clone git@github.com:ProteoWizard/pwiz-ai.git ai

# Create .claude junction (enables Claude Code commands and skills)
cmd /c mklink /J .claude ai\claude

# Create CLAUDE.md stub (tells Claude Code where to find documentation)
@"
# Claude Code Configuration

**Run Claude Code from this directory** (your project root).

All Claude Code documentation lives in the **ai/** folder. See:
- **ai/CLAUDE.md** - Critical configuration (PowerShell, paths, commands)
- **ai/CRITICAL-RULES.md** - Absolute constraints
- **ai/MEMORY.md** - Project context and gotchas

The ``.claude/`` folder is a junction to ``ai/claude/``, providing access to
commands, skills, and settings.
"@ | Out-File -FilePath CLAUDE.md -Encoding utf8

# Copy default Claude settings (pre-approved read operations)
# NOTE: settings-defaults.local.json must NOT contain $schema or $comment fields.
# Claude Code validates settings files and rejects unrecognized top-level keys,
# causing the entire file to be skipped with a "Settings Error".
Copy-Item ai\claude\settings-defaults.local.json ai\claude\settings.local.json

# Clone pwiz
git clone git@github.com:ProteoWizard/pwiz.git
```

The pwiz clone takes several minutes (large repository). Verify:
```powershell
Test-Path CLAUDE.md                              # Should be True (stub)
Test-Path ai\CLAUDE.md                           # Should be True (full docs)
Test-Path .claude\commands                       # Should be True
Test-Path pwiz\pwiz_tools\Skyline\Skyline.sln   # Should be True
```

> **For LLM assistants:** Now that the repositories are cloned, the master copy of this setup guide is available locally at `ai\docs\new-machine-setup.md`. If you fetched this document from the web, you can now reference and even edit the local copy for improvements.

### 1.11 Restart Claude Code

The `.claude` junction now points to project configuration (CLAUDE.md, skills, commands). Restart Claude Code to load this context:

1. Run `/exit` in Claude Code
2. In the terminal, run: `claude --continue`

This resumes the same conversation but with full project context loaded. You should see a `<system-reminder>` with the contents of `CLAUDE.md` after your next tool use.

> **For LLM assistants:** After the restart, you will have access to project-specific skills and commands. The setup continues from where you left off.

### 1.12 Configure Claude Code Statusline (Recommended)

**For LLM assistants:** You MUST offer to configure the statusline. Do not skip this step silently. Ask: "Would you like me to configure the Claude Code statusline? It shows the current project, git branch, model, and context usage."

This is a personal preference setting, but most developers find it useful.

Example statusline output: `pwiz [Skyline/work/20260113_feature] | Opus | 36% used`

> **Existing mode**: Check if statusline is already configured:
> ```powershell
> Get-Content ~/.claude/settings.json | Select-String "statusLine"
> ```
> If already configured, skip this step unless the user wants to update it.

Read `~/.claude/settings.json` and add the statusLine configuration, preserving any existing settings:

```json
{
  "statusLine": {
    "type": "command",
    "command": "pwsh -NoProfile -File <project root>\\ai\\scripts\\statusline.ps1"
  }
}
```

> **Note:** Replace `<project root>` with the actual path (e.g., `C:\\proj`). Reference the script directly from the pwiz-ai checkout rather than copying it. This ensures you always have the latest version.

The statusline takes effect on the next Claude Code restart. Since the user just restarted in 1.11, no immediate restart is needed—the statusline will activate at the next natural restart point (e.g., after MCP server configuration in Phase 7).

The statusline integrates with the StatusMcp server (configured in Phase 7.3) to show the active project's git branch in sibling mode setups.

The user can decline if they prefer the default Claude Code display.

### 1.13 About the Directory Structure

This setup uses **sibling mode** - the AI tooling (`ai/`) is a sibling to project checkouts (`pwiz/`):

```
<your project root>\        <- Claude Code runs from here (and stays here)
├── .claude/                <- Junction to ai/claude/
├── ai/                     <- AI tooling repository (pwiz-ai)
└── pwiz/                   <- Skyline source code
```

**Benefits of sibling mode:**
- Claude Code stays in your project root throughout - no context loss from directory changes
- Can assist across multiple project checkouts (e.g., `pwiz/`, `skyline_26_1/`, `scratch/`)
- Simple setup - just clone, no nested repos

> **Note:** An alternative "child mode" embeds `ai/` inside a pwiz checkout (the pwiz `.gitignore` ignores the `ai/` folder). See `ai/docs/ai-repository-strategy.md` for details. Sibling mode is recommended for most developers.

---

## Phase 2: Visual Studio Installation

### 2.1 Check for Visual Studio

List installed Visual Studio versions:
```powershell
Get-ChildItem "C:\Program Files\Microsoft Visual Studio" -Directory | Select-Object Name
```

Expected output shows a version folder:
- **VS 2022**: Folder named `2022`
- **VS 2026**: Folder named `18`

If no Visual Studio folder exists, install **Visual Studio 2022 Community** (required for nightly testing).

**Option A - Winget (recommended):**

Install VS 2022 with required workloads in one command:
```powershell
winget install Microsoft.VisualStudio.2022.Community --source winget --override "--add Microsoft.VisualStudio.Workload.ManagedDesktop --add Microsoft.VisualStudio.Workload.NativeDesktop --add Microsoft.Net.Component.4.7.2.TargetingPack --passive"
```

This installs with:
- .NET desktop development (`ManagedDesktop`)
- Desktop development with C++ (`NativeDesktop`)
- .NET Framework 4.7.2 targeting pack

The `--passive` flag shows progress without requiring interaction.

**Option B - Manual download:**

1. Open browser to: https://visualstudio.microsoft.com/downloads/
2. Download and run **Visual Studio 2022 Community** installer
3. Select these workloads:
   - **.NET desktop development** (required)
   - **Desktop development with C++** (required)
4. Verify in "Individual components": **.NET Framework 4.7.2 targeting pack**
5. Click Install and wait for completion

If the targeting pack is not available in the VS installer, download the Developer Pack directly:
- https://dotnet.microsoft.com/download/dotnet-framework/net472

> **Note on VS 2026:** Optionally install VS 2026 for compatibility testing. While VS 2026 support is being developed, nightly testing currently requires VS 2022. VS 2026 builds have shown compatibility issues with some vendor DLLs (access violations). Use `toolset=msvc-14.3` (VS 2022) for production builds. Set environment variable `SKYLINE_BUILD_TOOLSET=msvc-14.5` to test with VS 2026.

### 2.2 Verify Installation

After VS installation, verify the edition is installed:
```powershell
# For VS 2026:
Get-ChildItem "C:\Program Files\Microsoft Visual Studio\18" -Directory -ErrorAction SilentlyContinue | Select-Object Name

# For VS 2022:
Get-ChildItem "C:\Program Files\Microsoft Visual Studio\2022" -Directory -ErrorAction SilentlyContinue | Select-Object Name
```

Expected output shows one of: `Community`, `Professional`, or `Enterprise`.

> **Note:** The C++ compiler (`cl.exe`) is NOT in the system PATH. This is expected. It's only available from the Developer Command Prompt or when invoked through MSBuild. The real verification is whether the build succeeds in Phase 4.

If the Visual Studio folder is empty or missing the edition subfolder, the user needs to:
1. Open Visual Studio Installer
2. Click "Modify" on their VS installation
3. Ensure both workloads are checked:
   - ".NET desktop development"
   - "Desktop development with C++"
4. Click "Modify" to install

---

## Phase 3: Developer Tools

These tools are essential for productive Skyline development.

### 3.1 Essential Tools

Install these core tools (all available via winget except ReSharper).

> **Existing mode**: Check each tool before installing. Winget will skip already-installed packages, but checking first provides clearer feedback.

**TortoiseGit** - Windows Explorer integration for Git:
```powershell
# Existing mode check:
Test-Path "C:\Program Files\TortoiseGit\bin\TortoiseGitProc.exe"

# Install if missing:
winget install TortoiseGit.TortoiseGit --accept-source-agreements --accept-package-agreements
```
After installation, restart Windows Explorer to enable TortoiseGit status icons:
1. Open **Task Manager** (Ctrl+Shift+Esc)
2. Find **Windows Explorer** in the list
3. Right-click it → **Restart**
4. Open File Explorer and navigate to your pwiz checkout - you should see green checkmarks on files indicating Git status

**IMPORTANT - Configure TortoiseGit SSH client:**

This step is critical. Without it, TortoiseGit will fail to authenticate with GitHub when pushing or pulling.

1. Right-click on your pwiz checkout folder → **Show more options** → **TortoiseGit** → **Settings**
2. Select **Network** in the left panel
3. Set **SSH client** to: `C:\Program Files\Git\usr\bin\ssh.exe`
4. Click **OK**

> **For LLM assistants:** Do not skip this verification. Ask the user to confirm they have set the SSH client path. A missing or incorrect setting will cause confusing authentication failures later.

**Notepad++** - Lightweight text editor with syntax highlighting:
```powershell
# Existing mode check:
Test-Path "C:\Program Files\Notepad++\notepad++.exe"

# Install if missing:
winget install Notepad++.Notepad++ --accept-source-agreements --accept-package-agreements
```

**ReSharper** - JetBrains code analysis extension for Visual Studio (check in VS Extensions menu):
1. Go to: https://www.jetbrains.com/resharper/download/
2. Download and run the installer
3. A JetBrains license is required (30-day trial available)
4. Restart Visual Studio after installation

> **Note:** ReSharper requires a paid license but is highly recommended. The Skyline team uses it extensively.

### 3.2 Optional Utilities

These are useful but not required.

> **For LLM assistants:** You MUST explicitly offer these to the user. Do not skip this section. Ask: "Would you like me to install the optional utilities (WinMerge, EmEditor, WinSCP)? They're quick winget installs and useful for development."

**WinMerge** - File and folder comparison tool:
```powershell
winget install WinMerge.WinMerge --accept-source-agreements --accept-package-agreements
```

**EmEditor** - Text editor optimized for very large files (useful for large .sky XML and .mzML files):
```powershell
winget install Emurasoft.EmEditor --accept-source-agreements --accept-package-agreements
```

**WinSCP** - SFTP/SCP client for file transfers and WebDAV access to LabKey servers:
```powershell
winget install WinSCP.WinSCP --accept-source-agreements --accept-package-agreements
```

### 3.3 AI Development Tools

These CLI tools support AI-assisted development workflows.

> **Existing mode**: Check each tool with the verification command before installing.

**GitHub CLI** - For PR creation, issue management:
```powershell
# Existing mode check:
gh --version

# Install if missing:
winget install GitHub.cli --accept-source-agreements --accept-package-agreements
```

After installation (or if already installed but not authenticated), authenticate:
```powershell
gh auth status    # Check if already authenticated
gh auth login     # If not authenticated
```
(Choose GitHub.com, HTTPS, authenticate with browser)

> **Note:** When the browser asks for an 8-digit code, look in the terminal window you started from - the code is displayed there, not in an authenticator app.

**ReSharper CLI** - Code inspection from command line:
```powershell
# Existing mode check:
Get-Command jb -ErrorAction SilentlyContinue

# Install if missing:
dotnet tool install -g JetBrains.ReSharper.GlobalTools
```

> **Note:** The `jb` command doesn't support `--version`. Use `dotnet tool list -g | Select-String jetbrains` to see installed versions.

**dotCover CLI** - Code coverage analysis:
```powershell
# Existing mode check:
dotCover --version

# Install if missing:
dotnet tool install --global JetBrains.dotCover.CommandLineTools
```

**dotMemory CLI** - Memory profiling (optional, for leak investigation):
```powershell
# Existing mode check:
Test-Path "$env:USERPROFILE\.claude-tools\dotMemory"

# Install if missing:
pwsh -File ai\scripts\Install-DotMemory.ps1
```

> **Note:** Unlike dotCover, dotMemory is NOT a .NET global tool. The install script downloads and extracts the NuGet package to `~/.claude-tools/dotMemory/`. Use with `Run-Tests.ps1 -MemoryProfile`.

**dotTrace CLI** - Performance profiling (optional, for performance investigation):
```powershell
# Existing mode check:
dottrace --version

# Install if missing:
dotnet tool install --global JetBrains.dotTrace.GlobalTools
```

> **Note:** The dotTrace CLI is a .NET global tool for capturing performance snapshots. For XML report export (automated analysis), `Reporter.exe` from the dotTrace GUI installation is also required. Developers with the JetBrains All Products Pack already have this at `%LOCALAPPDATA%\JetBrains\Installations\dotTrace*\Reporter.exe`. Use with `Run-Tests.ps1 -PerformanceProfile`.
>
> **Known issue (.NET 9):** dotTrace CLI 2025.3.x ships with a broken `runtimeconfig.json` that targets `net6.0` with `rollForward: Major`, but its assemblies require .NET 8. On machines with .NET 9 SDK, the tool rolls forward to .NET 9 and crashes with `FileLoadException: System.Runtime, Version=8.0.0.0`. Fix by editing both runtimeconfig files in `~/.dotnet/tools/.store/jetbrains.dottrace.globaltools/<version>/.../tools/net8.0/any/`: change `tfm` to `"net8.0"`, `rollForward` to `"LatestMinor"`, and framework version to `"8.0.0"` in both `dottrace.runtimeconfig.json` and `dottrace.runtimeconfig.win.json`.

**Python packages** - For MCP servers and LabKey integration:
```powershell
# Existing mode check:
python -c "import mcp; import labkey; print('OK')"

# Install if missing:
pip install mcp labkey
```

---

## Phase 4: Initial Build

> **Existing mode**: Check if build artifacts already exist (from your pwiz checkout):
> ```powershell
> Test-Path "pwiz\pwiz_tools\Skyline\bin\x64\Release\Skyline.exe"
> Test-Path "pwiz\pwiz_tools\Skyline\bin\x64\Release\TestRunner.exe"
> ```
> If both exist and the user confirms the build is recent, skip to Phase 5.

### 4.1 Vendor License Agreement

Before creating the build scripts, **ask the user to review the vendor licenses**:

> "Building Skyline requires accepting vendor SDK licenses. Please review the licenses at:
> http://proteowizard.org/licenses.html
>
> Do you agree to these license terms?"

**Wait for explicit confirmation before proceeding.** The build scripts include `--i-agree-to-the-vendor-licenses` which indicates acceptance.

### 4.2 Create Build Scripts

Once the user agrees to the licenses, create two batch files in the pwiz checkout root:

**b.bat** - General build script (single line):
```batch
@call "%~dp0pwiz_tools\build-apps.bat" 64 --i-agree-to-the-vendor-licenses toolset=msvc-14.3 %*
```

**bs.bat** - Skyline-specific build:
```batch
call "%~dp0b.bat" pwiz_tools\Skyline//Skyline.exe
```

> **Note on toolset**: Use `toolset=msvc-14.3` for VS 2022 (recommended for nightly testing). Use `toolset=msvc-14.5` for VS 2026 (experimental).

### 4.3 Run the Build

**Important:** The build must run in a native Windows environment, not through Claude Code's bash shell.

Tell the user:
1. Open a **new Command Prompt or PowerShell window**
2. Run (from the pwiz checkout):
   ```cmd
   cd <your pwiz checkout>
   bs.bat
   ```
3. Wait for the build to complete (10-20 minutes on first run)
4. The build downloads vendor SDKs on first run

### 4.4 Verify Build Artifacts

After the user reports the build completed, verify:
```powershell
Test-Path "pwiz\pwiz_tools\Skyline\bin\x64\Release\Skyline.exe"
```

If the build failed, check `pwiz\build64.log` for errors. Common issues:
- Missing C++ tools: See Phase 2.3
- NuGet errors: See Troubleshooting section

---

## Phase 5: Visual Studio Configuration

### 5.1 Open Skyline Solution

Tell the user:
1. Open Visual Studio
2. On first launch, Visual Studio asks about keyboard shortcuts - recommend **IntelliJ** keybindings (the existing team preference)
3. File > Open > Project/Solution
4. Navigate to: `<your pwiz checkout>\pwiz_tools\Skyline\Skyline.sln`

### 5.2 Configure ReSharper Menu

Give ReSharper its own top-level menu (instead of being buried under Extensions):

Tell the user:
1. Extensions menu > **Customize Menu...**
2. In the "Menu items in the Extensions menu" list, **uncheck "ReSharper"**
3. Click OK
4. **Restart Visual Studio** (required for the change to take effect)
5. Reopen the Skyline solution

ReSharper should now appear as a top-level menu item.

### 5.3 Configure Test Settings

Tell the user:
1. Test menu > Configure Run Settings > Select Solution Wide runsettings File
2. Navigate to: `<your pwiz checkout>\pwiz_tools\Skyline\TestSettings_x64.runsettings`

### 5.4 Disable "Just My Code"

Tell the user:
1. Tools > Options > Debugging > General
2. Uncheck "Enable Just My Code"
3. Click OK

### 5.5 Build in Visual Studio

Tell the user:
1. Build menu > Build Solution (or Ctrl+Shift+B)
2. Wait for build to complete
3. Check Output window for "Build succeeded"

---

## Phase 6: Verify Setup

> **For LLM assistants:** Read `ai/docs/build-and-test-guide.md` for detailed information about the AI build and test scripts. Key points: always use `Build-Skyline.ps1` and `Run-Tests.ps1` (never call MSBuild or TestRunner directly).

### 6.1 Build with AI Scripts

Verify the AI build scripts work correctly (from your project root):
```powershell
pwsh -Command "& './ai/scripts/Skyline/Build-Skyline.ps1'"
```

This builds the entire Skyline solution using MSBuild (matching Visual Studio's Ctrl+Shift+B). The script auto-detects the `pwiz/` folder as a sibling to `ai/`.

### 6.2 Run CodeInspection Test

Run the CodeInspection test to verify test execution works:
```powershell
pwsh -Command "& './ai/scripts/Skyline/Run-Tests.ps1' -TestName CodeInspection"
```

This validates that ReSharper code inspection passes. Success means the environment is fully working.

### 6.3 Summary Checklist

Run these verification commands:
```powershell
# Git configured
git config --global core.autocrlf  # Should be: true

# Repository cloned (run from your project root)
Test-Path pwiz\pwiz_tools\Skyline\Skyline.sln  # Should be: True

# Build artifacts exist (from bs.bat in Phase 4)
Test-Path pwiz\pwiz_tools\Skyline\bin\x64\Release\Skyline-daily.exe  # Should be: True
Test-Path pwiz\pwiz_tools\Skyline\bin\x64\Release\TestRunner.exe  # Should be: True
```

---

## Phase 7: AI Tooling Configuration

The AI tooling is already set up from Phase 1.9 (sibling mode). This phase configures optional integrations.

### 7.1 Verify Environment

Run the verification script to check all AI tooling components (from your project root):
```powershell
pwsh -Command "& './ai/scripts/Verify-Environment.ps1'"
```

This checks for all required tools and reports any missing components.

**The verification must PASS before proceeding.** If any items are missing:
- Fix the missing items, OR
- Use `-Skip` to explicitly defer optional components (netrc credentials for LabKey access)

```powershell
# Skip netrc if deferring LabKey API setup
pwsh -Command "& './ai/scripts/Verify-Environment.ps1' -Skip netrc"
```

> **For LLM assistants:** You MUST achieve a passing verification (exit code 0) before continuing to Phase 8. If the user chooses to skip optional components, use the `-Skip` parameter explicitly. Do not proceed with MISSING or ERROR items.

### 7.2 LabKey API Credentials

The LabKey MCP server needs credentials for skyline.ms access.

> **Existing mode**: Check if credentials are already configured:
> ```powershell
> Test-Path "$env:USERPROFILE\.netrc"
> # If exists, verify it contains skyline.ms:
> Get-Content "$env:USERPROFILE\.netrc" | Select-String "skyline.ms"
> ```
> If properly configured, skip to 7.3.

> There needs to be a separate skyline.ms user account using a special "+claude" version of your current email address as the user name. An admin can help you with this.
> **IMPORTANT - This uses a dedicated +claude skyline.ms account, not your personal account:**
> - Team members: `yourname+claude@proteinms.net`
> - Interns/others: `yourname+claude@gmail.com`
> - The `+claude` suffix only works with Gmail-backed providers (not @uw.edu)
> - **Ask an administrator** to create an account on skyline.ms for this "+claude" email and have them add it to the **Site:Agents** group. You will then receive an email at your normal address asking you to set a password for the new account.
>
> **Why?** Individual +claude skyline.ms accounts provide attribution for any edits made via Claude, while the Site:Agents group has appropriate permissions for LLM agents.
> To be clear, you aren't creating a new email address - Google ignores the +claude part for routing purposes. This is just a new user id for a new skyline.ms account. Any email it generates will go to your normal email address.

Once an administrator has created your +claude account on skyline.ms, create a `.netrc` file:

```powershell
# Template - fill in your +claude credentials
@"
machine skyline.ms
login yourname+claude@proteinms.net
password your-password-here
"@ | Out-File -FilePath "$env:USERPROFILE\.netrc" -Encoding ASCII
```

For full LabKey MCP documentation, see: `ai/mcp/LabKeyMcp/README.md`

> **Deferring LabKey setup:** If you don't have a +claude account yet or want to set this up later, use `-Skip netrc` when running `Verify-Environment.ps1`. The LabKey MCP server will still be registered but will have limited functionality until credentials are configured.

### 7.3 MCP Server Configuration

Register the MCP servers with Claude Code.

> **Existing mode**: First check which servers are already registered:
> ```powershell
> claude mcp list
> ```
> Only register servers not already in the list.

**StatusMcp** - System status, git info, screenshot/clipboard capture, active project tracking:
```powershell
# Install dependencies (Pillow for clipboard image capture)
pip install mcp Pillow

claude mcp add status -- python ./ai/mcp/StatusMcp/server.py
```

**LabKey MCP** - Access to skyline.ms (nightly tests, exceptions, wiki, support):
```powershell
claude mcp add labkey -- python ./ai/mcp/LabKeyMcp/server.py
```

> **Note:** Use relative paths with forward slashes (`./ai/mcp/...`), not absolute Windows paths. The `claude mcp add` command strips backslashes, turning absolute paths like `C:\proj\ai\...` into `C:projai...` which fails to connect.

**After registering new servers, restart Claude Code** to activate them:
1. Exit Claude Code (`/exit`)
2. Resume with `claude --continue`

> **Note:** MCP servers require a Claude Code restart to become fully active, similar to how PATH updates require a terminal restart.

For Gmail integration (optional, for automated reports):
```powershell
claude mcp add gmail -- npx @gongrzhe/server-gmail-autoauth-mcp
```

See `ai/docs/mcp/gmail.md` for Gmail OAuth setup instructions.

### 7.4 Verify MCP Servers

Check that MCP servers are connected:
```powershell
claude mcp list
```

Expected output shows servers connected:
```
status: python ./ai/mcp/StatusMcp/server.py - ✓ Connected
labkey: python ./ai/mcp/LabKeyMcp/server.py - ✓ Connected
gmail: npx @gongrzhe/server-gmail-autoauth-mcp - ✓ Connected (if configured)
```

### 7.5 Browser Markdown Viewer (Recommended)

The `ai/` folder contains extensive documentation in Markdown format. Install a browser extension for easy viewing:

**Chrome or Edge:**
1. Install [Markdown Reader](https://chromewebstore.google.com/detail/markdown-reader/medapdbncneneejhbgcjceippjlfkmkg)
2. Click the Extensions icon (puzzle piece) → find Markdown Reader → click "⋮" → "Manage Extension"
3. **Enable "Allow access to file URLs"** (critical - won't render local files without this)

**Verify:** Open `ai\README.md` (in your project root) in Chrome/Edge - it should render with formatted headings, links, and code blocks.

> **Tip:** On Windows 11, you can associate `.md` files with Chrome for one-click viewing. On Windows 10, drag-and-drop `.md` files from File Explorer into Chrome.

For full AI tooling documentation, see: `ai/docs/developer-setup-guide.md`

---

## Phase 8: Nightly Test Setup (Optional)

Set up this machine to run Skyline nightly tests. This downloads the latest test harness from TeamCity and configures a scheduled task.

> **Existing mode**: Check if nightly tests are already configured:
> ```powershell
> # Check for existing scheduled task
> Get-ScheduledTask -TaskName '*Skyline*' -ErrorAction SilentlyContinue
> ```
> If a SkylineNightly task exists, nightly tests are already configured. SkylineNightly is self-updating, so no further action is needed—skip this phase.
>
> If no task exists but the user has a preferred nightly folder, check if SkylineNightly is already downloaded:
> ```powershell
> Test-Path "<NightlyFolder>\SkylineNightly.exe"
> ```
> If present, skip to 8.4 (Configure Nightly Tests) to create the scheduled task.

### 8.1 Choose a Nightly Folder Location

**Ask the developer where they want to store nightly test data.**

> **Important:** Nightly tests generate significant disk I/O. If the machine has a spinning hard drive (HDD), use that instead of the SSD. SSDs wear out faster under the sustained write stress that nightly tests cause.

Common locations:
- `D:\Nightly` - if D: is an HDD
- `E:\Nightly` - on machines where E: is the HDD
- `C:\Nightly` - only if no HDD is available (SSD will work, but has longevity trade-offs)

For the commands below, replace `<NightlyFolder>` with the chosen path.

### 8.2 Download SkylineNightly

Download and extract the nightly test harness:

```powershell
# Create the nightly directory (replace <NightlyFolder> with chosen path)
New-Item -ItemType Directory -Force -Path '<NightlyFolder>'

# Download SkylineNightly.zip from TeamCity (public guest access)
$url = 'https://teamcity.labkey.org/guestAuth/repository/download/bt209/.lastFinished/SkylineNightly.zip?branch=master'
Invoke-WebRequest -Uri $url -OutFile '<NightlyFolder>\SkylineNightly.zip'

# Extract the archive
Expand-Archive -Path '<NightlyFolder>\SkylineNightly.zip' -DestinationPath '<NightlyFolder>' -Force
```

Verify the extraction:
```powershell
Get-ChildItem '<NightlyFolder>'
# Should show: SkylineNightly.exe, SkylineNightlyShim.exe, DotNetZip.dll, etc.
```

### 8.3 Configure Antivirus Exclusions

**This step requires Administrator privileges.**

Nightly tests create and delete thousands of files. Real-time antivirus scanning significantly slows tests and can cause spurious failures. Add exclusions for both the source code and nightly test folders:

1. Open **Windows Security** (search for it in Start menu)
2. Go to **Virus & threat protection** → **Manage settings**
3. Scroll to **Exclusions** → **Add or remove exclusions**
4. Click **Add an exclusion** → **Folder**
5. Add these folders:
   - Your project root folder (source code and AI tooling)
   - `<NightlyFolder>` (nightly tests)

> **Security note:** These exclusions reduce protection for these folders. Only add them on development machines where you understand the trade-offs.

### 8.4 Configure Nightly Tests

Run SkylineNightly as Administrator to configure the scheduled task:

**Option A - File Explorer (easiest):**
1. Open Windows File Explorer
2. Navigate to `<NightlyFolder>`
3. Right-click **SkylineNightly.exe** → **Run as administrator**

**Option B - PowerShell:**
1. Open an **elevated PowerShell** (Run as Administrator)
2. Run:
   ```powershell
   cd <NightlyFolder>
   .\SkylineNightly.exe
   ```

In the GUI that appears:
1. Configure your preferred test schedule (typically overnight, e.g., 10 PM or later)
2. Save the configuration

The scheduled task will run `SkylineNightlyShim.exe` at your chosen time, which:
- Updates itself and `SkylineNightly.exe` from TeamCity
- Downloads the latest Skyline build
- Runs the full test suite
- Uploads results to skyline.ms

### 8.5 Verify Scheduled Task

Check that the task was created:
```powershell
Get-ScheduledTask -TaskName '*Skyline*'
```

You can also view it in Task Scheduler (taskschd.msc).

### 8.6 Test the Nightly Build (Recommended)

Before relying on the scheduled task, verify everything works by running a quick test:

1. In the SkylineNightly GUI, click the **"Now"** button
2. Wait for SkylineTester to appear and show progress
3. Verify these steps complete successfully:
   - **Checkout**: Status bar shows "Checking out Skyline (master)"
   - **Build**: Skyline compiles without errors
   - **First test**: `AaantivirusTestExclusion` passes (this test fails if antivirus exclusions aren't configured correctly)
4. Once you see tests running successfully, you can click **Stop** to end the test run

This validates that the build environment works, tests can execute, and antivirus exclusions are properly configured.

---

## Troubleshooting

### NuGet Package Errors (NU1101)

If you see "Unable to find package" errors:
1. In Visual Studio: Tools > NuGet Package Manager > Package Manager Settings
2. Click "Package Sources"
3. Add a new source:
   - Name: `nuget.org`
   - Source: `https://api.nuget.org/v3/index.json`
4. Click OK and rebuild

### Antivirus Blocking Tests

If tests fail randomly or builds are slow:
1. Open Windows Security
2. Virus & threat protection > Manage settings
3. Scroll to Exclusions > Add or remove exclusions
4. Add folder exclusion for your project root

**Note**: This requires admin privileges and the user should understand the security implications.

### SSH Connection Refused

If `ssh -T git@github.com` fails:
- Firewall may be blocking port 22
- Try HTTPS instead: `git remote set-url origin https://github.com/ProteoWizard/pwiz.git`
- User will need to set up a GitHub Personal Access Token for HTTPS auth

---

## Final Report

**Before declaring setup complete, you MUST produce a comprehensive final report.**

The report should be:
1. Written to `ai\.tmp\new-machine-setup-<date>.md` (the `.tmp` folder serves as a communication conduit between Claude Code and the developer)
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
- **Completion timestamp** - Call `mcp__status__get_status` and use the `localTimestamp` field in the report footer

### After the Report

After writing the report to `ai\.tmp`, ask the user:
1. **Finish local config** - Continue resolving any remaining items (deferred, not verified, skipped)
2. **Done for now** - User will review the report and return later if needed

> **Note:** The `ai\.tmp\` folder is not tracked in git. It's a scratch space for session-specific notes, handoffs, and communication between the developer and Claude Code.

### Update Documentation (Required)

**Before ending the session**, review your notes from the setup process. If the user reported issues, corrections, or friction points:

1. **Edit `ai/docs/new-machine-setup.md`** to address the issues
2. **Commit the changes** to pwiz-ai (the `ai/` folder is the pwiz-ai repository - commit directly to master)
3. **Tell the user** what improvements you made

Even if the user reported no issues, consider whether any steps caused confusion or required extra explanation. Proactively improve unclear sections.

If the setup was interrupted before `ai/` was cloned, note the improvements needed in the final report so a future session can apply them.

---

## Success Criteria

The setup is complete when:
1. `git config --global core.autocrlf` returns `true`
2. `pwiz\pwiz_tools\Skyline\Skyline.sln` exists (relative to your project root)
3. `pwiz\pwiz_tools\Skyline\bin\x64\Release\Skyline.exe` exists
4. Visual Studio can build the solution without errors
5. `TestRunner.exe test=TestA` passes

Congratulate the user and let them know they're ready to develop Skyline!
