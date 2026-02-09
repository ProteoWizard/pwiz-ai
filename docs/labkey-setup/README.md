# LabKey Server Development Environment Setup

**For LLM Assistants (Claude Code)**

This is a modular, token-efficient setup guide for Windows LabKey development.

## Quick Start

1. **Initialize**: Read this file and create `state.json`
2. **Load phase**: Read only the current phase file from `phases/`
3. **Track progress**: Update `state.json` after each step
4. **Resume**: Read `state.json` (not this file) to continue

## Assistant Behavior Rules

### Message Ordering (CRITICAL)

Tool output (Bash results, file writes) pushes earlier text off the user's
screen. Any message the user needs to see — status updates, instructions,
resume checkpoints — **MUST be output AFTER all tool calls complete.**

Never place user-facing text before a tool call that follows it.

Pattern for every step:
1. Run all tool calls silently (commands, state updates, file reads)
2. Output everything the user needs to see in a single block at the end

### Pre-install briefing for interactive installers (CRITICAL)
Before launching ANY interactive installer (one that opens a GUI), you MUST:
  1. List the important choices or settings the user will encounter in the installer
  2. Explain what to select for each choice and why
  3. Ask the user to confirm they are ready before launching the installer

Do NOT launch the installer first and then describe the steps — the user may have already clicked past the relevant screens. The briefing must come BEFORE the install command.


### State Management

- **Before every state.json update**, output a message to the user: "Let me update the state file..."
- **Initial creation** (Phase 0): Use the Write tool to create state.json since it doesn't exist yet.
- **All subsequent updates**: Use the Edit tool to update `state.json`:
  1. Read the current state.json first
  2. Use Edit tool with old_string = entire current content, new_string = entire updated content
  3. This shows a diff of changes and allows the user to select "always allow" to reduce permission prompts
- **After successful edit**, output a confirmation message: "State file updated successfully."
- Update state.json after each completed step.
- Track: current phase/step, completed items, deferred items, version choices.
- On resume: read state.json first. It is the source of truth. Announce the
  current phase, then **wait for the user to type "continue"** before proceeding.

### Command Execution

- Run ALL commands yourself via the Bash tool (uses Git Bash on Windows).
- PowerShell commands: `powershell.exe -Command "your-command"`
- Verify env vars from registry:
  `powershell.exe -Command "[System.Environment]::GetEnvironmentVariable('VAR', 'Machine')"`
- **User only runs:** GUI installers, interactive prompts, long builds/tests (15+ min).

### Interaction

- Ask questions, **wait for answers**, then proceed. Never run steps in parallel
  that depend on user input.
- Show progress after each phase: `✅ Done | 🔄 Current | ⬜ Pending`
- After showing progress, **confirm with the user** that they are ready before
  loading and starting the next phase. Do not auto-advance.
- On terminal restart: update state.json first, THEN output the resume checkpoint.
  The checkpoint must include the full resume command and instructions:
  ```
  To resume: cd "<setup_root>" && claude --resume
  When the session resumes, type "continue" to proceed.
  ```
  Use `setup_root` from state.json — that's where `CLAUDE.md` lives.

### Phase Loading

- Each phase is self-contained in `phases/phase-N-name.md`.
- Load reference docs from `reference/` only when needed.
- Never load all phases at once.

### Windows Environment

- Git Bash doesn't understand PowerShell syntax — wrap in `powershell.exe -Command`.
- UAC prompts require the user to click "Yes".
- New env vars need a terminal restart OR must be read from registry.

## Workflow Phases

1. **Getting Started** - Version selection, environment check
2. **Core Setup** - Java, Git, SSH
3. **PostgreSQL** - Database installation
4. **Repository Setup** - Clone LabKey repos
5. **Gradle Configuration** - Build settings
6. **Initial Build** - First deployApp
7. **IntelliJ Setup** - IDE configuration
8. **Running LabKey Server** - Start LabKey
9. **Test Setup** - UI test configuration
10. **Developer Tools** - Optional tools (Notepad++, WinMerge, TortoiseGit, GitHub CLI)

## State File Structure

```json
{
  "version": "1.0",
  "created": "2026-02-04T00:00:00Z",
  "labkey_version": "25.11",
  "java_version": 17,
  "postgres_version": 17,
  "setup_root": "C:\\labkey\\labkey-setup",
  "labkey_root": "C:\\labkey-dev\\release25.11",
  "current_phase": 1,
  "current_step": "1.1",
  "completed": ["phase-0", "phase-1-step-1.1"],
  "deferred": ["phase-9-notepad++"],
  "environment_check": {
    "completed": true,
    "missing_required": ["PostgreSQL"],
    "missing_optional": ["GitHub CLI"],
    "needs_update": []
  },
  "optional_tools": {
    "notepad++": false,
    "winmerge": false,
    "tortoisegit": false,
    "github_cli": false
  },
  "notes": []
}
```

## Prerequisites

- **Claude Code** - Installed and authenticated
- **Git** - Required by Claude Code (provides Git Bash)
- **Working directory** - Launch Claude Code from **this directory** (the
  `labkey-setup` folder containing this README). Claude Code automatically
  reads the `CLAUDE.md` here on every session, including resumes — that is
  what triggers `state.json` management and keeps sessions continuous.
  Starting from a different directory will break resume.

## Final Report

After Phase 9 (Developer Tools) completes, generate a setup report at
`setup-report.md` in this directory:

- Phase-by-phase status: DONE | DEFERRED | SKIPPED
- List of deferred items
- Issues encountered and how they were resolved
- Recommendations

### Friction Points

While writing the report, review the full session for any step where:
- A command failed or produced unexpected output
- The user had to ask for clarification (the docs were ambiguous)
- A verification check didn't match what was documented
- A warning or error appeared that the docs didn't anticipate
- A prerequisite was missing or steps felt out of order

Collect these into a **Friction Points** section at the end of the report.

### Offer to Update Phase Docs

After presenting the report, if any friction points were identified, offer
to update the affected phase documents:

> "I found [N] friction point(s) during this setup. Here's what I'd change:
> - Phase X, Step Y.Z: [one-line description]
> - ...
> Want me to update those phase documents?"

**Wait for confirmation** before making any changes. Update only the specific
steps that had friction — do not rewrite or reorganize unrelated content.

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
