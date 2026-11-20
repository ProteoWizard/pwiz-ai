# Quick Start: New Machine Setup with AI Assistance

This guide gets you from a pristine Windows machine to a working Skyline development environment in about an hour, with an AI assistant guiding most of the process.

**Prerequisites:** Windows 10/11, internet connection, a GitHub account with access to ProteoWizard/pwiz, and a Claude Pro or Claude Max subscription

There are two ways to start. **Claude Desktop** is the recommended one: there is nothing to type until the assistant is already helping you. The **Claude Code console** path is for developers who prefer to work in a terminal. Both end at the same prompt in Step 5, and the assistant installs whatever the other path would have given you.

---

## Step 1: Install Git

Claude no longer needs Git to start on Windows (Claude Desktop required it before version 1.49585.0), but the setup does: the first thing the assistant does is clone a repository, and Git Bash provides the Bash tool that the project's scripts and documentation assume.

Press <kbd>Win</kbd>+<kbd>X</kbd>, then press <kbd>I</kbd> to open **Terminal** (Windows 11) or **Windows PowerShell** (Windows 10), and run:

```powershell
winget install Git.Git --source winget --accept-source-agreements --accept-package-agreements
```

> **Note:** The `--source winget` flag avoids Microsoft Store SSL certificate errors that can occur on fresh Windows installations.

**Close and reopen PowerShell** after installation to get `git` in your PATH, then verify:

```powershell
git --version
```

## Step 2: Create Project Folder

Create the empty folder that will hold the repositories:

```powershell
# Use your preferred project root (C:\proj, C:\Dev, D:\proj, etc.)
New-Item -ItemType Directory -Path C:\proj -Force
```

**Why this matters:** Claude Code asks whether you trust the files in the folder it starts in. You want to answer that in an empty project folder, not your home directory, which may contain sensitive files like `.netrc`, `.ssh`, or other credentials. A short path also avoids Windows path-length problems later in the build.

## Step 3: Install Claude

### Option A: Claude Desktop (recommended)

1. Download Claude Desktop from [claude.com/download](https://claude.com/download) and run the installer.
2. Sign in with your Anthropic account.

### Option B: Claude Code console

```powershell
irm https://claude.ai/install.ps1 | iex
```

This is Anthropic's standalone installer. It installs to `%USERPROFILE%\.local\bin\claude.exe` and keeps itself up to date.

**Close and reopen PowerShell**, then verify:

```powershell
claude --version
```

If `claude` is not recognized, see Troubleshooting below.

> **Alternative:** `winget install Anthropic.ClaudeCode --source winget` also works and sets PATH for you, but it does not update itself. Run `winget upgrade Anthropic.ClaudeCode` from time to time.

**Subscription:** Use a **Claude Pro** or **Claude Max** subscription. These are straightforward monthly subscriptions at [claude.ai](https://claude.ai) that work immediately with both Claude Desktop and Claude Code.

> **Note:** Claude Code also supports API keys, but if you don't already have one set up and know how to use it, don't go down that path. It requires separate billing configuration and is meant for developers building integrations, not end users.

## Step 4: Start a Session in the Project Folder

### Option A: Claude Desktop

1. Open Claude Desktop and switch to the **Code** tab.
2. Start a new session and choose `C:\proj` (or your project root from Step 2) as its folder.

### Option B: Claude Code console

```powershell
cd C:\proj
claude
```

Follow the prompts to authenticate with your Anthropic account.

## Step 5: Let Claude Guide the Rest

Paste this prompt into the session:

```
Help me set up a Skyline development environment on this Windows machine.

Download this file with curl (not WebFetch, which returns a summary), then read and follow the instructions:
https://raw.githubusercontent.com/ProteoWizard/pwiz-ai/master/docs/new-machine-setup.md

This is a PRISTINE machine - I just completed the bootstrap steps (Git and Claude installed, nothing else).

Clone the pwiz-ai repository first, so you have the project documentation and the environment verification script before installing anything else.

Guide me through each step, verifying success before moving on.
Ask me before running any installers.
```

Claude will then:
1. Clone the AI tooling repository and check what the machine is missing
2. Configure Git settings (line endings, etc.)
3. Help you set up SSH keys for GitHub
4. Clone the pwiz repository
5. Install Visual Studio and the other build prerequisites
6. Run the initial build and a first test
7. Set up the AI development tools (MCP servers, command-line tools)

---

## What Happens Next

The AI assistant will walk you through each step interactively. It will:
- **Check what's already installed** and skip unnecessary steps
- **Verify each step worked** before moving on
- **Explain any errors** and help you fix them
- **Ask before each installer**, and ask which optional tools you want
- **Tell you exactly what to click** in GUI installers

Some steps are yours to do: approving Windows elevation prompts, creating your SSH key and adding it to GitHub, signing in to GitHub and JetBrains, and choosing settings inside Visual Studio. Claude will tell you when it needs one of them.

**If you started in Claude Desktop**, Claude will also offer to install the Claude Code console. A few parts of the setup use it (registering MCP servers and plugins), and the statusline and taskbar launcher exist only for console sessions. After the project configuration is in place, quit and reopen Claude Desktop once so it loads the project's skills, commands and MCP servers.

---

## Alternative: Manual Setup

If you prefer to set up without AI assistance, see the traditional guide: [How to Build Skyline](https://skyline.ms/home/software/Skyline/wiki-page.view?name=HowToBuildSkylineTip)

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `winget` not recognized | You're on older Windows. Download Git from https://git-scm.com instead. |
| `winget` SSL certificate errors | Add `--source winget` to the command (already included in commands above). |
| `git` not recognized after install | Close and reopen PowerShell to refresh PATH. |
| `claude` not recognized after install | See the PATH fix below. |
| Authentication fails | Sign up for Claude Pro or Max at [claude.ai](https://claude.ai). Avoid the API key path unless you already have one configured. |
| Claude can't fetch the setup page | Check your internet connection. The AI will still help with general guidance. |

### `claude` not recognized - PATH Fix

The standalone installer does not always add its folder to your PATH. Check that it installed:

```powershell
Test-Path "$env:USERPROFILE\.local\bin\claude.exe"
```

**If the file exists**, add the folder to your PATH, then close the whole PowerShell window (not just the tab) and open a new one:

```powershell
$claudePath = "$env:USERPROFILE\.local\bin"
[Environment]::SetEnvironmentVariable("Path", [Environment]::GetEnvironmentVariable("Path", "User") + ";$claudePath", "User")
```

**If the file doesn't exist**, the installer failed. Use the winget alternative from Step 3.

---

*Last updated:* 2026-11-20
