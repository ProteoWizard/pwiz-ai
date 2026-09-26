# WSL2 Setup Guide: Using the ai Repo from Linux

How to run Claude Code with the pwiz-ai tooling (`ai/`) inside a WSL2 Ubuntu VM on a
Windows machine. The guide can be used on windows machine that is configured with
the standard Windows setup ([developer-setup-guide.md](developer-setup-guide.md)) and 
WSL2 is used as an **additional** environment, not a replacement.  Or it can be used 
on a windows machine where building and testing Skyline/pwiz will not be performed.

## Scope

**Works in WSL2:** ai-repo documentation, TODOs, slash commands and skills, GitHub work
(`gh`, issues, PRs), non-.NET projects (Python, web), and team usage reporting
(`/pw-usage-reporting-wsl`).

**Stays on Windows:** building and testing Skyline/pwiz (.NET Framework, Visual Studio,
SkylineTester), screenshots, and anything that uses the MCP servers (status, LabKey,
nightly tests, exceptions, wiki). MCP servers are not yet configured for WSL, so skills
that call `mcp__*` tools will not work there.

Most of the ai repo's docs assume Windows (PowerShell, backslash paths, junctions). Read
them as describing the Windows environment; this guide lists the WSL substitutes.

## 1. Enable WSL2 and install Ubuntu

From an elevated PowerShell on Windows:

```powershell
wsl --install -d Ubuntu-24.04
```

Reboot if prompted, launch Ubuntu, and create your Linux user. Then enable systemd (needed
for scheduled jobs such as usage reporting) and set the default user in `/etc/wsl.conf`:

```ini
[boot]
systemd=true

[user]
default=<your-linux-user>
```

Apply with `wsl --shutdown` from Windows, then reopen Ubuntu. Verify: `ps -p 1 -o comm=`
prints `systemd`.

## 2. Base packages and Claude Code

```bash
sudo apt update
sudo apt install -y git jq python3
```

Install the GitHub CLI (`gh`) following its official Linux instructions (apt repository).

Install Claude Code with the native installer from the Claude Code docs; it lands in
`~/.local/bin/claude`. Make sure `~/.local/bin` is on `PATH`.

## 3. Git and GitHub credentials

GitHub access uses HTTPS through the GitHub CLI:

```bash
gh auth login            # choose GitHub.com, HTTPS
gh auth setup-git        # makes gh the git credential helper
git config --global user.name  "<your name>"
git config --global user.email "<your GitHub noreply or team email>"
```

For other SSH hosts, reuse your Windows SSH keys rather than creating new ones by mounting
the Windows `.ssh` folder over `~/.ssh`. Add to `/etc/fstab` (one line):

```
C:\Users\<winuser>\.ssh\  /home/<linuxuser>/.ssh  drvfs  rw,noatime,uid=1000,gid=1000,case=off,umask=0077,fmask=0177  0 0
```

The `umask`/`fmask` values give the keys the `600`/`700` permissions OpenSSH insists on
(drvfs files are otherwise world-readable and `ssh` refuses them). Run `sudo mount -a`, then
`ls -l ~/.ssh` to confirm.

## 4. Project layout (sibling mode)

Same layout as Windows ([ai-repository-strategy.md](ai-repository-strategy.md)), in the Linux
filesystem (not under `/mnt/c` - drvfs is slow and loses Linux permissions):

```bash
mkdir -p ~/dev/ai-dev
cd ~/dev/ai-dev
git clone https://github.com/ProteoWizard/pwiz-ai.git ai
ln -s ~/dev/ai-dev/ai/claude .claude     # replaces the Windows junction
cp ai/root-CLAUDE.md CLAUDE.md           # project-root CLAUDE.md
```

Start Claude Code from `~/dev/ai-dev`. Other repos you work on go beside `ai/` as siblings.

## 5. Windows-only pieces and their WSL substitutes

### Hooks: `pwsh` stub

`ai/claude/settings.json` runs its hooks with `pwsh` (PowerShell 7). PowerShell is not
installed in WSL, so without it every matching tool call triggers a failing hook. Install a
no-op stand-in at `~/.local/bin/pwsh`:

```bash
cat > ~/.local/bin/pwsh <<'EOF'
#!/bin/sh
# Stand-in for pwiz-ai hooks under WSL: PowerShell 7 isn't installed here.
exit 0
EOF
chmod +x ~/.local/bin/pwsh
```

**Consequence: every hook is silently skipped.** Under WSL you must do by hand what these
hooks enforce on Windows:

| Hook | What it enforces on Windows | Under WSL |
|------|-----------------------------|-----------|
| `Inject-VersionControlSkill` | Loads the version-control skill before git/gh commands | Load the `version-control` skill yourself before committing |
| `Deny-HarnessAttribution` | Blocks Claude Code's default attribution in commits/PRs | Check commit/PR text against the version-control skill |
| `Check-ReporterCredit` | Reminds about reporter credit on commits/PRs | Manual |
| `Deny-BomInCommit` | Blocks commits introducing a UTF-8 BOM | Manual |
| `Inject-PathBasedSkill` | Loads the matching skill when editing certain paths | Load skills per the CLAUDE.md skill list |
| `Deny-CodeReviewInAiRepo` | Blocks `/code-review` in the ai repo | Don't run it there |
| `Deny-DirectBuildTest` | Blocks direct build/test executables | N/A (no Windows builds in WSL) |
| `Set-ActiveCheckout` | Sets the active pwiz checkout at session start | N/A |

Porting these hooks to bash is a known follow-up.

The stub also means any `pwsh` command in the docs silently does nothing in WSL. Don't
follow `pwsh -File ...` instructions from the Windows docs inside WSL; use the WSL tooling
where it exists (see below), or run the step on Windows.

### Statusline

Use the bash port instead of `statusline.ps1`. In `~/.claude/settings.json`:

```json
"statusLine": {
  "type": "command",
  "command": "bash /home/<linuxuser>/dev/ai-dev/ai/scripts/statusline.sh"
}
```

It requires `jq`.

## 6. Windows interop notes

- **Drive letters:** WSL auto-mounts fixed disks at `/mnt/<letter>`, but not virtual drives
  such as Google Drive for Desktop (`G:`). Mount and persist it:
  ```bash
  sudo mkdir -p /mnt/g && sudo mount -t drvfs G: /mnt/g
  echo 'G: /mnt/g drvfs defaults,uid=1000,gid=1000 0 0' | sudo tee -a /etc/fstab
  ```
  Drive's "Add shortcut to Drive" `.lnk` files cannot be read from WSL, and
  `.shortcut-targets-by-id` is traverse-only (you can open a known path but not list it).
  Follow shortcuts through Windows:
  `powershell.exe -NoProfile -Command "(New-Object -ComObject WScript.Shell).CreateShortcut('G:\My Drive\X.lnk').TargetPath"`.
- **Calling Windows programs:** `cmd.exe`, `powershell.exe` and `/mnt/c/Program Files/PowerShell/7/pwsh.exe`
  work from an interactive WSL shell, but **not inside systemd services** (no interop
  there). Resolve anything that needs Windows at setup time and bake it into the unit.
- **Running Windows PowerShell on WSL files:** scripts at `\\wsl.localhost\...` are blocked by
  the execution policy as unsigned. For a one-off, use `pwsh.exe -ExecutionPolicy Bypass -File <path>`.
- **Output from Windows programs** ends lines with CRLF; pipe through `tr -d '\r'` before
  using it in bash.
- **Identity:** `cmd.exe /c 'echo %COMPUTERNAME%'` / `%USERNAME%` give the Windows machine
  and user names; the Linux `hostname` is usually the lowercase computer name.

## 7. Optional: team usage reporting

Claude Code in WSL keeps its transcripts in the Linux `~/.claude`, separate from Windows.
To contribute them to the team usage store, run `/pw-usage-reporting-wsl on`. It uses a
systemd user timer instead of a Windows Scheduled Task and records the machine as
`<COMPUTERNAME>-WSL`. Requires systemd (step 1) and the Drive mount (step 6).

## Related

- [developer-setup-guide.md](developer-setup-guide.md) - Windows developer setup
- [ai-repository-strategy.md](ai-repository-strategy.md) - sibling vs child layout
- [scheduled-tasks-guide.md](scheduled-tasks-guide.md) - Windows scheduled tasks
- `ai/scripts/Usage/README.md` - usage tracking
