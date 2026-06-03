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

The plugin's `workspaceFolder` is set to `${CLAUDE_PROJECT_DIR}/pwiz/pwiz_tools`,
and the launcher script is referenced as
`${CLAUDE_PROJECT_DIR}/ai/scripts/lsp/Invoke-RoslynLsp.ps1`.
`${CLAUDE_PROJECT_DIR}` is the directory Claude Code was launched from, which in
sibling mode is the project root containing both `ai/` and `pwiz/`. This makes the
plugin **path-independent**: it works unchanged whether the project root is
`C:\proj`, `D:\Dev`, `E:\repos`, or anything else, as long as the developer
launches Claude Code from that root (which the root `CLAUDE.md` already requires).

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

## Sibling pwiz clones

The default scope (`${CLAUDE_PROJECT_DIR}/pwiz/pwiz_tools`) covers the primary
`pwiz/` clone only. For other clones (`skyline_26_1/`, etc.), the LSP server is
NOT active. Two options:

1. Edit `plugin.json` to point at a different clone's `pwiz_tools` directory.
2. Create a personal sibling plugin with its own `workspaceFolder`.

A dynamic-workspace switcher is not feasible today: Roslyn LSP's workspace is
set via LSP `initialize`, not a CLI arg, so the sentinel-file design we used
for csharp-ls does not apply.

## Conflicts

Only one C# LSP plugin can be active at a time. Disable the official one before
installing this:

```
/plugin disable csharp-lsp@claude-plugins-official
/plugin install csharp-lsp@pwiz-lsp
/reload-plugins
```

Two C# LSP servers competing on `.cs` would fight each other.
