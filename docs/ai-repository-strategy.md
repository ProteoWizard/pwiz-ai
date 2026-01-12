# AI Repository Strategy

Strategy for managing all AI tooling in a dedicated repository (`ProteoWizard/pwiz-ai`), providing LLM context and tooling for Skyline development.

**Status**: Implemented

---

## Overview

All AI tooling lives in a separate repository (`ProteoWizard/pwiz-ai`) that can be used in two modes:

| Mode | Setup | Best For |
|------|-------|----------|
| **Sibling Mode** | Clone `pwiz-ai` as `ai/` alongside `pwiz/` | Multi-project work, new developers, simpler setup |
| **Submodule Mode** | `ai/` embedded inside `pwiz/` via submodule | Single-project focus, CI integration |

**Sibling mode is recommended for most developers.** It provides a simpler mental model and allows Claude Code to assist across multiple project checkouts without context loss.

---

## Sibling Mode (Recommended)

In sibling mode, `pwiz-ai` is cloned as a standalone repository alongside your pwiz checkouts:

```
C:\proj\                    <- Claude Code runs from here
├── .claude/                <- Junction to ai/claude/
├── ai/                     <- pwiz-ai repo (standalone clone)
├── pwiz/                   <- Main development checkout
├── skyline_26_1/           <- Release branch checkout
└── scratch/                <- Experimental work
```

### Benefits

- **Cross-project assistance** - Claude Code sees all checkouts, can help across branches
- **No context loss** - Stay in `C:\proj` throughout your session
- **Simpler setup** - No submodule complexity, just `git clone`
- **Natural workflow** - "Work from context-rich parent, modify anywhere"

### Setup

```bash
# Create project directory
mkdir C:\proj
cd C:\proj

# Clone the AI repository
git clone https://github.com/ProteoWizard/pwiz-ai.git ai

# Create .claude junction (enables Claude Code commands/skills)
mklink /J .claude ai\claude

# Clone pwiz
git clone git@github.com:ProteoWizard/pwiz.git

# Start Claude Code from the parent directory
claude
```

### Daily Workflow

```bash
# From C:\proj - update AI content
cd ai
git pull origin main
cd ..

# Work on any project - Claude Code sees everything
# Edit C:\proj\pwiz\..., C:\proj\skyline_26_1\..., etc.
```

### Working with Multiple Checkouts

All checkouts share the same `ai/` context:

```
C:\proj\
├── ai/              <- Single source of AI tooling
├── pwiz/            <- Main work
├── skyline_26_1/    <- Release branch
└── scratch/         <- Experiments
```

Claude Code running from `C:\proj` can read/write files in any checkout. This enables:
- Comparing implementations across branches
- Applying fixes to multiple checkouts
- Understanding how code evolved between releases

---

## Submodule Mode (Advanced)

In submodule mode, `pwiz-ai` is embedded inside a pwiz checkout as a Git submodule:

```
C:\proj\pwiz\               <- Claude Code runs from here
├── .claude/                <- Junction to ai/claude/
├── ai/                     <- pwiz-ai repo (submodule)
└── pwiz_tools/...
```

### When to Use Submodule Mode

- **CI/TeamCity** - Reproducible builds with pinned AI tooling version
- **Single-project focus** - Working exclusively in one checkout
- **Isolated environments** - Each checkout has independent AI tooling

### Setup via Build Flag

Submodule mode is opt-in via the `--ai` build flag:

**b.bat** (with AI tooling):
```batch
@call "%~dp0pwiz_tools\build-apps.bat" 64 --i-agree-to-the-vendor-licenses toolset=msvc-14.3 --ai %*
```

Running `bs.bat` will:
1. Initialize the ai/ submodule (`git submodule update --init ai`)
2. Create the `.claude` junction pointing to `ai/claude/`

### Submodule Workflow

```bash
# Enter the submodule
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

### Implementation Details

The `--ai` flag handling in `pwiz_tools/Skyline/Jamfile.jam`:

```jam
if "--ai" in [ modules.peek : ARGV ]
{
   echo "Initializing AI tooling (--ai flag detected)..." ;
   SHELL "git submodule update --init ai" ;

   if ! [ path.exists $(PWIZ_ROOT_PATH)/.claude ]
   {
      echo "Creating .claude junction to ai/claude..." ;
      SHELL "mklink /J \"$(PWIZ_ROOT_PATH)/.claude\" \"$(PWIZ_ROOT_PATH)/ai/claude\"" ;
   }
}
```

---

## The .claude Junction

Both modes use a Windows junction to expose `ai/claude/` as `.claude/` at the appropriate root:

| Mode | Junction Location | Points To |
|------|------------------|-----------|
| Sibling | `C:\proj\.claude` | `C:\proj\ai\claude` |
| Submodule | `C:\proj\pwiz\.claude` | `C:\proj\pwiz\ai\claude` |

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

| Consideration | Sibling Mode | Submodule Mode |
|---------------|--------------|----------------|
| Setup complexity | Simple (just clone) | Moderate (build flag + junction) |
| Cross-project work | Excellent | Limited to one checkout |
| Context switching | No restart needed | Restart Claude for each checkout |
| New developers | Recommended | After gaining experience |
| CI/automated builds | Not applicable | Use without `--ai` flag |

**Start with sibling mode.** Move to submodule mode if you have a specific need for isolated AI tooling per checkout.

---

## Transitioning Between Modes

### Sibling to Submodule

If you later want submodule mode for a specific checkout:

1. Add `--ai` to that checkout's `b.bat`
2. Run the build to initialize the submodule
3. The checkout now has its own `ai/` and `.claude/`

### Submodule to Sibling

To convert a submodule-mode checkout to use sibling mode:

```bash
# Remove the submodule
git submodule deinit ai
git rm ai
rm -rf .git/modules/ai
rmdir .claude

# Now use the parent's ai/ via sibling mode
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

- [Git Submodules Documentation](https://git-scm.com/book/en/v2/Git-Tools-Submodules)
- [new-machine-setup.md](new-machine-setup.md) - Developer onboarding guide
- GitHub Issue #3786 - Original repository proposal discussion
