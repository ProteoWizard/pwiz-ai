# LabKey Development Setup

Modular, Claude Code–driven setup guide for LabKey Server development on Windows.

## Quick Start

1. `cd` into this directory
2. Run: `claude`
3. Say: "Help me set up the LabKey development environment"

Claude walks you through each phase automatically. Progress is saved in
`state.json`, so you can pick up where you left off if the session ends.

## Directory Layout

```
labkey-setup/
├── CLAUDE.md                         # Auto-loaded by Claude Code each session
├── README.md                         # Main guide and assistant behavior rules
├── state-template.json               # Template for progress tracking
│
├── phases/                           # One file per setup phase
│   ├── phase-0-getting-started.md
│   ├── phase-1-core-setup.md
│   ├── phase-2-postgresql.md
│   ├── phase-3-repository-setup.md
│   ├── phase-4-gradle-config.md
│   ├── phase-5-initial-build.md
│   ├── phase-6-intellij-setup.md
│   ├── phase-7-running-server.md
│   ├── phase-8-test-setup.md
│   └── phase-9-developer-tools.md
│
├── reference/                        # Supplementary docs, loaded on demand
│   ├── design-rationale.md           # Why this is modular instead of single-file
│   ├── gradle-commands.md
│   ├── troubleshooting.md
│   ├── modules.md
│   └── final-report-template.md
│
└── scripts/
    └── Verify-LabKeyEnvironment.ps1  # Pre-setup environment check
```

## Setup Phases

1. **Getting Started** — Version selection, environment check
2. **Core Setup** — Java, Git, SSH
3. **PostgreSQL** — Database installation
4. **Repository Setup** — Clone LabKey and MacCoss repos
5. **Gradle Configuration** — Build settings
6. **Initial Build** — First `deployApp`
7. **IntelliJ Setup** — IDE configuration
8. **Running Server** — Start and verify LabKey
9. **Test Setup** — UI test environment (optional)
10. **Developer Tools** — Optional tools (Notepad++, WinMerge, TortoiseGit, GitHub CLI)

## Target Environment

- **OS**: Windows 10/11
- **LabKey**: 25.x or 26.x
- **Java**: 17 (LabKey 25.x) or 25 (LabKey 26.x)
- **Database**: PostgreSQL 17 or 18
- **IDE**: IntelliJ IDEA (Community or Ultimate)

## Further Reading

- `README.md` — Entry point for Claude Code; contains assistant behavior rules

## Resources

- [LabKey Developer Docs](https://www.labkey.org/Documentation/wiki-page.view?name=devMachine)
- [MacCoss Lab Wiki](https://skyline.ms/home/development/)
- [Supported Technologies](https://www.labkey.org/Documentation/wiki-page.view?name=supported)
