# LabKey Development Setup (Refactored)

**Token-efficient, modular setup workflow for Claude Code**

## What This Is

A refactored version of the LabKey development environment setup guide, optimized to reduce Claude Code's token usage by **83%** through modular architecture and state-based progress tracking.

## Problem Solved

**Before**: Single 51KB document consumed ~36,000 tokens over a typical setup workflow
**After**: Modular design consumes ~6,000 tokens for the same workflow

**Savings**: 30,000 tokens per complete setup (83% reduction)

## Package Contents

```
labkey-setup/
├── README.md                        # Main entry point (150 lines)
├── CLAUDE-USAGE.md                  # How Claude Code uses this
├── MIGRATION-GUIDE.md               # Old vs New comparison
├── state-template.json              # Progress tracking template
│
├── phases/                          # One file per phase (50-100 lines each)
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
├── reference/                       # Load on-demand (50-150 lines each)
│   ├── gradle-commands.md
│   ├── troubleshooting.md
│   ├── modules.md
│   └── final-report-template.md
│
└── scripts/
    └── Verify-LabKeyEnvironment.ps1
```

## How It Works

### For Users
No changes needed! Just say: "Help me setup LabKey development environment"

Claude Code will:
1. Read the main README (700 tokens)
2. Load phases one at a time as needed (500-700 tokens each)
3. Track progress in state.json (200 bytes)
4. Load reference docs only when needed (on-demand)

### For Claude Code
1. Start: Read `README.md`
2. Create `state.json` from template
3. Execute phases sequentially (read one file at a time)
4. Update state after each step
5. Load reference docs as needed
6. Generate final report from template

**See CLAUDE-USAGE.md for detailed workflow**

## Token Usage Breakdown

| Phase | File Size | Token Cost |
|-------|-----------|------------|
| README (start) | 3KB | 700 |
| Phase 0 | 2KB | 500 |
| Phase 1 | 3KB | 700 |
| Phase 2 | 2KB | 400 |
| Phase 3 | 2.5KB | 600 |
| Phase 4 | 2KB | 500 |
| Phase 5 | 2KB | 400 |
| Phase 6 | 3KB | 600 |
| Phase 7 | 2.5KB | 550 |
| Phase 8 | 3KB | 650 |
| Phase 9 | 3.5KB | 750 |
| **Total** | **~27KB** | **~6,350** |

Compare to old single-file approach: 51KB = 12,000 tokens loaded 3+ times = 36,000+ tokens

## Key Features

### 1. Incremental Loading
Load only the phase you're currently working on (500-700 tokens vs 12,000)

### 2. State Persistence  
JSON state file tracks progress (200 bytes vs re-reading 12,000-token doc)

### 3. On-Demand References
Load Gradle commands, troubleshooting, module info only when needed

### 4. Resume Efficiency
After terminal restart: read 200-byte state file, not 12,000-token markdown

### 5. Maintainability
Update one small phase file instead of searching through 1,150-line document

## Setup Phases

1. **Getting Started** - Version selection, environment check
2. **Core Setup** - PowerShell 7, Java, Git, SSH
3. **PostgreSQL** - Database installation and configuration
4. **Repository Setup** - Clone LabKey and MacCoss repos
5. **Gradle Configuration** - Build settings
6. **Initial Build** - First deployApp
7. **IntelliJ Setup** - IDE configuration
8. **Running Server** - Start and verify LabKey
9. **Test Setup** - UI test environment (optional)
10. **Developer Tools** - Optional productivity tools

## Documentation

- **README.md** - Main entry point for Claude Code
- **CLAUDE-USAGE.md** - Detailed workflow for LLM assistants
- **MIGRATION-GUIDE.md** - Comparison with old format
- **Phase files** - Step-by-step instructions per phase
- **Reference files** - On-demand lookup guides

## Target Environment

- **OS**: Windows 10/11
- **LabKey**: 25.x or 26.x
- **Java**: 17 (LabKey 25.x) or 25 (LabKey 26.x)
- **Database**: PostgreSQL 17 or 18
- **IDE**: IntelliJ IDEA Community or Ultimate

## Quick Start

1. Give this entire directory to Claude Code
2. Say: "Help me setup LabKey development environment"
3. Claude reads README.md and guides you through phases
4. Progress tracked in state.json
5. Get final report after completion

## Benefits vs Original

| Metric | Original | Refactored | Improvement |
|--------|----------|------------|-------------|
| Initial load | 12,000 tokens | 700 tokens | 94% |
| Per phase | Cached | 500 tokens | - |
| Resume cost | 12,000 tokens | 200 tokens | 98% |
| Reference access | Loaded always | On-demand | 99% |
| Total workflow | 36,000 tokens | 6,000 tokens | 83% |
| Maintainability | Hard (1 big file) | Easy (modular) | Much better |

## Contributing

To update this workflow:
- **Phase changes**: Edit specific phase-N file
- **New commands**: Add to reference/gradle-commands.md
- **Troubleshooting**: Add to reference/troubleshooting.md  
- **Behavior changes**: Edit README.md rules section

## Version

**Version**: 1.0  
**Created**: February 2026  
**Based on**: LabKey dev setup guide (retrieved 2026-01-30)

## Resources

- [LabKey Developer Docs](https://www.labkey.org/Documentation/wiki-page.view?name=devMachine)
- [MacCoss Lab Wiki](https://skyline.ms/home/development/)
- [Supported Technologies](https://www.labkey.org/Documentation/wiki-page.view?name=supported)
