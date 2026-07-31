# MCP Server Setup

How to set up all MCP servers for Claude Code. Referenced from [new-machine-setup.md](../new-machine-setup.md) Phase 7.

## Prerequisites

- Python 3.10+ with `pip`
- Claude Code installed
- Project cloned with `ai/` junction configured

Install Python packages:
```powershell
pip install "mcp<2" labkey Pillow
```

> **Pin `mcp` below 2.0.** mcp 2.0.0 removed `mcp.server.fastmcp`, which every server here imports.
> An unpinned install makes StatusMcp and LabKeyMcp crash at startup, and `claude mcp list` reports
> only `✘ Failed to connect — -32000: Connection closed`. Confirm the real cause by running a server
> directly (`python ./ai/mcp/StatusMcp/server.py`), then fix with `pip install "mcp<2"`.
> Verified 2026-07-30: 1.29.0 works, 2.0.0 does not.

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

> **For LLM assistants:** Do not just create the `.teamcity-mcp` folder and tell the developer
> to "add a config.json" — that leaves someone who has never seen the TeamCity UI with no idea
> what to click or where the file goes. Create the **template file with the placeholder in it**
> (step 2), then walk them through the web UI (step 1). Never ask for the token itself, and
> never write a file containing a real token — the developer pastes it into the template.
> If a config file already exists, **do not overwrite it**: it holds a live credential.

1. **Create a TeamCity API token** (in the browser):
   - Go to `https://teamcity.labkey.org` and sign in.
   - Click your **profile icon in the LOWER-LEFT corner** → **Profile**.
     (It is bottom-left, not top-right as on most sites — this is the step people miss.)
   - In the left sidebar choose **Access Tokens** → **Create access token**.
   - Name it `Claude Code MCP`. **Permissions: "Same as current user" / read-only is enough** —
     triggering a build counts as read-only usage of the REST API here.
   - Optionally set an expiry. If you set one, note it: an expired token fails exactly like a
     wrong one (see troubleshooting below).
   - Click **Create**, then **copy the token immediately**. TeamCity shows it **once** and never
     again. Store it in a password manager.

2. **Create the config template, then paste the token into it:**
   ```powershell
   New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.teamcity-mcp" | Out-Null
   @'
   {
     "url": "https://teamcity.labkey.org",
     "token": "PASTE_YOUR_TOKEN_HERE"
   }
   '@ | Set-Content "$env:USERPROFILE\.teamcity-mcp\config.json" -Encoding utf8
   notepad "$env:USERPROFILE\.teamcity-mcp\config.json"
   ```
   Replace `PASTE_YOUR_TOKEN_HERE` with the token, keeping the surrounding quotes. Save.

3. **Register** (from the **project root** — registration is per-project; see the scope note in
   `new-machine-setup.md` Phase 7.2):
   ```powershell
   claude mcp add teamcity -- python ./ai/mcp/TeamCityMcp/server.py
   ```

4. **Restart** Claude Code / Claude Desktop. MCP servers and their config are read at session
   start, so a newly added server never appears mid-session.

5. **Verify** — this catches a bad token in seconds instead of at the moment you need a build:
   ```powershell
   python -c "import json,os,urllib.request;c=json.load(open(os.path.expanduser(r'~\.teamcity-mcp\config.json')));r=urllib.request.urlopen(urllib.request.Request(c['url'].rstrip('/')+'/app/rest/server',headers={'Authorization':'Bearer '+c['token'],'Accept':'application/json'}),timeout=20);print('AUTH OK',json.load(r).get('version'))"
   ```

### Troubleshooting: HTTP 401 Unauthorized

The server registers and starts fine but every tool returns `401 Unauthorized`.

**401 means the credential was rejected, not that anything is misconfigured.** Confirm the file
itself is sound before touching the MCP setup — a valid TeamCity token is a 3-part
dot-separated value whose first segment decodes to `{"typ": "TCV2"}`:

```powershell
python -c "import json,os,base64;t=json.load(open(os.path.expanduser(r'~\.teamcity-mcp\config.json')))['token'];print('segments',[len(x) for x in t.split('.')]);print('header',base64.b64decode(t.split('.')[0]+'==').decode('utf-8','replace'))"
```

Expect three segments and `{"typ": "TCV2"}`. If you get that and still see 401, the file is
fine and the **token is revoked, expired, or from a different TeamCity server** — regenerate it
(step 1). A single mistyped character produces exactly this symptom, because the structure
still validates.

Note the token is standard base64, so `+` and `/` are normal characters — do not "fix" them.

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
