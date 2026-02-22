# AI Documentation Index - Detailed Guides

This directory contains comprehensive, detailed documentation for LLM-assisted development. These files are **unlimited in size** and provide encyclopedic detail.

**For quick reference, see the core files in [ai/](../)** - they're kept small (<200 lines) for fast loading.

## Available Guides

### Architecture

- **[architecture-data-model.md](architecture-data-model.md)** - Core data model architecture (immutable SrmDocument)
- **[architecture-error-handling.md](architecture-error-handling.md)** - Error handling patterns (user-actionable vs programming defects)
- **[architecture-files.md](architecture-files.md)** - File handle architecture (ConnectionPool, pooled streams, FileSaver)

### Setup

- **[developer-setup-guide.md](developer-setup-guide.md)** - Developer environment setup for AI-assisted development
- **[new-machine-bootstrap.md](new-machine-bootstrap.md)** - Quick start: pristine Windows to working dev environment
- **[new-machine-setup.md](new-machine-setup.md)** - Detailed new machine setup for LLM assistants
- **[new-machine-windows-install.md](new-machine-windows-install.md)** - Clean Windows installation and initial configuration
- **[labkey-setup/](labkey-setup/)** - LabKey Server development environment setup

### Development

- **[style-guide.md](style-guide.md)** - Comprehensive C# coding standards with full examples
- **[testing-patterns.md](testing-patterns.md)** - Testing patterns, AssertEx API, dependency injection
- **[build-and-test-guide.md](build-and-test-guide.md)** - Complete build and test command reference
- **[project-context.md](project-context.md)** - Full project context with detailed examples and gotchas
- **[debugging-principles.md](debugging-principles.md)** - Systematic debugging methodology

### Workflow

- **[workflow-guide.md](workflow-guide.md)** - Complete workflow guide with TODO templates and examples
- **[version-control-guide.md](version-control-guide.md)** - Git commit, PR, and branch management conventions
- **[release-guide.md](release-guide.md)** - Release management: versioning, workflows, automation
- **[release-cycle-guide.md](release-cycle-guide.md)** - Quick reference for the Skyline release cycle

### Tools

- **[skylinetester-guide.md](skylinetester-guide.md)** - Comprehensive SkylineTester reference
- **[skylinetester-debugging-guide.md](skylinetester-debugging-guide.md)** - Debugging hung tests, automated dev-build-test cycles
- **[leak-debugging-guide.md](leak-debugging-guide.md)** - Identifying and fixing handle leaks
- **[screenshot-update-workflow.md](screenshot-update-workflow.md)** - Tutorial screenshot review and update workflow

### Tutorials

- **[tutorial-doc-style-guide.md](tutorial-doc-style-guide.md)** - Style conventions for Skyline tutorial HTML
- **[translation-guide.md](translation-guide.md)** - Updating localized RESX files and translation tables

### AI System

- **[ai-repository-strategy.md](ai-repository-strategy.md)** - Strategy for the dedicated pwiz-ai repository
- **[documentation-maintenance.md](documentation-maintenance.md)** - Guide for maintaining this documentation system
- **[daily-report-guide.md](daily-report-guide.md)** - Generating daily consolidated reports
- **[scheduled-tasks-guide.md](scheduled-tasks-guide.md)** - Running Claude Code on a schedule via Task Scheduler

### Subdirectories

- **[mcp/](mcp/)** - MCP server documentation (LabKey, Gmail, status tools)
- **[labkey/](labkey/)** - LabKey module documentation
- **[labkey-setup/](labkey-setup/)** - LabKey Server setup guides and scripts
- **[archive/](archive/)** - Archived older documentation versions

## Core vs Detailed Documentation

### Core Files ([ai/](../))
- **Size**: <200 lines each
- **Purpose**: Essential rules and quick reference
- **Load**: Every session
- **Content**: Constraints, common patterns, key workflows

### Detailed Docs ([ai/docs/](.))
- **Size**: Unlimited
- **Purpose**: Comprehensive examples and deep dives
- **Load**: On-demand, when needed
- **Content**: Full examples, edge cases, historical context

## Quick Navigation

**Need to know:**
- **What's critical?** → [../CRITICAL-RULES.md](../CRITICAL-RULES.md)
- **Project basics?** → [../MEMORY.md](../MEMORY.md)
- **Git workflows?** → [../WORKFLOW.md](../WORKFLOW.md)
- **Style rules?** → [../STYLEGUIDE.md](../STYLEGUIDE.md)
- **Testing basics?** → [../TESTING.md](../TESTING.md)

## Growth Strategy

When adding new information:
1. **Critical constraint?** → Add to [CRITICAL-RULES.md](../CRITICAL-RULES.md) (bare rule only)
2. **Common pattern?** → Add to core file (MEMORY, STYLEGUIDE, etc.) with pointer to details
3. **Detailed example?** → Add to corresponding detailed doc in this directory
4. **New category?** → Create new detailed doc, add to this index

**Goal**: Keep core files small, grow detailed docs as needed.
