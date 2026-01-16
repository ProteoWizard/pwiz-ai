---
description: Prepare handoff summary
---
# End-of-Session Handoff

Prepare a complete handoff for the next session to continue this work.

## Steps

1. **Update the TODO file** with current progress (mark completed items, add notes)

2. **Write handoff file** to `ai/.tmp/handoff-{descriptor}.md` where descriptor is either:
   - The branch name suffix (e.g., `handoff-20260116_peak_picking_tutorial_hang.md`)
   - Or the date if working on master (e.g., `handoff-20260116.md`)

3. **Display a brief summary** to the user

## Handoff File Template

```markdown
# Handoff: {Brief Title}

**Date**: YYYY-MM-DD
**Branch**: `branch-name`
**Issue**: [#NNN](url) (if applicable)
**TODO**: `ai/todos/active/TODO-*.md`

## Summary
One paragraph describing what this work is about.

## Work Completed
- Bullet list of completed items

## Files Modified (Uncommitted)
| File | Change |
|------|--------|
| path/to/file.cs | Brief description |

## Next Steps
1. Numbered steps to continue

## Context for Continuation
Key decisions, gotchas, or context the next session needs.
```
