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

3. **Add a handoff pointer to the TODO file** so that `/pw-continue` in
   the next session naturally discovers the handoff. Append a line like:

   ```
   **Next session handoff**: For detailed startup protocol, read
   `ai/.tmp/handoff-{descriptor}.md` before starting work.
   ```

   to the end of the most recent progress log entry in the TODO. This
   closes the loop: `/pw-continue` reads the TODO, finds the pointer,
   and the new session loads the handoff with full startup instructions.

4. **Commit and push** the TODO update (ai repo) so the pointer is durable.

5. **Display a brief summary** to the user

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
