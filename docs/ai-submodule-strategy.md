# AI Submodule Strategy

Strategy for managing all AI tooling as a Git submodule, replacing the ai-context branch workflow.

**Status**: Implemented (opt-in)

**Key Design Decision**: The ai/ submodule is **opt-in** via the `--ai` build flag. This:
- Eliminates transition pain for developers not using AI tooling
- Keeps TeamCity builds simple (no AI tooling needed for CI)
- Allows gradual adoption at each developer's pace

---

## Overview

All AI tooling lives in a separate repository (`ProteoWizard/pwiz-ai`) included in pwiz as a Git submodule at `ai/`. This provides:

- **Normal git workflow** - Standard pull/push, no rebase complexity
- **Single source of truth** - All pwiz clones share the same AI content
- **Unified location** - All AI tooling in one place
- **Clear pattern** - Future projects add `ai/scripts/NewProject/`

### What's Where

| Component | Location | Notes |
|-----------|----------|-------|
| `ai/` folder | `pwiz-ai` repo (submodule) | Everything: docs, scripts, commands, MCP |
| `.claude/` folder | Windows junction | Points to `ai/claude/` |

### Unified Structure

```
ai/                              <- Single submodule (pwiz-ai repo)
+-- claude/                      <- Commands/skills (was .claude/)
|   +-- commands/
|   +-- skills/
+-- scripts/                     <- All project build scripts
|   +-- Skyline/
|   |   +-- Build-Skyline.ps1
|   |   +-- Run-Tests.ps1
|   |   +-- helpers/
|   +-- AutoQC/
|   |   +-- Build-AutoQC.ps1
|   +-- SkylineBatch/
|       +-- Build-SkylineBatch.ps1
+-- docs/                        <- All documentation
+-- mcp/                         <- MCP server
+-- todos/                       <- Work tracking
+-- CLAUDE.md, MEMORY.md, etc.
```

**In pwiz repo (after conversion):**
```
.claude/  ->  Windows junction to ai/claude/
ai/       ->  Submodule mount point
```

---

## Benefits

| Benefit | Description |
|---------|-------------|
| **Single source** | "Where's AI stuff?" -> `ai/` |
| **Single sync** | One submodule update gets everything |
| **Clear pattern** | New project? Add `ai/scripts/NewProject/` |
| **Findability** | All build scripts in one tree |
| **Normal workflow** | Standard push/pull, no force-push or rebase |

---

## Daily Workflow

### Updating AI Content

```bash
# Enter the submodule
cd ai

# Make sure you're on main and up to date
git checkout main
git pull origin main

# Make changes
# ... edit files ...

# Commit and push
git add .
git commit -m "Update documentation for X"
git push origin main

# Return to pwiz root
cd ..
```

### Updating Your Clone's ai/ Submodule

```bash
# From pwiz root - get latest ai/ content
git submodule update --remote ai
```

**In TortoiseGit:**
1. Right-click the `ai/` folder -> Submodule Update
2. Check "Remote tracking branch" to get latest

---

## Windows Junction for .claude/

Claude Code requires `.claude/` at repo root. Solution: Windows junction (directory link) pointing to `ai/claude/`.

### Opt-In via `--ai` Build Flag

The ai/ submodule and .claude/ junction are **only** initialized when you pass `--ai` to the build. In `pwiz_tools/Skyline/Jamfile.jam`:

```jam
if ! --incremental in [ modules.peek : ARGV ]
{
   echo "Updating submodules for Hardklor etc..." ;
   SHELL "git submodule update --init --recursive" ;

   # AI tooling is opt-in
   if "--ai" in [ modules.peek : ARGV ]
   {
      echo "Initializing AI tooling (--ai flag detected)..." ;
      SHELL "git submodule update --init ai" ;

      # Create .claude junction if it doesn't exist
      if ! [ path.exists $(PWIZ_ROOT_PATH)/.claude ]
      {
         echo "Creating .claude junction to ai/claude..." ;
         SHELL "mklink /J \"$(PWIZ_ROOT_PATH)/.claude\" \"$(PWIZ_ROOT_PATH)/ai/claude\"" ;
      }
   }
}
```

**Benefits of opt-in:**
- TeamCity doesn't need AI tooling (no `--ai` flag)
- Developers can adopt at their own pace
- No transition pain for those not using Claude Code
- Branch switching is clean (no ai/ folder collision)

### Junction Properties

- Works without admin rights
- Appears as normal folder to all tools
- Git sees it as a junction (not tracked)
- Created automatically by first build

---

## New Machine Setup

When cloning pwiz fresh:

```bash
git clone git@github.com:ProteoWizard/pwiz.git
cd pwiz
bs.bat   # Standard build (no AI tooling)
```

**To enable AI tooling**, add `--ai` to your `b.bat`:

```batch
@call "%~dp0pwiz_tools\build-apps.bat" 64 --i-agree-to-the-vendor-licenses toolset=msvc-14.3 --ai %*
```

Then run `bs.bat` and the build will:
1. Initialize the ai/ submodule (`git submodule update --init ai`)
2. Create the `.claude` junction pointing to `ai/claude/`

**For developers not using AI tooling**: No changes needed. The build works without `--ai`.

---

## Working with Multiple Clones

All your pwiz clones share the same ai/ content:

```
C:\proj\
  pwiz\ai\          -> pwiz-ai repo
  scratch\ai\       -> pwiz-ai repo (same!)
  review\ai\        -> pwiz-ai repo (same!)
  skyline_26_1\ai\  -> pwiz-ai repo (same!)
```

Update ai/ in any clone, and it's available everywhere (after `git pull` in each ai/ submodule).

---

## Working with Historical Branches

**For older release branches that predate the submodule** (e.g., skyline_25_1):

Don't retrofit them. Instead, work from a modern checkout:

```
C:\proj\scratch\          <- Work here (has full ai/ + .claude/ context)
  +-- Claude Code can read/write files in:
      C:\proj\skyline_25_1\   <- Older branch without ai/
```

**Pattern:** "Work from context-rich, modify anywhere"

- Claude Code has full context from the modern checkout
- Can read/write files in any directory on the system
- The LLM understands modern conventions and applies them to older code

---

## Existing Submodules in pwiz

The project already uses 4 submodules - this is an **established pattern**:

| Submodule | Path |
|-----------|------|
| BullseyeSharp | `pwiz_tools/Skyline/Executables/BullseyeSharp` |
| DocumentConverter | `pwiz_tools/Skyline/Executables/DevTools/DocumentConverter` |
| Hardklor | `pwiz_tools/Skyline/Executables/Hardklor/Hardklor` |
| MSToolkit | `pwiz_tools/Skyline/Executables/Hardklor/MSToolkit` |

**Implications:**
- CI/build already handles submodules
- Team has submodule experience
- Adding `ai/` follows existing pattern
- Difference: `ai/` won't be pinned (docs apply broadly), others are pinned (reproducible builds)

---

## Comparison: Before and After

### Before (ai-context branch)

```bash
# Update documentation
git checkout ai-context
git commit
git push --force-with-lease  # Force push required!

# Weekly sync
/pw-aicontextsync  # Complex rebase + squash

# Other machines after sync
git fetch origin ai-context
git reset --hard origin/ai-context  # Can't use pull!
```

### After (submodule)

```bash
# Update documentation
cd ai
git commit
git push  # Normal push!

# Other machines
cd ai
git pull  # Normal pull works!
```

---

## Transition Plan

### Phase 1: Create pwiz-ai Repository (DONE)

1. Created `ProteoWizard/pwiz-ai` repo on GitHub
2. Content structured as:
   ```
   docs/             <- Documentation
   mcp/              <- MCP servers
   scripts/          <- Utility scripts
   todos/            <- Work tracking
   claude/           <- Commands/skills (for .claude/ junction)
   *.md              <- Root docs (CLAUDE.md, MEMORY.md, etc.)
   ```

### Phase 2: Convert pwiz to Use Submodule (Opt-In)

1. Remove all ai-related folders from pwiz:
   ```bash
   git rm -r ai/
   git rm -r .claude/
   git rm -r pwiz_tools/Skyline/ai/
   git rm -r pwiz_tools/Skyline/Executables/AutoQC/ai/
   git rm -r pwiz_tools/Skyline/Executables/SkylineBatch/ai/
   ```
2. Add submodule (with `update = none` for opt-in):
   ```bash
   git submodule add https://github.com/ProteoWizard/pwiz-ai.git ai
   git config -f .gitmodules submodule.ai.update none
   ```
3. Add `.claude` to `.gitignore` (junction shouldn't be tracked)
4. Update `pwiz_tools/Skyline/Jamfile.jam` to handle `--ai` flag
5. Apply to master and skyline_26_1

### Phase 3: Retire ai-context Branch

- Delete remote branch: `git push origin --delete ai-context`
- Remove `/pw-aicontextsync`, `/pw-aicontextupdate` commands
- Archive `ai-context-branch-strategy.md`

### Transition Experience by Developer Type

| Developer | Experience |
|-----------|------------|
| **Not using AI tooling** | Merge from master removes ai/ folders. Done. No friction. |
| **Wants AI tooling** | Add `--ai` to b.bat, run build. Submodule + junction created. |
| **TeamCity** | No changes. Builds work without `--ai`. |
| **Existing PR authors** | Merge from master removes ai/ folders cleanly. |

---

## Critical Files to Update

| File | Change Needed |
|------|---------------|
| `pwiz_tools/Skyline/Jamfile.jam` | Add `--ai` flag handling for submodule init + junction |
| `.gitmodules` | Add ai submodule with `update = none` |
| `.gitignore` | Add `.claude` (junction shouldn't be tracked) |
| `new-machine-setup.md` | Add `--ai` to b.bat instructions for AI adopters |

---

## Rollback Plan

If issues arise, revert to regular directory:

```bash
git submodule deinit ai
git rm ai
rm -rf .git/modules/ai
rmdir .claude  # Remove junction
# Restore from pwiz-ai repo content
git add ai/ .claude/
git commit -m "Restore ai/ as regular directory"
```

---

## Troubleshooting

### "ai/ folder is empty"

Submodule not initialized. Run the build (`bs.bat`) or manually:
```bash
git submodule update --init
```

### ".claude/ folder missing after clone"

Run the build (`bs.bat`) which creates the junction, or manually:
```cmd
mklink /J .claude ai\claude
```

### "Detached HEAD in ai/"

Normal for submodules. To make changes:
```bash
cd ai
git checkout main
# Now you can commit
```

### "Changes in ai/ not showing in pwiz status"

Submodule changes are tracked separately:
```bash
cd ai
git status
```

---

## Design Decisions

### Why Unified (All AI Content Together)

- **Single location**: "Where's AI stuff?" -> `ai/`
- **Single sync**: One update gets everything
- **Clear pattern**: Future projects add `ai/scripts/NewProject/`
- **Build scripts self-navigate**: Location is organizational, not functional

### Why Not Pin Versions

- Documentation applies broadly across Skyline versions
- Each clone can update ai/ independently
- Reduces coordination overhead

### Why Junction for .claude/

- Claude Code requires `.claude/` at repo root
- Junction is transparent to all tools
- No admin rights required
- Created automatically by Boost Build

---

## Historical Note

Prior to this submodule approach, ai/ was managed via the ai-context branch with a rebase-based workflow. That approach required:
- Force-push after every change
- Weekly sync with squash and rebase
- "Never pull, always reset" rule for all machines

The submodule approach eliminates this complexity. See archived `ai-context-branch-strategy.md` for the previous workflow.

---

## References

- [Git Submodules Documentation](https://git-scm.com/book/en/v2/Git-Tools-Submodules)
- [documentation-maintenance.md](documentation-maintenance.md) - "Reference, don't embed" principle
- GitHub Issue #3786 - Original submodule proposal discussion
