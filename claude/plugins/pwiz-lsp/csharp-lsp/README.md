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

The plugin's `workspaceFolder` is set to `C:/proj/pwiz/pwiz_tools`. The server
indexes:

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
- Several minutes for full first-load indexing

If memory becomes a problem, `/plugin disable csharp-lsp@pwiz-lsp` and rely on
grep until needed.

## Sibling pwiz clones

The default scope (`C:/proj/pwiz/pwiz_tools`) covers the primary pwiz clone only.
For other clones (`skyline_26_1/`, etc.), the LSP server is NOT active. Two
options:

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
