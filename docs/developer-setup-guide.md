<!--
  Developer Environment Setup for AI-Assisted Development
  ========================================================
  This document is published to the AIDevSetup wiki page on skyline.ms.
  Audience: Human developers adding AI tooling to their Skyline development environment.

  The wiki page body is synced from this file. Use /pw-upconfig to update.
-->

# AI-Assisted Development Setup

This guide helps Skyline developers configure AI tooling for their development workflow.

## Our Recommended Toolset

The Skyline team has standardized on **Claude Code** for AI-assisted development, similar to how we standardize on **ReSharper** for code analysis. This provides:

- Consistent workflows across the team
- Shared skills and commands
- Integration with our MCP servers (LabKey, Status)
- Documentation optimized for Claude Code patterns

**External contributors** are welcome to use other tools (Cursor, VS Code + Copilot, etc.)—the codebase works with any IDE. However, some team-specific tooling (MCP servers, slash commands) is Claude Code-specific.

---

## Complete Setup

### Option A: New Machine

Follow the [NewMachineBootstrap](https://skyline.ms/home/software/Skyline/wiki-page.view?name=NewMachineBootstrap) guide to install Git and Claude Code, then let Claude Code guide you through the rest.

### Option B: Existing Development Machine

If you already have a working Skyline build environment (via [HowToBuildSkylineTip](https://skyline.ms/home/software/Skyline/wiki-page.view?name=HowToBuildSkylineTip)), you can add AI tooling by installing Claude Code and letting it configure the rest.

**Note that the following commands must be executed in a PowerShell terminal** - not in "cmd".

**Install Claude Code:**
```powershell
irm https://claude.ai/install.ps1 | iex
```

If `claude` isn't recognized after install, add it to PATH:
```powershell
$claudePath = "$env:USERPROFILE\.local\bin"
[Environment]::SetEnvironmentVariable("Path", [Environment]::GetEnvironmentVariable("Path", "User") + ";$claudePath", "User")
```

Close and reopen your terminal, then start Claude Code:
```powershell
cd C:\proj    # or wherever your pwiz checkout is
claude
```

Once authenticated, paste this prompt:

```
Help me configure AI tooling for Skyline development.

Fetch and follow the instructions at:
https://raw.githubusercontent.com/ProteoWizard/pwiz-ai/master/docs/new-machine-setup.md

This is an EXISTING development machine - I already have Visual Studio, Git, and a working Skyline build environment.

Check each component and only install what's missing.
```
**Note that there's an assumption that you have a copy of master checked out at c:\proj\pwiz.** That's pretty standard for the team, but if that's not how you work - for example if you work under d:\dev and you keep master in a folder d:\dev\master_clean - then add something like this to the prompt:

```Note that I work in D:\dev, not C:\proj - and when I check out master, I put it in D:\dev\master_clean, not D:\dev\pwiz```

Enter the prompt and Claude Code will check your environment and add only what's needed.

Keep in mind that you aren't just running a simple script, so if things start to go sideways (e.g. Claude can't find python, or forgets the URL for pwiz-ai repo etc) just have a conversation with Claude and the two of you will get back on track eventually.

### Option C: Quick Verification

If you have the AI tooling repository cloned, verify your environment:

```powershell
pwsh -Command "& './ai/scripts/Verify-Environment.ps1'"
```

Any `[MISSING]` items will show the command needed to fix them.

---

## Using Other AI Tools

If you prefer Cursor, VS Code + Copilot, or another AI-assisted IDE:

### What Works Everywhere

- All Skyline code, tests, and documentation
- Build scripts in `ai/scripts/Skyline/`
- Style guide: `ai/STYLEGUIDE.md`
- Critical rules: `ai/CRITICAL-RULES.md`

### Claude Code-Specific Features

These require Claude Code and won't work in other tools:

- **Slash commands** (`/pw-daily`, `/pw-commit`, etc.)
- **Skills** (context-loading prompts)
- **MCP servers** (LabKey, Status, Gmail integration)
- **Statusline** (custom status display)

### Generic Prompt for Other Tools

For Cursor, Copilot Chat, or similar tools, use this prompt to load context:

```
You are working on the Skyline mass spectrometry application (C#/.NET).

Before making changes, read these files:
- ai/CRITICAL-RULES.md - Absolute constraints (NO async/await, resource strings, etc.)
- ai/STYLEGUIDE.md - Coding conventions
- ai/MEMORY.md - Project context and gotchas

Build with: pwsh -Command "& './ai/scripts/Skyline/Build-Skyline.ps1'"
Test with: pwsh -Command "& './ai/scripts/Skyline/Run-Tests.ps1' -TestName <TestName>"
```

---

## IDE-Specific Configuration

### VS Code / Cursor Terminal Settings

Add to `.vscode/settings.json`:

```json
{
  "terminal.integrated.defaultProfile.windows": "PowerShell",
  "terminal.integrated.env.windows": {
    "LANG": "en_US.UTF-8",
    "LC_ALL": "en_US.UTF-8"
  }
}
```

### Recommended Extensions

- **C# Dev Kit** - C# language support
- **PowerShell** - Script editing
- **Markdown All in One** - Documentation preview

### Browser Markdown Viewer

For viewing `ai/` documentation in a browser:

1. Install [Markdown Reader](https://chromewebstore.google.com/detail/markdown-reader/medapdbncneneejhbgcjceippjlfkmkg) (Chrome/Edge)
2. Click Extensions icon → Markdown Reader → "⋮" → Manage Extension
3. Enable **"Allow access to file URLs"** (critical - won't work without this)

---

## Resources

- **New machine setup**: [NewMachineBootstrap](https://skyline.ms/home/software/Skyline/wiki-page.view?name=NewMachineBootstrap)
- **Build environment**: [HowToBuildSkylineTip](https://skyline.ms/home/software/Skyline/wiki-page.view?name=HowToBuildSkylineTip)
- **Claude Code documentation**: [docs.anthropic.com/claude-code](https://docs.anthropic.com/en/docs/claude-code)

---

## Feedback

If you discover improvements to the AI-assisted workflow, update the documentation in the `ai/` repository. Keeping documentation current helps every developer stay productive.
