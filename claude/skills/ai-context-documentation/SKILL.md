---
name: ai-context-documentation
description: Use this skill when editing files in ai/ or .claude/ folders.
---

# AI Context Documentation

When working on ai/ documentation, TODOs, or .claude/ configuration, consult these resources.

## Core Documentation Files

1. **ai/MEMORY.md** - Project context, gotchas, patterns
2. **ai/WORKFLOW.md** - Git workflows, TODO system, commit messages
3. **ai/CRITICAL-RULES.md** - Absolute constraints
4. **ai/STYLEGUIDE.md** - C# coding conventions
5. **ai/TESTING.md** - Testing patterns and rules

## Repository Structure

The `ai/` directory is the **pwiz-ai** repository (separate from pwiz). Changes to anything under `ai/` are committed and pushed directly to pwiz-ai master - no feature branches needed.

Read **ai/docs/ai-repository-strategy.md** for:
- Sibling vs child clone modes
- Setup instructions
- Rationale for the separate repository

## Creating New Documentation

### New Skill
```
.claude/skills/{skill-name}/SKILL.md
```

Required frontmatter:
```yaml
---
name: skill-name
description: When to activate this skill (one sentence)
---
```

### New Slash Command
```
.claude/commands/pw-{command-name}.md
```

Required frontmatter:
```yaml
---
description: Brief description of what the command does
---
```

### New Guide Document
```
ai/docs/{topic-name}.md
```

- Use descriptive kebab-case names
- Include cross-references to related docs
- Update relevant skills to reference new docs

## Documentation Locations

| Type | Location | Repository |
|------|----------|------------|
| Skills | `.claude/skills/` | pwiz-ai (ai/) |
| Commands | `.claude/commands/` | pwiz-ai (ai/) |
| Guides | `ai/docs/` | pwiz-ai (ai/) |
| TODOs (active) | `ai/todos/active/` | pwiz-ai (ai/) |
| TODOs (completed) | `ai/todos/completed/` | pwiz-ai (ai/) |

## Key Principle

All documentation in `ai/` belongs to the **pwiz-ai** repository. Commit and push directly to master - no feature branches needed for documentation work.
