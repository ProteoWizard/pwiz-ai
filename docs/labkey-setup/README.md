# LabKey Server Development Environment Setup

**For LLM Assistants (Claude Code)**

This is a modular, token-efficient setup guide for Windows LabKey development.

## Quick Start

1. **Initialize**: Read this file and create `state.json`
2. **Load phase**: Read only the current phase file from `phases/`
3. **Track progress**: Update `state.json` after each step
4. **Resume**: Read `state.json` (not this file) to continue

## Assistant Behavior Rules

**Command Execution:**
- Run ALL commands yourself via Bash tool (uses Git Bash on Windows)
- PowerShell commands: `powershell.exe -Command "your-command"`
- After PowerShell 7 installed: `pwsh -Command "your-command"`
- Verify env vars from registry: `powershell.exe -Command "[System.Environment]::GetEnvironmentVariable('VAR', 'Machine')"`
- User only runs: GUI installers, interactive prompts, long builds/tests (15+ min)

**Interaction:**
- Ask questions, WAIT for answers, then proceed (sequential, not parallel)
- Show progress after each phase: `✅ Done | 🔄 Current | ⬜ Pending`
- On terminal restart: Output resume checkpoint, update state.json
- On resume: Read state.json and announce current phase

**Phase Files:**
- Each phase is self-contained in `phases/phase-N-name.md`
- Load reference docs from `reference/` only when needed
- Never load all phases at once

**State Management:**
- Update `state.json` after each completed step
- Track: current phase/step, completed items, deferred items, version choices
- On resume, state.json is source of truth

## Workflow Phases

1. **Getting Started** - Version selection, environment check
2. **Core Setup** - PowerShell 7, Java, Git, SSH
3. **PostgreSQL** - Database installation
4. **Repository Setup** - Clone LabKey repos
5. **Gradle Configuration** - Build settings
6. **Initial Build** - First deployApp
7. **IntelliJ Setup** - IDE configuration
8. **Running Server** - Start LabKey
9. **Test Setup** - UI test configuration
10. **Developer Tools** - Optional tools (Notepad++, WinMerge, TortoiseGit, GitHub CLI)

## State File Structure

```json
{
  "version": "1.0",
  "labkey_version": "25",
  "java_version": 17,
  "postgres_version": 17,
  "current_phase": 1,
  "current_step": "1.1",
  "completed": ["phase-0", "phase-1-step-1.1"],
  "deferred": ["phase-9-notepad++"],
  "notes": []
}
```

## Windows Environment Notes

- Use `powershell.exe` (not `pwsh`) until PowerShell 7 installed
- Git Bash doesn't understand PowerShell syntax - wrap in `powershell.exe -Command`
- UAC prompts require user to click "Yes"
- New env vars need terminal restart OR read from registry

## Prerequisites

- **Claude Code** - Installed and authenticated
- **Git** - Required by Claude Code (provides Git Bash)

## Final Report

After phase 10, generate markdown report:
- Phase-by-phase status: DONE | DEFERRED | SKIPPED
- List of deferred items
- Issues encountered
- Recommendations

## Success Criteria

Setup complete when:
- Correct Java version in PATH and JAVA_HOME set
- PostgreSQL running and accessible
- All repos cloned with correct structure
- `.\gradlew deployApp` succeeds
- IntelliJ opens project and resolves dependencies
- Server accessible at http://localhost:8080/
- MacCoss modules visible in Module Information

## Resources

- [LabKey Developer Docs](https://www.labkey.org/Documentation/wiki-page.view?name=devMachine)
- [MacCoss Lab Build Notes](https://skyline.ms/home/development/wiki-page.view?name=build_and_deploy)
- [Supported Technologies](https://www.labkey.org/Documentation/wiki-page.view?name=supported)
