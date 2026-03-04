# MCP Server Setup

How to set up all MCP servers for Claude Code. Referenced from [new-machine-setup.md](../new-machine-setup.md) Phase 7.

## Prerequisites

- Python 3.10+ with `pip`
- Claude Code installed
- Project cloned with `ai/` junction configured

Install Python packages:
```powershell
pip install mcp labkey Pillow
```

## Core Servers (Required)

### StatusMcp

System status, git info, screenshot/clipboard capture, active project tracking.

```powershell
claude mcp add status -- python ./ai/mcp/StatusMcp/server.py
```

See [status.md](status.md) for tool documentation.

### LabKey MCP

Access to skyline.ms (nightly tests, exceptions, wiki, support).

**Requires** `~/.netrc` credentials — see [LabKey API Credentials](#labkey-api-credentials) below.

```powershell
claude mcp add labkey -- python ./ai/mcp/LabKeyMcp/server.py
```

See [README.md](README.md) for tool documentation.

## Optional Servers

### TeamCity MCP

Monitors PR builds on `teamcity.labkey.org` — build status, test failures, build logs.

1. **Create a TeamCity API token:**
   - Go to `https://teamcity.labkey.org`
   - Click your profile (top-right) > **Access Tokens** > **Create access token**
   - Name it "Claude Code MCP" (read-only permissions are sufficient)

2. **Store the token:**
   ```powershell
   New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.teamcity-mcp"
   ```
   Create `~/.teamcity-mcp/config.json`:
   ```json
   {
     "url": "https://teamcity.labkey.org",
     "token": "YOUR_TOKEN_HERE"
   }
   ```

3. **Register:**
   ```powershell
   claude mcp add teamcity -- python ./ai/mcp/TeamCityMcp/server.py
   ```

See [team-city.md](team-city.md) for tool documentation.

### Gmail MCP

Email sending for automated reports (daily nightly test reports, etc.).

```powershell
claude mcp add gmail -- npx @gongrzhe/server-gmail-autoauth-mcp
```

See [gmail.md](gmail.md) for OAuth setup instructions.

### ImageComparer MCP

Screenshot diff review for tutorial documentation. Only needed when working on tutorials.

This server is a .NET executable built from the Skyline solution. It must be built before registration:

```powershell
# Build the ImageComparer.Mcp project first (requires Visual Studio / MSBuild)
claude mcp add imagecomparer -- ./pwiz/pwiz_tools/Skyline/Executables/DevTools/ImageComparer.Mcp/bin/Debug/net8.0-windows/win-x64/ImageComparer.Mcp.exe
```

See [image-comparer.md](image-comparer.md) for tool documentation.

## Important Notes

**Path syntax:** Use relative paths with forward slashes (`./ai/mcp/...`), not absolute Windows paths. The `claude mcp add` command strips backslashes, turning absolute paths like `C:\proj\ai\...` into `C:projai...` which fails to connect.

**Restart required:** After registering new servers, restart Claude Code:
1. Exit Claude Code (`/exit`)
2. Resume with `claude --continue`

## Verify

Check that MCP servers are connected:
```powershell
claude mcp list
```

Expected output:
```
status: python ./ai/mcp/StatusMcp/server.py - ✓ Connected
labkey: python ./ai/mcp/LabKeyMcp/server.py - ✓ Connected
teamcity: python ./ai/mcp/TeamCityMcp/server.py - ✓ Connected (if configured)
gmail: npx @gongrzhe/server-gmail-autoauth-mcp - ✓ Connected (if configured)
```

## LabKey API Credentials

The LabKey MCP server needs credentials for skyline.ms access.

> **Existing machines**: Check if credentials are already configured:
> ```powershell
> Test-Path "$env:USERPROFILE\.netrc"
> Get-Content "$env:USERPROFILE\.netrc" | Select-String "skyline.ms"
> ```

There needs to be a separate skyline.ms user account using a special "+claude" version of your current email address:
- **Team members**: `yourname+claude@proteinms.net`
- **Interns/others**: `yourname+claude@gmail.com`
- The `+claude` suffix only works with Gmail-backed providers (not @uw.edu)
- **Ask an administrator** to create an account on skyline.ms for this "+claude" email and have them add it to the **Site:Agents** group

> **Why?** Individual +claude skyline.ms accounts provide attribution for any edits made via Claude, while the Site:Agents group has appropriate permissions for LLM agents.
> To be clear, you aren't creating a new email address - Google ignores the +claude part for routing purposes.

Once your +claude account is created, create a `.netrc` file:

```powershell
@"
machine skyline.ms
login yourname+claude@proteinms.net
password your-password-here
"@ | Out-File -FilePath "$env:USERPROFILE\.netrc" -Encoding ASCII
```

> **Deferring LabKey setup:** If you don't have a +claude account yet, use `-Skip netrc` when running `Verify-Environment.ps1`. The LabKey MCP server will still be registered but will have limited functionality until credentials are configured.
