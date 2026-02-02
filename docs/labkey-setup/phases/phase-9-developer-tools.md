# Phase 9: Developer Tools (Optional)

**Goal**: Install optional tools that improve developer experience.

All tools in this phase are optional. Offer each to the user with explanation.

## Tool 9.1: Notepad++

**Why**: Advanced text editor for quick file editing, log viewing.

**Ask user**: "Install Notepad++? (powerful text editor) [y/n]"

**If yes**:
```bash
powershell.exe -Command "winget install Notepad++.Notepad++ --source winget"
```

**Verify**:
```bash
powershell.exe -Command "Test-Path 'C:\Program Files\Notepad++\notepad++.exe'"
```

## Tool 9.2: WinMerge

**Why**: Visual diff/merge tool for comparing files and directories.

**Ask user**: "Install WinMerge? (file comparison/merge tool) [y/n]"

**If yes**:
```bash
powershell.exe -Command "winget install WinMerge.WinMerge --source winget"
```

**Verify**:
```bash
powershell.exe -Command "Test-Path 'C:\Program Files\WinMerge\WinMergeU.exe'"
```

## Tool 9.3: TortoiseGit

**Why**: Windows shell integration for Git (right-click context menu).

**Ask user**: "Install TortoiseGit? (Git GUI with Windows Explorer integration) [y/n]"

**If yes**:
```bash
powershell.exe -Command "winget install TortoiseGit.TortoiseGit --source winget --interactive"
```

**User must**:
- Click through installer
- Accept defaults
- Restart Windows Explorer (or reboot)

**Configure SSH client** (important):
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
powershell.exe -Command "Test-Path 'C:\Program Files\TortoiseGit\bin\TortoiseGitProc.exe'"
```

## Tool 9.4: GitHub CLI

**Why**: Manage GitHub from command line (required for Claude Code PR creation).

**Ask user**: "Install GitHub CLI? (required for Claude Code to create PRs) [y/n]"

**If yes**:
```bash
powershell.exe -Command "winget install GitHub.cli --source winget"
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

## Tool 9.5: Claude Code

**Why**: AI assistant for development tasks (if not already installed).

**Ask user**: "Install/verify Claude Code? [y/n]"

**If yes**:
```bash
powershell.exe -Command "irm https://claude.ai/install.ps1 | iex"
```

**Add to PATH**:
```bash
powershell.exe -Command "\$claudePath = \"\$env:USERPROFILE\.local\bin\"; [Environment]::SetEnvironmentVariable('Path', [Environment]::GetEnvironmentVariable('Path', 'User') + \";\$claudePath\", 'User')"
```

**Restart terminal** and verify:
```bash
claude --version
```

**Authenticate** if needed:
```bash
claude
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
    "github_cli": true,
    "claude_code": true
  }
}
```

**Next**: Generate final report
