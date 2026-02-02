# AI Repository Strategy

Strategy for managing all AI tooling in a dedicated repository (`ProteoWizard/pwiz-ai`), providing LLM context and tooling for Skyline development.

**Status**: Implemented

---

## Overview

All AI tooling lives in a separate repository (`ProteoWizard/pwiz-ai`) that can be used in two modes:

| Mode | Setup | Best For |
|------|-------|----------|
| **Sibling Mode** | Clone `pwiz-ai` as `ai/` alongside `pwiz/` | Multi-project work, new developers, simpler setup |
| **Child Mode** | Clone `pwiz-ai` as `ai/` inside `pwiz/` | Single-project focus, simpler path structure |

**Sibling mode is recommended for most developers.** It provides a simpler mental model and allows Claude Code to assist across multiple project checkouts without context loss.

---

## Sibling Mode (Recommended)

In sibling mode, `pwiz-ai` is cloned as a standalone repository alongside your pwiz checkouts:

```
<your project root>\        <- Claude Code runs from here (e.g., C:\Dev, D:\proj)
├── .claude/                <- Junction to ai/claude/
├── ai/                     <- pwiz-ai repo (standalone clone)
├── pwiz/                   <- Main development checkout
├── skyline_26_1/           <- Release branch checkout
└── scratch/                <- Experimental work
```

### Benefits

- **Cross-project assistance** - Claude Code sees all checkouts, can help across branches
- **No context loss** - Stay in your project root throughout your session
- **Simpler setup** - Just `git clone`, no nested repos
- **Natural workflow** - "Work from context-rich parent, modify anywhere"

### Setup

```bash
# Create project directory (use your preferred location)
mkdir C:\Dev
cd C:\Dev

# Clone the AI repository
git clone https://github.com/ProteoWizard/pwiz-ai.git ai

# Create .claude junction (enables Claude Code commands/skills)
mklink /J .claude ai\claude

# Clone pwiz
git clone git@github.com:ProteoWizard/pwiz.git

# Start Claude Code from the project root
claude
```

### Daily Workflow

```bash
# From your project root - update AI content
cd ai
git pull origin main
cd ..

# Work on any project - Claude Code sees everything
# Edit pwiz\..., skyline_26_1\..., etc.
```

### Working with Multiple Checkouts

All checkouts share the same `ai/` context:

```
<your project root>\
├── ai/              <- Single source of AI tooling
├── pwiz/            <- Main work
├── skyline_26_1/    <- Release branch
└── scratch/         <- Experiments
```

Claude Code running from your project root can read/write files in any checkout. This enables:
- Comparing implementations across branches
- Applying fixes to multiple checkouts
- Understanding how code evolved between releases

---

## Child Mode

In child mode, `pwiz-ai` is cloned inside a pwiz checkout:

```
<your pwiz checkout>\       <- Claude Code runs from here
├── .claude/                <- Junction to ai/claude/
├── ai/                     <- pwiz-ai repo (nested clone)
└── pwiz_tools/...
```

### When to Use Child Mode

- **Single-project focus** - Working exclusively in one checkout
- **Simpler paths** - Everything under one root directory
- **Isolated environments** - Each checkout has independent AI tooling

### Setup

```bash
cd <your pwiz checkout>

# Clone AI repo inside pwiz
git clone https://github.com/ProteoWizard/pwiz-ai.git ai

# Create .claude junction
mklink /J .claude ai\claude

# Start Claude Code from the pwiz directory
claude
```

### Child Mode Workflow

```bash
# Enter the ai repository
cd ai

# Make sure you're on main and up to date
git checkout main
git pull origin main

# Make changes, commit, push
git add .
git commit -m "Update documentation"
git push origin main

# Return to pwiz root
cd ..
```

### Note on .gitignore

The pwiz repository's `.gitignore` includes `ai/` and `.claude/`, so the nested clone won't appear as untracked files.

---

## The .claude Junction

Both modes use a Windows junction to expose `ai/claude/` as `.claude/` at the appropriate root:

| Mode | Junction Location | Points To |
|------|------------------|-----------|
| Sibling | `<project root>\.claude` | `<project root>\ai\claude` |
| Child | `<pwiz checkout>\.claude` | `<pwiz checkout>\ai\claude` |

Claude Code requires `.claude/` at the working directory root. The junction:
- Works without admin rights
- Appears as a normal folder to all tools
- Is listed in `.gitignore` (not tracked)

---

## Repository Structure

The `pwiz-ai` repository contains:

```
ai/
├── claude/                 <- Commands/skills (exposed via .claude junction)
│   ├── commands/
│   └── skills/
├── scripts/                <- Build and utility scripts
│   ├── Skyline/
│   │   ├── Build-Skyline.ps1
│   │   ├── Run-Tests.ps1
│   │   └── helpers/
│   ├── AutoQC/
│   └── SkylineBatch/
├── docs/                   <- All documentation
├── mcp/                    <- MCP servers
├── todos/                  <- Work tracking
├── CLAUDE.md               <- Critical configuration
├── CRITICAL-RULES.md       <- Absolute constraints
├── MEMORY.md               <- Project context
└── TOC.md                  <- Documentation index
```

---

## Choosing a Mode

| Consideration | Sibling Mode | Child Mode |
|---------------|--------------|------------|
| Setup complexity | Simple (clone alongside) | Simple (clone inside) |
| Cross-project work | Excellent | Limited to one checkout |
| Context switching | No restart needed | Restart Claude for each checkout |
| New developers | Recommended | After gaining experience |
| Path structure | Separate ai/ and pwiz/ | All under pwiz/ |

**Start with sibling mode.** Move to child mode if you prefer having everything under a single root directory.

---

## Transitioning Between Modes

### Sibling to Child

If you later want child mode for a specific checkout:

```bash
cd <your pwiz checkout>

# Clone AI repo inside pwiz
git clone https://github.com/ProteoWizard/pwiz-ai.git ai

# Create .claude junction
mklink /J .claude ai\claude
```

### Child to Sibling

To convert a child-mode checkout to use sibling mode:

```bash
cd <your pwiz checkout>

# Remove the nested ai/ clone and junction
rmdir /s ai
rmdir .claude

# Now use the parent's ai/ via sibling mode from your project root
```

---

## Historical Note

Prior to this repository approach, AI tooling was managed via the `ai-context` branch with a rebase-based workflow requiring:
- Force-push after every change
- Weekly sync with squash and rebase
- "Never pull, always reset" rule

The dedicated repository approach eliminates this complexity entirely.

---

## References

- [new-machine-setup.md](new-machine-setup.md) - Developer onboarding guide
- GitHub Issue #3786 - Original repository proposal discussion
