# csharp-lsp

C# language server for pwiz-area C# projects, using **Microsoft.CodeAnalysis.LanguageServer**
(the Roslyn-based LSP server bundled with the VS Code C# extension).

## Why Roslyn LSP, not csharp-ls

The previous design used `csharp-ls` (community Roslyn-based server). It cannot
load .NET Framework 4.7.2 projects because it only discovers .NET SDK MSBuild
instances and never finds the Visual Studio MSBuild needed for .NET Framework
targets. Confirmed empirically: csharp-ls 0.24.0 fails on Skyline.sln, AutoQC.sln,
and SkylineBatch.sln (all .NET Framework 4.7.2). OspreySharp.sln (.NET 8) was the
only pwiz solution it could load.

Microsoft.CodeAnalysis.LanguageServer bundles both `BuildHost-net472` and
`BuildHost-netcore` runtimes, so it handles .NET Framework and modern .NET in the
same workspace.

## Prerequisites

VS Code installed, with the C# extension (`ms-dotnettools.csharp`). The LSP
server lives at:

```
%USERPROFILE%\.vscode\extensions\ms-dotnettools.csharp-<version>-<arch>\.roslyn\Microsoft.CodeAnalysis.LanguageServer.exe
```

The wrapper script (`ai/scripts/lsp/Invoke-RoslynLsp.ps1`) discovers the latest
extension version dynamically, so VS Code C# extension updates do not break the
plugin.

You do NOT need to use VS Code to edit code - the extension just provides the
LSP binary.

## Scope

The plugin's `workspaceFolder` is `${PWIZ_LSP_DIR:-${CLAUDE_PROJECT_DIR}/pwiz/pwiz_tools}`
(`PWIZ_LSP_DIR` is the full `pwiz_tools` path), and the launcher script is referenced as
`${CLAUDE_PROJECT_DIR}/ai/scripts/lsp/Invoke-RoslynLsp.ps1`.
`${CLAUDE_PROJECT_DIR}` is the directory Claude Code was launched from — the
project root containing `ai/` and the C# checkout(s). This makes the plugin
**path-independent**: it works unchanged whether the project root is `C:\proj`,
`D:\Dev`, `E:\repos`, or anything else, as long as the developer launches Claude
Code from that root (which the root `CLAUDE.md` already requires). Which checkout
gets indexed is chosen by `PWIZ_LSP_DIR` — see
[Selecting the workspace](#selecting-the-workspace) below.

> **Why `${CLAUDE_PROJECT_DIR}` and not `${CLAUDE_PLUGIN_ROOT}`?** Claude Code
> expands both inside `lspServers` config. `${CLAUDE_PLUGIN_ROOT}` points at this
> plugin's install dir (`ai/claude/plugins/pwiz-lsp/csharp-lsp`), but the launcher
> script lives outside it (in `ai/scripts/`), so anchoring on the plugin root would
> require fragile `../../../..` traversal that Claude Code's docs do not define for
> `workspaceFolder`. `${CLAUDE_PROJECT_DIR}` reaches both the script and the
> workspace with no `..` segments.

The server indexes:

- `Skyline/` (Skyline.sln, ~900 KLOC of C#)
- `OspreySharp/` (.NET 8 port of osprey)
- `Skyline/Executables/AutoQC/`, `SkylineBatch/`, etc.
- `Shared/` (CommonUtil, PanoramaClient, etc.)

Cross-project navigation works (e.g., Skyline references to `Shared/CommonUtil`
resolve as expected).

## Memory and indexing

Expect:
- ~1.3 GB resident after Skyline.sln finishes indexing
- 2-3 GB resident with all pwiz_tools projects loaded
- **First-load indexing of the full `pwiz_tools` workspace can take tens of
  minutes**, not just "a few minutes." Plan for a slow first load; subsequent
  sessions reuse cached state and are much faster.

### Telling "still indexing" from "done" from "stuck"

Do **not** judge readiness from process CPU/memory deltas alone — they are
ambiguous:

- **Healthy, done indexing:** the process sits at a stable 1.3-3 GB with CPU no
  longer climbing. A flat plateau here means *idle, ready for queries* — NOT
  stuck. (This is the state that previously got misread as "hung.")
- **Still indexing:** memory climbs slowly and CPU ticks up over many minutes.
  Low-but-nonzero CPU growth is normal during a large first load.
- **Genuinely stuck:** the process *starts* at ~150-270 MB and never rises, with
  no CPU growth from the outset. That is the csharp-ls-on-.NET-Framework failure
  mode. If you see it on the Roslyn server, confirm the VS Code C# extension is
  installed and the `.roslyn/Microsoft.CodeAnalysis.LanguageServer.exe` binary
  exists (see Prerequisites), and that a compatible .NET runtime is installed
  (the server's `runtimeconfig.json` pins a specific major version — e.g. .NET 10
  for C# extension 2.120.x; a missing runtime crashes the host with exit code 150).

**The definitive readiness test is a query, not a metric.** A query like
`findReferences` on `SrmDocument` should return **several thousand references
across hundreds of files** once the workspace is fully loaded. If the *first*
query right after startup returns only same-file references (e.g. ~100 hits all
in `SrmDocument.cs`), that is a partial index still loading — re-run the query
after indexing finishes; it is not a misconfiguration.

If memory becomes a problem, `/plugin disable csharp-lsp@pwiz-lsp` and rely on
grep until needed.

## Selecting the workspace

Roslyn LSP indexes exactly one workspace folder, fixed when the server starts
(it is set via LSP `initialize`, not a CLI arg, so it cannot be switched
in-session — the sentinel-file design we used for csharp-ls does not apply). The
plugin resolves that folder from the `PWIZ_LSP_DIR` environment variable, with a
fallback:

```jsonc
"workspaceFolder": "${PWIZ_LSP_DIR:-${CLAUDE_PROJECT_DIR}/pwiz/pwiz_tools}"
```

`PWIZ_LSP_DIR` is the **full `pwiz_tools` path** (not the checkout root): the
`pwiz` segment belongs only to the single-clone fallback, where the clone is
literally named `pwiz`. In multi-checkout layouts the clone is named something
else (e.g. `IMoffset`) and contains `pwiz_tools` directly, so there is no `pwiz`
segment — which is why it lives inside the `:-` default, not after the variable.

- **Single-clone layout** (one `pwiz/` clone beside `ai/`): do nothing.
  `PWIZ_LSP_DIR` stays unset and the workspace falls back to
  `${CLAUDE_PROJECT_DIR}/pwiz/pwiz_tools` — the original zero-config behavior.
- **Multi-checkout layout** (many named clones beside `ai/` — e.g. `BugFix/`,
  `IMoffset/`, `master_clean/` — and no `pwiz/` folder): set `PWIZ_LSP_DIR` to
  that checkout's `pwiz_tools` folder *before* launching Claude Code (the
  `skyclaude` helper does this for you). Each session is
  typically dedicated to one checkout, so per-session scoping fits naturally and
  avoids mid-session reindex churn.

`ai/scripts/lsp/Enable-PwizLsp.ps1` provides a launcher that sets the variable.
Dot-source it from your PowerShell `$PROFILE` (use your own project root):

```powershell
. C:\Dev\ai\scripts\lsp\Enable-PwizLsp.ps1
$PwizLspDefault = 'master_clean'   # optional: checkout for a no-arg launch
```

Then start Claude Code with `skyclaude` instead of `claude`:

```powershell
skyclaude IMoffset   # scope the C# LSP to <root>\IMoffset\pwiz_tools, then launch
skyclaude            # use $PwizLspDefault (multi-checkout) or the 'pwiz' fallback
```

> **Note on the nested default.** `${VAR:-default}` is documented for `.mcp.json`
> and LSP config claims parity, but a *nested* `${CLAUDE_PROJECT_DIR}` inside the
> default is not separately documented. Multi-checkout machines always set
> `PWIZ_LSP_DIR`, so they are unaffected. If a single-clone machine ever indexes
> nothing on a bare `claude`, set `PWIZ_LSP_DIR` explicitly (or just use
> `skyclaude`), and confirm the resolved workspace in the Roslyn log under
> `ai/.tmp/state/roslyn-logs/`.

## Conflicts

Only one C# LSP plugin can be active at a time. Disable the official one before
installing this:

```
/plugin disable csharp-lsp@claude-plugins-official
/plugin install csharp-lsp@pwiz-lsp
/reload-plugins
```

Two C# LSP servers competing on `.cs` would fight each other.

## Updating the plugin (cache staleness)

`/plugin install` copies the plugin into a **cache** under
`~/.claude/plugins/cache/pwiz-lsp/csharp-lsp/<version>/`, and Claude Code runs the
LSP server from that cached copy — NOT from the source in this repo. So editing
`plugin.json` here (or pulling new pwiz-ai commits that change it) does **not**
affect the running plugin until you refresh the cache:

```
/plugin marketplace update pwiz-lsp
/plugin install csharp-lsp@pwiz-lsp
/reload-plugins
```

This is a real trap: a `git pull` that bumps the plugin version looks applied but
isn't until the cache is refreshed. A fresh `/plugin install` on a new machine
always gets the latest version, so this only bites machines that installed an
earlier version. (`Verify-Environment.ps1` reports the cached version, so compare
it against this plugin's `version` in `plugin.json` if in doubt.)
