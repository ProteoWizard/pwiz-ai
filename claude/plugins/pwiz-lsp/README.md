# pwiz-lsp marketplace

Claude Code plugin marketplace for the pwiz-area Language Server configuration.
Lives in the pwiz-ai repository so the team shares patterns, naming, and docs.

## Plugins

| Plugin | Purpose |
|---|---|
| `csharp-lsp` | C# LSP via Microsoft.CodeAnalysis.LanguageServer (Roslyn LSP from the VS Code C# extension). Workspace is `${PWIZ_LSP_DIR:-${CLAUDE_PROJECT_DIR}/pwiz/pwiz_tools}` (PWIZ_LSP_DIR is the full `pwiz_tools` path; set it per checkout in multi-checkout layouts — see [`csharp-lsp/README.md`](csharp-lsp/README.md#selecting-the-workspace)). Covers Skyline, Osprey, AutoQC, SkylineBatch, Shared, etc. Handles both .NET Framework 4.7.2 and modern .NET. |

## Install

Replaces the official `csharp-lsp@claude-plugins-official` plugin (which uses
`csharp-ls`, a community server that cannot load .NET Framework projects).

```
/plugin disable csharp-lsp@claude-plugins-official
/plugin marketplace add C:/proj/ai/claude/plugins/pwiz-lsp
/plugin install csharp-lsp@pwiz-lsp
/reload-plugins
```

Prerequisite: VS Code with the C# extension (`ms-dotnettools.csharp`).
The LSP server binary ships inside that extension. See
[`csharp-lsp/README.md`](csharp-lsp/README.md) for details.

## Why this exists

1. The official `csharp-lsp@claude-plugins-official` uses `csharp-ls`, which
   only discovers .NET SDK MSBuild instances and silently fails on any
   .NET Framework 4.7.2 project. That covers Skyline (~900 KLOC), AutoQC,
   SkylineBatch, and most of pwiz_tools.
2. Microsoft.CodeAnalysis.LanguageServer handles both .NET Framework and modern
   .NET in the same workspace via separate `BuildHost-net472` and
   `BuildHost-netcore` runners.
3. Centralizing the wrapper script (`ai/scripts/lsp/Invoke-RoslynLsp.ps1`) means
   one place to handle VS Code C# extension path discovery, log directory
   placement, and any future LSP launch tweaks.
