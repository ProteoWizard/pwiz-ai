# Claude Code Usage Guide

**For LLM Assistants**: How to use this refactored setup workflow efficiently.

## Token Savings Summary

**Old workflow**: ~51KB markdown (~12,000 tokens) loaded multiple times
**New workflow**: ~3KB per phase (~700 tokens) loaded once per phase

**Estimated savings**: 60-70% reduction in token usage over full setup

## Workflow Overview

```
1. User: "Help me setup LabKey development environment"
2. Claude: Read README.md (150 lines)
3. Claude: Create state.json from template
4. Claude: Read phase-0-getting-started.md (50 lines)
5. Claude: Execute phase 0 steps
6. Claude: Update state.json
7. Claude: Read next phase file
8. ... repeat for each phase
9. Claude: Generate final report from template
```

## Initial Setup Command

When user starts setup:

```bash
# 1. Read main README
view labkey-setup/README.md

# 2. Copy state template
cp labkey-setup/state-template.json labkey-setup/state.json

# 3. Read first phase
view labkey-setup/phases/phase-0-getting-started.md
```

## Phase Execution Pattern

For each phase:

```bash
# 1. Read phase file
view labkey-setup/phases/phase-N-name.md

# 2. Execute steps (run commands, ask questions, verify)

# 3. Update state.json
# Edit with completed steps, update current_phase and current_step

# 4. Show progress tracker
# Use emoji indicators: ✅ Done, 🔄 Current, ⬜ Pending

# 5. Move to next phase
view labkey-setup/phases/phase-N+1-name.md
```

## State Management

**After each step** within a phase:
```json
{
  "completed": ["phase-0", "phase-1-step-1.1", "phase-1-step-1.2"],
  "current_phase": 1,
  "current_step": "1.3"
}
```

**After completing a phase**:
```json
{
  "completed": ["phase-0", "phase-1"],
  "current_phase": 2,
  "current_step": "2.1"
}
```

## Terminal Restart Pattern

**Before restart** (e.g., after PowerShell 7 install):

1. Output resume checkpoint:
```
## Resume Checkpoint
**Current:** Phase 1, Step 1.1 (PowerShell 7)
**Next:** Phase 1, Step 1.2 (Java)
**Remaining:** Core Setup steps 1.2-1.4, Phases 2-10
```

2. Update state.json with current position

3. Tell user to run: `claude --resume`

**After resume**:

1. Read state.json (NOT README.md)
2. Announce: "Resuming from Phase X, Step X.X"
3. Read current phase file
4. Continue from current step

## Loading Reference Docs

Only load reference docs when needed:

**Gradle commands reference**:
```bash
# When user asks about Gradle commands
view labkey-setup/reference/gradle-commands.md
```

**Troubleshooting**:
```bash
# When build fails or issues occur
view labkey-setup/reference/troubleshooting.md
```

**Modules reference**:
```bash
# When user asks about modules
view labkey-setup/reference/modules.md
```

## Final Report Generation

After Phase 9:

```bash
# 1. Read template
view labkey-setup/reference/final-report-template.md

# 2. Read state.json for all data

# 3. Generate report with actual values

# 4. Save report
create_file labkey-setup-report-{date}.md

# 5. Show summary to user
```

## Token Usage Comparison

### Old Workflow
```
Initial read: 12,000 tokens (full doc)
Resume #1: 12,000 tokens (re-read doc)
Resume #2: 12,000 tokens (re-read doc)
Total: 36,000 tokens for 3 reads
```

### New Workflow
```
Initial read: 700 tokens (README)
Phase 0: 600 tokens
Phase 1: 700 tokens
Phase 2: 400 tokens
... (remaining phases)
Total: ~6,000 tokens for complete setup
```

**Savings**: 30,000 tokens (83% reduction)

## Best Practices

1. **Only load what you need**: Don't preload all phases
2. **Trust state.json**: It's the source of truth for progress
3. **Update state frequently**: After each step completion
4. **Use reference docs selectively**: Load only when relevant
5. **Keep conversations focused**: Each phase is self-contained

## Handling Edge Cases

**User skips phases**: Update state.json with deferred items
```json
{
  "deferred": ["phase-8-tests", "phase-9-tortoisegit"]
}
```

**User wants to revisit phase**: 
- Update current_phase in state.json
- Read that phase file
- Execute as normal

**Setup fails mid-phase**:
- Note the issue in state.json notes
- Reference troubleshooting.md
- Update state with where you stopped

## Progress Tracker Format

Show after each phase completion:

```
## Progress
✅ Getting Started
✅ Phase 1: Core Setup
✅ Phase 2: PostgreSQL
🔄 Phase 3: Repository Setup ← currently here
⬜ Phase 4: Gradle Configuration
⬜ Phase 5: Initial Build
⬜ Phase 6: IntelliJ Setup
⬜ Phase 7: Running Server
⬜ Phase 8: Test Setup
⬜ Phase 9: Developer Tools
```

## Summary

The key to token efficiency:
- Load incrementally (one phase at a time)
- Use state file for persistence (not full doc re-reads)
- Load reference docs only when needed
- Trust the modular structure
