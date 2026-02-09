# Phase 9: Developer Tools (Optional)

**Goal**: Install optional tools that improve developer experience.

All tools in this phase are optional. Offer each to the user with explanation.

## Tool 9.1: Notepad++

**Why**: Advanced text editor for quick file editing, log viewing.

**Ask user**: "Install Notepad++? (powerful text editor) [y/n]"

**If yes**:
```bash
powershell.exe -Command 'winget install Notepad++.Notepad++ --source winget'
```

**Verify**:
```bash
powershell.exe -Command 'Test-Path "C:\Program Files\Notepad++\notepad++.exe"'
```

## Tool 9.2: WinMerge

**Why**: Visual diff/merge tool for comparing files and directories.

**Ask user**: "Install WinMerge? (file comparison/merge tool) [y/n]"

**If yes**:
```bash
powershell.exe -Command 'winget install WinMerge.WinMerge --source winget'
```

**Verify** (winget installs WinMerge per-user, so check the registry):
```bash
powershell.exe -Command 'Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\WinMergeU.exe" -ErrorAction SilentlyContinue'
```

## Tool 9.3: TortoiseGit

**Why**: Windows shell integration for Git (right-click context menu).

**Ask user**: "Install TortoiseGit? (Git GUI with Windows Explorer integration) [y/n]"

**If yes, brief the user before launching the installer:**

> The TortoiseGit installer will open a GUI. Here's what to do:
>
> 1. **UAC prompt** — Click **Yes** to allow changes
> 2. Click **Next** through the installation screens, accepting the defaults
> 3. **Important**: On the final screen, **uncheck "Run first start wizard"**
> 4. Click **Finish**
>
> After installation, I'll help you configure the SSH client settings.
>
> Are you ready to start the installer?

**Wait for confirmation**, then run:
```bash
powershell.exe -Command 'winget install TortoiseGit.TortoiseGit --source winget --interactive'
```

**After installation completes, configure SSH client** (important):
1. Right-click on <labkey_root> → **Show more options** → **TortoiseGit** → **Settings**
2. Select **Network** in the left panel
3. Set **SSH client** to: `C:\Program Files\Git\usr\bin\ssh.exe`
4. Click **OK**

**Why?** TortoiseGit by default uses PuTTY's SSH client which expects keys in `.ppk` format. We set up SSH keys using OpenSSH (`id_ed25519`). 
By pointing TortoiseGit to Git's SSH client, it uses the same keys you already configured for GitHub. Without this, TortoiseGit push/pull will fail authentication.


**Windows 11 tip**: To add more TortoiseGit options to context menu:
- Right-click > TortoiseGit > Settings > General > Windows 11 Context Menu

**Verify**:
```bash
powershell.exe -Command 'Test-Path "C:\Program Files\TortoiseGit\bin\TortoiseGitProc.exe"'
```

## Tool 9.4: GitHub CLI

**Why**: Manage GitHub from command line (required for Claude Code PR creation).

**Ask user**: "Install GitHub CLI? (required for Claude Code to create PRs) [y/n]"

**If yes**:
```bash
powershell.exe -Command 'winget install GitHub.cli --source winget'
```

**Restart terminal**, then authenticate:
```bash
gh auth status
# If not authenticated:
gh auth login
```

**Verify**:
```bash
gh --version
gh auth status
```

## Completion

**Update state.json** with installed tools:
```json
{
  "completed": ["phase-9"],
  "optional_tools": {
    "notepad++": true,
    "winmerge": false,
    "tortoisegit": true,
    "github_cli": true
  }
}
```

**Next**: Generate final report
